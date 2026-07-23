# TP production rejection-path attribution -- 20260504

Events: 1

## TP_1777920600_down_1777921800 (2026.05.04 19:10:00)

| Eval | RegimeTrend | RegimeVol | Session | Spread | DirEff | Slope | Displacement | Returning | PullbackDepth | HTF | Trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BUY | 3 | 1 | 7 | 12.0 | 0.561 | 0.254 | 0.854 | no | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |
| SELL | 3 | 1 | 7 | 12.0 | 0.561 | 0.254 | 0.854 | no | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |

- Nominated lifecycle direction: **down**
- First production rejection reason (BUY): TP eligibility: structure not impulse/pullback state=STRUCTURE_BREAKOUT_ATTEMPT slope=0.254 dirEff=0.561 displacement=0.854 equilibrium=2.535 returning=no movingToward=no valueProgress=-0.683 crossedValue=no
- First production rejection reason (SELL): TP eligibility: structure not impulse/pullback state=STRUCTURE_BREAKOUT_ATTEMPT slope=0.254 dirEff=0.561 displacement=0.854 equilibrium=2.535 returning=no movingToward=no valueProgress=-0.683 crossedValue=no
- Geometry constructible (BUY): not computed (rejected upstream of geometry)
- Geometry constructible (SELL): not computed (rejected upstream of geometry)

## Summary -- rejection reason on the side matching the nominated direction

| EventID | Nominated direction | First rejection reason | Geometry |
| --- | --- | --- | --- |
| TP_1777920600_down_1777921800 | down | TP eligibility: structure not impulse/pullback state=STRUCTURE_BREAKOUT_ATTEMPT slope=0.254 dirEff=0.561 displacement=0.854 equilibrium=2.535 returning=no movingToward=no valueProgress=-0.683 crossedValue=no | not computed (rejected upstream of geometry) |
