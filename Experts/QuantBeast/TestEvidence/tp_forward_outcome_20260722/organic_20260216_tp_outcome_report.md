# TP resume-candidate forward outcome report

Input journals: 1
Windows: 20260216
Total events (pooled): 7

Horizons (3/6/12/24 completed M5 bars) and thresholds (+-0.25/0.50/1.00 ATR) were declared before any evidence was collected and are not re-chosen here.

## Pooled -- TP resume_candidate events

### Pooled (n=7 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 7 | 7 | 0 | 0.567 | 0.503 | 0.883 | 0.957 | 0.642 | -0.763 | -0.544 | 7 | 0.43 | 1 |
| H6 | 7 | 7 | 0 | 0.567 | 0.503 | 1.256 | 1.416 | 0.451 | -0.807 | -0.925 | 7 | 0.43 | 1 |
| H12 | 7 | 7 | 0 | 0.762 | 0.881 | 1.596 | 1.940 | 0.477 | -0.846 | -1.046 | 7 | 0.43 | 1 |
| H24 | 7 | 7 | 0 | 0.914 | 1.001 | 2.348 | 2.760 | 0.389 | -2.019 | -1.590 | 7 | 0.43 | 1 |

**Caution: n=7 is too small for statistical significance. Treat as descriptive only.**

## Per-window -- TP resume_candidate events

### 20260216 (n=7 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 7 | 7 | 0 | 0.567 | 0.503 | 0.883 | 0.957 | 0.642 | -0.763 | -0.544 | 7 | 0.43 | 1 |
| H6 | 7 | 7 | 0 | 0.567 | 0.503 | 1.256 | 1.416 | 0.451 | -0.807 | -0.925 | 7 | 0.43 | 1 |
| H12 | 7 | 7 | 0 | 0.762 | 0.881 | 1.596 | 1.940 | 0.477 | -0.846 | -1.046 | 7 | 0.43 | 1 |
| H24 | 7 | 7 | 0 | 0.914 | 1.001 | 2.348 | 2.760 | 0.389 | -2.019 | -1.590 | 7 | 0.43 | 1 |

**Caution: n=7 is too small for statistical significance. Treat as descriptive only.**


## Baseline B: direction-shuffled TP events (pooled)

Pure post-hoc relabeling of the same bars as if the opposite direction had been nominated (MFE<->MAE, Reached<->ReachedNeg, FirstThreshold flipped, CloseReturn negated). No new data; a sanity baseline only, not an independent sample.

### Direction-shuffled pooled (n=7 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 7 | 7 | 0 | 0.883 | 0.957 | 0.567 | 0.503 | 1.557 | 0.763 | 0.544 | 7 | 0.43 | 1 |
| H6 | 7 | 7 | 0 | 1.256 | 1.416 | 0.567 | 0.503 | 2.215 | 0.807 | 0.925 | 7 | 0.43 | 1 |
| H12 | 7 | 7 | 0 | 1.596 | 1.940 | 0.762 | 0.881 | 2.094 | 0.846 | 1.046 | 7 | 0.43 | 1 |
| H24 | 7 | 7 | 0 | 2.348 | 2.760 | 0.914 | 1.001 | 2.569 | 2.019 | 1.590 | 7 | 0.43 | 1 |

**Caution: n=7 is too small for statistical significance. Treat as descriptive only.**

## Effect-direction-by-window check

Whether any pooled effect depends on a single window or a single event:

- Windows contributing events: 1 (SINGLE WINDOW -- any effect cannot be attributed to more than one window)
- Total events: 7

## Baselines A/C/D (random bars, trend-direction-without-lifecycle, non-resuming impulse)

Not computed by this script -- they require forward OHLC at arbitrary non-resume_candidate anchor bars, which this journal does not carry. See the evidence README for the chart-history retrieval attempt per window.
