# Phase 1 — strategy entry-mode + level-source variations — 2026-07-20

## Purpose

First phase of the full EA build-out (approved plan
`expressive-hatching-eclipse.md`). Per `STRATEGY_SPEC.md` "Required completion",
each engine had only one hardcoded entry trigger. This phase adds selectable
entry trigger modes and objective level sources across all four strategies,
using the consolidated verification cadence (one compile + one self-test run +
one journaled baseline-preservation backtest for the whole batch).

## What was built

- **Six entry trigger modes**, gated by the existing `Inp*_TriggerMode` inputs,
  fail-closed on unsupported values:
  `TRIGGER_IMMEDIATE_BREAK`, `TRIGGER_CANDLE_CLOSE_BREAK`, `TRIGGER_DISPLACEMENT`
  (existing), plus `TRIGGER_BREAK_RETEST` (broke a level, wicked back to retest,
  held), `TRIGGER_PROBE_CONFIRM` (strong body closing near the extreme beyond a
  level), and `TRIGGER_REJECTION` (directional rejection-wick entry) — the last
  three previously declared-but-dead (`BREAK_RETEST`/`PROBE_CONFIRM` fell through
  to `false`) or absent.
- **Shared trigger helpers in `StrategyBase.mqh`**: `ConfirmCandleTrigger()`
  (candle/displacement/probe/rejection modes) and `ConfirmLevelTrigger()`
  (level-aware break-retest/probe-confirm). TP and MR were consolidated onto
  `ConfirmCandleTrigger` (their duplicate private `TriggerConfirmed` removed);
  BO's trigger switch was extended with the level modes; FBO layers the extra
  modes additively on top of its proven reclaim logic (default unchanged).
- **`ENUM_LEVEL_SOURCE`** (range / prev-day / session / opening-range / swing)
  + `SelectLevel()` helper + `InpBO_LevelSource` input, wired into BO's breakout
  level. Reuses existing FeatureEngine fields (`prev_day_*`, `session_*`,
  `or_*`, `swing_*`); no new feature math. Falls back to the range level when a
  source is unavailable.
- Every addition is **additive and defaults to current behavior**
  (`InpBO_TriggerMode=CANDLE_CLOSE`, `InpBO_LevelSource=RANGE`).

## Files

`Core/Enums.mqh` (new trigger value + `ENUM_LEVEL_SOURCE`), `StrategyBase.mqh`
(shared helpers), `Strategies/BreakoutEngine.mqh` (level source + level modes),
`FailedBreakoutEngine.mqh` (additive mode layer), `TrendPullbackEngine.mqh` /
`MeanReversionEngine.mqh` (consolidated onto shared helper),
`Core/Configuration.mqh` + `QuantBeastEA.mq5` (input + Init wiring),
`Testing/SafetyTests.mqh` (TEST 52 + 53).

## Verification

- Compile: **0 errors, 0 warnings**.
- Self-tests: **56 passed, 0 failed** (was 54). New:
  - `TEST 52 PASS: Entry trigger modes probe=ok probeWeak=ok rejFailClosed=ok mrRej=ok`
    — probe-confirm fires on a strong close and rejects a weak one, an
    unsupported mode (rejection on BO) fails closed, MR rejection-wick entry fires.
  - `TEST 53 PASS: Level-source selection rangeNoTrigger=ok prevTriggers=ok`
    — a prev-day-keyed breakout triggers where a range-keyed one does not.
  - `TEST 16-19` (BO/FBO/TP/MR reachability) all still PASS — defaults unchanged.
- **Baseline preservation** (journaled Apr 20-24, default config, real ticks):
  ACCEPTED **BO 2, FBO 9, TP 0, MR 5** — identical to the pre-Phase-1 baseline,
  confirming the shared-trigger/level-source refactor changes nothing at default
  configuration.

## Source state

- `QuantBeastEA.ex5` SHA-256:
  `ba23111d64876456fbfb38eb56fbf9896e1c0251e2c56df43fb280f02044452e`
- `StrategyBase.mqh` SHA-256:
  `7872d220d56506d90ea630238e8170d48fc8741994749cc18bfcbfc82336eb19`
- `Core/Enums.mqh` SHA-256:
  `db0ae89c479eb3fcf1347a3c39d019c4aad86fbf8588eccb92eb42cf3005b7c6`

No broker orders (Shadow mode). Readiness remains `READY FOR SHADOW MODE`.
