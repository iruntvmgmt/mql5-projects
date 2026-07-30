# Momentum Continuation v2 — Prospective Specification

Status: `INPUT_OWNERSHIP_GAP` and `SPECIFICATION_GAP`; implementation prohibited.

## Hypothesis and opportunity

A coherent fast impulse breaks structure in the direction of aligned medium structure, pauses with controlled pullback, then resumes before an opposite **medium** break or obstruction disproves continuation. One opportunity begins with one event-owned impulse/break and ends on emission, expiry, invalidation, or reset. A new opportunity requires a new impulse event after neutral reset; same-call and still-true re-arm are forbidden.

## Ownership

The impulse must expose one immutable object containing start/end pivot IDs/prices/times, broken level ID/price, break time/direction, amplitude in price and arm ATR units, and efficiency window. Current code combines `f.bullish_event_id`, current last-low/high and `regime.fast_swing_amplitude_r`; common ownership is unproven. No proxy is authorized.

## Sequence

| State | Guard | Next | Emit | Same-call re-arm |
|---|---|---|---|---|
| WAIT_IMPULSE | owned fast impulse + medium alignment + quality | PAUSE | no | no |
| PAUSE | controlled pullback for permitted bars | PAUSE | no | no |
| PAUSE | exact resumption trigger, valid geometry | EMITTED | once | no |
| PAUSE | opposite medium break/obstruction/expiry | WAIT_RESET | no | no |
| WAIT_RESET | neutral then a new owned impulse | WAIT_IMPULSE | no | no |

Active state is evaluated first and terminal transitions return.

## Gaps and formulas

Impulse owner, efficiency window, alignment timing, pause length, shallow/controlled depth, obstruction, reset, entry/stop/target and maximum extension remain unresolved. Opposite fast break is not an acceptable substitute for opposite medium confirmation.

```text
origin_id   = MC2|symbol|tf|impulse_event_id
sequence_id = origin_id|PAUSE|pause_start
event_id    = sequence_id|RESUME|trigger_time
```

Metadata must type every owned impulse field, medium alignment event/time, pause extrema/depth/bars, obstruction, trigger and geometry. Simulator/production share one-position occupancy and a frozen stop/target-only policy unless explicitly reviewed before screening. V2 production allocation is deferred.

