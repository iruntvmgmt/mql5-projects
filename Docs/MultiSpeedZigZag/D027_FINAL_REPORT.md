# D027 Final Report — Regime Architecture and Strategy-Family Expansion

D027 closes as research on `feature/mszz-standalone-suite`. Nothing here
authorizes production. Validation/holdout are chronological partitions of
available broker history, not genuinely independent data.

## Required 40-point report

1. **Starting SHA:** `5ed1e67`, the exact D026-complete branch head.

2. **Final SHA:** the commit containing this report, recorded in Git metadata
   and the final handoff. The last experimental checkpoint is `17bf222`.

3. **Exact A/E reproduction:** A reproduced 224 trades, +0.1261R expectancy,
   PF 1.2446, DD 15.1583R. E reproduced 213, +0.1467R, PF 1.2532, DD
   16.9205R. Both remained untouched controls.

4. **Regime architecture:** Layer 1 is a pure causal classifier; Layer 2 is
   explicit family identity; Layer 3 is stateless eligibility. `LABEL_ONLY`
   is the default/proven no-op. `RESEARCH_FILTER` can affect only enabled D027
   candidates.

5. **Exact definitions:** direction uses slow structure. Alignment priority is
   FULLY_ALIGNED, OPPOSED, PARTIALLY_ALIGNED, MIXED. Trend uses 20-bar
   efficiency at 0.35/0.65. Volatility uses ATR(14)/prior-100 ATR median at
   0.80/1.20. Compression ratio is fast/medium amplitude with 0.35 boundary.
   Phase priority is BREAKOUT, TREND_CONTINUATION, PULLBACK, COMPRESSION,
   TRANSITION, RANGE, UNCLASSIFIED. `FAILED_BREAK` is never emitted.

6. **Causality proof:** inputs are confirmed triple-ZigZag snapshots and
   closed bars only. There is no classifier MT5 data call, future pivot, or
   state. Trade attribution always uses the original entry-time snapshot.

7. **Strategy-family catalog:** the authoritative ID/family mapping is
   `STRATEGY_CATALOG.md`; family is stored, never inferred from a name.

8. **Original-eight assignments:** Fast/Medium/Slow breakout,
   FastMedConfluence, FastMedContext, and MedSlowContext are BREAKOUT;
   NestedPullback is PULLBACK; WeightedEnsemble is ENSEMBLE.

9. **New specifications:** S1 AlignedFastPullback `1031`; S2 BreakoutRetest
   `1040`; S3 SweepReclaim `1050`; S4 CompressionBreakout `1060`; S5
   StructureTransition `1070`. Frozen rules are in `Stage3/README.md` and
   `STATE_MACHINES.md`.

10. **Implementation files:** `RegimeClassifier.mqh`,
    `RegimeEligibilityPolicy.mqh`, `D027StrategyFamilies.mqh`, `Types.mqh`,
    `StrategySuite.mqh`, `OpportunityClusterEngine.mqh`, and
    `MultiSpeedZigZagEA.mq5`, plus D027 tests/tools.

11. **Default-off proof:** five new enable inputs default false; eligibility
    defaults `LABEL_ONLY`; score override, research trail, and partial close
    default off. Shadows and A/E parity prove no-op behavior.

12. **Tests:** EA and all 21 `Test_MSZZ_*` sources compiled with zero
    errors/warnings; all runtime suites passed. D027 adds 14 classifier, 12
    eligibility, and 20 strategy/state assertions.

13. **Shadow regression:** short is 113 raw/46 clusters; long 431/178; both
    zero orders/deals.

14. **Data windows:** development 2025-03-01–2025-12-31; validation
    2026-01-01–2026-04-30; holdout 2026-05-01–2026-07-24. Feed history starts
    2025-02-26, so no materially older unseen block exists.

15. **Regime distribution:** actual phases are BREAKOUT, TREND_CONTINUATION,
    PULLBACK, COMPRESSION, and UNCLASSIFIED. Exact counts are in
    `Stage2/strategy_regime_distribution.csv`; no `FAILED_BREAK` is invented.

16. **Existing performance by regime:** all 2,407 trades join uniquely.
    FastMedConfluence is strongest descriptively in NORMAL strength,
    EXPANDING volatility, OPPOSED alignment, and PULLBACK; phase/alignment
    rankings are not window-stable. Full tables are under `Stage2/`.

17. **New standalone results:** at 2R, AlignedFastPullback 110/-6.9288R;
    BreakoutRetest 354/-37.7759R; SweepReclaim 190/+28.6117R;
    CompressionBreakout 84/-2.7367R; StructureTransition 21/-2.1892R.

18. **2R results:** SweepReclaim alone is positive: +0.1506R expectancy, PF
    1.2688, DD 18.2941R; all windows and both directions positive; +22.6117R
    excluding top three and +13.3449R excluding best quarter.

19. **Qualified 3R:** only SweepReclaim ran. It records 187/+24.3583R,
    +0.1303R expectancy, PF 1.2041, DD 27.6952R. Holdout is -3.7531R and
    excluding best quarter -2.9085R, so 3R is rejected.

20. **Long/short:** SweepReclaim 2R has 96 longs at +0.0808R and 94 shorts at
    +0.2219R expectancy. All side tables are tracked; no side subgroup rescues
    a rejection.

21. **Quarterly/monthly:** Stage 2 tracks existing-strategy months/quarters;
    Stage 4 new-family quarters; Stage 5 2R/3R months/quarters; Stage 6 weak
    core months/rolling periods. SweepReclaim 2R has five positive/two
    negative quarters.

22. **Outliers:** stage artifacts include top-trade and period exclusions.
    Compression's filtered +4.4115R becomes -1.5885R excluding top three and
    -0.1801R excluding its best quarter.

23. **Unique trades:** SweepReclaim 2R has 162 same-bar-unique trades beyond
    the core worth +15.1882R (+0.0938R expectancy); at 3R unique contribution
    falls to +0.9348R.

24. **Core overlap:** Stage 4 reports same-bar and exact-origin overlap.
    D023 already proves FastMedContext/WeightedEnsemble redundant: 91.1%/
    79.3% overlap with negative unique expectancy.

25. **Combined portfolio:** A+Sweep 2R is +20.7400R versus A +28.2447R; DD
    rises 15.1581→25.2798R. E+Sweep 3R is +20.5933R versus E +31.2465R; DD
    rises 16.9204→28.1164R. Both are rejected.

26. **Correlations:** standalone core/Sweep daily returns are 0.1357/0.1947,
    weekly 0.0517/0.1397, monthly 0.4687/0.4079, and daily drawdown levels
    0.1963/0.1767 for A/E pairs. Actual combination still deteriorates.

27. **Regime filters:** filtered trades/R are Aligned 0/0; Retest
    96/-8.9922R; Sweep 0/0; Compression 73/+4.4115R; Transition
    21/-2.1892R. No filter is promoted; `LABEL_ONLY` stays default.

28. **Threshold neighborhoods:** offline entry-time sensitivity changes no
    classifier/execution. FastMedConfluence EXPANDING expectancy at
    1.15/1.20/1.25 is +0.2535/+0.2553/+0.1991R. Sweep changes
    +0.0988/+0.0098/-0.0461R, so that subgroup is unstable. Full adjacent
    volatility/efficiency/compression checks are in
    `Final/threshold_neighborhoods.csv`.

29. **Unknown exits:** zero throughout Stages 4–7. Known exits distinguish
    stop, target, own-family opposite, cross-family opposite, and test-end.

30. **MT5/CSV reconciliation:** every nonzero run reconciles HTML,
    RunSummary, analytics, and deals. Zero-trade Stage 7 HTML reports are 0/0
    and correctly omit trade-only CSVs. Attribution joins are one-to-one.

31. **Persistence limitations:** retest/sweep/compression state persists by
    symbol/timeframe/magic and fails closed if malformed. Transition is
    recomputed from confirmed pivots; S1 is stateless.

32. **Rejected candidates:** BreakoutRetest, CompressionBreakout, and
    StructureTransition are REJECTED; AlignedFastPullback is
    REDESIGN_REQUIRED. Sweep 3R and both portfolio additions are rejected.

33. **Further research:** FastBreakout and SweepReclaim 2R are RESEARCH_ONLY.
    Medium/Slow/MedSlow, FastMedContext, and WeightedEnsemble are
    CONTEXT_SIGNAL_ONLY. NestedPullback/Aligned are REDESIGN_REQUIRED.

34. **OOS candidates:** FastMedConfluence is the sole
    STANDALONE_VALIDATION_CANDIDATE benchmark. No new D027 family qualifies
    without independent OOS; there is no PORTFOLIO_VALIDATION_CANDIDATE.

35. **Edge beyond FastMedConfluence:** none accepted. Sweep has positive
    standalone/unique evidence, but actual A/E combinations reduce R and
    materially increase drawdown.

36. **Future T6/T8:** NORMAL efficiency and EXPANDING volatility are positive
    for the core across all three windows; EXPANDING survives adjacent
    boundaries. This is observer evidence, not an authorized gate. STRONG and
    FULLY_ALIGNED are too sparse/weak.

37. **Artifacts:** tracked work is under `Tools/D027/Stage2`, `Stage4`,
    `Stage5`, `Stage6`, `Stage7`, and `Final`; raw reports are under
    `/Users/matt/MT5-MSZZ-TEST/D027_Stage*_Results`.

38. **Commit SHA:** checkpoints are `26139a1`, `4d2db71`, `e0b2a21`,
    `b878a66`, `e80fda2`, and `17bf222`. This report commit is identified by
    Git metadata/final handoff.

39. **No merge to main:** confirmed; all D027 work remains on the feature
    branch.

40. **No live deployment:** confirmed; tests used only the isolated
    `/Users/matt/MT5-MSZZ-TEST` instance.

## Formal conclusion

Machine-readable categories are in
`Tools/D027/Final/strategy_decision_categories.csv` and
`regime_feature_categories.csv`. No result is production-ready. The causal
observer architecture is retained with `LABEL_ONLY`; the current family
filter policy is rejected. No new D027 family is promoted.
