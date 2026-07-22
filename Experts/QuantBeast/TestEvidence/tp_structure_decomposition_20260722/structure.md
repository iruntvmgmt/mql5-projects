# TP structure rejection decomposition

Rows matched: 58
Configured slope threshold: 0.200

Counts are overlapping predicate failures; one rejected observation may appear in several rows.

## Predicate failures

| Predicate | Failed rows | Share |
| --- | --- | --- |
| impulse_displacement | 54 | 93.1% |
| pullback_returning | 54 | 93.1% |
| impulse_efficiency | 40 | 69.0% |
| slope | 30 | 51.7% |

## Observed feature distribution

| Feature | Minimum | Median | Maximum |
| --- | --- | --- | --- |
| slope | 0.106 | 0.200 | 0.265 |
| eff | 0.305 | 0.375 | 0.619 |
| disp | 0.017 | 0.325 | 1.803 |
| equil | 0.664 | 1.372 | 3.609 |

## Otherwise impulse-qualified displacement

Rows: 10; minimum: 0.203; median: 0.419; maximum: 0.805

## Failure combinations

| Combination | Rows |
| --- | --- |
| slope + impulse_efficiency + impulse_displacement + pullback_returning | 20 |
| impulse_efficiency + impulse_displacement + pullback_returning | 16 |
| impulse_displacement + pullback_returning | 10 |
| slope + impulse_displacement + pullback_returning | 4 |
| slope + impulse_efficiency + impulse_displacement | 2 |
| slope + impulse_displacement | 2 |
| impulse_efficiency + pullback_returning | 2 |
| slope + pullback_returning | 2 |
