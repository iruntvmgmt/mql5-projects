# Phase 2 — strategy stop / target / exit variations — 2026-07-20

## Purpose

Second phase of the full EA build-out. Per `STRATEGY_SPEC.md` each engine had a
single hardcoded stop and target; the exit repertoire in `PositionManager` /
`ShadowPortfolio` lacked momentum-failure and regime-deterioration exits. This
phase adds selectable stop/target modes across all four engines and two
additive exit types in both execution paths, verified in one consolidated pass.

## What was built

- **`ENUM_STOP_MODE`** (default / ATR / swing / structural / sweep) and
  **`ENUM_TARGET_MODE`** (default / fixed-R / VWAP / range-mid / opposite-
  boundary), dispatched by shared `StrategyBase` helpers `ComputeStop()` and
  `ComputeTarget()`. Each engine passes its **native** stop/target as the
  `DEFAULT` value, so `*_MODE_DEFAULT` reproduces prior behavior exactly;
  alternative modes are validated onto the correct side of entry, falling back
  to the native value otherwise. Wired into all four engines
  (`BreakoutEngine`, `FailedBreakoutEngine`, `TrendPullbackEngine`,
  `MeanReversionEngine`) with 8 new inputs `Inp{BO,FBO,TP,MR}_StopMode` /
  `_TargetMode` (all default).
- **Two additive exit types**, gated off by default:
  - Momentum-failure (`EXIT_FAILED_MOMENTUM`): a position open past a window
    with current R below a floor is closed. `InpEnableMomentumExit`,
    `InpMomentumExitMinutes`, `InpMomentumExitMinR`.
  - Regime-deterioration (`EXIT_REGIME_DETERIORATE`): closed on a shock candle /
    volatility spike (Shadow path uses a `feat`-derived proxy; the live path
    uses the full `RegimeState` — shock/extreme volatility or a hard trend flip
    against the position). `InpEnableRegimeExit`.
  Implemented in **both** `ShadowPortfolio.Update` (via a `SetExtendedExits`
  setter, keeping the many self-test callers unaffected) and
  `PositionManager.UpdatePosition` (new steps 4-5 before the time stop).

## Files

`Core/Enums.mqh` (mode enums), `StrategyBase.mqh` (`ComputeStop`/`ComputeTarget`),
`Strategies/*.mqh` (all four engines: members + Init + stop/target dispatch),
`Core/Configuration.mqh` (10 new inputs), `QuantBeastEA.mq5` (Init wiring +
`SetExtendedExits` calls), `Execution/ShadowPortfolio.mqh` +
`Execution/PositionManager.mqh` (additive exits), `Testing/SafetyTests.mqh`
(TEST 54 + 55).

## Verification

- Compile: **0 errors, 0 warnings**.
- Self-tests: **58 passed, 0 failed** (was 56). New:
  - `TEST 54 PASS: Stop/target mode dispatch defValid=ok atrDiffers=ok
    atrCorrect=ok vwapTarget=ok` — the ATR stop mode yields a different,
    correctly-placed stop than the default, and the VWAP target mode hits VWAP.
  - `TEST 55 PASS: Extended exit types stayedOpen=ok regimeExit=ok` — a normal
    bar leaves an open shadow position untouched; a shock candle triggers the
    `EXIT_REGIME_DETERIORATE` close.
  - `TEST 16-19` (reachability) unchanged.
- **Baseline preservation** (journaled Apr 20-24, default config, real ticks):
  ACCEPTED **BO 2, FBO 9, TP 0, MR 5** — identical to baseline, confirming the
  stop/target dispatch and additive exits change nothing at default config.

## Source state

- `QuantBeastEA.ex5` SHA-256:
  `c701edb65c8170568120b7921084a57a95736a4b2f35c8338ea836db6ac710f9`

No broker orders (Shadow mode). Readiness remains `READY FOR SHADOW MODE`.
