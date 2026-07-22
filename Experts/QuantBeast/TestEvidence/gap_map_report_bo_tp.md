# QuantBeast gap-map report

Rows analyzed: 4140

## Coverage by family

| Family | Rows | Accepted | Rejected |
| --- | --- | --- | --- |
| breakout | 2070 | 0 | 2070 |
| trend_pullback | 2070 | 0 | 2070 |

## Coverage by template

| Family | Template | Rows | Accepted | Rejected |
| --- | --- | --- | --- | --- |
| breakout | range_breakout | 2070 | 0 | 2070 |
| trend_pullback | pullback_resume | 2070 | 0 | 2070 |

## Top rejection reasons

| Rejection reason | Count |
| --- | --- |
| TP: not eligible | 2062 |
| Breakout: not eligible | 1822 |
| Breakout Long: HTF bias is not up | 100 |
| Breakout Short: no trigger | 57 |
| Breakout Short: price not near lower boundary | 30 |
| Breakout Short: HTF bias is not down | 24 |
| Breakout: price not near upper boundary | 13 |
| Breakout: no trigger | 11 |
| TP Long: not uptrend | 4 |
| TP Short: configured trigger not confirmed | 2 |

## Template overlap hints

No multi-template family overlap detected in the analyzed rows.

## Tag cardinality hints

Each analyzed family/template combination used a single tag string in this sample.
