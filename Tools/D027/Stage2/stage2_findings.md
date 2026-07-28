# D027 Stage 2 deterministic findings

All attribution uses the regime snapshot at the original entry decision. Exit-time regimes are never used. No strategy is gated or promoted.

## Join audit

| Strategy | Trades | Matched | Status |
|---|---:|---:|---|
| FastBreakout | 261 | 261 | PASS |
| MediumBreakout | 513 | 513 | PASS |
| SlowBreakout | 337 | 337 | PASS |
| FastMedConfluence | 224 | 224 | PASS |
| FastMedContext | 235 | 235 | PASS |
| MedSlowContext | 440 | 440 | PASS |
| NestedPullback | 136 | 136 | PASS |
| WeightedEnsemble | 261 | 261 | PASS |

## Full-window strategy totals

| Strategy | Role | Trades | Cumulative R | Expectancy R |
|---|---|---:|---:|---:|
| FastBreakout | raw research trigger | 261 | 20.8403 | 0.0798 |
| MediumBreakout | potential context event | 513 | -21.2636 | -0.0414 |
| SlowBreakout | potential regime/transition evidence | 337 | -4.4264 | -0.0131 |
| FastMedConfluence | breakout benchmark | 224 | 28.2447 | 0.1261 |
| FastMedContext | positive but likely overlapping | 235 | 23.7320 | 0.1010 |
| MedSlowContext | potential higher-order context | 440 | -8.3073 | -0.0189 |
| NestedPullback | existing pullback prototype | 136 | -2.8280 | -0.0208 |
| WeightedEnsemble | potential arbitration/evidence layer | 261 | 20.2880 | 0.0777 |

## FastMedConfluence window totals

| Window | Trades | Cumulative R | Expectancy R |
|---|---:|---:|---:|
| Development | 133 | 13.9368 | 0.1048 |
| Validation | 52 | 6.8843 | 0.1324 |
| Final holdout | 39 | 7.4236 | 0.1903 |
| Full window | 224 | 28.2447 | 0.1261 |

## FastMedConfluence core questions

1. Strongest adequately populated entry-time descriptors were `NORMAL` trend strength (57 trades, +0.4054R expectancy), `EXPANDING` volatility (107, +0.2553R), `OPPOSED` alignment (123, +0.2188R), and `PULLBACK` phase (63, +0.2685R). The tiny `COMPRESSION` phase was higher at +0.4157R but has only 11 trades and is `INSUFFICIENT`.
2. Weakest were `CONTRACTING` volatility (35, -0.3387R), `BREAKOUT` phase (38, -0.1659R), `TREND_CONTINUATION` phase (31, -0.1341R), and `STRONG` trend strength (11, -0.1096R). Only fully aligned (64, -0.0075R) has at least 50 trades among non-positive descriptors.
3. Findings with at least 50 trades are marked `MODERATE_SAMPLE` or `STRONGER_DESCRIPTIVE_SAMPLE` in the CSVs. Validation has 52 total core trades and holdout only 39.
4. Removing `EXPANDING`, the strongest cumulative-R bucket (+27.3122R), leaves +0.9325R. Removing `OPPOSED`, the strongest alignment bucket (+26.9070R), leaves +1.3377R.
5. `NORMAL` trend strength and `EXPANDING` volatility are causal descriptors potentially relevant to later T6/T8 research: both were positive in development, validation, and holdout.
6. Expanded regimes are frequent (107/224), but `STRONG` is rare (11/224) and negative, while `FULLY_ALIGNED` is 64/224 and roughly flat. A combined strong/expanded/aligned runner gate is unsupported.
7. The core remains positive without its strongest bucket, but thinly.
8. The core is positive in all three windows. Volatility/trend findings are directionally consistent, but alignment/phase rankings are not; no filter is justified.

## Existing-eight interpretation

FastBreakout (+0.0798R expectancy) remains a raw research trigger, not production eligible; its holdout was slightly negative. MediumBreakout, SlowBreakout, MedSlowContext, and NestedPullback remain negative full-window and are not rescued by profitable subsets. FastMedContext (+0.1010R) and WeightedEnsemble (+0.0777R) remain positive but previously established as overlapping/redundant with the core. FastMedConfluence remains the benchmark and was positive in every window.

Across buckets with at least 50 trades:

| Strategy | Best | Worst |
|---|---|---|
| FastBreakout | NORMAL trend +0.3614R (60) | FULLY_ALIGNED -0.1038R (76) |
| MediumBreakout | EXPANDING +0.0472R (190) | PARTIALLY_ALIGNED -0.1666R (92) |
| SlowBreakout | EXPANDING +0.1757R (126) | CONTRACTING -0.2879R (75) |
| FastMedConfluence | NORMAL trend +0.4054R (57) | FULLY_ALIGNED -0.0075R (64) |
| FastMedContext | NORMAL trend +0.3691R (58) | FULLY_ALIGNED -0.0370R (67) |
| MedSlowContext | EXPANDING +0.0913R (174) | NORMAL trend -0.1208R (99) |
| NestedPullback | OPPOSED +0.1582R (83) | BULLISH -0.1080R (71) |
| WeightedEnsemble | NORMAL trend +0.3614R (60) | FULLY_ALIGNED -0.0824R (74) |

## Interpretation boundary

Sample labels are descriptive only. Regime subsets do not establish statistical proof, do not rescue losing strategies, and do not authorize a filtered strategy. Canonical A and E remain unchanged.
