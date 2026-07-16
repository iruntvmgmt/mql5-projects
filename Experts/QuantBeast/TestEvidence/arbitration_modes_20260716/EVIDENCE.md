# Arbitration-mode coverage evidence — 2026-07-16

## Defect

The arbitration enum cases existed in source, but deterministic coverage only proved highest-score, duplicate, reject-conflicts, and exposure behavior. Regime-priority and require-confluence modes lacked direct regression evidence.

Severity: Medium test-coverage/configuration defect. The source path existed, but unsupported evidence for exposed arbitration modes could hide future regressions.

## Fix

- Expanded `QBTestArbitrationPolicy()` to cover `ARBITRATION_REGIME_PRIORITY`.
- Expanded `QBTestArbitrationPolicy()` to cover `ARBITRATION_REQUIRE_CONFLUENCE` selected and rejected paths.
- Existing `TEST 34 PASS` now requires regime-priority selection, confluence selection, and no-confluence rejection.

## Validation

- Compile: `0 errors, 0 warnings`, 2026-07-16 11:23:58.
- Regression: `Self-tests complete: 48 passed, 0 failed`.
- Required markers: `regime=selected`, `confluence=selected`, `noConfluence=rejected`.
- Tester footer: final balance `10000.00 USD`, `OnTester result 0`, and `Test passed`.
- No broker orders were transmitted.

## Hashes

- Source SHA-256: `65a007c3cd091314c7000403c635f0f5fce4a11c5c88d419de86cac4f4635935`
- SafetyTests SHA-256: `e4fad7fcd448cb2b2d199fbbc5bc6b392a69025a6cdd4d5e1efd174d74fc1dfa`
- EX5 SHA-256: `3ecc2d1274891dc02db319ffa2373e1b804ef0fa4ec827dbcaeae3a4c5bafed1`
