# Exit-Efficiency Study — Phase 1 (D021)

Answers: does a smarter exit convert more of a trade's favorable excursion
(MFE) into realized profit than Stage A's fixed structural-stop N-R exit,
without reintroducing the ~23h holding-time problem seen in the
FastMedConfluence RR3.0 Stage A run? See `DECISION_LOG.md` D021 for full
design rationale.

## Architecture

- `Include/MultiSpeedZigZag/Research/ExitSimulatorPolicy.mqh` — pure,
  deterministic exit-resolution logic (14 Phase-1 models), unit-tested in
  `Tests/MultiSpeedZigZag/Test_MSZZ_ExitSimulator.mq5`.
- `Scripts/MultiSpeedZigZagTools/SignalSetExporter.mq5` — reads an
  already-completed Stage A run's `MSZZ_SignalJournal.csv` and exports the
  immutable **SIGNAL_LEVEL** entry set: every signal that passed every
  guard except (possibly) occupancy, i.e. the union of `EXECUTED` and
  `REJECT_OWNERSHIP` journal rows.
- `Scripts/MultiSpeedZigZagTools/ExitSimulator.mq5` — replays that fixed
  signal set against all 14 exit models in two modes:
  - **SIGNAL_LEVEL**: every signal simulated independently, overlapping
    trades allowed (no occupancy) — isolates entry/exit quality from
    portfolio constraints.
  - **PORTFOLIO_LEVEL**: the same signals replayed chronologically with
    one-owned-position enforced, using *that exit model's own* resolved
    exit time to determine occupancy — shows what the EA would actually
    have executed under each model, including signals lost to occupancy.

## Why SIGNAL_LEVEL and PORTFOLIO_LEVEL both exist

Stage A's trade counts differ across RiskReward values purely because of
position occupancy (a longer-held trade blocks later signals a
faster-exiting one would have caught) — not because the entries differ.
Comparing exit models using any single Stage A run's completed-trade CSV
as "the" entry set would silently bake one exit model's own occupancy
behavior into a comparison against a different exit model. Both replay
modes use the identical underlying signal stream.

## Known limitations (documented, not silently absorbed)

- **Tick coverage**: a build-time probe found the isolated instance's local
  cache has no real historical tick data for the Stage A window (only a
  ~124KB recent-activity cache, nowhere near 17 months) — `replay_price_mode`
  is `MSZZ_AMBIG_PESSIMISTIC` (OHLC bar-range, adverse-first on any
  same-bar ambiguity) for every trade in this pass, not tick-resolved.
  This is the honestly-labeled primary evidence, per D021's decision.
- **Cost model**: `InpEstimatedCostR=0.02` is a flat per-trade round-trip
  commission+spread estimate in R units, not derived from actual historical
  spread/commission data (which isn't available for hypothetical
  REJECT_OWNERSHIP signals that never actually filled).
- **MFE/MAE reference window**: computed over a fixed 3-day forward window
  per trade (`InpForwardWindowDays`), shared identically across all 14 exit
  models for a given signal, so `percent_mfe_captured`/`surrender_r` are
  directly comparable between models.

## Results summary (all three named strategies, RiskReward=2.0 entries)

`TRAIL_0_5R_AFTER_1R` (arm a 0.5R trailing stop once price reaches +1R) is
the standout, consistently: the only exit model that flips from negative
SIGNAL_LEVEL expectancy to **positive PORTFOLIO_LEVEL expectancy** in all
three strategies (FastMedConfluence +0.046R, FastMedContext +0.041R,
WeightedEnsemble +0.040R; profit factor 1.08–1.11 in all three) — see each
strategy's `results/<strategy>/MSZZ_ExitSim_Summary.csv` for the full
14-model comparison. Full findings and their caveats are in the D021
BACKTEST_LOG.md entry and the report delivered alongside this commit.

## Reproducing

1. Run a Stage A RR2.0 config for the target strategy (`../StageA/`) to
   produce a fresh `MSZZ_SignalJournal.csv`.
2. Copy it into the terminal's `MQL5/Files/` (not the Tester Agent
   sandbox — `SignalSetExporter`/`ExitSimulator` run as normal scripts,
   which use a different file location than a Tester run).
3. Run `SignalSetExporter.mq5`, then `ExitSimulator.mq5`, both via a
   `[StartUp] Script=...` config on a normal (non-Tester) terminal launch.
