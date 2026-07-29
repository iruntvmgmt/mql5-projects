# D029 Final — Sizing and Partial-Exit Decisions

Machine-readable final decisions for D029. See
`Docs/MultiSpeedZigZag/D029_FINAL_REPORT.md` for the full narrative.

- `sizing_architecture_decision.csv`: `DUAL_MODE_RECOMMENDED`.
- `partial_architecture_decision.csv`: `BROKER_PARTIAL_CLOSE_RECOMMENDED`.
- `strategy_policy_decisions.csv`: SR0-PCT `PORTFOLIO_VALIDATION_CANDIDATE`,
  SR3-PCT `RESEARCH_ONLY`, SR4-PCT `REJECTED`.
- `portfolio_decisions.csv`: D29-P3/D29-P4 `PORTFOLIO_VALIDATION_CANDIDATE`
  (unchanged from D028, now reconfirmed under percent-equity sizing);
  P3-SR3/P4-SR3 `REJECTED`.
- `anti_overfitting_summary.csv`: every anti-overfitting check applied in
  this pass, including the two disclosed gaps (no fixed cost-stress
  scenarios, no genuine independent out-of-sample data).
- `final_integrity_audit.csv`: rollup of every integrity check across all
  four phases.

Nothing in D029 is called production-ready. No merge to `main`, no live
deployment, at any point in this study.
