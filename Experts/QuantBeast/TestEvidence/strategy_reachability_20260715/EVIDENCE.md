# QuantBeast strategy-reachability evidence — 2026-07-15

## Build

- MetaEditor build: 6002
- Target: X64 Regular
- Result: `0 errors, 0 warnings, 9072 ms`
- Source SHA-256: `8cd0f4469a802964061ad7e8da7a1665b7879b1af30c2df596184f8e63383a88`
- EX5 SHA-256: `5d1c705968a7b08d2af72476986407d632840cf3279390063550d7b3fc1bce06`
- Safety-tests SHA-256: `85433d6b1294fabc6fd2926b0213adbea4fd82e791cd63aeeeb92aa14f3af498`

## Runtime fixture

- Config: `MQL5\Profiles\Tester\QuantBeast.ShadowFinal.XAUUSD.M5.20260518_20260522.ini`
- Symbol/timeframe: XAUUSD M5
- Dates: 2026-05-18 through 2026-05-22
- Deposit: USD 10,000
- Mode: `QB_MODE_SHADOW`
- Direct terminal launch was used after the native tester MCP timed out during `get_workspace_info`.

```text
TEST 16 PASS: BO reachability L=valid S=valid gate=rejected
TEST 17 PASS: FBO reachability L=valid S=valid gate=rejected
TEST 18 PASS: TP reachability L=valid S=valid gate=rejected
TEST 19 PASS: MR reachability L=valid S=valid gate=rejected
Self-tests complete: 21 passed, 0 failed
Tester final balance 10000.00 USD
XAUUSD,M5: 22080 ticks, 1104 bars generated. Test passed in 0:00:11.866.
```

## What this proves

- BO, FBO, TP, and MR can each produce a structurally valid long signal.
- BO, FBO, TP, and MR can each produce a structurally valid short signal.
- Every engine rejects an explicitly ineligible synthetic regime/setup.
- The tests exercise strategy classes directly and do not place broker orders.
- All previously proven Shadow lifecycle fixtures still pass in the same run.

## What this does not prove

- That live features and regime classification frequently create these conditions.
- Signal profitability, calibration, or appropriate default thresholds.
- Arbitration, risk approval, and lifecycle behavior for organically generated signals.
- Broker execution, transactions, fill protection, or restart recovery.

