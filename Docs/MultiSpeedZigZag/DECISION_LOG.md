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