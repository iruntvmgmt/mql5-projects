# QuantBeast acceptance funnel

Input journals: 1
Offset-scoped inputs: 1
End-bounded inputs: 0
Signal rows analyzed: 880

| Strategy | Rows | Strategy | Arbitration | Risk/stop | Sizing | Broker | Accepted | Other |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO | 220 | 220 | 0 | 0 | 0 | 0 | 0 | 0 |
| FBO | 220 | 211 | 2 | 0 | 0 | 0 | 7 | 0 |
| MR | 220 | 218 | 2 | 0 | 0 | 0 | 0 | 0 |
| TP | 220 | 220 | 0 | 0 | 0 | 0 | 0 | 0 |

## Risk/stop detail

| Strategy | Risk/stop rejects | With geometry | Mean price distance | Top risk/stop reason | Count |
| --- | --- | --- | --- | --- | --- |
| BO | 0 | 0 | n/a |  | 0 |
| FBO | 0 | 0 | n/a |  | 0 |
| MR | 0 | 0 | n/a |  | 0 |
| TP | 0 | 0 | n/a |  | 0 |

## Risk/stop rejection categories

No risk/stop rejections.

## Interpretation boundary

Inputs without byte bounds may contain overlapping combined and isolated strategy runs. Start-and-end-bounded inputs contain only rows within the recorded run slice.

This report starts at emitted strategy decisions. Tick/data-quality preflight blocks occur before journal emission and must be measured from the matching tester-agent log. Do not infer that absent journal rows are strategy or risk rejections.
