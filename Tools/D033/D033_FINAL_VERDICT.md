# D033 final verdict

**REJECTED — D034 is not authorized.** The frozen broker-executable SSR fails development, holdout, best-quarter-exclusion, and (pending final rerun) full-regression gates.

| Mandatory gate | Result |
|---|---|
| broker_expectancy_gt_0 | PASS |
| overall_pf_gt_1_05 | PASS |
| development_positive | FAIL |
| validation_positive | PASS |
| holdout_positive | FAIL |
| top_3_exclusion_positive | PASS |
| best_quarter_exclusion_positive | FAIL |
| zero_future_leakage | PASS |
| zero_accounting_mismatches | PASS |
| zero_ownership_violations | PASS |
| zero_unresolved_synthetic_broker_discrepancies | PASS |
| full_regression_green | FAIL |
| p4_parity_preserved | PASS |

No thresholds were loosened and no SSR parameter was tuned.
