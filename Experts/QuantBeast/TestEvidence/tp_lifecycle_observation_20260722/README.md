# TP observational lifecycle

## Purpose

The multi-window screen showed that isolated near-VWAP or movement-toward-VWAP
flags do not describe a complete trend-pullback event. This change introduces
event sequencing as instrumentation before any entry redesign.

## Lifecycle

```text
idle → impulse → retracing → resume_candidate
          └───────────────→ expired
any active phase ─────────→ invalidated
```

- `impulse`: directional trend plus `STRUCTURE_IMPULSE`.
- `retracing`: the same directional context subsequently contracts its
  absolute VWAP distance.
- `resume_candidate`: after retracing, VWAP distance stops contracting and the
  completed candle realigns with the original trend direction.
- `expired`: pullback observation exceeds `InpTP_MaxPullbackBars`.
- `invalidated`: trend direction/context changes or event state is not normal.

These are observational labels only. No phase can authorize a signal.

## Verification

- Compile: `0 errors, 0 warnings`, 2026-07-22 11:30:22.
- Deterministic Test 64 covers sequencing, same-snapshot idempotence, and trend
  reversal invalidation.
- Shadow regression: `67 passed, 0 failed`; 22,080 generated ticks, 1,104
  bars; final balance 10,000 USD; natural `test passed` / `thread finished`.
- No broker orders were transmitted.
- The report parser accepts legacy rows and synthetic lifecycle-formatted rows.

## First organic observation

The naturally completed 2026-01-05 rerun covered 372,741 ticks and the exact
journal slice `[14474114, 14991982)`. All 30 structure-rejection rows reported
`idle`. Review then found that lifecycle phase was only present on the
structure-rejection path; two earlier TP rejection paths in the same run could
therefore conceal lifecycle starts. The journal instrumentation was corrected
so every TP rejection now carries phase and phase age. The incomplete-coverage
run is preserved in `organic_funnel.md` and `organic_lifecycle.md`, but is not
accepted as full lifecycle reachability evidence.

After the coverage fix, compile remained `0 errors, 0 warnings` and the Shadow
regression again completed with `67 passed, 0 failed`. A fresh organic slice is
still required.

## Full-coverage organic result

The fresh 2026-01-05 run completed naturally over 372,741 ticks. Exact journal
range: `[14991982, 15520142)`. All 196 TP decisions carried lifecycle metadata;
all 196 were `idle` with phase age zero. TP again produced zero accepted or
risk-evaluated signals, while FBO and MR each accepted three.

This isolates lifecycle reachability: no `STRUCTURE_IMPULSE` observation
occurred, so the lifecycle never started. Retracement and resumption rules were
not reached organically and cannot yet be judged. Do not loosen the shared
structural displacement threshold merely to start the tracker; prior threshold
probes already showed state preemption and weak displacement. The next research
step is to define and instrument a TP-specific, observable impulse leg with
price/time anchors, without changing accepted signals.

Reports: `organic_full_coverage_funnel.md` and
`organic_full_coverage_lifecycle.md`.

## Hashes

- `QuantBeastEA.mq5`: `95cda300c9d10558b00c18f121951972b79e5bf15a26dfe0347a160305aaea70`
- `QuantBeastEA.ex5`: `371d1d157273441540dd9dd834cb941dc9fac01c525a64883d0e07fe2461f934`
- `TrendPullbackEngine.mqh`: `55009459dc58efc8ee3aebd7ca8b53885fd8ffc29ab0d2a2827e157a352d92e0`
- `SafetyTests.mqh`: `bb795f1d09e20b6e4813a129821bef558c5aadb11e3e569d23f87e3955cc9726`
