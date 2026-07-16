# TP pullback-age repair evidence — 2026-07-16

## Defect

`InpTP_MaxPullbackBars` was passed into `CTrendPullbackEngine::Init()` as `m_maxPullbackBars`, but long/short TP evaluation did not enforce pullback age.

## Severity

Medium configuration-integrity defect.

Operators could change the maximum pullback-duration input without affecting Trend Pullback eligibility, which could invalidate strategy research and later live-readiness assumptions.

## Affected paths

- `Include/QuantBeast/Strategies/TrendPullbackEngine.mqh`
- `Include/QuantBeast/Testing/SafetyTests.mqh`

## Fix

- Long TP setups now reject when `features.swing_high_bars > InpTP_MaxPullbackBars`.
- Short TP setups now reject when `features.swing_low_bars > InpTP_MaxPullbackBars`.
- Zero swing-age values are treated as unavailable, not as stale-pullback proof.
- TP signal descriptions now include pullback age.
- `TEST 18` now verifies valid long/short reachability and stale-age rejection.

## Compile

```text
2026.07.16 13:39:11.437 Compile MQL5\Experts\QuantBeast\QuantBeastEA.mq5 - 0 errors, 0 warnings, 19911 ms elapsed, cpu='X64 Regular'
```

## Tester configuration

- Evidence config: `QuantBeast.TPPullbackAge.XAUUSD.M5.20260716_1339.ini`
- EA: `QuantBeast\QuantBeastEA.ex5`
- Symbol/timeframe: `XAUUSD`, `M5`
- Model: `1` generated ticks
- Window: `2026.05.18` to `2026.05.22`
- Mode: Shadow (`InpMode=1`)
- Broker transmission acknowledgements: false
- Persistence/global variables: disabled
- File journals: disabled
- Self-tests: enabled with detail logging

## Result

The tester MCP returned the known unreliable `job_id: 0`, so the result is taken from the bounded newly appended tester-agent log suffix.

```text
TEST 18 PASS: TP reachability L=valid S=valid age=rejected gate=rejected
Self-tests complete: 51 passed, 0 failed
Tester final balance 10000.00 USD
Tester OnTester result 0
XAUUSD,M5: 22080 ticks, 1104 bars generated
Test passed in 0:00:15.699
```

Temporary `MQL5/Profiles/Tester` launcher config was removed after the run.

## Hashes

```text
MQL5/Experts/QuantBeast/QuantBeastEA.mq5 sha256=8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49 bytes=100657
MQL5/Experts/QuantBeast/QuantBeastEA.ex5 sha256=e64f3f8ce8b201b7614d13c3a6ea4129677883657c01af4528a35735f4e6f859 bytes=488768
MQL5/Include/QuantBeast/Strategies/TrendPullbackEngine.mqh sha256=41a5c6050560ed52c85e355c1a6e032b5ff36046f29e91e3a11882a69079f905 bytes=10839
MQL5/Include/QuantBeast/Testing/SafetyTests.mqh sha256=c9fbb503b55c851062583a435207c8e9ccb49749df26fea04dcd56aaab0ffdb0 bytes=59950
```

## Readiness impact

Readiness remains exactly:

```text
READY FOR SHADOW MODE
```

No broker orders were transmitted. This repair improves TP configuration correctness; it does not prove TP organic accepted-entry performance or live readiness.
