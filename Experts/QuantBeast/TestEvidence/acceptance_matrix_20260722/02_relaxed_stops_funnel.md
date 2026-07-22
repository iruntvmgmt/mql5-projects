# QuantBeast acceptance funnel

Input journals: 1
Offset-scoped inputs: 1
Signal rows analyzed: 2640

| Strategy | Rows | Strategy | Arbitration | Risk/stop | Sizing | Broker | Accepted | Other |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO | 660 | 660 | 0 | 0 | 0 | 0 | 0 | 0 |
| FBO | 660 | 633 | 6 | 2 | 0 | 0 | 19 | 0 |
| MR | 660 | 654 | 5 | 0 | 0 | 0 | 1 | 0 |
| TP | 660 | 660 | 0 | 0 | 0 | 0 | 0 | 0 |

## Risk/stop detail

| Strategy | Risk/stop rejects | With geometry | Mean price distance | Top risk/stop reason | Count |
| --- | --- | --- | --- | --- | --- |
| BO | 0 | 0 | n/a |  | 0 |
| FBO | 2 | 2 | 13.98500 | Risk: Stop too far: 1212.0 > 1000 | 1 |
| MR | 0 | 0 | n/a |  | 0 |
| TP | 0 | 0 | n/a |  | 0 |

## Risk/stop rejection categories

| Strategy | Category | Count |
| --- | --- | --- |
| FBO | stop_too_far | 2 |

## Interpretation boundary

Inputs without byte offsets may contain overlapping combined and isolated strategy runs. Offset-scoped inputs contain only rows appended after the recorded boundary.

This report starts at emitted strategy decisions. Tick/data-quality preflight blocks occur before journal emission and must be measured from the matching tester-agent log. Do not infer that absent journal rows are strategy or risk rejections.
