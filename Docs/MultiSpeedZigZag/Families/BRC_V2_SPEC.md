# Break-Retest Continuation v2 — Prospective Specification

Status: `INPUT_OWNERSHIP_GAP` and `SPECIFICATION_GAP`; implementation prohibited.

## Hypothesis and opportunity

One confirmed medium break closes a required distance beyond its immutable broken structural level; the first eligible retest rejects that level and continuation triggers before the lifecycle expires. One opportunity is tied to one break event. A later touch cannot silently replace the selected rejection event.

## Required break record

Arm input must contain break event ID/time/direction, broken level ID/price/confirmation, source pivots, close distance/body values and ATR. `resistance_now`/`support_now` are time-varying projections and cannot be treated as the immutable broken level absent an event-owned copy from the engine.

## Sequence

| State | Guard | Next | Emit | Same-call re-arm |
|---|---|---|---|---|
| WAIT_BREAK | owned break passes distance/body | WAIT_RETEST | no | no |
| WAIT_RETEST | before minimum bars | WAIT_RETEST | no | no |
| WAIT_RETEST | first eligible touch within penetration | REJECTION_FROZEN | no | no |
| REJECTION_FROZEN | continuation trigger | EMITTED | once | no |
| active | expiry/over-test/opposite break/penetration | WAIT_RESET | no | no |
| WAIT_RESET | neutral/new break | WAIT_BREAK | no | no |

Terminal transitions return. Comparison windows exclude the current trigger bar unless explicitly stated.

## Gaps and identity

Minimum close/body, retest delay/window, first-versus-latest touch, rejection formula, penetration, over-test count and reset remain unresolved.

```text
origin_id   = BRC2|symbol|tf|break_event_id|broken_level_id
sequence_id = origin_id|RETEST|first_touch_time
event_id    = sequence_id|TRIGGER|trigger_time
```

Typed metadata includes the complete break record, touch count/times, frozen rejection bar, penetration, invalidation and geometry. Simulator and production must share occupancy, opposite behavior, entry and exits. V2 production allocation is deferred.

