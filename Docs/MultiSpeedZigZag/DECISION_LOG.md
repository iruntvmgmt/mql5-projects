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

## D022 — Exit simulator: same-bar activation sequencing and replay-metric integrity

**Date:** 2026-07-27
**Status:** Accepted

### Scope of this increment

D021's `SimulateExit()` had a real methodological flaw in every breakeven and trailing model, caught on review before Stage B began: within a single bar, the code updated the stop from that bar's own favorable extreme *first*, then immediately tested that bar's adverse extreme against the *newly moved* stop. Without tick data, the true intrabar order of "price moved favorably enough to arm/ratchet" versus "price moved adversely enough to be stopped out" is unknowable — and the old code silently assumed the favorable event happened first, every time, even in `OHLC_PESSIMISTIC` mode, which is supposed to be the worst-case assumption. This could retroactively manufacture a breakeven/trail save on a bar that a truly worst-case ordering would have stopped out at the *original* stop.

**In scope:** correct the activation/ratchet sequencing for all 5 affected models (`BE_0_5R`, `BE_0_75R`, `BE_1R`, `BE_PLUS_COSTS`, `TRAIL_0_5R_AFTER_1R`); give `OHLC_OPTIMISTIC` its own genuinely favorable-first logic instead of reusing pessimistic sequencing; anchor time-based exits to the real `entry_time` rather than the first forward bar's own timestamp; add dual excursion metrics (until-exit vs. the shared reference horizon) so `percent_mfe_captured` stops conflating two different questions; new deterministic tests for every sequencing edge case; rerun all three strategies against all 14 Phase-1 models with the corrected logic and report what changed.

**Explicitly deferred:** Stage B execution and Phase 2 structural exits — both wait until this correction's results are reviewed, per explicit instruction. No live EA changes.

### Decision: track `stop_at_bar_open` separately from the stop carried into the next bar

Each bar now evaluates the stop **as it stood at that bar's open** against that bar's own high/low *before* any activation/ratchet logic runs. In `OHLC_PESSIMISTIC` mode: if the old stop and target are both touched this bar, the adverse level wins (unchanged from the original same-bar-ambiguity rule, just now applied to the *correct*, pre-update stop value); if only the old stop is touched, the trade exits there — the bar's own favorable excursion never gets a chance to arm or ratchet anything, because the position didn't survive to see it "count"; only a bar that survives against the old stop (neither old stop nor target touched) is allowed to compute a new stop from that bar's favorable extreme, and that new stop is recorded as `stop_at_bar_open` for the *next* bar only — never tested against the bar that produced it.

### Decision: flag same-bar sequencing ambiguity and report both bounds, rather than silently picking one

If a bar survives against the old stop and its favorable extreme would arm/ratchet a new stop, but that same bar's *adverse* extreme would also have touched the newly-computed (not-yet-active) stop, the true outcome is genuinely unknowable without ticks — the primary `OHLC_PESSIMISTIC` result still defers the new stop to the next bar (per the rule above, so the headline numbers stay methodologically consistent), but the row is marked `sequencing_ambiguous=true` and an alternate immediate-exit bound (as if the new stop had been hit the same bar) is computed and reported alongside, rather than silently discarded.

### Decision: `OHLC_OPTIMISTIC` gets its own explicit favorable-first logic, not a reused pessimistic path with the labels swapped

Optimistic mode now assumes the bar's favorable event resolves *first*: a target touch this bar wins outright before any adverse check; otherwise, activation/ratchet is applied first (as if the good move happened before the bad one), and only *then* is the adverse extreme checked against the freshly-updated stop for a same-bar exit. This is a genuinely different computation from pessimistic mode, not the same code path with which-level-wins flipped — the two now diverge exactly where they should (any bar with real intrabar ambiguity), and agree everywhere else.

### Decision: `entry_time` is an explicit parameter, not inferred from `bars[0].time`

Time-based exits (`TIME_4H/8H/12H/24H`) were anchored to `bars[0].time` (the first bar in the supplied forward-path array), documented at the time as "accurate to within one bar" — an approximation that no longer needs to exist now that the live script can simply pass the real `entry_time` through. `SimulateExit()` gains an `entry_time` parameter; the boundary check becomes `bars[i].time >= entry_time + time_limit_seconds`, exact rather than approximate.

### Decision: two excursion metrics, not one ambiguous `percent_mfe_captured`

D021's single `mfe_r`/`mae_r`/`percent_mfe_captured` conflated two different questions: "how much of the excursion available *while this specific model held the trade* was captured" versus "how much of the excursion available over the *shared reference window* (used to keep comparisons fair across models) was captured." Both are now computed and exported separately:
- `mfe_until_exit_r` / `mae_until_exit_r` — computed only over the bars this specific (signal, model) pair actually held the position, i.e. truncated at that model's own resolved exit.
- `mfe_reference_horizon_r` / `mae_reference_horizon_r` — the original D021 shared-window computation, unchanged, still comparable across all 14 models for a given signal.
- `pct_open_trade_mfe_captured` (against the until-exit denominator) and `pct_reference_horizon_mfe_captured` (against the reference-horizon denominator) replace the single D021 `percent_mfe_captured` column, each still null below the same minimum-MFE threshold rather than a meaningless or divide-by-zero ratio.

### Rejected alternatives

- **Assuming adverse-first unconditionally for every same-bar case, including the newly-computed-stop scenario, rather than deferring to the next bar**: rejected — the explicit instruction requires the *primary* pessimistic result to defer the new stop to the next bar (matching how a real broker's server-side trailing-stop modification would only take effect after the modification request completes, not retroactively within the same price bar), while still surfacing the alternate immediate-exit bound for anyone who wants the more conservative number.
- **Silently reusing `OHLC_PESSIMISTIC`'s same-bar-ambiguity branch for `OHLC_OPTIMISTIC`, just swapping which level "wins"**: rejected per explicit instruction — this was exactly the shortcut that made the original bug easy to miss, since both modes shared one code path differing only in a single comparison. Genuinely separate logic makes the two modes' divergence auditable.
- **Keeping a single `percent_mfe_captured` and just fixing its denominator**: rejected — the two questions ("how much of what was available while held" vs. "how much of what was available in the shared comparison window") are both legitimately useful and answer different things; collapsing them back into one field would just reintroduce a different ambiguity.

### Migration consequences

D021's committed trade-level CSVs (`Tools/ExitSim/results/*/MSZZ_ExitSim_Trades.csv`) are now known to be corrupted for the 5 affected models (`BE_*`, `TRAIL_0_5R_AFTER_1R`) and must be treated as superseded, not deleted-and-forgotten — this decision log entry and the D022 BACKTEST_LOG.md entry document exactly what was wrong with them and why. The 9 unaffected models (`FIXED_1R/1.5R/2R/3R`, `TIME_4H/8H/12H/24H`, `SESSION_CLOSE`) never had activation/ratchet logic in the first place and are unaffected by this fix — their D021 numbers stand. Output schema gains `mfe_until_exit_r`, `mae_until_exit_r`, `mfe_reference_horizon_r`, `mae_reference_horizon_r`, `pct_open_trade_mfe_captured`, `pct_reference_horizon_mfe_captured`, `sequencing_ambiguous`, `alt_bound_exit_price`, `alt_bound_exit_time`; the D021 single `percent_mfe_captured`/`mfe_r`/`mae_r` columns are superseded by the reference-horizon-suffixed equivalents.

### Testing requirements

New deterministic cases in `Test_MSZZ_ExitSimulator.mq5`: old stop touched before any same-bar favorable move can activate BE (long and short mirror); a bar that survives the old stop and correctly arms/ratchets, with the new stop only live starting the next bar; a same-bar case where the favorable extreme reaches the trail trigger *and* the adverse extreme would cross the proposed new stop (confirms `sequencing_ambiguous` fires and both bounds are populated); a case where the old stop is not hit but the proposed new stop alone would have been (must not exit this bar in pessimistic mode); pessimistic vs. optimistic producing genuinely different outcomes on an identical ambiguous bar; a time exit anchored to a entry_time that does not fall exactly on a bar boundary; MFE-until-exit excluding price movement after the resolved exit; reference-horizon MFE including it; a portfolio-occupancy rerun remaining deterministic after the fix.

### Demo-readiness / edge-research-readiness implications

Track 2 (research infrastructure) only. This does not change whether Stage B or Phase 2 are worth pursuing on its own — it changes whether the numbers used to decide that are trustworthy. Per explicit instruction, Stage B and Phase 2 remain paused until the corrected D021 results (this entry's rerun) are reviewed.

### Results (post-implementation rerun, all three strategies, all 14 models)

Compile: 0 errors/0 warnings, live tree and isolated instance, for `ExitSimulatorPolicy.mqh`, `Test_MSZZ_ExitSimulator.mq5`, `Scripts/MultiSpeedZigZagTools/ExitSimulator.mq5`. Tests: 34/34 assertions pass, `failures=0` (one test-authoring bug found and fixed during verification — `TestTimeExitAnchoredToEntryTime`'s original synthetic bar spacing didn't actually straddle a bar boundary between the old and new time-anchor, so the two anchors coincidentally agreed; corrected the entry-time offset so the two anchors provably disagree by a full bar, which is what the test claims to check).

**Trade-level changes:** of 22,278 (strategy, model, signal) SIGNAL_LEVEL resolutions compared 1:1 against the D021 originals, exactly **987 changed** (exit_time, exit_reason, or net_r differed) — all 987 fell within the 5 affected models, confirmed by zero changes in any of the 9 unaffected models (`FIXED_*`, `TIME_*`, `SESSION_CLOSE`), which is the expected internal-consistency proof that the fix is correctly scoped. Changed-row counts per (strategy, model): `TRAIL_0_5R_AFTER_1R` 112–122, `BE_0_5R` 92–99, `BE_0_75R` 48–54, `BE_1R`/`BE_PLUS_COSTS` 30–35, consistent across all three strategies.

**Expectancy/PF before vs. after (PORTFOLIO_LEVEL):**

| Strategy | Model | D021 expectancy_r (trades) | D022 expectancy_r (trades) | D021 PF | D022 PF |
|---|---|---|---|---|---|
| FastMedConfluence | BE_0_5R | -0.1354 (208) | -0.0200 (203) | 0.58 | 0.94 |
| FastMedConfluence | BE_0_75R | -0.0708 (177) | **+0.0029** (175) | 0.84 | 1.01 |
| FastMedConfluence | BE_1R | -0.0263 (160) | **+0.0303** (159) | 0.95 | 1.06 |
| FastMedConfluence | BE_PLUS_COSTS | -0.0326 (160) | **+0.0226** (159) | 0.93 | 1.05 |
| FastMedConfluence | TRAIL_0_5R_AFTER_1R | +0.0461 (173) | +0.0565 (170) | 1.10 | 1.11 |
| FastMedContext | BE_0_5R | -0.1675 (217) | -0.0577 (212) | 0.51 | 0.85 |
| FastMedContext | BE_0_75R | -0.0953 (186) | -0.0309 (184) | 0.79 | 0.93 |
| FastMedContext | BE_1R | -0.0614 (169) | -0.0140 (168) | 0.88 | 0.97 |
| FastMedContext | BE_PLUS_COSTS | -0.0671 (169) | -0.0211 (168) | 0.86 | 0.96 |
| FastMedContext | TRAIL_0_5R_AFTER_1R | +0.0406 (180) | +0.0232 (177) | 1.08 | 1.04 |
| WeightedEnsemble | BE_0_5R | -0.1292 (229) | -0.0379 (223) | 0.63 | 0.90 |
| WeightedEnsemble | BE_0_75R | -0.0860 (197) | -0.0303 (194) | 0.81 | 0.94 |
| WeightedEnsemble | BE_1R | -0.0535 (179) | -0.0144 (178) | 0.89 | 0.97 |
| WeightedEnsemble | BE_PLUS_COSTS | -0.0587 (179) | -0.0209 (178) | 0.88 | 0.96 |
| WeightedEnsemble | TRAIL_0_5R_AFTER_1R | +0.0397 (195) | +0.0134 (192) | 1.08 | 1.03 |

The sequencing bug was biasing BE/TRAIL results **pessimistically, not optimistically** — every affected model's expectancy improved after the fix (the bug was manufacturing phantom same-bar stop-outs that a correct next-bar-only activation wouldn't have hit). `BE_0_75R`, `BE_1R`, and `BE_PLUS_COSTS` flipped from negative to positive expectancy for FastMedConfluence specifically; for FastMedContext/WeightedEnsemble they moved from clearly negative to near-breakeven but did not flip. `TRAIL_0_5R_AFTER_1R` **remains positive at the portfolio level in all three strategies**, but the direction of the change was mixed: it strengthened for FastMedConfluence (+0.046→+0.057, PF 1.10→1.11) and weakened for FastMedContext (+0.041→+0.023, PF 1.08→1.04) and WeightedEnsemble (+0.040→+0.013, PF 1.08→1.03, now only marginally profitable).

**Holding-time / occupancy changes:** trade counts for affected models each dropped by 1–5 trades per strategy (a small number of previously-mis-sequenced same-bar exits shifted to a different, later resolution), which nudged occupancy percentages up by roughly 0.2–1.3 points across the board (e.g. FastMedConfluence `BE_0_5R` occupancy 56.67%→57.71%, `TRAIL` 64.48%→65.09%) — a minor second-order effect of correcting the primary sequencing bug, not a new finding on its own.

**Ambiguity counts** (`sequencing_ambiguous=true` rows, i.e. bars where the old stop survived but a same-bar proposed new BE/trail stop would also have been touched — genuinely unknowable without ticks): `TRAIL_0_5R_AFTER_1R` 92–99 per strategy, `BE_0_5R` 80–84, `BE_0_75R` 39–42, `BE_1R`/`BE_PLUS_COSTS` 21–23, out of 470–580 signal-level trades per model. This is a non-trivial fraction (up to ~19% for `TRAIL`) of trades where the OHLC-only replay cannot determine same-bar ordering — a material caveat on precision, honestly bounded rather than silently resolved, and a strong argument for prioritizing real tick-history acquisition before treating Phase 1 numbers as final.

### Portfolio-selection effect (rule 12 analysis, `TRAIL_0_5R_AFTER_1R`, the one model positive at portfolio level in all three strategies)

**Taken vs. occupancy-skipped expectancy** — the one-owned-position constraint is not a neutral drag, it is actively protective: signals *skipped* because the account was occupied have substantially *worse* SIGNAL_LEVEL expectancy than signals actually taken, in all three strategies:

| Strategy | Taken (n, expectancy_r) | Skipped (n, expectancy_r) |
|---|---|---|
| FastMedConfluence | 170, +0.0565 | 317, **-0.1056** |
| FastMedContext | 177, +0.0232 | 324, **-0.1291** |
| WeightedEnsemble | 192, +0.0134 | 381, **-0.1594** |

This suggests occupancy is incidentally filtering toward better setups (e.g. avoiding correlated re-entries into an already-adverse move), not merely capping opportunity — a meaningfully different interpretation than "occupancy costs edge," and relevant to any future decision about relaxing the one-owned-position constraint.

**Long/short (taken trades):** roughly balanced in all three strategies — FastMedConfluence long +0.087 / short +0.029 (a real long-side skew), FastMedContext long +0.000 / short +0.045, WeightedEnsemble long +0.018 / short +0.009. No strategy shows a broken or reversed side.

**Quarterly concentration — the most important caveat in this entire study:** cumulative profit is extremely concentrated in a single quarter, 2026Q1, across all three strategies:

| Strategy | 2026Q1 pct of total cumulative sum_r | Quarters net negative |
|---|---|---|
| FastMedConfluence | 75.8% | 2025Q2, 2025Q4, 2026Q3 |
| FastMedContext | 202.1% (total sum_r is only +4.1R) | 2025Q2, 2025Q4, 2026Q2, 2026Q3 |
| WeightedEnsemble | 242.5% (total sum_r is only +2.6R) | 2025Q2, 2025Q4, 2026Q2, 2026Q3 |

For FastMedContext and WeightedEnsemble, 2026Q1 alone contributes *more than the entire net profit* — every other quarter combined is a net loser, and the headline "TRAIL is positive at portfolio level" result is carried almost entirely by one quarter's performance rather than being broadly distributed across the ~17-month window. This does not necessarily mean the edge is fake (2026Q1 could reflect a genuine regime the strategy is suited to), but it means the current positive-expectancy finding should be treated as **fragile and regime-dependent, not a robust standalone result**, until either a longer/out-of-sample window is tested or the 2026Q1 period is understood (e.g. an unusually strong trending period in gold).

### Net conclusion for this pass

The sequencing fix changes the numbers but not the qualitative Phase 1 headline: `TRAIL_0_5R_AFTER_1R` is still the standout exit model and remains positive at the portfolio level in all three strategies post-fix. However, two new findings materially qualify that headline and should inform whether Stage B/Phase 2 proceed on the current evidence: (1) up to ~19% of `TRAIL` trades are same-bar sequencing-ambiguous under OHLC-only replay, and (2) the entire positive-expectancy finding is concentrated in a single quarter for two of the three strategies. Real tick-history acquisition and/or a longer or out-of-sample validation window are stronger candidates for the next research investment than proceeding directly to Stage B execution or Phase 2 structural exits on the current sample.

## D023 — Stage B-lite all-strategy parameter robustness execution

**Date:** 2026-07-27
**Status:** Accepted
**Starting SHA:** `e3949278d3cde6426cb0b95c4f4c1de338e8816a` (D022 commit, `feature/mszz-standalone-suite`)

### Scope of this increment

Execute D020's 64-config one-factor-at-a-time grid (ATR length, Fast/Med/Slow multiplier, each moved independently around canonical, 8 configs/strategy × 8 strategies) across all eight strategies, including FastBreakout under its D019 research eligibility override. Objective is explicitly **robustness mapping, not optimization** — classify each strategy/factor's 3-point neighborhood (low/canonical/high) rather than search for the single best cell. FastMedConfluence is the primary candidate for deep inspection; the other seven are checked for Stage-A misclassification (a canonical point sitting in an otherwise-viable region) and for genuine vs. illusory contribution (WeightedEnsemble vs. FastMedConfluence/FastMedContext overlap). Motivated directly by D022: the exit-replay pipeline is now internally trustworthy, but its one clearly positive finding (`TRAIL_0_5R_AFTER_1R`) is OHLC-ambiguous on up to ~19% of trades and concentrated almost entirely in a single quarter — Stage B tests whether the *entry* strategies have a stable edge independent of that provisional exit result, using the unrelated fixed 2R exit Stage A/B have always used.

**Explicitly deferred:** Phase 2 structural exits (do not begin until Stage B is complete, validated, and reviewed); any new parameter selection or "optimized" config; merge to `main`.

### Decision: rerun all 8 canonical center-point cells rather than importing Stage A/D019 numbers

D020 originally allowed reusing each strategy's existing Stage A RR2.0 canonical cell (or, for FastBreakout, the D019 research RR2.0 cell) under an exact-match condition on commit SHA, data interval, execution model, costs, symbol spec, eligibility mode, and output schema. Checking that condition against the *current* SHA: the data interval, execution model (`Model=2`), costs, symbol spec, and output schema are unchanged, but the commit SHA is not — D019, D020, D021, and D022 all landed after Stage A's canonical runs completed. `git log` on the EA's own trading-logic files (`Experts/MultiSpeedZigZagEA.mq5`, `Include/MultiSpeedZigZag/Strategies`, `Include/MultiSpeedZigZag/Core`) confirms the last change was D019 (`90807b6`, the fail-closed research-eligibility override, a no-op for every config that doesn't set `InpResearchMinScoreOverride`) — D020/D021/D022 never touched EA code at all. So the canonical cells are *very likely* numerically identical to Stage A's, but "very likely identical" is not "exact SHA match," and the instruction is explicit: rerun rather than import if anything differs. Eight canonical-rerun configs (`stageB_<Strategy>_canonical.ini`, one per strategy, byte-identical `[TesterInputs]` to the Stage A/D019 RR2.0 source except `Report=` and a fresh unique `InpMagic`) are added alongside the 64 D020 configs, giving 72 total runs and a complete, internally-consistent 3-point neighborhood per strategy per factor computed entirely at the current SHA. If a canonical rerun's numbers diverge materially from the old Stage A number, that itself is a data point (confirms or refutes the "no EA logic changed" assumption) and will be reported, not silently discarded.

### Decision: FastBreakout results kept in a separate track throughout

Every FastBreakout Stage B config (canonical and all 8 factor variants) uses the D019 research-eligibility override (`InpResearchMinScoreOverride=3.5`, `InpAcknowledgeResearchOverride=true`) and is reported, classified, and tabulated separately from the other seven strategies' canonical-production-eligibility results — never blended into a combined table or used to argue FastBreakout is production-ready. This mirrors D019's own separation of research output from canonical masters.

### Decision: robustness classification is a fixed four-way rule applied per (strategy, factor), not a ranking

`ROBUST_POSITIVE` (canonical positive, both neighbors positive or one positive/one approximately flat, no cliff, not wholly a 2026Q1 artifact), `MIXED_OR_REGIME_DEPENDENT` (full-window positive but a neighbor negative, or positive only because of 2026Q1, or long/short instability), `ROBUST_NEGATIVE` (canonical and both neighbors negative), `UNRESOLVED` (too few trades, structurally ineligible, data-integrity failure, or materially different execution conditions). Applied mechanically from the reported numbers per strategy/factor — the point is to surface plateaus versus isolated winning cells, not to rank cells by expectancy.

### Decision: ex-2026Q1 recomputation is mandatory for every strategy, not just the flagged ones

Given D022's finding that 2026Q1 alone can exceed 100% of a strategy's total cumulative exit-model profit, every Stage B run's temporal segmentation includes an explicit "does the full-window result remain positive with 2026Q1 excluded" check, independent of the exit-model question — this is an entry-strategy-level concentration check, not a reuse of D022's exit-level numbers (Stage B's fixed-2R exit is a different (and simpler) exit than any D021/D022 model).

### Decision: cost stress only for ROBUST_POSITIVE survivors, after all 72 primary runs are validated

Running a cost-sensitivity sweep (baseline / +25% / +50% / +100% spread+commission equivalent) against every cell would triple-plus the run count for strategies already headed for rejection. Restricting it to strategies that clear `ROBUST_POSITIVE` classification on their canonical/neighborhood result keeps the additional runs proportionate to the decision actually being made (is a real candidate's edge cost-fragile), and happens only after the full 72-run primary grid is complete and reviewed, per explicit instruction not to blend this with Phase 2 exit work.

### Run integrity requirements (per-run, before any result is trusted)

Every run must independently confirm, before its numbers are used: correct `strategy_id` (exactly one `InpEnable*=true`), correct varied factor (exactly the one factor differs from canonical; all others match), full-window completion verified via the terminal log's own new-success-line count (never inferred from process exit alone), final trade's `close_time` reaches `2026.07` (the expected final month — anything short is treated as truncated and rerun), a fresh output hash (no stale sandbox file silently reused from a previous run), no duplicate/stale result, no Tester Agent sandbox port confusion (every existing agent directory is checked, never a hardcoded port), and no `NEEDS_MANUAL_RERUN` marker left over from a prior failed attempt. This reuses `Tools/StageA/run_stageA.sh`'s already-hardened verification logic (built during the Stage A wifi-drop and port-migration incidents) via a Stage-B-parameterized copy, rather than re-deriving these checks from scratch.

### Rejected alternatives

- **Importing Stage A's canonical numbers directly (D020's original plan)**: rejected this pass per the explicit exact-SHA requirement, even though the EA's trading logic is provably unchanged since Stage A — see canonical-rerun decision above.
- **Blending FastBreakout into the main 7-strategy comparison tables**: rejected — FastBreakout is not production-eligible under canonical scoring and must never be allowed to look like a peer result to the other seven.
- **Running the cost stress sweep against all 64+8 cells up front**: rejected as disproportionate; see cost-stress decision above.

### Testing / verification requirements

No new MQL5 code in this increment (D020's generator and D019's eligibility gate are both already tested). Verification is entirely at the run-integrity and results-analysis level described above; the analysis scripts used to build the neighborhood tables, temporal segmentation, and overlap comparisons are throwaway (not part of the git-tracked MQL5 tree), but their logic and every derived number are reported in full in this entry's results addendum once the 72 runs complete.

### Results addendum

**1. Starting SHA:** `e3949278d3cde6426cb0b95c4f4c1de338e8816a` (D022 commit). **2. Final SHA:** this commit (see commit metadata). **3. Runs planned:** 72 (64 D020 configs + 8 canonical reruns). **4. Runs completed:** 72/72. **5. Reruns required:** 2 transient `NOT VERIFIED` retries during the batch (terminal-log completion count didn't advance on the first attempt), both recovered cleanly on retry with no data loss — not a data-integrity issue, the harness's designed retry path working as intended. **6. Data-integrity failures encountered:** 0 genuine failures (0 `NEEDS_MANUAL_RERUN`, 0 truncated `close_time`, 0 missing output files). One class of apparent anomaly was investigated and resolved: 5 groups of byte-identical `MSZZ_TradeAnalytics.csv` outputs across different configs (e.g. `MediumBreakout_canonical` = `MediumBreakout_fastmult_08` = `MediumBreakout_fastmult_12` = `MediumBreakout_slowmult_30` = `MediumBreakout_slowmult_40`, all 514 trades, identical hash). Cross-checked against `StrategySuite.mqh`'s actual trigger logic: `MediumBreakout` fires purely off the Medium ZigZag engine's own breakout events, `SlowBreakout` purely off Slow, `FastBreakout` purely off Fast — none reference the other two speeds' ATR multiplier at all, so varying an unrelated speed's multiplier is *expected* to produce zero change, confirmed symmetric (both the low and high neighbor match canonical) in every one of these groups. This is a genuine structural finding, not sandbox contamination — verified further by confirming every OTHER pair of the 72 runs (2556 pairs) is hash-distinct, and that the *dependent* factors for these same strategies (e.g. `MediumBreakout`'s own `medmult`, `atrlen`) do produce different results as expected.

**7. Full 72-cell results:** committed in full under `Tools/StageB/results/<strategy>_<variant>/` (`MSZZ_TradeAnalytics.csv` + `MSZZ_RunSummary.csv` per cell); headline numbers below.

| Strategy | Canonical expectancy_r | PF | Trades | Best quarter | Best-quarter % of total | Positive ex-2026Q1? |
|---|---|---|---|---|---|---|
| FastMedConfluence | **+0.1261** | 1.245 | 224 | 2025Q3 | 31.7% | Yes |
| FastMedContext | +0.1010 | 1.195 | 235 | 2025Q3 | 40.6% | Yes |
| WeightedEnsemble | +0.0777 | 1.152 | 261 | 2026Q1 | 51.3% | Yes |
| FastBreakout (research-only) | +0.0798 | 1.157 | 261 | 2026Q1 | 46.1% | Yes |
| SlowBreakout | -0.0137 | 0.974 | 336 | 2025Q3 | -153.5% | Yes |
| MediumBreakout | -0.0414 | 0.924 | 513 | 2026Q2 | -50.1% | No |
| MedSlowContext | -0.0189 | 0.965 | 440 | 2025Q4 | -100.5% | No |
| NestedPullback | -0.0208 | 0.965 | 136 | 2026Q3 | -120.7% | No |

Notably, under Stage B's simple fixed-2R exit, the three strategies with a real edge do **not** show D022's extreme 2026Q1 concentration — best quarter is 2025Q3 for two of the three, and every single one of FastMedConfluence's 9 neighborhood cells remains positive with 2026Q1 excluded. The 2026Q1 concentration problem found in D022 is specific to the `TRAIL_0_5R_AFTER_1R` exit model, not inherent to these entry strategies.

**8. Per-strategy robustness classifications** (4 factors × 8 strategies = 32 classifications; low/canonical/high = the 3-point neighborhood per factor):

| Strategy | atrlen | fastmult | medmult | slowmult |
|---|---|---|---|---|
| FastMedConfluence | ROBUST_POSITIVE | ROBUST_POSITIVE | ROBUST_POSITIVE | ROBUST_POSITIVE |
| FastMedContext | ROBUST_POSITIVE | MIXED (cliff at fastmult_08=-0.004) | ROBUST_POSITIVE | ROBUST_POSITIVE |
| WeightedEnsemble | MIXED (cliff at atrlen_10=-0.011) | MIXED (cliff at fastmult_08=-0.013) | ROBUST_POSITIVE | ROBUST_POSITIVE |
| FastBreakout (research) | MIXED (cliff at atrlen_10=-0.017) | MIXED (cliff at fastmult_08=-0.011) | ROBUST_POSITIVE | ROBUST_POSITIVE (all 3 identical, slow-independent) |
| SlowBreakout | MIXED (canonical neg, neighbors pos) | ROBUST_NEGATIVE | MIXED (canonical neg, medmult_16 pos) | ROBUST_NEGATIVE |
| MediumBreakout | MIXED (canonical neg, atrlen_10 barely pos) | ROBUST_NEGATIVE (fast-independent) | MIXED (canonical neg, medmult_16 pos) | ROBUST_NEGATIVE (slow-independent) |
| MedSlowContext | ROBUST_NEGATIVE | ROBUST_NEGATIVE (fast-independent) | MIXED (canonical neg, both neighbors pos) | ROBUST_NEGATIVE |
| NestedPullback | ROBUST_NEGATIVE | ROBUST_NEGATIVE | MIXED (medmult_16 pos, medmult_24 neg — cliff, not plateau) | ROBUST_NEGATIVE |

Interpretive note: the classification rules as given don't name a bucket for "canonical negative, a neighbor positive" — resolved as `MIXED_OR_REGIME_DEPENDENT` (an unstable sign flip across the neighborhood is definitionally not "robust" in either direction). Neighborhood summary stats (positive-cell count, median/worst/best expectancy, PF/DD range, %positive, %positive-ex-2026Q1) for all 32 rows are in `stageB_classification.json`-equivalent form, summarized in the per-strategy sections below.

**9-10. Temporal concentration / ex-2026Q1 results:** see table in point 7; full per-quarter (trades, expectancy, PF, cumulative R, long/short split) tables for all 72 runs were computed and reviewed — no strategy other than the four already-rejected ones shows a full-window-positive-but-ex-2026Q1-negative pattern, i.e. none of the three viable candidates are "only positive because of 2026Q1."

**11. Long/short robustness:**
- **FastMedConfluence**: long expectancy positive in all 9 grid cells (+0.031 to +0.249); short expectancy positive in 8 of 9, with one exception — `medmult_24`'s short side is -0.123 (masked by a strong +0.249 long side keeping the cell net positive). One real, narrow fragility, not a broad instability.
- **SlowBreakout**: never bidirectionally positive anywhere in the grid — short expectancy is negative in 7 of 9 cells; wherever the strategy shows an edge, it is long-only.
- **NestedPullback**: the most extreme and consistent asymmetry found — long expectancy is strongly positive in literally every one of the 9 cells (+0.035 to +0.326) while short expectancy is strongly negative in every one of the 9 cells (-0.066 to -0.389). This never narrows anywhere in the tested neighborhood; it reads as a structural short-side defect in the strategy's own logic, not a parameter-sensitivity issue.
- **MediumBreakout**: negative on both long and short at canonical (-0.024 / -0.058); no cell shows a genuinely bidirectional edge.

**12. Occupancy findings:** time-based occupancy (% of the backtest window with a position open — computed directly from fill/close timestamps, since Stage B did not preserve the per-signal journal that D021/D022's skip-based occupancy% required) for FastMedConfluence ranges 32.2%–41.6% across its 9-cell neighborhood — a stable band, not wildly different cell to cell. **Limitation, stated honestly:** whether occupancy is *protective* in the D021/D022 sense (skipped signals underperforming taken ones) cannot be assessed for Stage B without rerunning the signal-journal-preserving harness; this was out of scope for a single-strategy grid run and is flagged as a gap, not silently assumed either way.

**13. Strategy-overlap findings** (canonical cells, matched by the EA's own `cluster_id`, which is identical across strategies for the same underlying signal): FastMedConfluence/FastMedContext/WeightedEnsemble share the overwhelming majority of their trades (FMC∩FMCtx 95.5%/91.1%, FMC∩WE 92.4%/79.3%, all three simultaneously 203 trades). Decomposition:
- **WeightedEnsemble**: 79.3% of its trades are shared with FastMedConfluence (expectancy +0.180 on the shared slice) — its 54 *unique* trades (20.7%) have expectancy **-0.313**. WeightedEnsemble's positive headline number is carried entirely by trades FastMedConfluence already takes; its own incremental contribution is a net drag.
- **FastMedContext**: 91.1% shared with FastMedConfluence (expectancy +0.176 on the shared slice) — its 21 unique trades (8.9%) have expectancy **-0.664**, an even sharper negative than WeightedEnsemble's unique slice.
- **FastMedConfluence** itself: only 6 of its 224 trades (2.7%) are unique to it (not present in either other strategy) — expected, since it's the base signal the other two are built from.

**Conclusion: both WeightedEnsemble and FastMedContext are redundant with FastMedConfluence, not independently robust** — their unique, non-overlapping trades actively lose money rather than adding edge, exactly the pattern the task's own decision rule calls out.

**14. Cost-stress results for survivors:** run against FastMedConfluence and FastMedContext canonical (the two strategies with a ROBUST_POSITIVE majority across factors) — WeightedEnsemble and FastBreakout were excluded (2-of-4 ROBUST_POSITIVE each, not majority-robust; FastBreakout is additionally a separate research track). Method: the live EA has no cost-scaling input (Model=2's spread is real historical tick data already embedded in every trade's `r_result`); stress is applied post-hoc as an additional synthetic round-trip cost of 0.25×/0.50×/1.00× of D021's own documented flat-cost estimate (`InpEstimatedCostR=0.02R`), i.e. -0.005R/-0.01R/-0.02R subtracted from every trade — an honest proxy for cost sensitivity, not a re-simulation of fills under a wider spread path.

| Strategy | Baseline | +25% | +50% | +100% |
|---|---|---|---|---|
| FastMedConfluence expectancy_r (PF) | 0.1261 (1.245) | 0.1211 (1.233) | 0.1161 (1.222) | 0.1061 (1.201) |
| FastMedContext expectancy_r (PF) | 0.1010 (1.195) | 0.0960 (1.184) | 0.0910 (1.174) | 0.0810 (1.153) |

Both degrade **gradually and linearly**, never approaching zero or collapsing, even at +100% synthetic stress (a doubling of D021's own cost estimate). Cost fragility is not a concern for either survivor at this level of stress.

**15. Strategies rejected:** MediumBreakout, SlowBreakout, MedSlowContext, NestedPullback — each is `ROBUST_NEGATIVE` or has no genuine multi-factor plateau (isolated single-cell positives inside an otherwise negative neighborhood, which the task's own rule explicitly says not to use as a rescue). NestedPullback in particular shows a severe, parameter-independent long/short asymmetry that looks like a structural defect rather than a tuning problem.

**16. Strategies remaining candidates:** **FastMedConfluence** (primary, genuinely robust). FastMedContext and WeightedEnsemble are demoted from "candidate" to "redundant" per the overlap finding — they should not be pursued as independent strategies going forward, though FastMedConfluence's own robustness is reinforced by the fact that two heavily-overlapping variants of it also test positive. FastBreakout remains an open, separate research question (genuine-looking edge under the research override, per point 17 below) but is explicitly not production-eligible.

**17. Does FastMedConfluence have a genuine plateau?** Yes, with a precise caveat on shape: all 9 grid cells (canonical + 8 neighbors) are expectancy-positive, PF > 1.0, and remain positive excluding 2026Q1 — a genuine plateau in the sense of "no cliffs, no cell fails." However, canonical is the *peak* (or tied for peak) of 3 of its 4 factor neighborhoods, not necessarily centered in a flat plain — expectancy declines somewhat moving away from canonical in most directions (most sharply on `fastmult`, where the range is 0.112R, the largest of the four factors — `fastmult_08` at +0.014R is the closest thing to a soft edge in the whole grid, though it never turns negative). This is better described as a "positive dome centered at canonical" than a perfectly flat plateau — a materially more reassuring shape than an isolated spike, but not literally flat.

Answering the 8 explicit questions:
1. **Positive across most neighboring settings?** Yes — 9/9 cells positive.
2. **PF > 1.0 across most settings?** Yes — 9/9 cells, PF range 1.03–1.27.
3. **Remains positive without 2026Q1?** Yes, in all 9 cells.
4. **Largest performance cliff?** `fastmult` (range 0.112R; `fastmult_08` dips to +0.014R, PF 1.03 — the softest point in the grid, though still positive).
5. **Is canonical near the center of a stable plateau?** Partially — canonical is at/near the top in 3 of 4 factors (a "dome" shape), truly centered only in `medmult` (where `medmult_16` at +0.134R actually exceeds canonical).
6. **Are longs and shorts both stable?** Mostly — long is positive in all 9 cells; short is positive in 8 of 9, with `medmult_24` showing a real short-side breakdown (-0.123) masked by a strong long side.
7. **Does holding time remain operationally acceptable?** Median holding time is fine (95–220 minutes across the grid, ~1.5–3.7 hours) — but p90 holding time is 3360–4610 minutes (56–77 hours, i.e. 2.3–3.2 days) in every cell. The long tail flagged as a concern back in D021's original motivation is **not resolved** by Stage B's fixed-2R exit (Stage B never touched the exit) — it's an independent, still-open problem for Phase 2.
8. **Does occupancy remain protective across neighboring settings?** Cannot be answered for Stage B (see point 12's stated limitation) — time-based occupancy is stable (32–42%) across the neighborhood, but the skip-based "protective" question needs the signal journal, which this harness did not preserve.

**18. Is FastMedContext independent or redundant?** **Redundant** — 91.1% trade overlap with FastMedConfluence, and its 21 unique trades have expectancy -0.664R. It is not contributing anything FastMedConfluence doesn't already provide.

**19. Does WeightedEnsemble add independent edge?** **No** — 79.3% overlap with FastMedConfluence, and its 54 unique trades have expectancy -0.313R. Its apparent robustness (2 of 4 factors ROBUST_POSITIVE) is inherited almost entirely from FastMedConfluence, not from anything the ensemble weighting adds.

**20. Are Phase 2 structural exits justified?** For **FastMedConfluence specifically**, yes, cautiously: Stage B independently confirms a robust entry-side edge using a completely different, much simpler exit (fixed 2R) than D021/D022's `TRAIL_0_5R_AFTER_1R` model — two different exit frameworks now agree FastMedConfluence's entries have genuine edge, which is stronger evidence than either study alone. Combined with D021/D022's finding that a smarter exit (`TRAIL`) improves on the fixed-R baseline, Phase 2 work is justified **for FastMedConfluence only** — not for FastMedContext or WeightedEnsemble (redundant), and not yet for FastBreakout (separate research track, still not production-eligible).

**21. Is additional history or cross-market testing required before any edge claim?** Yes, unambiguously. This entire study — Stage A, D021/D022, and Stage B — covers one symbol (XAUUSD), one broker/demo feed, and a single ~17-month window with heavy internal overlap between "three strategies" that turn out to be one real signal wearing different names. No claim of a proven edge is warranted from this evidence alone; the next-highest-value work is out-of-sample / cross-market / longer-history validation of FastMedConfluence specifically, not further parameter search on the current sample.

### Explicit scope statement

Per instruction: **no proven edge is claimed from Stage B alone.** This entry documents robustness evidence and redundancy findings on a single-symbol, single-window sample. No merge to `main`.

## D024 — FastMedConfluence Phase 2 exit and holding-tail study

**Date:** 2026-07-27
**Status:** Accepted

### Scope of this increment

Following D023's acceptance, FastMedConfluence is now the sole primary production research candidate; FastMedContext and WeightedEnsemble are demoted (redundant, not independent); MediumBreakout/SlowBreakout/MedSlowContext/NestedPullback are rejected from the active path; FastBreakout stays a clearly separate research-only track. This increment builds and offline-replays 12 causal exit models against FastMedConfluence's canonical entries only, to try to reduce the ~56-77h p90 holding time found in D021/D022/D023 without materially damaging expectancy, PF, or drawdown. **Entry logic, canonical ATR settings, score logic, signal eligibility, one-owned-position policy, and the structural-stop definition are frozen — this pass changes exits only, never re-tunes entries.** No live EA changes and no merge to `main` in this pass; at most 2 survivors get selected for a *future* live-wiring pass.

### Decision: reuse the ZigZag engine's algorithm via a duplicated, equivalence-tested causal scan, never modify the live engine

`CMSZZTripleZigZagEngine::Rebuild()` is already a single forward O(n) pass over a full rates array that only ever uses `rates[0..i]` to confirm a pivot at step `i` (verified by reading `BuildSpeed()` in full: ATR lookback is bounded, extreme-tracking is monotonic from a directional start, `ConfirmHigh`/`ConfirmLow` fire exactly once per confirmed swing in chronological scan order) — the engine is therefore already fully causal and non-repainting by construction, exactly as documented in earlier decision log entries. Its public API, however, only exposes the *final* snapshot (last two highs/lows) after a full `Rebuild()`, not the intermediate timeline of every pivot confirmed along the way — which Phase 2's structural exits need (to know, bar by bar during replay, "what was the most recently confirmed swing at this point in history").

Rather than modify `TripleZigZagEngine.mqh` (live-EA-critical, extensively tested, and the entire point of this session's discipline has been never touching that class without exhaustive regression), a new research-only file duplicates `BuildSpeed`'s scanning loop verbatim into a function that appends every confirmed pivot (with its `pivot_time` and `confirmed_time`) to an output array instead of only keeping the last two. A dedicated test asserts the duplicated scan's *final* state (last high/low/leg direction) is byte-identical to the real engine's `Snapshot()` on the same input across multiple synthetic and real-data cases — this is the safeguard against silent algorithmic drift between the two copies. The live engine file is not touched in this increment.

### Decision: ground every structural model definition in the code that already exists, not a fresh invention

`CMSZZStrategySuite::LongStop`/`ShortStop` (used for every FastMedConfluence entry today) derive the initial structural stop from the **Medium** engine's last confirmed low/high (falling back to Fast only if Medium is invalid). This grounds two design choices:
- The **ATR Chandelier trail** (model 1) uses the same canonical Medium ATR configuration (`MedATRLen=14`, `MedATRMult=2.0`) as its basis — trail = highest-high-since-entry minus `MedATRMult × ATR(MedATRLen)` for longs (mirror for shorts), never widening. This reuses an already-canonical constant rather than inventing a new one.
- **Model 3 (Medium ZigZag confirmed-swing trail)** and **model 4 (previous confirmed HL/LH trail)** are deliberately distinct, not duplicates: model 3 ratchets to the Medium engine's latest same-direction swing extreme *regardless of its HH/HL/LH/LL classification* (any new low for a long, any new high for a short); model 4 only ratchets when the newly confirmed swing carries the *constructive* structure label (`MSZZ_STRUCT_HL` for a long, `MSZZ_STRUCT_LH` for a short) — i.e. model 4 requires the market to be making a confirmed higher-low (long) / lower-high (short), not merely any new extreme, which can differ meaningfully during a choppy or reversing leg.
- **Model 2 (Fast ZigZag confirmed-swing trail)** is model 3's same logic against the **Fast** engine instead of Medium.
- **Model 5 (opposite Fast-structure exit)** reuses the *exact* breakout-detection the live EA already uses for entries (`bullish_break`/`bearish_break`, a confirmed close beyond the Fast engine's projected structure line) — exit a long the moment Fast's `bearish_break` fires, exit a short the moment `bullish_break` fires. This is "the same signal that would make the EA enter the opposite direction," not a new invented reversal rule.
- **Model 10 (trail only after +1R)** reuses D021/D022's already-implemented and already-sequencing-fixed `TRAIL_0_5R_AFTER_1R` model verbatim (trigger 1.0R, distance 0.5R) — chosen deliberately for direct comparability with the D021/D022 finding, not a new untested distance.
- **Model 9 (fixed 2R plus stale-trade timeout)** combines the existing `FIXED_2R` model with a 24h time cap (first of target/stop/24h wins) — reuses D021/D022's `FIXED_2R` and `TIME_24H` logic combined, not new logic.
- **Model 11 (breakeven at +1R plus structural trail)** combines D021/D022's `BE_1R` arming with model 3's Medium-swing ratchet applied only once armed and only ever improving the stop.
- **Model 12 (session-aware overnight exit)** is deliberately distinct from D021's `SESSION_CLOSE` (which exits at *every* 8h session boundary): model 12 exits only at the transition into the lowest-liquidity session bucket (reusing D016's `CMSZZTradeAnalyticsPolicy::SessionBucket`), i.e. targets genuine overnight/gap risk once per calendar day rather than every session change.
- **Models 6-8** (max holding time 8h/12h/24h) are D021/D022's already-implemented, already-`entry_time`-anchored `TIME_8H/12H/24H` models, reused verbatim.

### Decision: every structural model inherits D022's exact same-bar sequencing discipline, uniformly

The same-bar activation bug D022 fixed for `BE_*`/`TRAIL_0_5R_AFTER_1R` generalizes directly to every structural model here: a bar's stop is evaluated **as it stood at that bar's open** against old-stop/target first (pessimistic: adverse wins on ambiguity, deferred exit-only-not-BE-arm on old-stop-hit); only a bar that survives may use a pivot **confirmed at or before that bar's own close** to compute a candidate new stop, which becomes executable no earlier than the *next* bar — never the bar that produced the confirming pivot, and never widened once armed. Any bar where the old stop survives but the same-bar proposed new stop would also have been touched is flagged `sequencing_ambiguous` with both bounds reported, exactly as D022 established. Tick-resolved replay remains declared-but-unavailable (D021's tick-coverage probe already found none for this window) — `OHLC_PESSIMISTIC` is the primary evidence path for every model; `OHLC_OPTIMISTIC` is computed as the explicit upper bound only.

### Decision: fresh signal/journal capture, not reuse of D021's or D023's exports

Neither D021's original FastMedConfluence signal set nor D023's Stage B rerun preserved `MSZZ_SignalJournal.csv` out of the Tester sandbox (D023's harness only copied `MSZZ_TradeAnalytics.csv`/`MSZZ_RunSummary.csv`, discovered as a gap while writing that entry's occupancy-findings section). A fresh Tester run of FastMedConfluence's canonical Stage B config additionally preserves the signal journal this time, and `SignalSetExporter.mq5` (D021, unmodified) builds a fresh SIGNAL_LEVEL set from it at the current commit SHA — consistent with D023's own exact-SHA discipline rather than importing an older export.

### Metrics and success criteria

Every required metric (expectancy_R, PF, max drawdown_R, median/p90 holding time, %>8h/12h/24h, return/exposure-hour, occupancy%, skipped-signal count, MFE-until-exit, peak-to-exit surrender, long/short split, quarterly results, ex-best-quarter results, cost stress, ambiguity count) is computed per model, both SIGNAL_LEVEL and PORTFOLIO_LEVEL, reusing D021/D022's already-built aggregation helpers (`CMSZZRunSummaryPolicy`) wherever the shape matches. Success criteria applied mechanically before any model is called a survivor: expectancy ≥ 80% of the fixed-2R canonical baseline (+0.1261R × 0.8 = **+0.1009R** floor), PF > 1.10, p90 holding time materially reduced from baseline (56-77h), no single-quarter dependency (must remain positive ex-best-quarter), no new long/short breakdown beyond what canonical already shows, no immediate cliff at neighboring trigger/distance choices tested. No more than 2 models are selected as survivors for a future live-wiring pass; nothing is wired into the live EA in this increment.

### Rejected alternatives

- **Modifying `TripleZigZagEngine.mqh` to expose pivot history directly**: rejected — touching the live-critical, already-tested engine class for a research-only need is disproportionate risk; a verified-equivalent duplicate is safer and keeps the live EA provably untouched.
- **Reusing D021's original FastMedConfluence signal set**: rejected per the same exact-SHA reasoning D023 already established for canonical cells.
- **Letting every model pick its own arbitrary ATR/distance constants**: rejected in favor of reusing already-canonical values (Medium ATR config, D021/D022's 0.5R/1.0R trail constants) wherever a reasonable reuse exists, to avoid introducing untested new parameters disguised as exit "logic."

### Testing requirements

Structural-scan equivalence test (duplicated scan vs. real engine, multiple synthetic + real-data cases). Deterministic causal-sequencing tests for every new model family (Chandelier ratchet-never-widens, Fast/Medium swing-trail activation-bar-survives-first, HL/LH-label-filtering distinguishing model 3 from model 4, opposite-structure-exit fires exactly on `bearish_break`/`bullish_break`, combined models 9/11 resolve ties correctly, session-aware model 12 only fires at the lowest-liquidity transition not every boundary), plus the full D022-style sequencing-ambiguity suite (old-stop-before-activation, same-bar trigger-and-new-stop-touch, pessimistic-vs-optimistic divergence, no-lookahead) applied per new model family.

### Two real bugs found and fixed during verification (before any result was trusted)

**Bug 1 — stale/wrong-side ZigZag swing accepted as a trail candidate.** The very first full offline run produced impossible numbers (`FAST_SWING_TRAIL` SIGNAL_LEVEL expectancy +1.18R, PF 3.49; `MEDIUM_SWING_TRAIL` +0.70R, PF 2.37). Root cause: `CMSZZTripleZigZagEngine`'s "last confirmed low/high" can legitimately be *stale* — during a sustained, un-reversed decline, `last_low` still holds the older, higher swing from before the decline began, which can sit **above** current price. `SwingTrailCandidate()` was accepting this as a valid long trailing-stop level purely because it was numerically "better" than the original stop, without checking it was on the correct side of the market — producing a stop placed above price, guaranteeing an immediate spurious "stop-out" that computed as a >100R fake profit via `RMultiple`. Fixed by requiring a candidate be strictly on the correct side of the current bar's close (`< close` for longs, `> close` for shorts) before it can be accepted at all. A dedicated regression test (`TestSwingTrailRejectsStaleWrongSideSwing`) now guards this.

**Bug 2 — off-by-one model-index mapping in the live script.** `ExitSimulatorPhase2.mq5` mapped model index `m` to the `MSZZPhase2Params` array via `pidx=(m<9)?m:m-1`, intended to skip the unused slot for the delegated `TRAIL_AFTER_1R` model (index 9). This was wrong for indices 10 and 11: `BE_1R_PLUS_TRAIL` (m=10) silently ran against `p2[9]` — uninitialized/garbage parameters that happened to resolve to a degenerate zero-multiplier Chandelier trail (locking in almost the exact entry-bar extreme as a stop) — while `SESSION_OVERNIGHT` (m=11) silently ran `BE_1R_PLUS_TRAIL`'s real parameters instead of its own logic. Caught via the same implausible-output review (`BE_1R_PLUS_TRAIL` showing a 75% win rate and PF 6.8). Fixed by removing the shift entirely (`pidx=m`, since `p2[]` is already indexed identically to `g_model_names[]` and slot 9 is simply never read). **Neither bug affected any already-tested code path** — `SwingTrailCandidate`'s unit tests all used data where the stale-swing case didn't arise, and the index bug was purely in the live script's wiring, not in `ExitModelsPhase2.mqh` itself.

Both fixes were cross-validated against two independent known-good baselines before trusting any further numbers: `TRAIL_AFTER_1R` (delegates directly to D021/D022's already-certified `SimulateExit`) reproduced D022's exact `ambiguous_count=92` for FastMedConfluence on the fresh signal set, and `FIXED_2R_PLUS_TIMEOUT`'s magnitude landed in the same ballpark as D022's committed plain `FIXED_2R` result (both near-flat-to-slightly-negative at the full-signal-population level, for the methodological reason described below) — not the wild multi-R-per-trade numbers the bugs were producing.

### Results

**Methodological finding, stated up front because it reframes every number below:** the SIGNAL_LEVEL/PORTFOLIO_LEVEL replay population (530 signals — every `EXECUTED ∪ REJECT_OWNERSHIP` row from a fresh journal capture) is **not the same population** as Stage B's canonical live-EA run (224 executed trades, the source of the `+0.1261R` baseline this study's success criteria were framed against). This is the exact same phenomenon D021 was built to expose in the first place: a given exit choice's own occupancy dynamics determine which signals from the full population actually get taken, so no single fixed trade list is "the" entry set across different exits. Confirmation: D022's own committed plain `FIXED_2R` model (functionally identical to this study's `FIXED_2R_PLUS_TIMEOUT`, since the 24h cap essentially never intervenes before a 2R/stop resolution) shows PORTFOLIO_LEVEL expectancy of **-0.0726R** against the full signal population — nowhere near the live-EA's `+0.1261R`. **The fair comparison for these 12 new models is therefore against this replay methodology's own fixed-2R-equivalent baseline (`FIXED_2R_PLUS_TIMEOUT`, PORTFOLIO_LEVEL +0.0006R), not directly against the `+0.1261R` Stage B number** — both are reported below so the reader can judge either way, but the literal 80%-of-baseline floor as originally specified (against +0.1261R) is not a population-matched comparison and is noted as such rather than silently applied as if it were.

**Full PORTFOLIO_LEVEL results, all 12 models** (SIGNAL_LEVEL numbers, quarterly tables, long/short splits, and MFE/surrender detail for every model are in the committed trade-level CSV; headline table below):

| Model | n | expectancy_r | PF | max DD_R | median hold | p90 hold | %>8h | %>12h | %>24h | ex-best-Q | ambiguous |
|---|---|---|---|---|---|---|---|---|---|---|---|
| CHANDELIER_TRAIL | 392 | -0.0212 | 0.91 | 19.6 | 25min | **85min** | 0% | 0% | 0% | -0.040 | 116 |
| FAST_SWING_TRAIL | 176 | +0.0087 | 1.02 | 15.6 | 115min | 4065min (67.8h) | 35% | 28% | 18% | -0.007 | 87 |
| MEDIUM_SWING_TRAIL | 195 | +0.0051 | 1.01 | 19.2 | 110min | 3035min (50.6h) | 28% | 22% | 14% | -0.037 | 39 |
| HL_LH_TRAIL | 188 | +0.0082 | 1.01 | 20.0 | 148min | 3295min (54.9h) | 29% | 24% | 15% | -0.047 | 33 |
| OPPOSITE_FAST_EXIT | 176 | **+0.0337** | **1.06** | 14.9 | 150min | 4065min (67.8h) | 37% | 31% | 19% | **+0.008** | 0 |
| TIME_8H | 209 | -0.0613 | 0.88 | 22.8 | 480min | 490min (8.2h) | 11% | 8% | 8% | -0.090 | 0 |
| TIME_12H | 182 | +0.0054 | 1.01 | 24.2 | 720min | 720min (12h) | 58% | 10% | 9% | -0.047 | 0 |
| TIME_24H | 173 | **+0.0584** | **1.09** | 25.0 | 800min | 3035min (50.6h) | 57% | 51% | 11% | -0.018 | 0 |
| FIXED_2R_PLUS_TIMEOUT | 187 | +0.0006 | 1.00 | 18.2 | 300min | 1440min (24h, capped by construction) | 46% | 41% | 8% | -0.033 | 0 |
| TRAIL_AFTER_1R (D021/D022) | 168 | +0.0298 | 1.06 | 10.6 | 140min | 3820min (63.7h) | 35% | 29% | 20% | +0.007 | 92 |
| BE_1R_PLUS_TRAIL | 160 | -0.0305 | 0.94 | 14.4 | 185min | 3965min (66.1h) | 38% | 32% | 21% | -0.058 | 31 |
| SESSION_OVERNIGHT | 140 | -0.0986 | 0.86 | 24.0 | 275min | 4305min (71.8h) | 44% | 39% | 26% | -0.149 | 31 |

**Success-criteria screen** (expectancy ≥ 80% of Stage B's +0.1261R = +0.1009R floor; PF > 1.10): **not one of the 12 models clears both bars.** Against the population-matched (`FIXED_2R_PLUS_TIMEOUT`, +0.0006R) baseline instead, three models show real relative improvement: `TIME_24H` (+0.0584R, PF 1.09), `OPPOSITE_FAST_EXIT` (+0.0337R, PF 1.06), and `TRAIL_AFTER_1R` (+0.0298R, PF 1.06) — the latter two are also the only models whose expectancy stays positive with the best quarter excluded, the strongest single robustness signal in this batch.

**Primary objective (reduce p90 holding time without materially damaging expectancy) is not cleanly achieved by any model.** The pattern is a stark trade-off, not a win: models that dramatically cut holding time (`CHANDELIER_TRAIL` at 85 minutes, `TIME_8H` at 8.2 hours) have negative expectancy; models with the best expectancy (`TIME_24H`, `OPPOSITE_FAST_EXIT`, `TRAIL_AFTER_1R`) barely move the p90 tail (50.6-67.8 hours, versus the ~56-77h that motivated this whole study). `TIME_24H` is the best-balanced compromise (p90 cut to 50.6h from the original range, positive expectancy, best PF of the batch) but even it doesn't represent a clean win on both axes simultaneously.

**Cost stress** (same D023 proxy methodology — additional synthetic round-trip cost of 0.25×/0.50×/1.00× of D021's 0.02R flat estimate) on the two best relative performers:

| Model | Baseline | +25% | +50% | +100% |
|---|---|---|---|---|
| TIME_24H | +0.0584 (PF 1.09) | +0.0534 (1.08) | +0.0484 (1.08) | +0.0384 (1.06) |
| OPPOSITE_FAST_EXIT | +0.0337 (1.06) | +0.0287 (1.05) | +0.0237 (1.04) | +0.0137 (1.02) |

Both degrade gradually, staying PF>1.0 even at +100% stress — neither is cost-fragile, for whatever that is worth given neither clears the primary success bar.

### Survivor selection

Per instruction, select no more than 2 survivors even though none pass the strict floor: **`TIME_24H` and `OPPOSITE_FAST_EXIT`** are named as the two most promising candidates for further study — best expectancy/PF in the batch, positive (or near-zero, in `TIME_24H`'s case slightly negative at -0.018) results excluding their best quarter, and (`OPPOSITE_FAST_EXIT` specifically) zero sequencing ambiguity since it is a discrete exit condition rather than a trail. This is **not** a claim that either is ready for live wiring — see explicit scope statement below. `TRAIL_AFTER_1R` (D021/D022's already-vetted model) remains a reasonable third reference point but is not "new" to this study.

### Recommended next step before any live wiring

Rerun `TIME_24H` and `OPPOSITE_FAST_EXIT` against the **live-EA's own actually-executed trade population** (not the full SIGNAL_LEVEL/PORTFOLIO_LEVEL replay set) for a population-matched comparison against the real +0.1261R baseline — this requires either instrumenting the live EA to journal which of its real executed trades would have exited earlier under each candidate model, or accepting the replay population's own (lower) baseline as the correct frame of reference going forward. Given neither candidate cleanly solves the original holding-time problem, longer/out-of-sample history (per D023's own closing recommendation) is likely higher-value next research than iterating further on Phase 2 exit variants against the current single-window sample.

### Explicit scope statement

No exit model from this study is implemented into the live EA. No merge to `main`. Per instruction, no production-ready edge is claimed — the primary objective (cut the holding-time tail without damaging expectancy) is not achieved by any of the 12 models tested, and the two named "survivors" are relative-best-in-batch, not validated candidates.

## D025 — Canonical strategy decomposition and full-EA equivalence

**Date:** 2026-07-27
**Status:** Accepted
**Supersedes:** whatever "D025" would otherwise have been scoped as a continuation of D024's exit-model work — this entry replaces that plan entirely, per explicit instruction to pause it.

### The core finding, confirmed against source before anything else

D024's fixed-2R-equivalent offline baseline (`FIXED_2R_PLUS_TIMEOUT`, PORTFOLIO_LEVEL ≈ flat, PF ≈ 1.00) was compared against Stage B's canonical live-EA result (`+0.1261R`, PF `1.2446`) as if they measured the same mechanism. **They do not.** Verified directly in `Experts/MultiSpeedZigZagEA.mq5` and `Include/MultiSpeedZigZag/Execution/PositionOwnership.mqh` before writing anything further:

- `InpExitOwnedOpposite=true` is the default and what every Stage A/B canonical config used (never overridden to `false` anywhere in this branch's history).
- `ApplyOwnershipPreflight()` is called from `ExecuteCluster()` immediately before opening a new position, after every other gate (score, expiry, duplicate, recovery, safeguards, trading-allowed, spread, stops, volume, margin) has already passed.
- Inside it, `CMSZZPositionOwnership::CloseOwnedOpposite()` unconditionally fully closes (via `trade.PositionClose()`, not a partial close) every owned position in the direction opposite the new candidate, whenever `InpExitOwnedOpposite` is true and such a position exists — then, in the same `ExecuteCluster()` call, the new position opens if every remaining check still passes.

So Stage B's canonical FastMedConfluence result is not "structural SL + fixed 2R target, held to whichever hits first" — it is that, **plus** an unconditional close-and-immediately-reverse whenever a qualifying opposite-direction FastMedConfluence signal arrives while a position is open. None of D021, D022, or D024's offline exit simulators modeled this at all — they only ever resolved a trade's fate from its own OHLC path forward from entry, with zero awareness of a second, later, opposite signal arriving. This is a genuine, previously-undiscovered gap that invalidates the "no model beats baseline" framing in D024 to the extent that framing implied "fixed 2R" and "canonical" were the same mechanism. D024's actual findings about the 12 new structural/time models relative to *each other*, and relative to D021/D022's `TRAIL_0_5R_AFTER_1R`, are not invalidated by this — but the *baseline they were compared against* was not what it was labeled.

### Scope of this increment

**In scope:** exact reproduction of the canonical result with full artifact preservation; a genuine (not generic-`OTHER`) exit-reason classifier distinguishing structural SL, fixed TP, opposite-signal closes, and test-end liquidations; eight full-EA mechanism-decomposition variants (A-H) run with identical data/settings, differing only in the mechanism under test; two Tester execution models (the historical `Model=2` for exact reproduction, then "every tick based on real ticks" for every surviving variant, with coverage reported honestly); a full metrics matrix per variant including explicit attribution of the opposite-signal mechanism's contribution; and a baseline-equivalence gate for any offline analysis this entry relies on.

**Explicitly out of scope, per instruction:** no new structural/trailing exit models beyond what's needed for variants A-H; no wiring of any D024 survivor into the live EA; no parameter optimization (every variant is a mechanism decomposition, not a search); no merge to `main`.

### Decision: three of the eight variants require new EA code; the rest are pure config

Auditing what already exists before deciding what to build:

- **A (CANONICAL_2R_REVERSE)** = the unmodified canonical Stage B config. No change.
- **B (PURE_FIXED_2R)** = canonical with `InpExitOwnedOpposite=false`. Already a supported input; no code change.
- **E (CANONICAL_3R_REVERSE)** = canonical with `InpRiskReward=3.0`. No code change.
- **D (REVERSE_ON_OPPOSITE, "instrumented as a first-class policy")**: re-examined against what "instrumented" requires — the exit-reason classifier built for §1 (below) can already identify every opposite-signal close and its immediately-following reversal purely from the existing signal journal, trade analytics, and deal history, with no EA behavior change. Rather than add a redundant EA-side reversal-tagging feature that would just duplicate what post-hoc analysis already does correctly, **D is implemented as canonical (identical to A) re-analyzed through the classifier**, explicitly labeled as such. If the classifier cannot cleanly identify reversals this way, an EA-side tag will be added instead — this is the fallback, not the default plan.
- **C (EXIT_ON_OPPOSITE_NO_REVERSE)** requires new EA behavior: a new input `InpSuppressReversalEntry` (default `false`, so canonical behavior is provably unchanged unless explicitly enabled). When `true`, if the candidate currently in `ExecuteCluster()` is itself the one whose arrival caused `ApplyOwnershipPreflight()` to close an owned opposite position, the close is kept (matching the spec: "close when opposite signal arrives") but the subsequent open of that *same* triggering candidate is suppressed — journaled as a new status `SUPPRESSED_REVERSAL_ENTRY`, cluster still marked consumed (so it isn't retried), leaving the account flat until a **later, independent** cluster's own signal is evaluated on its own merits.
- **F (NO_FIXED_TP_REVERSE)** requires new EA behavior: a new input `InpDisableFixedTarget` (default `false`). When `true`, `PrepareMarketCandidate()` sets `target=0.0` instead of the RR-derived value, and `ValidateStops()`'s "non-positive target is invalid" / orientation checks are bypassed for this case — the position is opened with a structural stop and no take-profit at all, so it can only close via stop, opposite-signal reversal, or (in the offline sense) test end. Rejected alternative: setting `InpRiskReward` to an arbitrarily large number to make the target practically unreachable — works numerically (no maximum-distance check exists in `ValidateStops`) but is a hack disguising intent as a parameter value rather than an explicit mode, and risks pathological price/order-send behavior at extreme distances on some symbols. An explicit flag is clearer and safer.
- **G/H (PARTIAL_2R_RUNNER_REVERSE / PARTIAL_3R_RUNNER_REVERSE)** require new EA behavior: the EA has no partial-close capability today. New inputs `InpPartialCloseAtR` (`double`, `0.0`=disabled) and `InpPartialCloseFraction` (`double`, default `0.5`). A lightweight, explicitly **research-scoped, non-persistent** in-memory set of "already partially closed" ticket IDs (not integrated with the durable `ExecutionIntentStore`/`IntentStateMachine` machinery, since this is a mechanism-decomposition research variant, not a live-safety-critical feature) is checked on each tick for every owned position; once floating R crosses `InpPartialCloseAtR`, `trade.PositionClosePartial()` takes `InpPartialCloseFraction` of the volume, and the remainder continues to ride to stop or opposite-signal reversal exactly as before. Documented explicitly as a research simplification, matching this project's established practice (e.g. D019's research-eligibility override, D021's flat cost estimate) of being honest about scope-limited implementations rather than quietly presenting them as production-grade.

All five new inputs default to values that reproduce today's exact canonical behavior — none of this is reachable by any existing config, mirroring D019's fail-inert-unless-opted-in pattern.

### Decision: exit-reason classification is built from data already captured, not a new export format

Every trade's `exit_reason` in `MSZZ_TradeAnalytics.csv` is currently one of a small fixed set (`SL`, `TP`, `OTHER`, ...) written at the moment a position-close is detected, with no distinction for *why* `OTHER` occurred. Rather than guess from price alone, the classifier cross-references, per closed position: the close price against the position's own stop/target (near-exact match within a small tolerance → `SL`/`TP`); the signal journal for an `EXECUTED` opposite-direction FastMedConfluence candidate whose fill time coincides with this position's close time within the same tick/second → `OPPOSITE_SIGNAL_CLOSE`; the run's own end-of-test boundary time → `TEST_END`; anything left over is `OTHER_TRUE_UNKNOWN` and is expected to be rare-to-zero given the above three cover every code path that can currently close a position. Each `OPPOSITE_SIGNAL_CLOSE` is further matched to its triggering cluster ID (from the journal), the immediately-following position (if the same `ExecuteCluster()` call successfully opened one), and both the closed position's own realized R and the subsequent reversal trade's R, enabling the reversal-count/reversal-expectancy metrics required in §4.

### Decision: real-tick results are primary; Model=2 is the reproduction anchor only

Per instruction, the historical `Model=2` run is required first (to prove the canonical numbers reproduce exactly), but the decision-relevant comparisons across variants use "every tick based on real ticks" wherever coverage exists for the Stage A/B window. D021 already probed this window's tick coverage once and found essentially none (~124KB recent-activity cache against 17 months needed) — this entry re-probes rather than assumes that finding still holds, and reports the result honestly rather than silently falling back to `Model=2` and calling it real-tick.

### Decision: the baseline-equivalence gate applies to the exit classifier, not a new parallel simulator

Given this audit's primary evidence is full-EA Tester runs directly (not an offline exit-outcome simulator, which is exactly the machinery whose blind spot caused the original problem), the "reproduce the full-EA canonical result at the trade-ID level" gate in the instructions is satisfied by construction for the eight Tester-run variants (they *are* the EA) — it applies specifically to the post-hoc exit-reason classifier described above: before its output is trusted for any reported number, it must independently reconstruct the already-known canonical facts (224 trades, 107 long/117 short, matching aggregate expectancy) purely from the raw journal/deals/analytics files, with the first chronological mismatch (if any) investigated and explained rather than averaged away.

### Rejected alternatives

- **Patching D021/D022/D024's offline simulators to also model opposite-signal closes**: rejected — the whole point of this audit is to stop trusting an offline approximation for a mechanism this consequential; the full EA is the ground truth here, not a simulator retrofit.
- **Implementing variant D as new EA-side reversal tagging**: rejected as the default (see decision above) in favor of reusing the exit classifier; kept as an explicit fallback if the classifier can't do it cleanly.
- **Variant F via an extreme `InpRiskReward` value**: rejected in favor of an explicit `InpDisableFixedTarget` flag, for clarity and to avoid extreme-distance edge cases.
- **Durable partial-close tracking wired into `ExecutionIntentStore`**: rejected for this pass as disproportionate engineering for a bounded research variant; explicitly flagged as a limitation, not silently treated as production-ready.

### Testing requirements

Deterministic tests for each new EA-adjacent function: `InpSuppressReversalEntry`'s suppress-vs-normal-open branching (including that a later independent cluster is unaffected), `InpDisableFixedTarget`'s target=0 path through `ValidateStops`, and the partial-close threshold/fraction/already-closed-ticket logic. Full regression (all existing `Test_MSZZ_*.mq5` suites) plus shadow regression (short+long windows, identical RAW_CANDIDATE/SHADOW counts, 0 orders/deals) after each new EA input is wired, exactly matching this branch's established discipline for any live-EA-touching change — these are not research-only Include files, they modify `Experts/MultiSpeedZigZagEA.mq5` itself. The exit-reason classifier is tested against the canonical reproduction's own known facts before being trusted for any other variant's numbers (see baseline-equivalence-gate decision above).

### A third real bug found during implementation: partial closes silently discarded

Verifying variant G's very first result showed byte-identical output to variant F (which has partial-close disabled entirely) — impossible if the mechanism were doing anything. Root cause 1: `InpFixedLots=0.01` (this project's standard fixed lot size) equals XAUUSD's own broker minimum tradable volume, so a 50% partial close (0.005 lots) gets clamped back up to the full 0.01 by `NormalizeVolume()`, which the code's own safety check (`close_volume>=record.volume`) correctly refuses as "would close 100%, not a partial." Fixed by using `InpFixedLots=0.02` for variants G/H only (a pure execution-mechanics necessity — R-multiples are lot-size-invariant, so this doesn't touch the "no parameter optimization" instruction). Root cause 2, found immediately after: `DetectClosedPositions()` computed every trade's `r_result` from only the *last* exit deal's price, silently discarding any profit already banked at an earlier partial close. Since R-multiple is linear in price for a fixed entry/risk, the volume-weighted average price across *every* exit deal for a position gives the mathematically exact blended R — fixed in `DetectClosedPositions()` by accumulating `exit_price_volume_sum`/`exit_volume_sum` across all `DEAL_ENTRY_OUT`/`DEAL_ENTRY_OUT_BY` deals instead of tracking only the latest. This fix is a provable no-op for every normal (single-exit-deal) trade — confirmed by rerunning the canonical config after the fix and reproducing the exact same 224/+0.1261R/PF 1.2446/15.1583R/107L/117S result, byte-identical to before.

### Results

**1-2. Starting/final SHA:** starting `a08ae6e` (this entry's own decision-log commit); final SHA is this results commit.

**Exact canonical reproduction:** confirmed byte-identical across three independent runs (D024's fresh journal capture, this entry's initial rerun, and the post-partial-close-fix rerun): **224 trades, expectancy +0.1261R, PF 1.2446, max drawdown 15.1583R, 107 long / 117 short.** Full signal journal (1434 rows), trade analytics, run summary, and MT5 HTML report (with Deals/Orders tables) preserved under `Tools/D025/results/canonical/`.

**Exit-reason decomposition** (224 trades, no generic `OTHER` remaining): **93 SL, 69 TP, 62 OPPOSITE_SIGNAL_CLOSE, 0 TEST_END, 0 OTHER_TRUE_UNKNOWN.** Every one of the 62 opposite-signal closes is matched to its triggering cluster ID, the immediately-following reversal position (all 62 had one — canonical's `InpExitOwnedOpposite=true` never suppresses re-entry), the closed position's own realized R, and the reversal trade's own realized R.

**3. Opposing-signal exits:** 62, expectancy **-0.2702R** (a real, and on average substantial, loss taken early on these 62 positions — 27.7% of all canonical trades).

**4. Immediate reversals:** 62 (100% of opposite-signal closes reverse under canonical settings), expectancy **+0.0736R**. Non-reversal-involved trades (the 162 trades that resolved via plain SL/TP, i.e. never triggered or were triggered by an opposite-signal close) average **+0.1462R** — notably *higher* than the blended canonical average, confirming the opposite-signal mechanism's own trades (both the cut-short loser and its reversal) are individually less profitable than a "clean" SL/TP trade, but the mechanism still adds net value by existing at all (see point 6).

**5. Pure fixed-2R result (variant B, `InpExitOwnedOpposite=false`):** **89 trades, expectancy -0.0562R, PF 0.918, cumulative -5.00R.** Long side stays positive (+0.2955R, 44 trades) but **short side collapses to -0.4000R average (45 trades)** — without the reversal mechanism, FastMedConfluence is a net-losing strategy overall, driven by a catastrophic short-side breakdown. Occupancy effect: 441 signals rejected for ownership (vs. canonical's 306) — without the release valve of closing-then-reversing, the account sits in stale positions far longer (avg 300min median hold vs. canonical's 102min), starving the system of ~135 additional trades canonical would have taken.

**6. Canonical vs. pure-2R delta:** canonical cumulative **+28.24R** vs. pure-2R cumulative **-5.00R** — **the opposite-signal mechanism's contribution is +33.24R over the study window**, and it is *not* a subtle effect: it is the difference between a working strategy and a losing one. Trade count also differs by 135 (224 vs. 89), confirming D021's original insight (reused directly for D024, now proven decisively here) that different exit mechanisms produce genuinely different entry populations via occupancy, not just different outcomes on a fixed trade list.

**7. 2R vs. 3R with reversal retained (variant E):** **213 trades, expectancy +0.1467R, PF 1.253, cumulative +31.25R** — slightly *better* than canonical on every headline metric, with a healthier long/short balance (+0.2098R/101 long, +0.0898R/112 short, both clearly positive) than canonical's own long/short split. The reversal mechanism's value is not narrowly tied to the 2R target choice.

**8. No-TP-reversal result (variant F, `InpDisableFixedTarget=true`):** **184 trades, expectancy +0.9976R, PF 2.471, cumulative +183.56R** — by far the largest headline number in this study, driven almost entirely by the long side (+2.3036R/88 trades) with the short side still negative (-0.1996R/96 trades). **Critical caveat: this result is extremely temporally concentrated** — 2025Q1 and 2025Q4 alone account for 36.7% and 60.1% of total cumulative profit respectively (**~97% combined**, from only 47 of 184 trades), while three of the seven quarters are net negative. This is not a broadly distributed edge; it is a small number of large trending moves captured because nothing capped the winner early. Compare canonical (A)'s own quarterly profile, which is well-distributed (best quarter 31.7% of total, worst -8.9%, no single quarter dominant) — a materially healthier shape than F's.

**9. Partial-runner results (variants G/H):** **G (50% at 2R): 184 trades, expectancy +0.5477R, PF 2.044, cumulative +100.78R, win rate 33.7%** (up sharply from F's 19.0%, as expected from banking profit early). **H (50% at 3R): 184 trades, expectancy +0.5639R, PF 1.964, cumulative +103.76R, win rate 28.8%.** Both sit between B/C and F on every axis — locking in half the position tempers F's extreme concentration and raises win rate/lowers variance (max drawdown 16.79R/18.15R vs. F's 23.33R) while still capturing much of the uncapped-runner upside. Short side improves close to breakeven in both (-0.0167R, -0.0123R) versus F's -0.1996R. Exit-reason classification for G/H is complete for SL (76, 88) and definite opposite-signal-with-reversal (80, 80 each); a residual 28 (G) / 16 (H) trades exit at a price inconsistent with SL/TP but could not be matched to a specific triggering event within exact-second tolerance — most plausibly opposite-signal closes whose deal timestamp is offset by the extra broker round-trip these variants' own partial-close mechanism introduces. Honestly retained as `OTHER_TRUE_UNKNOWN` rather than force-classified; this does not materially affect the headline conclusion given SL/definite-reversal classification alone already accounts for 85-92% of each variant's trades.

**Suppressed-reversal result (variant C, `InpSuppressReversalEntry=true`):** **189 trades, expectancy +0.1074R, PF 1.208, cumulative +20.30R** — retaining "close on opposite signal" while removing "immediately reverse into it" keeps *most* of canonical's edge (85% of canonical's expectancy, 72% of its cumulative R) with zero reversal trades by construction (54 `SUPPRESSED_REVERSAL_ENTRY` events confirmed in the journal). This is strong evidence that **cutting the losing position early is the larger component of the mechanism's value; immediately re-entering in the new direction is a real but smaller incremental contributor** (canonical's extra +7.94R over C's +20.30R, from allowing those 54 suppressed signals — and later independent signals occupancy would otherwise have blocked — to actually fire).

**10. Model=2 vs. real-tick comparison:** real-tick coverage for the full `2025.03.01-2026.07.24` window is **2% real ticks** (MT5's own "History Quality" metric) — re-confirming and precisely quantifying D021's earlier informal finding (a ~124KB recent-activity-only tick cache). A short, very recent 4-day window shows 100% real ticks, confirming the isolated instance's tick cache only covers recent activity, not the historical study window. Per instruction to base decisions on real-tick results "where coverage permits" — 2% does not permit it. One demonstrative comparison run (canonical, full window, `Model=4`): 224 trades (identical count), expectancy +0.1342R vs. Model=2's +0.1261R, PF 1.2573 vs. 1.2446 — close enough to confirm execution-model choice is not the dominant factor here, so the remaining 7 variants were not separately rerun under a tick model already proven 98% synthetic for this window; doing so would not have produced decision-grade real-tick evidence, only numbers that *looked* more precise without being more true.

**11. Which mechanic creates the edge:** primarily **cutting adverse positions early** (variant C retains 72-85% of canonical's edge with zero reversals), secondarily **immediately entering the opposite trend** (canonical's incremental +7.94R over C), and **not** primarily an occupancy/trade-frequency effect in isolation — though occupancy *is* real and large (224 vs. 89 vs. 189 trades across A/B/C shows the mechanism's on/off state changes how many signals the account is even free to act on, which is *how* both of the above effects get expressed, not a separate fourth mechanism). Removing the fixed take-profit entirely (F) reveals a further, independent lever — letting winners run uncapped adds a large expected-value contribution, but one that is fragile/concentrated (point 8) rather than robust. Partial-taking (G/H) is a genuine partial synthesis of "cap some, let some run," landing between F and canonical/C on every axis as expected.

**12. Do D024's conclusions remain relevant?** Partially. D024's *comparative* findings among its 12 new structural/time exit models (none clearing the strict success floor, `TIME_24H`/`OPPOSITE_FAST_EXIT` as relative best-in-batch) are unaffected — those were computed via the SIGNAL_LEVEL/PORTFOLIO_LEVEL offline replay and are internally consistent with each other. What is **invalidated** is treating D024's `FIXED_2R_PLUS_TIMEOUT` offline-replay baseline (`~flat, PF~1.00`) as equivalent to "the strategy's fixed-2R performance" — it never modeled the opposite-signal-close/reverse mechanism at all, so it was always answering a different, narrower question (entry-quality under a purely price-path-driven exit) than "how does FastMedConfluence actually perform." D024's own report already flagged a population mismatch between its replay baseline and Stage B's live-EA number; this entry supplies the mechanistic reason why — the missing reversal mechanism — rather than leaving it as an unexplained gap.

**13. Best full-EA candidate for out-of-sample validation:** **canonical (variant A) itself**, not a new configuration — it has the best-distributed quarterly profile of any variant with a strong result (point 8's comparison), a coherent, now-fully-understood mechanism (points 3-6, 11), and D025's own exact-reproduction gate proves it is stable and reproducible run to run. Variant E (3R) is a legitimate secondary candidate (slightly better on every headline metric, healthier long/short balance) worth carrying into the same validation. **Variant F and its partial-runner derivatives (G/H) are explicitly *not* recommended for out-of-sample validation yet** despite their striking headline numbers — point 8's concentration finding means their apparent edge could easily be an artifact of 2-3 large trending episodes in this specific historical window, exactly the kind of finding that should be stress-tested against unseen history before being trusted, not extrapolated from.

### Planning the next validation stage (not executed in this pass)

Per instruction, only planned, not run: longer unseen XAUUSD history (extend backward before 2025.03.01 and/or forward past 2026.07.24, whatever the broker's actual history supports); walk-forward segmentation (train/validate splits rather than one continuous backtest window, to directly test whether canonical's well-distributed quarterly profile holds out-of-sample); a second broker/feed (to rule out this specific Coinexx-Demo feed's idiosyncrasies, especially given the confirmed near-total absence of real tick data for the historical window); an out-of-sample holdout (reserve a final slice of history never touched during any of D019-D025's work); and a small live-account-equivalence test (once a demo-forward-test track record exists, not before).

### Explicit scope statement

Every new EA input (`InpSuppressReversalEntry`, `InpDisableFixedTarget`, `InpPartialCloseAtR`, `InpPartialCloseFraction`) defaults to a value that reproduces exactly today's canonical behavior — none of D019-D024's existing configs are affected. No exit model or mechanism variant from this study is promoted to a new default. No merge to `main`. Per instruction: this entry does not call the canonical system "fixed-2R" anywhere — every reference is to "structural SL + 2R target + opposite-signal close/reverse," and the pure-fixed-2R condition is always named as `PURE_FIXED_2R` (variant B), a distinct, materially worse-performing configuration, never the default. No production-ready edge is claimed — point 13's recommendation is which candidate to validate next, not a claim that validation is complete.

## D026 — Trailing-stop validation on the proven full-EA strategy

**Date:** 2026-07-27
**Status:** In progress (decision recorded before implementation, per this branch's established discipline)

### Objective

Test trailing-stop mechanics **only on top of** D025's proven full-EA canonical mechanism (structural stop, FastMedConfluence entries, `InpExitOwnedOpposite=true` close/reverse) — never as a standalone offline replay, and never with any entry/ATR/score change. The question is narrowly: can a causal, monotonic, broker-valid trailing stop retain a meaningful share of variant F's uncapped-runner upside while reducing drawdown, giveback, and the 2025Q1/Q4 concentration that made F unfit for out-of-sample validation in D025 — without weakening the opposite-signal-close/reverse mechanism D025 identified as the actual source of the edge?

### A pre-existing bug found while auditing the ground-truth baselines: test-end positions silently dropped from the CSV

Per instruction, before building anything new, the known discrepancy between the MT5 native report and `MSZZ_TradeAnalytics.csv` for variant B was root-caused, not just "accounted for": `D025_VariantB_PureFixed2R.htm` reports **90** total trades (46 short + 44 long); `MSZZ_TradeAnalytics.csv` contains **89** rows (45 short + 44 long per the D025 report). The cause is structural, not variant-specific: `DetectClosedPositions()` (in `Experts/MultiSpeedZigZagEA.mq5`) only runs from `ProcessClosedBar()`, which only fires on a new-bar `OnTick()` event. The Strategy Tester force-closes any still-open position at the literal end of the test window to finalize equity — a real closing deal that the MT5 native report counts — but this happens after the EA's last new-bar tick has already been processed, so no further `ProcessClosedBar()` call ever runs to detect it. The position's closing deal exists in broker history, but our own CSV export never sees it. Variant B is the variant most likely to expose this (no reversal mechanism to end trades early, so it holds positions the longest and is the variant most likely to still be in one at the literal end of the window), but the bug is general — any variant/run could in principle have exactly one uncounted test-end trade, silently understating its own trade count by one and (in variants with a large realized R on that specific trade) skewing expectancy.

**Fix:** call `DetectClosedPositions()` a second time at the very start of `OnDeinit()`, before `WriteRunSummary()`. This is safe by construction for the live/non-Tester case: `DetectClosedPositions()` already skips any ticket that still resolves via `PositionSelectByTicket()` (i.e., a position still genuinely open, as it always will be when an EA is removed from a live/demo chart mid-trade), so the extra call is a no-op there. It only does new work in the Tester-forced-liquidation case, where the position is no longer selectable and a closing deal now exists in history. This is not a new research-only branch — it is a correctness fix to infrastructure D016 already claimed to be complete, applied once, unconditionally, with no new input. All of D026's fresh baseline reproductions (task below) are run under the fixed binary, and are expected to gain at most one trade each versus the original D025 numbers (only variants that actually had an open position exactly at the test boundary are affected).

### Ground-truth baselines: reproduce, do not assume

Per instruction, before any trailing variant is built, A/E/F/G/H are rerun from the current branch head (which includes the `OnDeinit` fix above) and required to match D025's reported trade counts and aggregates within the ±1-trade tolerance the fix itself introduces, with any larger deviation investigated before proceeding. These reruns are also the natural place to notice if anything else about the branch head has drifted since D025 — none is expected, since no other code between `32f890b` and this entry touches execution or analytics.

### Design: a general trailing-stop policy, not eight hardcoded variants

Rather than hardcode T1-T8 as EA-side branches, one generic, pure, deterministic policy (`Include/MultiSpeedZigZag/Research/ResearchTrailPolicy.mqh`, `CMSZZResearchTrailPolicy`) is built from two independent, composable mechanisms, each individually causal and monotonic:

1. **A profit-floor ladder** — an ordered list of `(trigger_r, floor_r)` rungs (up to 5, matching T6's ladder, the largest required). Once a closed bar's favorable excursion (in R, measured from the position's true entry and *original* structural risk — never from a later, already-trailed stop) reaches a rung's `trigger_r`, the stop moves forward to `entry + floor_r × initial_risk` (sign-adjusted for direction). A `floor_r` of exactly `0.0` additionally adds a configurable estimated round-trip cost in R (`InpTrailCostEstimateR`, matching D021's established "explicit, documented, flat cost estimate" precedent rather than trying to model live spread/commission inside a pure policy function) so "breakeven" really means "flat after costs," not "flat before them." Rungs are evaluated high-to-low so a bar that gaps past more than one rung in one step still lands on the correct (highest passed) rung, and `next_rung_index` guarantees no rung is ever re-applied once superseded. T1's single breakeven-at-+1R, T6's five-rung ladder, T7's breakeven-after-the-2R-partial, and T8's move-to-+1R-after-the-3R-partial are all the *same* mechanism with different rung tables — no separate code path per variant.
2. **A structure/volatility trail**, activated once favorable excursion crosses its own `structure_activation_r`: `FAST_SWING` and `MEDIUM_SWING` read the **live** `MSZZSpeedSnapshot.last_low`/`last_high` that `CMSZZTripleZigZagEngine` already computes every closed bar inside `ProcessClosedBar()` — this is real, already-tested EA state, not an offline duplicate (see "Rejected alternatives" below for why this matters). `CHANDELIER` computes `highest/lowest_since_activation ∓ mult × ATR(len)` from closed bars only, with ATR a plain (non-Wilder) true-range average over `InpTrailChandelierATRLen` bars — documented as a simplification, not a claim of matching any specific published Chandelier formula exactly. The swing candidate reuses D024's Bug-1 fix verbatim (a confirmed swing on the wrong side of the current close is stale, not tradeable — see D024 "Bug 1") since the wrong-side-swing failure mode is structurally identical here.

Both mechanisms only ever produce a *candidate* stop; a single `ResolveTightening()` function is the only place a stop is actually allowed to move, and it enforces, unconditionally: the candidate must be strictly tighter than the current effective stop (long: higher; short: lower — otherwise rejected, not clamped), and the candidate must clear the broker's minimum stop distance from the current bid/ask on the correct side (otherwise rejected outright, not clamped to the nearest valid level — a clamped stop is a *different* stop than the one the model actually computed, which would silently misrepresent what the model is being credited or blamed for). If both mechanisms produce a valid tightening candidate on the same bar, the more protective one (closer to current price) wins — there is only ever one broker-side stop.

### Design: same-bar ordering, exactly as specified

`ProcessClosedBar()`'s existing structure already matches the required ordering without rearrangement: `DetectClosedPositions()` (detect actual broker SL/TP/forced closure) already runs first; the new `ProcessResearchTrail()` call is inserted immediately after the engine rebuild and the three `Snapshot()` calls (it needs `fast`/`med` for the structure trail) and before `g_suite.Evaluate()`/`ExecuteCluster()` (which is where the opposite-signal-close/reverse mechanism lives). `ProcessPartialCloses()` (D025) keeps its existing position, before the engine rebuild, since it needs only bar OHLC. This yields exactly: detect closure → confirmed trailing-stop update → evaluate/execute opposite signal → reverse if qualified. No test is meaningful without confirming this ordering holds in practice, so the deterministic same-bar-ordering test (below) asserts it directly rather than trusting the source layout alone.

### Design: exit-reason classification gets one new category, not a rebuilt classifier

`ClassifyExitReason()` in `TradeAnalyticsExporter.mqh` compares a trade's exit price only to `intent.requested_stop` (the *original* stop, deliberately never overwritten by trailing, since R-multiples must always be measured against the original risk) — so under any active trail, a trailing-stop exit will not match `SL` there and will fall through to `OTHER`, exactly as D025's opposite-signal closes did before its external classifier. Rather than change the CSV schema or the live R-multiple computation, every trail modification is journaled to a new `MSZZ_TrailJournal.csv` (`ticket;time;old_stop;new_stop;fav_r;reason;modify_ok`), and the same external, journal-cross-referencing classifier design D025 already validated (extended with one more category, `TRAILING_STOP_EXIT`: exit price matches a ticket's last successfully-applied trail stop, checked before falling back to `OPPOSITE_SIGNAL_CLOSE`/`TEST_END`/`OTHER_TRUE_UNKNOWN`) produces the final decomposition. This keeps the baseline-equivalence discipline D025 established: the classifier's output is re-verified against the fresh A/E baseline's already-known facts before being trusted for any trailing variant.

### Design: restart persistence is explicitly partial, stated plainly per instruction

Per-position trail state (`max_favorable_r`, which rungs have already fired, whether the structure trail has activated, the running highest/lowest since activation) lives in a new in-memory array (`g_trail_states[]`), **not** integrated with the durable `ExecutionIntentStore`/`IntentStateMachine` — matching D025's own precedent for `g_partial_closed_tickets` (a bounded research mechanism, not a live-safety-critical feature). **This is not restart-persistent and this feature is not being called production-ready.** However, it degrades safely rather than silently, because of one deliberate design choice: a freshly (re)created state's `effective_stop` is always initialized from the *current broker-side stop* (`PositionGetDouble(POSITION_SL)` via the ownership record), never from a remembered value — so `ResolveTightening()`'s monotonic-only rule can never regress an already-trailed stop after a restart, even though `max_favorable_r`/`next_rung_index`/`structure_activated` reset to a fresh recomputation from that bar forward. `entry` and `original_stop` (needed for the R basis) are *not* lost across restart — they are read from the durable `ExecutionIntentStore` record matching the position's ticket (`average_fill_price`/`requested_stop`), not from in-memory state, so restart at least never corrupts the R basis, only the "how far along the ladder are we" bookkeeping. This is a real limitation (a rung that logically should already be active may need its trigger crossed again post-restart to actually apply), stated here rather than glossed over, and restart behavior is one of the required deterministic tests below.

### New EA inputs (all default to values that make `ProcessResearchTrail()` a no-op)

```cpp
input bool   InpEnableResearchTrail=false;
input double InpTrailRung1TriggerR=0.0;  input double InpTrailRung1FloorR=0.0;
input double InpTrailRung2TriggerR=0.0;  input double InpTrailRung2FloorR=0.0;
input double InpTrailRung3TriggerR=0.0;  input double InpTrailRung3FloorR=0.0;
input double InpTrailRung4TriggerR=0.0;  input double InpTrailRung4FloorR=0.0;
input double InpTrailRung5TriggerR=0.0;  input double InpTrailRung5FloorR=0.0;
input double InpTrailCostEstimateR=0.02;
input int    InpTrailStructureMode=0; // 0=NONE,1=FAST_SWING,2=MEDIUM_SWING,3=CHANDELIER
input double InpTrailStructureActivationR=0.0;
input int    InpTrailChandelierATRLen=14;
input double InpTrailChandelierATRMult=3.0;
```

A rung with `TriggerR<=0.0` is simply unused (not a rung, per this project's established "non-positive disables" convention — D012/D013/D015). Rungs must be supplied in strictly ascending `trigger_r` order or `OnInit()` fails closed (`INIT_PARAMETERS_INCORRECT`) rather than silently misbehaving — a deliberate config-authoring guard, not a runtime concern. `InpResearchTrailMode` (a single mode selector, as the prompt's "stronger design" suggested) was considered and rejected in favor of exposing the rung table and structure mode directly: T1/T6/T7/T8 are all the same floor-ladder mechanism at different rung values, so hardcoding eight named modes would either duplicate the ladder logic eight times or require the same generic table internally anyway — better to let each `Txx.ini` config simply set the rungs it needs, with `InpEnableResearchTrail=false` as the single master off-switch proving every existing D019-D025 config is untouched.

### Required variants → config mapping (no EA code branches per variant)

- **T0** = variant F unmodified (`InpDisableFixedTarget=true`, `InpEnableResearchTrail=false`) — direct comparison baseline, not a new run design.
- **T1** = T0 + `InpEnableResearchTrail=true`, one rung `(1.0, 0.0)`, `InpTrailStructureMode=0` (NONE).
- **T2** = T0 + rung `(1.0, 0.0)` + `InpTrailStructureMode=1` (FAST_SWING), `InpTrailStructureActivationR=2.0`.
- **T3** = T0 + no rungs, `InpTrailStructureMode=1`, `InpTrailStructureActivationR=2.0`.
- **T4** = T0 + no rungs, `InpTrailStructureMode=2` (MEDIUM_SWING), `InpTrailStructureActivationR=2.0`.
- **T5** = T0 + no rungs, `InpTrailStructureMode=3` (CHANDELIER), `InpTrailStructureActivationR=2.0`, `InpTrailChandelierATRLen=14`, `InpTrailChandelierATRMult=3.0`.
- **T6** = T0 + five rungs `(1.0,0.0) (2.0,0.5) (3.0,1.5) (5.0,3.0) (8.0,5.0)`, `InpTrailStructureMode=0`.
- **T7** = variant G's partial-close inputs (`InpPartialCloseAtR=2.0`, `InpPartialCloseFraction=0.5`, `InpFixedLots=0.02`) + `InpDisableFixedTarget=true` + one rung `(2.0, 0.0)` (breakeven, timed to the same threshold the partial fires at) + `InpTrailStructureMode=1`, `InpTrailStructureActivationR=3.0`.
- **T8** = variant H's partial-close inputs (`InpPartialCloseAtR=3.0`, `InpFixedLots=0.02`) + `InpDisableFixedTarget=true` + one rung `(3.0, 1.0)` (move to +1R, not breakeven, per spec) + `InpTrailStructureMode=2`, `InpTrailStructureActivationR=4.0`.

### Rejected alternatives

- **Offline replay of trailing exits against the existing signal journal** (D021/D022/D024's architecture): rejected outright — this is the exact mistake D025 found and this entry's own title names as the thing not to repeat. Every T-variant is a full-EA Tester run.
- **Duplicating the ZigZag engine's swing state (à la D024's `StructuralReplay.mqh`) for trail candidates**: rejected — unlike D024, the live engine's own snapshot is already available at exactly the point `ProcessResearchTrail()` needs it (`ProcessClosedBar()` already rebuilds and snapshots the engine every bar for signal evaluation), so there is no reason to duplicate it; using the live snapshot directly is both simpler and strictly more faithful to actual EA behavior.
- **A single `InpResearchTrailMode` enum selecting one of eight hardcoded presets**: rejected in favor of exposing the general rung table + structure mode (see above) — avoids eight near-duplicate code paths for what is mechanically two composable primitives.
- **Wiring trail state into `ExecutionIntentStore`/`IntentStateMachine` for durability**: rejected for this pass as disproportionate for a bounded research mechanism, exactly matching D025's own rejection of durable partial-close tracking — explicitly flagged as a restart-persistence limitation instead (see above), not silently presented as production-ready.
- **Clamping an invalid trail candidate to the nearest broker-valid level**: rejected — a clamped stop is a different, un-modeled stop; skipping the update for that bar (and re-evaluating next bar) keeps every applied stop attributable to the model that actually proposed it.

### Testing requirements

All 20 deterministic cases specified are required before any Tester run: long/short R calculation; breakeven activation boundary (one bar before / exactly at threshold); stop never widens; stop never crosses to the invalid side of current market; Fast-swing and Medium-swing trails reject wrong-side/stale confirmed pivots (reusing D024's Bug-1 regression pattern); Chandelier uses only closed-bar ATR/extrema; profit-floor ladder threshold-crossing (including a same-bar multi-rung gap); same-bar trail-vs-opposite-signal ordering; partial-plus-runner blended R (reusing D025's volume-weighted-exit-price fix, unmodified); single-exit trades unaffected; canonical byte-identical parity when `InpEnableResearchTrail=false`; restart behavior (state reconstructed from durable intent + current broker stop, no regression); broker stop-distance rejection; failed-modification handling; duplicate-modification suppression (a candidate equal to the current effective stop is not resubmitted); long/short symmetry; test-end forced-closure reconciliation (the `OnDeinit` fix, above); and the MT5-HTML-vs-CSV trade-count reconciliation for every baseline and every T-variant. Full `Test_MSZZ_*` regression and short/long shadow regression (identical candidate/shadow counts, zero orders/deals, no behavior change with research trailing disabled) run after wiring, exactly matching this branch's standing discipline for any change to `Experts/MultiSpeedZigZagEA.mq5` itself.

### Success criteria (unchanged from instruction, restated for traceability)

A trailing variant is promoted for further validation only if **all** of: long and short expectancy positive (or short approximately flat with a clearly strong long side); PF above canonical (A); expectancy materially above E's `+0.1467R`; max drawdown below F's `23.33R`; best-two-quarters contribution materially below F's ~97%; positive expectancy excluding the top three trades; positive expectancy excluding the best quarter; no unexplained trade-count mismatch; unknown-exit classification at or below 2%; byte-identical canonical behavior with trailing disabled. Meeting all ten is necessary, not sufficient, for out-of-sample candidacy — no variant is promoted directly to production regardless of how many criteria it clears.

No merge to `main`. No live/production deployment. No entry, ATR, or score parameter is changed anywhere in this entry.

### Results

**1. Exact baseline reproduction.** All five ground-truth baselines were rerun fresh from the current branch head (which includes the `OnDeinit` fix) and matched D025's numbers **exactly, not merely within the ±1-trade tolerance the fix could in principle have introduced**: A (canonical) 224 trades/+0.1261R/PF 1.2446/DD 15.1583R/107L/117S; E (3R) 213/+0.1467R/PF 1.2532/DD 16.9205R/101L/112S; F (=T0) 184/+0.9976R/PF 2.4709/DD 23.3265R/88L/96S; G 184/+0.5477R/PF 2.0439/DD 16.7873R/88L/96S; H 184/+0.5639R/PF 1.9645R/DD 18.1478R/88L/96S. No test-end position happened to be open in any of these five specific windows, so the `OnDeinit` fix was a proven no-op for all five — its correction only ever mattered for variant B, exactly as diagnosed.

**2. Code changes and default-off proof.** `Include/MultiSpeedZigZag/Research/ResearchTrailPolicy.mqh` (new, pure policy), `Experts/MultiSpeedZigZagEA.mq5` (new inputs, `BuildTrailConfig()`, `ProcessResearchTrail()`, the `OnDeinit` fix), `Tests/MultiSpeedZigZag/Test_MSZZ_ResearchTrail.mq5` (new, 33 assertions, 0 failures). Default-off proof: both shadow regressions (short window: 113 candidates/46 clusters; long window: 431 candidates/178 clusters) reproduced byte-identical counts with zero orders/deals, run against the new binary with `InpEnableResearchTrail=false` explicit in the config — matching every prior shadow baseline this branch has ever produced. All 15 pre-existing `Test_MSZZ_*` suites still pass at 0 failures.

**3. Full variant table** (17-month window `2025.03.01`–`2026.07.24`, `Model=2`, same as D025):

| Variant | Trades | Exp_R | PF | Cum_R | Max DD (R) | Sharpe (native) | Win% | Med Hold | P90 Hold | Long Exp (n) | Short Exp (n) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A (canonical) | 224 | +0.1261 | 1.245 | 28.24 | 15.16 | 0.89 | 36.2% | 1.7h | 65h | +0.2054 (107) | +0.0536 (117) |
| E (3R) | 213 | +0.1467 | 1.253 | 31.25 | 16.92 | 1.08 | 29.6% | 2.3h | 68h | +0.2098 (101) | +0.0898 (112) |
| T0 (=F, no trail) | 184 | +0.9976 | 2.471 | 183.56 | 23.33 | 0.67 | 19.0% | 2.9h | 132h | +2.3036 (88) | -0.1996 (96) |
| G (partial 2R) | 184 | +0.5477 | 2.044 | 100.78 | 16.79 | 0.80 | 33.7% | 2.9h | 132h | +1.1634 (88) | -0.0167 (96) |
| H (partial 3R) | 184 | +0.5639 | 1.964 | 103.76 | 18.15 | 0.89 | 28.8% | 2.9h | 132h | +1.1925 (88) | -0.0123 (96) |
| T1 (BE @1R) | 212 | +0.3986 | 1.946 | 84.50 | 23.34 | 0.70 | 47.6% | 1.7h | 65h | +1.0501 (95) | -0.1305 (117) |
| T2 (BE1R + Fast-swing @2R) | 220 | +0.4740 | 2.125 | 104.29 | 18.51 | 0.89 | 47.3% | 1.8h | 68h | +1.3030 (99) | -0.2042 (121) |
| T3 (Fast-swing @2R, no BE) | 200 | +0.6438 | 2.049 | 128.76 | 20.65 | 0.92 | 24.5% | 3.1h | 105h | +1.5105 (97) | -0.1723 (103) |
| T4 (Medium-swing @2R) | 199 | +0.3956 | 1.641 | 78.73 | 23.38 | 0.49 | 24.6% | 2.8h | 120h | +1.0706 (97) | -0.2463 (102) |
| T5 (Chandelier @2R) | 222 | +0.1105 | 1.204 | 24.54 | 18.55 | 0.80 | 33.3% | 2.5h | 65h | +0.2750 (106) | -0.0398 (116) |
| T6 (profit-floor ladder) | 221 | +0.5198 | 2.247 | 114.87 | **12.36** | **1.15** | 48.0% | 1.7h | 65h | +1.2950 (99) | -0.1093 (122) |
| T7 (G + trailed runner) | 209 | +0.2564 | 1.486 | 53.59 | 16.89 | 0.81 | 35.9% | 3.0h | 80h | +0.6508 (98) | -0.0918 (111) |
| T8 (H + trailed runner) | 205 | +0.3018 | 1.512 | 61.88 | 17.30 | 0.63 | 29.3% | 3.2h | 89h | +0.6288 (96) | **+0.0139 (109)** |

**4. Trail activation counts** (successful `PositionModify` calls, from `MSZZ_TrailJournal.csv`, all `modify_ok=true` — **zero failed or rejected modifications in any of the eight variants**): T1 96, T2 270, T3 256, T4 153, T5 509, T6 193, T7 212, T8 133.

**5. Exit-reason decomposition** (SL/TP against original structural stop/target; `TRAILING_STOP_EXIT` newly added by cross-referencing each trade's exit price against `MSZZ_TrailJournal.csv`'s successfully-applied stops within that trade's own open window; `OPPOSITE_SIGNAL_CLOSE` via the D025 exact-second reversal-pair method; no `TEST_END` in any of these 13 runs):

| Variant | SL | TP | Opposite | Trailing | Unknown |
|---|---|---|---|---|---|
| A | 93 | 69 | 62 | — | 0 |
| E | 101 | 49 | 63 | — | 0 |
| T0/F | 104 | 0 | 80 | — | 0 |
| G | 76 | 0 | 80 | — | 28 |
| H | 88 | 0 | 80 | — | 16 |
| T1 | 71 | 0 | 65 | 76 | 0 |
| T2 | 74 | 0 | 54 | 92 | 0 |
| T3 | 97 | 0 | 64 | 39 | 0 |
| T4 | 98 | 0 | 64 | 37 | 0 |
| T5 | 97 | 0 | 64 | 61 | 0 |
| T6 | 73 | 0 | 60 | 88 | 0 |
| T7 | 90 | 0 | 61 | 0* | 58 |
| T8 | 100 | 0 | 64 | 0* | 41 |

T1–T6's unknown rate is **exactly 0%** — the new `TRAILING_STOP_EXIT` category, matched purely on price/time against the trail journal, accounts for every previously-unclassifiable exit. T7/T8 (\*) retain G/H's own already-documented residual (27.8%/20.0%, same 28/16-trade-scale phenomenon D025 found and explained: the partial-close mechanism's extra broker round-trip shifts a deal's timestamp past exact-second matching) — combining partial-close with trailing does not fix or worsen that pre-existing limitation, and does not affect the R-multiple/expectancy numbers, which are computed directly from the raw CSV regardless of exit-reason attribution.

**6. Giveback analysis** (`mfe_r - r_result`, mean/median/p90 in R):

| Variant | Avg | Median | P90 |
|---|---|---|---|
| A | 1.05 | 1.05 | 2.23 |
| E | 1.27 | 1.18 | 2.54 |
| T0/F | 3.44 | 1.58 | 6.27 |
| T1 | 2.35 | 1.37 | 3.67 |
| T2 | 1.96 | 1.35 | 3.06 |
| T3 | 2.46 | 1.47 | 4.94 |
| T4 | 2.55 | 1.56 | 5.83 |
| T5 | 1.45 | 1.26 | 2.45 |
| T6 | 1.88 | 1.38 | 2.45 |
| T7 | 2.44 | 1.45 | 3.68 |
| T8 | 2.62 | 1.54 | 3.98 |

Every trail reduces average giveback versus F (23.7%–57.7%), confirming the mechanism does what it is meant to at the individual-trade level — the open question (§9 below) is whether that translates into portfolio-level robustness.

**7. Long/short analysis.** Every single trail variant **reduces long expectancy relative to F** (by -0.79R to -2.03R per trade) — expected and unavoidable, since capping/trailing a runner by definition caps what F's uncapped long runners were capturing. Short-side effect is small and mixed: most variants nudge short expectancy toward flat by 0.03–0.21R without flipping its sign; **T8 is the only variant across the entire study (including A, E, and every other trail) with a positive short expectancy** (+0.0139R, 109 trades) — genuinely notable, though the magnitude is close enough to zero that it should be read as "no longer a structural liability" rather than "a source of edge."

**8. Quarterly concentration analysis** (share of total cumulative R from the best quarter / best two quarters, compared to F's 60.1%/96.7%):

| Variant | Best-Q% | Best-2Q% | Positive Q / Negative Q |
|---|---|---|---|
| A | 31.7% | 55.6% | 6 / 1 |
| E | 40.8% | 64.6% | 6 / 1 |
| T0/F | 60.1% | 96.7% | 4 / 3 |
| T1 | 102.3% | 118.8% | 2 / 5 |
| T2 | 101.7% | 104.9% | 3 / 4 |
| T3 | 102.2% | 104.4% | 4 / 3 |
| T4 | 61.0% | 120.7% | 3 / 4 |
| T5 | 37.3% | 70.0% | 5 / 2 |
| T6 | 86.5% | 94.6% | 5 / 2 |
| T7 | 88.2% | 99.0% | 5 / 2 |
| T8 | 41.0% | 70.6% | 6 / 1 |

Only **T5 and T8** materially reduce two-quarter concentration versus F (26.7pp and 26.1pp respectively, landing at 70.0%/70.6% — still well above canonical's 55.6% but a real improvement over F). T1–T4 and T7 do not improve concentration at all — several (T1, T2, T3, T4) show best-two-quarter figures **exceeding 100%**, meaning the *rest* of the quarters are net negative in aggregate even though the strategy is profitable overall — a more fragile shape than F itself, not a better one, despite T1–T4's much higher headline expectancy than canonical. T6, despite its excellent drawdown and PF, barely moves this needle (94.6% vs. F's 96.7%) — its headline numbers are strong specifically *because* it still depends heavily on a small number of quarters, not because it broadened the base.

**9. Outlier-removal analysis** (top-1/3/5 trade contribution as % of total cumulative R; expectancy excluding the top 3 trades — canonical is +0.1007R, E is +0.1059R ex-top-3, both comfortably positive):

| Variant | Top-1% | Top-3% | Top-5% | Exp. ex-top-3 |
|---|---|---|---|---|
| A | 7.1% | 21.2% | 35.4% | +0.1007 |
| E | 9.6% | 28.8% | 48.0% | +0.1059 |
| T0/F | 56.0% | 109.8% | 129.3% | **-0.0994** |
| T1 | 121.7% | 156.0% | 171.0% | -0.2263 |
| T2 | 114.3% | 130.7% | 141.8% | -0.1474 |
| T3 | 92.6% | 123.3% | 135.7% | -0.1524 |
| T4 | 62.8% | 142.5% | 166.6% | -0.1706 |
| T5 | 51.6% | 95.9% | 131.6% | +0.0045 |
| T6 | 89.5% | 102.3% | 111.1% | -0.0124 |
| T7 | 112.6% | 134.1% | 150.2% | -0.0887 |
| T8 | 42.4% | 100.9% | 131.1% | -0.0028 |

**This is the study's central, sobering finding.** Removing just the top three trades flips **seven of the eight trailing variants** to negative expectancy — only T5 survives (+0.0045R, barely). T6 and T8, the two variants with the best headline numbers and the most encouraging quarterly/giveback results, are both negative ex-top-3 (-0.0124R, -0.0028R) — essentially flat-to-slightly-negative, not the robust edge their PF/expectancy headlines suggest. **None of the eight trailing variants converts F's outlier-dependent upside into an outlier-independent one** — they all repackage a small number of extreme trending trades under different stop-management regimes, with T6/T8 doing the best job of that repackaging (highest PF, best drawdown, least fragile-looking headline shape) without actually solving the underlying dependency. Expectancy excluding the best quarter alone is a materially easier bar and five variants clear it (T4 +0.1616, T8 +0.1863, T6 +0.0889, T5 +0.0729, T7 +0.0380) — the gap between "survives losing one quarter" and "survives losing three trades" is itself informative about how concentrated the remaining edge is even after the best quarter is removed.

**10. Exposure and holding-time analysis.** Every trail variant increases median holding time relative to canonical/E (as expected — a trail's entire purpose is to stay in winners longer than a fixed 2R target would) while several (T1, T2, T6) keep median holding time *closer to canonical's* (~1.7–1.8h) than F's own median (2.9h), because most trades still resolve via SL or an opposite-signal close well before any trail-related mechanism engages — only the minority of trades that reach the structure/floor activation threshold ride longer, which is exactly why P90 and max holding times remain wide (68–132h) even when the median stays short. Return per exposure hour ranges from T6's 0.0198 (best among trailing variants, still below T0/F's own 0.0205) down to T5's 0.0057 (below even canonical's 0.0068) — no trail improves capital efficiency per hour-in-market beyond F itself; they trade some of F's raw R/hour for a materially different risk shape.

**11. MT5-report-to-CSV reconciliation.** For every non-partial-close variant (A, E, T0/F, T1–T6), the MT5 native report's "Total Trades" figure matches `MSZZ_TradeAnalytics.csv`'s row count **exactly** — the `OnDeinit` fix (§1/§2) holds with zero further discrepancies across this entire batch. For the four partial-close variants (G, H, T7, T8), the native report's count is **higher** than the CSV's (G: 240 vs. 184; H: 225 vs. 184; T7: 272 vs. 209; T8: 251 vs. 205) — this is the expected, already-documented divergence from D025 (MT5's own trade counter treats a partial-close-then-remainder-close sequence as two native "trades," while `DetectClosedPositions()`'s volume-weighted-blended-R logic correctly treats it as one logical trade sequence, per this project's own "do not count partial and runner legs as separate entries" rule) — **not a new bug, not left unexplained, and not treated as a mismatch requiring investigation.**

**12. Which trail preserves the most of F.** By raw retained upside: **T3** (70.1% of F's cumulative R, 64.5% of its expectancy) preserves the most, followed by T6 (62.6%/52.1%) and T2 (56.8%/47.5%). T5 preserves the least (13.4%/11.1%) — it behaves much closer to a canonical-like exit than to F.

**13. Which trail gives the best robustness/return trade-off.** **T6 (profit-floor ladder)** is the strongest single candidate on this axis: best drawdown of the *entire study including canonical* (12.36R vs. A's 15.16R), best PF (2.247), best native Sharpe (1.15), highest win rate (48.0%), and it retains a majority of F's cumulative upside (62.6%) — but it still fails the outlier-independence bar (ex-top-3 expectancy -0.0124R) and barely moves quarter concentration (94.6% vs. F's 96.7%), so "best trade-off" is a relative, not absolute, statement. **T8 (H + trailed runner)** is the next-best-rounded candidate: it is the only variant with positive short expectancy, meaningfully reduces two-quarter concentration (70.6% vs. 96.7%), and clears more of the ten success criteria than any other variant (see §14) — offset by its 20% unknown-exit rate (a measurement-completeness limitation, not a performance one) and its own near-zero ex-top-3 expectancy.

**14. Success-criteria classification** (all ten checked per variant; "materially above/below" operationalized as ≥10% relative for expectancy-vs-E and ≥20 percentage points for quarter-concentration-vs-F, stated explicitly since the instruction deliberately left "material" undefined):

| Variant | 1 L/S | 2 PF>A | 3 Exp≫E | 4 DD<F | 5 Q2conc≪F | 6 Exp ex-top3>0 | 7 Exp ex-bestQ>0 | 8 Count OK | 9 Unk≤2% | 10 Parity | **Total** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | 5/10 |
| T2 | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | 6/10 |
| T3 | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | 6/10 |
| T4 | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | 6/10 |
| T5 | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 7/10 |
| T6 | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | 7/10 |
| T7 | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | 6/10 |
| T8 | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | 8/10 |

**No variant meets all ten criteria — per the instruction's own "meeting all ten is necessary," none qualifies for promotion.** T8 comes closest (8/10), failing only outlier-independence (§9) and the unknown-exit-rate measurement limitation (§5) — both real, not cosmetic, gaps. T5 and T6 tie at 7/10 but for opposite reasons: T5 fails on headline return/PF (it simply doesn't capture enough of F's upside to be interesting), while T6 fails on the two robustness checks that matter most (concentration, outlier-independence) despite the best headline numbers in the study.

**15. Does any trail clearly beat A and E?** **On raw headline metrics, yes, dramatically** — T6's PF (2.247 vs. A's 1.245), expectancy (+0.52R vs. +0.13R), and drawdown (12.36R vs. 15.16R) all beat canonical simultaneously, and several other variants beat E by similar margins. **On the robustness checks this study was specifically built to apply, no** — every variant that beats A/E on headline terms fails the outlier-removal test (§9), meaning that headline edge is not demonstrated to survive without its 1–3 largest trades, which canonical and E both do. This is exactly the distinction the "Interpretation rules" warn against collapsing: none of these should be reported as "beats canonical," only as "shows a larger, more fragile, not-yet-validated edge than canonical."

**16. Is F still worth separate long-only or regime-gated research?** Yes, and this study sharpens rather than answers that question. Every trail variant's improvement over F comes almost entirely from what happens to the **long side's extreme winners** (all eight show long-expectancy declines of -0.79R to -2.03R relative to F) — the short side barely changes in absolute terms and remains a net drag in seven of eight variants. This is consistent with F's edge being a long-side, likely trend/regime-dependent phenomenon that stop-management alone cannot convert into a broadly robust, direction-symmetric strategy. A long-only or explicitly regime-gated (e.g., only active in confirmed strong-trend regimes) variant of F, tested with the same rigor D025/D026 applied here (full-EA runs, outlier-removal, quarter-concentration), is a more promising direction than further exit-model search on the current direction-agnostic entry.

**17. Recommended candidates for out-of-sample validation.** Per D025, **canonical (A)** and **3R-with-reversal (E)** remain the only candidates that pass every robustness check applied across both studies (positive ex-top-3, positive ex-best-quarter, well-distributed quarterly profile, no reliance on outlier trades). Of the eight new trailing variants, **none is recommended for promotion to out-of-sample validation on this evidence** — T6 and T8 are flagged as the most promising *further-research* candidates (not validation-ready) specifically because they are the only two that meaningfully improve on F's drawdown/concentration profile while retaining a majority (T6) or plurality (T8) of its raw upside; both would need the outlier-independence gap closed (e.g., by testing on materially more history, where three additional years of trending episodes might either confirm or dilute the current top-3-trade dependency) before being considered for the same validation track as A/E.

### Commit and artifacts

Starting SHA for this results addendum: `d7ab166` (this entry's own decision-log-only commit). Final SHA is this results commit. New/modified files: `Include/MultiSpeedZigZag/Research/ResearchTrailPolicy.mqh`, `Experts/MultiSpeedZigZagEA.mq5`, `Tests/MultiSpeedZigZag/Test_MSZZ_ResearchTrail.mq5`, `Tools/D026/` (13 `.ini` configs plus `README.md`), `Tools/D026/results/` (all 13 runs' `MSZZ_TradeAnalytics.csv`/`MSZZ_SignalJournal.csv`/`MSZZ_RunSummary.csv`/`MSZZ_TrailJournal.csv` where applicable, and MT5 `.htm` reports). No merge to `main`. No production/live deployment of any trail. Two infrastructure bugs were found and fixed during execution and are worth recording for future batch scripts on this machine: macOS ships bash 3.2 (no associative arrays — use indexed parallel arrays); MT5's own `/config:` argument parser splits on `/`, silently truncating a relative subdirectory path at the first slash — pass the absolute Windows path with backslash separators instead (`Z:\Users\...\Dir\file.ini`), exactly as this branch's D023 `${cfg}` bash-escaping fix already established for a related reason.

## D027 — Regime architecture and strategy-family expansion

**Date:** 2026-07-27
**Status:** In progress (staged; this entry is written before implementation per this branch's established discipline, and will be extended with results as each stage completes — later stages are tracked as pending work, not silently skipped)

### Mission and scope

Build a causal, auditable market-regime classifier as an **observer layer** (Layer 1), an explicit strategy-family taxonomy (Layer 2), and a regime-eligibility policy (Layer 3) that starts in `LABEL_ONLY` mode everywhere. On top of that architecture, implement five new, structurally distinct strategy-family candidates (S1–S5) and test whether any of them contains expectancy independent of FastMedConfluence, either standalone or in combination with the existing A/E core. **A and E are the control group and are not modified by this decision** — no entry, ATR, score, stop, or opposite-signal logic change; no regime gate added to A/E in this pass. This is research and architecture, not optimization of the proven core. No merge to `main`, no live deployment, no production promotion of anything built in this entry.

Given the size of the full brief (six execution stages, five new strategies, a portfolio-interaction study, a regime-filter stage, and a 40-point final report), this entry is being delivered the same way every other multi-stage decision on this branch has been: in bounded, independently-verified increments, each committed once it is genuinely done, rather than claimed complete in one pass. This entry currently covers **Stage 0 (baseline integrity) and the architecture/design decisions for Layers 1–3**; Stages 1–6 and the strategy implementations are tracked explicitly as pending and will extend this same entry (append-only, per file convention) as they land.

### Stage 0 — Baseline integrity (satisfied by direct inheritance from D026)

The branch head at the start of this entry is `5ed1e67`, exactly the SHA D027 was instructed to start from — confirmed via `git log`/`git rev-parse`, zero commits or working-tree drift since D026's own commit. D026's own verification, performed against this exact same commit, already proved: canonical (A) reproduces 224 trades/+0.1261R/PF 1.2446/DD 15.1583R; E reproduces 213 trades/+0.1467R/PF 1.2532/DD 16.9205R; all 15 pre-existing `Test_MSZZ_*` suites pass at 0 failures; both shadow regressions (113/46 short, 431/178 long candidates/clusters, zero orders/deals) are unchanged; every D026 trailing input is confirmed default-off. Since zero code has changed between that verification and this entry, re-running the same 17-month backtests would produce byte-identical numbers for no new information — Stage 0 is satisfied by citing that evidence directly rather than mechanically repeating it, consistent with this project's own precedent (D023's exact-SHA-match reuse policy for canonical cells is a *stricter* bar than this, since D023 was willing to reuse across "same commit family"; here it is the literal same commit).

### Out-of-sample window declaration, and an honest data-availability limitation

Per instruction, the development/validation/holdout boundaries must be declared before any candidate is tested, and older data should be used where the broker's history permits. A direct probe (`check_history` script requesting 100,000 M5 bars back from the most recent available bar) found: **`earliest=2025.02.26 05:00`, `latest=2026.07.24 23:55`** — i.e., this account/feed's actual usable M5 history for XAUUSD begins only **three days before** the existing D018–D026 research window's own start (`2025.03.01`). There is no materially older unseen block available. Per the instruction's own explicit fallback ("If sufficient older data is unavailable, state that clearly rather than reusing the same sample and calling it out of sample"), this is stated plainly here rather than glossed over: **D027 cannot construct a genuine fresh-history out-of-sample split.** What it can do, and will do, is a **within-window chronological split**, which is a real (if weaker) safeguard against overfitting the *new* regime definitions and strategy rules specifically — none of the regime classifier or S1–S5 strategies have been evaluated against any of this data yet, unlike A/E/D019–D026's existing strategies, which have already been fit to the reader's knowledge of the whole window:

- **Development window:** `2025.03.01`–`2025.12.31` (10 months) — regime definitions, strategy trigger logic, and thresholds are designed and iterated against this slice only.
- **Validation window:** `2026.01.01`–`2026.04.30` (4 months) — used once definitions are frozen, to check stability; does not feed back into threshold changes.
- **Final holdout:** `2026.05.01`–`2026.07.24` (~3 months) — untouched until every regime definition, strategy rule, and threshold is frozen in this document; used only for final confirmation.

This is disclosed as a **within-sample chronological holdout, not independent out-of-sample data**, and every later results section will state which window(s) a given number comes from rather than silently mixing them.

### Layer 1 — Regime classifier: exact definitions

All definitions below are frozen before any strategy or regime-filter result is inspected, per the anti-overfitting rules. `CMSZZRegimeClassifier::Evaluate()` is a pure function of `(fast, medium, slow, rates[], closed_count)` — the same three `MSZZSpeedSnapshot`s `ProcessClosedBar()` already computes for signal evaluation, plus the same closed-bar `rates[]` array — with no MT5 API calls and no persistent classifier-side state, so "same input produces byte-identical output" is true by construction, not by testing luck.

- **Direction** (`BULLISH`/`BEARISH`/`NEUTRAL`): taken from the **slow** speed's `leg_direction` (the dominant structural bias) — `MSZZ_DIR_LONG`→`BULLISH`, `MSZZ_DIR_SHORT`→`BEARISH`, `MSZZ_DIR_NONE`→`NEUTRAL`.
- **Structural alignment** (`FULLY_ALIGNED`/`PARTIALLY_ALIGNED`/`MIXED`/`OPPOSED`), checked in this fixed priority order (documented precisely because the four categories are not mutually exclusive without one):
  1. `FULLY_ALIGNED` if `fast.leg_direction == medium.leg_direction == slow.leg_direction` and none is `NONE`.
  2. Else `OPPOSED` if `fast.leg_direction` is the exact opposite of `slow.leg_direction` (both non-`NONE`) — checked before the "two agree" rule below so a direct fast-vs-slow contradiction is never masked by medium happening to agree with one side.
  3. Else `PARTIALLY_ALIGNED` if any two of the three speeds agree (non-`NONE`).
  4. Else `MIXED`.
- **Trend strength** (`WEAK`/`NORMAL`/`STRONG`): driven by `directional_efficiency` (below) with predeclared boundaries `WEAK <0.35`, `NORMAL 0.35–0.65`, `STRONG >0.65`. (The instruction only predeclared volatility boundaries explicitly; these trend-strength boundaries are this entry's own predeclared, documented, not-tuned-after-results choice, stated here before any result is computed.)
- **Volatility state** (`CONTRACTING`/`NORMAL`/`EXPANDING`): `normalized_atr = ATR(14) / median(ATR(14) over the previous 100 closed bars)`, boundaries exactly as suggested: `CONTRACTING <0.80`, `NORMAL 0.80–1.20`, `EXPANDING >1.20`.
- **Directional efficiency**: Kaufman-style efficiency ratio over a fixed, predeclared lookback of **20 closed bars**: `abs(close[t] - close[t-19]) / sum(abs(close[i]-close[i-1]) for i in [t-19, t])`. One lookback, not optimized in D027, per instruction.
- **Compression ratio**: `fast_swing_amplitude_r / medium_swing_amplitude_r` (guarded against zero). `market_phase = COMPRESSION` requires this ratio `< 0.35` (predeclared) **and** `volatility_state != EXPANDING` **and** the fast amplitude is non-increasing versus its own immediately preceding confirmed swing.
- **Swing amplitude** (fast/medium/slow, in R): `abs(last_high.price - last_low.price) / atr` for that speed — normalizes the latest confirmed swing leg by that speed's own current ATR, both already present on `MSZZSpeedSnapshot`.
- **Swing duration** (fast/medium/slow, in bars): `abs(last_high.confirmed_time - last_low.confirmed_time) / PeriodSeconds()` — the gap between that speed's most recent confirmed high and most recent confirmed low, regardless of which came first. A simpler, equally causal definition than sorting all four available pivots by time; documented exactly so a reviewer can recompute it by hand.
- **Market phase** (`BREAKOUT`/`TREND_CONTINUATION`/`PULLBACK`/`COMPRESSION`/`TRANSITION`/`RANGE`/`FAILED_BREAK`/`UNCLASSIFIED`), evaluated in this order, first match wins:
  1. `BREAKOUT`: the current closed bar has `fast.bullish_break` or `fast.bearish_break` set, and alignment is `FULLY_ALIGNED` or `PARTIALLY_ALIGNED` in that break's direction.
  2. `TREND_CONTINUATION`: alignment `FULLY_ALIGNED`, `volatility_state` is `NORMAL` or `EXPANDING`, and this bar is *not* itself a fresh break (excludes double-counting with #1).
  3. `PULLBACK`: slow direction is non-`NONE`, medium agrees with slow, fast opposes slow — the same structural precondition S1 (below) requires, computed once here and reused.
  4. `COMPRESSION`: as defined above.
  5. `TRANSITION`: uses the **fast** speed's four most recent confirmed pivots (`prior_high`, `last_high`, `prior_low`, `last_low`, all must be `valid`), sorted by `confirmed_time` ascending; if the resulting chronological `structure_label` sequence is exactly `LL,LH,HL,HH` (bullish) or `HH,HL,LH,LL` (bearish), **and** medium's `leg_direction` matches the new direction (fast = timing, medium = validation, exactly per instruction) → `TRANSITION`. Requires at least two structural confirmations by construction (four labeled pivots, not one).
  6. `RANGE`: none of the above, alignment is `MIXED`, and volatility is not `EXPANDING` — an intentionally coarse residual bucket, not a validated range-detection algorithm; used only as a descriptive label in this entry, never as a strategy precondition (matches the instruction's own deferral of range mean-reversion).
  7. Otherwise `UNCLASSIFIED`.

  **`FAILED_BREAK` is explicitly not implemented in this pass and is never emitted by the classifier.** A causal, well-tested `FAILED_BREAK` definition needs short-term memory of a breakout's own origin level beyond what the two-pivot-per-side snapshot exposes; rather than add under-tested mutable classifier state to hit every enum value, this is deferred and disclosed here rather than faked. This does not block S3 (Sweep and Reclaim, below), which implements its own fully self-contained excursion/reclaim detection at the strategy layer and does not depend on a classifier-level `FAILED_BREAK` label.

### Causality proof

Every input to `Evaluate()` is drawn exclusively from `fast`/`medium`/`slow` (the same already-certified, non-repainting `CMSZZTripleZigZagEngine::Snapshot()` output `ProcessClosedBar()` uses for live signal evaluation) and `rates[0..closed_count-1]` (closed bars only — `closed_count` is `ProcessClosedBar()`'s own `copied-1`, which already excludes the forming bar, exactly as every existing strategy in `StrategySuite.mqh` relies on). No pivot's `confirmed_time` can exceed the evaluation bar's own close time, because the engine itself only confirms a pivot once its defining reversal has closed — the same non-repainting contract `NON_REPAINTING_CONTRACT.md` already documents and `Test_MSZZ_Determinism.mq5`/`Test_MSZZ_StructuralReplay.mq5` already certify. The classifier adds no new access path to price/time data — it is a pure reducer over data the engine already proved causal.

### Layer 2 — Strategy-family taxonomy and existing-eight classification (recorded in full in `STRATEGY_CATALOG.md`)

`ENUM_MSZZ_STRATEGY_FAMILY` as specified. Existing eight strategies classified exactly per instruction: FastBreakout/MediumBreakout/SlowBreakout/FastMedConfluence/FastMedContext/MedSlowContext → `BREAKOUT`; NestedPullback → `PULLBACK`; WeightedEnsemble → `ENSEMBLE`. Every candidate gains `family_id` alongside its existing `strategy_id` — family is assigned explicitly at declaration, never inferred later from the setup name.

### Layer 3 — Regime eligibility policy: two modes, `LABEL_ONLY` default

`CMSZZRegimeEligibilityPolicy::IsEligible()` is pure and stateless. `LABEL_ONLY` (default, and the only mode active anywhere in this entry's Stage 1 work) always returns eligible — every existing strategy's behavior is provably unchanged, matching this branch's universal "new research input defaults to a no-op" rule (D019, D025, D026). `RESEARCH_FILTER` mode is defined but not activated until the dedicated regime-filter stage, and even then only for the six predeclared per-family hypotheses in the instruction — no combinatorial search, no gating of A/E.

### Rejected alternatives

- **Inferring `market_phase` from a single confidence score**: rejected per instruction's own explicit requirement for auditable, named fields rather than one opaque number.
- **Implementing `FAILED_BREAK` via a quick heuristic** (e.g., "any close back through the last pivot within N bars"): rejected as under-specified and untestable to the same standard as the other six phases; explicit deferral is more honest than a plausible-looking guess.
- **Using fresh out-of-sample history for the holdout split**: not available — see the data-availability finding above. A within-window chronological split is used instead, disclosed as weaker than genuine unseen data.
- **Combining Stage 0 with a fresh 17-month rerun of A/E**: rejected as computationally wasteful and epistemically redundant — the exact same commit already has that evidence from D026.

### Stage 1 results — regime labeling wired, `LABEL_ONLY`, zero behavior change

Implementation: `Include/MultiSpeedZigZag/Research/RegimeClassifier.mqh` (Layer 1, `CMSZZRegimeClassifier::Evaluate()`), `Include/MultiSpeedZigZag/Research/RegimeEligibilityPolicy.mqh` (Layer 3, `CMSZZRegimeEligibilityPolicy::IsEligible()`), `Include/MultiSpeedZigZag/Core/Types.mqh` (new `ENUM_MSZZ_STRATEGY_FAMILY`, and a new strategy ID `MSZZ_STRAT_ALIGNED_FAST_PULLBACK=1031` for D027 S1 — see the "existing architecture already reserved most of this" finding below), `Experts/MultiSpeedZigZagEA.mq5` (new `InpRegimeEligibilityMode` input, default `0`=`LABEL_ONLY`; `g_last_regime`/`g_last_regime_id` computed once per closed bar immediately after the engine rebuild; `JournalRegime()` writing one row per closed bar to `MSZZ_RegimeJournal.csv`; `JournalCandidate()` extended with `regime_snapshot_id`/`regime_direction`/`regime_alignment`/`regime_phase`/`eligibility_mode`/`eligibility_result`/`eligibility_reason` columns appended to `MSZZ_SignalJournal.csv`).

**A genuinely useful discovery made while assigning IDs to the new strategies**: the original architecture (`ENUM_MSZZ_STRATEGY_ID`, `Docs/MultiSpeedZigZag/STRATEGY_CATALOG.md`, `Docs/MultiSpeedZigZag/ARCHITECTURE.md`, and `OpportunityClusterEngine.mqh`'s `OwnerPriority()`) had already reserved IDs, catalog rows, planned file names, and cluster-arbitration priorities for `BREAKOUT_RETEST` (100), `SWEEP_RECLAIM` (95), `SEQUENTIAL_CONFIRMATION` (85), `STRUCTURE_TRANSITION` (80), and `COMPRESSION_BREAKOUT` (75) — i.e., S2, S3, and (via a differently-named ID) most of the groundwork for S4/S5 was anticipated from the very start of this project. This means Stage 3 will need **zero changes to `OpportunityClusterEngine.mqh`'s priority table** for S2/S3/S4/S5 — only the strategy detection logic itself. One correction made to avoid a silent collision: `MSZZ_STRAT_SEQUENTIAL_CONFIRMATION` (`1020`) was reserved for a **different**, already-documented hypothesis ("fast break followed by medium within a window") than D027's S1 ("Aligned Fast Pullback Continuation") — S1 is assigned a new ID (`1031`, grouped with `NestedPullback`'s `1030` in the `PULLBACK` family) rather than reusing `1020`, and `1020` remains reserved for its original meaning, undisturbed. Full family assignments for the existing eight and the five new IDs are recorded in `STRATEGY_CATALOG.md`, per instruction, with family never inferred later from a setup name.

**Scope decision on `MSZZCandidate.family_id`**: Layer 2 requires every candidate to eventually carry a `family_id` field. Adding it to `MSZZCandidate` itself (used by every strategy, the cluster engine, and the EA) is deferred to Stage 3, when S1–S5 actually exist and family needs to flow through journaling for real — Stage 1's `JournalCandidate()` calls `IsEligible()` with a placeholder `MSZZ_FAMILY_NONE`, which is not a correctness gap for `LABEL_ONLY` mode specifically, since that mode's result never depends on family (checked first, short-circuits before any family-specific branch). This keeps Stage 1's EA-touching change small and bounded rather than bundling a struct-shape change with the observer wiring.

**Scope decision on `MSZZ_TradeAnalytics.csv`**: rather than extend `MSZZExecutionIntent`'s durable, versioned wire format (a materially riskier change) to carry a regime snapshot ID through to trade-close time, Stage 1 relies on the already-established D025 pattern of joining `MSZZ_TradeAnalytics.csv` to `MSZZ_SignalJournal.csv` by `cluster_id`/fill-time to recover a trade's entry-time regime — Stage 2's per-strategy regime attribution will need this join regardless of whether the ID were duplicated into trade analytics directly, so no capability is actually lost.

**Deterministic tests**: `Tests/MultiSpeedZigZag/Test_MSZZ_RegimeClassifier.mq5` (14 cases: determinism, closed-bar-only, bullish/bearish/opposed/mixed/partially-aligned classification, trend-strength and volatility-state boundaries, compression, bullish transition sequencing, premature-transition rejection, unclassified fallback, no-future-pivot-access) — **0 failures**. `Tests/MultiSpeedZigZag/Test_MSZZ_RegimeEligibility.mq5` (12 cases: `LABEL_ONLY` no-op regardless of regime validity, `RESEARCH_FILTER` per-family hypotheses for breakout/pullback/retest/compression, the structure-transition alignment guard, and an explicit lock-in test that sweep/reclaim is *always* ineligible under `RESEARCH_FILTER` until `FAILED_BREAK` is implemented — not silently redirected to another phase) — **0 failures**.

**Regression and shadow proof**: all 17 pre-existing `Test_MSZZ_*` suites pass at 0 failures on the new binary (live tree and isolated instance, hash-verified identical). `shadow_d027_short.ini`/`shadow_d027_long.ini` (identical to the D026 shadow configs plus explicit `InpRegimeEligibilityMode=0`) reproduce **113 candidates/46 clusters (short)** and **431 candidates/178 clusters (long)** — byte-identical to every prior shadow baseline this entire branch has ever produced, zero orders/zero deals in both. `InpRegimeEligibilityMode=0` (`LABEL_ONLY`) is a proven no-op, exactly as designed.

**Regime journal sanity check**: `MSZZ_RegimeJournal.csv` populated correctly during the shadow runs with a real, non-degenerate phase distribution (in the combined short+long shadow sample: 2234 `UNCLASSIFIED`, 1716 `TREND_CONTINUATION`, 350 `PULLBACK`, 335 `COMPRESSION`, 6 `BREAKOUT`, 4 `TRANSITION`, 0 `RANGE`) — confirming the classifier neither crashes nor degenerates to a single always-true phase, and that `UNCLASSIFIED` being the largest bucket is the honest, expected behavior per its own design ("do not force every bar into a confident phase") rather than a sign of a broken classifier.

### Status of remaining stages

Stage 1 is complete as of this addendum. Not yet started, tracked explicitly rather than silently deferred: Stage 2 (descriptive regime attribution of the existing eight strategies), Stage 3 (implement S1–S5, including the `MSZZCandidate.family_id` field deferred above), Stage 4 (standalone fixed-2R screen), Stage 5 (qualified 3R screen), Stage 6 (incremental portfolio analysis against A/E), the regime-filter research stage, the anti-overfitting/decision-category pass, and the final 40-point report. This entry will be extended (append-only) as each lands, exactly as D023/D024/D025/D026 each grew from a decision-only commit into a full results entry.

### Stage 2 results — descriptive entry-time regime attribution of the existing eight

**Run inventory and configuration integrity:** the already-completed isolated
MT5 batch was reused, not rerun. Its source is
`/Users/matt/MT5-MSZZ-TEST/D027_Stage2_Results`, with one directory each for
FastBreakout, MediumBreakout, SlowBreakout, FastMedConfluence,
FastMedContext, MedSlowContext, NestedPullback, and WeightedEnsemble. Every
directory contains a non-empty native HTML report, `MSZZ_RunSummary.csv`,
`MSZZ_TradeAnalytics.csv`, `MSZZ_SignalJournal.csv`, and
`MSZZ_RegimeJournal.csv`. All HTML reports state XAUUSD, M5,
`2025.03.01–2026.07.24`, 99% history quality, 98,944 bars, 387,894 real ticks,
and their unique magic number. The tracked configs use `Model=2`, fixed 2R,
one enabled strategy, no trailing research input, and `LABEL_ONLY`. Magics are
`26072893`–`26072899`, plus `26072901` for FastBreakout. Only FastBreakout
uses the already-authorized D019 `InpResearchMinScoreOverride=3.5` with the
required acknowledgement; the other seven have no test score override.

**LABEL_ONLY equivalence proof:** FastBreakout matches its authorized Stage B
research canonical baseline exactly. MediumBreakout, FastMedConfluence,
FastMedContext, MedSlowContext, NestedPullback, and WeightedEnsemble match
their accepted Stage B canonical summaries and trade analytics exactly
(ignoring intentionally unique magic). FastMedConfluence also exactly matches
D026 canonical A: 224 trades, +0.1261R expectancy, PF 1.2446, 15.1583R maximum
drawdown, 107 long and 117 short. SlowBreakout preserves all 336 Stage B
canonical trades byte-for-byte, then includes one position opened
`2026.07.21 05:35` and closed at tester end `2026.07.23 23:59:59` for
+0.1635R. HTML, RunSummary, and analytics all agree on 337 trades. This
explicit test-end completion explains the small headline change
(-0.0137R to -0.0131R expectancy); it is preserved rather than omitted and
does not indicate a Stage 1 no-op regression.

**Attribution join audit:** `Tools/D027/Stage2/analyze_stage2_regimes.py`
performs the deterministic join
`TradeAnalytics.cluster_id -> EXECUTED SignalJournal row ->
regime_snapshot_id -> RegimeJournal.time`. It requires the snapshot ID to
equal original signal time and cross-checks direction/alignment/phase labels.
Exit-time regimes are never used. All 2,407 trades are preserved and uniquely
attributed: FastBreakout 261, MediumBreakout 513, SlowBreakout 337,
FastMedConfluence 224, FastMedContext 235, MedSlowContext 440,
NestedPullback 136, and WeightedEnsemble 261. Missing signals, duplicate
signals, missing snapshots, duplicate snapshots, unmatched trades, and
non-`LABEL_ONLY` rows are all zero.

**Regime distribution and full-window strategy results:** the emitted
entry-time phase set is BREAKOUT, TREND_CONTINUATION, PULLBACK, COMPRESSION,
and UNCLASSIFIED; no `FAILED_BREAK` is invented. Full-window expectancy is
FastBreakout +0.0798R, MediumBreakout -0.0414R, SlowBreakout -0.0131R,
FastMedConfluence +0.1261R, FastMedContext +0.1010R, MedSlowContext -0.0189R,
NestedPullback -0.0208R, and WeightedEnsemble +0.0777R. Exact distributions
for direction, trend strength, volatility, alignment, and every emitted phase
are in `strategy_regime_distribution.csv`; all required bucket metrics are in
the summary CSVs.

**Window-separated findings:** cumulative R for development / validation /
final holdout is: FastBreakout +11.2100 / +10.5939 / -0.9636;
MediumBreakout -22.8771 / +2.0789 / -0.4654; SlowBreakout -3.4447 /
-13.2258 / +12.2441; FastMedConfluence +13.9368 / +6.8843 / +7.4236;
FastMedContext +11.8657 / +9.2538 / +2.6125; MedSlowContext -10.6094 /
+5.8309 / -3.5288; NestedPullback -8.5741 / +0.2900 / +5.4561; and
WeightedEnsemble +9.8691 / +11.3825 / -0.9636. These are a
within-history chronological split, not independent out-of-sample evidence.
No threshold was changed after inspection.

**Per-strategy descriptive interpretation:** FastMedConfluence remains the
breakout benchmark. FastMedContext is positive but previously shown to
overlap the core. FastBreakout remains a raw research trigger under its
authorized override. MediumBreakout remains potential context evidence;
SlowBreakout potential regime/transition evidence; MedSlowContext potential
higher-order context; NestedPullback the existing pullback prototype; and
WeightedEnsemble a potential evidence/arbitration layer that is already known
to overlap the core. No losing strategy is rescued by a profitable subgroup.

**Core FastMedConfluence:** strongest adequately populated descriptors were
NORMAL trend strength (57 trades, +0.4054R expectancy), EXPANDING volatility
(107, +0.2553R), OPPOSED alignment (123, +0.2188R), and PULLBACK phase
(63, +0.2685R). Weak descriptors were CONTRACTING volatility (35,
-0.3387R), BREAKOUT phase (38, -0.1659R), TREND_CONTINUATION (31, -0.1341R),
and STRONG trend strength (11, -0.1096R); these negative findings are mostly
small samples. Removing the strongest cumulative bucket, EXPANDING
volatility (+27.3122R), leaves the core +0.9325R; removing OPPOSED alignment
(+26.9070R) leaves +1.3377R. The remainder is positive but thin.

NORMAL trend strength and EXPANDING volatility were positive in development,
validation, and holdout, so they are causal descriptive evidence potentially
relevant to later T6/T8 opportunity research. That does **not** establish a
runner filter: STRONG regimes are rare (11/224) and negative, while
FULLY_ALIGNED regimes are 64/224 and approximately flat. Phase/alignment
rankings are not window-stable; for example PULLBACK is positive in
development/validation but negative in holdout. The core itself remains
positive in all three windows.

**Sample and robustness warnings:** fixed labels are `<20 INSUFFICIENT`,
`20–49 EXPLORATORY`, `50–99 MODERATE_SAMPLE`, and `100+
STRONGER_DESCRIPTIVE_SAMPLE`. They are descriptive, not statistical proof.
Validation contains only 52 core trades and final holdout 39. Monthly,
quarterly, side, best-period, best-trade, and top-three-trade exclusion
descriptors are recorded in the machine-readable artifacts. Concentrated
subsets do not authorize promotion, rescue, or gating.

**Artifacts:** tracked inputs are `Tools/D027/d027_stage2_*.ini`. Analysis and
derived results are under `Tools/D027/Stage2/`: `README.md`,
`analyze_stage2_regimes.py`, `strategy_regime_summary.csv`,
`strategy_regime_window_summary.csv`, `strategy_regime_monthly.csv`,
`strategy_regime_quarterly.csv`, `strategy_regime_outlier_checks.csv`,
`strategy_regime_join_audit.csv`, `strategy_regime_distribution.csv`,
`strategy_regime_concentration.csv`, `stage2_findings.md`, and
`output_sha256.txt`. Raw files remain at the exact isolated-instance path
above; they are not duplicated because the eight regime journals alone are
approximately 120 MB.

**Decision boundary:** Stage 2 gates no strategy, promotes no strategy,
modifies neither canonical A nor E, changes no frozen regime threshold, and
deploys nothing live. There is no merge to `main`. Remaining work is Stage 3
(S1–S5), Stage 4 (standalone fixed-2R screen), Stage 5 (qualified 3R screen),
Stage 6 (incremental portfolio analysis), the dedicated regime-filter stage,
anti-overfitting/decision-category pass, and final report.

### Stage 3 results — five distinct default-off strategy families

**Scope and frozen definitions:** Stage 3 implements, but does not screen,
gate, or promote, the five predeclared hypotheses: S1 Aligned Fast Pullback
(`1031`, `PULLBACK`), S2 Breakout Retest (`1040`, `RETEST`), S3 Sweep and
Reclaim (`1050`, `REVERSAL`), S4 Compression Breakout (`1060`,
`COMPRESSION`), and S5 Confirmed Structure Transition (`1070`, `REVERSAL`).
Their five independent EA inputs all default to `false`. Before any Stage 4
result, the stateful constants were frozen as follows: retest = 12 bars,
0.15 fast-ATR touch/reclaim tolerance, 0.30 fast-ATR close invalidation;
sweep = six bars, 0.10 fast-ATR minimum excursion, 0.05 fast-ATR reclaim,
0.50 fast-ATR maximum failure; compression = three consecutive causal
`COMPRESSION` bars and a six-bar release window. These are compile-time
constants, not optimizer inputs. No D027 regime definition or window changed.

**Implementation:** `D027StrategyFamilies.mqh` is a closed-bar-only evaluator
with independent enable flags, structural stops, immutable event/origin IDs,
explicit reasons, mirrored directions, and serialized retest/sweep/compression
state keyed by symbol/timeframe/magic. S1 requires slow direction, non-neutral
medium context, a confirmed fast HL/LH, and its close-confirmed reversal
break. S2 freezes the compatible fast breakout level and cannot count the
breakout bar as its own retest. S3 requires a confirmed pivot shelf, minimum
excursion, closed-bar reclaim, and fast structural confirmation; a wick alone
cannot trigger. S4 reuses the already-frozen causal classifier features and
freezes fast boundaries after compression persistence. S5 accepts only the
classifier's four-pivot `LL,LH,HL,HH` or inverse sequence with medium
validation; a single pivot change cannot trigger. Classifier-level
`FAILED_BREAK` remains deliberately unimplemented.

**Family identity, arbitration, and filtering boundary:** every
`MSZZCandidate` now carries an explicit `family_id`; all existing eight and
all new five assignments are made in code, never inferred from display names.
Clusters retain unique supporting strategy and family IDs. S1 receives the
predeclared owner priority between BreakoutRetest/SweepReclaim and
NestedPullback; the pre-existing priorities for S2–S5 are unchanged.
`RESEARCH_FILTER` applies only to explicitly enabled D027 candidates. It
cannot filter canonical A/E or any existing-eight candidate. `LABEL_ONLY`
remains the default.

**Audit journals and persistence:** `MSZZ_SignalJournal.csv` now includes
strategy family, full entry-time regime fields, cluster owner, overlapping
strategy/family IDs, execution status, and rejection reason.
`MSZZ_SequenceJournal.csv` records sequence ID, strategy/family, state,
direction, origin time/level, confirmation/expiry/invalidation time, exact
final event ID, and reason. Retest, sweep, and compression nonterminal state
is saved after every closed-bar evaluation and on deinitialization. A malformed
existing state file fails EA initialization when any D027 family is enabled;
an absent file is a valid first start.

**Deterministic and compile evidence:** the new
`Test_MSZZ_D027Strategies.mq5` suite passes 20/20 assertions, covering both
directions, premature and invalid paths, retest expiry, exact save/load
continuity, sweep-without-reclaim rejection, compression persistence,
four-pivot transition confirmation, cross-family clustering, existing-family
assignment, and default-off behavior. The EA and all 21 `Test_MSZZ_*` source
files compile in the isolated MT5 tree with **0 errors and 0 warnings**. The
complete runtime suite and parity export were then rerun from those freshly
compiled binaries; every suite reports zero failures and parity export
completed successfully.

**Final default-off regressions:** on the final EA binary,
`shadow_d027_short.ini` reproduces 113 raw candidates / 46 shadow clusters and
`shadow_d027_long.ini` reproduces 431 / 178. Both native reports contain zero
trades and zero deals. Canonical A reproduces 224 trades, +0.1261R expectancy,
PF 1.2446, and 15.1583R maximum drawdown. Canonical E reproduces 213 trades,
+0.1467R expectancy, PF 1.2532, and 16.9205R maximum drawdown. Thus family
identity, journal expansion, and five disabled evaluators are no-ops for the
accepted baselines.

**Artifacts and boundary:** implementation is in
`Include/MultiSpeedZigZag/Strategies/D027StrategyFamilies.mqh`, with wiring in
the EA, types, existing strategy suite, and cluster engine. Deterministic
coverage is in `Tests/MultiSpeedZigZag/Test_MSZZ_D027Strategies.mq5`; the
frozen Stage 3 summary is `Tools/D027/Stage3/README.md`. Raw compiler logs,
tester reports, journals, and terminal logs remain under
`/Users/matt/MT5-MSZZ-TEST`. Stage 3 inspected no S1–S5 performance result,
promoted no strategy, gated no strategy, altered neither A nor E, placed no
live order, and did not merge to `main`. Remaining work is Stage 4 standalone
fixed-2R screening, Stage 5 limited qualified 3R screening, Stage 6
incremental portfolio analysis, the dedicated regime-filter stage,
anti-overfitting/decision categories, and the final report.

### Stage 4 results — standalone fixed-2R screen

**Inventory and immutable screen:** five single-family tests completed once in
the isolated `/Users/matt/MT5-MSZZ-TEST` instance: AlignedFastPullback
(`1031`, magic `26072931`), BreakoutRetest (`1040`, `26072932`),
SweepReclaim (`1050`, `26072933`), CompressionBreakout (`1060`, `26072934`),
and StructureTransition (`1070`, `26072935`). All use XAUUSD M5, tester
`Model=2`, 2025-03-01 through 2026-07-24, structural stops, fixed 2R,
`InpExitOwnedOpposite=true`, canonical costs/execution, and exactly one new
family enabled. Existing strategies and the other new families are disabled.
`LABEL_ONLY` is retained; the research score override, partial close, fixed
target suppression, research trail, and all regime filtering are disabled.
No parameter sweep or rerun occurred, and no frozen Stage 3 trigger or D027
regime definition changed after inspection.

**Run and attribution integrity:** all five native reports and all required
CSV artifacts are non-empty. RunSummary, TradeAnalytics, and native HTML agree
exactly: 110/220 trades/deals for AlignedFastPullback, 354/708 for
BreakoutRetest, 190/380 for SweepReclaim, 84/168 for CompressionBreakout, and
21/42 for StructureTransition. The deterministic join
`TradeAnalytics.cluster_id -> one EXECUTED SignalJournal row ->
regime_snapshot_id -> RegimeJournal.time` uniquely preserves all 759 trades.
Missing or duplicate signal joins, missing or duplicate regime joins,
non-entry-time snapshots, and non-`LABEL_ONLY` trades are all zero. One
StructureTransition position was explicitly closed on the broker's final
modeled tester tick (`2026.07.23 23:59:59`) and is retained.

**Full-window results:** AlignedFastPullback records 110 trades, -6.9288R,
-0.0630R expectancy, PF 0.9023, and 17.6810R maximum drawdown. BreakoutRetest
records 354, -37.7759R, -0.1067R, PF 0.8470, and 49.5189R. SweepReclaim
records 190, +28.6117R, +0.1506R, PF 1.2688, and 18.2941R.
CompressionBreakout records 84, -2.7367R, -0.0326R, PF 0.9353, and 11.4151R.
StructureTransition records 21, -2.1892R, -0.1042R, PF 0.8457, and 8.0000R.
Exact win rate, median R, MFE/MAE, hold-time, exposure, and side metrics are
tracked in `strategy_summary.csv`.

**Frozen-window evidence:** development / validation / final-holdout
cumulative R is AlignedFastPullback -9.0086 / +4.7310 / -2.6512;
BreakoutRetest -18.4909 / -14.9881 / -4.2969; SweepReclaim +17.5830 /
+4.4695 / +6.5592; CompressionBreakout -3.8395 / -0.0146 / +1.1174; and
StructureTransition -5.0000 / 0.0000 / +2.8108. SweepReclaim is the only
family positive in all three chronological windows. Validation and holdout
remain within-history partitions, not independent out-of-sample evidence.

**Concentration and direction:** SweepReclaim remains +22.6117R after its top
three trades and +13.3449R after its best quarter. It has five positive and
two negative quarters. Its long side is +0.0808R expectancy over 96 trades
and its short side +0.2219R over 94, so the result is not dependent on one
direction. Every other family is negative after excluding its top three and
after excluding its best quarter. Full top-1/top-3/top-5, best-one/best-two
quarter, quarterly, and side descriptors are machine-readable.

**Regime description:** no regime is used as a gate. SweepReclaim is positive
in both BULLISH (89 trades, +0.2002R expectancy) and BEARISH (101, +0.1069R)
entry-time regimes. WEAK trend strength is the largest positive trend bucket
(143, +0.2286R), while NORMAL (40, -0.0567R) and the seven-trade STRONG bucket
are negative. OPPOSED alignment is strong descriptively (84, +0.5064R), but
FULLY_ALIGNED (46) and PARTIALLY_ALIGNED (60) are negative. CONTRACTING
volatility is strongest but exploratory (22, +0.4565R); NORMAL is positive
(79, +0.2241R), while EXPANDING is approximately flat (89, +0.0098R).
Every actual phase, the fixed D027 sample label, and its distribution are in
`strategy_regime_summary.csv`; `FAILED_BREAK` is not invented.

**Overlap and unique contribution:** overlap is reported using two explicit
causal descriptors against the preserved canonical FastMedConfluence Stage 2
baseline: same entry-decision bar plus direction, and exact shared structural
origin. SweepReclaim overlaps 28 core decisions for +13.4235R and has 162
same-bar-unique trades for +15.1882R (+0.0938R expectancy); exact shared
origins are zero. AlignedFastPullback's 62 same-bar-unique trades are +3.7627R
despite a negative standalone total, so it is not rescued or promoted.
BreakoutRetest, CompressionBreakout, and StructureTransition have negative
same-bar-unique contribution. These overlap definitions are descriptive and
do not claim statistical independence.

**Exit and cost audit:** own-family opposite exits are 12 / 4 / 24 / 27 / 0
in S1–S5 order. Cross-family exits are structurally impossible in these
single-family tests and equal zero. Unknown exits equal zero; the sole
test-end exit is recorded separately. Spread is present in actual tester
fills; the canonical 80-point spread guard and 30-point deviation are
unchanged. No unsupported commission-R estimate is invented.

**Stage 5 eligibility decision:** only SweepReclaim qualifies for the single
predeclared 3R follow-up: positive expectancy, PF above 1.05, 190 trades,
positive after the top three, both directions positive, no integrity failure,
and profitable unique contribution beyond the core. The other four are not
eligible. This authorizes one fixed 3R research run only; it does not promote,
gate, deploy, or rescue any strategy.

**Artifacts and boundary:** tracked configs are
`Tools/D027/d027_stage4_*.ini`. Deterministic analysis, audits, tables, hashes,
and findings are under `Tools/D027/Stage4/`. Raw artifacts remain at
`/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results` under repository size
discipline. Stage 4 changes no EA code, canonical A, canonical E, frozen
history window, strategy trigger, or regime threshold. There was no live
deployment and no merge to `main`. Remaining work is Stage 5's one qualified
3R SweepReclaim run, Stage 6 incremental portfolio analysis, the dedicated
regime-filter stage, anti-overfitting/decision categories, and the final
report.

### Stage 5 results — limited SweepReclaim 3R screen

**Eligibility and scope:** SweepReclaim was the only Stage 4 family permitted
one fixed-3R run. At 2R it met all seven frozen admission criteria: positive
expectancy, PF above 1.05, 190 trades, both directions positive, +22.6117R
after its top three trades, no integrity issue, and 162 same-bar-unique trades
worth +15.1882R beyond FastMedConfluence. No other family was run at 3R.

The Stage 5 config uses XAUUSD M5, `Model=2`, 2025-03-01 through 2026-07-24,
magic `26072936`, only SweepReclaim enabled, structural stop, fixed 3R target,
`InpExitOwnedOpposite=true`, and the same canonical costs/execution settings.
`LABEL_ONLY` remains active. Research score override, regime filter, trailing,
partial exits, and fixed-target suppression remain disabled. The test
completed once in the isolated MT5 instance; no parameter sweep or rerun was
performed.

**Trigger and integrity equivalence:** both 2R and 3R emit exactly 376 raw
SweepReclaim candidates with identical decision time, strategy/direction,
score, entry, stop, origin/event identity, reason, and entry-time regime
labels. Their `MSZZ_SequenceJournal.csv` files are byte-identical. Thus the
3R result does not modify or retune the frozen trigger. Execution differs
causally because the wider target occupies position ownership longer: 187
cluster IDs are common, three occur only at 2R, and none occur only at 3R.

RunSummary, TradeAnalytics, and native HTML agree exactly at 190 trades /
380 deals for 2R and 187 / 374 for 3R. Every trade joins uniquely to one
executed signal and one original entry-time regime snapshot. Missing or
duplicate joins, eligibility mismatches, trade-count mismatches, and unknown
exits are all zero. The 3R exit inventory is 113 stop, 45 target, and 29
own-family opposite exits; cross-family and test-end exits are zero.

**Headline comparison:** 2R records 190 trades, +28.6117R cumulative,
+0.1506R expectancy, PF 1.2688, and 18.2941R maximum drawdown. The sole 3R
run records 187 trades, +24.3583R cumulative, +0.1303R expectancy, PF 1.2041,
and 27.6952R drawdown. Median / p90 hold rises from 5.0 / 40.2 bars at 2R to
6.0 / 70.4 at 3R; wall-clock exposure rises from 3.1295% to 5.0420%.
Both 3R directions remain positive but weaker: long +0.0841R over 94 trades
and short +0.1769R over 93.

**Frozen-window and concentration result:** 3R development / validation /
final-holdout performance is +26.6608R / +1.4506R / -3.7531R, compared with
2R's +17.5830R / +4.4695R / +6.5592R. The wider target improves known
development but degrades validation and turns the final holdout negative.
Although 3R remains +15.3583R after its top three trades, it becomes -2.9085R
without its best quarter and -11.7694R without its best two. Five quarters
are positive and two negative, but 2025-Q2 contributes +27.2668R—more than
the full result. Monthly and quarterly tables are tracked explicitly.

**Unique contribution and decision:** 3R has 29 same-bar overlaps with the
core worth +23.4235R and 158 same-bar-unique trades worth only +0.9348R
(+0.0059R expectancy). This is substantially weaker than 2R's +15.1882R
unique contribution (+0.0938R). Consequently the 3R target is formally
`REJECTED`: it lowers cumulative R, expectancy, PF, unique expectancy, and
holdout performance while increasing drawdown and best-quarter dependence.
Frozen 2R remains `RESEARCH_ONLY` for Stage 6 actual combined-EA portfolio
testing. It is not yet an out-of-sample, portfolio, or production candidate.

**Artifacts and boundary:** the tracked config is
`Tools/D027/d027_stage5_SweepReclaim_3R.ini`; deterministic analysis, audits,
tables, findings, and hashes are under `Tools/D027/Stage5/`. Raw artifacts
remain at
`/Users/matt/MT5-MSZZ-TEST/D027_Stage5_Results/SweepReclaim_3R` under size
discipline. Stage 5 changes no EA code, strategy trigger, regime threshold,
history split, canonical A, or canonical E. No live deployment occurred and
there was no merge to `main`. Remaining work is Stage 6 incremental portfolio
analysis, the dedicated regime-filter stage, anti-overfitting/decision
categories, and the final report.

### Stage 6 results — actual combined-EA portfolio analysis

**Design and inventory:** the EA exposes one global reward/risk input, so the
portfolio comparison is target matched rather than an invalid arithmetic sum:
canonical A, SweepReclaim, and the actual A+SweepReclaim combination at fixed
2R; canonical E, SweepReclaim, and actual E+SweepReclaim at fixed 3R. Certified
standalone artifacts are reused from D027 Stages 2, 4, and 5 and D026. The two
new combined tests ran once in the isolated MT5 instance and are stored at
`/Users/matt/MT5-MSZZ-TEST/D027_Stage6_Results/A_plus_SweepReclaim_2R`
and `E_plus_SweepReclaim_3R`.

Both configs use XAUUSD M5, tester `Model=2`, 2025-03-01 through 2026-07-24,
canonical costs/execution, structural stops, fixed target, and
`InpExitOwnedOpposite=true`. Only FastMedConfluence and SweepReclaim are
enabled. A uses magic `26072941` and 2R; E uses `26072942` and 3R.
`LABEL_ONLY` remains active. Score override, trailing, partial close, fixed
target suppression, and regime filtering are off. No trigger, score,
threshold, frozen window, canonical A, or canonical E definition changed.

**Run and join integrity:** every required native HTML and CSV artifact is
present and non-empty. A+SweepReclaim reconciles at 371 trades / 742 deals in
HTML, RunSummary, and TradeAnalytics; E+SweepReclaim reconciles at 353 / 706.
Every combined trade joins to exactly one executed signal and exactly one
original entry-time regime snapshot. Missing, duplicate, ambiguous, non-entry
snapshot, eligibility, and trade-count mismatches are zero. The A run has
1,037 raw candidates, 371 executions, 317 ownership rejections, 139 duplicate
cluster rejections, and two expirations. E has 1,036 / 353 / 337 / 138 / two.

**Headline incremental result:** canonical A records 224 trades, +28.2447R,
15.1581R drawdown; actual A+SweepReclaim records 371, +20.7400R, 25.2798R
drawdown. The addition therefore loses 7.5047R versus A while adding 147
trades and 10.1217R drawdown. Canonical E records 213 trades, +31.2465R,
16.9204R drawdown; E+SweepReclaim records 353, +20.5933R, 28.1164R drawdown.
It loses 10.6532R, adds 140 trades, and adds 11.1960R drawdown.

**Window and concentration evidence:** A+SweepReclaim development /
validation / final-holdout R is +13.0881 / +1.5663 / +6.0856, below A's
+13.9368 / +6.8843 / +7.4236 in every window. E+SweepReclaim is +13.3488 /
+6.4847 / +0.7598 versus E's +7.5366 / +14.8843 / +8.8256: development
improves, but validation and holdout deteriorate sharply. Both combinations
remain positive without their top three trades (+14.7400R and +11.5933R),
but excluding the best quarter leaves only +6.8464R and +4.4775R. They do not
improve the matched cores on total return, drawdown, or holdout behavior.

**Ownership, uniqueness, and exits:** the actual A combination executes 126
SweepReclaim-owned trades worth +11.0677R (+0.0878R expectancy), retains 214
baseline core clusters, displaces ten, and newly executes 31 core clusters.
The E combination executes 123 SweepReclaim-owned trades worth +5.2142R
(+0.0424R), retains 199, displaces 14, and newly executes 31. Executed
SweepReclaim-owned trades have no same-bar/direction core overlap in either
combined run; exact executed cluster overlap is also zero because ownership
has already resolved candidate overlap. Positive new-owner contribution is
therefore real, but it does not compensate for altered core paths.

The A exit inventory is 153 stops, 96 targets, 56 own-family opposite exits,
and 66 cross-family opposite exits. E is 161 / 63 / 59 / 70. Unknown exits
are zero. These actual cross-family reversals explain why standalone
contributions cannot be added and why the core outcome changes.

**Diversification descriptors:** matched standalone A/SweepReclaim and
E/SweepReclaim trade-return correlations are 0.4606 and 0.4749 over 28 and 29
overlaps. Daily return correlations are 0.1357 and 0.1947; weekly 0.0517 and
0.1397; monthly 0.4687 and 0.4079; daily drawdown-level correlations 0.1963
and 0.1767. Rolling eight-week and three-month descriptors are tracked rather
than reduced to one full-period number. During core-negative months, the A
combination improves two of five and worsens three; E improves two of four
and worsens two. It does not robustly repair weak core periods.

**Decision:** SweepReclaim as an actual combined portfolio addition to A or E
under the frozen shared-ownership architecture is `REJECTED`. The result is
not promoted or rescued by its positive standalone or owner-only subset.
Frozen standalone SweepReclaim 2R remains `RESEARCH_ONLY` for the dedicated
regime-filter stage; no strategy is gated, promoted, or deployed here.

Tracked configs are `Tools/D027/d027_stage6_A_plus_SweepReclaim_2R.ini` and
`Tools/D027/d027_stage6_E_plus_SweepReclaim_3R.ini`. Deterministic analysis,
config/join/arbitration/exit audits, full and window results, incremental and
owner contributions, uniqueness, outlier checks, correlations, weak-month
evidence, findings, and hashes are under `Tools/D027/Stage6/`. Raw reports
remain outside the repository under established size discipline. Stage 6
changes no EA code. No live deployment occurred and there was no merge to
`main`. Remaining work is the dedicated regime-filter stage,
anti-overfitting/decision categories, and the final report.

### Stage 7 results — frozen regime-filter research

**Predeclared scope:** the dedicated filter stage runs exactly five fixed-2R
standalone comparisons, one for each default-off D027 strategy S1–S5. The
only change from its Stage 4 control is
`InpRegimeEligibilityMode=1` (`RESEARCH_FILTER`), plus report and magic
identity. There is no combinatorial regime search, parameter optimization,
or threshold change. A and E are not gated or rerun. The policy remains the
six frozen family/strategy hypotheses implemented and deterministically
tested in Stage 1; classifier-level `FAILED_BREAK` remains unimplemented.

Tracked configs use magics `26072951`–`26072955`, XAUUSD M5, `Model=2`,
2025-03-01 through 2026-07-24, fixed 2R, structural stops, canonical
costs/execution, exactly one enabled D027 strategy, and no score override,
trailing, partial close, or fixed-target suppression. The live-tree and
isolated EA binaries retain matching SHA-256
`a91c59506db7e7ef4a10cb060d5bc1cd8e782d6331b20e07ee9bf87b34482840`.

An initial launcher invocation referenced the Stage 4 config directory with a
Stage 7 filename. MT5 rejected that nonexistent config before initialization;
it produced no report or research artifact. The path was corrected before
the evidence batch. The valid AlignedFastPullback test then completed but
legitimately produced no RunSummary or TradeAnalytics because it had zero
trades; its native report and signal/regime journals were preserved rather
than rerunning it. The collector was made zero-trade-aware and resumed at
BreakoutRetest, so each valid Stage 7 config ran exactly once.

**Trigger and attribution integrity:** for every strategy, the ordered raw
candidate stream is identical to Stage 4 across 20 causal fields: decision
time, symbol/timeframe, strategy/setup/direction, score, entry/stop/target,
origin/event/reason, explicit family, snapshot ID, and all entry-time regime
labels. Counts are 210 AlignedFastPullback, 402 BreakoutRetest, 376
SweepReclaim, 966 CompressionBreakout, and 242 StructureTransition. Thus the
filter changes eligibility only, never the frozen trigger.

Native HTML reports agree with analytics at 0/0 trades/deals for
AlignedFastPullback, 96/192 for BreakoutRetest, 0/0 for SweepReclaim, 73/146
for CompressionBreakout, and 21/42 for StructureTransition. Every nonzero
trade joins uniquely to one executed signal and one original entry-time
regime snapshot; missing or ambiguous joins are zero. Filtered cluster IDs
are strict subsets of their controls. One retained BreakoutRetest trade and
four retained CompressionBreakout trades have causally different close/R
paths because filtering an opposite signal changes position duration; this
is reported, not treated as arithmetic subset performance.

**Eligibility action:** all 210 AlignedFastPullback candidates are rejected.
The classifier's causal `PULLBACK` phase requires fast structure to oppose
slow, while the frozen pullback policy additionally requires aligned
structure; that conjunction is unreachable in actual classifier output even
though the pure policy can accept a synthetic state. All 376 SweepReclaim
candidates are rejected for the explicitly predeclared reason that
`FAILED_BREAK` is unavailable. BreakoutRetest rejects 297 of 402 raw
candidates and executes 96. CompressionBreakout rejects only 11 of 966 raw
candidates; clustering/ownership still reduces the remainder to 73 trades.
StructureTransition rejects none by regime and reproduces all 21 trades, so
its filter is behaviorally redundant with its trigger.

**Performance:** AlignedFastPullback goes from 110 trades / -6.9288R to zero.
BreakoutRetest goes from 354 / -37.7759R to 96 / -8.9922R and remains
negative. SweepReclaim's positive 190-trade / +28.6117R standalone is
entirely suppressed. CompressionBreakout goes from 84 / -2.7367R to 73 /
+4.4115R, +0.0604R expectancy, PF 1.1257, and 6.7882R drawdown.
StructureTransition remains exactly 21 / -2.1892R.

**Chronology and concentration:** filtered BreakoutRetest development /
validation / holdout R is +3.0032 / -18.0004 / +6.0050, with only 12 holdout
trades. Filtered CompressionBreakout is +0.7874 / -0.0146 / +3.6387; its
holdout has only 15 trades. CompressionBreakout becomes -1.5885R without its
top three trades and -0.1801R without its best quarter. It therefore fails
the project's no-rescue and concentration safeguards despite a positive
headline. StructureTransition retains only 21 full-window trades and remains
negative. Validation and holdout are the already-declared within-history
partitions, not independent out-of-sample evidence.

**Decision:** no Stage 7 filter is promoted, accepted for production, or
applied to A/E. AlignedFastPullback's filter hypothesis is `REJECTED` as
causally unreachable; BreakoutRetest is `REJECTED`; the SweepReclaim filter
is `UNAVAILABLE` under the honest classifier limitation and is not replaced
with a post-hoc proxy; CompressionBreakout remains `REJECTED` rather than
being rescued by a concentrated subset; StructureTransition is `REJECTED`
and its filter is redundant. Standalone SweepReclaim 2R remains
`RESEARCH_ONLY` evidence, but its Stage 6 portfolio addition and Stage 7
frozen filter are both rejected/unavailable. `LABEL_ONLY` remains the
default and no production behavior changes.

Configs are `Tools/D027/d027_stage7_*_Filter.ini`. Deterministic analysis,
config/trigger/status/join/path audits, full and window comparisons, outlier
checks, findings, and hashes are under `Tools/D027/Stage7/`. Raw artifacts
remain at `/Users/matt/MT5-MSZZ-TEST/D027_Stage7_Results`. Stage 7 changes no
EA code, frozen trigger, regime definition, A, or E. No live deployment
occurred and there was no merge to `main`. Remaining work is the final
anti-overfitting/decision-category pass and D027 report.

### Final anti-overfitting pass and D027 closeout

Adjacent-threshold checks were performed offline from continuous entry-time
regime measurements, never by changing the frozen classifier or selecting a
winning neighbor. Volatility was inspected at 0.75/0.80/0.85 and
1.15/1.20/1.25, directional efficiency at 0.30/0.35/0.40 and
0.60/0.65/0.70, and compression ratio at 0.30/0.35/0.40.
FastMedConfluence's EXPANDING subset stays positive across all three
expansion boundaries (+0.2535/+0.2553/+0.1991R expectancy); SweepReclaim
changes sign (+0.0988/+0.0098/-0.0461R), so no expanding-volatility gate is
justified for it.

The required outlier, temporal, direction, regime, uniqueness, overlap,
portfolio, correlation, exit, persistence, and reconciliation evidence is
consolidated in the numbered 40-point
`Docs/MultiSpeedZigZag/D027_FINAL_REPORT.md`. Machine-readable formal
categories and the full neighborhood table are under `Tools/D027/Final/`.

Final new-family categories are: AlignedFastPullback `REDESIGN_REQUIRED`;
BreakoutRetest `REJECTED`; SweepReclaim `RESEARCH_ONLY`; CompressionBreakout
`REJECTED`; StructureTransition `REJECTED`. No new family is a standalone or
portfolio validation candidate and none adds accepted incremental edge beyond
FastMedConfluence. FastMedConfluence remains the sole
`STANDALONE_VALIDATION_CANDIDATE` benchmark, pending genuinely independent
data. The regime observer is retained with `LABEL_ONLY`; no
`RESEARCH_FILTER` is accepted for current use.

D027 is complete as a bounded research program. It produced a causal,
auditable architecture and one interesting standalone research signal
(SweepReclaim 2R), but no production promotion. A/E remain unchanged, all new
families remain default-off, no merge to `main` occurred, and no live or
production deployment occurred.
