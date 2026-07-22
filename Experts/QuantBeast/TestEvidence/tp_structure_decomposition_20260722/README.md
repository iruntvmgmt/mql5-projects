# TP structure decomposition — 2026-07-22

## Method

TP structure rejections now journal the raw values used by `StructuralState`:
absolute normalized slope, directional efficiency, displacement, equilibrium
distance, and return-to-value state. This is diagnostic-only and does not alter
eligibility or order behavior.

The pinned TP combined profile ran on XAUUSD M5 true ticks for 2026-06-22.
SignalJournal range `9,043,702..9,621,846` contains 880 decisions. The normal
funnel remains unchanged: TP produced zero candidates, with 160 directional
trend failures, 58 structure failures, and 2 persistence failures.

## Result

Within the 58 TP structure-rejection rows, overlapping failures were:

| Predicate | Rows | Share |
| --- | ---: | ---: |
| Impulse displacement `<= 1.0` | 54 | 93.1% |
| Pullback not returning to value | 54 | 93.1% |
| Impulse efficiency `<= 0.4` | 40 | 69.0% |
| Slope `<= 0.2` | 30 | 51.7% |
| Pullback equilibrium distance `<= 0.5` | 0 | 0.0% |

Ten rows passed slope and structural efficiency and were blocked from the
impulse path only by displacement; two more passed slope and displacement but
were blocked by structural efficiency. No row represented a complete pullback:
the four rows returning to value all failed the configured slope threshold.

Observed displacement was broad (`0.017..1.803`, median `0.325`), so directly
dropping the threshold to the median would be an aggressive selection change,
not a bug fix. A moderate displacement matrix should be tested before changing
the default.

## Architecture finding

The TP profile set `InpTP_MinDirEfficiency=0.3`, but impulse structure retains
its own fixed `dir_efficiency > 0.4` gate. This does not make the TP input wholly
inert—pullback structure has no efficiency gate—but it prevents that input from
relaxing the impulse path. Future parameter metadata should distinguish
strategy eligibility thresholds from upstream regime-classifier thresholds.

## Verification

- Compile: **0 errors, 0 warnings**.
- Combined self-test regression: **65 passed, 0 failed**.
- Shadow mode only; no broker orders transmitted.
