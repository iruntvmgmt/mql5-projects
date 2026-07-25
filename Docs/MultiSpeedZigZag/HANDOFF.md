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

Reserved in code, now fully specified as state machines:

- Sequential confirmation
- Breakout retest
- Sweep and reclaim
- Compression breakout
- Structure transition

Invalid candidates without usable event, entry, or stop data are rejected before entering the candidate array.

### Persistent event store

- `Include/MultiSpeedZigZag/Execution/EventStore.mqh`

Consumed structural event IDs are stored in a symbol/timeframe/magic-scoped file and reloaded on initialization. The store is bounded and rewritten after additions. Runtime verification remains pending.

### Execution guard

- `Include/MultiSpeedZigZag/Execution/ExecutionGuard.mqh`

Added symbol execution-property loading, volume normalization, terminal/EA/symbol permission checks, spread gate, stop/freeze-distance validation, and stop/target orientation validation.

### Standalone EA

- `Experts/MultiSpeedZigZagEA.mq5`, version `0.20`

Features include closed-bar processing, three execution authorization gates, per-strategy toggles, persistent deduplication, journaling, spread rejection, normalized volume, broker stop validation, market-entry target recalculation, opposite-position close verification, and one-position-per-symbol control.

The three live gates are:

1. `InpShadowOnly=false`
2. `InpAllowLiveExecution=true`
3. `InpAcknowledgeRisk=true`

The EA remains not production-authorized.

### Tests and deterministic specifications

- `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`
- `Docs/MultiSpeedZigZag/SYNTHETIC_FIXTURES.md`

Twelve canonical fixtures now define candidate replacement, pivot confirmation timing, equal-high/equal-low tie rules, minimum spacing, structure labels, close-only breakouts, forming-bar exclusion, history-extension stability, and data-gap behavior.

Important discovery: the current engine projects lines using elapsed seconds, while Pine commonly projects using bar indices. This can create parity failures across gaps or irregular sessions. The parity test must determine whether the engine should move to bar-index geometry.

### Reserved-strategy contracts

- `Docs/MultiSpeedZigZag/STATE_MACHINES.md`

The five reserved strategies now have explicit states, transitions, invalidations, expirations, deduplication rules, and persistence requirements.

### Opportunity clustering contract

- `Docs/MultiSpeedZigZag/OPPORTUNITY_CLUSTERING.md`

Defined immutable cluster IDs, compatibility rules, parent-child structural origins, evidence families, cluster lifecycle, canonical owner selection, conflict arbitration, and staged-entry restrictions.

### Pine/MQL5 parity contract

- `Docs/MultiSpeedZigZag/PARITY_EXPORT_SCHEMA.md`

Defined run manifests and CSV schemas for bars, pivots, trendlines, line values, breakouts, candidates, and clusters, plus mismatch categories and acceptance tolerances.

### Research journal contract

- `Docs/MultiSpeedZigZag/RESEARCH_JOURNAL_SCHEMA.md`

Defined bar-state, raw-candidate, cluster, execution, fixed-horizon, excursion, barrier, and structural outcome records. Features must be frozen at decision time; future bars may only populate outcome fields.

## Canonical behavior

- Wick highs/lows maintain leg extremes.
- ATR reversal distance confirms pivots.
- Closed prices break projected support/resistance.
- Only closed bars are processed.
- Last two confirmed same-kind pivots define each projected line.
- Pivot decisions use `confirmed_time`, never claim the pivot was known at `pivot_time`.
- Identical closed history must reproduce identical IDs.
- Equal highs/lows currently use latest-equal-wins.

## Known limitations and risks

1. MetaEditor compile remains unverified.
2. The deterministic test has not been executed.
3. Full-history rebuild performance has not been measured.
4. Event-store behavior has not been runtime-tested.
5. Position ownership reconstruction is absent.
6. No account-risk sizing, daily limits, trade-count gate, margin preflight, or kill switch exists.
7. Fixed strategy scores are placeholders rather than edge estimates.
8. Advanced Pine features remain unported.
9. Current code still uses best-candidate selection rather than first-class cluster objects.
10. Bar-for-bar Pine parity has not been run.
11. Time-based versus bar-index trendline geometry is unresolved and potentially material.

## Required next actions

1. Compile the EA, headers, and tests in MetaEditor; fix every error and warning.
2. Convert the synthetic fixture specification into executable fixture tests.
3. Run deterministic and event-store tests and save evidence.
4. Implement the parity exporters and compare Pine against MQL5.
5. Resolve bar-index versus elapsed-time line geometry through parity evidence.
6. Add first-class cluster types and aggregation based on the clustering contract.
7. Implement position and order ownership reconstruction.
8. Add account-risk sizing, margin preflight, daily limits, and emergency controls.
9. Implement reserved strategies one at a time from `STATE_MACHINES.md`.
10. Collect shadow evidence before demo execution.

## Agent start procedure

1. Read this file.
2. Read `DECISION_LOG.md` from the end backward.
3. Read `TEST_PLAN.md`, `NON_REPAINTING_CONTRACT.md`, `SYNTHETIC_FIXTURES.md`, and `STATE_MACHINES.md`.
4. Inspect the latest branch commits and draft PR.
5. Do not call the branch production-ready without compile, parity, restart, safety, and evidence gates.

## Agent end procedure

1. Update this handoff with exact changes and next task.
2. Append decisions rather than rewriting history.
3. Update tests with behavior changes.
4. Record compile/test evidence and unresolved defects.
5. Keep Quant Beast integration deferred until standalone structural parity is certified.