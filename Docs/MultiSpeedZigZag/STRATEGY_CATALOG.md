# Strategy Catalog

Every strategy is a separately measured hypothesis even when multiple strategies describe the same market event.

| ID | Name | Trigger | Context | Status |
|---:|---|---|---|---|
| 1001 | Fast Breakout | Fast projected resistance/support break | None required | Implemented |
| 1002 | Medium Breakout | Medium projected line break | None required | Implemented |
| 1003 | Slow Breakout | Slow projected line break | None required | Implemented |
| 1010 | Fast + Medium Confluence | Fast break plus medium break/context | Slow aligned | Implemented |
| 1011 | Fast with Medium Context | Fast break | Medium supportive | Implemented |
| 1012 | Medium with Slow Context | Medium break | Slow supportive | Implemented |
| 1020 | Sequential Confirmation | Fast break followed by medium within a window | Optional slow alignment | Reserved |
| 1030 | Nested Pullback | Fast reversal break | Slow trend, medium correction | Implemented |
| 1040 | Breakout Retest | Retest after confirmed break | Original break remains valid | Reserved |
| 1050 | Sweep and Reclaim | Pivot/line sweep then close back through | Structural context | Reserved |
| 1060 | Compression Breakout | Contracted fast structure expands | Medium/slow context | Reserved |
| 1070 | Structure Transition | LL/LH to HL/HH or inverse | Multi-speed transition | Reserved |
| 1080 | Weighted Ensemble | Weighted votes reach threshold | Three-speed evidence | Implemented |

## Overlap rule

Candidates sharing the same structural origin are supporting interpretations, not automatically separate trades. The suite selects one best candidate for the current event. Future clustering work may combine evidence more formally, but duplicate order placement remains forbidden.

## Required metrics

Each strategy must retain its own count, expectancy, win rate, average adverse excursion, average favorable excursion, holding time, regime, symbol, timeframe, spread, and execution mode. Combined-suite results may never substitute for per-strategy evidence.