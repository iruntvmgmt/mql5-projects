# QuantBeast acceptance funnel

Input journals: 1
Offset-scoped inputs: 1
Signal rows analyzed: 3520

| Strategy | Rows | Strategy | Arbitration | Risk/stop | Sizing | Broker | Accepted | Other |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO | 880 | 880 | 0 | 0 | 0 | 0 | 0 | 0 |
| FBO | 880 | 844 | 8 | 4 | 0 | 0 | 24 | 0 |
| MR | 880 | 872 | 6 | 0 | 0 | 0 | 2 | 0 |
| TP | 880 | 880 | 0 | 0 | 0 | 0 | 0 | 0 |

## Risk/stop detail

| Strategy | Risk/stop rejects | With geometry | Mean price distance | Top risk/stop reason | Count |
| --- | --- | --- | --- | --- | --- |
| BO | 0 | 0 | n/a |  | 0 |
| FBO | 4 | 4 | 13.98500 | Risk: Stop too far: 1212.0 > 1000 | 2 |
| MR | 0 | 0 | n/a |  | 0 |
| TP | 0 | 0 | n/a |  | 0 |

## Risk/stop rejection categories

| Strategy | Category | Count |
| --- | --- | --- |
| FBO | stop_too_far | 4 |

## Interpretation boundary

Inputs without byte offsets may contain overlapping combined and isolated strategy runs. Offset-scoped inputs contain only rows appended after the recorded boundary.

This report starts at emitted strategy decisions. Tick/data-quality preflight blocks occur before journal emission and must be measured from the matching tester-agent log. Do not infer that absent journal rows are strategy or risk rejections.
