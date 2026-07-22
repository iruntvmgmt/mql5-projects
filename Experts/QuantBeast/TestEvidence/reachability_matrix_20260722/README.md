# Reachability threshold matrix — 2026-07-22

## Scope

Four all-strategy Shadow runs used XAUUSD M5 true ticks for 2026-06-22.
Every run emitted 880 SignalJournal decisions (220 per strategy). Profiles pin
all matrix-relevant defaults because MT5 can retain unspecified inputs from the
preceding tester job.

| Variant | Main change | BO accepted | TP accepted |
| --- | --- | ---: | ---: |
| Baseline | BO compression 5; trend slope 0.3 | 0 | 0 |
| BO moderate | compression 5 -> 3 | 0 | 0 |
| BO aggressive | compression 5 -> 1 | 0 | 0 |
| TP slope | trend slope 0.3 -> 0.2 | 0 | 0 |
| TP combined | slope 0.2; min efficiency 0.3; HTF off | 0 | 0 |

## Findings

Lowering BO compression moved only 20 of 176 baseline first failures through
that gate. They migrated mainly to HTF alignment/direction, setup location, and
trigger failures; no BO candidate reached arbitration or risk. Compression is
a real constraint, but it is not the sole reason BO is absent in this window.

Lowering the global trend slope threshold moved 18 TP failures out of the
`directional_trend` bucket, but they failed later gates and produced no TP
candidate. The combined TP relaxation moved most newly eligible observations
to `impulse_pullback_structure` (58/220), with two reaching trend persistence.

The classifier is internally inconsistent for calibration experiments:
`TrendState` consumes `InpTrendSlopeThreshold`, while `StructuralState` keeps a
hard-coded `0.3` slope threshold for both impulse and pullback. A `0.2` trend
threshold can therefore label a bar directional while the structure classifier
still refuses the corresponding trend structure. The next controlled change
should make StructuralState consume the same configured threshold, followed by
an untouched baseline regression and a rerun of the TP matrix. This is threshold
coherence, not evidence for removing TP structure checks.

## Exact journal ranges

- BO compression 3: `3,920,024..4,489,046`
- BO compression 1: `4,489,046..5,057,874`
- TP slope 0.2, pinned rerun: `6,196,182..6,766,062`
- TP combined, pinned rerun: `6,766,062..7,335,498`

Earlier unpinned TP slices were discarded after input carryover was detected.
