# Known Issues and Production Blockers

## Build verification

- MetaEditor compile has not been run in the current tool environment.
- The deterministic script exists but has not been executed.

## Structural engine

- Full-history rebuild is O(bars × speeds × ATR length) each new bar.
- No incremental/rebuild parity harness exists yet.
- Only last-two-confirmed-pivot trendlines are implemented.
- Reversal source is wick-based and breakout source is close-based; other source modes are deferred.

## Strategy suite

- Scores are research ranking placeholders.
- Sequential confirmation, retest, sweep/reclaim, compression, and structure-transition strategies are reserved only.
- Formal opportunity clusters are not yet persisted as first-class objects.

## Execution

- Fixed lots only.
- No symbol volume-step normalization.
- No broker stop/freeze-level validation.
- No spread or slippage gate.
- No account-risk sizing.
- No daily drawdown, trade count, or emergency kill switch.
- Consumed-event memory is lost on restart.
- Position ownership reconstruction is not implemented.

## Research

- No bar-for-bar Pine parity export has been completed.
- No backtest result supports an edge claim.
- No live or demo authorization should be inferred from the presence of an execution path.