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

## Organic-run attempt

The intended XAUUSD M5 `Model=4` 2026-01-05 run was requested through the
native tester MCP after the compile/regression evidence above. The initial
request overlapped the preceding regression agent's delayed shutdown and never
loaded a profile. After `MetaTester 5 stopped` appeared, later clean requests
alternated between `{ok:false, job_id:0}` and `{ok:true, job_id:0}` but created
no tester process, new controller/agent-log section, or signal-journal bytes.
The signal journal remained exactly 15,520,142 bytes. Therefore no organic
result is claimed and no report was generated from a nonexistent slice. This
matches the already documented intermittent native tester no-execution mode;
the next session should retry only after confirming fresh agent-log growth.
