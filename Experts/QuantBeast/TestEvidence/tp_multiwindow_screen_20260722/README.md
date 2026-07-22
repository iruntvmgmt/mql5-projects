# TP multi-window reachability screen

This package tests whether the existing trend-pullback family can reach a candidate before adding another strategy engine. It is reachability evidence, not a performance claim.

## Valid evidence

| Window | Tick model | Journal byte range | TP rows | TP accepted | Dominant TP blocker |
| --- | --- | --- | ---: | ---: | --- |
| 2025-01-06 | Real ticks (`Model=4`) | `[11937582, 12533566)` | 222 | 0 | Directional trend (120), then impulse/pullback structure (102) |

The structure decomposition for the 102 TP structure rows found 98 `pullback_returning` failures and 90 displacement failures. No TP observation reached risk/stop evaluation. The same combined run did accept four FBO and one MR signal, confirming that strategy evaluation and downstream acceptance were reachable.

See `01_20250106.md` and `01_20250106_structure.md` for the generated reports.

## Excluded attempts

- Fast modeled (`Model=1`) attempts emitted no signal-journal decisions and are excluded because that model did not exercise the feature/strategy path.
- The first 2026-01-05 attempt was externally forced to stop at 19:55 market time while a subsequent run was requested. Its partial journal slice `[12533566, 13155226)` is excluded.
- After the forced stop, the MT5 MCP reported `job_id=0`/stopped and acknowledged launches without dispatching work. The native `/config:` fallback initialized and reported `automatic testing started`, but the controller did not assign a job to the local tester agent. Recycling the terminal and local agents did not restore dispatch during this session.
- No 2026-05-04 evidence was emitted.

## Interpretation

The valid window does not support the hypothesis that TP's zero acceptance is caused by risk or stop management: TP never reached that stage. It instead nominates event-state and pullback-return detection for audit. This does not rule out risk/stop defects in other families; the partial 2026 run contained two FBO `stop_too_far` rejects, but that slice is not accepted as a complete comparison window.

## Resume protocol

1. Start MT5 normally and confirm a local tester agent is registered.
2. Run the 2026-01-05 profile to natural `test passed` / `thread finished` completion before launching another profile.
3. Record exact SignalJournal start and end byte offsets.
4. Generate both reports with `acceptance_funnel_report.py` and `tp_structure_report.py`.
5. Repeat for 2026-05-04, then aggregate only naturally completed slices.
