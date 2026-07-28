# D027 Stage 7 — frozen regime-filter findings

Five fixed-2R S1–S5 controls were compared with their sole predeclared `RESEARCH_FILTER` counterpart. Raw candidate streams are identical; only the frozen eligibility policy changes.

| Strategy | Control trades | Filtered trades | Control R | Filtered R | R change |
|---|---:|---:|---:|---:|---:|
| AlignedFastPullback | 110 | 0 | -6.928800 | 0.000000 | 6.928800 |
| BreakoutRetest | 354 | 96 | -37.775900 | -8.992200 | 28.783700 |
| SweepReclaim | 190 | 0 | 28.611700 | 0.000000 | -28.611700 |
| CompressionBreakout | 84 | 73 | -2.736700 | 4.411500 | 7.148200 |
| StructureTransition | 21 | 21 | -2.189200 | -2.189200 | 0.000000 |

## Decision

AlignedFastPullback is filtered to zero because the frozen policy's aligned requirement is incompatible with the classifier's causally emitted PULLBACK state. SweepReclaim is filtered to zero exactly as predeclared because `FAILED_BREAK` is not implemented. BreakoutRetest remains negative. StructureTransition is unchanged, so its filter adds no selectivity.

CompressionBreakout improves to 4.411500R over 73 trades, with development / validation / holdout R of 0.787400 / -0.014600 / 3.638700. This is a filtered subset of a losing Stage 4 strategy and is not rescued or promoted by one regime rule.

No frozen regime filter is accepted for production or for A/E. SweepReclaim 2R remains the only positive standalone new family, but its frozen filter is unavailable; LABEL_ONLY remains the global default.
