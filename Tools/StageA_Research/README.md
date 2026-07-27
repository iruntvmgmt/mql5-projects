# FastBreakout research eligibility results (D019)

FastBreakout's base score (`4.0`, hardcoded in `StrategySuite.mqh`) sits below
`InpMinScore` (default `5.0`), so it can never produce a standalone trade
under canonical isolation-mode Stage A settings — a structural non-finding,
not a strategy result. These configs use D019's `InpResearchMinScoreOverride`
(set to `3.5`) to evaluate it anyway, for research purposes only.

**These results are NOT part of the canonical Stage A baseline** — kept in
separate `_master_trades_research.csv` / `_master_runsummary_research.csv`
files, never merged into `Tools/StageA/_master_trades.csv`.

## Files
- `generate_research_fastbreakout.sh` — generates the 4 RR configs.
- `stageA_research_FastBreakout_RR*.ini` — the 4 generated configs
  (`InpResearchMinScoreOverride=3.5`, `InpAcknowledgeResearchOverride=true`).
- `stageA_research_negtest_FastBreakout_RR10.ini` — negative-path smoke test
  (`InpAcknowledgeResearchOverride=false` while the override is still set) —
  confirms the fail-closed gate actually blocks (`INIT_FAILED`) rather than
  silently falling back to normal scoring. Run via `../StageA/run_stageA.sh`.
- `_master_trades_research.csv` / `_master_runsummary_research.csv` — merged
  results from all 4 real runs.

## Result summary

| RR | Trades | Win% | Expectancy(R) | PF | Long Exp(R) | Short Exp(R) |
|---|---|---|---|---|---|---|
| 1.0 | 290 | 47.2% | +0.044 | 1.11 | +0.05 | +0.04 |
| 1.5 | 272 | 39.7% | +0.057 | 1.12 | +0.14 | -0.03 |
| 2.0 | 261 | 34.9% | +0.080 | 1.16 | +0.15 | +0.01 |
| 3.0 | 246 | 28.5% | +0.056 | 1.10 | +0.11 | +0.00 |

Positive expectancy at every RR tested, same pattern as FastMedConfluence/
FastMedContext/WeightedEnsemble — but short-side is weak-to-flat at RR≥1.5,
consistent with the long/short drift asymmetry flagged in the main Stage A
report. A research-only data point at a relaxed threshold, not a validated
result — not yet subjected to Stage B robustness testing.
