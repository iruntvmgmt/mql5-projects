# XAUUSD Scalper — V6 CRSI Prestige Regime + Pullback

## Strategy: CRSI-Driven Regime Classification + Pullback Continuation

Uses the CRSI_Prestige_Strategy indicator (TradingView port) as the primary signal engine.

## CRSI Buffer Map (iCustom Indexes)

| Index | Variable | Type | Description | Used In EA |
|---|---|---|---|---|
| 0 | g_crsi | DRAW_LINE | Main CRSI oscillator (0-100) | Regime, pullback, trigger |
| 1 | g_smoothCRSI | DRAW_LINE | Smoothed CRSI | Reference |
| 2 | g_dbCRSI | DRAW_LINE | Dynamic Low band | Band slope, range |
| 3 | g_ubCRSI | DRAW_LINE | Dynamic High band | Band slope, range |
| 4 | g_fib50 | DRAW_LINE | Fib 50% midline | Regime midline reference |
| 5 | g_fib618Up | DRAW_LINE | Fib 61.8% upper | Upper pullback zone |
| 6 | g_fib618Dn | DRAW_LINE | Fib 61.8% lower | Lower pullback zone |
| 12 | g_bbUpper | DRAW_LINE | BB Upper on CRSI | Reference |
| 13 | g_bbMiddle | DRAW_LINE | BB Middle (SMA of CRSI) | Reference |
| 14 | g_bbLower | DRAW_LINE | BB Lower on CRSI | Reference |
| 15 | g_buySig | DRAW_ARROW | Native Buy signal | Not used (informational) |
| 16 | g_sellSig | DRAW_ARROW | Native Sell signal | Not used (informational) |
| 17 | g_sqzMom | DRAW_HISTOGRAM | Squeeze momentum | Not used |
| 18 | g_sqzOn | DRAW_NONE | Squeeze state (1=squeezed) | Squeeze filter |
| 20 | g_priceNorm | DRAW_LINE | Normalized price trend | Regime confirmation |

## Regime Rules

**Bullish** (all must hold):
- CRSI > InpRegimeBullCRSI (default 55)
- PriceNorm > InpRegimePriceNormHi (default 55) — price above midpoint
- Dynamic High band not declining (or squeeze off)

**Bearish** (all must hold):
- CRSI < InpRegimeBearCRSI (default 45)
- PriceNorm < InpRegimePriceNormLo (default 45) — price below midpoint
- Dynamic Low band not rising (or squeeze off)

**Neutral**: skip trading

## Pullback + Trigger

**LONG**: Regime bullish, CRSI(bar-2) dipped below InpPullbackLongZone (35), CRSI(bar-1) reclaims above InpTriggerReclaim (50) AND above Fib50

**SHORT**: Regime bearish, CRSI(bar-2) rallied above InpPullbackShortZone (65), CRSI(bar-1) drops below InpTriggerReclaim (50) AND below Fib50

## Exit Management

| Exit | Rule |
|---|---|
| Stop Loss | max(1.25× ATR, swing ± 0.15× ATR buffer) |
| Take Profit | 2.0R |
| Breakeven | SL → entry at +1R |
| Trailing Stop | After +1.25R, trail at 1.0× ATR |

## Key Inputs

| Input | Default | Purpose |
|---|---|---|
| InpCRSIPath | Tradingview_Indicators\CRSI\CRSI_Prestige_Strategy | Indicator path |
| InpRegimeBullCRSI | 55 | CRSI above = bullish bias |
| InpRegimeBearCRSI | 45 | CRSI below = bearish bias |
| InpPullbackLongZone | 35 | CRSI must dip below for long pullback |
| InpPullbackShortZone | 65 | CRSI must rise above for short pullback |
| InpTriggerReclaim | 50 | CRSI must reclaim past this |
| InpRiskPct | 1.5 | % equity per trade |

## Assumptions

- CRSI indicator must be compiled and present at the specified path
- iCustom loads 21 buffers — buffer indexes are hardcoded per the indicator source
- If the indicator is recompiled with different buffer ordering, update the EA macros
- Default CRSI params (DomCycle=20, Leveling=10, SmoothLen=3) used unless overridden

## Compilation

Compile in MetaEditor: open XAUUSD_Scalper.mq5, press F7.

Requires: CRSI_Prestige_Strategy.ex5 in Indicators/Tradingview_Indicators/CRSI/
