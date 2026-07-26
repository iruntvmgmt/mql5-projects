# Multi-Speed ZigZag Suite — Agent Handoff

## Mission

Build a standalone MQL5 Expert Advisor around the existing three-speed ATR ZigZag and trendline-breakout concept, while keeping the core reusable through a future Quant Beast adapter.

## Branch

`feature/mszz-standalone-suite`

Quant Beast work on `main` remains isolated from this branch.

## Validated baseline through commit `31f13b0`

- Determinism test passed.
- Cluster test passed, including D004 cluster-ID tests.
- MQL5 parity export generated clean IDs.
- Shadow Strategy Tester runs placed zero orders/deals/trades.
- Event-store component persistence survived a process restart.
- EA compiled with zero errors and one reviewed Market-version warning.

## Current compile-pending batch — ownership foundation

### Decision

`DECISION_LOG.md` D005 defines account-mode-aware, magic-safe, ticket-specific ownership behavior.

### New files

- `Include/MultiSpeedZigZag/Execution/PositionOwnership.mqh`
- `Include/MultiSpeedZigZag/Execution/PositionOwnershipPolicy.mqh`
- `Tests/MultiSpeedZigZag/Test_MSZZ_Ownership.mq5`

### EA integration

`Experts/MultiSpeedZigZagEA.mq5` is now version `0.310` and replaces symbol-wide ownership logic with:

- explicit `ACCOUNT_MARGIN_MODE` detection;
- live position inventory by ticket;
- symbol and magic-number ownership classification;
- manual/foreign-position protection;
- ticket-specific closure of owned opposite positions only;
- fail-closed behavior on terminal selection ambiguity;
- netting/exchange rejection when foreign or manual symbol exposure exists;
- hedging coexistence with foreign/manual positions;
- one-position limit applied only to owned MSZZ positions;
- startup ownership snapshot and diagnostic logging.

The previous `PositionSelect(_Symbol)` and `CTrade::PositionClose(_Symbol)` execution behavior has been removed from the EA.

### Deterministic ownership test

`Test_MSZZ_Ownership.mq5` covers:

- matching magic classified as owned;
- zero magic classified as manual;
- other nonzero magic classified as foreign;
- hedging coexistence policy;
- netting/exchange foreign-exposure rejection;
- one-owned-position policy;
- unsupported/invalid/error snapshots failing closed;
- opposite-ticket selection excluding manual, foreign, same-direction, and unknown-direction records.

## Required local validation

Claude should pull the latest branch into the one true Wine MQL5 working tree using `git pull --ff-only`, then compile in this order:

1. `Tests/MultiSpeedZigZag/Test_MSZZ_Ownership.mq5`
2. `Experts/MultiSpeedZigZagEA.mq5`
3. Existing determinism, cluster, and parity scripts as regression checks

Required evidence:

- exact MetaEditor error/warning output;
- ownership test `failures=0`;
- existing tests remain passing;
- hedging demo shadow regression places zero orders;
- ownership logs correctly report the demo account as hedging;
- manual and foreign positions are never selected for closure;
- ticket-specific `CTrade::PositionClose(ticket)` compiles and behaves as expected.

Do not enable demo execution merely because this batch passes. It establishes ownership isolation but does not solve order-intent persistence, deal reconstruction, risk sizing, margin preflight, or account-level safeguards.

## Remaining production blockers

1. Post-order persistence failure and idempotent execution intent.
2. Full order/deal/cluster restart reconstruction.
3. Percentage-risk sizing and broker-correct risk calculations.
4. Margin preflight and exposure limits.
5. Daily loss, trade-count, cooldown, and kill-switch controls.
6. Five reserved stateful strategies.
7. Pine-side parity and trendline-geometry decision.
8. Long-duration forward shadow and demo evidence.

## Agent procedure

Read `DECISION_LOG.md`, `KNOWN_ISSUES.md`, `TEST_PLAN.md`, and this file before modifying the batch. Fix compile defects without weakening D005 invariants. Any behavioral change requires documentation and, where material, a new decision entry. Keep live execution gates closed and do not merge into `main`.