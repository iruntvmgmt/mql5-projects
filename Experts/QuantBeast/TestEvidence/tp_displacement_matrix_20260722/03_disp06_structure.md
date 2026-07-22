# TP structure rejection decomposition

Rows matched: 58
Configured slope threshold: 0.200

Configured displacement threshold: 0.600

Counts are overlapping predicate failures; one rejected observation may appear in several rows.

## Predicate failures

| Predicate | Failed rows | Share |
| --- | --- | --- |
| pullback_returning | 54 | 93.1% |
| impulse_displacement | 46 | 79.3% |
| impulse_efficiency | 40 | 69.0% |
| slope | 30 | 51.7% |

## Preempting structural states

| State | Rows |
| --- | --- |
| STRUCTURE_BALANCED | 40 |
| STRUCTURE_FAILED_BREAKOUT | 14 |
| STRUCTURE_BREAKOUT_ATTEMPT | 4 |

## Observed feature distribution

| Feature | Minimum | Median | Maximum |
| --- | --- | --- | --- |
| slope | 0.106 | 0.200 | 0.265 |
| eff | 0.305 | 0.375 | 0.619 |
| disp | 0.017 | 0.325 | 1.803 |
| equil | 0.664 | 1.372 | 3.609 |

## Otherwise impulse-qualified displacement

Rows: 6; minimum: 0.203; median: 0.288; maximum: 0.419

## Failure combinations

| Combination | Rows |
| --- | --- |
| slope + impulse_efficiency + impulse_displacement + pullback_returning | 20 |
| impulse_efficiency + impulse_displacement + pullback_returning | 14 |
| impulse_displacement + pullback_returning | 6 |
| impulse_efficiency + pullback_returning | 4 |
| pullback_returning | 4 |
| slope + pullback_returning | 4 |
| slope + impulse_efficiency + impulse_displacement | 2 |
| slope + impulse_displacement | 2 |
| slope + impulse_displacement + pullback_returning | 2 |

## State and failure combination

| State | Combination | Rows |
| --- | --- | --- |
| STRUCTURE_BALANCED | slope + impulse_efficiency + impulse_displacement + pullback_returning | 16 |
| STRUCTURE_BALANCED | impulse_efficiency + impulse_displacement + pullback_returning | 12 |
| STRUCTURE_FAILED_BREAKOUT | slope + impulse_efficiency + impulse_displacement + pullback_returning | 4 |
| STRUCTURE_BALANCED | impulse_efficiency + pullback_returning | 4 |
| STRUCTURE_BALANCED | impulse_displacement + pullback_returning | 4 |
| STRUCTURE_FAILED_BREAKOUT | pullback_returning | 4 |
| STRUCTURE_FAILED_BREAKOUT | impulse_efficiency + impulse_displacement + pullback_returning | 2 |
| STRUCTURE_BALANCED | slope + impulse_efficiency + impulse_displacement | 2 |
| STRUCTURE_BALANCED | slope + impulse_displacement | 2 |
| STRUCTURE_FAILED_BREAKOUT | slope + pullback_returning | 2 |
| STRUCTURE_BREAKOUT_ATTEMPT | slope + impulse_displacement + pullback_returning | 2 |
| STRUCTURE_FAILED_BREAKOUT | impulse_displacement + pullback_returning | 2 |
| STRUCTURE_BREAKOUT_ATTEMPT | slope + pullback_returning | 2 |
