# TP structure rejection decomposition

Rows matched: 54
Configured slope threshold: 0.200

Configured displacement threshold: 1.000

Counts are overlapping predicate failures; one rejected observation may appear in several rows.

## Predicate failures

| Predicate | Failed rows | Share |
| --- | --- | --- |
| impulse_displacement | 54 | 100.0% |
| pullback_returning | 54 | 100.0% |
| slope | 42 | 77.8% |
| impulse_efficiency | 36 | 66.7% |

## Preempting structural states

| State | Rows |
| --- | --- |
| STRUCTURE_BALANCED | 30 |
| STRUCTURE_EXHAUSTION | 10 |
| STRUCTURE_FAILED_BREAKOUT | 8 |
| STRUCTURE_BREAKOUT_ATTEMPT | 6 |

## Observed feature distribution

| Feature | Minimum | Median | Maximum |
| --- | --- | --- | --- |
| slope | 0.101 | 0.157 | 0.269 |
| eff | 0.301 | 0.371 | 0.641 |
| disp | 0.023 | 0.230 | 0.960 |
| equil | 0.802 | 1.359 | 4.622 |

## Otherwise impulse-qualified displacement

Rows: 10; minimum: 0.064; median: 0.257; maximum: 0.854

## Value-return movement diagnostics

| Diagnostic | Rows | Share of diagnostic rows |
| --- | --- | --- |
| moving_toward | 8 | 14.8% |
| not_moving_toward | 46 | 85.2% |
| crossed_into_value | 0 | 0.0% |
| near_value_but_departing | 0 | 0.0% |


Progress distribution: minimum -0.844, median -0.145, maximum 0.471.

## Observational lifecycle phases

| Phase | Rows | Median phase bars | Maximum phase bars |
| --- | --- | --- | --- |
| invalidated | 166 | 0.0 | 0 |
| idle | 104 | 0.0 | 0 |
| impulse | 30 | 0.0 | 4 |
| retracing | 2 | 1.0 | 1 |
| resume_candidate | 2 | 2.0 | 2 |

## Observational impulse seeds

| Seed source | Rows | Median span ATR | Maximum span ATR |
| --- | --- | --- | --- |
| none | 104 | n/a | n/a |
| tp_specific | 104 | 0.915 | 1.500 |
| structural | 96 | 0.006 | 0.006 |

## Failure combinations

| Combination | Rows |
| --- | --- |
| slope + impulse_efficiency + impulse_displacement + pullback_returning | 34 |
| impulse_displacement + pullback_returning | 10 |
| slope + impulse_displacement + pullback_returning | 8 |
| impulse_efficiency + impulse_displacement + pullback_returning | 2 |

## State and failure combination

| State | Combination | Rows |
| --- | --- | --- |
| STRUCTURE_BALANCED | slope + impulse_efficiency + impulse_displacement + pullback_returning | 16 |
| STRUCTURE_EXHAUSTION | slope + impulse_efficiency + impulse_displacement + pullback_returning | 10 |
| STRUCTURE_FAILED_BREAKOUT | slope + impulse_efficiency + impulse_displacement + pullback_returning | 8 |
| STRUCTURE_BALANCED | impulse_displacement + pullback_returning | 8 |
| STRUCTURE_BREAKOUT_ATTEMPT | slope + impulse_displacement + pullback_returning | 4 |
| STRUCTURE_BALANCED | slope + impulse_displacement + pullback_returning | 4 |
| STRUCTURE_BALANCED | impulse_efficiency + impulse_displacement + pullback_returning | 2 |
| STRUCTURE_BREAKOUT_ATTEMPT | impulse_displacement + pullback_returning | 2 |
