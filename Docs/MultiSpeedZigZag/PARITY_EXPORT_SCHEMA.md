# Pine ↔ MQL5 Parity Export Schema

## Objective

Produce machine-comparable records from Pine and MQL5 for the same symbol, timeframe, parameters, and closed-bar interval.

## Run manifest

Every export must include:

- engine version and commit SHA
- platform and script version
- symbol and broker feed
- timeframe
- timezone/session assumptions
- start and end timestamps
- fast/medium/slow ATR lengths and multipliers
- minimum pivot spacing
- reversal source mode
- breakout source mode
- line projection mode
- ATR definition
- price precision

Comparisons without matching manifests are invalid.

## Bar export

File: `bars.csv`

```text
bar_index,time,open,high,low,close,volume,atr_fast,atr_medium,atr_slow
```

`bar_index` must be chronological and zero-based inside the exported interval. Time must be UTC ISO-8601 or Unix seconds, consistently across platforms.

## Pivot export

File: `pivots.csv`

```text
engine,speed,pivot_kind,pivot_index,pivot_time,confirmed_index,confirmed_time,price,structure_label,pivot_id
```

Required rules:

- One row per confirmed pivot.
- No candidate/forming pivots in this file.
- `pivot_index` and `confirmed_index` are both required.
- IDs may differ between platforms; identity comparison uses semantic fields first.

## Trendline export

File: `trendlines.csv`

```text
engine,speed,line_kind,line_id,anchor1_index,anchor1_time,anchor1_price,anchor2_index,anchor2_time,anchor2_price,active_from_index,broken_index
```

File: `line_values.csv`

```text
bar_index,time,speed,line_kind,line_id,value,is_active,is_broken
```

This file exposes geometry differences, especially bar-index versus elapsed-time projection.

## Breakout export

File: `breakouts.csv`

```text
engine,speed,direction,bar_index,time,line_id,line_value,source_value,distance_points,distance_atr,event_id
```

Only first cross events are exported. Remaining above or below an already-broken line must not create repeated rows.

## Candidate export

File: `candidates.csv`

```text
bar_index,time,strategy_id,strategy_version,direction,origin_type,origin_id,event_id,entry,stop,target,raw_score,passes_filters,reason
```

## Cluster export

File: `clusters.csv`

```text
bar_index,time,cluster_id,direction,origin_id,state,owner_strategy_id,supporting_strategy_ids,evidence_mask,combined_score,stop,expiry_time
```

### `cluster_id` encoding (format version `MSZZC1`, see DECISION_LOG.md D004)

`cluster_id` is a **self-describing, length-prefixed** string, not a naive delimited value. It must not be parsed by splitting on `|`:

```text
MSZZC1|<len>:<symbol>|<len>:<timeframe>|<len>:<direction>|<len>:<origin_type>|<len>:<origin_id>
```

Each `<len>` is the exact character count of the value that follows its `:`. A correct decoder consumes exactly `<len>` characters for each field rather than scanning for the next `|`, because `origin_id` is frequently itself an already pipe-delimited breakout/pivot identity and may contain any number of `|` or `:` characters. `CMSZZOpportunityClusterEngine::EncodeClusterId()`/`DecodeClusterId()` in `OpportunityClusterEngine.mqh` are the only correct way to construct or parse this field.

Cluster IDs produced before 2026-07-25 used an unversioned `MSZZC|symbol|timeframe|direction|origin_type|origin_id` format that is ambiguous when `origin_id` itself contains `|`. Any exported `clusters.csv` from before that date is legacy evidence only — its `cluster_id` values cannot be reliably decoded and should not be compared field-by-field against `MSZZC1`-format exports.

## Comparison tolerances

- Price: no more than one symbol tick unless a documented feed difference applies.
- Time: exact closed-bar timestamp.
- ATR: tolerance declared in manifest.
- Pivot semantics: pivot and confirmation indexes must match exactly for strict parity.
- Trendline values: one tick strict target; mismatches are classified before accepting wider tolerance.

## Mismatch categories

- `DATA_FEED`
- `ATR_DEFINITION`
- `REVERSAL_SOURCE`
- `PIVOT_TIE_RULE`
- `PIVOT_SPACING`
- `GEOMETRY_BAR_INDEX_VS_TIME`
- `BREAKOUT_SOURCE`
- `FORMING_BAR_LEAK`
- `IMPLEMENTATION_DEFECT`
- `INTENTIONAL_SPEC_DIFFERENCE`

## Acceptance report

The parity report must state totals and mismatch counts by speed and category. A percentage alone is insufficient. Every mismatch must be traceable to concrete exported rows.