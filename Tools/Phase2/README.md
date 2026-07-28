# FastMedConfluence Phase 2 Exit and Holding-Tail Study (D024)

Answers: can any of 12 causal structural/composite exit models reduce
FastMedConfluence's ~56-77h p90 holding time (found in D021/D022/D023)
without materially damaging expectancy, PF, or drawdown? Entry logic,
canonical ATR settings, score logic, signal eligibility, one-owned-position
policy, and the structural-stop definition are all frozen — this study
changes exits only. See `DECISION_LOG.md` D024 for full design rationale
and results.

## Architecture

- `Include/MultiSpeedZigZag/Research/StructuralReplay.mqh` — a
  verified-equivalent duplicate of `CMSZZTripleZigZagEngine`'s causal
  scanning loop (`Test_MSZZ_StructuralReplay.mq5` proves byte-identical
  final state vs. the real engine), extended to emit a per-bar structural
  snapshot instead of only the final one. The live engine is never modified.
- `Include/MultiSpeedZigZag/Research/ExitModelsPhase2.mqh` — 11 causal
  exit models (Chandelier trail, Fast/Medium ZigZag swing trail, HL/LH
  trail, opposite-Fast-structure exit, max holding time 8h/12h/24h, fixed
  2R plus stale-trade timeout, breakeven-at-1R-plus-structural-trail,
  session-aware overnight exit), all inheriting D022's exact same-bar
  sequencing discipline. A 12th model, trail-only-after-+1R, is D021/D022's
  already-certified `TRAIL_0_5R_AFTER_1R`, reused verbatim (not
  reimplemented) for direct comparability.
- `Scripts/MultiSpeedZigZagTools/ExitSimulatorPhase2.mq5` — replays
  FastMedConfluence's fixed SIGNAL_LEVEL entry set (fresh capture at the
  current commit SHA, not reused from D021 or D023) against all 12 models,
  both SIGNAL_LEVEL and PORTFOLIO_LEVEL, exactly mirroring D021/D022's
  dual-replay design.

## Two real bugs found and fixed during verification

1. A stale ZigZag swing on the wrong side of current price (e.g. an old
   "last low" left over from before a sustained decline, now sitting above
   current price) was being accepted as a valid trailing-stop candidate,
   producing >100R "fake profits." Fixed by requiring every trail candidate
   be on the correct side of the current bar's close.
2. An off-by-one index mapping in `ExitSimulatorPhase2.mq5` silently ran
   `BE_1R_PLUS_TRAIL` against uninitialized parameters and
   `SESSION_OVERNIGHT` against `BE_1R_PLUS_TRAIL`'s real parameters. Fixed
   by removing the incorrect index shift.

Both fixes were cross-validated against two independent known-good
baselines (D022's `TRAIL_0_5R_AFTER_1R` ambiguous-count and `FIXED_2R`
magnitude) before any further number was trusted. See `DECISION_LOG.md`
D024 for full detail.

## Key finding: population mismatch with Stage B's live-EA baseline

The SIGNAL_LEVEL/PORTFOLIO_LEVEL replay population (530 signals) is not
the same population as Stage B's canonical live-EA run (224 executed
trades, the source of the `+0.1261R` baseline) — the same "occupancy
depends on the exit chosen" phenomenon D021 was built to expose. D022's
own committed plain `FIXED_2R` model (functionally equivalent to this
study's `FIXED_2R_PLUS_TIMEOUT`) shows PORTFOLIO_LEVEL expectancy of only
-0.0726R against the full signal population, confirming the mismatch is
real and not specific to any Phase 2 model. Results are reported against
both baselines.

## Results summary

**No model meets the strict success floor** (expectancy ≥ 80% of the
`+0.1261R` Stage B baseline, PF > 1.10). Against the population-matched
baseline instead, `TIME_24H` (+0.0584R, PF 1.09), `OPPOSITE_FAST_EXIT`
(+0.0337R, PF 1.06), and `TRAIL_AFTER_1R` (+0.0298R, PF 1.06) show real
relative improvement. The primary objective — cut the p90 holding-time
tail without damaging expectancy — is not cleanly achieved by any model:
models that dramatically cut holding time have negative expectancy;
models with positive expectancy barely move the p90 tail. `TIME_24H` and
`OPPOSITE_FAST_EXIT` are named as the two best-in-batch candidates for
further study, **not** as validated survivors ready for live wiring.

## Reproducing

1. Rerun `Tools/StageB/stageB_FastMedConfluence_canonical.ini` via the
   Tester, this time also copying `MSZZ_SignalJournal.csv` out of the
   sandbox (the Stage B harness normally only preserves
   `MSZZ_TradeAnalytics.csv`/`MSZZ_RunSummary.csv`).
2. Copy the journal into the terminal's `MQL5/Files/` and run
   `SignalSetExporter.mq5` (D021, unmodified) to build a fresh
   `MSZZ_SignalSet.csv`.
3. Run `ExitSimulatorPhase2.mq5`, both via `[StartUp] Script=...` configs
   on a normal (non-Tester) terminal launch.
