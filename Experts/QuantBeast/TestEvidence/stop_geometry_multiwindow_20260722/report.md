# QuantBeast stop-geometry report

Completed journal slices: 3

Point size: 0.01

Central maximum stop: 1000 points

Only accepted signals and central risk/stop rejections with proposed geometry are included.

## Geometry distribution

| Strategy | Outcome | Rows | Min points | Median points | Max points | Min ATR | Median ATR | Max ATR |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FBO | accepted | 10 | 231.00 | 728.50 | 986.00 | 1.39 | 1.76 | 2.33 |
| FBO | risk_rejected | 9 | 1138.00 | 1499.00 | 2181.00 | 1.57 | 2.21 | 2.90 |
| MR | accepted | 4 | 156.00 | 258.00 | 435.00 | 0.63 | 0.90 | 0.97 |
| MR | risk_rejected | 1 | 1006.00 | 1006.00 | 1006.00 | 0.75 | 0.75 | 0.75 |

## Counts by completed window

| Window | Strategy | Accepted | Risk rejected |
| --- | --- | --- | --- |
| 2025-01-06 | FBO | 4 | 0 |
| 2025-01-06 | MR | 1 | 0 |
| 2026-01-05 | FBO | 3 | 2 |
| 2026-01-05 | MR | 3 | 0 |
| 2026-05-04 | FBO | 3 | 7 |
| 2026-05-04 | MR | 0 | 1 |

## Excess over central maximum

| Strategy | Rows | Min excess | Median excess | Max excess |
| --- | --- | --- | --- | --- |
| FBO | 9 | 138.00 | 499.00 | 1181.00 |
| MR | 1 | 6.00 | 6.00 | 6.00 |

## Interpretation boundary

This is conditional on signals that reached final geometry. It does not describe strategy-rejected observations and does not prove that a wider stop would be profitable. The central safety limit must not be changed from this report alone.
