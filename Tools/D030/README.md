# D030 — P4 Loss-Cluster and Uncovered-Regime Map

Read-only analysis of the certified P4 portfolio (`D29-P4`: FastMedConfluence
E at fixed 3R + SweepReclaim at fixed 2R). No strategy code, sizing, exits,
targets, or stops were touched. No new backtest was run.

## Script

`analyze_p4_loss_map.py` — deterministic, no arguments, reads only the paths
below, writes everything to `out/`.

```bash
python3 Tools/D030/analyze_p4_loss_map.py
```

## Inputs

Trade population (the 330 certified `D29_P4` trades, byte-identical to the
figures in `D029_AUDIT_FINAL_REPORT.md` — total R 47.6083, PF 1.2472,
reconfirmed by this script's own recomputation from the raw evidence, not
copied from the report):

```text
/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4/MSZZ_PortfolioTradeAnalytics.csv
/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4/MSZZ_SignalJournal.csv
/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4/MSZZ_SizingJournal.csv
/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4/MSZZ_StrategyBookJournal.csv
/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4/MSZZ_DealJournal.csv
/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4/MSZZ_PortfolioRiskJournal.csv
```

This is the FINAL rerun batch on the fully-patched binary (the same root the
audit's own `audit_portfolios_rerun.py` certifies against) — not the Phase2
or Phase4 pre-audit evidence.

Bar-level regime census (for the uncovered-regime map only):

```text
/Users/matt/MT5-MSZZ-TEST/D028_Stage4_Results/P4_Independent_E3R_Sweep2R/MSZZ_RegimeJournal.csv
```

### Why a D028 file is used for the regime census

`D029_Audit_Results/D29_P4` does not include a bar-level `MSZZ_RegimeJournal.csv`
(that exporter path was not enabled for the D029 audit reruns — only signal-time
and trade-time regime snapshots were journaled there). The D028 Stage4 `P4`
run's regime journal is the only full bar-by-bar regime census on disk that
covers the same symbol/timeframe/window. This substitution is safe because:

- The Layer 1 regime classifier (`Include/MultiSpeedZigZag/Research/RegimeClassifier.mqh`)
  is a pure, deterministic function of price structure only — it has no
  dependency on position sizing, exit management, or partial-close logic,
  which is everything D029's audit patched. The classifier code is
  unchanged between D028 and D029.
- Both runs replay the same broker XAUUSD M5 history over the same
  calendar window.

`sha256` of every input file (including the regime census) is recorded in
`out/input_hashes.csv` for reproducibility.

## Key joins (all on existing frozen journal fields, nothing invented)

- **Regime at entry**: `MSZZ_SignalJournal.csv` rows with `status=EXECUTED`,
  keyed by `cluster_id == logical_position_id`. This is the ENTRY-time
  regime snapshot. (`MSZZ_PortfolioTradeAnalytics.csv`'s own
  `regime_snapshot_id` column is re-stamped at EXIT time by the CLOSE-side
  `StrategyBookJournal` row, so it was not used for entry-regime attribution.)
- **Stop distance / requested risk**: `MSZZ_SizingJournal.csv`, first
  `sizing_result=OK` row per `logical_position_id`.
- **Simultaneous exposure**: `MSZZ_PortfolioRiskJournal.csv` `action=OPEN`
  rows, keyed by `(book_id, time==entry_time)`, using the existing
  `open_books` field (0 = SOLO, >0 = CONCURRENT). Not a new computation.
- **Cost proxy**: `MSZZ_DealJournal.csv` commission+swap, summed per
  position via `broker_position_ticket` (`MSZZ_StrategyBookJournal.csv`
  `action=OPEN` rows) → `logical_position_id`.
- **Session**: reuses the exact frozen definition in
  `Include/MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh`
  `CMSZZTradeAnalyticsPolicy::SessionBucket` — three fixed 8-hour buckets
  on broker server time (Asian <08:00, London <16:00, NewYork else). Not
  redefined here.
- **Dev/validation/holdout split**: the exact frozen windows D029's own
  `Phase4/analyze_portfolios.py` and `Audit/audit_portfolios_rerun.py` use
  (dev 2025-03-01..2025-12-31, val 2026-01-01..2026-04-30, holdout
  2026-05-01..2026-07-24).

## Data limitations (disclosed, not worked around)

1. **MFE/MAE bucket**: not computable from the certified portfolio-level
   evidence. `MSZZ_PortfolioTradeAnalytics.csv` for portfolio-book runs
   (`D29_P4`, `D29_P3`, `D29_SR0`, etc.) does not carry `mfe_r`/`mae_r` —
   only the separate single-strategy standalone exporter
   (`MSZZ_TradeAnalytics.csv`, used for `SR0`/`SR3_PCT`/`SR4_PCT` in
   `D029_Phase3_Results`) does, and that's SweepReclaim-only, not the P4
   portfolio. Reconstructing MFE/MAE for 330 portfolio trades would require
   a new bar-by-bar price replay per trade window — not attempted in this
   pass; flagged for a future D0xx research task if excursion-based exits
   become relevant.
2. **spread/risk decile**: `execution_cost` is uniformly `0.0` across all
   330 `D29_P4` trades — no per-trade spread cost is journaled in R terms
   for portfolio-book runs. `cost_to_risk_decile` (broker commission+swap
   ÷ requested risk money) is reported as the closest available real-cost
   substitute, explicitly labeled as such in `bucket_summary.csv`. Note:
   it correlates strongly with `holding_time_decile` (swap accrues per
   day held), so it should not be read as an independent "spread" signal —
   see the report's "Data limitations" section.
3. **Regime census provenance**: see above — sourced from a D028 run, not
   the D029 certified evidence itself, for the reason given.

## Outputs (`out/`)

```text
trades_enriched.csv              — all 330 trades with every joined/derived field
bucket_summary.csv               — long-format: dimension x bucket x {count, PF, expectancy, total R, dev/val/holdout expectancy, long/short split}
monthly_summary.csv              — same shape, month dimension only
concentration.csv                — top-1/3/5, best-month, best-quarter exclusion tests
regime_coverage.csv              — full 5-way regime combo: bar count/pct in window vs trade count/expectancy
regime_dimension_coverage.csv    — single-dimension roll-up of the same bar-vs-trade comparison (the 5-way table is too sparse per-cell to call anything "uncovered" cleanly)
book_overlap.csv                 — FastMedConfluence vs SweepReclaim overlap episodes (reuses D029 Phase4's own overlap computation, not reinvented)
input_hashes.csv                 — sha256 of every input file read
```

See `Docs/MultiSpeedZigZag/D030_P4_LOSS_MAP.md` for the narrative findings.
