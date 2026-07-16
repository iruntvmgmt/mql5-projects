# QuantBeast live recovery gate evidence — 2026-07-16

## Defect

Live startup reconstruction could execute `UNKNOWN_FLATTEN` immediately when an unknown QuantBeast-range broker position was discovered. That behavior is broker-mutating during initialization and is unsafe without explicit operator authorization.

## Severity

High for live/restart safety. A passive startup path could transmit close orders before the operator has confirmed the current broker/account state.

## Fix

`QBLiveRecoveryPolicyAllowed()` now rejects `UNKNOWN_FLATTEN` for Conservative Live and acknowledged Challenge Live initialization. Non-transmitting policies remain allowed: `UNKNOWN_IGNORE`, `UNKNOWN_REPORT`, and `UNKNOWN_QUARANTINE`.

## Validation

- Compile: `0 errors, 0 warnings` at `2026-07-16 10:13:30`
- Shadow regression: `41 passed, 0 failed`
- Model: generated ticks, broker-free Shadow only
- Ticks/bars: `22080` ticks, `1104` bars
- Final balance: `10000.00 USD`
- Tester result: `OnTester result 0`

## Hashes

- Source SHA-256: `4611b0a29f54744a3ff4ee75eddb09d83c103d3954300930affc830c2ac487aa`
- EX5 SHA-256: `5a266f505530aa67a84a775c38a290d5cb4d24321ddccc1a552ad7de0886bafe`

## Files

- `QuantBeast.LiveRecoveryGate.XAUUSD.M5.20260518_20260522.ini`
- `agent_log_offset.txt`
- `agent_log_suffix.txt`
- `hashes_pre_test.txt`
- `hashes_post_test.txt`
- `regression_summary.txt`
- `sanitized_markers.txt`

No broker orders were transmitted.
