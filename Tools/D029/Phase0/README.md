# D029 Phase 0 — Tester Balance Selection

`volume_resolution_analysis.py` projects, for a set of candidate synthetic
tester balances, what fraction of SweepReclaim's 190 canonical (SR0,
D028-certified) trades would produce a broker-normalized volume >= 0.02 lots
at 0.25% requested risk per book -- the minimum size needed to support a
valid 50% partial close at this account's 0.01 volume step.

Inputs: canonical stop distances (`|entry - stop|`) read directly from
`/Users/matt/MT5-MSZZ-TEST/D028_Stage5_Results/SR0/MSZZ_TradeAnalytics.csv`
(D028's already-certified SweepReclaim SR0 run -- no new backtest needed for
this projection) and XAUUSD symbol metadata captured by
`Scripts/MultiSpeedZigZagTools/SymbolMetadataProbe.mq5`
(`tick_size=0.01`, `tick_value=1.00`, `contract_size=100`, `volume_min=0.01`,
`volume_step=0.01`).

This is a pre-result projection only -- it never looks at trade P&L, only at
stop-distance-driven position sizing. Run before any D029 backtest.

Result: `volume_resolution_summary.csv`. `$100,000` (the handoff's own
suggested starting candidate) achieves **100%** partial-capability at
>=0.02 lots, exceeding the required 95% threshold with the maximum
available margin, and is the frozen D029 tester balance. See
`frozen_design.md` and `Docs/MultiSpeedZigZag/D029_PERCENT_RISK_PARTIALS.md`
for the full rationale and every other frozen Phase 0 decision.
