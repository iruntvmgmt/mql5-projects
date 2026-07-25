# Test Plan and Release Gates

## Gate 1 — Compile

- `Experts/MultiSpeedZigZagEA.mq5` compiles with zero errors.
- Core headers compile through both the EA and test script.
- Warnings are reviewed; none may hide truncation, uninitialized state, or enum conversion defects.

## Gate 2 — Determinism

- Run `Tests/MultiSpeedZigZag/Test_MSZZ_Determinism.mq5`.
- Two independent rebuilds over identical closed-bar history must produce identical pivot IDs, labels, directions, and breakout IDs.

## Gate 3 — Closed-bar integrity

- Confirm the forming bar is excluded.
- Compare tick-by-tick tester output against open-prices-only output for closed-bar signal timestamps.
- No signal may move earlier when more future data becomes available.

## Gate 4 — Pine/MQL5 parity

For a fixed symbol, timeframe, history window, and parameter set, export:

- confirmed pivots and confirmation bars
- structure labels
- projected line values
- breakout timestamps
- strategy candidates

Classify mismatches as intentional specification differences or defects.

## Gate 5 — Duplicate suppression

- One structural event may produce many raw candidates.
- At most one selected action may be emitted per event ID.
- Restart reconstruction must not retrade an already executed event once persistence is added.

## Gate 6 — Shadow evidence

Run shadow mode before any broker execution. Journal raw candidates, selection, rejected candidates, stop, target, spread, and strategy ID.

## Gate 7 — Execution safety

Before enabling execution:

- symbol volume limits normalized
- stop-level and freeze-level validation
- spread guard
- daily loss and trade-count controls
- persistent consumed-event store
- restart-safe ownership reconstruction
- explicit demo authorization

## Current gate status

- Gate 1: UNVERIFIED — MetaEditor compiler is not available through the current GitHub connector session.
- Gate 2: TEST IMPLEMENTED, NOT RUN.
- Gates 3–7: NOT YET CERTIFIED.

The branch is an implementation milestone, not production authorization.