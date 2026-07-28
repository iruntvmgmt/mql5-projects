# D027 Stage 5 — limited 3R screen

Stage 4 admitted only SweepReclaim to the single predefined fixed-3R check.
No other family was run. The tracked input changes only the fixed
risk/reward target from 2.0 to 3.0 while retaining the frozen trigger,
structural stop, XAUUSD M5 history window, tester model, costs,
`InpExitOwnedOpposite=true`, and `LABEL_ONLY`. Research overrides, regime
filters, trailing, partial exits, and fixed-target suppression remain off.

Run:

```bash
python3 Tools/D027/Stage5/analyze_stage5_3r.py
```

The analyzer compares the Stage 4 2R result with Stage 5 3R, validates the
config and native MT5/CSV counts, joins every trade to one executed signal and
one entry-time regime snapshot, proves the frozen raw candidates identical,
and proves the multi-step sequence journals byte-identical. It reports frozen
windows, monthly and quarterly results, outliers, sides, holds, exposure,
exits, regimes, core overlap, unique contribution, and target-dependent
execution-path differences.

Raw artifacts remain under:

`/Users/matt/MT5-MSZZ-TEST/D027_Stage5_Results/SweepReclaim_3R`

They are not copied into Git because the regime and sequence journals account
for approximately 50 MB.

The 3R result is positive full-window but inferior to 2R: lower cumulative R,
expectancy, and PF, higher drawdown, negative final holdout, negative after
removing its best quarter, and almost flat unique expectancy beyond the core.
The 3R target is therefore rejected. SweepReclaim 2R remains `RESEARCH_ONLY`
for the separate Stage 6 portfolio experiment; it is not promoted or deployed.
