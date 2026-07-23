# TP resume-candidate forward outcome report

Input journals: 1
Windows: 20260126
Total events (pooled): 3

Horizons (3/6/12/24 completed M5 bars) and thresholds (+-0.25/0.50/1.00 ATR) were declared before any evidence was collected and are not re-chosen here.

## Pooled -- TP resume_candidate events

### Pooled (n=3 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 3 | 3 | 0 | 1.794 | 2.041 | 0.407 | 0.604 | 4.408 | 1.287 | 0.576 | 3 | 0.33 | 2 |
| H6 | 3 | 3 | 0 | 1.794 | 2.041 | 0.451 | 0.754 | 3.978 | 0.019 | 0.457 | 3 | 0.33 | 2 |
| H12 | 3 | 3 | 0 | 2.037 | 2.528 | 1.404 | 1.096 | 1.451 | 0.220 | 0.609 | 3 | 0.33 | 2 |
| H24 | 3 | 3 | 0 | 3.754 | 4.107 | 1.404 | 1.123 | 2.674 | 2.237 | 2.842 | 3 | 0.33 | 2 |

**Caution: n=3 is too small for statistical significance. Treat as descriptive only.**

## Per-window -- TP resume_candidate events

### 20260126 (n=3 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 3 | 3 | 0 | 1.794 | 2.041 | 0.407 | 0.604 | 4.408 | 1.287 | 0.576 | 3 | 0.33 | 2 |
| H6 | 3 | 3 | 0 | 1.794 | 2.041 | 0.451 | 0.754 | 3.978 | 0.019 | 0.457 | 3 | 0.33 | 2 |
| H12 | 3 | 3 | 0 | 2.037 | 2.528 | 1.404 | 1.096 | 1.451 | 0.220 | 0.609 | 3 | 0.33 | 2 |
| H24 | 3 | 3 | 0 | 3.754 | 4.107 | 1.404 | 1.123 | 2.674 | 2.237 | 2.842 | 3 | 0.33 | 2 |

**Caution: n=3 is too small for statistical significance. Treat as descriptive only.**


## Baseline B: direction-shuffled TP events (pooled)

Pure post-hoc relabeling of the same bars as if the opposite direction had been nominated (MFE<->MAE, Reached<->ReachedNeg, FirstThreshold flipped, CloseReturn negated). No new data; a sanity baseline only, not an independent sample.

### Direction-shuffled pooled (n=3 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 3 | 3 | 0 | 0.407 | 0.604 | 1.794 | 2.041 | 0.227 | -1.287 | -0.576 | 3 | 0.00 | 2 |
| H6 | 3 | 3 | 0 | 0.451 | 0.754 | 1.794 | 2.041 | 0.251 | -0.019 | -0.457 | 3 | 0.00 | 2 |
| H12 | 3 | 3 | 0 | 1.404 | 1.096 | 2.037 | 2.528 | 0.689 | -0.220 | -0.609 | 3 | 0.00 | 2 |
| H24 | 3 | 3 | 0 | 1.404 | 1.123 | 3.754 | 4.107 | 0.374 | -2.237 | -2.842 | 3 | 0.00 | 2 |

**Caution: n=3 is too small for statistical significance. Treat as descriptive only.**

## Effect-direction-by-window check

Whether any pooled effect depends on a single window or a single event:

- Windows contributing events: 1 (SINGLE WINDOW -- any effect cannot be attributed to more than one window)
- Total events: 3

## Baselines A/C/D (random bars, trend-direction-without-lifecycle, non-resuming impulse)

Not computed by this script -- they require forward OHLC at arbitrary non-resume_candidate anchor bars, which this journal does not carry. See the evidence README for the chart-history retrieval attempt per window.
