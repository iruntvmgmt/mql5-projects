# D027 Stage 7 — frozen regime-filter research

This stage applies the one predeclared `RESEARCH_FILTER` hypothesis to each
default-off D027 strategy family at fixed 2R. It does not search regime
combinations, alter thresholds, gate A or E, or modify a trigger.

Run:

```bash
python3 Tools/D027/Stage7/analyze_stage7_filters.py
```

The analysis compares the filtered runs in
`/Users/matt/MT5-MSZZ-TEST/D027_Stage7_Results` with their Stage 4
`LABEL_ONLY` controls. It verifies config identity, byte-equivalent ordered
raw-candidate fields, native HTML counts, optional zero-trade artifact
behavior, executed-signal and original entry-time regime joins, filtered
trade subset identity, frozen-window reconciliation, and concentration.

Zero-trade runs legitimately omit `MSZZ_RunSummary.csv` and
`MSZZ_TradeAnalytics.csv`; their native report, signal journal, and regime
journal are required and audited. Raw MT5 artifacts remain outside the
repository under the established size policy.
