# D029 Phase 4 — Percentage-Sized Portfolio Comparison

Only SR3-PCT qualified from Phase 3 (SR4-PCT was rejected), so Phase 4
required two new actual EA portfolio runs: `P3_SR3` (FastMedConfluence A 2R
+ SweepReclaim SR3-PCT) and `P4_SR3` (FastMedConfluence E 3R + SweepReclaim
SR3-PCT), both at the frozen $100,000 balance. Controls (`D29_P3`,
`D29_P4`, both SweepReclaim SR0) were already run in Phase 2 and reused,
not rerun. Configs: `d029_phase4_*.ini`. Raw results:
`/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/`. `analyze_portfolios.py`
produces the CSVs in this directory.

## Headline finding: neither P3-SR3 nor P4-SR3 exceeds its matched control on cumulative R

| | D29-P3 (ctrl) | P3-SR3 | D29-P4 (ctrl) | P4-SR3 |
|---|---|---|---|---|
| trades | 342 | 347 | 330 | 335 |
| cum R | +41.6064 | **+29.8514** | +47.6083 | **+35.6172** |
| max DD | 23.9365 | 20.8497 | 24.2455 | 22.6597 |
| Sweep trades | 136 | 139 | 134 | 137 |
| Sweep cum R | +17.4889 | **+4.7340** | +19.4889 | **+5.4978** |

Unlike D028's SR5 (whose standalone drawdown improvement was exactly
canceled out at the portfolio level, DD ending byte-identical to control),
SR3-PCT's drawdown improvement **does partially survive** into the actual
portfolio: -12.9% for P3 (23.94R -> 20.85R), -6.5% for P4 (24.25R ->
22.66R). But this comes at a much larger cost to cumulative R than the
standalone SR3-PCT test alone would predict — SweepReclaim's own portfolio
contribution collapses from +17.49R to +4.73R in P3 (with almost the same
trade count, 136 vs 139), and from +19.49R to +5.50R in P4. This is a
genuine portfolio-specific interaction (occupancy/opposing-book dynamics
change which SweepReclaim signals resolve and how, once a real
FastMedConfluence book is competing for the same account's risk budget) —
exactly the kind of effect the handoff's "do not construct combined
results by arithmetic addition" requirement exists to surface, and it
would be invisible from Phase 3's standalone-only test.

## Weak-core-month behavior

Of D29-A's 5 negative-expectancy months, P3-SR3 improves 3 (2025-05,
2025-11, 2026-03) and worsens 2 (2025-07, 2026-06) relative to the P3
control — a mixed, not clearly favorable, pattern (see
`weak_core_months.csv`).

## Integrity

Zero duplicate logical IDs, zero cross-family actions, maximum observed
portfolio risk 0.4997%/0.4997% (both under the 0.50% cap), account mode
HEDGING throughout, 64/63 partial-close events for P3-SR3/P4-SR3
respectively (see `partial_reconciliation.csv`).

## Classification

**Both P3-SR3 and P4-SR3: `REJECTED`.** The primary Phase 4 gate —
"exceeds matched core on cumulative R" — fails for both, decisively (-28%
and -25% respectively). The drawdown improvement that motivated advancing
SR3-PCT out of Phase 3 is real but far too small to offset the much larger
loss of SweepReclaim's own portfolio-level edge. This reinforces, with a
percent-equity-sized, genuinely-executing partial-close mechanism, exactly
what D028 already found with SR5: **no tested SweepReclaim exit-management
variant has ever improved the actual executed independent-book
portfolio.** D29-P3 and D29-P4 (both SweepReclaim SR0, unmodified exit
management) remain the best percentage-sized portfolios found in D029.
