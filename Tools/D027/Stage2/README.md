# D027 Stage 2 — descriptive regime attribution

This checkpoint attributes the existing eight fixed-2R strategies to the
frozen D027 entry-time regime labels. It does not gate, promote, rescue, or
modify a strategy. Canonical A and E are unchanged.

## Inputs

The completed MT5 batch is preserved outside the repository at:

`/Users/matt/MT5-MSZZ-TEST/D027_Stage2_Results`

The eight tracked tester configurations are one directory above this file:

`Tools/D027/d027_stage2_<Strategy>.ini`

Raw results are not duplicated in Git. The eight regime journals alone are
approximately 120 MB, while the full raw batch is 129 MB. This follows the
existing repository-size discipline while retaining exact paths and
machine-readable derived artifacts.

All runs used the isolated `/Users/matt/MT5-MSZZ-TEST` terminal, XAUUSD M5,
real ticks (`Model=2`), `2025.03.01`–`2026.07.24`, fixed 2R, one enabled
strategy, no trailing mode, and `LABEL_ONLY`. Magic numbers are unique:
`26072893`–`26072899`, with `26072901` reserved for FastBreakout. FastBreakout
alone uses the already-authorized D019 research score override (`3.5`);
all other strategies use the normal score threshold and no override.

## Reproduce

```bash
python3 Tools/D027/Stage2/analyze_stage2_regimes.py
```

The script is standard-library only. It fails on missing/empty inputs,
malformed rows, summary/analytics count disagreement, missing or duplicate
executed-signal joins, missing or duplicate regime snapshots, snapshot-time
disagreement, label disagreement, or non-`LABEL_ONLY` eligibility.

Attribution is:

`trade cluster_id -> EXECUTED signal -> regime_snapshot_id -> regime journal`

The snapshot must equal the original signal time. Exit-time regimes are never
used. Outputs are sorted and formatted deterministically. `output_sha256.txt`
records hashes for the generated CSV files.

## Baseline equivalence

Stage 2 exactly matches the accepted Stage B canonical run summaries and trade
analytics for FastBreakout (authorized research baseline), MediumBreakout,
FastMedConfluence, FastMedContext, MedSlowContext, NestedPullback, and
WeightedEnsemble, apart from intentionally unique magic numbers.

SlowBreakout matches all 336 accepted canonical trades byte-for-byte by
`cluster_id` and analytics fields, then preserves one additional position
opened at `2026.07.21 05:35` and closed by the tester at
`2026.07.23 23:59:59` for `+0.1635R`. MT5 HTML, RunSummary, and analytics all
report 337 trades. This is a test-end completion difference, not a
`LABEL_ONLY` behavior change, and the trade is not omitted.

## Outputs

- `strategy_regime_summary.csv`: full-window bucket metrics.
- `strategy_regime_window_summary.csv`: development, validation, final
  holdout, and full-window bucket metrics.
- `strategy_regime_monthly.csv` / `strategy_regime_quarterly.csv`: temporal
  concentration.
- `strategy_regime_outlier_checks.csv`: best-period and top-trade exclusions,
  plus side contributions.
- `strategy_regime_join_audit.csv`: preservation and attribution integrity.
- `strategy_regime_distribution.csv`: emitted entry-regime frequencies.
- `strategy_regime_concentration.csv`: strongest bucket contribution by
  dimension.
- `stage2_findings.md`: readable interpretation and research boundaries.

Sample labels are fixed: `<20 INSUFFICIENT`, `20–49 EXPLORATORY`,
`50–99 MODERATE_SAMPLE`, and `100+ STRONGER_DESCRIPTIVE_SAMPLE`.
