# TP structure rejection decomposition

Rows matched: 104
Configured slope threshold: 0.200

Configured displacement threshold: 1.000

Counts are overlapping predicate failures; one rejected observation may appear in several rows.

## Predicate failures

| Predicate | Failed rows | Share |
| --- | --- | --- |
| pullback_returning | 100 | 96.2% |
| impulse_displacement | 92 | 88.5% |
| impulse_efficiency | 44 | 42.3% |
| slope | 40 | 38.5% |
| pullback_equilibrium | 6 | 5.8% |

## Preempting structural states

| State | Rows |
| --- | --- |
| STRUCTURE_BALANCED | 66 |
| STRUCTURE_FAILED_BREAKOUT | 22 |
| STRUCTURE_EXHAUSTION | 10 |
| STRUCTURE_BREAKOUT_ATTEMPT | 6 |

## Observed feature distribution

| Feature | Minimum | Median | Maximum |
| --- | --- | --- | --- |
| slope | 0.102 | 0.212 | 0.312 |
| eff | 0.304 | 0.416 | 0.597 |
| disp | 0.021 | 0.309 | 1.554 |
| equil | 0.095 | 1.832 | 3.905 |

## Otherwise impulse-qualified displacement

Rows: 44; minimum: 0.077; median: 0.160; maximum: 0.925

## Value-return movement diagnostics

| Diagnostic | Rows | Share of diagnostic rows |
| --- | --- | --- |
| moving_toward | 52 | 50.0% |
| not_moving_toward | 52 | 50.0% |
| crossed_into_value | 2 | 1.9% |
| near_value_but_departing | 0 | 0.0% |


Progress distribution: minimum -1.359, median -0.004, maximum 2.189.

## Observational lifecycle phases

| Phase | Rows | Median phase bars | Maximum phase bars |
| --- | --- | --- | --- |
| invalidated | 122 | 0.0 | 0 |
| idle | 80 | 0.0 | 0 |
| impulse | 30 | 0.0 | 1 |
| retracing | 24 | 2.0 | 4 |
| resume_candidate | 8 | 2.5 | 3 |

## Observational impulse seeds

| Seed source | Rows | Median span ATR | Maximum span ATR |
| --- | --- | --- | --- |
| tp_specific | 184 | 0.969 | 3.706 |
| none | 80 | n/a | n/a |

## Observational lifecycle directions

| Nominated direction | Rows |
| --- | --- |
| none | 202 |
| down | 44 |
| up | 18 |

## Failure combinations

| Combination | Rows |
| --- | --- |
| impulse_displacement + pullback_returning | 44 |
| slope + impulse_efficiency + impulse_displacement + pullback_returning | 16 |
| impulse_efficiency + impulse_displacement + pullback_returning | 14 |
| slope + impulse_displacement + pullback_returning | 10 |
| pullback_returning | 4 |
| slope + impulse_efficiency + pullback_returning | 4 |
| slope + impulse_efficiency + impulse_displacement + pullback_equilibrium + pullback_returning | 4 |
| slope + impulse_efficiency + impulse_displacement | 4 |
| slope + pullback_returning | 2 |
| impulse_efficiency + pullback_equilibrium + pullback_returning | 2 |

## State and failure combination

| State | Combination | Rows |
| --- | --- | --- |
| STRUCTURE_BALANCED | impulse_displacement + pullback_returning | 34 |
| STRUCTURE_BALANCED | impulse_efficiency + impulse_displacement + pullback_returning | 10 |
| STRUCTURE_BALANCED | slope + impulse_efficiency + impulse_displacement + pullback_returning | 10 |
| STRUCTURE_FAILED_BREAKOUT | impulse_displacement + pullback_returning | 8 |
| STRUCTURE_BALANCED | slope + impulse_displacement + pullback_returning | 6 |
| STRUCTURE_FAILED_BREAKOUT | impulse_efficiency + impulse_displacement + pullback_returning | 4 |
| STRUCTURE_EXHAUSTION | slope + impulse_displacement + pullback_returning | 4 |
| STRUCTURE_EXHAUSTION | slope + impulse_efficiency + impulse_displacement + pullback_returning | 4 |
| STRUCTURE_FAILED_BREAKOUT | slope + impulse_efficiency + impulse_displacement + pullback_equilibrium + pullback_returning | 4 |
| STRUCTURE_BALANCED | slope + impulse_efficiency + impulse_displacement | 4 |
| STRUCTURE_BREAKOUT_ATTEMPT | pullback_returning | 2 |
| STRUCTURE_BREAKOUT_ATTEMPT | impulse_displacement + pullback_returning | 2 |
| STRUCTURE_BREAKOUT_ATTEMPT | slope + impulse_efficiency + pullback_returning | 2 |
| STRUCTURE_EXHAUSTION | slope + pullback_returning | 2 |
| STRUCTURE_FAILED_BREAKOUT | pullback_returning | 2 |
| STRUCTURE_BALANCED | slope + impulse_efficiency + pullback_returning | 2 |
| STRUCTURE_FAILED_BREAKOUT | impulse_efficiency + pullback_equilibrium + pullback_returning | 2 |
| STRUCTURE_FAILED_BREAKOUT | slope + impulse_efficiency + impulse_displacement + pullback_returning | 2 |
