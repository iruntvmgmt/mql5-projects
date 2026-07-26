# Known Issues and Production Blockers

## Build verification

The previously validated MSZZ files compiled with 0 errors on MetaEditor builds 6033/6061; the EA carried one reviewed Market-version warning. The new ownership batch added after commit `31f13b0` is **compile-pending and runtime-pending** until pulled and validated locally.

## Fixed and verified in prior passes

- Illegal local reference in `OpportunityClusterEngine.mqh`.
- Unsafe `ZeroMemory()` use on string-containing structs and the follow-on uninitialized-field defect.
- Malformed cluster IDs, replaced by D004 `MSZZC1` length-prefixed encoding.

## Fixed and verified 2026-07-25 (second pass)

### Account-mode and position ownership — D005 — RESOLVED

Added:

- `Execution/PositionOwnership.mqh`
- `Execution/PositionOwnershipPolicy.mqh`
- `Test_MSZZ_Ownership.mq5`
- EA version `0.310` ownership integration

The implementation detects netting, hedging, exchange, and unsupported account modes; inventories symbol positions by ticket; classifies owned/manual/foreign positions by magic number; closes only owned opposite tickets; fails closed on selection ambiguity; blocks foreign/manual symbol exposure in netting or exchange mode; and applies the one-position limit only to owned MSZZ positions in hedging mode.

This supersedes the old "netting-account assumption" blocker previously listed here. All resolution criteria are met:

- the unsafe symbol-wide `PositionSelect(_Symbol)`/`CTrade::PositionClose(_Symbol)` path is gone (confirmed by repo-wide grep, zero matches);
- account mode is detected and logged (`AccountInfoInteger(ACCOUNT_MARGIN_MODE)`, verified to correctly resolve to `HEDGING` on the isolated demo account, matching the terminal's own connection log);
- ownership inventory works (read-only diagnostic: valid snapshot, zero false positives on empty position state);
- hedging policy passes (deterministic test: coexistence allowed when unowned, blocked at the owned-position limit, foreign/manual never counted as owned);
- netting/exchange policies pass deterministic tests (foreign/manual exposure blocks execution in both modes; no real netting/exchange broker account was available, so this is unit-test coverage only, documented as such — not real broker runtime coverage);
- EA compile (0 errors, 1 pre-existing reviewed warning) and shadow regression (zero orders/deals/trades, short and long windows) both pass.

**Narrower remaining issues** (replacing the old blocker):

- **Close-by-ticket execution against a real open position has not been demo-tested.** No positions were created during this pass (per instruction — shadow-only, zero orders). The `CTrade::PositionClose(ticket)` call path compiles and is exercised by zero live tickets; it has not been proven against an actual broker position.
- **`owned_longs`/`owned_shorts`/volume-total counting and same-symbol-vs-different-symbol exclusion** are implemented in `CMSZZPositionOwnership::Refresh()` (every field of `MSZZPositionRecord` is set explicitly — confirmed by source review, no uninitialized-field risk) but have only been exercised against a zero-position inventory; they are unverified against actual mixed-symbol or multi-position live state.
- **Order/deal history reconciliation is absent.** The ownership subsystem inventories only currently-open positions at startup; it does not reconstruct historical orders or deals.
- **Post-order persistence failure remains** (see below, unchanged by this batch).
- **Full position-management restart reconstruction remains absent** (see below, unchanged by this batch).

## Implemented and verified 2026-07-26 (fifth entry) — Execution state machine, first increment (D010)

`IntentStateMachine.mqh` closes the gap D009 explicitly left open: reconciliation verdicts now actually complete the intent lifecycle instead of leaving matched intents permanently stuck at `BROKER_ACCEPTED`. `CMSZZIntentStateMachine` (pure, static) holds one auditable from→{legal-to-set} table for all 14 `ENUM_MSZZ_INTENT_STATE` values and a `TryTransition()` gate that every `execution_state` write in the EA now goes through. `MATCHED_ACTIVE_POSITION`/`MATCHED_CLOSED_POSITION`/`CONSISTENT_REJECTION` reconciliation verdicts now transition intents to `POSITION_ACTIVE`/`POSITION_CLOSED`/`ABANDONED` respectively — none of these three transitions existed anywhere in the codebase before this decision.

Verified: EA and new files compile clean (0 errors; EA carries the one pre-existing unrelated warning). 25/25 deterministic transition-legality assertions pass, `failures=0`, including that a rejected transition leaves the intent struct completely unchanged (not partially mutated) and that both terminal states (`POSITION_CLOSED`, `ABANDONED`) have zero legal outgoing transitions. Shadow regression (short + long windows) shows identical 431/178/178 counts and zero orders/deals/trades. Full regression (ownership, determinism, clusters, intent-store, reconciler, state-machine) all re-ran clean.

**New known limitation introduced by this decision**: none of the new `POSITION_ACTIVE`/`POSITION_CLOSED`/`ABANDONED` transitions have ever fired in a real run — they have only been exercised by the deterministic unit test and by the shadow regression's empty-intent-store no-op path. No live order has been placed on this branch, so this remains unverified against real broker state, same caveat as every decision in this series so far.

**Still not done**: the EA does not emit the finer-grained `PREFLIGHT_PASSED`/`SUBMISSION_STARTED`/`RESULT_UNKNOWN`/`PARTIALLY_FILLED`/`FILLED` states — `ExecuteCluster()` still goes directly from `PERSISTED` to `BROKER_ACCEPTED`/`BROKER_REJECTED` in one step, exactly as before this decision. Those states are defined in the legality table for forward-compatibility but nothing causes the EA to emit them. `PROTECTION_FAILED` is defined and included in the table but wired nowhere (Phase 4's job). No risk sizing, margin preflight, or account safeguards exist yet.

## Implemented and verified 2026-07-26 (fourth entry) — Broker order/deal/position reconciliation wired into the EA (D009)

`ExecutionReconciler.mqh` closes two gaps D008 explicitly left open: `position_ticket` is now backfilled from broker records when a match is found (rather than left permanently at `0`), and every loaded intent is checked against live broker truth once at startup, not silently trusted. `CMSZZReconciliationPolicy` (pure) classifies each non-terminal intent into `NO_ACTION`/`MATCHED_ACTIVE_POSITION`/`MATCHED_CLOSED_POSITION`/`CONSISTENT_REJECTION`/`RECOVERY_REQUIRED`, given intents plus injected broker records (open positions, history orders, history deals) built by `CMSZZExecutionReconciler` (live) from `PositionsTotal`/`HistorySelect`. A `RECOVERY_REQUIRED` verdict — the fail-closed default for "nothing conclusive found" — now actually blocks new live execution (`ExecuteCluster()` rejects with `REJECT_RECOVERY_REQUIRED` while `g_recovery_required` is set), not just a logged observation.

Verified: EA and new files compile clean (0 errors; EA carries the one pre-existing unrelated warning). 17/17 deterministic reconciliation assertions pass, `failures=0`, including the critical fail-closed case (a `PERSISTED` intent with nothing found is `RECOVERY_REQUIRED`, never assumed abandoned) and the netting-vs-hedging ambiguity rule (two simultaneous non-terminal intents fail closed on netting, resolve cleanly on hedging). Shadow regression (short + long windows) shows identical 431/178/178 counts and zero orders/deals/trades, with `OnInit()` reconciliation running cleanly against an empty intent store every time (structurally inert in shadow mode, same as every prior decision here). Full regression (ownership, determinism, clusters, intent-store, reconciler) all re-ran clean.

**New known limitation introduced by this decision**: the reconciler has only ever been exercised against deterministic mock data and the isolated demo account's empty broker history. It has never seen a real, non-empty position/order/deal history — no live order has been placed on this branch — so the `RECOVERY_REQUIRED` blocking gate in `ExecuteCluster()` has never actually fired in a real run. This is a first increment, not full coverage: pending-order and partial-fill scenarios remain out of scope (this EA only ever submits market orders today, so these are not currently reachable), externally-modified-stop detection remains Phase 4's job, and there is still no automated recovery/clearing workflow for a `RECOVERY_REQUIRED` intent — clearing one today is a manual, out-of-band operational step.

**Still not done**: no execution state machine with transition-legality enforcement (Phase 3) — the reconciler's own state updates are narrow and verdict-specific, not a general lifecycle driver. The live-execution path (new comment format plus the new blocking gate) has not been exercised against a real order — all three live-execution gates remain closed in every test this pass.

## Implemented and verified 2026-07-26 (third entry) — ExecutionIntentStore wired into the EA (D008)

`ExecutionIntentStore` (D007) is no longer inert: `ExecuteCluster()`'s live-execution path now creates a full `MSZZExecutionIntent` record via `CreateIntent()` as a second, independent, fail-closed gate (journaled `REJECT_INTENT_STORE` on failure), run after D006's proven `EventStore` gate — not replacing it. After the order attempt, `UpdateIntent()` records the outcome (`BROKER_ACCEPTED`/`BROKER_REJECTED`, retcode, result text, order/deal tickets); this specific update is deliberately warn-only, not fail-closed, since the anti-duplicate guarantee is already secured by the EventStore gate earlier in the sequence — see `DECISION_LOG.md` D008 for the full reasoning.

Verified: EA compiles clean (0 errors, 1 pre-existing unrelated warning) in both live tree and isolated instance, hash-identical. Long-window shadow regression (2026.07.01–2026.07.24) shows identical 431/178/178 counts and zero orders/deals/trades, with the intent store correctly initializing (`MSZZ intent store loaded count=0 unknown=0 file=...`) and zero `REJECT_INTENT_STORE` occurrences (expected — shadow mode returns before reaching this code). Full regression (ownership 24/24, determinism, clusters 22/22, parity exporter, intent-store 52/52) all pass, unchanged.

**New known limitation introduced by this decision**: unlike `CMSZZEventStore` (which trims to `InpMaxPersistentEvents`), `ExecutionIntentStore` has no record-count cap or eviction policy yet. For a long-running live/demo EA this file will grow without bound. This was deliberately deferred rather than bolted on hastily, since eviction interacts with Phase 2 (reconciliation) in ways that deserve their own decision (e.g. what happens to a reconciler's view of an intent that gets evicted before reconciliation runs).

**Still not done**: `position_ticket` is left at `0` by design (deriving it correctly, especially under hedging, is Phase 2's job — see D008). No reconciliation of loaded intents against live broker state at startup. No execution state machine with transition-legality enforcement (Phase 3). The live-execution path itself (the new gate plus order submission) has not been exercised against a real order — all three live-execution gates remain closed in every test this pass.

## Implemented and verified 2026-07-26 (second entry) — Atomic execution-intent store (D007)

`Include/MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh` is a new, dedicated persistence component: versioned `MSZZExecutionIntent` records (schema version, intent/cluster/origin IDs, strategy/symbol/timeframe/magic/direction, signal/intent/expiry times, requested volume/entry/stop/target, execution state, submission attempts, broker retcode/result text, order/position/first-deal/last-deal tickets, filled volume, average fill price, last reconciliation time, protection status, instance identity, and an FNV-1a corruption checksum), persisted via a temp-write → reopen-and-verify → backup-rotate → primary-replace → reopen-and-verify protocol with documented (not overstated) atomicity guarantees, exclusivity locking, and unknown-future-schema preservation. 52 deterministic assertions across 13 scenarios (round trip, multiple records, duplicate rejection, simulated temp-write and primary-replacement failures with in-memory rollback, truncated temp/primary files, corrupt checksum, backup recovery both directions, schema preservation, long IDs, embedded delimiters, restart reload, exclusivity and filename separation, deterministic serialization) all pass, `failures=0`. See `BACKTEST_LOG.md` for the full compile and test evidence.

**This is a persistence component only.** It is not yet wired into `MultiSpeedZigZagEA.mq5`'s execution path — `ExecuteCluster()` still uses `CMSZZEventStore` exactly as D006 left it. Wiring this store into live execution (replacing the flat consumed-event check with real per-intent lifecycle tracking), building the broker-history reconciler that reads real order/deal/position state against it, and building the execution state machine that drives its `execution_state` field are each separate, larger, future decisions — none of Phases 2 through 17 of the 2026-07-26 execution-safety engineering request were attempted in this pass. See `HANDOFF.md` for the explicit reasoning on why that scope was not compressed into one pass.

## Fixed and verified 2026-07-26 — Idempotent execution-intent persistence (D006)

**Event persistence failure after successful order submission — RESOLVED.** `ExecuteCluster()`'s live-execution path now calls `ConsumeEvent(persistence_id)` *before* submitting the order (was: after a successful order, warning-only on failure). If the persistence write fails, the order is never attempted (`REJECT_INTENT_PERSISTENCE`, fail-closed). This makes execution idempotent with respect to persistence-layer I/O failures by construction — a durable consumed record and a live order attempt can never be split apart. See `DECISION_LOG.md` D006 for the accepted trade-off (an order that is placed but then rejected by the broker will not be retried, since the cluster is already marked consumed — deliberate and conservative).

Verified: EA compiles clean (0 errors, 1 pre-existing unrelated warning); shadow-mode regression (short + long windows) shows identical candidate/cluster/journal counts to the pre-D006 baseline and zero `REJECT_INTENT_PERSISTENCE` occurrences (expected — shadow mode never reaches the live-execution path); determinism, cluster (22/22), parity exporter, and ownership (24/24) regressions all re-ran clean on otherwise-unchanged source. The live-execution path itself (order submission with the new persist-first ordering) has **not** been exercised against a real broker order — all three live-execution gates remain closed in every test run this pass, by design.

**Explicitly out of scope, still open:** full order/deal history reconstruction (querying `HistorySelect`/`HistoryDealGetTicket` to rebuild past MSZZ-owned orders/deals and reconcile cluster lifecycle state after restart). This is a separate, materially larger feature.

## Identified, not fixed

- **Full ownership reconstruction:** the current batch reconstructs live owned positions at startup, but does not yet map positions/orders/deals back to full cluster lifecycle records after restart.
- **Freeze-level conservatism:** initial stop validation uses `max(stops_level, freeze_level)`, which may reject valid initial protection distances.
- **Risk controls absent:** fixed lots only; no account-risk sizing, margin preflight, daily limits, exposure cap, or emergency kill switch.
- **Reserved strategies absent:** sequential confirmation, retest, sweep/reclaim, compression, and structure transition remain specifications.
- **Pine parity absent:** no completed Pine-side bar-for-bar comparison.
- **Trendline geometry unresolved:** elapsed-time versus bar-index projection remains open.
- **Cluster lifecycle persistence incomplete:** only consumed cluster IDs are persisted.
- **Full-history rebuild performance:** not measured or optimized.
- **Partial opposite-ticket closure is possible but undistinguished:** if multiple owned opposite tickets exist and one `CTrade::PositionClose(ticket)` call fails after an earlier one in the same loop succeeded, `CMSZZPositionOwnership::CloseOwnedOpposite` returns `false` with a reason describing only the failing ticket. This is fail-safe (no foreign/manual position is ever at risk, and the EA correctly aborts the new-entry attempt), but the failure reason does not distinguish "nothing was closed" from "some owned tickets closed, then one failed." Not exercised this pass (zero owned positions existed).

## Reviewed and accepted

The EA version remains below 1.0 and may trigger the known MQL5 Market publishing warning. This branch is not a Market product; reports must still disclose the warning rather than call the build warning-free.

## Production status

- Safe for continued shadow research — the ownership batch compiled clean and passed all regression tests (2026-07-25 second pass).
- Demo execution remains blocked by: no real-position close-by-ticket demo test, post-order persistence recovery, full order/deal reconstruction, risk sizing, margin preflight, and account safeguards.
- No edge or live-readiness claim is supported.