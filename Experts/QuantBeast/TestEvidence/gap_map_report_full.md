# QuantBeast gap-map report

Rows analyzed: 17874

## Coverage by family

| Family | Rows | Accepted | Rejected |
| --- | --- | --- | --- |
| breakout | 4452 | 0 | 4452 |
| failed_breakout | 4518 | 99 | 4419 |
| mean_reversion | 4452 | 0 | 4452 |
| trend_pullback | 4452 | 0 | 4452 |

## Coverage by template

| Family | Template | Rows | Accepted | Rejected |
| --- | --- | --- | --- | --- |
| breakout | range_breakout | 4452 | 0 | 4452 |
| failed_breakout | reclaim_reversal | 4518 | 99 | 4419 |
| mean_reversion | value_reversion | 4452 | 0 | 4452 |
| trend_pullback | pullback_resume | 4452 | 0 | 4452 |

## Top rejection reasons

| Rejection reason | Count |
| --- | --- |
| TP: not eligible | 4436 |
| MR: not eligible | 4250 |
| Breakout: not eligible | 3930 |
| FBO: not eligible | 3898 |
| Breakout Long: HTF bias is not up | 200 |
| FBO Short: no upside failed auction | 169 |
| Breakout Short: no trigger | 114 |
| FBO Long: no downside failed auction | 106 |
| FBO Long: reclaim depth too small | 88 |
| Breakout Short: HTF bias is not down | 61 |

## Template overlap hints

No multi-template family overlap detected in the analyzed rows.

## Tag cardinality hints

Each analyzed family/template combination used a single tag string in this sample.
