# TP production rejection-path attribution -- 20260620

Events: 1

## TP_1782249000_down_1782250800 (2026.06.23 21:40:00)

| Eval | RegimeTrend | RegimeVol | Session | Spread | DirEff | Slope | Displacement | Returning | PullbackDepth | HTF | Trigger |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BUY | 3 | 0 | 7 | 21.0 | 0.423 | 0.273 | 0.520 | no | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |
| SELL | 3 | 0 | 7 | 21.0 | 0.423 | 0.273 | 0.520 | no | not observed (rejected upstream) | not observed (rejected upstream) | not observed (rejected upstream) |

- Nominated lifecycle direction: **down**
- First production rejection reason (BUY): TP eligibility: structure not impulse/pullback state=STRUCTURE_BALANCED slope=0.273 dirEff=0.423 displacement=0.520 equilibrium=2.933 returning=no movingToward=no valueProgress=-0.526 crossedValue=no
- First production rejection reason (SELL): TP eligibility: structure not impulse/pullback state=STRUCTURE_BALANCED slope=0.273 dirEff=0.423 displacement=0.520 equilibrium=2.933 returning=no movingToward=no valueProgress=-0.526 crossedValue=no
- Geometry constructible (BUY): not computed (rejected upstream of geometry)
- Geometry constructible (SELL): not computed (rejected upstream of geometry)

## Summary -- rejection reason on the side matching the nominated direction

| EventID | Nominated direction | First rejection reason | Geometry |
| --- | --- | --- | --- |
| TP_1782249000_down_1782250800 | down | TP eligibility: structure not impulse/pullback state=STRUCTURE_BALANCED slope=0.273 dirEff=0.423 displacement=0.520 equilibrium=2.933 returning=no movingToward=no valueProgress=-0.526 crossedValue=no | not computed (rejected upstream of geometry) |
