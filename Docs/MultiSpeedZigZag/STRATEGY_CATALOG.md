# Strategy Catalog

Every strategy is a separately measured hypothesis even when multiple strategies describe the same market event.

| ID | Name | Trigger | Context | Family | Status |
|---:|---|---|---|---|---|
| 1001 | Fast Breakout | Fast projected resistance/support break | None required | BREAKOUT | Implemented |
| 1002 | Medium Breakout | Medium projected line break | None required | BREAKOUT | Implemented |
| 1003 | Slow Breakout | Slow projected line break | None required | BREAKOUT | Implemented |
| 1010 | Fast + Medium Confluence | Fast break plus medium break/context | Slow aligned | BREAKOUT | Implemented |
| 1011 | Fast with Medium Context | Fast break | Medium supportive | BREAKOUT | Implemented |
| 1012 | Medium with Slow Context | Medium break | Slow supportive | BREAKOUT | Implemented |
| 1020 | Sequential Confirmation | Fast break followed by medium within a window | Optional slow alignment | BREAKOUT | Reserved (distinct from D027 S1 — see note below) |
| 1030 | Nested Pullback | Fast reversal break | Slow trend, medium correction | PULLBACK | Implemented |
| 1031 | Aligned Fast Pullback Continuation (D027 S1) | Confirmed fast HL/LH after countertrend correction, close through reversal trigger | Slow trend, medium aligned/correcting | PULLBACK | Implemented, default disabled (D027 Stage 3) |
| 1040 | Breakout Retest (D027 S2) | Retest after confirmed break | Original break remains valid | RETEST | Implemented, default disabled (D027 Stage 3) |
| 1050 | Sweep and Reclaim (D027 S3) | Pivot/line sweep then close back through | Structural context | REVERSAL | Implemented, default disabled (D027 Stage 3) |
| 1060 | Compression Breakout (D027 S4) | Contracted fast structure expands | Medium/slow context | COMPRESSION | Implemented, default disabled (D027 Stage 3) |
| 1070 | Structure Transition (D027 S5) | LL/LH to HL/HH or inverse | Multi-speed transition | REVERSAL | Implemented, default disabled (D027 Stage 3) |
| 1080 | Weighted Ensemble | Weighted votes reach threshold | Three-speed evidence | ENSEMBLE | Implemented |

## D027 family classification notes (see DECISION_LOG.md D027 for full rationale)

Per D027's explicit instruction to classify the existing eight and record it here:

- **BREAKOUT family**: FastBreakout (research-only — standard score eligibility not met, per D019), MediumBreakout (previously negative standalone — D023 rejected it from the active production-candidate path; retained here only as a research signal/context event, not a promoted entry), SlowBreakout (weak as a direct entry, potentially useful as regime/state-transition evidence), FastMedConfluence (current core strategy — the sole primary production research candidate per D023/D024), FastMedContext (positive but redundant with FastMedConfluence — D023's overlap analysis found materially negative unique-trade expectancy), MedSlowContext (previously weak as a direct entry).
- **PULLBACK family**: NestedPullback (D023: weak overall and especially poor on shorts — explicitly treated as a prototype, not proof the pullback family lacks edge). D027 S1 (`MSZZ_STRAT_ALIGNED_FAST_PULLBACK`, ID `1031`) is a new, independently-designed pullback hypothesis in the same family, not a modification of NestedPullback.
- **ENSEMBLE family**: WeightedEnsemble (D023: previously positive but redundant with FastMedConfluence — more likely useful as an arbitration/evidence layer than an independent entry family).

## Note on ID 1020 vs. D027 S1

`MSZZ_STRAT_SEQUENTIAL_CONFIRMATION` (`1020`) was reserved by the original architecture for a **different** hypothesis ("fast break followed by medium within a window") than D027's S1 ("Aligned Fast Pullback Continuation," a pullback-then-confirmed-reversal pattern). D027 assigns S1 a new ID (`1031`, adjacent to NestedPullback in the PULLBACK family) rather than reusing `1020`, to avoid silently repurposing an already-documented reserved slot. `1020` remains reserved and unimplemented for its originally-documented meaning.

## Overlap rule

Candidates sharing the same structural origin are supporting interpretations, not automatically separate trades. The suite selects one best candidate for the current event. Future clustering work may combine evidence more formally, but duplicate order placement remains forbidden.

## D027 final research categories

These are research decisions, not implementation-state or production labels:

| Strategy | Final category |
|---|---|
| FastBreakout | RESEARCH_ONLY |
| MediumBreakout | CONTEXT_SIGNAL_ONLY |
| SlowBreakout | CONTEXT_SIGNAL_ONLY |
| FastMedConfluence | STANDALONE_VALIDATION_CANDIDATE |
| FastMedContext | CONTEXT_SIGNAL_ONLY |
| MedSlowContext | CONTEXT_SIGNAL_ONLY |
| NestedPullback | REDESIGN_REQUIRED |
| WeightedEnsemble | CONTEXT_SIGNAL_ONLY |
| AlignedFastPullback | REDESIGN_REQUIRED |
| BreakoutRetest | REJECTED |
| SweepReclaim | RESEARCH_ONLY |
| CompressionBreakout | REJECTED |
| StructureTransition | REJECTED |

No D027 family is a `PORTFOLIO_VALIDATION_CANDIDATE`. Full rationales and
regime-feature categories are machine-readable under `Tools/D027/Final/`.

## D028 addendum — SweepReclaim upgraded to portfolio-validated

D027 left SweepReclaim at `RESEARCH_ONLY` (row above, unchanged as a
historical record of what D027 concluded at the time). D028 subsequently
found SweepReclaim performs strongly as an **independent HEDGING-mode book**
running alongside FastMedConfluence with opposing entries enabled (Stage 4,
certified; see `D028_MULTIBOOK_ARCHITECTURE.md`) — contributing +16.49R to
P3 and +18.49R to P4 as an actually executed portfolio leg, not an arithmetic
addition. D028 Stage 5 additionally screened six exit-management variants
for SweepReclaim and found none that improve on its original fixed-2R exit
(see `D028_FINAL_REPORT.md`). SweepReclaim's D028 status:
**`PORTFOLIO_VALIDATION_CANDIDATE`** (independent-book context, fixed-2R
exit only, opposing entries enabled) — still not a standalone production
recommendation on its own, and still bound by every anti-overfitting caveat
already disclosed in D027 and D028 (within-sample chronological split only,
no genuine independent OOS data, no cost-stress testing performed).

## Required metrics

Each strategy must retain its own count, expectancy, win rate, average adverse excursion, average favorable excursion, holding time, regime, symbol, timeframe, spread, and execution mode. Combined-suite results may never substitute for per-strategy evidence.
