# BO compression-percentile repair evidence — 2026-07-16

## Defect

`InpBO_CompressionPct` was passed into `CBreakoutEngine::Init()` as `m_compressionPct`, but `CBreakoutEngine::IsEligible()` never read it. BO eligibility depended only on the shared `features.compression_bars` value.

## Severity

Medium configuration-integrity defect.

Operators could change a BO-specific compression-percent input and believe the strategy became more or less selective, while BO eligibility did not independently apply that threshold.

## Affected paths

- `Include/QuantBeast/Strategies/BreakoutEngine.mqh`
- `Include/QuantBeast/Data/FeatureEngine.mqh`
- `Include/QuantBeast/Core/Types.mqh`
- `Include/QuantBeast/Testing/SafetyTests.mqh`

Safety consequence: BO research/test behavior could be misinterpreted, and future live-readiness decisions could rely on a disconnected strategy parameter.

## Fix

- Added `FeatureSnapshot::atr_percentile_rank`.
- `FeatureEngine` now calculates the current ATR percentile rank inside the configured compression lookback.
- `CBreakoutEngine::IsEligible()` now rejects when `features.atr_percentile_rank > m_compressionPct`.
- BO signal reason strings now include ATR percentile rank.
- Existing BO reachability self-test now also verifies rejection when the rank exceeds `InpBO_CompressionPct`.

This preserves the shared compression-bar duration check and adds the missing BO-specific threshold gate.

## Compile

```text
2026.07.16 13:34:32.590 Compile MQL5\Experts\QuantBeast\QuantBeastEA.mq5 - 0 errors, 0 warnings, 20999 ms elapsed, cpu='X64 Regular'
```

## Tester configuration

- Evidence config: `QuantBeast.BOCompressionPct.XAUUSD.M5.20260716_1334.ini`
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
TEST 16 PASS: BO reachability L=valid S=valid gate=rejected pct=rejected
Self-tests complete: 51 passed, 0 failed
Tester final balance 10000.00 USD
Tester OnTester result 0
XAUUSD,M5: 22080 ticks, 1104 bars generated
Test passed in 0:00:15.274
```

Temporary `MQL5/Profiles/Tester` launcher config was removed after the run.

## Hashes

See `hashes_post_test.txt` for exact post-test hashes of the EA source, EX5, and modified include files.

## Readiness impact

Readiness remains exactly:

```text
READY FOR SHADOW MODE
```

No broker orders were transmitted. This repair improves strategy-configuration correctness; it does not prove BO organic accepted-entry performance or live readiness.
