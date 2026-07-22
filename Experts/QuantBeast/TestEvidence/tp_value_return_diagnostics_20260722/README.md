# TP value-return diagnostics

## Demonstrated defect

`FeatureEngine` set `returning_to_value=true` whenever the current closed bar
was within 0.3 ATR of rolling VWAP. It did not compare consecutive bars. The
name therefore conflated location with direction of travel, preventing the TP
reachability study from testing whether a pullback was actually returning.

Severity: **Medium** research/strategy semantics. This did not weaken a safety
control or create broker exposure.

## Change boundary

The feature snapshot now records the prior normalized VWAP distance, absolute
distance contraction, movement toward value, and crossing into the existing
0.3 ATR value zone. TP structure rejection descriptions expose these fields.
The legacy `returning_to_value` calculation and all eligibility, entry, stop,
target, sizing, and risk behavior are unchanged.

## Verification

- Compile at 2026-07-22 10:12:06: `0 errors, 0 warnings`.
- Deterministic Test 63 distinguishes an approaching bar outside value, a
  departing bar still inside value, and a crossing bar.
- Shadow regression: `66 passed, 0 failed`.
- Tester footer: 22,080 generated ticks, 1,104 bars, final balance 10,000 USD,
  natural `test passed` / `thread finished` completion.
- Journals were disabled and Shadow mode was used; no broker orders were sent.

## Hashes

- `QuantBeastEA.mq5`: `3cf5c6c7a4bd6b4ce54ca7956b49e69bad91ba16dd8b39fe0ec86e8305ef6c23`
- `QuantBeastEA.ex5`: `11f63fd0617af6d1af17c0638f00d9d838c60a44f5f198354b93ca25f151d473`
- `FeatureEngine.mqh`: `33b3f9740c3ac58ad22f034606bf808c8b43922f3db588b7cd0025d34adc6892`
- `TrendPullbackEngine.mqh`: `31bab78fb90e44fcac6e711d4e2c67d80a2cc3cb78da695f9492be749711d616`
