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

Core types now include:

- structural origin types
- cluster lifecycle states
- evidence-family masks
- expanded candidate origin metadata
- first-class cluster fields

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

Reserved in code and fully specified as state machines:

- Sequential confirmation
- Breakout retest
- Sweep and reclaim
- Compression breakout
- Structure transition

### Opportunity clustering implementation

- `Include/MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh`
- `Tests/MultiSpeedZigZag/Test_MSZZ_Clusters.mq5`

The cluster engine now:

- groups candidates by structural origin and direction
- creates stable cluster IDs
- merges evidence masks
- tracks supporting strategies
- measures stop disagreement
- applies capped support bonuses
- assigns a canonical owner using strategy specificity priority
- selects the strongest cluster

The cluster test defines three related fast-origin candidates plus one independent medium-origin candidate. Expected output is two clusters with nested pullback owning the related cluster.

The standalone EA is not yet wired to execute clusters; it still selects raw candidates. Cluster integration should occur only after compile and test verification.

### Persistent event store

- `Include/MultiSpeedZigZag/Execution/EventStore.mqh`

Consumed structural event IDs are stored in a symbol/timeframe/magic-scoped file and reloaded on initialization. Runtime verification remains pending.

### Execution guard

- `Include/MultiSpeedZigZag/Execution/ExecutionGuard.mqh`

Added symbol execution-property loading, volume normalization, permission checks, spread gate, stop/freeze-distance validation, and stop/target orientation validation.

### Standalone EA

- `Experts/MultiSpeedZigZagEA.mq5`, version `0.20`

Features include closed-bar processing, three execution authorization gates, per-strategy toggles, persistent deduplication, journaling, spread rejection, normalized volume, broker stop validation, market-entry target recalculation, opposite-position close verification, and one-position-per-symbol control.

The EA remains not production-authorized.

### Deterministic specifications and tests

- `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`
- `Tests/MultiSpeedZigZag/Test_MSZZ_Clusters.mq5`
- `Docs/MultiSpeedZigZag/SYNTHETIC_FIXTURES.md`

Twelve canonical structural fixtures define candidate replacement, confirmation timing, tie rules, minimum spacing, structure labels, close-only breakouts, forming-bar exclusion, history extension, and gap behavior.

### Parity exporter

- `Include/MultiSpeedZigZag/Diagnostics/ParityExporter.mqh`
- `Tests/MultiSpeedZigZag/Export_MSZZ_Parity.mq5`

The exporter writes:

- manifest
- bars
- pivots
- per-bar speed snapshots
- candidates
- clusters

The export script rebuilds the engine at every historical closed-bar prefix, emits structural state, runs the strategy suite, forms clusters, and writes machine-comparable CSV files.

Important caveat: the exporter currently records the engine's elapsed-seconds geometry. Pine comparison may prove bar-index geometry is required.

### Behavioral documentation

- `STATE_MACHINES.md`
- `OPPORTUNITY_CLUSTERING.md`
- `PARITY_EXPORT_SCHEMA.md`
- `RESEARCH_JOURNAL_SCHEMA.md`
- `NON_REPAINTING_CONTRACT.md`
- `STRATEGY_CATALOG.md`
- `TEST_PLAN.md`
- `PARITY_AUDIT.md`
- `KNOWN_ISSUES.md`

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
2. Determinism, cluster, persistence, and parity scripts have not been executed.
3. Candidate origin metadata is now available, but existing strategy emitters still need to populate it consistently.
4. The standalone EA still executes raw selected candidates rather than selected clusters.
5. Full-history rebuild performance has not been measured.
6. Event-store behavior has not been runtime-tested.
7. Position ownership reconstruction is absent.
8. No account-risk sizing, daily limits, trade-count gate, margin preflight, or kill switch exists.
9. Fixed strategy scores are placeholders rather than edge estimates.
10. Advanced Pine features remain unported.
11. Bar-for-bar Pine parity has not been run.
12. Time-based versus bar-index trendline geometry remains unresolved.
13. Pivot export may emit repeated rows when rebuilding each history prefix; comparison tooling must deduplicate by semantic pivot identity or the exporter must maintain an emitted-ID set.

## Required next actions

1. Compile all EA, headers, and test scripts in MetaEditor; fix every error and warning.
2. Update strategy emitters to populate `origin_type`, `origin_id`, and `evidence_mask` consistently.
3. Run cluster tests and verify owner priority, grouping, and stop-disagreement behavior.
4. Add emitted-ID deduplication to parity exports.
5. Run parity export on a fixed XAUUSD interval and produce the corresponding Pine export.
6. Resolve bar-index versus elapsed-time line geometry through evidence.
7. Wire the standalone EA to select and persist clusters instead of raw candidates.
8. Convert remaining synthetic fixtures into executable tests.
9. Implement position and order ownership reconstruction.
10. Add account-risk sizing, margin preflight, daily limits, and emergency controls.
11. Implement reserved strategies one at a time.
12. Collect shadow evidence before demo execution.

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