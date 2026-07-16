# Live Strategy Gate Evidence - 2026-07-16

## Purpose

Prevent accidental live-mode transmission from strategies that do not yet have organic accepted-entry evidence.

## Defect

The conservative live preset could inherit the default strategy configuration where BO, FBO, TP, and MR are all enabled. Current true-tick evidence only proves accepted BUY/SELL trade state for FBO; BO, TP, and MR have rejection-path coverage but no organic accepted entries in the completed baseline windows.

Severity: High live-safety/configuration risk.

Affected paths:

- `QuantBeastEA.mq5` live initialization
- `XAUUSD_Conservative_Live.set`

Safety consequence:

- A future operator could load Conservative Live and allow unproven BO/TP/MR live transmissions before their accepted-entry and lifecycle evidence exists.

## Fix

- Added a production live-mode strategy gate: Conservative Live and acknowledged Challenge Live initialize only when the enabled strategy set is exactly FBO-only.
- Updated `XAUUSD_Conservative_Live.set` to be explicitly not approved, FBO-only, market-order-only, lower risk, tighter exposure, persistence-enabled, and unknown-position quarantine.
- Added deterministic self-test coverage: `TEST 37 PASS: Live strategy gate FBO-only`.

Shadow and Diagnostic modes remain unchanged for research.

## Compile evidence

`compile_result.txt`

- MetaEditor build 6002
- Result: `0 errors, 0 warnings`
- Compile duration: `11690 ms`
- Source SHA-256: `528534276ce0efa35d259cd0e41a733f37e3d21a13a162a6639a0f7032b3d7ee`
- EX5 SHA-256: `889fadaea02d89a35abea203e14a474712d8fad6e612a5e2b41f4a3581203129`
- Conservative preset SHA-256: `656351a33a8866bd07de83cff2c5e27446fa6f9e4cb529a9d03d54f6d9a75bb8`

## Regression evidence

Config:

- `QuantBeast.LiveStrategyGate.XAUUSD.M5.20260518_20260522.ini`

Run:

- Mode: Shadow (`InpMode=1`)
- Challenge acknowledgement: false
- Model: generated ticks (`Model=1`)
- Symbol/period: XAUUSD M5
- Date range: `2026.05.18` to `2026.05.22`
- Deposit/leverage: 10000 USD / 500
- Self-tests: enabled
- Journals: disabled for narrow startup regression

Result:

- `TEST 37 PASS: Live strategy gate FBO-only`
- `Self-tests complete: 38 passed, 0 failed`
- Final balance: `10000.00 USD`
- `OnTester result 0`
- `22080 ticks, 1104 bars generated`
- `Test passed in 0:00:18.484`

Files:

- `agent_log_suffix.txt`
- `tester_log_suffix.txt`
- `regression_summary.txt`

## Boundaries

- This does not authorize broker orders.
- This does not prove live execution or restart recovery.
- BO, TP, and MR remain research-only for live transmission until accepted-entry and lifecycle evidence exists.
- Readiness remains `READY FOR SHADOW MODE`.
