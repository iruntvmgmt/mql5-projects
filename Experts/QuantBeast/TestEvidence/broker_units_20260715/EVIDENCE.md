# Broker Unit Policy Evidence — 2026-07-15

## Confirmed defects

1. Executable prices were normalized only to display digits. On a broker symbol whose trade tick size is coarser than its point/display quantum, that can create an off-grid entry, stop, or target rejected by the broker.
2. `CTrade` used a hardcoded 50-point deviation while risk sizing and Shadow accounting charged the configured `InpSlippageAllowancePts`. Live execution could therefore accept materially more slippage than the risk model budgeted.

## Repair

- `CSymbolAdapter::NormalizePrice()` now aligns prices to `SYMBOL_TRADE_TICK_SIZE` and then normalizes display digits.
- `CBrokerAdapter::Init()` now receives `InpSlippageAllowancePts` and configures `CTrade` with its non-negative integer ceiling.
- Invalid/negative deviation values fail to zero.
- The same pure conversion helpers are exercised by deterministic startup tests.

## Evidence

- Compile: `0 errors, 0 warnings, 8246 ms`, X64 Regular
- Source SHA-256: `91aa32ea26af33ae46edf96395d31f8d2df6ab640cf6a859f870c5a80aa22271`
- EX5 SHA-256: `a7b6b512ef955e234d34ec3f3614781087e275fba91b7436697d3578767961a6`
- MarketData SHA-256: `492e4bdf1e96be9875a3bcc65e6b4111047877627c07649abc77130773dd0d80`
- BrokerAdapter SHA-256: `36a1e3551c7d1adea538096d93bd805c624bc67b59744b4d336ade4b8dbb5987`
- SafetyTests SHA-256: `f4693e363686d9ee7b2b0a206b8105ee4ffd89302c608d1f1616652c37123503`
- Initialization: `BrokerAdapter initialized. Magic=20260701 deviation_pts=11`
- New fixture: `TEST 26 PASS: Broker unit policy tick=aligned deviation=configured`
- Complete suite: `28 passed, 0 failed`
- Tester: `43553` ticks, `2179` bars, `42.449 s`
- Deposit/final balance: `10000.00 USD` / `10000.00 USD`

## Boundary

PASS for deterministic price-grid and configured-deviation consistency. This does not prove fills, requotes, freeze-level handling, modification rejection, or fail-safe close behavior at a real broker.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
