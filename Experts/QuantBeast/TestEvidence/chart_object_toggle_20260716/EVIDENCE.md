# Chart object toggle evidence — 2026-07-16

## Defect

`InpShowChartObjects` was exposed as a dashboard/UI input but had no runtime effect outside configuration.

Severity: Low UI/operational defect. It did not affect signal generation, risk, execution, or broker safety, but it made a user-facing control misleading.

## Fix

- Added bounded accepted-signal chart level rendering to `CDashboard`.
- Added `QBChartObjectsShouldRender()` to keep the policy explicit and testable.
- `InpShowChartObjects=true` allows drawing entry, stop, and target horizontal levels for accepted signals on normal charts.
- Strategy Tester suppresses chart-level rendering to avoid GUI object noise in deterministic runs.
- Level objects rotate through 10 slots, bounding retained objects to 30 accepted-signal lines.
- Dashboard cleanup now also removes QuantBeast level objects.

## Validation

- Compile: MetaEditor build 6002, `0 errors, 0 warnings`, 2026-07-16 10:56:38.
- Regression config: `QuantBeast.ChartObjectToggle.XAUUSD.M5.20260518_20260522.ini`.
- Regression result: `Self-tests complete: 47 passed, 0 failed`.
- Deterministic marker: `TEST 45 PASS: Chart object toggle policy`.
- Tester footer: final balance `10000.00 USD`, `OnTester result 0`, and `Test passed`.
- No broker orders were transmitted.

## Hashes

- Source SHA-256: `a985147dbfd36f6dead2f7f467888edb2d3106d8f4e2b5fc83720e049e305b24`
- Dashboard SHA-256: `9aad1d1995f4df0999fb18d2f5c7edddfe29c7d240fae755425fa3ef03e6174f`
- EX5 SHA-256: `82ff8e1335d7a2bef94b004c0211f6e5dfdda05ef2d404524d93f2e48434fbb4`

## Evidence files

- `hashes_pre_test.txt`
- `hashes_post_test.txt`
- `regression_summary.txt`
- `agent_log_suffix.txt`
- `QuantBeast.ChartObjectToggle.XAUUSD.M5.20260518_20260522.ini`
