# Multi-window stop-geometry audit

## Scope

This audit uses the same three naturally completed, exact-byte-bounded journal
slices as the TP reachability screen. It includes only signals with final
geometry that either passed central risk or were rejected by central risk.
Point size is the tested XAUUSD specification's `0.01`; the configured central
maximum is 1,000 points.

## Result

| Strategy | Accepted | Stop-too-far | Accepted median | Rejected median | Rejected ATR range |
| --- | ---: | ---: | ---: | ---: | ---: |
| FBO | 10 | 9 | 728.5 points | 1,499 points | 1.57–2.90 ATR |
| MR | 4 | 1 | 258 points | 1,006 points | 0.75 ATR |

FBO's rejects are material rather than rounding noise: the median exceeds the
cap by 499 points and the maximum by 1,181. Source review found the intended
construction: the stop sits beyond `sweep_extreme` plus
`InpFBO_StopBeyondSweep` (1.0 ATR). Large sweep-to-entry distance therefore
combines with the ATR buffer. The central limit is correctly rejecting that
geometry; this sample does not justify clipping the stop or widening the cap.

MR's only reject exceeds the cap by six points. Its 0.75 ATR normalization
shows that a fixed absolute cap can reject a moderate volatility-relative stop
during a high-price-range window. The source correctly anchors the stop at the
range boundary with the configured emergency multiplier. One boundary sample
is insufficient to change the policy.

## Decision

- No malformed stop arithmetic was found in FBO or MR.
- Keep `InpMaxStopPoints=1000` unchanged.
- Do not clamp an engine stop to the cap: that would move invalidation inside
  the strategy's defining structure.
- Future stop research should compare strategy outcomes under named stop-mode
  templates (`DEFAULT`, `ATR`, `SWEEP`, `STRUCTURAL`) while applying the same
  central safety limit, costs, and untouched holdout.
- Collect more MR boundary observations before considering a volatility-aware
  *eligibility* filter. Do not make the safety maximum volatility-adaptive from
  this evidence.

The generated distribution is in `report.md`.
