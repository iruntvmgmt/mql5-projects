# D029 Final Report — Percentage-Risk Sizing, Executable Partial-Leg Validation, and Portfolio Reconciliation

1. **Starting SHA**: `1ff69f918aefe43ce7c213992805be33a9c3be6a` (D028 final,
   on `feature/d028-multibook-portfolio`).
2. **Final SHA**: `e309d2f8ddac89ec769f7826d00fabd71019fa51` (before this
   report's own commit).
3. **Branch**: `feature/d029-percent-risk-partials`.
4. **No merge to `main`**: confirmed — every commit stayed on the D029
   feature branch.
5. **No live deployment**: confirmed — every run used the isolated
   Coinexx-Demo test instance (`/Users/matt/MT5-MSZZ-TEST`), never the
   live install.
6. **Fixed-lot D028 preservation**: confirmed — `InpSizingMode` defaults
   to `MSZZ_SIZE_FIXED_LOT`; every pre-D029 certified result (A, E, SR0,
   P3, P4) reproduces byte-identically on the new binary (verified after
   every phase's EA changes, not assumed).
7. **Percentage-sizing design**: `raw_volume = (equity * risk_pct/100) /
   ((stop_distance/tick_size)*tick_value)`, normalized down only to the
   broker's volume step, never up, never silently forcing the minimum lot
   above requested risk. Implemented in
   `Include/MultiSpeedZigZag/Portfolio/PositionSizing.mqh`
   (`CMSZZPositionSizing`), pure, no MT5 API calls.
8. **Tester balance rationale**: $100,000, the handoff's own suggested
   starting candidate, verified (not assumed) via a pre-result
   volume-resolution projection against D028's certified SweepReclaim
   stop-distance distribution — clears the required 95% partial-capable
   threshold at 100%, the maximum possible margin.
9. **Symbol volume metadata** (XAUUSD, Coinexx-Demo, captured via a new
   read-only `SymbolMetadataProbe.mq5`): `volume_min=0.01`,
   `volume_step=0.01`, `volume_max=100.00`, `tick_size=0.01`,
   `tick_value=1.00`, `contract_size=100`.
10. **Volume-resolution analysis**: projected 6 candidate balances against
    190 canonical SweepReclaim stop distances before any backtest ran;
    $100,000 achieved 100% partial-capability (>=0.02 lots), $50,000 and
    above already exceeded the 95% threshold. Full table:
    `Tools/D029/Phase0/volume_resolution_summary.csv`.
11. **Risk-sizing formula**: see point 7; `requested_risk_money =
    equity_snapshot * risk_pct / 100`, `loss_per_lot =
    (stop_distance/tick_size)*tick_value`.
12. **Volume normalization rule**: floor to the nearest broker volume
    step; reject (not clamp) if the result falls below the broker minimum.
13. **Requested versus actual risk**: actual risk never exceeded requested
    risk across every sizing decision observed in this study (2,802+ in
    Phase 2 alone, plus Phase 3/4) — verified empirically, not merely
    guaranteed by construction.
14. **Minimum-volume rejects**: 7 per A/E-touching run in Phase 2
    (`MIN_VOLUME_REJECT`, ~1.3-3.4% of decisions); **zero** for
    SweepReclaim in every phase (Phase 0's 100% projection held exactly).
15. **D29-A result**: 221 trades, +28.9237R, expectancy 0.1309, PF 1.2520,
    max DD 14.9204R (vs. D028's certified fixed-lot 224 trades, +28.2447R
    — a -3 trade delta fully attributed to `MIN_VOLUME_REJECT` +
    `BOOK_ALREADY_OPEN` cascading).
16. **D29-E result**: 210 trades, +31.9255R, expectancy 0.1520, PF 1.2601,
    max DD 16.9204R (vs. certified 213 trades, +31.2465R — same -3 trade
    pattern).
17. **D29-SR0 result**: 190 trades, +28.6117R, expectancy 0.1506, PF
    1.2688, max DD 18.2941R — **exact match** to the certified fixed-lot
    baseline, proving percent-equity sizing is R-neutral when volume
    resolution is sufficient.
18. **D29-P3 result**: 342 trades, +41.6064R, expectancy 0.1217, PF
    1.2218, max DD 23.9365R (vs. certified fixed-lot 343 trades,
    +39.9275R).
19. **D29-P4 result**: 330 trades, +47.6083R, expectancy 0.1443, PF
    1.2472, max DD 24.2455R (vs. certified fixed-lot 331 trades,
    +45.9294R).
20. **SR3-PCT result** (standalone): 194 trades, +15.6561R, expectancy
    0.0807, PF 1.1776, max DD **14.9477R (-18.3% vs. SR0's 18.2941R)**.
21. **SR4-PCT result** (standalone): 186 trades, +14.7800R, expectancy
    0.0795, PF 1.1752, max DD 19.5860R (worse than SR0).
22. **Successful partial count**: 86 (SR3-PCT), 82 (SR4-PCT).
23. **Failed partial count**: 0 for both — every attempted partial that
    reached the exit-management dispatcher succeeded (the pre-entry
    `PARTIAL_VOLUME_INELIGIBLE` gate filtered out the volume-insufficient
    case before entry, per design, rather than letting a partial attempt
    fail post-entry).
24. **Exact split count**: 0/86 and 0/82 were mathematically exact 50.00%
    (volume-step rounding on odd-step original volumes always produces a
    small deviation, disclosed in Phase 0 before any result existed);
    77/86 and 70/82 fell within 2% of an exact 50/50 split. Executed
    fraction range: 44.4%-50.0% in both variants.
25. **Parent/child reconciliation**: 100% exact — `executed_partial_volume
    + remaining_volume == original_volume` in every one of the 168 total
    partial events, verified via the new `MSZZ_PartialCloseJournal.csv`.
26. **Weighted-R reconciliation**: computed downstream from partial
    price/volume plus each trade's already-proven (D025) volume-weighted
    blended close price in `MSZZ_TradeAnalytics.csv`; not duplicated as
    separate EA-side R-calculation logic.
27. **MFE and giveback**: SR0 avg MFE 1.3003R/giveback 1.1497R; SR3-PCT
    1.1772R/1.0965R; SR4-PCT 1.9826R/1.9031R (SR4-PCT's much higher MFE
    reflects its uncapped runner leg, consistent with its later-diagnosed
    outlier dependence).
28. **Development**: SR0 +17.5830R (123 trades); SR3-PCT +11.4533R (126
    trades); SR4-PCT +5.2988R (120 trades).
29. **Validation**: SR0 +4.4695R; SR3-PCT +0.6198R (positive, but much
    thinner than control); SR4-PCT +3.5033R.
30. **Holdout**: SR0 +6.5592R; SR3-PCT +3.5830R; SR4-PCT +5.9779R.
31. **Long/short**: SR0 0.0808/0.2219; SR3-PCT -0.0035/0.1684 (long
    essentially breakeven under SR3-PCT); SR4-PCT 0.0704/0.0883.
32. **Top-three exclusion**: SR0 remains +0.1209 expectancy excluding top
    3; SR3-PCT remains positive at +0.0506; **SR4-PCT flips negative,
    -0.0721** — the single most important standalone finding of Phase 3.
33. **Best-quarter exclusion**: SR0 +0.0845; SR3-PCT +0.0263 (positive);
    **SR4-PCT -0.0333 (negative)**.
34. **Portfolio comparisons**: P3-SR3 (+29.8514R) vs. P3 control
    (+41.6064R, -28%); P4-SR3 (+35.6172R) vs. P4 control (+47.6083R,
    -25%) — neither exceeds its matched core, the primary Phase 4
    disqualifier for both.
35. **Weak-core-month behavior**: of FastMedConfluence A's 5 negative
    months, P3-SR3 improves 3 and worsens 2 relative to the P3 control — a
    mixed, not clearly favorable, pattern.
36. **Risk-cap behavior**: maximum observed actual portfolio risk 0.4997%
    (P3-SR3) and 0.4997% (P4-SR3), both safely under the frozen 0.50% cap;
    zero risk-cap violations anywhere in D029.
37. **Simultaneous exposure**: P3 control 69 episodes/57.05h vs. P3-SR3 67
    episodes/49.63h; P4 control 74 episodes/60.54h vs. P4-SR3 72
    episodes/53.04h — SR3-PCT's earlier/different exits shift occupancy
    timing measurably.
38. **Cross-family audit**: zero unauthorized cross-family actions across
    every D029 run.
39. **Order failures**: one `ORDER_FAILED` (`retcode=10016 invalid
    stops`) in each of D29-A and D29-E, matching the exact benign category
    D028's Stage 4 checkpoint already documented — not a new defect.
40. **Unknown exits**: zero across every D029 run, every phase.
41. **Sizing architecture category**: **`DUAL_MODE_RECOMMENDED`**.
42. **Partial architecture category**: **`BROKER_PARTIAL_CLOSE_RECOMMENDED`**.
43. **Strategy categories**: SR0-PCT `PORTFOLIO_VALIDATION_CANDIDATE`;
    SR3-PCT `RESEARCH_ONLY`; SR4-PCT `REJECTED`.
44. **Portfolio categories**: D29-P3 `PORTFOLIO_VALIDATION_CANDIDATE`;
    D29-P4 `PORTFOLIO_VALIDATION_CANDIDATE`; P3-SR3 `REJECTED`; P4-SR3
    `REJECTED`.
45. **Remaining production gaps**: (a) no fixed cost/stress scenarios
    (increased spread, adverse slippage, missed fill, delayed stop
    modification) were tested — same disclosed gap D028 left open; (b) no
    genuine independent out-of-sample data exists for this account/symbol
    (within-sample chronological splits only, per D027's original,
    unresolved disclosure); (c) percent-equity sizing produces very large
    nominal positions (up to 15+ lots) on tight-stop FastMedConfluence
    trades — mathematically correct given the frozen formula, but a real
    liquidity/slippage consideration this backtest's constant-cost
    assumption does not model; (d) the portfolio-level mechanism by which
    SweepReclaim's own edge collapses under SR3-PCT in the actual P3/P4
    context (Finding in Phase 4) was observed and reported but not
    root-caused further — a natural follow-on question, out of scope for
    this bounded study.

## Summary

Two real, independent contributions this study set out to make:

**1. Percentage-of-equity sizing works.** Built, tested (41+25 unit
assertions), and empirically validated across every phase: when volume
resolution is sufficient (as SweepReclaim's always was at $100,000),
percent-equity sizing reproduces fixed-lot's certified R-results exactly.
Two real implementation bugs were found only once the engine was exercised
against real backtests for the first time (a leftover fixed-lot exposure
cap; a flawed first attempt at a journal-deduplication fix) — both found,
fixed, and reverified before any result was accepted.

**2. With sizing no longer the blocker, SR3/SR4 could finally be tested as
designed — and the answer is still no.** Both partial variants executed
genuinely this time (168 total partial closes, 100% exact reconciliation).
SR3-PCT (partial + breakeven) is a legitimate, non-overfit standalone
finding — a real, distributed 18% drawdown reduction — but fails the
actual portfolio test: SweepReclaim's own edge collapses in the real P3/P4
context far more than the standalone result predicts, so neither P3-SR3
nor P4-SR3 exceeds its matched core. SR4-PCT (partial + uncapped runner)
fails outright on its own standalone evidence — extreme dependence on a
tiny handful of outsized trades, exactly the pattern the anti-overfitting
rules exist to catch.

**Combined with D028's SR5 finding, D029 is now the second independent
study — under two different sizing regimes, with a genuinely working
partial-close mechanism this time — to conclude that no tested
SweepReclaim exit-management variant improves the actual executed
independent-book portfolio.** P3 and P4 with SweepReclaim's original,
unmodified fixed-2R exit remain the best portfolios found across both
studies. No exit-management change to SweepReclaim is recommended.
`DUAL_MODE_RECOMMENDED` sizing and `BROKER_PARTIAL_CLOSE_RECOMMENDED`
partial architecture are both validated, reusable infrastructure for
future MSZZ research, independent of this specific negative result.
