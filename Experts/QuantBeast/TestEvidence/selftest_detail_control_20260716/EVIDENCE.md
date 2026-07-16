# Self-test detail-control evidence — 2026-07-16

## Defect

`InpLogSelfTestDetails` was documented as a testing/logging input but self-test PASS detail rows were emitted unconditionally.

Severity: Low operational/documentation defect. It did not affect trading safety, but it made an exposed input misleading and could unnecessarily expand terminal/tester logs.

## Fix

- Added `DiagSetSelfTestDetails()`.
- Added `QBIsSelfTestPassDetail()` and `QBShouldLogSelfTestMessage()`.
- `QBLog()` now suppresses only self-test PASS detail rows when self-test detail logging is disabled.
- Self-test FAIL rows and the final `Self-tests complete` summary remain visible.
- Added deterministic `TEST 44 PASS: Self-test detail logging policy`.

## Validation

- Compile: MetaEditor build 6002, `0 errors, 0 warnings`, 2026-07-16 10:47:44.
- Regression config: `QuantBeast.SelfTestDetail.XAUUSD.M5.20260518_20260522.ini`.
- Regression result: `Self-tests complete: 46 passed, 0 failed`.
- Suppression config: `QuantBeast.SelfTestDetailOff.XAUUSD.M5.20260518_20260522.ini`.
- Suppression result: `InpLogSelfTestDetails=false` retained `Self-tests complete: 46 passed, 0 failed`, final balance, `OnTester result 0`, and tester `Test passed` footer; no `TEST ... PASS` detail rows were present in the new log suffix.
- Final tester balance remained `10000.00 USD`.
- No broker orders were transmitted.

## Hashes

- Source SHA-256: `26b69114f94465a6c901f62c353e24235bcb61bba905644e5e1a2b14a4a7154a`
- EX5 SHA-256: `884d316e0560508e21d05d005004e38804c7f230b88f078a16a9a2d5bda97ad8`

## Evidence files

- `hashes_pre_test.txt`
- `hashes_post_test.txt`
- `regression_summary.txt`
- `suppression_summary.txt`
- `agent_log_suffix.txt`
- `suppression_rerun_agent_log_suffix.txt`
- `QuantBeast.SelfTestDetail.XAUUSD.M5.20260518_20260522.ini`
- `QuantBeast.SelfTestDetailOff.XAUUSD.M5.20260518_20260522.ini`
