# D028 Stage 3 — Single-Book Equivalence

Stage 3 activates one independently accountable book at a time in the isolated
HEDGING tester. No combined configuration was run.

## Exact controls

| Book | Target | Trades | Cumulative R | Expectancy R | PF | Max DD R | Long | Short |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FastMedConfluence A | 2R | 224 | 28.2447 | 0.1261 | 1.2446 | 15.1581 | 107 | 117 |
| FastMedConfluence E | 3R | 213 | 31.2465 | 0.1467 | 1.2532 | 16.9204 | 101 | 112 |
| SweepReclaim | 2R | 190 | 28.6117 | 0.1506 | 1.2688 | 18.2941 | 96 | 94 |

All three trade-analytics files are byte-identical to their certified controls.
This covers entry and exit timestamps, exit reasons, direction, R, MFE/MAE,
holding time, and session.

## Attribution audit

- Certified trades: 627
- Portfolio logical trades: 627
- Missing IDs: 0
- Unexpected IDs: 0
- Duplicate IDs: 0
- Direction mismatches: 0
- Entry-time mismatches: 0
- Exit-time mismatches: 0
- Maximum absolute R difference: below 0.00005R (four-decimal display rounding)

The initial A run revealed that opposite-signal closures were absent from the
new logical journal. That run was not accepted. Closure export was corrected,
A was rerun, and all 224 logical rows reconciled before E or SweepReclaim
evidence was accepted.

## Verification

- EA compile: 0 errors, 0 warnings
- Test-script compiles: 27/27 clean
- Runtime suites: 27/27 passed
- Short shadow: 113 candidates / 46 clusters / 0 malformed / 0 trades
- Long shadow: 431 candidates / 178 clusters / 0 malformed / 0 trades
- Analyzer repeated twice with byte-identical outputs
- Live account/deployment: none

`analyze_stage3.py` regenerates the equivalence, window, and logical-join CSVs
from the exact external result and certified-control paths.

Stage 4 remains blocked from this change set. It must separately introduce
distinct simultaneous book magics and run actual combined portfolio controls.
