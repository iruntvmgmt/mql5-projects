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