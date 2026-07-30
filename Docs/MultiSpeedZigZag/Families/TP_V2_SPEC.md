# Trend Pullback v2 — Prospective Specification

Status: `SPECIFICATION_GAP` and `INPUT_OWNERSHIP_GAP`; implementation prohibited.

## Hypothesis and opportunity

After one event-owned trend impulse, price must move materially **toward** an approved value measure, enter a frozen proximity band without invalidating the trend, then resume. Merely remaining above/below VWAP is insufficient. One opportunity spans pullback start through resumption/terminal reset.

## Inputs and sequence

The value measure (VWAP or ALMA), session anchoring, trend event/age, pre-pullback impulse and value-distance series must be captured with ownership. The current system does not provide an owned impulse object.

| State | Guard | Next | Emit | Same-call re-arm |
|---|---|---|---|---|
| WAIT_TREND | owned mature trend impulse | WAIT_APPROACH | no | no |
| WAIT_APPROACH | distance moves toward value by required amount | IN_VALUE | no | no |
| IN_VALUE | inside proximity/depth bounds | IN_VALUE | no | no |
| IN_VALUE | exact resumption trigger | EMITTED | once | no |
| active | opposite transition/overextension/expiry | WAIT_RESET | no | no |
| WAIT_RESET | neutral/new impulse | WAIT_TREND | no | no |

## Gaps and identity

Value source/anchor, proximity, trend age, movement-toward formula, pullback start/depth, minimum/maximum distance, resumption, opposition, overextension and reset are unresolved.

```text
origin_id   = TP2|symbol|tf|trend_impulse_event_id|value_anchor_id
sequence_id = origin_id|PULLBACK|pullback_start
event_id    = sequence_id|RESUME|trigger_time
```

Typed metadata includes the value series/anchor, distance at impulse/start/minimum/trigger, owned pivots, trend age, pullback extrema and all invalidations. Simulator/production parity and v2 production allocation remain blocked.

