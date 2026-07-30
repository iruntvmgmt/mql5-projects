# D031 — Six-Family Shadow-Candidate Architecture

Phase 2 of the D030–D035 six-family shadow research program (see
`D030_D035_Six_Family_Claude_Handoff.md`). Scope: implement all six
families as deterministic, non-executing shadow candidate generators.
**No standalone performance screening (D032) was run.** No FastMedConfluence,
SweepReclaim, P4 exit logic, or `OWN_FAMILY_OPPOSITE` behavior was touched.

Branch: `feature/d030-six-family-shadow-research`, continuing from D030
(`9b603927dd812224a677a444403744f04948a543`).

## Governing D030 findings (context, not re-litigated here)

`market_phase=TREND_CONTINUATION` and `alignment_state=FULLY_ALIGNED` are
two views of the same structural gap, not independent evidence — treated
that way throughout: Momentum Continuation and Trend Pullback both target
it, and neither's priority is double-counted on the strength of two labels
for one phenomenon. `OWN_FAMILY_OPPOSITE` and any existing-book exit
question is out of scope for this program. Range Rotation does not depend
on `MSZZ_PHASE_RANGE` (confirmed never firing in D030's 98,943-bar census)
— see "Range Rotation's independent detector" below.

## ID allocation

Full inspection and every existing/new ID: `Tools/D031/id_allocation.csv`.

Inspected `Include/MultiSpeedZigZag/Core/Types.mqh` before allocating
anything. Existing production `ENUM_MSZZ_STRATEGY_ID` uses 1001-1080;
`ENUM_MSZZ_STRATEGY_FAMILY` uses 0-7. **The handoff's own suggested IDs
collide**: `1060` (Session Sweep Reversal) collides with the existing
`1060 = Compression Breakout (D027 S4)`; `1070` (Momentum Continuation)
collides with the existing `1070 = Structure Transition`; `1080`
(Break-Retest Continuation) collides with the existing `1080 = Weighted
Ensemble`. Only three of the handoff's six suggested IDs (1090/1100/1110)
were actually free. Rather than cherry-pick the three survivors, D031
allocates a fresh, unambiguous, non-colliding block:

| Strategy ID | Family | Family ID |
|---:|---|---:|
| 1200 | Session Sweep Reversal | 8 |
| 1201 | Momentum Continuation | 9 |
| 1202 | Break-Retest Continuation | 10 |
| 1203 | Compression Breakout (Research) | 11 |
| 1204 | Trend Pullback | 12 |
| 1205 | Range Rotation | 13 |

**Existing strategy `1060` (D027 S4 Compression Breakout) was not renamed,
reused, or modified.** `Include/MultiSpeedZigZag/Strategies/D027StrategyFamilies.mqh`
and `Core/Types.mqh` are untouched by D031.

These IDs are `#define` integer constants in
`Include/MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh`,
**not** new values added to the production `ENUM_MSZZ_STRATEGY_ID`/
`ENUM_MSZZ_STRATEGY_FAMILY` enums — see "Architecture" below for why.

## Architecture

### Why a disjoint candidate type, not `MSZZCandidate`

`MSZZCandidate` (`Core/Types.mqh`) is the type the LIVE execution path
requires: `StrategySuite`/`D027StrategyFamilies` → `CandidateHandoff` →
`OpportunityClusterEngine` → `ExecuteCluster` → `StrategyBook` → broker.
Reusing it for shadow research candidates would create exactly the kind
of coupling the handoff's isolation requirements ("no execution intents",
"shadow mode cannot reach execution") exist to prevent — a research
candidate could, by construction, be handed to
`CMSZZCandidateHandoff::Append()` and flow into a live cluster.

D031 instead defines `MSZZResearchCandidate`
(`Research/Families/ResearchCandidateTypes.mqh`) — a disjoint struct with
every field the handoff's shared candidate interface + research metadata
sections require (`strategy_id, family_id, setup_name, signal_time,
expiry_time, direction, entry, stop, target, score, origin_id, event_id,
reason, valid, canonical_variant_id, hypothesis_version, regime_id,
session_id, reference_level_type, structural_context,
stop_distance_points, target_r, spread_to_risk_ratio`), using plain `int`
for `strategy_id`/`family_id` rather than the production enums. This makes
"pass a research candidate into the execution pipeline" a compile error,
not just a convention.

All six families and the aggregator route every emission through one of
two shared, deterministic factory methods
(`CMSZZResearchCandidateFactory::Emit` / `::EmitWithExplicitTarget`) that
enforce identical geometry invariants everywhere (non-null keys, correct
stop side, `entry != stop`) — the same one-choke-point pattern
`D027StrategyFamilies.mqh`'s own `Emit()` already uses one layer up.

### Layout

```text
Include/MultiSpeedZigZag/Research/Families/
  ResearchCandidateTypes.mqh       -- shared struct, IDs, factory
  SessionSweepReversal.mqh         -- Family 1, priority 3
  MomentumContinuation.mqh         -- Family 2, priority 1
  BreakRetestContinuation.mqh      -- Family 3, priority 4
  CompressionBreakoutResearch.mqh  -- Family 4, priority 5
  TrendPullback.mqh                -- Family 5, priority 2
  RangeRotation.mqh                -- Family 6, priority 6
Include/MultiSpeedZigZag/Research/
  SixFamilyResearchSuite.mqh       -- aggregator, one shared journal
```

Six separate `.mqh` files, not one giant function, per the handoff.

### Safety contract and how it's verified

`SixFamilyResearchSuite.mqh` never calls a trade function, never includes
anything under `Execution/*` or `Portfolio/*`, and never constructs an
`MSZZCandidate`. Verified by static grep audit (reproducible commands and
results in `Tools/D031/shadow_safety_audit.md`) rather than assumed.

EA wiring (`Experts/MultiSpeedZigZagEA.mq5`, `ProcessClosedBar()`): the
suite is evaluated immediately after regime classification — same
dependency, same "pure observer" shape as `JournalRegime()` — behind a new
`input bool InpEnableSixFamilyResearch=false;` (default disabled, same
convention as the five D027 research strategies). Its output array is
declared, populated, and goes out of scope; it is never appended to
`candidates[]`/`d027_candidates[]` and never reaches
`CMSZZCandidateHandoff`, `g_cluster_engine`, or `ExecuteCluster`. This is
enforced by the type system (§ above), not only by where the code happens
to sit.

### One shared journal

`MSZZ_SixFamilyResearchJournal.csv`, written by
`CMSZZSixFamilyResearchSuite::Journal()` — one CSV, all six families,
every field in `MSZZResearchCandidate`, header written once. Gated on the
same `InpWriteCSV` flag the rest of the EA already uses (no new flag
proliferation).

## Canonical definitions (frozen, one per family, at most one alternate — none tested)

Full per-family table (canonical event, stop, target, frozen constants):
`Tools/D031/family_definition_matrix.csv`. Summary:

1. **Session Sweep Reversal** (1200/8) — Asia session high/low frozen at
   08:00 broker time; excursion ≥0.15 ATR beyond it during London/NewYork;
   closed-bar reclaim within 6 bars. Stop beyond sweep extreme. Target
   fixed 2R. Reuses the exact frozen session-hour boundaries already
   established in `TradeAnalyticsExporter.mqh`'s `SessionBucket` — not
   redefined.
2. **Momentum Continuation** (1201/9) — confirmed fast break + impulse
   ≥1.5× fast ATR (`regime.fast_swing_amplitude_r`, the classifier's own
   feature, not re-derived) + directional efficiency ≥0.55 + fast/medium
   aligned; shallow pause (≤50% retracement, ≤6 bars); trigger on close
   beyond the pause extreme. Stop beyond pullback structure. Target fixed
   2R.
3. **Break-Retest Continuation** (1202/10) — confirmed MEDIUM-swing break
   (deliberately not fast, unlike existing `1040`) with a body/range
   filter (≥0.40) rejecting marginal breaks; retest window 2-12 bars, max
   0.30 ATR penetration; trigger on close through the rejection bar's
   extreme. Stop beyond retest extreme. Target fixed 2R.
4. **Compression Breakout (Research)** (1203/11) — raw
   `regime.normalized_atr` ≤0.80 (short/long ATR ratio, read before any
   bucketing) AND a self-tracked rolling 12-bar range width ≤2.5× ATR,
   persisting ≥3 bars; medium/slow-aligned close beyond the frozen
   compression boundary. Stop opposite side of the compression range.
   Target fixed 2R. **Deliberately never reads `regime.market_phase`** —
   see "Audit of existing 1060" below.
5. **Trend Pullback** (1204/12) — fast/medium aligned trend + directional
   efficiency ≥0.50 + price on the correct side of a day-anchored VWAP
   (the handoff's "choose one of ALMA or VWAP" — VWAP chosen, no
   window/weighting parameter to freeze) + confirmed countertrend
   micro-pivot; bounded pullback depth; trigger on close through the
   pullback's own micro-structure. Stop beyond pullback extreme. Target
   fixed 2R.
6. **Range Rotation** (1205/13) — see below.

`hypothesis_version = "D031v1"` for all six, frozen before any D032
screening.

## Audit of existing strategy `1060` (handoff Family 4 requirement)

The handoff's own Family 4 section requires: *"Audit any existing
CompressionBreakout code before reuse. Do not assume prior implementation
is correct or complete."* Read `D027StrategyFamilies.mqh`'s S4 in full:
it arms on three consecutive closed bars where the discrete regime
classifier already labeled `market_phase==MSZZ_PHASE_COMPRESSION`, then
waits up to six bars for a close beyond the frozen fast support/resistance
boundary. **Finding: it is implemented, correct for its own frozen
definition, and default-disabled — there is no defect to fix.** It is
simply a different measurement (discrete classifier label) than the raw
continuous ATR-ratio + rolling-window approach Family 4's own
"Recommended canonical definition" asks for, which is what
`CompressionBreakoutResearch.mqh` implements instead — distinct type,
strategy ID, and implementation identity, not a copy or wrapper. Because
an implemented `1060` of the same *name* already exists, D031/D032 must
eventually decide whether the new Family 4 supersedes it, coexists with
it as a genuinely different hypothesis, or is redundant — that decision is
explicitly deferred to D032's overlap analysis, not made here.

## Range Rotation's independent detector (handoff requirement)

`MSZZ_PHASE_RANGE` never fired once across the D030 census (98,943 bars).
`RangeRotation.mqh` never reads `regime.market_phase` and never modifies
`RegimeClassifier.mqh` or any global regime state. Instead it maintains
its own rolling 48-bar high/low window (causal — updated only with each
newly closed bar) and derives every one of the handoff's required range
properties from it directly:

- **range high/low**: window max/min.
- **minimum range age**: consecutive bars the window's width has stayed
  inside a frozen stable band (1.0-6.0× ATR) — `m_stable_bars`, gated at
  ≥12.
- **upper/lower touch counts**: bars within the window whose high/low
  came within 0.15× ATR of the boundary — gated at ≥2 per side.
- **low directional efficiency**: `regime.directional_efficiency` (an
  existing, already-computed classifier feature — read, not recomputed or
  altered) ≤0.40.
- **lack of an accepted medium-structure breakout**: `!m.bullish_break &&
  !m.bearish_break` on the current bar (a live per-bar gate — see
  `Tools/D031/known_limitations.md` #4 for why this is a simplification of
  a full-window scan, disclosed rather than silently assumed complete).

Only once all five hold does a slight excess (≤0.30× ATR) beyond the
boundary followed by a closed-bar reclaim emit a candidate, target the
range midpoint (not a fixed R-multiple — `EmitWithExplicitTarget`), stop
beyond the rejection extreme.

**A real ordering bug was found and fixed while building the test fixtures
for this family**: the range window was originally updated (`PushWindow`)
*before* computing `range_high`/`range_low` for the current bar, which
meant a genuine breakout bar's own high/low was already included in the
range it was being compared against — `bar.high>range_high` was then
literally unsatisfiable, since a new high always ties (never exceeds) a
range_high computed including itself. Fixed by moving `PushWindow` to the
end of `Evaluate()`, so range stats reflect only prior bars. See the
comment left at the fix site and `Tools/D031/known_limitations.md` #1.

## Tests

`Tests/MultiSpeedZigZag/Test_MSZZ_D031_SixFamilies.mq5`, same shape and
helper-fixture conventions (`BaseSnapshots`/`Pivot`/`Regime`/`Bar`,
`AssertTrue`/`g_tests`/`g_failures`) as the existing
`Test_MSZZ_D027Strategies.mq5` and `Test_MSZZ_CandidateHandoff.mq5`.
Covers: ID uniqueness/no-collision (shared), factory-level invalid-geometry
rejection and no-mutation-after-emission (shared, one choke point for all
six), and per family — canonical long, canonical short (Momentum
Continuation only, mirrored explicitly; the other five test canonical-long
plus a missing-prerequisite/stale-expiry pair), one missing-prerequisite
case, and (Momentum Continuation, Session Sweep Reversal) a decisive
post-expiry bar proving real expiry rather than "just hasn't triggered
yet". A determinism test replays an identical bar sequence through two
fresh suite instances and asserts field-identical output. See
`Tools/D031/known_limitations.md` #7 for exactly which of the handoff's
11 per-family test categories this does and doesn't cover 1:1.

**This test file was written and manually cross-checked (every fixture's
arithmetic hand-traced against the actual family logic — this is how the
Range Rotation bug above was caught) but could not be compiled or run in
this session.** See "Known limitations" below.

## Known limitations

Full list: `Tools/D031/known_limitations.md`. Headline: the MetaEditor
compile bridge did not produce a compiler-log update across four attempts
in this session (including against a previously-known-good file), an
environment issue confirmed via `mt5_status` (no MT5/MetaEditor process
running). Mitigated by manual signature cross-checks, brace/paren
balancing, an independent (non-MQL5) ID-collision check, and hand-tracing
every test fixture — which is how the Range Rotation ordering bug was
caught and fixed before this was ever run. **`Test_MSZZ_D031_SixFamilies.mq5`
must be compiled and run, and the existing test suite re-run, before D032
begins.**

## Deliverables

```text
Docs/MultiSpeedZigZag/D031_SIX_FAMILY_ARCHITECTURE.md   (this file)
Include/MultiSpeedZigZag/Research/Families/*.mqh          (6 families + shared types)
Include/MultiSpeedZigZag/Research/SixFamilyResearchSuite.mqh
Tests/MultiSpeedZigZag/Test_MSZZ_D031_SixFamilies.mq5
Tools/D031/id_allocation.csv
Tools/D031/family_definition_matrix.csv
Tools/D031/shadow_safety_audit.md
Tools/D031/known_limitations.md
```

Additive updates: `DECISION_LOG.md`, `STRATEGY_CATALOG.md`.

D032 (standalone synthetic screening) has not started.
