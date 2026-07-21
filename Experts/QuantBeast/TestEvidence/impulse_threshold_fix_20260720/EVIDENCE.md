# TP eligibility investigation, part 2: StructuralState IMPULSE/PULLBACK — 2026-07-20

## Purpose

Continuation of the user-authorized "BO/TP/MR parameter review" after the
`slope_norm` scale-bug fix (`TestEvidence/slope_norm_scale_fix_20260720/`)
closed MR's blocker but confirmed TP's own bottleneck was unrelated.
Initial framing (TP blocked by `dir_efficiency` averaging 0.233 against its
0.4 floor) was itself an artifact of measuring unconditionally across all
bars, including non-trending ones. This task re-measured conditioned on
already being in a `TrendState`-qualified trend, using the same
instrument-then-revert methodology as the `slope_norm` investigation.

## Investigation, round 1: conditioned dir_efficiency

Temporary counters added to `QuantBeastEA.mq5` (removed before commit each
time; every compile confirmed `0 errors, 0 warnings` and every revert
confirmed via source hash matching
`23e16ebb560c022cd42ea56cf97ed3fbf1a58825cf81ac068aab22957f7a12be`), run
over the same Apr 20-24 XAUUSD M5 real-tick window already in evidence.

```
DIAG2 bars=1100 trending=246 avgDirEffWhenTrending=0.4764
dirEffOK=166 persistOK=239 htfOK=124 structOK=0 allOK=0
```

Conditioned on trending, `dir_efficiency` averages 0.4764 — *above* TP's
0.4 floor, and 67.5% of trending bars clear it. **`dir_efficiency` is not
the bottleneck; the earlier unconditional 0.233 average was misleading.**
The real bottleneck: `structOK` (TP's requirement that
`regime.structure ∈ {IMPULSE, PULLBACK}`) is a hard **zero** across all 246
trending bars.

## Investigation, round 2: why structOK is zero

Further instrumentation broke down the raw structure distribution among
the same 246 trending bars:

```
DIAG3 trending=246 struct[BAL,BOATT,ACCBO,FBO,PB,IMP,EXH]=161,36,0,41,0,0,8
pullbackSlopeSub=59 pullbackDistEquilSub=234 pullbackReturningSub=4
avgDistEquil=-0.4219
```

65.4% of trending bars fall into the `BALANCED` (residual/default)
structure category despite `TrendState` independently classifying them as
trending — the two classifiers read overlapping features
(`slope_norm`, `dir_efficiency`) but apply inconsistent thresholds.
`IMPULSE` and `PULLBACK` are both zero. Breaking down PULLBACK's three
sub-conditions (`StructuralState.mqh`: `|slope_norm|>0.3 &&
|dist_from_equil|>0.5 && returning_to_value`) isolates the blocker:
`returning_to_value` (`|norm_dist_vwap|<0.3`, i.e. "currently near VWAP")
holds on only 4/246 bars (1.6%), while the other two sub-conditions are
satisfied 24% and 95% of the time respectively. **This looks like correct,
narrow-by-design behavior, not a bug**: `TrendState` measures a sustained
directional state, while "returning to value" describes a brief instant —
price actively trending is usually moving *away* from VWAP, not sitting
near it. PULLBACK's rarity was not touched by any fix in this task.

IMPULSE's own definition (`|slope_norm|>0.75 && dir_efficiency>0.55 &&
displacement>1.0`) requires a higher slope bar (0.75) than `TrendState`'s
own STRONG threshold (0.6, `TrendState.mqh`) and a higher `dir_efficiency`
bar (0.55) than TP's own floor (0.4) — a bar `TrendState` calls STRONG
could never also qualify as IMPULSE. This looked like a genuine,
fixable miscalibration.

## Fix applied (user-approved: "loosen IMPULSE only")

`Include/QuantBeast/Regime/StructuralState.mqh`, IMPULSE thresholds lowered
to align with `TrendState`'s STRONG bar and TP's own `dir_efficiency`
floor:

```cpp
// was: MathAbs(feat.slope_norm) > 0.75 && feat.dir_efficiency > 0.55 && feat.displacement > 1.0
if(MathAbs(feat.slope_norm) > 0.6 && feat.dir_efficiency > 0.4 && feat.displacement > 1.0)
```

PULLBACK left untouched (its rarity is by-design, not a defect).

- Compile: `0 errors, 0 warnings`.
  - `StructuralState.mqh` SHA-256:
    `d6b27ba7c9028814996e84f9a868056aa68a2dee51787a1ce02d2b895cd02ac0`
  - `QuantBeastEA.ex5` SHA-256:
    `a8b8b717335428f536b545f4a6bc990f6c01e93308acacf46a74c77d22a967d7`
- Self-test regression (1-day Shadow, real ticks): **54 passed, 0 failed**
  — no regression.

## Result: the fix is real but insufficient in this window, and why

A full journaled Apr 20-24 rerun after the fix showed **TP unchanged**:
still 1150/1150 (100%) not-eligible, 0 ACCEPTED — identical to the
pre-fix run. BO, MR, and FBO were also unchanged (confirming no
regression: BO 1030/1150 not-eligible/0 accepted, MR 416/1150/5 accepted,
FBO 974/1150/10 accepted, all matching the prior `slope_norm`-fix
baseline).

A follow-up diagnostic re-confirmed `structOK` was **still exactly 0/246**
even after the fix, and isolated why:

```
DIAG4 trending=246 structOK=0 allOK=0 slopeOK=0 dirEffOK=166
displacementOK=21 stolenByBreakout=36 avgDisplacement=0.4435
```

**`slopeOK` (`|slope_norm| > 0.6`) is itself zero across all 246 trending
bars in this window.** Since post-`slope_norm`-fix values are now correctly
scaled, no bar in this particular window reached the STRONG-trend magnitude
(0.6) at all — every trending bar here was `WEAK_UP`/`WEAK_DOWN`
(threshold 0.15), never `STRONG`. Aligning IMPULSE's slope bar with
`TrendState`'s STRONG threshold was internally consistent, but STRONG
itself may be rare-to-absent in a given short window, so the aligned
IMPULSE bar inherits that same rarity. `avgDisplacement=0.4435` (only
21/246 = 8.5% clearing 1.0) suggests `displacement>1.0` would likely have
been the *next* binding constraint even if slope were satisfied, and 36/246
(14.6%) trending bars never reach the IMPULSE/PULLBACK checks at all
because `StructuralState.Classify()`'s if/else ordering classifies them as
`BREAKOUT_ATTEMPT` first.

**This is not a failure of the fix** — the fix correctly removed an
internal inconsistency (IMPULSE stricter than the trend classification it
was meant to describe) and is verified working at the code level. It
simply wasn't sufficient, by itself, to produce a visible TP trade in this
one short (4-day) window, because reaching `STRONG` trend at all is rare
here, and `IsEligible()`'s remaining conditions (`displacement`,
`BREAKOUT_ATTEMPT` stealing 14.6% of candidates before the check is even
reached) still compound against it.

## Open questions for a future decision (not applied this task)

Per the user's standing "one at a time, confirm before changing" direction,
no further parameter change was made pending explicit sign-off:

1. Whether `TrendState`'s own STRONG threshold (0.6) is itself well
   calibrated post-`slope_norm`-fix, or whether it's now too strict given
   real-market slope magnitudes — this wasn't measured across enough
   windows to conclude either way (one 4-day sample showed zero STRONG
   bars, which alone doesn't prove STRONG is broken vs. genuinely rare that
   week).
2. Whether IMPULSE should require STRONG specifically, or whether a
   WEAK-trend-compatible impulse definition (lower slope bar, e.g. aligned
   with WEAK's 0.15 rather than STRONG's 0.6) would better match what TP is
   actually trying to capture ("a real trend has resumed/continued").
3. `displacement > 1.0` (a single-bar body/ATR ratio) was never
   individually reviewed for calibration — only 8.5% of trending bars
   clear it, and it may independently warrant its own investigation.
4. `StructuralState.Classify()`'s if/else ordering means any bar that
   qualifies for breakout/failed-breakout is never even evaluated for
   IMPULSE/PULLBACK — 14.6% of trending bars in this window fell into that
   category. Whether this ordering is intentional (breakout takes
   precedence) or an unintended side effect of classification order was not
   assessed.

## Scope discipline

No risk, execution, or safety code was touched. No trades were placed on a
live or demo broker (all backtests were Strategy Tester, Shadow mode, no
broker transmission). Every temporary diagnostic addition to
`QuantBeastEA.mq5` was reverted before this document was written, verified
by source-hash match each time. The one durable change from this task is
the single IMPULSE-threshold edit in `StructuralState.mqh`, explicitly
approved by the user before being applied.
