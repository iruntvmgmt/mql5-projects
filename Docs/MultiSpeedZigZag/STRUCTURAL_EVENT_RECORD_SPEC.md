# Structural Event Record Specification

Version: `MSZZSE2`. Scope: additive core/replay evidence only.

## Event ownership

Origin adjacency is captured during the bar scan when the second projection anchor is confirmed. The certified record is constructed immediately after the final-bar break comparison from retained exact comparison inputs. It owns immutable copies of the exact previous/event projections, their two same-kind and same-speed pivot anchors, the direction-specific origin associated with the second projection anchor, event closes, ATR and derived geometry.

Bullish:

- projection anchors are `prior_high` and `last_high`;
- broken pivot is `last_high`, the second projection anchor;
- origin is the latest low that was already confirmed when that broken high was confirmed, whose pivot time and confirmation time both precede the broken high’s corresponding times;
- the previous close is at or below the previous projection and event close is above the event projection.

Bearish mirrors this with `prior_low`, `last_low`, and the latest chronologically preceding high.

The origin is captured alongside the second anchor when that pivot is confirmed. It is never selected later from final snapshot slots. If no such adjacent origin exists, the break flag and legacy ID remain unchanged, but the certified record is invalid with a diagnostic reason.

## Projection basis

The record retains both anchors’ IDs, prices, pivot times and confirmation times, plus previous/event projected levels. Projection is:

```text
slope = (anchor2.price-anchor1.price) /
        (anchor2.pivot_time-anchor1.pivot_time)
level(t) = anchor2.price + slope*(t-anchor2.pivot_time)
```

Both anchor times must be strictly ordered. The record validator recomputes both levels from the copied anchors and bar times.

## Identity

```text
MSZZSE2|
LP(symbol)|LP(timeframe)|LP(speed)|LP(direction)|LP(event_time)|
LP(broken_pivot_id)|LP(anchor1_id)|LP(anchor2_id)|LP(source_origin_pivot_id)
```

`LP(x)` is decimal byte/character length, colon, then value. IDs change with speed, direction, event time, broken pivot, projection basis, or source origin. `MSZZSE1` is retained only in historical infrastructure evidence and must not be consumed by new code. Legacy `BO|...` IDs remain untouched compatibility fields and are not ownership-certified identities.

## Geometry

```text
break_distance = abs(event_close-event_projected_level)
break_distance_atr = break_distance/atr_at_event
impulse_origin_price = source_origin_pivot.price
impulse_extreme_price = max(event high, broken pivot price) bullish
                        min(event low, broken pivot price) bearish
impulse_distance = abs(impulse_extreme_price-impulse_origin_price)
impulse_distance_atr = impulse_distance/atr_at_event
```

Event high/low is passed explicitly to the shared builder; it is not reconstructed from the snapshot.

## Validation

Required: finite positive prices/ATR; known speed and long/short direction; nonempty distinct projection IDs; every copied pivot has `record.speed`; bullish anchors/broken pivot are HIGH and origin is LOW; bearish anchors/broken pivot are LOW and origin is HIGH; strictly ordered anchor pivot times; origin pivot and confirmation chronology preceding the broken pivot; broken pivot equals anchor 2; event time not before broken confirmation; exact projection, break-distance and normalized-distance recomputation within `max(point_size*0.1,1e-10)`; and directionally valid cross/impulse.

Any construction or public validation failure blanks every consumable identity, ownership, price, time, and geometry field. Only `validation_reason` remains and `valid=false`. Attempted values are not exposed through the certified record. Validation never changes legacy flags.

## Lifetime and parity

Each `MSZZSpeedSnapshot` has additive bullish and bearish records representing only the final bar of that rebuild. Reset clears them. Copying a snapshot/record produces an immutable value. `StructuralReplay` exposes equivalent per-bar records and calls the same builder and validator. Engine/replay parity proves implementation consistency through that shared policy; it is not an independent ownership algorithm. Formula duplication is prohibited.
