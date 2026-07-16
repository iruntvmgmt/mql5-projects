# Strategy counter persistence evidence — 2026-07-16

## Defect

Per-strategy daily trade counters were runtime-only, so terminal restart could reset strategy daily limits while daily/weekly risk locks persisted.

Severity: Medium risk/restart defect. It could permit additional same-day strategy entries after restart in live modes, although no broker exposure was created during this repair.

## Fix

- Added scoped global-variable keys for strategy trade day and BO/FBO/TP/MR daily counts.
- Persisted counters as part of runtime state checkpoints.
- Restored counters only when the saved trade day matches the current broker day.
- Reset and persisted counters on broker-day rollover.
- Persisted immediately after `MarkStrategyTrade()` increments a strategy count.
- Did not change state schema version; missing counter keys are treated as empty legacy state.

## Validation

- Compile: `0 errors, 0 warnings`, 2026-07-16 11:30:53.
- Regression: `Self-tests complete: 49 passed, 0 failed`.
- Required marker: `TEST 47 PASS: Strategy counter restore policy`.
- Tester footer: final balance `10000.00 USD`, `OnTester result 0`, and `Test passed`.
- No broker orders were transmitted.

## Hashes

- Source SHA-256: `3723de29e9b0caf6dd4ef2201866476c1d77a32f6761f85c5c64e59d5f50ecee`
- StateStore SHA-256: `1c43138f0e685c1f52e2f5509768f6873903ea7b81211e39302b32dd830a67eb`
- EX5 SHA-256: `e1f34f0bb49bf2b506da3f37f405377bf9903c3c87d084f06cf7756c379b4499`
