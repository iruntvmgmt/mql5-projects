# TP resume-candidate forward outcome report

Input journals: 1
Windows: 20260620
Total events (pooled): 1

Horizons (3/6/12/24 completed M5 bars) and thresholds (+-0.25/0.50/1.00 ATR) were declared before any evidence was collected and are not re-chosen here.

## Pooled -- TP resume_candidate events

### Pooled (n=1 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 1 | 1 | 0 | 2.225 | 2.225 | 0.121 | 0.121 | 18.388 | 1.380 | 1.380 | 1 | 1.00 | 0 |
| H6 | 1 | 1 | 0 | 2.225 | 2.225 | 2.101 | 2.101 | 1.059 | -0.779 | -0.779 | 1 | 1.00 | 0 |
| H12 | 1 | 1 | 0 | 2.225 | 2.225 | 2.101 | 2.101 | 1.059 | -0.889 | -0.889 | 1 | 1.00 | 0 |
| H24 | 1 | 1 | 0 | 4.159 | 4.159 | 2.101 | 2.101 | 1.980 | 3.044 | 3.044 | 1 | 1.00 | 0 |

**Caution: n=1 is too small for statistical significance. Treat as descriptive only.**

## Per-window -- TP resume_candidate events

### 20260620 (n=1 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 1 | 1 | 0 | 2.225 | 2.225 | 0.121 | 0.121 | 18.388 | 1.380 | 1.380 | 1 | 1.00 | 0 |
| H6 | 1 | 1 | 0 | 2.225 | 2.225 | 2.101 | 2.101 | 1.059 | -0.779 | -0.779 | 1 | 1.00 | 0 |
| H12 | 1 | 1 | 0 | 2.225 | 2.225 | 2.101 | 2.101 | 1.059 | -0.889 | -0.889 | 1 | 1.00 | 0 |
| H24 | 1 | 1 | 0 | 4.159 | 4.159 | 2.101 | 2.101 | 1.980 | 3.044 | 3.044 | 1 | 1.00 | 0 |

**Caution: n=1 is too small for statistical significance. Treat as descriptive only.**


## Baseline B: direction-shuffled TP events (pooled)

Pure post-hoc relabeling of the same bars as if the opposite direction had been nominated (MFE<->MAE, Reached<->ReachedNeg, FirstThreshold flipped, CloseReturn negated). No new data; a sanity baseline only, not an independent sample.

### Direction-shuffled pooled (n=1 events)

| Horizon | n | n_complete | n_truncated | Median MFE | Mean MFE | Median MAE | Mean MAE | Fav/Adv ratio | Median close-ret | Mean close-ret | n resolved | Target-before-adverse rate | n ambiguous |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H3 | 1 | 1 | 0 | 0.121 | 0.121 | 2.225 | 2.225 | 0.054 | -1.380 | -1.380 | 1 | 0.00 | 0 |
| H6 | 1 | 1 | 0 | 2.101 | 2.101 | 2.225 | 2.225 | 0.944 | 0.779 | 0.779 | 1 | 0.00 | 0 |
| H12 | 1 | 1 | 0 | 2.101 | 2.101 | 2.225 | 2.225 | 0.944 | 0.889 | 0.889 | 1 | 0.00 | 0 |
| H24 | 1 | 1 | 0 | 2.101 | 2.101 | 4.159 | 4.159 | 0.505 | -3.044 | -3.044 | 1 | 0.00 | 0 |

**Caution: n=1 is too small for statistical significance. Treat as descriptive only.**

## Effect-direction-by-window check

Whether any pooled effect depends on a single window or a single event:

- Windows contributing events: 1 (SINGLE WINDOW -- any effect cannot be attributed to more than one window)
- Total events: 1 (SINGLE EVENT -- any effect cannot be attributed to more than one observation)

## Baselines A/C/D (random bars, trend-direction-without-lifecycle, non-resuming impulse)

Not computed by this script -- they require forward OHLC at arbitrary non-resume_candidate anchor bars, which this journal does not carry. See the evidence README for the chart-history retrieval attempt per window.
