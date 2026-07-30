# Structural Event Ownership Audit

Audit base: `2fbd246a31a74b31c82ddf0f934ed831e36aa0de`.

## Verdict

No existing repository type is an immutable coherent structural-break record. `MSZZPivot` is immutable once copied, but represents one pivot, not a break or impulse. `MSZZSpeedSnapshot` is rebuilt current state. Break event IDs are strings, not records. `MSZZRegimeState` derives contemporaneous statistics without an event owner.

Consequently MC, BRC and TP remain blocked. The next authorized code change is a shared `MSZZStructuralEventRecord` produced by the engine and replay path, with parity tests, before any family code changes.

## Exact production and update order

`CMSZZTripleZigZagEngine::Rebuild()` calls `BuildSpeed()` independently for fast, medium and slow. `BuildSpeed()` first resets the snapshot, then scans the entire chronological rate prefix. During that scan `ConfirmHigh/ConfirmLow` replace `prior_*` and `last_*`. After the scan:

1. current ATR/threshold and unfinished leg/extreme are finalized;
2. `resistance_now` and `support_now` are projected at the final represented closed bar from the then-current same-kind pivot pairs;
3. previous-bar projections are independently calculated;
4. break flags compare previous and current closes to those projections;
5. a break ID is formatted from symbol, timeframe, speed, direction, event time and only `last_high.id` for bullish or `last_low.id` for bearish.

A final-bar reversal may confirm a pivot during the same rebuild before projections and break flags are calculated. Therefore pivot slots can change in the same rebuild that raises a break.

## Answers

- `bullish_event_id` does not own `resistance_now`. It names the time and last-high ID used, but contains no projected price, prior-high ID, or immutable projection record.
- `bearish_event_id` does not own `support_now` for the symmetric reason.
- `fast_swing_amplitude_r` does not describe the same break event by contract. `RegimeClassifier::SwingAmplitudeR()` uses whatever current `last_high`, `last_low`, and ATR the snapshot contains.
- `last_high/last_low` are not proven to form the impulse associated with a break. They are independently maintained latest pivots of each kind; temporal adjacency and direction-specific origin are not encoded as a pair.
- All snapshot fields may change on the next rebuild, and pivot slots may change in the same rebuild that emits a break. A family may safely copy individual valid values, but cannot claim common event ownership.

`StructuralReplay.mqh` reproduces the same state and projection algorithm but also exposes no immutable break record.

## Frozen record design

Add to the shared core type layer:

```cpp
struct MSZZStructuralEventRecord
{
   bool valid;
   string event_id;
   ENUM_MSZZ_SPEED speed;
   ENUM_MSZZ_DIRECTION direction;
   datetime event_time;
   string source_origin_pivot_id;
   double source_origin_price;
   datetime source_origin_confirmation_time;
   string broken_pivot_id;
   double broken_level_price;
   datetime broken_pivot_confirmation_time;
   double break_close_price;
   double break_distance;
   double break_distance_atr;
   double impulse_origin_price;
   double impulse_extreme_price;
   double impulse_distance;
   double impulse_distance_atr;
   double atr_at_event;
};
```

Creation point: inside `BuildSpeed()`, immediately after a break condition becomes true and before returning the snapshot. It must receive explicit copies of the exact pivots and projection used in that comparison. The direction-specific origin pivot must be selected by a documented adjacency rule; if adjacency cannot be proven, `valid=false` and no event is exposed.

Lifetime: immutable value stored in the snapshot for the represented bar only; consumers copy it at arm time. Historical replay produces byte-equivalent records. Later rebuilds replace the snapshot record but cannot mutate prior copies.

Validation requires nonempty unique event and pivot IDs, valid speed/direction/time, finite positive ATR/prices, directionally valid close/level/distance, and exact recomputation of price and ATR-normalized distances. Missing origin adjacency fails closed.

## Required infrastructure tests

Test bullish/bearish creation; projection equality; pivot IDs and confirmation times; same-rebuild pivot update; missing adjacency; ATR/distance recomputation; deterministic replay; snapshot replacement without copy mutation; fast/medium/slow separation; and parity between engine rebuild and structural replay.
