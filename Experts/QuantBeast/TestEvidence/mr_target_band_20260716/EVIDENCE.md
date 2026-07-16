# MR opposite-band target repair evidence — 2026-07-16

## Defect

`InpMR_TargetSDBandR` was passed into `CMeanReversionEngine::Init()` and stored as `m_targetSDBandR`, but MR target calculation never used it. Long and short targets used only VWAP, range midpoint, or fixed-R fallback.

## Severity

Medium configuration-integrity defect.

Operators could change an MR target input without affecting MR target geometry, which could invalidate strategy research and later live-readiness assumptions.

## Affected paths

- `Include/QuantBeast/Strategies/MeanReversionEngine.mqh`
- `Include/QuantBeast/Testing/SafetyTests.mqh`

## Fix

- Long MR now targets `features.vwap + InpMR_TargetSDBandR * features.vwap_sd` when VWAP SD is available.
- Short MR now targets `features.vwap - InpMR_TargetSDBandR * features.vwap_sd` when VWAP SD is available.
- Existing VWAP, range-midpoint, and fixed-R fallbacks remain for unavailable or invalid band geometry.
- MR signal descriptions now include `targetBandR`.
- `TEST 19` now verifies long and short SD-band target direction.

## Compile

An intentional intermediate compile failed because the test used nonexistent `StrategySignal.target`; this was corrected to `StrategySignal.proposed_target`.

Final compile:

```text
Result: 0 errors, 0 warnings, 19852 ms elapsed, cpu='X64 Regular'
```

Compile log: `compile.log`.

## Tester configuration

- Evidence config: `QuantBeast.MRTargetBand.XAUUSD.M5.20260716_1349.ini`
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
TEST 19 PASS: MR reachability L=valid S=valid bandL=ok bandS=ok gate=rejected
Self-tests complete: 51 passed, 0 failed
Tester final balance 10000.00 USD
Tester OnTester result 0
XAUUSD,M5: 22080 ticks, 1104 bars generated
Test passed in 0:00:19.122
```

Temporary `MQL5/Profiles/Tester` launcher config was removed after the run.

## Hashes

```text
MQL5/Experts/QuantBeast/QuantBeastEA.mq5 sha256=8b36c2f7f66f38d2fbe982cd4d9427e2c14e2d8e55658c041d1d38bcd1b9ba49 bytes=100657
MQL5/Experts/QuantBeast/QuantBeastEA.ex5 sha256=136d822b4f92d84711e6e8e9f0ca65b1001add796e5983c79eca8150c547c591 bytes=489672
MQL5/Include/QuantBeast/Strategies/MeanReversionEngine.mqh sha256=e77275d0b56f14a788595ea6c83b4f608448a5d1ab65365a6329ee9458ed3443 bytes=10007
MQL5/Include/QuantBeast/Testing/SafetyTests.mqh sha256=2faf41297450ea5493ea25f3f8e27cfee0751652312ceb4ced67281069717ab6 bytes=60311
```

## Readiness impact

Readiness remains exactly:

```text
READY FOR SHADOW MODE
```

No broker orders were transmitted. This repair improves MR configuration correctness; it does not prove MR organic accepted-entry performance or live readiness.
