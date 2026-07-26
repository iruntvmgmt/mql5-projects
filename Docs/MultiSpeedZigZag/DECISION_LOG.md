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

**Example:**

- Old (ambiguous): `MSZZC|XAUUSD|5|-1|2|BO|XAUUSD|5|1|S|1784639100|MSZZ|XAUUSD|5|1|-1|1784637600|1784638200`
- New (unambiguous): `MSZZC1|6:XAUUSD|1:5|2:-1|1:2|76:BO|XAUUSD|5|1|S|1784639100|MSZZ|XAUUSD|5|1|-1|1784637600|1784638200`

  (`76` is the exact character length of the `origin_id` value that follows; a decoder reads exactly those 76 characters regardless of how many `|` or `:` characters they contain.)

### Reason

Length-prefixing was chosen over percent/escape-encoding the `origin_id` (option B) because it is deterministic and reversible without needing an escaping/unescaping pass or a table of characters that must be escaped. It has no failure mode for "did I escape everything the origin ID might ever contain" — the origin ID's internal structure is completely irrelevant to correct decoding.

### Consequences

- `CMSZZOpportunityClusterEngine` gains dedicated `EncodeClusterId(...)` and `DecodeClusterId(...)` methods. `ClusterId()`/`Build()` must call `EncodeClusterId(...)` rather than constructing the string inline, and no other code may construct or parse a cluster ID by ad hoc string manipulation.
- The cluster-ID format version is bumped from the old unversioned `MSZZC|` prefix to `MSZZC1|`. Old and new IDs are textually distinct (different literal prefixes), so an old-format ID stored in a legacy `MSZZ_Consumed_*.txt` event-store file can never string-match a new-format ID and therefore can never falsely suppress a legitimate new-format cluster as a duplicate.
- This is not a reason to skip cleanup: legacy consumed-event entries become permanently orphaned garbage in any event-store file that mixes old- and new-format IDs. **The event store must be cleared or migrated before the next shadow-testing session that uses the new format**, so that evidence isn't split across two incompatible ID schemes. No automatic migration is performed by this change — clearing/migrating an event-store file is an operational step for whoever runs the next test session, not something this commit does silently.
- `PARITY_EXPORT_SCHEMA.md`'s `clusters.csv` documentation must reflect that `cluster_id` is now a self-describing length-prefixed string, not a naive five-field pipe-delimited value.
- Existing shadow-test evidence in `BACKTEST_LOG.md` from before this decision remains valid evidence of clustering/dedup *behavior*, but any cluster-ID *values* quoted there are legacy-format examples, not current-format examples.
