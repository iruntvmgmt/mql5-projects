# D029 Phase 3 — Executable Partial and Runner Study

SR0 (control, percent-equity), SR3-PCT (50% partial at +1R + breakeven
remainder), SR4-PCT (50% partial at +1R + structural-pivot runner), each
run exactly once at the frozen $100,000 balance. Configs: `d029_phase3_*.ini`.
Raw results: `/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/`.
`analyze_partials.py` produces the CSVs in this directory from each
variant's `MSZZ_TradeAnalytics.csv`, `MSZZ_SizingJournal.csv`,
`MSZZ_SignalJournal.csv`, and `MSZZ_PartialCloseJournal.csv`.

Unlike D028's SR3/SR4 (invalidated by the 0.01-lot volume floor), both
variants here executed genuine partial closes: 86 for SR3-PCT, 82 for
SR4-PCT, 100% exact volume reconciliation (`partial + remaining ==
original` in every case), zero `REJECT_PARTIAL_VOLUME_INELIGIBLE` events
(0/203, 0/207 — SweepReclaim's volume resolution at $100,000 remains
perfect, matching Phase 0/Phase 2). `RAW_CANDIDATE` count is identical
(376) across all three variants, proving zero signal-stream divergence.

**SR3-PCT: PORTFOLIO_TEST_ELIGIBLE.** Passes every explicit decision-rule
gate: positive full-window/validation/holdout expectancy, remains positive
excluding the top 3 trades and the best quarter, no extreme runner
dependence, exact accounting, zero unknown exits, zero signal mismatch. Max
DD improves 18% versus SR0 (14.95R vs 18.29R) — a genuine, distributed
improvement, not an artifact of a few trades. The tradeoff is real and
disclosed: cumulative R, expectancy, and PF are all lower than SR0
(long-direction expectancy actually goes slightly negative, -0.0035).

**SR4-PCT: REJECTED.** Fails three explicit gates at once: excluding the
top 3 trades flips the entire result negative (+14.78R -> **-13.20R**),
excluding the top 5 goes further negative (-20.90R), and excluding the best
quarter also goes negative (-5.23R). This is the exact "extreme runner
dependence" pattern the Stage 5/Phase 3 decision rules exist to catch —
now observed with a fully working partial-close mechanism, not an artifact
of D028's volume-floor defect. The runner design itself does not produce a
robust edge on SweepReclaim's entries.

Only SR3-PCT advances to Phase 4 (alongside SR0 as the mandatory control).
