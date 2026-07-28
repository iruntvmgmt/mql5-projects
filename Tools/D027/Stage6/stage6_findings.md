# D027 Stage 6 — actual combined-EA portfolio findings

The EA has one global RR input, so comparisons are target-matched: A and SweepReclaim at 2R, E and SweepReclaim at 3R. Combined figures come from actual shared arbitration/ownership backtests; standalone results are never arithmetically added.

## Incremental results

| Pair | Core R | Combined R | Incremental R | Core DD | Combined DD | Trades Δ |
|---|---:|---:|---:|---:|---:|---:|
| A 2R | 28.244700 | 20.740000 | -7.504700 | 15.158100 | 25.279800 | 147 |
| E 3R | 31.246500 | 20.593300 | -10.653200 | 16.920400 | 28.116400 | 140 |

## Decision

A+SweepReclaim loses 7.5047R versus A and increases drawdown by 10.1217R. E+SweepReclaim loses 10.6532R versus E and increases drawdown by 11.1960R.

The combined A and E variants remain positive after removing their top three trades (14.740000R and 11.593300R), but only 6.846400R and 4.477500R remain after each best quarter. Final-holdout results are 6.085600R for the A pair and 0.759800R for the E pair, both below their matched core holdout results.

The actual A pair adds 126 same-bar-unique SweepReclaim-owned trades at 0.087839R expectancy; the E pair adds 123 at 0.042392R. These additions do not compensate for displaced/degraded core behavior: the A pair displaces 10 baseline core trades and newly executes 31; the E pair displaces 14 and newly executes 31. The changed outcomes arise under shared ownership and opposite-family exits. SweepReclaim is therefore rejected as a portfolio addition to A or E under the frozen combined architecture. Standalone 2R remains research-only, not promoted.
