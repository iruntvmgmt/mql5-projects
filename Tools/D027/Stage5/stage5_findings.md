# D027 Stage 5 — limited SweepReclaim 3R screen

SweepReclaim was the only Stage 4 family eligible for this single predefined 3R run. The frozen trigger and sequence journals are unchanged; only the fixed target changes from 2R to 3R.

## Headline comparison

| Variant | Trades | Expectancy R | PF | Cumulative R | Max DD R |
|---|---:|---:|---:|---:|---:|
| 2R | 190 | 0.150588 | 1.268759 | 28.611700 | 18.294100 |
| 3R | 187 | 0.130258 | 1.204079 | 24.358300 | 27.695200 |

## Decision

The 3R variant remains positive full-window and after its top three trades, but it falls to -2.908500R without its best quarter and is negative in the final holdout. It also lowers cumulative R, expectancy, and PF while increasing maximum drawdown versus 2R. Therefore 3R is rejected as the preferred fixed target; frozen 2R remains the research candidate for Stage 6 portfolio testing. This is not production promotion.

Raw candidate sets are identical and sequence journals are byte-identical. The executed trade counts differ only because the wider target changes how long ownership remains occupied, which causally changes later execution eligibility. No standalone returns are arithmetically combined.
