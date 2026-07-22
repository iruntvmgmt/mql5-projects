# QuantBeast acceptance funnel

Input journals: 1
Offset-scoped inputs: 1
End-bounded inputs: 1
Signal rows analyzed: 1216

| Strategy | Rows | Strategy | Arbitration | Risk/stop | Sizing | Broker | Accepted | Other |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO | 304 | 304 | 0 | 0 | 0 | 0 | 0 | 0 |
| FBO | 304 | 290 | 4 | 7 | 0 | 0 | 3 | 0 |
| MR | 304 | 303 | 0 | 1 | 0 | 0 | 0 | 0 |
| TP | 304 | 304 | 0 | 0 | 0 | 0 | 0 | 0 |

## Risk/stop detail

| Strategy | Risk/stop rejects | With geometry | Mean price distance | Top risk/stop reason | Count |
| --- | --- | --- | --- | --- | --- |
| BO | 0 | 0 | n/a |  | 0 |
| FBO | 7 | 7 | 16.19857 | Risk: Stop too far: 1138.0 > 1000 | 1 |
| MR | 1 | 1 | 10.06000 | Risk: Stop too far: 1006.0 > 1000 | 1 |
| TP | 0 | 0 | n/a |  | 0 |

## Risk/stop rejection categories

| Strategy | Category | Count |
| --- | --- | --- |
| FBO | stop_too_far | 7 |
| MR | stop_too_far | 1 |

## Strategy rejection categories

| Strategy | Category | Count |
| --- | --- | --- |
| BO | compression | 250 |
| BO | htf_alignment | 20 |
| BO | htf_direction | 17 |
| BO | setup_location | 14 |
| BO | trigger | 3 |
| FBO | failed_breakout_or_reclaim | 252 |
| FBO | directional_setup | 25 |
| FBO | reclaim_depth | 9 |
| FBO | reward_risk | 3 |
| FBO | reclaim | 1 |
| MR | vwap_deviation | 192 |
| MR | balanced_structure | 86 |
| MR | rejection_wick | 12 |
| MR | volatility | 6 |
| MR | trend_strength | 4 |
| MR | trigger | 3 |
| TP | directional_trend | 248 |
| TP | impulse_pullback_structure | 54 |
| TP | directional_setup | 1 |
| TP | pullback_depth | 1 |

## Interpretation boundary

Inputs without byte bounds may contain overlapping combined and isolated strategy runs. Start-and-end-bounded inputs contain only rows within the recorded run slice.

This report starts at emitted strategy decisions. Tick/data-quality preflight blocks occur before journal emission and must be measured from the matching tester-agent log. Do not infer that absent journal rows are strategy or risk rejections.
