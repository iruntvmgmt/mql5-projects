# D027 Stage 4 deterministic standalone screen

All five families were screened alone at fixed 2R on the frozen history split. Regimes are joined at the entry decision. No threshold was changed, no regime gate was applied, and no strategy was promoted by this analysis.

## Full-window results

| Strategy | Trades | Expectancy R | PF | Cumulative R | Max DD R |
|---|---:|---:|---:|---:|---:|
| AlignedFastPullback | 110 | -0.062989 | 0.902338 | -6.928800 | 17.681000 |
| BreakoutRetest | 354 | -0.106712 | 0.846951 | -37.775900 | 49.518900 |
| SweepReclaim | 190 | 0.150588 | 1.268759 | 28.611700 | 18.294100 |
| CompressionBreakout | 84 | -0.032580 | 0.935325 | -2.736700 | 11.415100 |
| StructureTransition | 21 | -0.104248 | 0.845714 | -2.189200 | 8.000000 |

## Window-separated results

| Strategy | Window | Trades | Expectancy R | Cumulative R |
|---|---|---:|---:|---:|
| AlignedFastPullback | Development | 66 | -0.136494 | -9.008600 |
| AlignedFastPullback | Validation | 23 | 0.205696 | 4.731000 |
| AlignedFastPullback | Final holdout | 21 | -0.126248 | -2.651200 |
| BreakoutRetest | Development | 175 | -0.105662 | -18.490900 |
| BreakoutRetest | Validation | 89 | -0.168406 | -14.988100 |
| BreakoutRetest | Final holdout | 90 | -0.047743 | -4.296900 |
| SweepReclaim | Development | 123 | 0.142951 | 17.583000 |
| SweepReclaim | Validation | 29 | 0.154121 | 4.469500 |
| SweepReclaim | Final holdout | 38 | 0.172611 | 6.559200 |
| CompressionBreakout | Development | 48 | -0.079990 | -3.839500 |
| CompressionBreakout | Validation | 12 | -0.001217 | -0.014600 |
| CompressionBreakout | Final holdout | 24 | 0.046558 | 1.117400 |
| StructureTransition | Development | 11 | -0.454545 | -5.000000 |
| StructureTransition | Validation | 6 | 0.000000 | 0.000000 |
| StructureTransition | Final holdout | 4 | 0.702700 | 2.810800 |

## Stage 5 eligibility screen

- `AlignedFastPullback`: **NOT ELIGIBLE** for the later one-off 3R check under the frozen mechanical screen.
- `BreakoutRetest`: **NOT ELIGIBLE** for the later one-off 3R check under the frozen mechanical screen.
- `SweepReclaim`: **ELIGIBLE** for the later one-off 3R check under the frozen mechanical screen.
- `CompressionBreakout`: **NOT ELIGIBLE** for the later one-off 3R check under the frozen mechanical screen.
- `StructureTransition`: **NOT ELIGIBLE** for the later one-off 3R check under the frozen mechanical screen.

Same-bar overlap means the canonical FastMedConfluence baseline emitted an executed signal with the same decision time and direction. Shared-origin overlap is reported separately. “Unique” uses the stricter practical same-bar definition and is descriptive, not proof of independent edge.

Wall-clock exposure is summed holding bars divided by elapsed wall-clock M5 bars; it is not MT5 margin exposure. Spread is naturally present in tester fills; the configurations use the canonical 80-point spread guard and 30-point deviation. No separate commission-R estimate is invented.
