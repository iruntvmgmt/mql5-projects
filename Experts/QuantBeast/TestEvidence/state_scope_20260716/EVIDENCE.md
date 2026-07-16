# State Scope Evidence - 2026-07-16

## Purpose

Ensure persisted Terminal Global Variable state is scoped to the effective QuantBeast trading symbol, not only the chart symbol.

## Defect

`StateStore.mqh` constructed persisted-state keys from account login and `_Symbol`. QuantBeast supports `InpPrimarySymbol`, so the effective trading symbol can differ from the chart symbol. In that case, persistence and recovery could read or write the wrong symbol namespace.

Severity: High recovery/isolation risk.

Affected paths:

- `Include/QuantBeast/Core/StateStore.mqh`
- `Experts/QuantBeast/QuantBeastEA.mq5` startup initialization

Safety consequence:

- Live restart could restore risk locks, kill state, broker-rejection streak, or Challenge state from the wrong symbol scope when `InpPrimarySymbol` differs from chart `_Symbol`.

## Fix

- Added explicit state-scope symbol storage in `StateStore.mqh`.
- `GV_ScopedName()` now uses the configured state scope symbol, falling back to `_Symbol` only before the EA sets a scope.
- `OnInit()` calls `SetStateScopeSymbol(g_Adapter.Symbol())` immediately after symbol adapter initialization.
- Added deterministic self-test coverage: `TEST 20b PASS: State scope policy symbol=scoped account=scoped override=effective`.

## Compile evidence

`compile_result.txt`

- Result: `0 errors, 0 warnings`
- Compile duration: `12581 ms`
- Source SHA-256: captured in `compile_result.txt`
- EX5 SHA-256: captured in `compile_result.txt`
- `StateStore.mqh` SHA-256: captured in `compile_result.txt`

## Regression evidence

Config:

- `QuantBeast.StateScope.XAUUSD.M5.20260518_20260522.ini`

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

- `TEST 20b PASS: State scope policy symbol=scoped account=scoped override=effective`
- `TEST 37 PASS: Live strategy gate FBO-only`
- `TEST 38 PASS: Live execution gate market-only`
- `Self-tests complete: 40 passed, 0 failed`
- Final balance: `10000.00 USD`
- `OnTester result 0`
- `22080 ticks, 1104 bars generated`
- `Test passed in 0:00:11.537`

Files:

- `agent_log_suffix.txt`
- `tester_log_suffix.txt`
- `regression_summary.txt`

## Boundaries

- This is broker-free Strategy Tester evidence.
- Normal-terminal restart with broker-visible positions remains unproven and requires explicit authorization if orders are needed.
- Readiness remains `READY FOR SHADOW MODE`.
