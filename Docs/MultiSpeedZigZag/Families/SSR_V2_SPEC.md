# Session Sweep Reversal v2 — Prospective Specification

Status: `SPECIFICATION_GAP`; implementation prohibited.

## Hypothesis and opportunity

An accepted session-range extreme is swept during a later eligible liquidity window, price fails to accept outside, and a confirmed close reclaims the level. One economic opportunity is one **fresh outside excursion** from an inside/neutral state through one immutable session level until reclaim, invalidation, expiry, or session end.

Freshness requires a closed bar at or inside the range after the preceding lifecycle terminates, followed on a later closed bar by an outside transition. Same-call, same-trigger-bar, and still-outside re-arms are forbidden. Expiry/invalidation cannot re-arm until reset. One excursion may emit once.

## Frozen clock contract

`SESSION_TIME_AUTHORITY.md` authority `MSZZ_TIME_AUTH_C1` governs SSR. The Asian range is `[00:00,08:00)` UTC; London eligibility is `[08:00,12:00)` UTC; New York eligibility is `[08:30,12:00)` US Eastern. Broker and Eastern offsets come only from a reviewed, committed per-dataset transition schedule. Host timezone lookup and inferred broker DST are forbidden. Missing authority fails closed. The UTC day boundary terminates active state and the next day requires a newly frozen range.

## Inputs and ownership

Session ID/date, timezone offsets, DST regime, immutable range high/low and construction close time must be copied at range freeze. Arm captures level ID/price, direction, arm time, arm ATR and sweep extreme. Later range or snapshot changes may not mutate them. Missing clock/range ownership fails closed.

## Sequence and transitions

| State | Event/guard | Next | Emit | Re-arm same call |
|---|---|---|---|---|
| WAIT_RANGE | authoritative range frozen | INSIDE_READY | no | no |
| INSIDE_READY | eligible closed bar crosses outside by frozen threshold | ARMED | no | no |
| ARMED | new extreme | ARMED/update extreme | no | no |
| ARMED | close reclaims by frozen buffer with valid geometry/cost | EMITTED | once | no |
| ARMED | failure/expiry/session end | WAIT_RESET | no | no |
| EMITTED | any bar | WAIT_RESET | no | no |
| WAIT_RESET | later close returns inside/neutral | INSIDE_READY | no | no |

Active evaluation precedes arming, but any terminal transition returns immediately. The trigger is the current closed bar; synthetic entry is the next executable bar/tick as separately frozen.

## Geometry and identity

Thresholds, reclaim buffer, failure distance, window bars, stop buffer, target and spread/risk maximum require explicit reviewed formulas before authorization. Prospectively:

```text
origin_id   = SSR2|symbol|tf|range_session_id|range_date|side|level_id
sequence_id = origin_id|ARM|arm_time
event_id    = sequence_id|FINAL
```

Required metadata: clock regime, broker/UTC/ET timestamps, range open/close/high/low IDs, side, reset time/type, arm ATR/time/price, sweep extreme, reclaim values, spread/risk and every terminal reason.

## Simulator/production

Both must use one open family position; candidates while open are rejected; stop/target/test-end are the only exits; no opposite close or reversal; fixed declared risk and target. Production IDs/book/magic remain unallocated for v2. Cluster origin is `sequence_id`; consumed key is strategy-qualified cluster ID.
