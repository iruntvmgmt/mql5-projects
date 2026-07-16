# FBO target-variant repair evidence — 2026-07-16

## Defect

`InpFBO_TargetVWAPR` was passed into `CFailedBreakoutEngine::Init()` and stored as `m_targetVWAPR`, but fallback target geometry used only `m_targetMidR` when midpoint/VWAP levels were invalid or on the wrong side of entry.

## Severity

Medium configuration-integrity defect.

Operators could change the VWAP target fallback input without changing fallback target geometry, which could invalidate strategy research and later live-readiness assumptions.

## Affected paths

- `Include/QuantBeast/Strategies/FailedBreakoutEngine.mqh`
- `Include/QuantBeast/Testing/SafetyTests.mqh`

## Fix

- FBO now builds separate midpoint and VWAP target candidates.
- Valid midpoint/VWAP levels are still used.
- Invalid or wrong-side midpoint falls back through `InpFBO_TargetMidR`.
- Invalid or wrong-side VWAP falls back through `InpFBO_TargetVWAPR`.
- Longs select the higher candidate; shorts select the lower candidate, preserving prior directional target-selection intent.
- FBO signal descriptions now include `targetMidR` and `targetVWAPR`.
- `TEST 17` now verifies long and short VWAP-R fallback behavior.

## Compile

```text
Result: 0 errors, 0 warnings, 20130 ms elapsed, cpu='X64 Regular'
```

Compile log: `compile.log`.

## Tester configuration

- Evidence config: `QuantBeast.FBOTargetVariants.XAUUSD.M5.20260716_1355.ini`
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
TEST 17 PASS: FBO reachability L=valid S=valid targetL=vwapR targetS=vwapR gate=rejected
Self-tests complete: 51 passed, 0 failed
Tester final balance 10000.00 USD
Tester OnTester result 0
XAUUSD,M5: 22080 ticks, 1104 bars generated
Test passed in 0:00:20.920
```

Temporary `MQL5/Profiles/Tester` launcher config was removed after the run.

## Hashes

```text
MQL5/Experts/QuantBeast/QuantBeastEA.mq5 sha256=8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49 bytes=100657
MQL5/Experts/QuantBeast/QuantBeastEA.ex5 sha256=869da00fbd86607002ad605c5364511938e33a93a2875f91df9ee134647ec232 bytes=492552
MQL5/Include/QuantBeast/Strategies/FailedBreakoutEngine.mqh sha256=0790d244f9682a9cb774b5ad04e24b48963ee5bb4d3fb52d5bfb44934f4bbdab bytes=9355
MQL5/Include/QuantBeast/Testing/SafetyTests.mqh sha256=b9937f79d9ee928fd02824c12ab5a1026daea7652533f2c26a8abaead40d6fbc bytes=61380
```

## Readiness impact

Readiness remains exactly:

```text
READY FOR SHADOW MODE
```

No broker orders were transmitted. This repair improves FBO configuration correctness; it does not prove strategy edge or live readiness.
