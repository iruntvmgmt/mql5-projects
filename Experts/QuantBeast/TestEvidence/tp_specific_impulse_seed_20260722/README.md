# TP-specific observational impulse seed — 2026-07-22

## Purpose

The preceding full-coverage organic slice contained 196 TP decisions, all in
`idle`, because shared `STRUCTURE_IMPULSE` was never observed. This change adds
an anchored TP-specific research seed without changing production eligibility,
trade geometry, arbitration, risk, or order routing.

## Implementation boundary

- Shared `STRUCTURE_IMPULSE` remains the primary seed.
- The fallback requires directional context, an aligned completed candle, the
  configured TP persistence and directional-efficiency floors, and displacement
  of at least 0.30 ATR.
- The fixed 0.30 ATR value is an observational research threshold, not a
  production input.
- Journal fields record lifecycle phase/age, seed source, impulse start epoch,
  completed-bar open, directional extreme, and ATR-normalized span.
- Lifecycle state cannot authorize a TP candidate.

## Verification

- The first compile exposed an invalid `LongToString` call: 2 errors and 6
  dependent warnings. It was corrected to MQL5-supported `StringFormat`.
- Final MetaEditor compile: **0 errors, 0 warnings**.
- Shadow regression: **67 passed, 0 failed**; 22,080 generated ticks and 1,104
  bars; normal completion.
- Test 64 proves the existing structural lifecycle plus a balanced-structure
  TP-specific seed with source, time, start price, and ATR span anchors.
- `tp_structure_report.py` passed Python syntax validation and an anchored
  synthetic-row parser check.

## Artifact hashes

```text
QuantBeastEA.mq5                 95cda300c9d10558b00c18f121951972b79e5bf15a26dfe0347a160305aaea70
QuantBeastEA.ex5                 510c55f79c7f407fba24b0c66afec67b5ba5a5acc2bee184aa4049091fa36333
TrendPullbackEngine.mqh          d0ae44cba628447852b8e081a8a056b67795319340d30a1c3e922d4aa612b18b
SafetyTests.mqh                  fe7b9aee78491a820eb7ccb27edc511d08ac7e2117f0bb2d34b474ba83bc4a82
tp_structure_report.py           5935c5b784bb2d1bbf2753ad0c9154dba0df7f2c1c1356c8c2724128c7346ac6
```

## Conclusion

Deterministic reachability and diagnostic serialization are proven. Natural
market reachability is not; it requires a fresh exact-byte-bounded organic run.
Readiness remains `READY FOR SHADOW MODE`.

## Organic-run result

The native launcher initially appeared to remain in its documented
`job_id: 0` no-execution mode, but the final clean request started after a
delay and completed naturally. The authoritative agent footer records XAUUSD
M5, `Model=4`, 2026-01-05, 372,741 ticks, 276 bars, `OnTester result 0`,
`test passed`, and `thread finished`. The exact signal-journal slice is
`[15520142,16093698)`.

The slice contains 196 TP decisions and zero TP risk/stop evaluations or
accepted signals. Lifecycle coverage was:

| Phase | Rows |
| --- | ---: |
| idle | 114 |
| invalidated | 64 |
| impulse | 14 |
| retracing | 4 |
| resume_candidate | 0 |

All 82 non-empty seed annotations were `tp_specific`; median observed impulse
span was 0.842 ATR and maximum was 2.615 ATR. Because long and short evaluations
share one completed-bar snapshot, row counts occur in direction pairs. The two
retracing snapshots continued moving toward value and were followed by loss of
directional trend context, so the lifecycle invalidated before resumption.

This proves natural seed, impulse, retracement, anchor, and serialization
reachability. It does not prove a resumption entry. Reports:

- `organic_tp_structure_report.md`
- `organic_acceptance_funnel.md`

## Independent-window extension

Two additional one-day `Model=4` Shadow windows completed naturally with exact
journal bounds and unchanged observational logic:

| Window | Exact slice | TP rows | Impulse | Retracing | Resume candidate | TP risk/stop | TP accepted |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2026-01-05 | `[15520142,16093698)` | 196 | 14 | 4 | 0 | 0 | 0 |
| 2025-01-06 | `[16093698,16891238)` | 264 | 30 | 24 | 8 | 0 | 0 |
| 2026-05-04 | `[16891238,17787378)` | 304 | 30 | 2 | 2 | 0 | 0 |
| **Total** | | **764** | **74** | **30** | **10** | **0** | **0** |

Aggregate phase rows were 298 idle, 352 invalidated, 74 impulse, 30
retracing, and 10 resume candidate. Aggregate seed annotations were 298 none,
370 TP-specific, and 96 structural. Direction-paired strategy evaluation means
the 10 resume rows represent five completed-bar observations, not ten
independent setups.

The 2025 and May 2026 windows prove that the full observational lifecycle is
naturally reachable in independent samples. They do not justify production
candidate logic: lifecycle direction is not yet serialized, and no forward
counterfactual outcome has been measured for the five resumption observations.
The next instrumentation step is explicit lifecycle-direction attribution,
followed by side-effect-free outcome tracking.

Additional reports:

- `organic_20250106_tp_structure_report.md`
- `organic_20250106_acceptance_funnel.md`
- `organic_20260504_tp_structure_report.md`
- `organic_20260504_acceptance_funnel.md`
