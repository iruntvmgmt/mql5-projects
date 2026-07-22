# QuantBeast acceptance funnel

Input journals: 11
Signal rows analyzed: 17808

| Strategy | Rows | Strategy | Arbitration | Risk/stop | Sizing | Broker | Accepted | Other |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO | 4452 | 4426 | 1 | 25 | 0 | 0 | 0 | 0 |
| FBO | 4452 | 4375 | 8 | 36 | 0 | 0 | 33 | 0 |
| MR | 4452 | 4452 | 0 | 0 | 0 | 0 | 0 | 0 |
| TP | 4452 | 4452 | 0 | 0 | 0 | 0 | 0 | 0 |

## Risk/stop detail

| Strategy | Risk/stop rejects | With geometry | Mean price distance | Top risk/stop reason | Count |
| --- | --- | --- | --- | --- | --- |
| BO | 25 | 25 | 29.01080 | Risk: Max consecutive losses: 5 | 3 |
| FBO | 36 | 36 | 13.48111 | Risk: Max consecutive losses: 5 | 9 |
| MR | 0 | 0 | n/a |  | 0 |
| TP | 0 | 0 | n/a |  | 0 |

## Risk/stop rejection categories

| Strategy | Category | Count |
| --- | --- | --- |
| BO | stop_too_far | 22 |
| BO | consecutive_loss_lock | 3 |
| FBO | stop_too_far | 27 |
| FBO | consecutive_loss_lock | 9 |

## Interpretation boundary

Input journals may contain overlapping combined and isolated strategy runs. Counts describe gate incidence across the evidence package; they are not an independent-trade sample size.

This report starts at emitted strategy decisions. Tick/data-quality preflight blocks occur before journal emission and must be measured from the matching tester-agent log. Do not infer that absent journal rows are strategy or risk rejections.
