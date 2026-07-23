# TP structure rejection decomposition

Rows matched: 26
Configured slope threshold: 0.200

Configured displacement threshold: 1.000

Counts are overlapping predicate failures; one rejected observation may appear in several rows.

## Predicate failures

| Predicate | Failed rows | Share |
| --- | --- | --- |
| pullback_returning | 24 | 92.3% |
| impulse_displacement | 22 | 84.6% |
| slope | 6 | 23.1% |

## Preempting structural states

| State | Rows |
| --- | --- |
| STRUCTURE_BALANCED | 26 |

## Observed feature distribution

| Feature | Minimum | Median | Maximum |
| --- | --- | --- | --- |
| slope | 0.161 | 0.224 | 0.283 |
| eff | 0.401 | 0.477 | 0.641 |
| disp | 0.009 | 0.495 | 1.176 |
| equil | 0.780 | 1.371 | 2.952 |

## Otherwise impulse-qualified displacement

Rows: 16; minimum: 0.215; median: 0.419; maximum: 0.889

## Value-return movement diagnostics

| Diagnostic | Rows | Share of diagnostic rows |
| --- | --- | --- |
| moving_toward | 20 | 76.9% |
| not_moving_toward | 6 | 23.1% |
| crossed_into_value | 0 | 0.0% |
| near_value_but_departing | 2 | 7.7% |


Progress distribution: minimum -0.514, median 0.247, maximum 1.524.

## Observational lifecycle phases

| Phase | Rows | Median phase bars | Maximum phase bars |
| --- | --- | --- | --- |
| idle | 804 | 0.0 | 0 |
| invalidated | 94 | 0.0 | 0 |
| retracing | 26 | 2.0 | 7 |
| impulse | 16 | 0.0 | 1 |
| resume_candidate | 6 | 3.0 | 4 |

## Observational impulse seeds

| Seed source | Rows | Median span ATR | Maximum span ATR |
| --- | --- | --- | --- |
| none | 804 | n/a | n/a |
| tp_specific | 142 | 2.782 | 4.966 |

## Observational lifecycle directions

| Nominated direction | Rows |
| --- | --- |
| none | 898 |
| down | 40 |
| up | 8 |

## Failure combinations

| Combination | Rows |
| --- | --- |
| impulse_displacement + pullback_returning | 14 |
| slope + impulse_displacement + pullback_returning | 6 |
| pullback_returning | 4 |
| impulse_displacement | 2 |

## State and failure combination

| State | Combination | Rows |
| --- | --- | --- |
| STRUCTURE_BALANCED | impulse_displacement + pullback_returning | 14 |
| STRUCTURE_BALANCED | slope + impulse_displacement + pullback_returning | 6 |
| STRUCTURE_BALANCED | pullback_returning | 4 |
| STRUCTURE_BALANCED | impulse_displacement | 2 |
