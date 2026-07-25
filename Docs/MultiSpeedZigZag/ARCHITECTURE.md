# Multi-Speed ZigZag Suite Architecture

## Design goals

- Standalone-first research and execution.
- Shared core suitable for a future Quant Beast adapter.
- Deterministic closed-bar behavior.
- Strategy isolation with shared structural data.
- Explicit event clustering to prevent duplicate trades.
- Full restart reconstruction from price history and persisted execution state.

## Planned layout

```text
Include/MultiSpeedZigZag/
├── Core/
│   ├── Types.mqh
│   ├── ATRSeries.mqh
│   ├── ZigZagSpeedEngine.mqh
│   ├── TripleZigZagEngine.mqh
│   ├── PivotStore.mqh
│   ├── StructureClassifier.mqh
│   ├── TrendlineEngine.mqh
│   └── EventIdentity.mqh
├── Strategies/
│   ├── IStrategy.mqh
│   ├── FastBreakout.mqh
│   ├── MediumBreakout.mqh
│   ├── SlowBreakout.mqh
│   ├── FastMediumConfluence.mqh
│   ├── NestedPullback.mqh
│   ├── SequentialConfirmation.mqh
│   ├── BreakoutRetest.mqh
│   ├── SweepReclaim.mqh
│   ├── CompressionBreakout.mqh
│   ├── StructureTransition.mqh
│   └── WeightedEnsemble.mqh
├── Arbitration/
│   ├── OpportunityCluster.mqh
│   └── SuiteArbitrator.mqh
├── Execution/
│   ├── StandaloneRiskEngine.mqh
│   ├── OrderRouter.mqh
│   └── PositionManager.mqh
├── Diagnostics/
│   ├── SignalJournal.mqh
│   ├── StateSnapshot.mqh
│   └── ParityJournal.mqh
└── Adapters/
    ├── StandaloneAdapter.mqh
    └── QuantBeastAdapter.mqh

Experts/
└── MultiSpeedZigZagEA.mq5

Tests/MultiSpeedZigZag/
└── deterministic and replay tests
```

## Layer boundaries

### Structural engine

Owns only market-derived state. It must not know about account balance, lot size, open positions, or broker order APIs.

### Strategy layer

Consumes immutable structural snapshots and emits hypotheses. A strategy may not directly place or modify orders.

### Opportunity clustering

Groups strategy candidates that describe the same underlying structural event. It determines whether they are independent opportunities, supporting evidence, conflicting interpretations, or duplicates.

### Suite arbitration

Ranks opportunity clusters and chooses the suite-level action. It must preserve all rejected candidates and rejection reasons in diagnostics.

### Execution layer

Used only by the standalone EA. It handles risk, order submission, ownership, stop/target management, daily controls, and restart recovery.

### Quant Beast adapter

Future component. It emits normalized candidates and disables local execution. Quant Beast remains authoritative for global risk, exposure, allocation, and routing.

## Core data flow

```text
closed price bar
    ↓
ATR series
    ↓
fast / medium / slow ZigZag engines
    ↓
confirmed pivot and trendline snapshots
    ↓
structure classifier
    ↓
strategy evaluators
    ↓
raw candidates
    ↓
opportunity clustering
    ↓
suite arbitration
    ↓
standalone execution OR Quant Beast candidate adapter
    ↓
journal and state evidence
```

## Engine invariants

- Structural state advances in a defined order once per closed bar.
- A speed engine cannot revise a confirmed pivot.
- Candidate state may move until reversal confirmation.
- Trendline identity is derived from immutable pivot identities.
- Breakout identity is derived from trendline identity, direction, and confirmation bar.
- Reprocessing identical history must reproduce identical IDs and state.

## Strategy isolation

Each strategy has:

- immutable ID
- version
- hypothesis statement
- required structural inputs
- trigger
- invalidation
- signal expiry
- deduplication relationship
- independent metrics

Strategies may share the engine but must not share hidden mutable signal state.

## Open design questions

- Whether the Pine strategy or the desired discretionary behavior becomes the final canonical reference.
- Exact reversal source: wicks, closes, or selectable mode.
- Exact breakout source and wick-failure handling.
- Whether projected lines use last-two-pivot geometry, volatility slope, or both as separate models.
- Whether standalone execution should initially support one position total or one position per opportunity cluster.

Resolve these through explicit decisions and tests, not silent implementation choices.