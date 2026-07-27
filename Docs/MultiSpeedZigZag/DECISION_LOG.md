# Multi-Speed ZigZag Suite Decision Log

This file is append-only. Do not rewrite earlier decisions to make the history look cleaner. Supersede a decision with a new entry that references the old one.

---

## D001 — Standalone-first, reusable-core architecture

**Date:** 2026-07-25  
**Status:** Accepted

### Decision

Develop the Multi-Speed ZigZag system as a standalone EA and self-contained strategy suite, while keeping the structural engine and strategy logic reusable through a future Quant Beast adapter.

### Reason

The ZigZag concept supports many distinct hypotheses and requires independent research, parity validation, event clustering, and execution experiments. Embedding all of that directly into Quant Beast would increase coupling and interfere with active Quant Beast edge research.

### Consequences

- Primary front end: `MultiSpeedZigZagEA.mq5`.
- Quant Beast integration is deferred until the shared engine is validated.
- No duplicate strategy implementation is allowed between standalone and adapter modes.

---

## D002 — Dedicated branch and path isolation

**Date:** 2026-07-25  
**Status:** Accepted

### Decision

Use branch `feature/mszz-standalone-suite` and place new implementation and documentation under dedicated MSZZ paths.

### Reason

Claude is actively modifying Quant Beast on `main`. Path isolation reduces merge conflicts and accidental changes to active Quant Beast research.

### Consequences

- Existing indicator files are initially read-only behavioral references.
- Quant Beast files should not be modified during the initial standalone milestone.

---

## D003 — Documentation is a completion requirement

**Date:** 2026-07-25  
**Status:** Accepted

### Decision

A material code change is incomplete unless its architecture, behavior, test impact, and continuation state are documented in the same branch.

### Required updates

At least one of the following must change with each meaningful implementation change:

- `HANDOFF.md`
- `ARCHITECTURE.md`
- `STRATEGY_CATALOG.md`
- `NON_REPAINTING_CONTRACT.md`
- `TEST_PLAN.md`
- this decision log

### Reason

Future agents must be able to continue from evidence and explicit decisions rather than reconstructing intent from code alone.

---

## D004 — Length-prefixed, versioned cluster-ID encoding

**Date:** 2026-07-25
**Status:** Accepted
**Supersedes:** the unversioned `MSZZC|symbol|timeframe|direction|origin_type|origin_id` format used by `CMSZZOpportunityClusterEngine::ClusterId()` since the opportunity-clustering milestone.

### Defect being fixed

`ClusterId()` builds `MSZZC|symbol|timeframe|direction|origin_type|origin_id` by naive `StringFormat` concatenation with `|` as the field delimiter. `origin_id` is itself frequently an already pipe-delimited breakout/pivot identity string (e.g. `BO|XAUUSD|5|1|S|<time>|MSZZ|XAUUSD|5|1|-1|<time>|<time>`), so the resulting cluster ID nests one pipe-delimited string inside another pipe-delimited string. Confirmed empirically during the 2026-07-25 compile/shadow-test pass: every cluster ID exported by `Export_MSZZ_Parity` on real XAUUSD data contained 17 `|` characters, not the 5 the documented five-field format implies. Any consumer that splits on `|` to recover the five documented fields cannot do so unambiguously — the true field boundary between `origin_type` and `origin_id`, and the internal structure of `origin_id` itself, are both lost.

**All cluster IDs produced before this decision (including the shadow-test evidence recorded in `BACKTEST_LOG.md` on 2026-07-25) are legacy evidence only.** They proved the clustering/dedup *logic* worked (zero duplicate cluster IDs, correct owner selection, correct shadow journaling), but the ID *string format* itself is not compatibility-stable and must not be parsed as if it had exactly five `|`-delimited fields.

### Decision

Replace the naive delimited format with a versioned, length-prefixed encoding that is parse-safe regardless of what characters appear inside `origin_id`.

**Format:**

```
MSZZC1|<len>:<symbol>|<len>:<timeframe>|<len>:<direction>|<len>:<origin_type>|<len>:<origin_id>
```

- `MSZZC1` is a fixed literal: the `MSZZC` namespace plus format version `1`. A future format change bumps this to `MSZZC2`, etc.
- Every field is written as `<len>:<value>`, where `<len>` is the decimal UTF-16 code-unit length of `<value>` (as returned by `StringLen`). `timeframe`, `direction`, and `origin_type` are encoded as their decimal integer values (`(int)timeframe`, `(int)direction`, `(int)origin_type`), matching the integer encoding already used elsewhere in this codebase (e.g. `PivotId`, breakout event IDs).
- Fields are still separated by `|` for human readability in raw CSV/journal output, but the separator is never required for correct parsing: decoding consumes each field by its declared length, so a `|` or `:` occurring *inside* `origin_id` is never mistaken for a delimiter. Only the final field (`origin_id`) is variable-length in practice, but the same length-prefix rule applies uniformly to all five fields for consistency and defense-in-depth.
- Decoding validates that the string starts with the literal `MSZZC1|`, that every length prefix is composed only of decimal digits, that every declared length fits within the remaining string, and that the final field's declared length consumes the string exactly to its end. Any violation is a decode failure, not a best-effort partial parse.

### Consequences

- `CMSZZOpportunityClusterEngine` gains dedicated `EncodeClusterId(...)` and `DecodeClusterId(...)` methods.
- Legacy consumed-event files must be cleared or explicitly migrated before new evidence sessions.
- No automatic destructive migration is performed.

---

## D005 — Account-mode-aware, magic-safe ownership and ticket-specific position control

**Date:** 2026-07-25  
**Status:** Accepted

### Defect being fixed

The standalone EA currently uses symbol-wide helpers such as `PositionSelect(_Symbol)` and `CTrade::PositionClose(_Symbol)`. On hedging accounts, multiple positions can exist for one symbol; on all account modes, symbol-wide selection can observe or close positions that belong to a manual trader, Quant Beast, or another EA. The current implementation therefore cannot be authorized for demo or live execution.

### Decision

Introduce a dedicated ownership subsystem with these invariants:

1. Every position, pending order, and historical deal is classified by symbol, magic number, direction, and ticket.
2. MSZZ may manage or close only records whose magic number equals `InpMagic` and whose symbol equals the active symbol.
3. Manual trades (`magic == 0`) and foreign-EA trades are never closed, modified, counted as owned exposure, or used as proof that an MSZZ cluster is already represented.
4. Position closure is ticket-specific. Symbol-wide close calls are prohibited in MSZZ execution code.
5. Account margin mode is detected at initialization and represented explicitly as netting, hedging, exchange, or unsupported.
6. In netting/exchange modes, a foreign position on the active symbol blocks new standalone MSZZ execution because the broker aggregates symbol exposure and MSZZ cannot guarantee ownership isolation.
7. In hedging mode, foreign positions may coexist, but one-position-per-symbol means one **owned MSZZ** position, not one account-wide symbol position.
8. Opposite-signal handling closes only owned MSZZ opposite-direction tickets. It never closes foreign or manual tickets.
9. Startup reconciliation rebuilds an owned-position snapshot from live terminal state before new execution is considered.
10. Any ambiguity or terminal-selection failure is fail-closed: execution is rejected and the reason is journaled.

### Consequences

- Add `Execution/PositionOwnership.mqh` and pure ownership-policy records suitable for deterministic tests.
- Replace `HasSymbolPosition()` and symbol-wide opposite closing in the EA.
- Add explicit inputs controlling owned-position limits and opposite-owned-position policy.
- Add deterministic tests covering manual, foreign, owned, mixed, netting, and hedging scenarios.
- Compilation and terminal verification are required before this subsystem changes demo-readiness status.

---

## D006 — Idempotent execution-intent persistence (write-ahead, fail-closed)

**Date:** 2026-07-26
**Status:** Accepted

### Defect being fixed

`ExecuteCluster()` currently calls `g_trade.Buy()`/`g_trade.Sell()` first, and only *after* a successful order calls `ConsumeEvent(persistence_id)` to persist the cluster as consumed. If that persistence write fails (disk error, file lock, any I/O failure), the code path is:

```
if(ok)
{
   if(!ConsumeEvent(persistence_id)) Print("MSZZ WARNING: cluster executed but persistence failed.");
   ...
}
```

This is a warning, not a recovery halt. The order has already been placed with the broker, but the consumed-cluster record may never reach disk. This gap is documented in `KNOWN_ISSUES.md` under "Event persistence failure after successful order submission" since the D005 pass. Concretely: if the EA restarts (crash, VPS reboot, manual reattach) while historical closed-bar data still contains that cluster's origin within `InpHistoryBars`' lookback window, `ProcessClosedBar()` rebuilds the full structural history from `CopyRates` again on the next new bar, `EventConsumed()` returns `false` for the un-persisted cluster ID, and the EA can select and attempt to execute the *same* cluster a second time. The D005 one-owned-position limit is a coincidental backstop only — it does not help if the original position was already closed (SL/TP/manual) by the time of the restart-replay.

### Decision

Reorder `ExecuteCluster()`'s live-execution path so the durable consumed-event write happens **before** the order is submitted, not after, and treat a failed write as fail-closed (abort the order attempt) rather than a warning:

1. All existing pre-flight gates run unchanged and in the same order: min-score, duplicate-cluster check, `TradingAllowed`, spread guard, stop/target preparation, volume normalization, ownership preflight (D005).
2. Immediately before calling `g_trade.Buy()`/`g_trade.Sell()`, call `ConsumeEvent(persistence_id)`. If it returns `false`, journal `REJECT_INTENT_PERSISTENCE` and return `false` **without ever calling `OrderSend`**.
3. If the persistence write succeeds, submit the order. Whether the order itself then succeeds or fails at the broker, the cluster ID is already durably marked consumed — it will not be attempted again.

This makes cluster execution idempotent with respect to persistence-layer failures by construction: a durable "consumed" record and a live order attempt can never be split by an I/O failure, because the durable record is written first and gates the attempt.

### Explicit trade-off

If the order is submitted but rejected by the broker (spread moved, requote, disconnection mid-`OrderSend`, etc.), the cluster is still marked consumed and will **not** be retried, even though no position was actually opened. This is a deliberate, conservative choice: it is safer to skip a legitimate opportunity than to risk uncontrolled retry/duplicate-execution behavior. This does not change behavior in shadow mode (`InpShadowOnly=true`) — the live-execution path this decision touches is only reached when all three live-execution gates (`InpShadowOnly=false`, `InpAllowLiveExecution=true`, `InpAcknowledgeRisk=true`) are open, which they are not during any of this branch's testing.

### Explicitly out of scope

Full order/deal history reconstruction (querying `HistorySelect`/`HistoryDealGetTicket` to rebuild past MSZZ-owned orders/deals and reconcile cluster lifecycle state after restart) is a separate, materially larger feature and is not part of this decision. It remains an open item in `KNOWN_ISSUES.md`.

### Consequences

- `ExecuteCluster()` in `MultiSpeedZigZagEA.mq5` reorders persistence ahead of order submission on the live-execution path only; the shadow-mode branch (return before any live logic) is unchanged.
- A new journaled status `REJECT_INTENT_PERSISTENCE` replaces the old post-hoc "WARNING: cluster executed but persistence failed" print, which can no longer occur (the order is never attempted if persistence fails).
- No new files, no new inputs, no change to `CMSZZEventStore` itself — this decision reuses its existing fail-reporting `Add()` return value, which was already correct and simply wasn't being treated as fail-closed by its caller.
- Full order/deal history reconstruction remains a separate, future decision.

---

## D007 — Atomic, versioned execution-intent store

**Date:** 2026-07-26
**Status:** Accepted (component only — not yet wired into the EA's execution path)

### Defect or gap

D006 made cluster execution idempotent against *one specific* failure mode (a silent `SaveAll()` I/O failure racing an order submission), by reusing `CMSZZEventStore` — a flat list of opaque "already consumed" strings with no schema, no per-record state, no ticket/fill/protection tracking, and no ability to distinguish *why* a cluster was consumed (shadow-journaled vs. submitted-but-unknown-result vs. filled vs. rejected). D006 itself says so explicitly: it "does not yet provide atomic, versioned, transactional intent persistence or broker-history reconstruction." That gap blocks everything downstream of it — a restart cannot distinguish "this cluster was shadow-journaled" from "this cluster's order result is unknown because the terminal crashed mid-submission," which is exactly the ambiguity that must fail closed rather than guess.

### Chosen behavior

Introduce `Include/MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh`, a dedicated component (not an extension of `EventStore`, per the instruction that unrelated complex schemas should not be bolted onto it) holding one versioned `MSZZExecutionIntent` record per cluster execution attempt, with:

- **Schema-versioned, length-prefixed serialization** (`MSZZI1` format literal, identical primitive to D004's `MSZZC1` cluster-ID encoding: every field is `<len>:<value>`, so no field's content — including a cluster ID that is itself a nested `MSZZC1|...` string — can ever be mistaken for a delimiter). This is a proven pattern in this codebase; D007 reuses it rather than inventing a new one.
- **A non-cryptographic FNV-1a 32-bit checksum** over each record's serialized field payload, stored as an 8-hex-digit field. This detects accidental corruption (truncation, partial writes, bit rot) — it is explicitly **not** a security/tamper-resistance mechanism, and this document does not claim it is one.
- **A two-generation, verify-at-every-step persistence protocol**: serialize to a temp file → flush and close → reopen the temp file and re-parse/re-checksum every record, aborting if anything fails → rotate the current primary to a backup file (abort if this fails, so a backup is never silently skipped) → move the temp file onto the primary → reopen the primary and re-verify record count and checksums → only then report success.
- **Fail-closed in-memory rollback**: the caller-facing `CreateIntent`/`UpdateIntent` methods snapshot the in-memory record array before mutating it; if the persistence protocol above fails at any step, the in-memory array is restored to its pre-mutation snapshot and `false` is returned. The in-memory state and the on-disk state can never disagree about a successful write.
- **`CreateIntent` vs. `UpdateIntent` as distinct operations**: `CreateIntent` rejects (returns `false`) if an intent with the same `intent_id` already exists — this is the "duplicate intent rejection" requirement. `UpdateIntent` requires the `intent_id` to already exist and replaces that record in place — this is how a single intent progresses through execution states over its lifetime without being treated as a duplicate.
- **A load-time fallback chain**: `Load()` tries the primary file; if it fails schema/checksum/truncation validation, it falls back to the backup file; if the backup also fails validation, `Load()` returns `false` with an empty in-memory set (fail closed — never partially load a corrupt file and pretend it succeeded).
- **Unknown-schema preservation**: a record whose `schema_version` field does not match the version this build understands is not parsed, mutated, or dropped — its raw serialized line is held verbatim in a side buffer and re-emitted unchanged on the next save, so an older build can never destroy a newer build's data by round-tripping the file.
- **Exclusivity**: `Configure()` opens a dedicated `.lock` marker file without `FILE_SHARE_WRITE`. If that open fails (because another process/instance already holds it), `Configure()` returns `false` and no further writes are permitted from this instance. This is the "detect multiple writers or fail closed when exclusivity cannot be guaranteed" requirement, implemented with a mechanism MQL5 actually provides rather than an invented guarantee.
- **Filename isolation**: the primary/backup/temp/lock filenames are derived from symbol, timeframe, and magic number (matching `CMSZZEventStore`'s existing convention), so different EA configurations never collide. Cross-*installation* isolation is inherent to MQL5's per-data-folder file sandboxing, not something this component can or needs to enforce itself.

### Rejected alternatives

- **Extending `CMSZZEventStore`'s existing flat-string schema** to carry structured intent data: rejected per this phase's own instruction, and because it would mean overloading a component whose entire contract today is "is this opaque string present or not" with a materially more complex, mutable, multi-field record — a correctness and testability regression, not an improvement.
- **Claiming atomic filesystem rename**: rejected because it cannot be proven true under MQL5/Wine. `FileMove()`'s actual atomicity guarantee at the OS/filesystem level is unverified in this environment. Instead of asserting atomicity, this decision documents the exact residual risk below.
- **A cryptographic hash (e.g., a full hash algorithm) for the integrity field**: rejected as unnecessary engineering weight for a corruption-detection-only requirement with no adversarial-tampering threat model in scope; FNV-1a is sufficient, dependency-free (no DLL imports), and deterministic.

### Failure policy

Every persistence operation that cannot be fully verified end-to-end returns `false` and leaves the in-memory state exactly as it was before the call. There is no partial-success return value and no silent best-effort fallback within a single `CreateIntent`/`UpdateIntent` call.

### Exact atomicity guarantee (not to be overstated elsewhere in this project)

This component provides a **two-generation recoverable protocol**, not proven atomicity:
1. The temp file is fully written, flushed, closed, and independently re-verified before anything touches the primary or backup.
2. The primary→backup rotation and the temp→primary promotion are each individual `FileMove()` calls. If the process is killed between these two calls, the store is left with a backup that equals the *previous* primary and a temp file that equals the *intended new* primary, with the old primary already gone. `Load()`'s fallback-to-backup path recovers to the last-known-good state in that specific case, at the cost of losing only the single in-flight update — never a run of accumulated, unverifiable data.
3. If the process is killed between the temp→primary move completing and this call returning, the caller does not receive a `true` result and may retry or treat the operation as failed — but the data is in fact durable on disk. This is a conservative failure direction (reporting failure when the write actually succeeded), not a dangerous one.

### Migration consequences

This is a new component with no prior on-disk format to migrate from. It does not read or write `CMSZZEventStore`'s existing `MSZZ_Consumed_*.txt` files. The two stores currently coexist independently.

### Restart behavior

`Load()` is designed to be called once at EA startup (mirroring `CMSZZEventStore::Load()`'s existing contract) and reconstructs the full in-memory intent set from durable storage, including any unknown-schema records carried through verbatim. This component alone does not yet reconcile intents against live broker order/position/deal state — that is Phase 2 (order/deal/position reconciliation), a separate future decision.

### Account-mode implications

None directly — this component has no knowledge of account margin mode, ownership, or broker state. It is a pure persistence layer. Account-mode-aware decisions remain the responsibility of `CMSZZPositionOwnership`/`CMSZZPositionOwnershipPolicy` (D005) and the future reconciler (Phase 2).

### Testing requirements

Deterministic, broker-independent unit tests covering: valid save/load round trip; multiple records; duplicate-intent rejection; simulated temp-write failure; simulated primary-replacement failure; truncated temp file; truncated primary file; corrupt checksum; valid-backup-with-corrupt-primary recovery; valid-primary-with-corrupt-backup (primary still wins); in-memory rollback after a failed save; schema-version rejection (and preservation, not destruction); long cluster/origin IDs; IDs containing delimiter characters (`|` and `:`); restart reload; two-instance filename/exclusivity separation; deterministic serialization (identical input encodes identically every time).

### Demo-readiness implications

**None yet.** This decision covers the persistence component in isolation. It is explicitly not wired into `MultiSpeedZigZagEA.mq5`'s execution path in this pass — `ExecuteCluster()` continues to use `CMSZZEventStore` exactly as D006 left it. Wiring this store into the live execution path, building the reconciler that reads broker history against it, and building the execution state machine that drives its `execution_state` transitions are each separate, later decisions (Phase 2 and Phase 3 of the current engineering plan) with their own testing and evidence requirements before any of them can move demo-readiness forward. Demo execution remains blocked on all of the production blockers already listed in `KNOWN_ISSUES.md`, unchanged by this decision.

---

## D008 — Wire `ExecutionIntentStore` into the EA as a supplementary fail-closed gate

**Date:** 2026-07-26
**Status:** Accepted

### Gap being closed

D007 built and exhaustively tested `ExecutionIntentStore` in isolation, but it was inert — no code path in `MultiSpeedZigZagEA.mq5` ever created or updated a record. A tested-but-unused component provides no actual safety benefit and cannot be the foundation Phase 2 (broker reconciliation) needs, since there would be nothing real to reconcile against.

### Decision

Wire the store into `ExecuteCluster()`'s live-execution path as a **second, independent, equally fail-closed gate alongside D006's existing `CMSZZEventStore` check** — not a replacement for it:

1. `OnInit()` additionally configures and loads a `CMSZZExecutionIntentStore` (`g_intent_store`), using a per-run `g_instance_id` derived from account login, local time, and a random component. Exactly like D005's ownership refresh and the existing `CMSZZEventStore::Load()`, failure to configure (e.g. the exclusivity lock is already held — see D007) or load (corrupt store with no valid backup) returns `INIT_FAILED`. This is unchanged fail-closed philosophy applied to a new component, not a new philosophy.
2. In `ExecuteCluster()`'s live path, **after** D006's `ConsumeEvent()` gate passes (unchanged — still the first, proven gate), build a full `MSZZExecutionIntent` record from the already-validated cluster/candidate data and call `g_intent_store.CreateIntent()`. If this fails, journal `REJECT_INTENT_STORE` and return `false` **without ever calling `OrderSend`** — identical fail-closed shape to D006's `REJECT_INTENT_PERSISTENCE`, just for the second store.
3. After the order attempt (success or failure), call `g_intent_store.UpdateIntent()` with the outcome: `execution_state` (`BROKER_ACCEPTED`/`BROKER_REJECTED`), `broker_retcode`, `broker_result_text`, and on success, `order_ticket` (`CTrade::ResultOrder()`) and `first_deal_ticket` (`CTrade::ResultDeal()`). This update is **warn-only, not fail-closed**, and that asymmetry is deliberate: by this point in the sequence, D006's `EventStore` gate has *already* durably marked the cluster consumed, so the anti-duplicate-execution guarantee does not depend on this update succeeding. A failed update here means the intent record's fill/ticket details are incomplete or stale — exactly the situation Phase 2's broker-history reconciler is meant to detect and repair by checking broker truth directly, not a new safety gap this decision introduces.
4. `intent_id` is set to the cluster's own `cluster_id` (already globally unique per D004). No new ID scheme is introduced.
5. `position_ticket` is deliberately left at `0` by this decision. MT5's `CTrade` result accessors after a market order give the order and deal tickets directly; deriving the resulting *position* ticket correctly (especially under hedging, where it is not always identical to the order/deal ticket) is exactly the kind of broker-truth reconciliation Phase 2 is scoped to do properly, not something to guess at here.

### Rejected alternatives

- **Replacing `CMSZZEventStore` outright with `ExecutionIntentStore`** in this pass: rejected. D006's `EventStore` gate is proven across many shadow-regression passes; swapping the primary safety gate and adding a new, less-battle-tested one that ALSO reconciles/manages full lifecycle state in the same change would conflate two decisions and make any regression harder to attribute. Running both gates in sequence is strictly more conservative than either alone.
- **Making the post-submission `UpdateIntent()` fail-closed** (e.g., attempting to cancel/reverse the just-placed order if the update fails): rejected as unsafe and out of proportion — attempting to programmatically reverse a live order to satisfy a logging failure is a materially riskier action than accepting an incomplete-but-recoverable local record, and reversal logic does not exist yet in any case.

### Failure policy

Both `CreateIntent()` (pre-submission) and the `OnInit()` configure/load calls are fail-closed: any failure blocks the corresponding operation (order submission, or EA initialization) and journals/prints the specific reason. `UpdateIntent()` (post-submission) is warn-only, per the explicit reasoning above.

### Migration consequences

None. This is purely additive wiring of an already-existing, already-tested component. No on-disk format changes.

### Restart behavior

Unchanged from D007: `Load()` reconstructs the in-memory intent set at startup. This decision does not yet add any reconciliation of those loaded intents against live broker state — an intent left in `BROKER_ACCEPTED` from a prior session is not yet cross-checked against whether a position actually exists for it. That remains Phase 2.

### Account-mode implications

None directly, same as D007.

### Testing requirements

Extend `Test_MSZZ_Determinism`/`Test_MSZZ_Clusters`/`Export_MSZZ_Parity`/`Test_MSZZ_Ownership`/`Test_MSZZ_IntentStore` regression (all must remain green, unaffected by this additive change) and re-run the shadow Strategy Tester regression to confirm zero orders/deals/trades and that `REJECT_INTENT_STORE` never spuriously fires in shadow mode (it cannot, structurally, since shadow mode returns before reaching this code — the same non-interference property D006 already established for `REJECT_INTENT_PERSISTENCE`).

### Demo-readiness implications

**Still none.** This wires a second persistence gate into the live path, but the live path itself remains untested against a real order (all three live-execution gates stay closed in every test this decision covers). Phase 2 (broker-history reconciliation), Phase 3 (the actual execution state machine with legality-checked transitions), risk sizing, margin preflight, and account safeguards all remain unstarted. Demo execution is not brought closer by this decision beyond making the persisted evidence a future reconciler will need actually exist.

---

## D009 — Broker order/deal/position reconciliation, first increment

**Date:** 2026-07-26
**Status:** Accepted

### Scope of this increment

Phase 2 of the 2026-07-26 execution-safety request lists ~20 reconciliation scenarios (pending orders, partial fills, multi-deal orders, manual/SL/TP closes, externally modified stops, truncated comments, terminal crashes at various points, netting aggregation, etc.). This decision covers a **first, deliberately bounded increment**, not all of them, following the same scope discipline as D007/D008. Covered now: an intent that is still `PERSISTED` (no confirmed broker outcome) being matched against live positions, open orders, and closed-deal history by ticket and by a new comment correlation token; a `BROKER_REJECTED` intent being confirmed as having no matching position (the consistent, expected case); and — critically — an intent for which nothing conclusive is found, which **fails closed to `RECOVERY_REQUIRED`** rather than being assumed abandoned. Explicitly deferred to a later increment: pending-order and partial-fill scenarios (this EA only ever submits market orders today, so these are not currently reachable and are not fabricated as tested coverage), externally-modified-stop detection (that is Phase 4, protection verification), and netting-account aggregation beyond "more than one unresolved intent on a netting account is itself an ambiguity, fail closed" (see below).

### Correlation token

The current trade comment (`"MSZZC|"+strategy_id`) does not correlate to any specific intent. Add `MSZZCorrelationToken(intent_id)`: an 8-hex-character FNV-1a hash of the intent ID (reusing D007's proven checksum algorithm as a free function), embedded in the trade comment as `"MI"+token` (10 characters total, well inside MT5's comment length limit, unlike a full cluster ID which would not fit). This is explicitly a **correlation aid, not a primary key** — matching by `order_ticket`/`position_ticket` (recorded locally by D008 at submission time) is always tried first; the comment token is the fallback for exactly the cases where the local ticket is missing (crash before the D008 `UpdateIntent()` call) or a ticket alone is insufficient to disambiguate.

### Decision: policy/live-query split, mirroring D005

Exactly as `PositionOwnership.mqh`/`PositionOwnershipPolicy.mqh` split live MT5 API calls from a pure, deterministically-testable policy layer, this decision introduces:

- **`CMSZZReconciliationPolicy`** (pure): given an array of `MSZZExecutionIntent` and an array of injected `MSZZBrokerRecord` (ticket, symbol, magic, direction, volume, price, time, comment token, record type [open position / history order / history deal], and — for deals — the owning position ID), classifies every non-terminal intent into one verdict: `NO_ACTION` (already terminal, e.g. `POSITION_CLOSED`/`ABANDONED`), `MATCHED_ACTIVE_POSITION`, `MATCHED_CLOSED_POSITION`, `CONSISTENT_REJECTION` (locally `BROKER_REJECTED` and no matching broker record exists — expected, not ambiguous), or `RECOVERY_REQUIRED` (anything else, including "nothing found" for a `PERSISTED` intent, multiple candidate matches, or more than one unresolved intent simultaneously on a netting-mode account).
- **`CMSZZExecutionReconciler`** (live): builds the `MSZZBrokerRecord` array from `PositionsTotal()`/`PositionGetTicket()`, `HistorySelect()` + `HistoryDealsTotal()`/`HistoryDealGetTicket()`, and `HistoryOrdersTotal()`/`HistoryOrderGetTicket()` — filtered to the configured symbol and magic number (never adopting a foreign-magic record, consistent with D005), deduplicated by ticket — then delegates to `CMSZZReconciliationPolicy` for the actual classification.

### Failure policy (per the original instruction, restated precisely for this component)

- A `PERSISTED` intent with no matching broker record found is **not** assumed abandoned — "never assume a missing local callback means broker rejection" applies exactly here. It is marked `RECOVERY_REQUIRED`.
- More than one non-terminal intent found on a **netting** account is itself ambiguous (a netting account has one aggregated position per symbol, which cannot be unambiguously attributed to multiple distinct intents) and is marked `RECOVERY_REQUIRED` for all of them, not resolved by guessing.
- Any intent resolving to `RECOVERY_REQUIRED` blocks new live execution for that symbol/magic until cleared. No automated recovery/clearing workflow exists yet in this increment — clearing is a manual, out-of-band operational step. This is a known, accepted limitation of a first increment, not a silent gap.
- A conflicting match (the same broker ticket appears to satisfy two different intents) halts execution and journals the exact conflict, per the original instruction, rather than picking one arbitrarily.

### Rejected alternatives

- **Embedding the full cluster ID in the trade comment**: rejected — MT5 comment length limits (well under the ~76+ character length these IDs can reach, per D004) make this structurally impossible, not just impractical.
- **Trusting ticket fields alone with no comment-token fallback**: rejected — the exact scenario this component exists to handle (terminal crash between order submission and the local ticket being recorded) is precisely the case where the local ticket is missing and a fallback correlation signal is needed.
- **Attempting netting-account position-to-intent disambiguation via volume/price heuristics**: rejected as unsound — a netting account's single aggregated position cannot be soundly decomposed back into which specific intents contributed to it without additional broker-side data this component does not have. Failing closed is the honest answer, not a heuristic that could be wrong.

### Migration consequences

None — this is additive. Existing `ExecutionIntentStore` records without a `last_reconciliation_time`/`protection_status` set are handled the same as any other `PERSISTED` record.

### Restart behavior

The reconciler runs once at `OnInit()`, after `ExecutionIntentStore::Load()`, for every loaded intent not already in a terminal state. `last_reconciliation_time` is updated on every intent examined, whether or not its verdict changed, so operators can see when reconciliation last ran.

### Account-mode implications

Directly relevant for the first time: reconciliation behavior differs by account mode specifically for the netting-ambiguity rule above. Hedging accounts do not have this specific ambiguity (multiple simultaneous positions are normal and individually ticketed), though the general "one broker record can only satisfy one intent" conflict rule still applies to all modes.

### Testing requirements

Deterministic, broker-independent tests for `CMSZZReconciliationPolicy` covering: a terminal intent is left alone; a `PERSISTED` intent correctly matches an open position by ticket; by comment token when the ticket is missing; a `PERSISTED` intent matches a closed position via deal history; a `BROKER_REJECTED` intent with nothing found is `CONSISTENT_REJECTION`, not flagged; a `PERSISTED` intent with nothing found is `RECOVERY_REQUIRED`; a foreign-magic record is never considered a match; duplicate ticket rows in the observed-record list do not produce duplicate/inconsistent verdicts; two simultaneously non-terminal intents on a netting-mode account are both `RECOVERY_REQUIRED`; a record that would satisfy two different intents is treated as a conflict, not resolved arbitrarily.

### Demo-readiness implications

Still not sufficient alone. This increment gives the EA a real, tested, fail-closed answer to "did my last order actually happen and what state is it in now," which Phase 12's readiness gate explicitly requires — but risk sizing, margin preflight, account safeguards, the full execution state machine, and fault injection across the combined stack remain unstarted. The reconciler itself has only been exercised against deterministic mock data and the real (currently empty) broker history on the isolated demo account — it has not yet been exercised against a real, non-empty position/order/deal history, since no live order has ever been placed on this branch.

## D010 — Execution state machine, first increment (transition-legality enforcement)

**Date:** 2026-07-26
**Status:** Accepted

### Scope of this increment

Phase 3 of the 2026-07-26 execution-safety request is "the execution state machine driving `ExecutionIntentStore`'s `execution_state` transitions, wired into `ExecuteCluster()`." Following the same scope discipline as D006–D009, this is a **first, deliberately bounded increment**, not the full phase. Covered now: a single, centralized, pure transition-legality table for all 14 `ENUM_MSZZ_INTENT_STATE` values; a `TryTransition()` gate that every `execution_state` write in the EA now goes through instead of a direct field assignment, so an illegal state jump is caught and rejected rather than silently applied; and — the concrete, immediately useful payoff — completing two transitions D009 deliberately left undone. D009's own text said: "Do NOT auto-transition to `POSITION_ACTIVE`/`POSITION_CLOSED`/`ABANDONED` terminal states — that reclassification is arguably Phase 3's execution state machine job." This decision is that job, for exactly those three transitions and no others.

Explicitly deferred to a later increment: the EA still does not emit `PREFLIGHT_PASSED`, `SUBMISSION_STARTED`, `RESULT_UNKNOWN`, `PARTIALLY_FILLED`, or `FILLED` — `ExecuteCluster()` still goes directly from `PERSISTED` to `BROKER_ACCEPTED`/`BROKER_REJECTED` in one step, exactly as it does today. Those states remain defined in the enum and included in the legality table (so a future increment can adopt them without a table redesign), but nothing in this decision causes the EA to emit them. `PROTECTION_FAILED` is likewise defined and included in the table but wired nowhere — that is Phase 4's job. No automated recovery/clearing workflow for `RECOVERY_REQUIRED` is added (unchanged from D009, still a manual, out-of-band step).

### Decision: a pure, static legality table plus a single gated setter

`Include/MultiSpeedZigZag/Execution/IntentStateMachine.mqh` (new) — `CMSZZIntentStateMachine`, a pure, deterministic, no-MT5-API class (same "pure policy" shape as `CMSZZPositionOwnershipPolicy` and `CMSZZReconciliationPolicy`):

- `IsLegalTransition(from, to)`: a static from→{legal-to-set} adjacency table. Every state can reach `RECOVERY_REQUIRED` (any point in the lifecycle can go wrong and need manual attention) and `ABANDONED` (an intent can always be given up on) — modelled as two explicit rows covering all 12 non-terminal source states, rather than special-cased in every other row, to keep the table auditable at a glance. `POSITION_CLOSED` and `ABANDONED` are terminal: no outgoing legal transitions from either (matches `CMSZZExecutionReconciler::IsTerminal()`'s existing definition — this decision does not redefine terminality, it enforces it). A state transitioning to itself is legal (idempotent re-application, e.g. reconciliation re-confirming the same verdict on a second restart) and is not treated as an error.
- `TryTransition(intent, new_state, reason)`: checks `IsLegalTransition`; on success, sets `intent.execution_state` and returns `true`; on failure, leaves `intent` completely unchanged and returns `false` with a human-readable reason. The caller decides what "fail closed" means for its context (see wiring below) — this class never mutates state on a rejected transition, by construction.

### Wiring into the EA

- `ExecuteCluster()`: the post-submission `intent.execution_state=(int)MSZZ_INTENT_BROKER_ACCEPTED` / `MSZZ_INTENT_BROKER_REJECTED` direct assignments are replaced with `TryTransition()` calls. In practice this transition (`PERSISTED`→`BROKER_ACCEPTED`/`BROKER_REJECTED`) is always legal given how intents are constructed, but routing it through the gate means a future refactor that changes construction order gets caught immediately instead of silently corrupting a record. If `TryTransition` somehow fails here, the EA logs `MSZZ WARNING` and falls back to leaving `execution_state` as `PERSISTED` (not the illegal target) — the existing D009 reconciler will pick up a stuck `PERSISTED` intent and correctly fail it closed to `RECOVERY_REQUIRED` on the next restart, so this failure mode was already covered, not newly introduced.
- `OnInit()`'s D009 reconciliation loop: the direct `updated.execution_state=(int)MSZZ_INTENT_RECOVERY_REQUIRED` assignment is replaced with `TryTransition()`. Two new transitions are added that D009 did not perform: `MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION` now transitions the intent to `MSZZ_INTENT_POSITION_ACTIVE`, and `MSZZ_RECONCILE_MATCHED_CLOSED_POSITION` now transitions it to `MSZZ_INTENT_POSITION_CLOSED` (this is what finally makes `CMSZZExecutionReconciler::IsTerminal()`'s `POSITION_CLOSED` check reachable — before this decision no code path ever set it). `MSZZ_RECONCILE_CONSISTENT_REJECTION` now transitions `BROKER_REJECTED`→`ABANDONED`, marking a confirmed-rejected intent terminal so it stops being re-examined every restart (previously it stayed non-terminal forever, which was wasteful but not unsafe — this decision fixes the waste, it was not a correctness bug). Any `TryTransition` failure in this loop is journaled as `MSZZ WARNING` and the intent's `execution_state` is left as loaded — never forced.

### Rejected alternatives

- **Encoding legality as scattered `if` guards at each call site** instead of one table: rejected — the entire point of a "state machine" is one auditable source of truth for what is and is not a legal transition; scattering the checks would recreate exactly the ad hoc, unenforced-invariant problem this decision exists to fix.
- **Special-casing `RECOVERY_REQUIRED`/`ABANDONED` reachability per source state** instead of two blanket rows: rejected — both are explicitly "something went wrong, stop trying" escape hatches by design (see D009's own `RECOVERY_REQUIRED` semantics), and a lifecycle bug that reaches an unanticipated state must still be nameable as broken, not trapped by a table that forgot to allow the one escape hatch it needs.
- **Adopting the fine-grained intermediate states (`PREFLIGHT_PASSED`, `SUBMISSION_STARTED`, etc.) in this same pass**: rejected — `ExecuteCluster()`'s actual submission flow does not currently have distinct preflight/submission phases to hang those states off of; inventing transitions the EA doesn't actually go through would be untested, fabricated coverage, not real behavior.

### Migration consequences

None — additive. Existing `PERSISTED`/`BROKER_ACCEPTED`/`BROKER_REJECTED` records on disk are valid starting points for every transition this decision adds; no record needs to be rewritten or reinterpreted.

### Testing requirements

Deterministic tests for `CMSZZIntentStateMachine` covering: every currently-reachable transition in the EA is legal (`PERSISTED`→`BROKER_ACCEPTED`, `PERSISTED`→`BROKER_REJECTED`, `PERSISTED`→`RECOVERY_REQUIRED`, `BROKER_ACCEPTED`→`POSITION_ACTIVE`, `BROKER_ACCEPTED`→`RECOVERY_REQUIRED`, `POSITION_ACTIVE`→`POSITION_CLOSED`, `POSITION_ACTIVE`→`RECOVERY_REQUIRED`, `BROKER_REJECTED`→`ABANDONED`); every state can reach `RECOVERY_REQUIRED` and `ABANDONED`; `POSITION_CLOSED` and `ABANDONED` have zero legal outgoing transitions (terminal); a same-state transition is legal (idempotent); an arbitrary illegal jump (e.g. `CREATED`→`POSITION_ACTIVE`, skipping the entire lifecycle) is rejected; `TryTransition` leaves the intent struct byte-for-byte unchanged on a rejected transition, not partially mutated.

### Demo-readiness implications

Still not sufficient alone. This increment makes intent lifecycle transitions auditable and enforced rather than ad hoc, and completes the `POSITION_ACTIVE`/`POSITION_CLOSED`/`ABANDONED` reachability gap D009 explicitly deferred — but risk sizing, margin preflight, account safeguards, and fault injection across the combined stack remain unstarted, and the finer-grained intermediate states remain unadopted. As with every decision in this series, the new code path has only been exercised against deterministic mock data and the isolated demo account's empty broker history — no live order has ever been placed on this branch.

## D011 — Protection verification and repair, first increment

**Date:** 2026-07-26
**Status:** Accepted

### Scope of this increment

Phase 4 of the 2026-07-26 execution-safety request is "protection verification and repair after fill." A market order's SL/TP are submitted in the same `CTrade::Buy`/`Sell` request as the entry, so under normal conditions the resulting position already carries the correct protection atomically — but a broker can still reject or silently drop the SL/TP at the actual fill price (which can differ from the requested entry via slippage) while still filling the entry itself, especially near the freeze/stops-level boundary already validated pre-submission against the *requested*, not the *filled*, price. This is a first, deliberately bounded increment: verify the actual position's SL/TP against what was requested immediately after a successful order, attempt exactly one repair via `CTrade::PositionModify` if they don't match, and fail closed (block new execution, same as D009's `RECOVERY_REQUIRED`) if the repair also fails — not a general position-management or trailing-stop system.

Explicitly deferred to a later increment: externally-modified-stop detection (an operator or another EA manually changing SL/TP after this EA set it correctly) is a distinct, ongoing-monitoring problem, not a one-shot post-fill check, and is not attempted here. Trailing stops, break-even moves, and partial-close management remain entirely unimplemented. Repair is attempted exactly once — no retry loop, no backoff — because an unbounded retry against a broker that keeps rejecting the same modify request is itself a risk (e.g. repeatedly hammering a request during a freeze-level violation); one attempt followed by fail-closed is deliberately conservative.

### Decision: reuse the position-ticket-from-market-order assumption, document its limit

Immediately after a successful `CTrade::Buy`/`Sell`, `g_trade.ResultOrder()` is used as the position ticket to verify. This is correct for a brand-new position on a **hedging** account (every market order opens a distinct position whose ticket equals the opening order's ticket) — the only account mode this EA has ever run against (Coinexx-Demo, confirmed `HEDGING` in every prior decision's evidence). It is **not proven correct under netting**, where an order can be aggregated into an existing position with a different ticket. This is the same class of account-mode-specific assumption D005 and D009 already made explicit rather than silently generalized, and is documented as a limitation, not fixed by a heuristic, per this branch's established fail-closed philosophy.

### Decision: policy/live-query split, mirroring D005/D009

- **`CMSZZProtectionPolicy`** (pure): `NeedsRepair(actual_sl, actual_tp, expected_sl, expected_tp, point)` — a tolerance-based comparison (half a point, to absorb broker rounding) with no MT5 API calls, unit-testable with injected doubles.
- **`CMSZZProtectionGuard`** (live): `VerifyAndRepair(trade, ticket, expected_stop, expected_target, reason)` — selects the position by ticket, reads its actual `POSITION_SL`/`POSITION_TP`, delegates the comparison to the policy class, and if repair is needed, calls `CTrade::PositionModify(ticket, expected_stop, expected_target)` exactly once, then re-reads to confirm. Returns one of `PROTECTION_OK` (already correct), `PROTECTION_REPAIRED` (was wrong, fixed), `PROTECTION_REPAIR_FAILED` (still wrong after the one repair attempt), or `PROTECTION_POSITION_NOT_FOUND` (the ticket does not resolve to a live position — treated the same as a failure, not silently skipped).

### Wiring into the EA

- `ExecuteCluster()`: immediately after a successful order (`ok==true`), the intent's `position_ticket` is set to `g_trade.ResultOrder()` and, if `PositionSelectByTicket` confirms the position exists, the intent transitions `BROKER_ACCEPTED`→`POSITION_ACTIVE` via the D010 state machine (this is new — previously the EA only reached `POSITION_ACTIVE` via next-restart reconciliation, leaving a freshly-opened position's intent record stuck at `BROKER_ACCEPTED` for however long the EA kept running). `CMSZZProtectionGuard::VerifyAndRepair` then runs; on `PROTECTION_REPAIR_FAILED` or `PROTECTION_POSITION_NOT_FOUND`, the intent transitions `POSITION_ACTIVE`→`PROTECTION_FAILED` (a transition D010's table already allows) and `g_recovery_required` is set — the exact same new-execution block D009 built for `RECOVERY_REQUIRED`, now serving double duty for "something needs manual attention," per the original instruction's intent rather than a narrower one. If position selection fails (ticket doesn't resolve), the intent is left at `BROKER_ACCEPTED` rather than forcing an unproven `POSITION_ACTIVE` — D009's reconciler will pick this up at next restart exactly as it already does for any other stuck `BROKER_ACCEPTED` intent.
- `OnInit()`'s reconciliation loop: when a `MATCHED_ACTIVE_POSITION` verdict transitions an intent to `POSITION_ACTIVE` (a D010 addition), the same `VerifyAndRepair` call now also runs against the reconciled ticket, extending protection coverage to positions that survived a restart, not just freshly-opened ones in the same session.

### Rejected alternatives

- **Retrying `PositionModify` in a loop until it succeeds**: rejected — an unbounded retry against a broker that keeps rejecting the same request (e.g. a genuine freeze-level violation at the fill price) is itself a new risk, not a fix. One attempt, then fail closed.
- **Silently accepting a missing/wrong SL/TP and relying on the next reconciliation pass to notice**: rejected — the entire point of Phase 4 is a same-tick check, not a "hope a future restart catches it" gap; an unprotected live position is exactly the scenario this component exists to close.
- **Attempting to generalize position-ticket derivation for netting accounts in this pass**: rejected — this EA has never run against a netting account, and inventing untested ticket-aggregation logic would be speculative, not verified behavior. Documented as an explicit limitation instead.

### Migration consequences

None — additive. `PROTECTION_FAILED` was already a defined-but-unused `ENUM_MSZZ_INTENT_STATE` value (D007) and an already-legal destination from `POSITION_ACTIVE` in D010's transition table; this decision is the first to actually reach it.

### Testing requirements

Deterministic tests for `CMSZZProtectionPolicy` covering: matching SL/TP within tolerance needs no repair; SL off by more than tolerance needs repair; TP off by more than tolerance needs repair; both off needs repair; a zero (unset) SL/TP when a nonzero one was expected needs repair; exact-match at floating-point-imprecision boundaries does not spuriously trigger repair.

### Demo-readiness implications

Still not sufficient alone. This increment gives the EA a real, tested answer to "is my open position actually protected," which closes a real gap (SL/TP can theoretically be dropped independently of entry fill) — but risk sizing, margin preflight, account safeguards, fault injection across the combined stack, and the finer-grained intermediate lifecycle states all remain unstarted or unadopted. The position-ticket-equals-order-ticket assumption is hedging-account-specific and undocumented risk if this EA is ever pointed at a netting account without revisiting this decision. As with every decision in this series, this has only been exercised against deterministic mock data — no live order has ever been placed on this branch, so `VerifyAndRepair` has never run against a real position.

## D012 — Margin preflight, first increment

**Date:** 2026-07-26
**Status:** Accepted

### Scope of this increment

Phase 6 of the 2026-07-26 execution-safety request is "margin and exposure preflight." Today the EA has **zero** margin awareness — it will attempt to submit an order at whatever fixed lot size is configured regardless of available free margin. This is a first, deliberately bounded increment: before submitting an order, calculate the margin the intended order would require via the broker-authoritative `OrderCalcMargin()`, compare it against current free margin with a conservative safety buffer, and fail closed (reject the cluster, no order attempted) if the margin is insufficient. This covers **per-order margin sufficiency on the traded symbol only** — not a general account-wide or cross-symbol exposure cap.

Explicitly deferred to a later increment: a cross-symbol/account-wide exposure cap (this EA only ever trades `_Symbol`, and D005's existing one-owned-position-per-symbol policy already bounds same-symbol exposure to at most one position by default, so the marginal risk a broader cap would additionally close is smaller than it would be for a multi-symbol EA); daily loss/drawdown limits, trade-count limits, and a kill switch (Phase 7, a distinct account-safeguards concern, not margin-specific); dynamic/risk-based position sizing (Phase 5 — this increment checks margin for whatever volume `NormalizeVolume()` already produced, it does not change how that volume is computed).

### Decision: use `OrderCalcMargin()`, not a manual leverage/contract-size formula

`OrderCalcMargin(trade_operation, symbol, volume, price, margin)` is the broker-authoritative margin calculation — it accounts for symbol-specific margin requirements, tick value, contract size, and hedged-margining rules that vary by broker and instrument. Reimplementing this from leverage and contract-size inputs manually was considered and rejected: a hand-rolled formula that is subtly wrong in a way that matters is exactly the kind of error this whole execution-safety engineering effort exists to prevent, and there is no reason to accept that risk when the broker already exposes the authoritative calculation directly.

### Decision: policy/live-query split, mirroring D005/D009/D011

- **`CMSZZMarginPolicy`** (pure): `HasSufficientMargin(required_margin, free_margin, buffer_ratio)` — `free_margin >= required_margin * (1.0 + buffer_ratio)`. No MT5 API calls, deterministic, unit-testable with injected doubles.
- **`CMSZZMarginGuard`** (live): `CheckMargin(symbol, order_type, volume, price, buffer_ratio, required_margin_out, free_margin_out, reason)` — calls `OrderCalcMargin()`, reads `AccountInfoDouble(ACCOUNT_MARGIN_FREE)`, delegates the comparison to the policy class. If `OrderCalcMargin()` itself fails (returns `false`), this is treated as insufficient margin, not skipped or assumed fine — "never assume a missing calculation means it's safe" applies here exactly as it has everywhere else in this series.

### Buffer default and new input

A new input, `InpMarginBufferRatio` (default `1.0`), requires free margin to be at least **double** the bare minimum required margin before allowing execution. This is deliberately conservative for a component that has never been exercised against a real account's real margin state — opening a position that consumes exactly 100% of free margin leaves zero room for adverse price movement before a margin call, which defeats the purpose of a margin check that only confirms the order can be *placed*, not that the account can *survive* it. The buffer is configurable, not hardcoded, so an operator can tune it once real demo evidence exists.

### Wiring into the EA

`ExecuteCluster()`: immediately after `NormalizeVolume()` succeeds (i.e. after the existing volume<=0 rejection), `CMSZZMarginGuard::CheckMargin()` runs for the prepared direction/volume/entry price. On insufficient margin (or a failed `OrderCalcMargin()` call), the cluster is rejected (`REJECT_MARGIN`) before `ApplyOwnershipPreflight()`, `CreateIntent()`, or any order submission — consistent with every other pre-order guard in this chain (spread, stops, volume) rejecting before any state-mutating call.

### Rejected alternatives

- **Manual margin formula from leverage/contract size**: rejected, see above — `OrderCalcMargin()` is authoritative and broker/instrument-correct in ways a manual formula is not guaranteed to be.
- **A single "enough margin exists" check with no buffer**: rejected — passing a check that leaves zero headroom is not the same as being safe to actually hold the position through normal price movement.
- **Combining this with a full account-wide exposure cap in the same pass**: rejected as premature scope expansion — this EA trades one symbol with an existing one-position cap; a true multi-symbol exposure cap is Phase 7 territory and would be speculative (untested) if built before this EA ever trades more than one symbol.

### Migration consequences

None — additive. `InpMarginBufferRatio` has a default, so no existing `.set` file or test config needs to change to keep working.

### Testing requirements

Deterministic tests for `CMSZZMarginPolicy::HasSufficientMargin` covering: free margin comfortably above the buffered requirement passes; free margin exactly at the buffered boundary passes; free margin just below the buffered boundary fails; zero required margin is trivially sufficient regardless of free margin; zero free margin with nonzero required margin fails; a buffer ratio of `0` reduces to a bare `free >= required` comparison.

### Demo-readiness implications

Still not sufficient alone. This increment gives the EA its first real margin awareness, closing a genuine gap (previously: none at all) — but risk sizing, a broader account-wide exposure cap, account safeguards (daily loss limits, kill switch), and fault injection across the combined stack all remain unstarted. As with every decision in this series, `CMSZZMarginGuard::CheckMargin()` has only been exercised against deterministic mock data and the isolated demo account's real-but-untested-under-load margin state — no live order has ever been placed on this branch, so this has never actually gated a real order.

## D013 — Account safeguards, first increment (kill switch, daily trade-count limit, daily loss limit)

**Date:** 2026-07-26
**Status:** Accepted

### Scope of this increment

Phase 7 of the 2026-07-26 execution-safety request is "account safeguards: daily loss/drawdown limits, trade-count limits, cooldowns, kill switch." This is a first, deliberately bounded increment covering three of these: a manual kill switch, a daily trade-count limit, and a daily realized-loss limit — all scoped to this EA's own trades (filtered by symbol and magic, exactly as every other guard in this series has been since D005), not the account as a whole. Explicitly deferred to a later increment: cooldowns (a minimum elapsed-time gap between trades), drawdown limits measured against floating/unrealized equity rather than realized daily loss, and any notion of safeguarding trades placed by other EAs or manually on the same account (this EA has no authority over those, consistent with the magic-number-scoped safety philosophy established since D005).

### Decision: three independent circuit breakers, one shared gate

- **Kill switch** (`InpKillSwitchEngaged`, default `false`): when `true`, blocks all new execution unconditionally. This is the simplest, most direct manual override the plan calls for — no query, no calculation, just an operator-controlled flag checked first.
- **Daily trade-count limit** (`InpMaxTradesPerDay`, default `20`): counts today's opening deals (`DEAL_ENTRY_IN`) for this symbol+magic via `HistorySelect` over today's date range, blocks new execution once the count reaches the configured maximum. Default is nonzero and reasonably generous — the primary threat model here is a runaway bug causing rapid repeated execution, not legitimate trading volume, so a permissive-but-real default is safer than leaving this unbounded by default.
- **Daily realized-loss limit** (`InpMaxDailyLossAmount`, default `0.0` = disabled): sums today's realized P&L (`DEAL_PROFIT`+`DEAL_SWAP`+`DEAL_COMMISSION`) for this symbol+magic over today's date range; if the loss magnitude meets or exceeds the configured amount, blocks new execution. Default is **disabled**, not a guessed number — the "right" daily loss cap depends entirely on the account's size and the operator's risk tolerance, and hardcoding a currency amount here would be presumptuous for an account this component has never been evaluated against. An operator must explicitly opt in with a real number once they have an account size in mind.

All three fail closed the same way: a query failure (`HistorySelect` returning `false`) is treated as if a limit were breached, not silently ignored — "never assume a missing calculation means it's safe" applies here exactly as it has everywhere else in this series.

### Decision: policy/live-query split, mirroring D005/D009/D011/D012

- **`CMSZZAccountSafeguardPolicy`** (pure): `TradeCountLimitReached(today_count, max_trades)` (`max_trades>0 && today_count>=max_trades`) and `DailyLossLimitReached(loss_magnitude, max_loss_amount)` (`max_loss_amount>0 && loss_magnitude>=max_loss_amount`). Both treat a non-positive limit as "disabled," not as "always breached" or "always some numeric comparison against zero." No MT5 API calls, deterministic, unit-testable with injected values.
- **`CMSZZAccountSafeguardGuard`** (live): `CheckSafeguards(symbol, magic, max_trades, max_daily_loss_amount, kill_switch_engaged, reason)` — checks the kill switch first, then calls `HistorySelect` for today's date range (from local midnight to now) and, on success, counts today's `DEAL_ENTRY_IN` deals and sums realized P&L across all matching deals, delegating both comparisons to the policy class.

### Rejected alternatives

- **A single combined "account health" score instead of three independent checks**: rejected — three simple, independently-reasoned-about circuit breakers are more auditable than one opaque composite score, consistent with this branch's preference for explicit, narrow checks over clever aggregation (see D010's explicit transition table for the same reasoning applied to state).
- **A default nonzero daily loss limit (e.g. guessing a "reasonable" dollar amount)**: rejected — there is no account-size-independent "reasonable" default, and guessing one risks being silently wrong (too loose to matter, or too tight to be usable) for whatever account this actually runs against. Disabled-by-default with a clear operator opt-in is the honest choice.
- **Measuring drawdown against floating equity instead of realized daily loss in this pass**: rejected as premature — floating-equity drawdown requires deciding what "today's starting equity" means across restarts and requires the protection-guard and reconciliation machinery to be fully trustworthy first; realized-deal-history P&L is simpler, broker-authoritative, and does not depend on this EA's own bookkeeping being perfect.

### Migration consequences

None — additive, and the loss limit defaults to disabled, so no existing `.set` file or test config changes behavior by omission.

### Wiring into the EA

`ExecuteCluster()`: `CMSZZAccountSafeguardGuard::CheckSafeguards()` runs first, immediately after the existing `RECOVERY_REQUIRED`/`PROTECTION_FAILED` block check and before the spread/stops/volume/margin/ownership preflight chain — this is a higher-level circuit breaker that should short-circuit everything else as cheaply as possible, consistent with cheapest-checks-first ordering already used for spread/stops/volume. On failure, the cluster is rejected (`REJECT_ACCOUNT_SAFEGUARD`) with no order attempted and no intent created.

### Testing requirements

Deterministic tests for `CMSZZAccountSafeguardPolicy` covering: trade count below the limit passes, at the limit is blocked, above the limit is blocked, a non-positive max-trades value disables the check entirely; loss magnitude below the limit passes, at the limit is blocked, above is blocked, a non-positive max-loss value disables the check entirely; zero loss magnitude never blocks regardless of a positive limit. The live `CMSZZAccountSafeguardGuard::CheckSafeguards()` history-querying and summation logic is not independently unit-testable without a live terminal (same category as D009's `CollectBrokerRecords`) — it is exercised via compile-time smoke test and shadow regression only, exactly as `CollectBrokerRecords` was in D009.

### Demo-readiness implications

Still not sufficient alone. This increment gives the EA its first real per-day loss and trade-count circuit breakers, plus a manual kill switch — real progress toward Phase 12's readiness gate — but cooldowns, floating-equity drawdown limits, risk sizing, and fault injection across the combined stack all remain unstarted. As with every decision in this series, `CheckSafeguards()` has only been exercised against the isolated demo account's genuinely empty trade history (zero trades ever placed on this branch) — it has never actually counted a real trade or summed a real loss.

## D014 — Phase 12 demo-readiness gate evaluation

**Date:** 2026-07-26
**Status:** Accepted (verdict below; no code changed by this entry)

### Purpose

D005 through D013 each built one bounded increment of the 2026-07-26 execution-safety request and each closed with an honest "demo-readiness implications" paragraph saying, correctly, "still not sufficient alone." This entry is Phase 12 of that request: stop adding increments and instead evaluate, explicitly and in writing, whether what exists is sufficient for Phase 13 (the first controlled demo execution test) — not by assuming the answer, but by walking every phase and every gate and stating plainly what is proven, what is assumed, and what is still missing.

### What is proven (compile + deterministic test + shadow regression evidence exists)

- **Compile**: every file across every decision compiles with 0 errors on both the live tree and the isolated instance, hash-verified identical, in every single pass (D005–D013). One pre-existing, reviewed, unrelated Market-version warning persists throughout and is not a defect.
- **Determinism, closed-bar integrity, cluster-ID encoding, duplicate suppression**: established and re-verified clean through Gates 1–8 (`TEST_PLAN.md`), unchanged by anything in D009–D013.
- **Restart-safe ownership** (D005), **idempotent consumed-event persistence** (D006), **atomic versioned intent store** (D007), **intent store wired into the EA** (D008): all compile-clean, deterministically tested, shadow-regression-clean.
- **Broker reconciliation, first increment** (D009): 17/17 deterministic assertions. Correctly fails closed on "nothing found," on netting-account ambiguity, and on conflicting matches.
- **Execution state machine, first increment** (D010): 25/25 deterministic assertions. Every reachable transition is legal; both terminal states have zero legal outgoing transitions; a rejected transition never partially mutates the record.
- **Protection verification and repair, first increment** (D011): 10/10 deterministic assertions. Tolerance comparison is correct at and around the boundary.
- **Margin preflight, first increment** (D012): 8/8 deterministic assertions. Correctly treats a non-positive buffer as clamped, not as a weakened check.
- **Account safeguards, first increment** (D013): 11/11 deterministic assertions. Kill switch, trade-count limit, and daily-loss limit each independently verified at, above, and below their thresholds, and independently disable-able via a non-positive threshold.
- **Shadow-mode non-interference**: every single decision in this series (D006–D013) re-ran the short and long shadow Strategy Tester windows and reported the same 431 candidates / 178 clusters / 0 orders / 0 deals / 0 trades, proving none of this new machinery has ever changed shadow-mode behavior by so much as one candidate.

That is real, load-bearing evidence — not a claim, a checkable trail across nine decision-log entries and their linked `BACKTEST_LOG.md` sections.

### What is assumed but not yet observed (the honest core of this evaluation)

This is the single most important finding of this gate evaluation, stated as plainly as possible: **no live-execution code path built since D009 has ever actually executed against real broker state.** `InpAllowLiveExecution` has been `false` in every test run of every decision in this entire series. Concretely, none of the following have ever run for real:

- `CMSZZExecutionReconciler::CollectBrokerRecords()` against a real, non-empty position/order/deal history.
- `CMSZZProtectionGuard::VerifyAndRepair()` against a real position's real `POSITION_SL`/`POSITION_TP`, and its one-shot `CTrade::PositionModify()` repair path.
- `CMSZZMarginGuard::CheckMargin()`'s `OrderCalcMargin()` call against a real pending order.
- `CMSZZAccountSafeguardGuard::CheckSafeguards()`'s `HistorySelect()`/deal-summation against real deal history.
- The `position_ticket = order_ticket` assumption (D011) that a market order's ticket equals its resulting position's ticket, which is believed true for this hedging-mode demo account but has literally never been checked against a real fill.
- The `"MI"+8-hex` comment correlation token (D009) actually appearing on a real broker order and being read back correctly from `POSITION_COMMENT`/`DEAL_COMMENT`/`ORDER_COMMENT`.

Every one of these has exactly one form of evidence: a deterministic unit test against hand-constructed mock data. That is real evidence for the *logic*, and it is not evidence that the *live MT5 API integration* is correct, because shadow mode returns before any of this code runs (`ExecuteCluster()`'s very first check is `if(!LiveExecutionAuthorized()) { ...; return true; }`) — confirmed by grep of the current source, not inferred. This is not a new discovery; every decision from D009 onward stated it in its own "not exercised" section. This entry's contribution is naming it as the single cross-cutting fact that determines what "gates pass" can honestly mean.

### Gaps that remain genuinely unstarted

- **Phase 5 (risk sizing beyond fixed lots)**: not started. `InpFixedLots=0.01` is the only sizing path. Assessed as **non-blocking** for a first test — fixed-lot sizing is the *safest* available choice for an initial validation (no calculation to get wrong), not a gap that needs closing before one.
- **Phase 8 (stale-signal/expiry revalidation)**: not started. `intent.expiry_time` is populated (from `owner.expiry_time`) but never read or enforced anywhere in the source — confirmed by grep, there is no code path that checks it. Assessed as **currently unreachable, not currently dangerous**: `ProcessClosedBar()` generates a candidate and calls `ExecuteCluster()` synchronously in the same `OnTick()` invocation, with no queue, no retry, and no delayed-resubmission path anywhere in the codebase. A signal cannot currently go stale because nothing holds one and reconsiders it later. This would become a real, blocking gap the moment any retry/backoff logic is added — it is not one today.
- **Cooldowns and floating-equity drawdown limits** (explicitly deferred in D013): not started.
- **Phase 11 (fault injection across the *combined* stack)**: partial. Every component listed above has its own deterministic fault-injection-style unit tests for its own failure modes in isolation. Nothing has exercised two or more of these guards failing, or interacting, in the same order attempt (e.g., a margin check that barely passes, a requote that shifts the fill price, and a protection repair that itself fails, all in one submission). This is not something a unit test can honestly simulate — MT5 does not expose a way to inject a broker-side requote or partial fill deterministically — so closing this gap fully requires exactly the kind of real, supervised demo activity Phase 13 exists to provide, not more code.

### Verdict

**Not ready for unsupervised or extended live operation.** It is, however, **conditionally ready for exactly one narrow purpose**: a single, fully-supervised, tightly bounded first demo trade, whose explicit goal is to observe the previously-unobserved live-integration paths above for the first time — not to generate a trading result. Recommended conditions for that specific, narrow test, not for anything broader:

1. Run only on the isolated `~/MT5-MSZZ-TEST` instance, attached to a live/demo chart (not the Strategy Tester, which never lets these code paths run for real) — never the live MT5 terminal or account, per this branch's standing constraint.
2. Set `InpMaxTradesPerDay=1` for this specific run, overriding the default `20` — the test should produce exactly one trade, not up to twenty.
3. Set a real, nonzero `InpMaxDailyLossAmount` sized to a small fraction of the actual demo balance, rather than leaving it at the disabled default `0.0` — this is the first time this gate would ever actually be armed.
4. A human must be actively watching in real time for the duration of the test — this evaluation cannot itself confirm that condition, only recommend it.
5. Immediately after the single trade resolves (filled-and-managed-to-close, or rejected), revert `InpShadowOnly` to `true` regardless of outcome, before considering any further live activity.
6. Capture and review, in the same pass: the `MSZZ RECONCILE`, `MSZZ PROTECTION`, and order-submission journal lines, plus a post-hoc reconciliation run (a restart) to confirm the reconciler correctly finds and classifies the real position/deal history this test will finally create.

This verdict is a recommendation, not an authorization to act — see `HANDOFF.md` for how this is being surfaced.

## D015 — Stale-signal expiry enforcement (Phase 8), closed as defense-in-depth

**Date:** 2026-07-26
**Status:** Accepted

### Context and user decision

D014 assessed Phase 8 (stale-signal/expiry revalidation) as "currently unreachable, not currently dangerous," since nothing in the codebase retries or delays a signal, and recommended closing it before any future retry logic is added rather than after. Presented with D014's conditional go/no-go on Phase 13, the user chose explicitly: not yet — close Phase 8 first, stay in shadow-only. This decision is that work.

### A deeper finding than D014 stated

Investigating the fix surfaced something D014 did not know: `MSZZCandidate.expiry_time` is not merely *unenforced* — it is **never assigned a nonzero value anywhere in the strategy code**. Every strategy in `StrategySuite.mqh` constructs its candidates through one shared helper, `CMSZZStrategySuite::AddCandidate()`, and that helper never touches `expiry_time`, leaving it at its zero-initialized default. `OpportunityClusterEngine.mqh`'s cluster-level expiry aggregation logic (propagate the earliest nonzero constituent candidate's expiry to the cluster) is already correct and has been sitting there unused this whole time — it has simply never received a nonzero input to aggregate. This means "closing Phase 8" is not only about adding an enforcement check; the signal-validity horizon has to actually be computed somewhere first, or an enforcement check would just be comparing against a permanently-zero value forever.

### Decision: compute expiry at the single existing choke point, enforce at the single existing execution choke point

- **`CMSZZStrategySuite::AddCandidate()`** (the one place every strategy's candidate is constructed) now sets `c.expiry_time = t + validity_bars * PeriodSeconds()`, where `validity_bars` is a new configurable member (`SetSignalValidityBars()`, mirroring the existing `SetRiskReward()` setter pattern) wired from a new EA input, `InpSignalValidityBars` (default `3` — a signal is considered valid for a small, fixed number of bars past its own close, matching the same order of magnitude as `InpMinBarsBetween`'s existing "a few bars" scale, not a guessed unrelated number).
- **`ExecuteCluster()`** now checks `cluster.expiry_time` — the cluster-level aggregated value, not the individual winning candidate's own `owner.expiry_time` — because the cluster is the actual unit being decided upon, and the cluster engine's existing aggregation already correctly computes "the earliest point at which any constituent candidate goes stale." A non-positive `expiry_time` (still possible in principle, e.g. if this logic were ever bypassed) is treated as "no expiry configured," consistent with the non-positive-disables-the-check convention already used in D012/D013, not as "always expired."
- The persisted `intent.expiry_time` field (D007) is left recording `owner.expiry_time` (the winning candidate's own value) unchanged — that is a record of the specific candidate that won, not the enforcement input, and changing what gets recorded there was not necessary to close this gap.
- The check is placed as the very first content check in `ExecuteCluster()`, before the score/duplicate-cluster checks that already exist there — a stale signal should be rejected before any other consideration, including whether it would have scored well enough to execute.

### Decision: a static, pure comparison function, not a new class

Given the actual comparison is a single line (`expiry_time>0 && now>expiry_time`), this does not warrant a new policy/live-query class pair like D009–D013's guards. Instead, `CMSZZExecutionGuard` (already home to spread/stops/volume checks — an existing "general execution guard" component, not a new concept) gains one new static method, `IsExpired(now, expiry_time)`, pure and deterministic, unit-tested the same way as everything else in this series.

### Rejected alternatives

- **A configurable expiry horizon expressed in seconds/minutes instead of bars**: rejected — every other timing concept in this codebase (`InpMinBarsBetween`, the ATR lookback lengths) is expressed in bars, and a signal's natural staleness horizon is more meaningfully "how many bars have closed since this formed," not a fixed wall-clock duration that would mean something different on every timeframe.
- **Enforcing against `owner.expiry_time` (the individual candidate) instead of `cluster.expiry_time`**: rejected — the cluster, not the individual candidate, is what `ExecuteCluster()` actually decides to act on, and the cluster engine already has correct, existing logic for aggregating multiple candidates' expiries into one cluster-level value. Enforcing against the narrower value would ignore that existing, correct aggregation.
- **A new dedicated policy/live-query class pair**: rejected as unnecessary ceremony for a single-line, side-effect-free comparison — see above.

### Migration consequences

None on disk — `ExecutionIntentStore` records are unaffected (the field was always present, D007). Behaviorally: candidates now carry a real, nonzero `expiry_time` for the first time. Since candidates are generated and acted upon synchronously within the same `OnTick()` call (confirmed in D014), the elapsed time between a candidate's `signal_time` and `ExecuteCluster()`'s check of `TimeCurrent()` is, in every currently-possible code path, effectively zero — so this check is not expected to ever actually reject anything under the EA's current architecture. It exists as defense-in-depth for the day retry/backoff logic is added, exactly as the user directed.

### Testing requirements

Deterministic tests for `CMSZZExecutionGuard::IsExpired()` covering: `now` before `expiry_time` is not expired; `now` exactly at `expiry_time` is not expired (expiry is exclusive, matching "valid through this instant"); `now` after `expiry_time` is expired; `expiry_time<=0` is never expired regardless of `now` (disabled, not "always stale"). Additionally, a smoke check that `CMSZZStrategySuite::AddCandidate()` now produces a nonzero, `signal_time`-relative `expiry_time` given a nonzero `validity_bars` setting — exercised via the existing `Test_MSZZ_Clusters.mq5`/shadow-regression evidence rather than a new dedicated test, since candidate construction is already covered there.

### Demo-readiness implications

This closes the one concretely-named gap from D014's verdict that the user chose to close before any live-execution decision. It does not change D014's core finding — no live-execution code path has ever run against real broker state — which remains the determining fact for Phase 13. Risk sizing (Phase 5) remains an assessed non-blocker, and combined-stack fault injection (Phase 11) remains something only real supervised demo activity can close. The Phase 13 go/no-go decision remains open and unchanged by this entry.

## D016 — Edge Discovery Sprint, Stage A infrastructure: per-trade CSV export with R-multiples and MFE/MAE

**Date:** 2026-07-26
**Status:** Accepted

### Context and pivot

The user redirected this effort onto two separate tracks: the execution-safety work (D005–D015, now paused mid-way through the first supervised live-integration test, waiting on a live signal on a quiet Sunday session) and a new, much larger **Edge Discovery Sprint** aimed at answering a question the 17-phase execution-safety plan never tried to answer — whether the strategy engine has any real edge at all. The user's Stage A spec: run each of the 8 strategies independently with structural-stop exits at 1R/1.5R/2R/3R on XAUUSD M5 at canonical ATR settings, producing a run-level summary and a per-trade CSV so trades can be analyzed outside MT5.

Two of the ingredients Stage A needs require no new code: isolating one strategy at a time (`CMSZZStrategySuite::ConfigureStrategies()` + existing `InpEnable*` inputs) and the 1R/1.5R/2R/3R exit sweep (the existing `InpRiskReward` input already controls `target = entry ± risk*RR`; re-running the Tester with different values *is* the sweep). What's missing, confirmed by source inspection, is the data-capture pipeline itself: nothing in this codebase computes or exports anything about a trade after it opens — no `OnTradeTransaction`, no per-tick or per-bar position-outcome tracking anywhere. This decision builds exactly that, and nothing more.

### Scope of this increment

**Covered**: detecting when an MSZZ-owned position closes on every bar (not just at EA restart — the existing D009 reconciler only runs once at `OnInit()`, so in a single continuous Strategy Tester run spanning months, a position opening and closing mid-test would never be detected as closed under the current architecture); computing R-multiple, MFE/MAE-in-R, exit reason, bars held, and a session bucket for that closed trade; writing one CSV row per completed trade immediately on detection.

**Explicitly deferred**: the master run-level summary CSV (a separate, later decision); `spread_at_entry` and ATR/structure-snapshot columns from the user's full wishlist schema — these are only known at signal time, not close time, and capturing them would require new plumbing to carry signal-time context forward through the intent's lifetime (a schema-versioned `ExecutionIntentStore` bump or a side-table), not worth bundling into this first increment; `commit_sha` in the CSV — not obtainable from MQL5 at runtime, recorded externally per research batch instead; actually running any of the Stage A matrix, ATR robustness grids, cross-market tests, or walk-forward splits; and the currently-paused live demo test (D014/D015), which this decision does not touch (`InpShadowOnly`/`InpAllowLiveExecution`/`InpAcknowledgeRisk` are untouched by this change).

### Decision: direct ticket check, not the D009 reconciler, for closed-position detection

`CMSZZReconciliationPolicy::Reconcile()` (D009) exists to resolve *ambiguous* identity — comment-token matching, netting-conflict handling — for the *restart* case where a position's ticket might not be locally known. Here, the ticket is already known and trustworthy: D011 already sets `intent.position_ticket` and walks the intent to `MSZZ_INTENT_POSITION_ACTIVE` in the same tick as the fill. So `ProcessClosedBar()` gains a small, independent step: for every intent currently `MSZZ_INTENT_POSITION_ACTIVE`, a direct `PositionSelectByTicket(intent.position_ticket)` check. If it no longer resolves, the position closed — look up the closing deal via `HistorySelect`+`HistoryDealGetTicket` matching `DEAL_POSITION_ID`, transition the intent via `CMSZZIntentStateMachine::TryTransition(..., MSZZ_INTENT_POSITION_CLOSED, ...)` (already a legal transition per D010), and export. This does not refactor or reuse the OnInit reconciliation loop — the two paths stay independent, exactly as D009's restart-reconciliation and D011's same-tick-fill-handling already coexist without sharing implementation.

### Decision: policy/live-query split, mirroring D005/D009–D013

- **`CMSZZTradeAnalyticsPolicy`** (pure): `RMultiple(entry, stop, close, direction)`; `ExcursionInR(extreme_price, entry, stop, direction)` (used for both MFE and MAE by passing the window's high or low); `ClassifyExitReason(close, stop, target, point)` (SL/TP/OTHER, reusing D011's `ProtectionGuard.mqh` `point/2.0` tolerance convention rather than inventing a new one); `SessionBucket(hour_of_day)` (three fixed, non-overlapping 8-hour buckets on broker server time — Asian/London/NewYork — explicitly documented as a simplification, not a DST-aware trading-session calendar).
- **`CMSZZTradeAnalyticsExporter`** (live), in a new `Include/MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh`: computes R-multiple from **`intent.average_fill_price`**, not `intent.requested_entry` — the latter is the pre-submission candidate price, the former is the true cost basis; using the wrong one would silently produce systematically-wrong R values on every trade. The MFE/MAE window is `CopyRates(_Symbol, _Period, fill_time, close_time, rates)` using the position's actual fill time (not `intent.signal_time`, which is one bar earlier — the signal candle, not the fill candle); a `copied<=0` guard falls back to MFE=MAE=realized-R with a logged warning rather than failing the whole export. Writes one row via the same pattern as `Diagnostics/ParityExporter.mqh`'s `OpenCsv()` (`FILE_CSV`, `;` delimiter, header-once-if-empty, reopen/seek-end/close per write) — mirrored, not shared code, since `ParityExporter` is a signal-shape-validation concern and this is a trade-outcome concern, the same separation this series has kept everywhere else. **Correction**: this first cut does not compute a raw-currency realized-profit figure at all — the shipped CSV schema carries only the R-multiple, which is sufficient for Stage A's stated comparisons. This entry originally described reusing D013's `DEAL_PROFIT+DEAL_SWAP+DEAL_COMMISSION` convention for a profit column; that was never implemented, and the description has been corrected here to match the actual code rather than left overstating it.

### Decision: one continuously-appended CSV, not one file per run

`MSZZ_TradeAnalytics.csv` accumulates rows across every run, rather than a fresh file per Tester invocation — every row already carries `strategy_id`/`symbol`/`timeframe`, so downstream analysis (pandas, etc.) can group/filter across many runs from one file instead of stitching per-run files together, which is the more useful shape for exactly the "compare 8 strategies × 4 exit multiples" analysis Stage A calls for.

### Rejected alternatives

- **Batch computation at `OnDeinit()`** (scan the whole completed run's `HistoryDealsTotal()` in one pass at the end): rejected — lower code complexity, but Stage A means running the Tester unattended dozens of times over multi-month windows, and this session's own `BACKTEST_LOG.md` already documented MetaTester Agent sandbox quirks. A run that's killed or crashes before `OnDeinit` fires would silently lose every trade row for that entire run. Incremental per-bar detection with an immediate write only loses trades that hadn't closed yet at the point of interruption.
- **Refactoring/reusing the OnInit reconciliation loop for per-bar closure detection**: rejected — see the ticket-check decision above; the reconciler solves a harder problem (identity ambiguity) this case doesn't have, and threading this through it increases surface area touching D009/D010 code for no benefit.
- **Tick-level MFE/MAE instead of bar-range**: rejected for this increment — the existing Tester regressions in this series use `Model=2` (open-price-only), which doesn't simulate a real intrabar path either; computing MFE/MAE from bar highs/lows is precision-matched to that fill model, not a downgrade from it. Upgrading both the fill model and MFE/MAE precision together is a future decision, not two independent ones.

### Migration consequences

None — additive. No `ExecutionIntentStore` schema change; exit price is looked up fresh from broker history at detection time, not persisted on the intent record.

### Testing requirements

Deterministic tests for `CMSZZTradeAnalyticsPolicy` covering: `RMultiple` correct sign/magnitude for a long win, long loss, short win, short loss, and a zero-risk guard; `ExcursionInR` for MFE/MAE in both directions; `ClassifyExitReason` exactly at stop, exactly at target, within tolerance of each, and between the two (OTHER); `SessionBucket` boundary hours (0, 7, 8, 15, 16, 23).

### Demo-readiness / edge-research-readiness implications

This is Edge Discovery Sprint infrastructure, not execution-safety work — it does not advance or regress D014's Phase 13 verdict in either direction. Unlike every prior guard in this series, this component's entire purpose is to observe a closed trade, and there has never been one on this branch or in this session — so unlike D009–D015, this cannot be shadow-regression-validated as proof the export path itself works, only that it stays inert (zero `POSITION_ACTIVE` intents to iterate) during shadow-mode regression. The actual export logic remains unverified against a real closed trade until the Stage A backtests are actually run.

## D017 — Edge Discovery Sprint, Stage A infrastructure: master run-level summary CSV

**Date:** 2026-07-26
**Status:** Accepted

### Scope of this increment

D016 built per-trade export. This increment builds the second half of Stage A's stated output: one row per completed *run* (not per trade), aggregating the same trades D016 already captures — trade count, win rate, expectancy, profit factor, max drawdown, average MFE/MAE, average holding time, and a long/short split — plus run metadata (symbol, timeframe, magic, the `InpRiskReward` exit multiple this run used, and which strategies were enabled).

**In scope**: an in-memory accumulator fed by every call to D016's `ExportClosedTrade()` (no double detection work — the same closed-trade event that writes a trade-level CSV row also feeds this run's summary), a pure aggregation policy class, and one summary row written at `OnDeinit()`.

**Explicitly deferred**: raw-currency profit/profit-factor (D016 never computed dollar profit either — see the correction to D016's own entry above; this stays R-only, consistent with what actually exists); `commit_sha` (unchanged reasoning from D016 — not obtainable from MQL5 at runtime); ATR-setting and full date-range columns beyond what's trivially derivable (the run's actual observed first-signal/last-close timestamps, not the Tester's *requested* `FromDate`/`ToDate`, which isn't exposed to a running EA as a queryable value) — deferred rather than guessed at; walk-forward/holdout bookkeeping (Stage D territory, far later).

### Decision: accumulate in the existing exporter, not a new file

`CMSZZTradeAnalyticsExporter` (D016) already receives every closed trade's inputs at the exact moment `ExportClosedTrade()` is called. Rather than a second detection/call site in the EA, `ExportClosedTrade()` itself appends the trade's R-multiple, direction, MFE/MAE-in-R, and bars-held to small internal arrays, and a new `WriteRunSummary()` method (called once, from `OnDeinit()`) aggregates them. This mirrors `Diagnostics/ParityExporter.mqh`'s own shape — one exporter class producing several related CSV outputs for one concern — more closely than spinning up a second, separate exporter file would.

### Decision: policy/live split, mirroring every prior component in this series

- **`CMSZZRunSummaryPolicy`** (pure, static, array-based — deterministic and directly unit-testable with injected arrays, the same shape D009's tests already use for struct arrays): `Average(values,count)`; `WinRate(r_results,count)` (fraction with `r_result>0`; exactly `0.0` counts as not-a-win, i.e. breakeven is not counted as a win); `ProfitFactorR(r_results,count)` (sum of positive R / `|sum of negative R|`; returns the sentinel `-1.0`, documented explicitly, when there are wins but zero losing trades — a true profit factor is undefined there, not infinite-in-a-meaningful-sense, and `-1.0` is unambiguous against the normal `>=0` range); `MaxDrawdownR(r_results,count)` (walks the cumulative-R equity curve in trade order, tracks the running peak, returns the largest peak-to-trough drop as a positive R number).
- **`CMSZZTradeAnalyticsExporter::WriteRunSummary(symbol, magic, timeframe, risk_reward, enabled_strategies)`** (live): calls the policy functions on the accumulated arrays (and on direction-filtered subsets for the long/short expectancy split — filtering is data-wrangling, not policy, and stays in the live class), and writes one row to a new continuously-appended `MSZZ_RunSummary.csv`, via the same `OpenCsv` pattern as everything else in this series.

CSV schema for this increment: `symbol;timeframe;magic;risk_reward;enabled_strategies;first_signal_time;last_close_time;trades;win_rate;expectancy_r;profit_factor_r;max_drawdown_r;avg_mfe_r;avg_mae_r;avg_bars_held;long_expectancy_r;long_trades;short_expectancy_r;short_trades`.

### Rejected alternatives

- **A second, independent scan of `HistoryDealsTotal()` at `OnDeinit()`** (re-deriving everything from broker history rather than reusing D016's already-computed per-trade values): rejected — recomputing R-multiples, MFE/MAE, etc. a second, independent way risks the two numbers silently disagreeing (which one would be "right"?) and is pure duplicated work for data D016's `ExportClosedTrade()` already has in hand at the moment it's called.
- **Writing the summary incrementally, one partial row updated after every trade** (matching D016's "write immediately, don't batch" reasoning for durability): rejected here — a run-level summary is, by definition, only meaningful once the run is over; a partial mid-run summary row would need to be overwritten in place (not appended), which is a different, more complex CSV-file operation than this series' established append-only pattern, for a case (an entire Tester run being killed mid-way through months of simulated history) that is a real risk for trade-level data but a much smaller one for a single end-of-run row.
- **A separate `RunSummaryExporter.mqh` file**: rejected — see the "accumulate in the existing exporter" decision above; `ParityExporter.mqh` already establishes the "one class, several related CSV outputs" precedent for exactly this kind of closely-coupled concern.

### Migration consequences

None — additive, new file only (`MSZZ_RunSummary.csv`), no existing schema touched.

### Testing requirements

Deterministic tests for `CMSZZRunSummaryPolicy` covering: `WinRate` with a mix of wins/losses/an exact-zero breakeven; `ProfitFactorR` with a normal mixed set, an all-wins set (the `-1.0` sentinel), and an all-losses set; `MaxDrawdownR` with a monotonically-improving sequence (drawdown `0`), a single large loss after wins (drawdown equals that loss), and a sequence with a genuine peak-to-trough-to-recovery shape; `Average` on a simple known set.

### Demo-readiness / edge-research-readiness implications

Same as D016: this is Track 2 (research infrastructure), does not touch D014's Phase 13 verdict, and — like D016 — has never executed against a real closed trade, so the run-summary aggregation itself remains unverified against real data until Stage A backtests are actually run.

## D018 — Edge Discovery Sprint, Stage A pipeline validation: fix `average_fill_price` never assigned

**Date:** 2026-07-26
**Status:** Accepted

### Scope of this increment

D016/D017 built the trade-analytics export pipeline but, per both entries' own honest caveats, it had "never executed against a real closed trade." The first actual Stage A run (MediumBreakout, RiskReward=1.0, XAUUSD M5, full ~17-month history, 548 closed trades) is that first real exercise, and it surfaced a genuine bug: every row's `entry` field in `MSZZ_TradeAnalytics.csv` was `0.00000000`, and every `r_result`/`mfe_r`/`mae_r` value was consequently wrong — e.g. a SHORT trade whose `exit_reason` was `TP` (a win) showed `r_result=-0.9948` (reading as a loss). This is not a Stage A strategy finding; it is a data-correctness bug in infrastructure that would have silently invalidated every Stage A result if run against the full 32-config matrix before being caught.

**In scope:** find and fix the root cause; re-validate against the same MediumBreakout run; nothing else. No strategy logic, no scoring, no exit-model code is touched.

### Root cause

`MSZZExecutionIntent.average_fill_price` (`ExecutionIntentStore.mqh:92`) is declared, serialized/deserialized by the intent-store persistence layer (`ExecutionIntentStore.mqh:203,288`), and read by `TradeAnalyticsExporter.mqh:224` (`double entry=intent.average_fill_price;`) exactly as D016 designed it. But nothing between intent construction and export ever *assigns* it a real value — `MultiSpeedZigZagEA.mq5:319` initializes it to `0.0` at intent creation, and no line after the order fills (`ExecuteCluster()`'s post-`g_trade.Buy()/Sell()` block, `MultiSpeedZigZagEA.mq5:353-394`, which already captures `order_ticket` from `g_trade.ResultOrder()` and `first_deal_ticket` from `g_trade.ResultDeal()`) ever writes the actual fill price into it. It is a field that was designed, plumbed through persistence, and consumed, but never populated — a gap that unit tests couldn't catch (D016/D017's tests inject known-good struct values directly) and that shadow regression couldn't catch either (shadow mode never creates a real intent). Only a real closed trade could expose it, which is exactly why D016 and D017 both flagged "unverified against a real closed trade" as a named, not-yet-closed risk rather than a pass.

`filled_volume` (same struct, same `MultiSpeedZigZagEA.mq5:319` initializer) has the identical never-assigned gap, but nothing currently reads it (not part of the D016/D017 CSV schema), so it was fixed in the same pass as cheap, obviously-correct hygiene rather than treated as a second bug investigation.

### Decision: assign both fields immediately after a successful `g_trade.Buy()/Sell()`, from the same `CTrade` result object already in scope

`MultiSpeedZigZagEA.mq5:357-358` already reads `g_trade.ResultOrder()` and `g_trade.ResultDeal()` in the `if(ok)` block. Add `intent.average_fill_price=g_trade.ResultPrice();` and `intent.filled_volume=g_trade.ResultVolume();` alongside them — same source object, same block, no new API surface. This runs unconditionally once the order is accepted (`ok==true`), before the `PositionSelectByTicket()` branch, so both fields are populated even in the "ticket did not resolve to a live position" fallback path (`MultiSpeedZigZagEA.mq5:393`) — that path already leaves other fields (e.g. `position_ticket`) representing what's actually known, and the fill itself did happen (the order was accepted) regardless of whether the position lookup succeeded a moment later, so recording the fill price there is consistent, not a special case.

### Rejected alternatives

- **Deriving entry price at export time from `PositionGetDouble(POSITION_PRICE_OPEN)` or the opening deal's `DEAL_PRICE` instead of storing it on the intent**: rejected — by the time a position closes and `ExportClosedTrade()` runs, `PositionSelectByTicket()` no longer resolves (the position is gone), and re-deriving from `HistoryDealGetDouble(DEAL_PRICE)` on the opening deal would require a second history lookup beyond the closing-deal lookup `DetectClosedPositions()` already does (D016) — strictly more code and a second point of failure, to reconstruct a value that is already known for free at fill time and just needs to be saved.
- **Fixing only `average_fill_price` and leaving `filled_volume` as a separately-tracked known issue**: rejected — the fix is the same shape, the same block, one extra line, and leaving a field with an identical bug sitting right next to the one just fixed (for no cost saved) would just be manufacturing a future "wait, this one's broken too" moment for whoever eventually reads `filled_volume`.
- **Re-running all of D016/D017's existing deterministic unit tests as sufficient proof of the fix**: rejected as sufficient on its own — those tests inject known-good struct values and would pass whether or not this field is ever assigned in the live EA path, which is exactly how this bug shipped through two prior decisions undetected. The fix is only actually verified by re-running the same real Stage A backtest and confirming the CSV changes shape (see Verification).

### Migration consequences

None — no schema change, no CSV column change. Existing `MSZZ_TradeAnalytics.csv`/`MSZZ_RunSummary.csv` output from the one MediumBreakout run made before this fix is corrupt and must be discarded, not merged into any Stage A master table.

### Testing requirements

No new deterministic unit test — the pure policy functions (`RMultiple`, `ExcursionInR`) were already correct and already tested (D016); the bug was entirely in live-code field assignment, which this codebase's established pattern (D009 onward) verifies via full regression + shadow regression + an actual exercised run, not a mocked unit test. Verification here is empirical: re-run the exact same MediumBreakout Stage A config and confirm `entry` is a real, non-zero XAUUSD price on every row, and that winning trades (`exit_reason=TP`) show positive-sign `r_result` for both directions.

### Demo-readiness / edge-research-readiness implications

Track 2 (research infrastructure) only — does not touch D014's Phase 13 execution-safety verdict. This closes D016/D017's own named open risk ("unverified against a real closed trade") for the `average_fill_price`-dependent fields specifically. The one MediumBreakout run made before this fix is not usable as a Stage A result and will be re-run after the fix is compiled, synced, and regression-clean.

## D019 — FastBreakout research eligibility override (fail-closed, hardened)

**Date:** 2026-07-27
**Status:** Accepted

### Scope of this increment

Stage A's D018 investigation found FastBreakout's base score (`4.0`, hardcoded in `StrategySuite.mqh`) is structurally below `InpMinScore` (default `5.0`), and since isolation-mode testing enables only one strategy, no cross-strategy clustering can lift it above threshold — FastBreakout can never produce a standalone trade under canonical settings, by design of the current scoring literals. The user wants FastBreakout evaluated anyway, for research purposes, without changing production scoring for any strategy running normally.

**In scope:** one new pair of EA inputs that lower the effective score threshold, gated behind a fail-closed authorization check so this can never accidentally run against anything but the Tester or the isolated demo account; a manifest CSV recording that a run used this mode; four new Tester configs exercising it against FastBreakout specifically.

**Explicitly deferred:** any change to `StrategySuite.mqh`'s scoring literals themselves (this overrides the *threshold*, not the *score* — FastBreakout's `4.0` is untouched); Stage B-lite execution (D020, harness only this pass); the exit-efficiency study (D021).

### Decision: general override, not FastBreakout-specific, gated fail-closed

One new input pair: `InpResearchMinScoreOverride` (`double`, default `0.0` — a provable no-op, every existing config omits it) and `InpAcknowledgeResearchOverride` (`bool`, default `false`). General rather than narrowly named for FastBreakout, since any strategy could hit this same isolation-mode ceiling later (e.g. after a Stage B ATR-multiplier change shifts an achievable score) and would need the identical mechanism, not a second one-off input.

Authorization is checked once, early in `OnInit()`, before any other setup, and is **all-or-nothing** — if `InpResearchMinScoreOverride>0.0` is set, every one of the following must also hold, or `OnInit()` returns `INIT_FAILED` with a loud `Print()`. There is no partial/fallback path that silently reverts to normal scoring with the override quietly ignored — a config author who gets this wrong needs to see the EA refuse to start, not get confusing results from a threshold they thought they'd changed:
- `InpAcknowledgeResearchOverride==true` (a second, explicit flag — a single numeric override input is too easy to set accidentally by copy-pasting a `.set` file; a human has to also flip a boolean specifically labeled "acknowledge" for this to activate).
- Running inside the Strategy Tester (`MQLInfoInteger(MQL_TESTER)`), **or** `AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO` on a live-attached chart.
- When live-attached (not Tester): `AccountInfoInteger(ACCOUNT_LOGIN)` matches a hardcoded expected login (`870012`, the documented isolated-instance account in `ISOLATED_TEST_ACCOUNT.md`) — hardcoded, not read from an input, specifically so this check can't be satisfied by pointing the override at some *other* demo account by accident. Tester runs skip this specific check since every Tester run is inherently sandboxed regardless of which account the config references.

This mirrors this branch's established fail-closed philosophy (D005 onward: ambiguous or unverifiable states block, they don't proceed optimistically) applied to a new kind of risk — not "did the broker state resolve correctly" but "did a human definitely mean to relax a safety threshold on this specific run."

### Decision: effective-score computed once, used at both existing gate sites

`InpMinScore` is checked at two sites today — once in the per-bar candidate-evaluation path (before `ExecuteCluster()` is even called) and again inside `ExecuteCluster()` itself (defense-in-depth, same pattern as every other guard in this codebase's chain). A new global, `g_effective_min_score`, is computed once in `OnInit()` (set to `InpResearchMinScoreOverride` only after the authorization check above passes; otherwise `InpMinScore` unchanged) and both existing comparison sites are updated to read it instead of `InpMinScore` directly. Computing it once and reusing it avoids the two gates silently disagreeing (one honoring the override, one not) if only one call site were updated.

### Decision: manifest CSV, not folded into the existing run-summary

A new `MSZZ_ResearchManifest.csv`, written once from `OnDeinit()` (alongside, not inside, the existing `WriteRunSummary()` call) **only when research mode was active this run** — a normal Stage A/shadow/live run never writes this file at all, so its mere presence in a Tester Agent sandbox is itself a signal that research eligibility was used. Columns: `configured_min_score;effective_min_score;research_eligibility_enabled;tester_or_demo;account_login;account_server;commit_sha_placeholder;ex5_hash`. `commit_sha` and the compiled `.ex5`'s hash are not obtainable from MQL5 at runtime (same limitation D016/D017 already documented for `commit_sha`) — both columns are written empty and filled in externally (via `git rev-parse` / `shasum`) when the research batch is logged in `BACKTEST_LOG.md`, not faked or hardcoded into the CSV itself.

### Decision: research results kept out of the canonical Stage A masters

New configs (`stageA_research_FastBreakout_RR1.0/1.5/2.0/3.0.ini`, `InpResearchMinScoreOverride=3.5`, `InpAcknowledgeResearchOverride=true` — `3.5` chosen comfortably below FastBreakout's hardcoded `4.0`, not at some arbitrary round number) are run through the existing `Tools/StageA/run_stageA.sh` harness unchanged, but their output is merged into separate `_master_trades_research.csv` / `_master_runsummary_research.csv` files, never appended to the canonical `_master_trades.csv`/`_master_runsummary.csv`. A reader of the canonical Stage A table should never be able to mistake an eligibility-relaxed research result for a normal-scoring one.

### Rejected alternatives

- **A single override input with no acknowledge flag**: rejected — a bare numeric input is exactly the kind of thing that survives a copy-paste of a `.set`/`.ini` file into a context where it was never meant to apply (e.g. accidentally carried into a future live-demo test config). Requiring a second, explicitly-named boolean makes the activation impossible to trigger by accident.
- **Silently falling back to `InpMinScore` if the authorization check fails, with a warning log only**: rejected — this is precisely the shape of bug this whole branch's discipline exists to prevent: a config author believes research mode is active (because they set the override), gets normal-threshold behavior instead, and the only signal is a log line they may never read. Fail-closed (`INIT_FAILED`) makes the mismatch impossible to miss — the EA simply doesn't start.
- **Checking account login via a user-suppliable input instead of a hardcoded constant**: rejected — an input the config itself controls doesn't add any real protection (a wrong config could just set the "expected login" to match whatever account it's pointed at, defeating the check's purpose). Hardcoding the one authorized isolated-instance login is a deliberate, if inflexible, choice: extending this to a second isolated instance later means changing code, not just a config value, which is the right amount of friction for a check whose entire job is "prove a human isn't pointing this at the wrong account."

### Migration consequences

None — additive. Every existing config (all 32 Stage A `.ini` files, both shadow-regression configs, the paused live-demo `.set` file) omits both new inputs, so `InpResearchMinScoreOverride` defaults to `0.0` and the authorization block never executes for any of them.

### Testing requirements

A deterministic test of the authorization decision as a pure function (given override value, acknowledge flag, tester-flag, trade-mode, login → pass/`INIT_FAILED` decision), independent of `OnInit()` itself, covering: override `<=0` always passes (mechanism fully disabled); override `>0` with acknowledge `false` → fail; override `>0`, acknowledge `true`, non-demo trade mode, not in Tester → fail; override `>0`, acknowledge `true`, demo mode, wrong login, not in Tester → fail; override `>0`, acknowledge `true`, in Tester (login irrelevant) → pass; override `>0`, acknowledge `true`, demo mode, correct login, not in Tester → pass.

### Demo-readiness / edge-research-readiness implications

Track 2 (research infrastructure) only — does not touch D014's Phase 13 execution-safety verdict, and does not relax any live-execution guard (`InpShadowOnly`/`InpAllowLiveExecution`/`InpAcknowledgeRisk` are untouched; this only ever changes what counts as a high-enough score to be considered, not whether execution itself is authorized). Per the user's broadened standing authorization for the isolated demo account (documented in `ISOLATED_TEST_ACCOUNT.md` and this session's memory), this mechanism is deliberately narrow and fail-closed regardless — the account being disposable is a reason to test aggressively, not a reason to make a scoring-threshold override easier to trigger by accident.

## D020 — Stage B-lite harness: one-factor-at-a-time ATR robustness (generate only, no execution)

**Date:** 2026-07-27
**Status:** Accepted

### Scope of this increment

Stage A found positive expectancy in 3-4 strategies under one fixed set of canonical ATR settings. That says nothing about whether those settings are a narrow, lucky peak or sit inside a genuinely robust parameter region — and, symmetrically, whether a Stage-A-negative strategy might have a wide stable plateau somewhere else in the ATR space that canonical settings simply missed. Stage B-lite answers this with one-factor-at-a-time robustness testing across **all 8 strategies**, not just the 3 Stage-A-promising ones — deliberately, so a weak-Stage-A strategy isn't excluded before its parameter space is even looked at, and a strong-Stage-A strategy isn't overrated before its sensitivity to nearby settings is checked.

**In scope this increment:** a config generator producing the 64 non-canonical `.ini` files (8 strategies × 4 factors × 2 non-canonical levels each), committed to the repo, verified for correctness. **Not in scope:** running any of the 64 configs — per explicit prior direction, Stage B execution waits until D021's exit-efficiency Phase 1 results are reviewed, since the exit-model choice could change which strategies are even worth spending robustness-testing time on.

### Decision: fixed RiskReward=2.0 throughout, not "best two Stage A exit targets"

An earlier draft of this plan proposed using each strategy's best two Stage A RR values as the exit models for Stage B. Superseded by explicit direction: entry-parameter robustness and exit-model choice are two different questions, and testing both at once (4 ATR factors × 3 levels × 2 exit models × 8 strategies) would have made the robustness grid's own results harder to read (is a weak cell weak because of the ATR setting, or because of the exit model?). Fixing RiskReward=2.0 as a single shared baseline isolates the entry-robustness question cleanly; exit-model comparison is D021's job entirely.

### Decision: the "ATR length" factor moves all three speeds together

`InpFastATRLen`/`InpMedATRLen`/`InpSlowATRLen` are set to the same tested value (10, 14, or 20) simultaneously when varying the length factor — only the three ATR *multipliers* differentiate fast/medium/slow speed identity from each other, so testing "does a shorter/longer ATR lookback window (applied uniformly) change the outcome" is the meaningful one-factor question, not "what if only the fast speed's length changed while medium/slow stayed at 14" (a combination canonical settings never exercise and that wouldn't isolate a single interpretable factor).

### Decision: canonical-cell reuse from Stage A, with an explicit match requirement

Each factor's canonical level (ATR length 14, Fast mult 1.0, Medium mult 2.0, Slow mult 3.5) is the exact cell Stage A's own RR2.0 run already computed for 7 of the 8 strategies — regenerating and rerunning it would be pure duplicated work. Reuse is only valid because, checked explicitly rather than assumed: same commit family, same `2025.03.01–2026.07.24` data interval, same `Model=2` execution/tick model, same broker/account cost assumptions, same symbol specification, no research-override eligibility mode active (for the 7 non-FastBreakout strategies), and the same CSV output schema. Any future change to any of these invalidates the reuse and that cell must be regenerated and rerun, not assumed. FastBreakout's canonical cell does **not** reuse Stage A (which was 0 trades under normal scoring — not a valid data point) — it reuses D019's research-mode RR2.0 run instead, which used the same `InpResearchMinScoreOverride=3.5`/`InpAcknowledgeResearchOverride=true` eligibility mode Stage B's own FastBreakout configs will also need.

### Decision: extend the existing generator pattern, don't modify it

New `Tools/StageB/generate_configs_stageB.sh`, structurally mirroring `Tools/StageA/generate_configs.sh` (same `[Tester]`/`[TesterInputs]` shape, same magic-number-per-config scheme) rather than editing the Stage A script to take on a second responsibility — Stage A's generator stays exactly as it was for D018, matching this branch's consistent avoidance of retroactively repurposing already-shipped tooling.

### Rejected alternatives

- **Testing all 4 RR values per factor cell (256 configs instead of 64)**: rejected — quadruples execution time for a question (entry robustness) that doesn't need an exit-model sweep to answer; RiskReward is Stage A's and D021's variable, not Stage B's.
- **Varying two factors at once (e.g. ATR length and Fast multiplier together) to catch interaction effects**: rejected for this pass — one-factor-at-a-time was the user's explicit design; interaction effects are a legitimate follow-up question but multiply the grid size combinatorially and weren't asked for here.

### Migration consequences

None — additive, new files only (`Tools/StageB/*.ini`, generator script, README). No existing Stage A config or result is touched.

### Testing requirements

Config correctness only (this increment produces no new MQL5 code): generator produces exactly 64 files; spot-check confirms the ATR-length factor's configs set all three `*ATRLen` inputs together while leaving multipliers canonical, and each of the other three factors changes exactly one multiplier while leaving everything else canonical.

### Demo-readiness / edge-research-readiness implications

Track 2 (research infrastructure) only. No Tester execution occurs in this increment, so there is nothing to verify empirically yet — that happens once Stage B execution is authorized after D021's Phase 1 review.

## D021 — Exit-efficiency simulator, Phase 1

**Date:** 2026-07-27
**Status:** Accepted

### Scope of this increment

Stage A's exit model is fixed structural-stop N-R. The FastMedConfluence RR3.0 run held positions ~23 hours on average — inconsistent with an intraday objective, and the open question is whether a different exit converts more of the already-observed favorable excursion (MFE) into realized profit without reintroducing that holding-time problem. This increment builds and validates **Phase 1 only** (14 exit models: fixed-R, breakeven variants, one fixed-distance trail, time exits, session-close) — Phase 2 (structural: ATR trail, ZigZag confirmed-swing trails, opposite-structure exit) and Phase 3 (partial-close hybrids) are named, deferred, separate future decisions, built only after this pass is reviewed.

**Explicitly out of scope:** any live EA exit-management code (`ExecuteCluster()`'s entry logic and the broker-side fixed SL/TP it submits are completely untouched); Phase 2/3 exit models; executing Stage B (D020).

### Decision: replay entries offline, not live in the EA

Confirmed via source inspection: nothing in this codebase does per-tick or per-bar position management after an order fills — `g_trade.Buy()/Sell()` submits a fixed broker-side SL/TP and that's the entire exit mechanism today. Implementing 14 (and eventually more) exit models as live EA behavior would mean new `OnTick()`-level position management, broker-side trailing-stop modification calls, and a full Tester re-run per model per strategy (~14 runs × several strategies). Building an **offline replay engine** instead — taking a fixed, already-captured entry set and simulating every exit model against the identical post-entry price path — is both far cheaper to run and methodologically cleaner: entries are guaranteed identical across every exit-model comparison by construction, rather than relying on separate Tester runs never producing any small nondeterminism between them.

### Decision: two replay modes, not one — SIGNAL_LEVEL and PORTFOLIO_LEVEL

A review of Stage A's own data caught a real flaw in an earlier draft of this design: Stage A's trade counts differ across RR values (e.g. MediumBreakout: 548 trades at RR1.0, 502 at RR3.0) **because of position occupancy, not because the entries differ** — a longer-held trade (higher RR) blocks the one-owned-position constraint from taking a later signal that a shorter-held trade would have caught. Treating any single RR's completed-trade CSV as "the" entry set for exit-model comparison would silently bake one exit model's own occupancy behavior into the entry sample being tested against a *different* exit model — comparing apples that were never actually the same signals.

Two separate replays instead, using the same underlying signal stream, run against every exit model:
- **SIGNAL_LEVEL**: every qualifying signal, independent of occupancy, overlapping trades allowed. Confirmed buildable entirely from data Stage A already captured — `MSZZ_SignalJournal.csv` already logs `EXECUTED` and `REJECT_OWNERSHIP` as distinct statuses (alongside `RAW_CANDIDATE`, `ORDER_FAILED`, `REJECT_EXPIRED`, `REJECT_SPREAD`, `REJECT_STOPS`). The union of `EXECUTED` and `REJECT_OWNERSHIP` rows is exactly "passed every other guard, blocked only by occupancy" — the immutable signal-level entry set, with no new EA instrumentation required. Answers: "given identical signals, which exit converts more MFE into realized return."
- **PORTFOLIO_LEVEL**: the same signal stream replayed chronologically, enforcing one-owned-position + expiry, letting *each exit model's own* resolution determine when the hypothetical position frees the account for the next signal — occupancy duration is now exit-model-dependent and computed dynamically during replay, not read from whatever RR Stage A happened to have used. Answers: "what would the EA actually have executed under this exit model," including how many later signals it cost.

Both modes report qualifying signals, executed trades, skipped-while-occupied, occupancy %, average time between executable trades, return per calendar day, and return per exposure-hour, for every exit model.

### Decision: bid/ask execution, not mid-price plus a generic cost subtraction

Long trades enter at ask and have stop/target/exit checked against executable bid; short trades enter at bid, checked against ask. Commission, swap, slippage, and tick size are modeled as separate explicit fields, not folded into one "cost" number — this is the same level of rigor D016 already applies to R-multiple computation (average fill price, not requested price) applied to the exit side. Long/short symmetry (one of the validation cases) is checked **after** spread handling is applied, which is a stricter, more honest test than checking symmetry on unspread mid-prices and hoping it survives cost modeling unexamined.

### Decision: tick replay is the primary path when coverage exists — but a build-time probe found it effectively doesn't, for this window

The plan for this increment specified tick data should drive the *entire* simulation (entry, stop/target detection, breakeven/trail activation, MFE/MAE, exit ordering) wherever coverage exists, not just resolve same-bar OHLC ambiguity. A read-only probe of the isolated instance's local cache before building found: `Tester/bases/Coinexx-Demo/history/XAUUSD/` has only bar-level `.hcs` files, no tick cache at all; the terminal-level `bases/Coinexx-Demo/ticks/XAUUSD/ticks.dat` exists but is only ~124KB — a tiny recent window (almost certainly from live-chart activity during this session), nowhere near enough to cover the `2025.03.01–2026.07.24` Stage A window. **Tick coverage is effectively unavailable for this historical range on this instance.** Downloading full 17-month tick history for a liquid instrument is a large, slow operation not attempted without separate authorization, since it wasn't asked for and its cost/benefit for a Phase 1 pass whose exit models don't need sub-bar precision (none of the 14 Phase 1 models depend on knowing which of two same-bar levels was touched first, except the trail-activation-timing edge case) is unclear.

Consequence: all three replay-price modes are implemented and unit-tested (`TICK_RESOLVED`, `OHLC_PESSIMISTIC`, `OHLC_OPTIMISTIC`), but **`OHLC_PESSIMISTIC` is the actual primary evidence for every result in this pass** — every trade's `replay_price_mode` and `tick_coverage_pct` field records this honestly rather than the report implying tick-level precision that doesn't exist. `TICK_RESOLVED` remains available and tested for whenever real tick coverage is obtained (e.g. if a future increment explicitly downloads it).

### Decision: session-close given an explicit, checkable specification

Reuses `CMSZZTradeAnalyticsPolicy::SessionBucket` (D016) for the three 8-hour buckets rather than redefining session windows a second way, but the exit model itself additionally records the exact session-boundary timestamp, that DST is **not** modeled (same simplification `SessionBucket` already documents, not silently inherited), and — since no tick exists at bar boundaries when running in `OHLC_PESSIMISTIC` mode — that the boundary bar's own close price is used as the executable exit price, recorded per trade rather than left implicit.

### Decision: MFE-capture percentage is null, not zero or divide-by-zero, below a threshold

`surrender_r = mfe_r - realized_r` is always computed and reported. `percent_mfe_captured = realized_r / mfe_r` is only computed when `mfe_r` exceeds a configured minimum (`0.1R`) — below that, the ratio is not meaningful (a trade with `mfe_r=0.02R` "capturing" any fraction of it says nothing about exit quality) and the field is `null`, excluded from every mean/median aggregate rather than silently pulling the average toward an arbitrary value or crashing on division by a near-zero number.

### Phase 1 exit models (14)

Fixed 1R / 1.5R / 2R / 3R (reproduces Stage A's own exit for a clean baseline comparison against the newer models); breakeven activated at +0.5R / +0.75R / +1R; breakeven-plus-estimated-costs (stop moved to entry plus estimated round-trip commission/spread in price terms); one fixed-distance trail (0.5R trailing distance, armed only after price first reaches +1R, monotonic — the trail may only move in the profitable direction, enforced in the policy layer and covered by a dedicated test); time exits at 4h / 8h / 12h / 24h; session-close.

### Design: files and output schema

- `Include/MultiSpeedZigZag/Research/ExitSimulatorPolicy.mqh` — pure, static, deterministic exit-resolution functions, one per Phase-1 model family (not 14 near-duplicates), parameterized by a small struct. No MT5 API calls, directly unit-testable with hand-built synthetic bar arrays, matching this whole branch's policy/live split precedent.
- `Scripts/MultiSpeedZigZagTools/SignalSetExporter.mq5` — reads `MSZZ_SignalJournal.csv`, emits the SIGNAL_LEVEL set.
- `Scripts/MultiSpeedZigZagTools/ExitSimulator.mq5` — the live replay engine, both modes.
- `Tests/MultiSpeedZigZag/Test_MSZZ_ExitSimulator.mq5` — the validation suite below.

Per-trade schema: `replay_mode;strategy_id;exit_model;cluster_id;direction;entry_time;exit_time;exit_reason;entry_price;initial_stop;initial_risk;gross_r;net_r_after_costs;mfe_r;mae_r;bars_to_mfe;minutes_to_mfe;bars_held;minutes_held;surrender_r;percent_mfe_captured;reached_0_5r;reached_1r;reached_1_5r;reached_2r;reached_3r;reached_1r_then_negative;spent_time_above_breakeven;number_of_trail_updates;final_stop;commission;swap;slippage;replay_price_mode;tick_coverage_pct;fallback_reason;session;weekday;skipped_while_occupied`. `partial_exit_r`/`remainder_exit_r` declared but always `null` in Phase 1, so Phase 3's hybrid models don't require a schema migration later.

Per-(strategy, exit_model, replay_mode) aggregate schema extends D017's `CMSZZRunSummaryPolicy` (reusing `WinRate`/`ProfitFactorR`/`MaxDrawdownR`/`Average`, not reimplementing them) with the occupancy/timing/MFE-capture columns listed in this session's plan file.

### Validation suite

Target-hit-first, stop-hit-first, same-bar ambiguity (pessimistic vs. optimistic divergence), breakeven-then-reversal, trail ratcheting, trail-never-widens, time-exit exact-boundary, session-close boundary, long/short symmetry after spread handling, commission/swap arithmetic, no-lookahead (truncated-vs-full-array produces identical results up to the shared decision point), long bid/ask path, short bid/ask path, spread-widening-before-stop, spread-widening-before-target, missing/partial tick coverage fallback, no-tick-at-time-exit-boundary, no-tick-at-session-close, signal-level identical-entry-count across models (*E2E*), portfolio-level *differing* trade count across models (*E2E* — the key assertion proving occupancy dynamics actually respond to exit-model choice, not a fixed Stage-A-inherited number), occupancy-blocking caused by a long-held trade (*E2E*), same signal stream producing different executed trades under different exits (*E2E*), deterministic replay hash (*E2E*, two runs on identical input produce byte-identical output). Structural-pivot no-lookahead case deferred to Phase 2 (no pivot-based model exists yet).

### Rejected alternatives

- **Using any single Stage A RR's completed-trade CSV as the fixed entry set**: rejected — see the SIGNAL_LEVEL/PORTFOLIO_LEVEL decision above; this was the actual flaw caught in the first draft of this plan.
- **Downloading full tick history before building anything**: rejected for this pass — large, slow, not requested, and Phase 1's exit models don't need sub-bar precision badly enough to justify the cost before even knowing whether Phase 1 changes the picture. Revisit if Phase 2's structural exits (which may care more about precise intrabar sequencing) make the case stronger.
- **Mid-price entries with one blended "cost" subtraction**: rejected — bid/ask modeling is barely more code and materially more honest, especially for comparing exit models whose holding-time distributions differ (spread cost is paid once per trade regardless of holding time; a cruder model would bias comparisons between short-holding and long-holding exit models in ways that have nothing to do with exit quality).

### Migration consequences

None — additive, entirely new files. Existing `MSZZ_TradeAnalytics.csv`/`MSZZ_RunSummary.csv`/`MSZZ_SignalJournal.csv` schemas are read, never written to or altered.

### Testing requirements

`Test_MSZZ_ExitSimulator.mq5` covering the synthetic cases above against `ExitSimulatorPolicy.mqh`'s pure functions; E2E cases verified against the actual three-strategy run output rather than synthetic data, per this branch's established distinction between what a unit test can prove and what only a real run can.

### Demo-readiness / edge-research-readiness implications

Track 2 (research infrastructure) only — no live EA behavior changes, D014's Phase 13 verdict untouched. This pass's headline result should be read as `OHLC_PESSIMISTIC`-derived, not tick-precise, per the tick-coverage finding above — reported plainly rather than overstated.