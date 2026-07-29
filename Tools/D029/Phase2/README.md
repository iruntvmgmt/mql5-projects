# D029 Phase 2 — Percentage-Sized Controls

Five controls run at the frozen $100,000 tester balance, 0.25%/0.50%
percent-equity sizing, canonical entries/stops/costs unchanged from D028:
`D29-A` (FastMedConfluence A alone, fixed 2R), `D29-E` (FastMedConfluence E
alone, fixed 3R), `D29-SR0` (SweepReclaim alone, fixed 2R), `D29-P3`
(A 2R + SweepReclaim 2R, independent books), `D29-P4` (E 3R + SweepReclaim
2R, independent books). Configs: `d029_phase2_D29_*.ini`. Raw results:
`/Users/matt/MT5-MSZZ-TEST/D029_Phase2_Results/`.

`analyze_controls.py` computes headline/window/reconciliation metrics from
each control's `MSZZ_TradeAnalytics.csv` (single-book) or
`MSZZ_PortfolioTradeAnalytics.csv` (multi-book) plus `MSZZ_SizingJournal.csv`.
Output CSVs: `control_summary.csv`, `risk_reconciliation.csv`,
`volume_distribution.csv`, `window_summary.csv`, `integrity_audit.csv`.

One real bug was found and fixed while running this batch (see
`Docs/MultiSpeedZigZag/D029_PERCENT_RISK_PARTIALS.md` Phase 2 section for
the full account): `symbol_exposure_cap_lots` was derived from
`InpFixedLots` unconditionally, silently capping every percent-equity
position at 0.02 lots regardless of sizing mode. Fixed by disabling that
lot-count cap in percent-equity mode (risk is already bounded by the
mode-aware percent caps).

Headline finding: D29-SR0 reconciles **exactly** to the D028 certified
fixed-lot baseline (190/190 trades, identical R statistics) — zero
`MIN_VOLUME_REJECT` events, since SweepReclaim's stop distances are always
wide enough at $100,000 to size well above the 0.02-lot partial-capable
threshold, exactly as Phase 0's projection predicted. D29-A/E/P3/P4 show
small (-3/-3/-1/-1 trade) deltas versus their fixed-lot counterparts,
fully attributed to `MIN_VOLUME_REJECT` (7 genuine sizing rejections in
each run) plus `BOOK_ALREADY_OPEN` cascading occupancy shifts — both
explicitly allowed reconciliation categories.
