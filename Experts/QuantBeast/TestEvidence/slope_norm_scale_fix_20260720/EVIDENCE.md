# BO/TP/MR eligibility-gate investigation: slope_norm scale bug — 2026-07-20

## Purpose

User-authorized task: "BO/TP/MR parameter review" — investigate why BO, TP,
and MR have shown 88-100% "not eligible" rejections across every organic
window tested to date (see `organic_multiwindow_20260719/EVIDENCE.md`),
determine whether this is genuine miscalibration or correctly-modeled
rarity, and if a specific fix is identified, apply it through its own
compile + regression + evidence cycle. Explicitly scoped to strategy signal
generation only — no risk/execution/safety code touched.

## Investigation

Read `RegimeEngine.mqh`, all four regime classifiers (`TrendState`,
`VolatilityState`, `StructuralState`, `LiquidityState`), `FeatureEngine.mqh`,
`Configuration.mqh`, and each strategy's `IsEligible()`
(`BreakoutEngine`/`TrendPullbackEngine`/`MeanReversionEngine`/
`FailedBreakoutEngine`). Code reading alone produced an initial hypothesis:
that `VolatilityState`'s `VOL_EXPANSION` classification over-fires because
`compression_bars` defaults to 0 whenever the market isn't actively
compressing, making the `compression_bars < minExpansionBars` sub-condition
a near-tautology.

**This hypothesis was tested directly against real production code and
found wrong.** Rather than trust a hand-derived Python replication of the
feature math (error-prone, as this session's own earlier `atr_ratio`
estimate already demonstrated), temporary counters were added directly to
`QuantBeastEA.mq5` (globals near the state-tracking block, an increment
block in `OnTick()` right after `g_RegimeEngine.Classify()` gated on
`isNewBar && dataQualityOK`, and a summary print in `OnDeinit()`) to tally
the real `regime.structure`/`regime.volatility` distribution and
`slope_norm`/`dir_efficiency` statistics. Compiled clean (0 errors/0
warnings), ran over the same Apr 20-24 XAUUSD M5 real-tick window already
in evidence (`organic_multiwindow_20260719`), then the instrumentation was
fully reverted (confirmed via source hash matching the pre-instrumentation
value `23e16ebb560c022cd42ea56cf97ed3fbf1a58825cf81ac068aab22957f7a12be`
after revert + recompile) before any real fix was made.

Real measured distribution, 1100 bars:

```
struct[BAL,BOATT,ACCBO,FBO,PB,IMP,EXH] = 792,102,0,174,30,0,2   (BALANCED = 72%)
vol[COMP,NORM,EXP,EXTR,SHOCK]          = 209,614,85,186,6       (EXPANSION = only 7.7%)
avgSlopeNorm=-0.3368  avgAbsSlopeNorm=2.3526  avgDirEff=0.2332
slopeUnder025=67  slopeUnder025AndBalanced=47
```

`VOL_EXPANSION` is only 7.7% of bars — nowhere near dominant, refuting the
original hypothesis. `STRUCTURE_BALANCED` (MR's own structural requirement)
is common (72%). The real bottleneck: MR requires `|slope_norm| <= 0.25`,
satisfied on only **67 of 1100 bars (6%)** — by far the tightest constraint
of anything gating MR, well below the volatility (~75% pass) or structure
(72% pass) gates.

## Root cause

`FeatureEngine::CalcTrendFeatures()` computed:

```cpp
m_current.slope_norm = m_current.trend_slope * m_trendLookback / atrVal;
```

`trend_slope` is already a per-bar OLS regression slope. Multiplying by
`m_trendLookback` (20) converts it into total window displacement, then
dividing by a *single-bar* ATR produces a ratio naturally on the order of
several ATRs for almost any real price path — matching the measured average
magnitude of 2.35. But every consumer of `slope_norm` was calibrated
assuming a roughly `[-1, 1]` per-bar-normalized range: `Types.mqh`'s own
comment says "Slope normalized by ATR"; `TrendState` uses thresholds
0.15/0.3/0.6; `StructuralState` uses 0.2/0.3/0.75 and clamps
`1.0 - |slope_norm|` into `[0.3, 0.6]` (only sensible if `|slope_norm|` is
typically well under 1); `MeanReversionEngine` uses 0.25. This is a scale
bug in the shared feature, not a per-strategy threshold judgment call — it
likely also distorts `TrendState`'s own trend classification (near-every
bar with any drift would trivially clear the 0.6 "STRONG" bar against an
average magnitude of 2.35), though TP's own measured bottleneck is a
separate, correctly-scaled, genuinely-low `dir_efficiency` (avg 0.233 vs
its 0.4 floor) — a distinct, out-of-scope finding for a future task.

## Fix

`Include/QuantBeast/Data/FeatureEngine.mqh`:

```cpp
// Normalized slope: per-bar regression slope expressed in ATR units.
// (Previously multiplied by m_trendLookback too, which double-counted
// the window length -- trend_slope is already a per-bar rate...)
m_current.slope_norm = m_current.trend_slope / atrVal;
```

Removed the redundant `* m_trendLookback`. Single-line, single-purpose
change confined to shared feature computation — no strategy, risk, or
execution code touched.

## Verification

- Compile (`wine start /Unix` pattern): `0 errors, 0 warnings`.
  - `FeatureEngine.mqh` SHA-256:
    `b44b1bba9184bb2f4da6578fa7733eae605c3d720ef7218b008d6bc3e20bf763`
  - `QuantBeastEA.mq5` SHA-256 (unchanged by this fix):
    `23e16ebb560c022cd42ea56cf97ed3fbf1a58825cf81ac068aab22957f7a12be`
  - `QuantBeastEA.ex5` SHA-256:
    `98640830e41bedc7def7bf311a0f878b30eae439f9cdb41c69452481fb930439`
- Self-test regression (Shadow, `InpSelfTestOnInit=true`, XAUUSD M5,
  2026.04.20-2026.04.21, real ticks): **54 passed, 0 failed** — no
  regression in any existing self-test, including TEST 50/51 added earlier
  this session.

## Before/after evidence — closed

The native tester automation (`tester_run_backtest`) became unreliable
partway through this task, beyond the already-documented `job_id: 0` issue:
several resubmissions produced either no `metatester64` process at all, or
a process that ran for 60-90+ seconds without ever writing a new line to
`Tester/Agent-127.0.0.1-3000/logs/<date>.log` or a new row to
`SignalJournal.csv` (confirmed via file-size and mtime checks, not just
process presence, which was misleading earlier in this task). Per user
direction the fix was initially accepted on code-level evidence and the
54/0 self-test regression alone. The automation subsequently recovered on
its own (no environment change made), and a clean, journal-enabled,
self-tests-disabled Apr 20-24 rerun completed normally
(`final balance ... test passed`, log grew from 524306 to 578218 bytes),
producing the following confirmed before/after comparison (same window,
same code path, only the `slope_norm` fix differs):

| Strategy | Not-eligible (pre-fix) | Not-eligible (post-fix) | Past-eligibility (pre→post) | ACCEPTED (pre→post) |
|---|---|---|---|---|
| BO  | 1030/1150 (89.6%) | 1030/1150 (89.6%, unchanged) | 120→120 | 0→0 |
| MR  | 1100/1150 (95.7%) | **416/1150 (36.2%)** | 50→**729** | **0→5** |
| TP  | 1148/1150 (99.8%) | 1150/1150 (100%, unchanged) | 2→0 | 0→0 |
| FBO | 974/1150 (84.7%)  | 974/1150 (84.7%, unchanged) | 166→166 | 10→10 |

BO and FBO are unchanged, as expected — neither strategy's `IsEligible()`
reads `slope_norm` at all (confirmed in the source: BO gates on
compression/ATR-percentile/spread/event/volatility/HTF-bias only; FBO gates
on the `failed_breakout`/`reclaim_detected` event flags only). **MR is the
strategy whose eligibility gate directly reads `slope_norm`
(`|slope_norm| <= InpMR_MaxTrendStrength`), and it shows the fix working
exactly as diagnosed**: not-eligible dropped from 95.7% to 36.2%, and MR
produced its first-ever ACCEPTED signals in any window tested this
project — 5 real trades:

```
2026.04.20 16:40:00  MR SELL  dev=1.56sd wick=0.56  entry=4818.49 sl=4826.32 tp=4787.21
2026.04.21 15:05:00  MR SELL  dev=1.84sd wick=0.45  entry=4793.39 sl=4797.92 tp=4780.18
2026.04.22 17:55:00  MR BUY   dev=-1.59sd wick=0.77 entry=4737.68 sl=4729.85 tp=4758.40
2026.04.22 18:25:00  MR BUY   dev=-1.68sd wick=0.39 entry=4734.20 sl=4729.80 tp=4756.88
2026.04.23 13:00:00  MR BUY   dev=-1.73sd wick=0.35 entry=4697.41 sl=4694.69 tp=4720.17
```

The first of these (2026.04.20 16:40:00) is the exact same bar where an
earlier same-day 1-day Shadow run with `InpSelfTestOnInit=true` had shown a
live `SHADOW: MR ORDER_TYPE_SELL` trade. That earlier observation had been
flagged as unreliable (possible self-test-process contamination); this
clean, self-tests-disabled, independently-run rerun reproduces the exact
same trade, confirming it was genuine and not an artifact.

TP is unaffected (still 100% not-eligible, 0 ACCEPTED), confirming the
earlier finding that TP's bottleneck is its own `dir_efficiency` gate, not
`slope_norm` — a separate, still-open item. Whether `TrendState`'s own
classification was distorted by the pre-fix scale bug remains unmeasured
and is a candidate for a future task.

## Scope discipline

No risk, execution, or safety code was touched. No trades were placed on a
live or demo broker in this task (all backtests were Strategy Tester,
Shadow mode, no broker transmission). `HANDOFF.md` and
`KNOWN_LIMITATIONS.md` updated accordingly.
