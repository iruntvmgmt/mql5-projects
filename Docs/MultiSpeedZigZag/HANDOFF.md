# Multi-Speed ZigZag Suite — Agent Handoff

## Mission

Build a standalone MQL5 Expert Advisor around the existing three-speed ATR ZigZag and trendline-breakout concept, while keeping the core reusable through a future Quant Beast adapter.

This is a strategy suite sharing one structural engine, not one entry rule.

## Branch

`feature/mszz-standalone-suite`

Claude is actively working on Quant Beast on `main`. This branch intentionally avoids Quant Beast implementation paths.

## Implemented

### Structural core

- `Include/MultiSpeedZigZag/Core/Types.mqh`
- `Include/MultiSpeedZigZag/Core/TripleZigZagEngine.mqh`

The engine rebuilds three ATR-reversal ZigZags from closed-bar history. It records candidate extremes internally, immutable confirmed pivots, original pivot time, confirmation time, HH/HL/LH/LL classification, projected lines, close-confirmed breakouts, and stable identities.

### Strategy suite

- `Include/MultiSpeedZigZag/Strategies/StrategySuite.mqh`

Implemented and independently configurable:

- Fast breakout
- Medium breakout
- Slow breakout
- Fast + medium confluence with slow alignment
- Fast breakout with medium context
- Medium breakout with slow context
- Nested pullback continuation
- Weighted three-speed ensemble

Reserved:

- Sequential confirmation
- Breakout retest
- Sweep and reclaim
- Compression breakout
- Structure transition

Invalid candidates without usable event, entry, or stop data are now rejected before entering the candidate array. Selection no longer depends on `DBL_MAX`.

### Persistent event store

- `Include/MultiSpeedZigZag/Execution/EventStore.mqh`

Consumed structural event IDs are stored in a symbol/timeframe/magic-scoped file and reloaded on initialization. The store is bounded and rewritten after additions. This closes the original in-memory-only duplicate risk, subject to compile and runtime verification.

### Execution guard

- `Include/MultiSpeedZigZag/Execution/ExecutionGuard.mqh`

Added:

- symbol execution-property loading
- volume min/max/step normalization
- terminal, EA, and symbol trade-permission checks
- spread gate
- stop/freeze-distance validation
- stop and target orientation validation

### Standalone EA

- `Experts/MultiSpeedZigZagEA.mq5`, version `0.20`

Current features:

- closed-bar processing only
- three independent execution authorization gates
- per-strategy enable inputs
- persistent event deduplication
- raw candidate and selected-decision journal
- spread rejection
- normalized volume
- broker stop/freeze validation
- live market entry substituted before target recalculation
- opposite-position close verification
- one-position-per-symbol option

The three live gates are:

1. `InpShadowOnly=false`
2. `InpAllowLiveExecution=true`
3. `InpAcknowledgeRisk=true`

This EA remains not production-authorized.

### Test

- `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`

The test rebuilds identical history through two independent engines and compares structural identities and state. It has not been run.

## Canonical behavior

- Wick highs/lows maintain leg extremes.
- ATR reversal distance confirms pivots.
- Closed prices break projected support/resistance.
- Only closed bars are processed.
- Last two confirmed same-kind pivots define each projected line.
- Pivot decisions use `confirmed_time`, never claim the pivot was known at `pivot_time`.
- Identical closed history must reproduce identical IDs.

## Known limitations and risks

1. MetaEditor compile remains unverified.
2. The deterministic test has not been executed.
3. Full-history rebuild performance has not been measured.
4. Event-store behavior has not been runtime-tested, including missing-file and concurrent-terminal cases.
5. Position ownership reconstruction is still absent.
6. No account-risk sizing, daily-loss gate, trade-count gate, margin preflight, or emergency kill switch exists.
7. Fixed strategy scores are placeholders rather than edge estimates.
8. Advanced Pine features remain unported: source modes, quality scoring, volume, momentum, Renko bodies, volatility-slope lines, and historical projection variants.
9. Formal opportunity aggregation remains incomplete; current logic selects the best candidate.
10. Bar-for-bar Pine parity has not been run.

## Required next actions

1. Compile the EA, headers, and tests in MetaEditor; fix every error and review every warning.
2. Run deterministic and event-store tests and save terminal evidence.
3. Add synthetic structural fixtures instead of relying only on market history.
4. Add a replay/export harness for Pine-versus-MQL5 pivots, line values, and breakout timestamps.
5. Implement position and order ownership reconstruction after restart.
6. Add account-risk sizing, margin preflight, daily limits, and emergency controls.
7. Implement reserved strategies one at a time with explicit state machines and tests.
8. Replace best-candidate-only handling with first-class opportunity clusters.
9. Collect shadow evidence before demo execution.

## Agent start procedure

1. Read this file.
2. Read `DECISION_LOG.md` from the end backward.
3. Read `TEST_PLAN.md`, `NON_REPAINTING_CONTRACT.md`, and `KNOWN_ISSUES.md`.
4. Inspect the latest branch commits and draft PR.
5. Do not call the branch production-ready without compile, parity, restart, safety, and evidence gates.

## Agent end procedure

1. Update this handoff with exact changes and next task.
2. Append decisions rather than rewriting history.
3. Update tests with behavior changes.
4. Record compile/test evidence and unresolved defects.
5. Keep Quant Beast integration deferred until standalone structural parity is certified.