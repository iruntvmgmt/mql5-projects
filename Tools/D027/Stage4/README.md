# D027 Stage 4 — standalone fixed-2R screen

This checkpoint screens the five frozen Stage 3 strategy families individually
on XAUUSD M5 from 2025-03-01 through 2026-07-24. Each run uses the canonical
tester model and costs, structural stops, a fixed 2R target,
`InpExitOwnedOpposite=true`, and `LABEL_ONLY` regime attribution. All existing
eight strategies and the other four D027 families are disabled in each run.
Research score overrides, partial exits, fixed-target suppression, research
trailing, and regime filtering are disabled.

Run inputs are tracked as `Tools/D027/d027_stage4_*.ini`. Raw native HTML and
CSV artifacts remain under:

`/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results`

They are not copied into Git because the five regime journals total roughly
75 MB. The deterministic standard-library analyzer is:

```bash
python3 Tools/D027/Stage4/analyze_stage4.py
```

It validates config identity, RunSummary/TradeAnalytics/native-HTML parity,
unique entry-signal and entry-time regime joins, frozen-window reconciliation,
exit classification, concentration, direction, regime distribution, and
same-bar/shared-origin overlap against the preserved Stage 2
FastMedConfluence baseline. It fails rather than dropping an ambiguous trade.

`wall_clock_exposure_pct` is a transparent research descriptor: summed
holding bars divided by elapsed wall-clock M5 bars between the first entry and
last exit. It is not MT5 margin exposure. Tester fills naturally include
spread; configs retain the canonical 80-point spread guard and 30-point
deviation. No unsupported commission-R estimate is invented.

Only SweepReclaim passes the frozen mechanical gate for Stage 5's single 3R
check. This is eligibility to run one predefined follow-up, not strategy
promotion or deployment approval. No Stage 4 result changes canonical A or E,
any frozen trigger, any regime definition, or any history window.
