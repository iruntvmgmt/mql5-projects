# TP multi-window reachability screen

This package tests whether the existing trend-pullback family can reach a candidate before adding another strategy engine. It is reachability evidence, not a performance claim.

## Valid evidence

| Window | Tick model | Journal byte range | TP rows | TP accepted | Dominant TP blocker |
| --- | --- | --- | ---: | ---: | --- |
| 2025-01-06 | Real ticks (`Model=4`) | `[11937582, 12533566)` | 222 | 0 | Directional trend (120), then impulse/pullback structure (102) |
| 2026-01-05 | Real ticks (`Model=4`) | `[13155226, 13671234)` | 196 | 0 | Directional trend (164), then impulse/pullback structure (30) |
| 2026-05-04 | Real ticks (`Model=4`) | `[13671234, 14474114)` | 304 | 0 | Directional trend (248), then impulse/pullback structure (54) |

Across 722 TP decisions, none reached risk/stop evaluation or acceptance. The
three runs contained 186 TP structure rejections. The legacy first window had
98 `pullback_returning` failures and 90 displacement failures among 102 rows.
The two instrumented windows had 84 structure rows: 22 (26.2%) were actually
moving toward VWAP, 62 were not, and none crossed into the 0.3 ATR value zone.

Other strategies proved the downstream pipeline was reachable: the three
windows accepted ten FBO and four MR signals in total. Complete generated
funnel and structure reports are stored beside this file.

## Excluded attempts

- Fast modeled (`Model=1`) attempts emitted no signal-journal decisions and are excluded because that model did not exercise the feature/strategy path.
- The first 2026-01-05 attempt was externally forced to stop at 19:55 market time while a subsequent run was requested. Its partial journal slice `[12533566, 13155226)` is excluded.
- Several MCP retry attempts are excluded. MT5 treats another
  `tester_run_backtest` call during preliminary tick download as a stop request,
  while still returning ambiguous `job_id=0` results. Only slices with natural
  `test passed` and `thread finished` footers are included above.

## Interpretation

The three completed windows do not support the hypothesis that TP's zero
acceptance is caused by risk or stop management: TP never reached that stage.
Movement toward value exists, so the old location-only name concealed useful
state, but movement alone does not establish a complete pullback-resumption
setup. None of the observed structure rows crossed into the existing value
zone, and displacement also failed 78 of 84 instrumented rows.

Do not replace TP eligibility with `moving_toward_value` based on this sample.
The next TP work should define an explicit impulse → retracement → resumption
event lifecycle and test it as a candidate path before altering production
eligibility.

Risk/stop management is nevertheless a real secondary issue for other
families: completed windows recorded nine FBO and one MR `stop_too_far`
rejections. Those should be analyzed as geometry distributions rather than
weakening the central maximum-stop safety limit.

## Resume protocol

1. Specify TP's observable impulse, retracement, resumption, expiry, and
   invalidation states without future information.
2. Add deterministic positive and negative lifecycle fixtures.
3. Journal candidate lifecycle transitions without changing accepted trades.
4. Compare lifecycle coverage with the 22 movement-toward-value observations.
5. Separately report FBO/MR stop-distance distributions against the unchanged
   central maximum-stop limit.
