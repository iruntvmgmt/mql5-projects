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