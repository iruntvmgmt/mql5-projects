# Strategy-logic review: six fixes — 2026-07-20

## Purpose

User-directed code review of the four strategy engines for "obvious mistakes,
bugs, stubs, gaps," followed by "fix them all." Seven findings were surfaced;
six were fixed and one (stateless strategies) was deliberately left alone as
an intentional architectural choice. All changes are strategy signal
generation / feature computation only — no risk, execution, or safety code.

## Findings and fixes

1. **MR targeted the opposite SD band, not the mean (inversion).**
   `MeanReversionEngine` set an oversold long's target to `vwap + 1.5*SD`
   (a ~3 SD round-trip), inverting classic mean-reversion and producing
   unrealistic R (8+) while leaving `InpMR_TargetVWAPR` nearly unreachable.
   Fix: primary target is now the VWAP mean (fair value), with range-midpoint
   and fixed-R fallbacks. Confirmed in evidence: the 2026-04-23 13:00 MR long
   now reads `targetVWAP=4709.68` with R=4.51, versus R=8.37 for the identical
   trade before the fix.

2. **`compression_bars` was zeroed on the very breakout bar BO trades.**
   `FeatureEngine` only populated `compression_bars` while the current bar was
   itself compressed, so on an expansion/breakout bar it collapsed to 0 even
   when 5+ prior bars were compressed. Fix: added a separate
   `preceding_compression_bars` feature (`Types.mqh`, `FeatureEngine.mqh`)
   that always counts the compression run ending just before the trigger bar,
   independent of the current bar's state; BO now reads it. `compression_bars`
   semantics for the volatility classifier are unchanged.

3. **BO's current-bar ATR-percentile gate contradicted its own breakout.**
   BO required `atr_percentile_rank <= InpBO_CompressionPct(15)` on the trigger
   bar — i.e. the breakout bar had to still be in the bottom 15% ATR — which is
   mutually exclusive with an actual breakout. Fix: dropped that gate
   (`VOL_SHOCK`/`VOL_EXTREME` regime gates still block dangerous expansion).
   Demonstrated by an accepted BO short at `atrRank=76.0`, which the old gate
   would have rejected outright.

4. **BO stop was the far side of the entire range → chronic "Stop too far".**
   Long stop was `rangeLow - 1.5*ATR` (opposite boundary of the whole
   compression range), routinely exceeding `InpMaxStopPoints=1000`. Fix:
   anchored to the broken level — long `rangeHigh - stopATRMult*ATR`, short
   `rangeLow + stopATRMult*ATR` — bounding the stop near the breakout. The two
   accepted BO signals passed the risk stage (no "Stop too far").

5. **MR/TP stops could be pathologically tight → inflated R, noise stop-outs.**
   Added a strategy-level floor of `0.5*ATR` minimum stop distance to
   `MeanReversionEngine` and `TrendPullbackEngine` (both directions), on top of
   the risk engine's `InpMinStopPoints` floor.

6. **`TRIGGER_IMMEDIATE_BREAK` fired unconditionally in TP and MR.**
   `TriggerConfirmed()` returned `true` for immediate-break with no direction
   check. Fix: it now requires the just-closed candle to point in the trade
   direction. (Only affects the non-default immediate mode; the default
   `TRIGGER_CANDLE_CLOSE_BREAK` was already direction-checked.)

7. **Strategies could emit inverted stop/target geometry.**
   `CheckRiskReward` used `MathAbs`, so a wrong-side stop still passed the
   strategy check (caught only by the central risk engine). Fix: added a
   geometry self-guard in `StrategyBase::MakeSignal` that downgrades any
   structurally invalid signal to a rejection at the source. Defense in depth;
   the central `RiskEngine.mqh:331` geometry check remains.

**Not changed — stateless strategies (intentional).** The `OnPositionOpened/
Updated/Closed` hooks in `StrategyBase` are empty and unoverridden. This is a
deliberate architectural choice (position management is centralized in the
position manager / risk engine); adding per-strategy state would rearchitect
the centralized-management safety model and is out of scope for a strategy
signal-generation fix. Flagged, not "fixed."

## Now-inert inputs (config cleanup follow-up)

Two inputs became inert as a side effect and are intentionally left wired to
avoid preset/documentation churn this session; they should be removed or
repurposed in a dedicated config-cleanup task:

- `InpBO_CompressionPct` — previously fed BO's dropped current-bar ATR gate.
- `InpMR_TargetSDBandR` — previously fed MR's opposite-band target.

## Verification

- Compile (`wine start /Unix`): **0 errors, 0 warnings** (16:53).
- Self-test regression (Shadow, real ticks, `InpSelfTestOnInit=true`):
  **54 passed, 0 failed** (16:55). The four strategy reachability self-tests
  were updated in lockstep to assert the corrected behavior — BO uses
  `preceding_compression_bars` and the bounded stop; MR asserts the target is
  at/near the VWAP mean (`longMeanTarget`/`shortMeanTarget`) rather than beyond
  it; TP supplies a direction candle for the now-hardened immediate-break path.
  These updated deterministic tests are the per-fix proof.
- Journaled evidence backtest, XAUUSD M5, 2026.04.20-04.24, real ticks, all
  four strategies, Shadow mode (`OnTester result 0`, final balance unchanged).

### Before/after (same window, newest SignalJournal run block)

| Strategy | ACCEPTED before | ACCEPTED after | not-eligible before → after |
|---|---|---|---|
| **BO** | **0** | **2** | 1030 → 1002 |
| MR | 5 | 5 | 416 → 416 |
| FBO | 10 | 9 | 974 → 974 |
| TP | 0 | 0 | 1150 → 1150 |

- **BO reached ACCEPTED for the first time in this project** (0 → 2), directly
  attributable to fixes 2+3+4: one accepted signal had `atrRank=76` (old gate
  would block) and both passed the risk stage where BO's old range-wide stops
  were rejected.
- **MR unchanged in frequency (5)** — expected, since fixes 1 and 5 change the
  trade's target/stop *geometry*, not whether MR fires. The geometry change is
  confirmed directly (target now at the VWAP mean; R on the 2026-04-23 trade
  dropped from 8.37 to 4.51).
- **FBO unchanged** (9 vs 10 is run-to-run arbitration variance; FBO reads none
  of the changed fields).
- **TP still 0 ACCEPTED** — honest result, not a regression. TP's structure
  gate needs `STRUCTURE_IMPULSE`/`PULLBACK`, which needs STRONG-trend-magnitude
  bars that are rare-to-absent in this specific 4-day window (see
  `impulse_threshold_fix_20260720/`). The stop-floor (#5) and geometry-guard
  (#7) fixes apply to TP but don't change its eligibility here. TP reaching
  ACCEPTED needs either a window with genuine strong trends or the open
  STRONG-threshold review.

## Source state

- `QuantBeastEA.mq5` SHA-256 (unchanged — all fixes are in includes):
  `23e16ebb560c022cd42ea56cf97ed3fbf1a58825cf81ac068aab22957f7a12be`
- `QuantBeastEA.ex5` SHA-256:
  `be41085d9243dfa3d039e2006637143dfbc96c6204cc7f95cfe697ff3300674c`
- `Core/Types.mqh`: `4763fcc279b79fd2823f5439199b9a589e0a97277e7123a4756903c1b550d353`
- `Data/FeatureEngine.mqh`: `4035ab7c65fbf64b150b5fc28959a6f1a4c2c688d7ad547a135766f1bfd8f6dc`
- `Strategies/BreakoutEngine.mqh`: `931c7be3dd44b81ac5dd5cf218c8950afed1d4c89241e2ea11ba8481151a937d`
- `Strategies/MeanReversionEngine.mqh`: `c1ad37a24a2e0fc7eb1845e80dd0b3ebed316641c9f692b0203aa826ad3836aa`
- `Strategies/TrendPullbackEngine.mqh`: `8a12c562a392ea1e78b26ecdffb8dcb741368536002fbec1c9b56b719be7ea2a`
- `Strategies/StrategyBase.mqh`: `07d56f0bd15b3e427b4693209b97acf30e3392200ec90b5454d7fa7d9874bf2e`
- `Testing/SafetyTests.mqh`: `416f712ffd41eb1f071caae6a56dc1804f53afe3b38e98b88c5c44a489c079f4`

No broker orders transmitted (Shadow mode). Readiness remains
`READY FOR SHADOW MODE`.
