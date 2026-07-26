# Test Plan and Release Gates

## Gate 1 — Compile

- `Experts/MultiSpeedZigZagEA.mq5` compiles with zero errors.
- Core headers compile through both the EA and test script.
- Warnings are reviewed; none may hide truncation, uninitialized state, or enum conversion defects.

## Gate 2 — Determinism

- Run `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`.
- Two independent rebuilds over identical closed-bar history must produce identical pivot IDs, labels, directions, and breakout IDs.

## Gate 3 — Closed-bar integrity

- Confirm the forming bar is excluded.
- Compare tick-by-tick tester output against open-prices-only output for closed-bar signal timestamps.
- No signal may move earlier when more future data becomes available.

## Gate 4 — Pine/MQL5 parity

For a fixed symbol, timeframe, history window, and parameter set, export:

- confirmed pivots and confirmation bars
- structure labels
- projected line values
- breakout timestamps
- strategy candidates

Classify mismatches as intentional specification differences or defects.

## Gate 5 — Duplicate suppression

- One structural event may produce many raw candidates.
- At most one selected action may be emitted per event ID.
- Restart reconstruction must not retrade an already executed event once persistence is added.

## Gate 6 — Shadow evidence

Run shadow mode before any broker execution. Journal raw candidates, selection, rejected candidates, stop, target, spread, and strategy ID.

## Gate 7 — Execution safety

Before enabling execution:

- symbol volume limits normalized
- stop-level and freeze-level validation
- spread guard
- daily loss and trade-count controls
- persistent consumed-event store
- restart-safe ownership reconstruction
- explicit demo authorization

## Current gate status (2026-07-25)

- Gate 1 (Compile): **PASS**. All four files compile with 0 errors on MetaEditor build 6033 (live tree) and build 6061 (isolated verification instance). One reviewed/accepted warning remains on the EA (see KNOWN_ISSUES.md). Two real defects were found and fixed during this pass: a compile-blocking local reference bound to an array element in `OpportunityClusterEngine.mqh`, and an unsafe `ZeroMemory()` call on structs containing `string` members across five sites (crash risk per MetaQuotes docs).
- Gate 2 (Determinism): **PASS**. `Test_MSZZ_Determinism` ran against real XAUUSD M5 history (isolated demo account) and reported `TEST PASS: deterministic rebuild`.
- Gate 3 (Closed-bar integrity): Verified by source review (forming bar is excluded from `BuildSpeed`'s loop bound). Not separately verified via tick-by-tick vs. open-prices tester comparison this pass.
- Gate 4 (Pine/MQL5 parity): MQL5-side export **PASS** — `Export_MSZZ_Parity` produced all 6 CSV files (manifest/bars/pivots/candidates/clusters/snapshots) for XAUUSD M5, 1000 closed bars, default ATR settings, with no duplicate pivot rows, no missing origin/event IDs, and no forming-bar timestamps found on inspection. The matching Pine-side export/comparison has not been produced — parity is not yet certified end-to-end. One real defect found: cluster IDs are malformed (see KNOWN_ISSUES.md).
- Gate 5 (Duplicate suppression): **PASS** at the single-run level — `Test_MSZZ_Clusters` reported `failures=0` (8/8 assertions), and the shadow Strategy Tester run journaled 178 unique clusters with 178 matching consumed-event entries and zero duplicate cluster IDs shadow-journaled twice. Restart reconstruction is **partially verified**: the `CMSZZEventStore` component was directly proven to persist and reload consumed events across a genuine process restart (see BACKTEST_LOG.md), but a full end-to-end EA restart test (attached to a live/demo chart across real elapsed bar-closes) was not performed — the MetaTester Agent sandbox resets its `MQL5/Files/` on every separate invocation, so two successive Strategy Tester runs cannot be used to prove this end-to-end.
- Gate 6 (Shadow evidence): **PASS**. Shadow run journaled all raw candidates, cluster selection, and rejected/duplicate paths were exercised at the unit level (`Test_MSZZ_Clusters`); zero broker orders were placed (Strategy Tester report: 0 orders, 0 deals, 0 trades).
- Gate 7 (Execution safety): **NOT YET CERTIFIED**. Symbol volume/stop/freeze validation and spread guard exist and compile, but were not exercised (`InpAllowLiveExecution=false` in every run, by design, so `ExecuteCluster`'s live-order path never ran). Daily loss/trade-count controls remain absent. Restart-safe ownership reconstruction (open-position inventory) and the persistent consumed-event store are both implemented (D005, D006) and pass compile/shadow/deterministic-test evidence, but neither has been exercised against a real order submission — see BACKTEST_LOG.md 2026-07-26 entry. Order/deal history reconstruction remains absent per KNOWN_ISSUES.md.

The branch is an implementation milestone with real compile and shadow-test evidence behind it now, but it is still not production authorization. See BACKTEST_LOG.md for full evidence.

## Gate 8 — Account-mode-aware, magic-safe position ownership (D005, 2026-07-25 second pass)

- **Compile: PASS.** `Test_MSZZ_Ownership.mq5`, `PositionOwnership.mqh`, `PositionOwnershipPolicy.mqh`, and the EA (version `0.310`) compile with 0 errors on isolated MetaEditor build 6061. EA carries the same single reviewed/accepted Market-version warning as before (unrelated to ownership).
- **Deterministic ownership policy test: PASS.** 24/24 assertions, `failures=0` — magic classification (owned/manual/foreign), hedging coexistence, netting/exchange foreign-exposure blocking, one-owned-position limit (including that manual/foreign exposure never triggers it), opposite-ticket collection (excludes manual, foreign, same-direction, unknown-direction, no duplicates), empty-input determinism, and nonempty failure reasons on every rejection path.
- **Live inventory diagnostic (read-only): PASS.** On the isolated demo account (Coinexx-Demo 870012): `ACCOUNT_MARGIN_MODE` raw value correctly resolves to `HEDGING` (matches the terminal's own connection log), ownership snapshot valid, zero positions of every kind (a valid empty-inventory baseline), execution allowed.
- **Shadow Strategy Tester regression: PASS**, both the short window (2026.07.20–2026.07.24) and the previously-validated long window (2026.07.01–2026.07.24): zero orders/deals/trades in both, account mode logged as `HEDGING` at init, zero init failures, zero position-selection errors, candidate/cluster counts identical to the pre-ownership baseline (431 candidates / 178 clusters on the long window), all cluster IDs `MSZZC1`-prefixed with zero duplicates.
- **Regression (determinism/clusters/parity): PASS, no change.** All three re-ran clean on hash-identical source to the prior verified pass.
- **Not verified this pass** (see KNOWN_ISSUES.md): actual close-by-ticket execution against a real open position (no positions were created, per instruction); netting/exchange account modes were validated only via deterministic unit tests, not a real netting/exchange broker account (none available); `owned_longs`/`owned_shorts`/volume totals and same-symbol/different-symbol exclusion are implemented in `CMSZZPositionOwnership::Refresh()` but only exercisable with live non-zero position state, which did not exist during this pass — verified instead by source review (every `MSZZPositionRecord` field is set explicitly, no reliance on implicit struct defaults) and the read-only inventory diagnostic's zero-position baseline.

## Gate 9 — Atomic, versioned execution-intent store (D007, 2026-07-26, Phase 1 of a 17-phase execution-safety request)

- **Compile: PASS.** `ExecutionIntentStore.mqh` and `Test_MSZZ_IntentStore.mq5` 0 errors/0 warnings on both live tree (build 6033) and isolated instance (build 6061), hash-verified identical. Two real MQL5 language errors were found and fixed pre-test (generic `ArrayCopy()`/whole-array `=` do not support struct arrays containing `string` members).
- **Deterministic persistence test: PASS.** 52/52 assertions, `failures=0`, across 13 scenarios: valid round trip, multiple records, duplicate-intent rejection, simulated temp-write failure with rollback, simulated primary-replacement failure with rollback, truncated temp file recovery, truncated primary file fail-closed, corrupt-checksum fail-closed, valid-backup/corrupt-primary recovery, valid-primary/corrupt-backup (primary wins), unknown-schema-version preservation (not destruction), 500-character IDs, IDs containing `|`/`:` delimiter characters, restart reload, exclusivity locking (two instances cannot hold the same file), filename separation (different magic numbers never collide), and deterministic serialization (identical input encodes identically). The temp-write and primary-replacement failure simulations use genuine MQL5 file-sharing conflicts, not fake injected error codes.
- **Regression: PASS, no change.** All other MSZZ targets (ownership 24/24, determinism, clusters 22/22, parity, EA) recompile clean on hash-unchanged source. Not re-executed at runtime this pass since no runtime-affecting source changed — `ExecutionIntentStore.mqh` is a new standalone file included by nothing else yet.
- **Not done this pass, and explicitly not attempted**: Phases 2–17 of the requesting instruction (broker order/deal/position reconciliation, execution state machine, protection verification, risk sizing, margin preflight, account safeguards, stale-signal controls, fault injection across the full stack, and controlled demo execution). See `HANDOFF.md`'s "Scope decision, 2026-07-26" for the reasoning. No live-execution gates were opened; no order, demo or otherwise, was placed.

## Gate 10 — ExecutionIntentStore wired into the EA (D008, 2026-07-26, third pass)

- **Compile: PASS.** EA 0 errors, 1 pre-existing reviewed warning, live tree and isolated instance hash-identical (`5dad1be8...`).
- **Shadow regression: PASS, no change.** Long window (2026.07.01–2026.07.24): identical 431/178/178 counts, zero orders/deals/trades, intent store correctly initializes, zero `REJECT_INTENT_STORE` occurrences (structurally impossible in shadow mode).
- **Full regression: PASS, no change.** Ownership (24/24), determinism, cluster (22/22), parity exporter, and the intent-store suite (52/52) all re-ran clean.
- **What this proves**: the new second persistence gate is correctly wired, fail-closed on creation, warn-only on the post-submission update (by design — see D008), and structurally inert in shadow mode.
- **What this does not prove**: correct behavior against a real order submission (all three live-execution gates remain closed); any reconciliation of loaded intents against broker truth (Phase 2, not started); `position_ticket` derivation (deliberately left at `0`, Phase 2's job).

## Gate 11 — Broker order/deal/position reconciliation wired into the EA (D009, 2026-07-26, fourth pass)

- **Compile: PASS.** EA 0 errors, 1 pre-existing reviewed warning. New files (`ExecutionReconciler.mqh`, `Test_MSZZ_Reconciler.mq5`) 0 errors/0 warnings. Live tree and isolated instance hash-identical.
- **Deterministic reconciliation test: PASS.** 17/17 assertions, `failures=0` — terminal-intent skip, ticket-based match, comment-token fallback match, closed-position match via deal history, consistent rejection, the critical fail-closed case (`PERSISTED` + nothing found → `RECOVERY_REQUIRED`), foreign-magic exclusion, no cross-contamination between intents, duplicate-history-row tolerance, netting-account ambiguity (fails closed) vs. the identical hedging-account shape (resolves cleanly), conflicting-match halt, and correlation-token determinism/distinctness/format.
- **Shadow regression: PASS, no change.** Short (2026.07.20–2026.07.24) and long (2026.07.01–2026.07.24) windows both `successfully finished`, zero orders/deals/trades, identical 431 candidates / 178 clusters on the long window (re-verified from this specific run's isolated log window, not the cumulative daily Tester-agent log — a known gotcha in this test harness). `OnInit()` reconciliation runs cleanly every time against an empty intent store (shadow mode never creates intents).
- **Full regression: PASS, no change.** Ownership, determinism, cluster, intent-store, and reconciler suites all re-ran clean.
- **What this proves**: the reconciler correctly classifies every scenario in its declared scope against deterministic mock data; the EA wiring backfills `position_ticket` on a match and blocks new execution on `RECOVERY_REQUIRED`; none of this interferes with shadow-mode operation.
- **What this does not prove**: correct behavior against a real, non-empty broker position/order/deal history (none exists on this branch — no live order has ever been placed); the `RECOVERY_REQUIRED` blocking gate has never actually fired in a real run; pending-order/partial-fill reconciliation (out of scope — this EA only submits market orders); an execution state machine with transition-legality enforcement (Phase 3, not started).

## Gate 12 — Execution state machine, first increment (D010, 2026-07-26, fifth pass)

- **Compile: PASS.** EA 0 errors, 1 pre-existing reviewed warning. New files (`IntentStateMachine.mqh`, `Test_MSZZ_StateMachine.mq5`) 0 errors/0 warnings. Live tree and isolated instance hash-identical.
- **Deterministic transition-legality test: PASS.** 25/25 assertions, `failures=0` — every currently-reachable transition legal, universal `RECOVERY_REQUIRED`/`ABANDONED` reachability from every non-terminal state, both terminal states have zero legal outgoing transitions, same-state (idempotent) transitions legal even from terminal states, an arbitrary illegal jump rejected, and a rejected `TryTransition` leaves the intent struct byte-for-byte unchanged.
- **Shadow regression: PASS, no change.** Short and long windows both `successfully finished`, zero orders/deals/trades, identical 431/178/178 counts on the long window. `OnInit()` reconciliation runs cleanly against an empty intent store every time.
- **Full regression: PASS, no change.** Ownership, determinism, cluster, intent-store, reconciler, and state-machine suites all re-ran clean.
- **What this proves**: `execution_state` writes throughout the EA are now routed through one auditable legality table instead of scattered direct field assignments; the reconciler's `MATCHED_ACTIVE_POSITION`/`MATCHED_CLOSED_POSITION`/`CONSISTENT_REJECTION` verdicts now actually complete the intent lifecycle to `POSITION_ACTIVE`/`POSITION_CLOSED`/`ABANDONED`, closing a gap D009 explicitly left open.
- **What this does not prove**: any of the new transitions firing against a real, non-empty broker history (none exists on this branch); the finer-grained intermediate states (`PREFLIGHT_PASSED`, `SUBMISSION_STARTED`, etc.) remain unadopted — `ExecuteCluster()`'s actual submission flow is unchanged; risk sizing, margin preflight, and account safeguards (Phases 5–7, not started).