# Multi-Speed ZigZag Suite — Agent Handoff

## Mission

Build a standalone MQL5 Expert Advisor around the existing three-speed ATR ZigZag and trendline-breakout concept, while keeping the core reusable through a future Quant Beast adapter.

This is a strategy suite sharing one structural engine, not one entry rule.

## Branch

`feature/mszz-standalone-suite`

Claude is actively working on Quant Beast on `main`. This branch intentionally avoids Quant Beast implementation paths.

## Implemented in this milestone

### Shared structural core

- `Include/MultiSpeedZigZag/Core/Types.mqh`
- `Include/MultiSpeedZigZag/Core/TripleZigZagEngine.mqh`

The engine rebuilds three ATR-reversal ZigZags from closed-bar history using the default fast/medium/slow multipliers 1.0, 2.0, and 3.5. It records candidate extremes internally, immutable confirmed pivots, original pivot time, confirmation time, HH/HL/LH/LL classification, projected lines, close-confirmed breakouts, and stable IDs.

### Strategy suite

- `Include/MultiSpeedZigZag/Strategies/StrategySuite.mqh`

Implemented strategy IDs:

- Fast breakout
- Medium breakout
- Slow breakout
- Fast + medium confluence with slow alignment
- Fast breakout with medium context
- Medium breakout with slow context
- Nested pullback continuation
- Weighted three-speed ensemble

Reserved but not yet implemented:

- Sequential confirmation
- Breakout retest
- Sweep and reclaim
- Compression breakout
- Structure transition

The suite emits all raw candidates, scores them, and selects one best candidate for the current event. It does not place orders.

### Standalone EA

- `Experts/MultiSpeedZigZagEA.mq5`

Features:

- closed-bar processing only
- shadow-only default
- explicit second live-execution authorization flag
- raw candidate and selected-signal CSV journaling
- fixed-lot standalone execution path
- one-position-per-symbol option
- opposite-position close option
- in-memory event deduplication

This EA is not production-authorized. Execution safeguards remain incomplete.

### Test

- `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`

The test rebuilds identical history through two independent engines and compares structural identities and state.

### Documentation

- `README.md`
- `ARCHITECTURE.md`
- `DECISION_LOG.md`
- `NON_REPAINTING_CONTRACT.md`
- `STRATEGY_CATALOG.md`
- `TEST_PLAN.md`
- `PARITY_AUDIT.md`
- this handoff

## Canonical milestone-1 behavior

- Wick highs/lows maintain leg extremes.
- ATR reversal distance confirms pivots.
- Close breaks projected support/resistance.
- Only closed bars are processed.
- The last two confirmed same-kind pivots define each projected trendline.
- Pivot decisions use `confirmed_time`, never retrospectively claim knowledge at `pivot_time`.
- Identical closed history must produce identical IDs.

## Known limitations and risks

1. No MetaEditor compile was available in this connector session. Compile status is unverified.
2. The engine rebuilds full history each bar. This is deliberate for determinism but needs performance measurement.
3. Consumed event IDs are not persisted across terminal restarts.
4. Standalone execution lacks spread, stop-level, freeze-level, volume-step, daily-loss, and trade-count gates.
5. Fixed strategy scores are placeholders, not proven edge estimates.
6. Pine quality scoring, source selection, volume, momentum, Renko-body mode, volatility-slope lines, and historical projection variants are not yet ported.
7. Candidate overlap is reduced by best-candidate selection, but formal opportunity-cluster aggregation remains incomplete.
8. The source parity audit is structural and initial; bar-for-bar exported parity has not been run.

## Required next actions, in order

1. Compile the EA and test in MetaEditor; repair every error and review every warning.
2. Run deterministic test and record terminal output.
3. Add a replay/export harness comparing pivot and breakout timestamps against Pine on a fixed XAUUSD window.
4. Add persistent consumed-event storage and restart reconstruction.
5. Add broker-safe volume and stop normalization plus spread and account-risk gates.
6. Implement reserved strategies one at a time, each with deterministic fixtures.
7. Add real opportunity clustering so supporting strategies strengthen one opportunity rather than only competing by score.
8. Run shadow-mode evidence collection before any demo execution.

## Agent start procedure

1. Read this file.
2. Read `DECISION_LOG.md` from the end backward.
3. Read `TEST_PLAN.md` and `NON_REPAINTING_CONTRACT.md`.
4. Inspect latest branch commits.
5. Do not call this branch production-ready until every release gate has evidence.

## Agent end procedure

1. Update this handoff with exact changes and next task.
2. Append decisions rather than rewriting history.
3. Update tests with behavior changes.
4. Record compile/test evidence and unresolved defects.
5. Keep Quant Beast integration deferred until standalone structural parity is certified.