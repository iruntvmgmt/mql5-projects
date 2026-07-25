# Non-Repainting Contract

## Decision-time rule

The EA may evaluate signals only after a bar closes. The currently forming bar is excluded from the structural rebuild.

## Pivot lifecycle

1. A leg maintains a movable candidate extreme.
2. The candidate is not a pivot and cannot produce historical claims.
3. A reversal equal to or greater than the configured ATR threshold confirms the candidate extreme.
4. The pivot stores both `pivot_time` and `confirmed_time`.
5. After confirmation, price, time, type, label, and ID are immutable.

## Permitted delay

A pivot may be plotted historically at its original extreme bar after it is confirmed. Trading decisions must use its confirmation time, not pretend the pivot was known at the original bar.

## Forbidden behavior

- Reading future bars relative to the simulated decision time.
- Moving or deleting confirmed pivots.
- Emitting a signal at the pivot bar when confirmation occurred later.
- Reusing one structural break as multiple independent entries.
- Using the forming bar for close-confirmed breakout logic.

## Event identity

Pivot IDs include symbol, timeframe, speed, pivot type, pivot time, and confirmation time. Breakout IDs include the underlying pivot/trendline identity, direction, speed, and breakout confirmation bar.

Rebuilding identical closed-bar history must reproduce identical IDs.

## Current implementation status

`CMSZZTripleZigZagEngine` rebuilds from closed history on every new bar. This is computationally heavier than incremental state but intentionally deterministic for the first milestone. Incremental optimization is forbidden until replay parity against rebuild mode is proven.