# TP production rejection-path attribution -- 20260126

Events: 3

## TP_1769462400_down_1769463600 (2026.01.26 21:40:00)

| Eval | RegimeTrend | RegimeVol | Session | Spread | DirEff | Slope | Displacement | Returning | PullbackDepth | HTF | Trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BUY | 3 | 1 | 7 | 19.0 | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |
| SELL | 3 | 1 | 7 | 19.0 | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |

- Nominated lifecycle direction: **down**
- First production rejection reason (BUY): TP eligibility: directional efficiency 0.34 below 0.40
- First production rejection reason (SELL): TP eligibility: directional efficiency 0.34 below 0.40
- Geometry constructible (BUY): not computed (rejected upstream of geometry)
- Geometry constructible (SELL): not computed (rejected upstream of geometry)

## TP_1769587200_up_1769588100 (2026.01.28 08:15:00)

| Eval | RegimeTrend | RegimeVol | Session | Spread | DirEff | Slope | Displacement | Returning | PullbackDepth | HTF | Trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BUY | 1 | 1 | 2 | 19.0 | 0.424 | 0.180 | 0.668 | no | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |
| SELL | 1 | 1 | 2 | 19.0 | 0.424 | 0.180 | 0.668 | no | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |

- Nominated lifecycle direction: **up**
- First production rejection reason (BUY): TP eligibility: structure not impulse/pullback state=STRUCTURE_BALANCED slope=0.180 dirEff=0.424 displacement=0.668 equilibrium=1.132 returning=no movingToward=no valueProgress=-0.514 crossedValue=no
- First production rejection reason (SELL): TP eligibility: structure not impulse/pullback state=STRUCTURE_BALANCED slope=0.180 dirEff=0.424 displacement=0.668 equilibrium=1.132 returning=no movingToward=no valueProgress=-0.514 crossedValue=no
- Geometry constructible (BUY): not computed (rejected upstream of geometry)
- Geometry constructible (SELL): not computed (rejected upstream of geometry)

## TP_1769681100_down_1769682900 (2026.01.29 10:35:00)

| Eval | RegimeTrend | RegimeVol | Session | Spread | DirEff | Slope | Displacement | Returning | PullbackDepth | HTF | Trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BUY | 3 | 1 | 3 | 13.0 | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |
| SELL | 3 | 1 | 3 | 13.0 | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |

- Nominated lifecycle direction: **down**
- First production rejection reason (BUY): TP eligibility: directional efficiency 0.33 below 0.40
- First production rejection reason (SELL): TP eligibility: directional efficiency 0.33 below 0.40
- Geometry constructible (BUY): not computed (rejected upstream of geometry)
- Geometry constructible (SELL): not computed (rejected upstream of geometry)

## Summary -- rejection reason on the side matching the nominated direction

| EventID | Nominated direction | First rejection reason | Geometry |
| --- | --- | --- | --- |
| TP_1769462400_down_1769463600 | down | TP eligibility: directional efficiency 0.34 below 0.40 | not computed (rejected upstream of geometry) |
| TP_1769587200_up_1769588100 | up | TP eligibility: structure not impulse/pullback state=STRUCTURE_BALANCED slope=0.180 dirEff=0.424 displacement=0.668 equilibrium=1.132 returning=no movingToward=no valueProgress=-0.514 crossedValue=no | not computed (rejected upstream of geometry) |
| TP_1769681100_down_1769682900 | down | TP eligibility: directional efficiency 0.33 below 0.40 | not computed (rejected upstream of geometry) |
