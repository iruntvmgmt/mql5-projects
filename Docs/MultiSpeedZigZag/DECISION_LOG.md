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