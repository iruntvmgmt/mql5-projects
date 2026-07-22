# TP observational lifecycle

## Purpose

The multi-window screen showed that isolated near-VWAP or movement-toward-VWAP
flags do not describe a complete trend-pullback event. This change introduces
event sequencing as instrumentation before any entry redesign.

## Lifecycle

```text
idle → impulse → retracing → resume_candidate
          └───────────────→ expired
any active phase ─────────→ invalidated
```

- `impulse`: directional trend plus `STRUCTURE_IMPULSE`.
- `retracing`: the same directional context subsequently contracts its
  absolute VWAP distance.
- `resume_candidate`: after retracing, VWAP distance stops contracting and the
  completed candle realigns with the original trend direction.
- `expired`: pullback observation exceeds `InpTP_MaxPullbackBars`.
- `invalidated`: trend direction/context changes or event state is not normal.

These are observational labels only. No phase can authorize a signal.

## Verification

- Compile: `0 errors, 0 warnings`, 2026-07-22 11:30:22.
- Deterministic Test 64 covers sequencing, same-snapshot idempotence, and trend
  reversal invalidation.
- Shadow regression: `67 passed, 0 failed`; 22,080 generated ticks, 1,104
  bars; final balance 10,000 USD; natural `test passed` / `thread finished`.
- No broker orders were transmitted.
- The report parser accepts legacy rows and synthetic lifecycle-formatted rows.

## Hashes

- `QuantBeastEA.mq5`: `95cda300c9d10558b00c18f121951972b79e5bf15a26dfe0347a160305aaea70`
- `QuantBeastEA.ex5`: `b7d77c4cc9fe608277ee9fdc3b50b9ed35f75e40e24c9b9c8da8b28111a931d3`
- `TrendPullbackEngine.mqh`: `c7ca741b0409c921e8d354af62263607d202551eb69c752971b7e99cbf790ac4`
- `SafetyTests.mqh`: `bb795f1d09e20b6e4813a129821bef558c5aadb11e3e569d23f87e3955cc9726`
