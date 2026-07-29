# D028 Stage 3 — Single-Book Equivalence

All three active single-book runs are byte-identical to their certified controls.

| Run | Trades | Cumulative R | Expectancy R | PF | Max DD R | Long | Short |
|---|---:|---:|---:|---:|---:|---:|---:|
| A_2R | 224 | 28.2447 | 0.1261 | 1.2446 | 15.1581 | 107 | 117 |
| E_3R | 213 | 31.2465 | 0.1467 | 1.2532 | 16.9204 | 101 | 112 |
| SweepReclaim_2R | 190 | 28.6117 | 0.1506 | 1.2688 | 18.2941 | 96 | 94 |

Every portfolio logical-position ID matches the corresponding certified
trade cluster ID in chronological order. There are no missing, unexpected,
or duplicate logical trades.

No combined strategy configuration was run. Stage 4 remains blocked until
this Stage 3 checkpoint is committed and pushed.
