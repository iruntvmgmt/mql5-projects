# Alert category routing evidence — 2026-07-16

## Defect

`InpAlertOrderFilled` and `InpAlertReconFailure` were declared but had no runtime references.

Severity: Medium operational-visibility defect. The issue did not affect signal generation, risk validation, execution, or broker safety, but operators could not receive configured fill/reconciliation alerts.

## Fix

- Routed Shadow order-filled events through `InpAlertOrderFilled`.
- Routed live broker filled/protected order events through `InpAlertOrderFilled`.
- Routed pending-entry transaction fills through `InpAlertOrderFilled` when they were not already locally owned.
- Routed protection/reconciliation failures through `InpAlertReconFailure`.
- Routed close-reconciliation queue failures and missing local close context through `InpAlertReconFailure`.
- Added deterministic self-test coverage: `TEST 46 PASS: Fill/reconciliation alert categories`.

## Validation

- Compile: MetaEditor build 6002, `0 errors, 0 warnings`, 2026-07-16 11:01:07.
- Regression config: `QuantBeast.AlertCategoryRouting.XAUUSD.M5.20260518_20260522.ini`.
- Regression result: `Self-tests complete: 48 passed, 0 failed`.
- Tester footer: final balance `10000.00 USD`, `OnTester result 0`, and `Test passed`.
- No broker orders were transmitted.

## Hashes

- Source SHA-256: `65a007c3cd091314c7000403c635f0f5fce4a11c5c88d419de86cac4f4635935`
- EX5 SHA-256: `bce28bc0c5c019988f2a14f28fd3dd6e9459bf3e6b5743c1ea38a91bcaab69fe`

## Evidence files

- `hashes_pre_test.txt`
- `hashes_post_test.txt`
- `regression_summary.txt`
- `agent_log_suffix.txt`
- `QuantBeast.AlertCategoryRouting.XAUUSD.M5.20260518_20260522.ini`
