# Multi-Speed ZigZag Suite — Agent Handoff

## Mission

Build a standalone MQL5 Expert Advisor around the existing three-speed ATR ZigZag and trendline-breakout concept, while keeping the core reusable through a future Quant Beast adapter.

This is not one entry rule. It is a strategy suite sharing one structural engine.

## Current status

- Working branch created: `feature/mszz-standalone-suite`
- Existing Pine and MQL5 reference files identified.
- No production EA code has been added yet.
- The immediate task is a full source audit and behavioral specification.

## Important architectural direction

Use one shared implementation for:

- ATR-driven fast, medium, and slow ZigZag states
- confirmed and candidate pivots
- HH/HL/LH/LL classification
- pivot shelves
- projected support and resistance trendlines
- breakout events
- stable event IDs
- opportunity clustering and duplicate suppression

Expose that shared implementation through two possible front ends:

1. `MultiSpeedZigZagEA.mq5` — standalone execution and research EA.
2. A future Quant Beast adapter — signal provider only, with Quant Beast retaining global risk and execution authority.

Do not fork the signal logic between the two front ends.

## First implementation milestone

1. Audit all files in `Indicators/Tradingview_Indicators/MULTI_SPEED_ZIGZAG/`.
2. Record exact differences between Pine strategy, Pine indicator, and MQL5 indicator.
3. Define pivot confirmation timing and prove there is no unavailable future information in live decisions.
4. Create deterministic engine types and tests before broker execution.
5. Build shadow-mode signal journaling.
6. Validate bar-for-bar parity against the chosen behavioral reference.

## Candidate initial strategies

Each must have a separate immutable strategy ID and separate performance statistics:

- Fast breakout
- Medium breakout
- Slow breakout
- Fast + medium confluence with slow alignment
- Fast breakout with medium context
- Medium breakout with slow context
- Sequential fast-to-medium confirmation
- Nested pullback continuation
- Breakout retest
- Sweep and reclaim
- Compression to expansion
- Structure-state transition
- Weighted three-speed ensemble

Do not enable all strategies simultaneously before event clustering is complete.

## Non-negotiable safety requirements

- Candidate pivots and confirmed pivots must be distinct states.
- Original pivot bar and confirmation bar must both be recorded.
- A confirmed pivot cannot move later.
- Historical signals cannot disappear after confirmation.
- Each structural break receives a stable event ID.
- One event cannot create duplicate independent entries merely because several strategy descriptions recognize it.
- Backtests must not read bars that did not exist at the simulated decision time.
- Live, tester, and restart behavior must produce equivalent structural state from the same closed-bar history.

## Agent workflow

At the start of a work session:

1. Read this file.
2. Read `DECISION_LOG.md` from the end backward.
3. Inspect the latest branch commits.
4. Check `TEST_PLAN.md` for the next unproven requirement.
5. Do not assume a prior agent's claim is true without code or test evidence.

Before ending a work session:

1. Update this handoff with completed work and the exact next task.
2. Add any architectural decision to `DECISION_LOG.md`.
3. Add or update tests for changed behavior.
4. Record known defects and unresolved questions.
5. Leave the branch compiling or clearly document why it does not.

## Coordination with Quant Beast work

Claude is actively working on Quant Beast on `main`. Avoid modifying Quant Beast files during the standalone research phase. New MSZZ work should remain under dedicated `Include`, `Experts`, `Tests`, and `Docs` paths. Rebase or merge `main` only when necessary, and inspect conflicts rather than accepting either side blindly.

## Immediate next task

Perform the source parity and repaint audit. Produce a table covering:

- feature
- Pine strategy behavior
- Pine indicator behavior
- MQL5 indicator behavior
- parity status
- execution risk
- chosen canonical behavior

Then update this handoff.