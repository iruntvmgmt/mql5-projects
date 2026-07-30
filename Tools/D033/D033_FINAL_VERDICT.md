# D033 final verdict

**D033_INTEGRATION_DEFECT — D034 is not authorized.** The tested production configuration fails development, holdout, best-quarter-exclusion, and full-regression gates. The frozen hypothesis remains inconclusive because production consumed distinct timestamped re-arm events under one day/direction cluster.

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
