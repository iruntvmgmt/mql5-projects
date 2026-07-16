# Performance Readiness Evidence - 2026-07-16

Purpose: reproducible Shadow-mode performance-test readiness baselines. These are broker-free correctness/performance baselines, not optimization evidence and not a profitability claim.

## Build under test

- Source SHA-256: `220577a689c55b7ee263e0bae779752b610e0c75ca3f5ff528d2bb473a0ce30a`
- EX5 SHA-256: `fca02855e1396c768c974b3ce2650beb45f4af51f81f9d14f4ed714be8590040`
- Latest compile gate before these runs: 0 errors, 0 warnings.
- Latest deterministic Shadow regression before these runs: 38 passed, 0 failed.

## Config set

See `README.md` in this directory. Configs are XAUUSD M5, Model=4/every tick based on real ticks, Shadow mode (`InpMode=1`), challenge acknowledgement false, self-tests/persistence/global variables/news/dashboard/debug disabled, and signal/order/trade journals enabled.

## Combined training baseline

Configuration: `QuantBeast.Perf.Combined.Train.XAUUSD.M5.20260622_20260626.ini`

Pre-run byte boundaries:

- SignalJournal.csv: 348570
- OrderJournal.csv: 924
- TradeJournal.csv: 1400
- Agent log: 349734
- Main tester log: 323024

Tester result from the new agent-log section:

- Model: every tick based on real ticks.
- Period: XAUUSD M5, 2026.06.22 00:00 to 2026.06.26 00:00.
- Ticks/bars: 1,736,377 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:14:42.937, plus history synchronization.
- Final balance: 10000.00 USD.
- OnTester result: 0.

New journal suffix metrics:

- Signal rows: 3,760.
- Signal status: 3,755 REJECTED, 5 ACCEPTED.
- Strategy coverage: BO 940 rows, FBO 940 rows, TP 940 rows, MR 940 rows.
- Accepted signals: FBO BUY 3, FBO SELL 2.
- Rejected signals: BUY 1,877, SELL 1,878.
- Signal IDs missing direction: 0.
- Order journal rows: 5 (`ORDER_TYPE_BUY` 3, `ORDER_TYPE_SELL` 2).
- Trade journal rows: 5 (`LONG` 3, `SHORT` 2).
- Closed-trade net sum: -193.03.
- Gross profit/loss: 115.26 / 308.29.
- Profit factor: 0.373869.
- Closed-trade running max drawdown: 308.29.

Evidence files:

- `combined_train_metrics.csv`
- `SignalJournal_combined_train_suffix.csv`
- `OrderJournal_combined_train_suffix.csv`
- `TradeJournal_combined_train_suffix.csv`
- `SignalJournal_combined_train_excerpt.txt`
- `OrderJournal_combined_train_excerpt.txt`
- `TradeJournal_combined_train_excerpt.txt`
- `accepted_signal_rows_combined_train.csv`
- `selected_rejected_signal_rows_combined_train_excerpt.csv`

Interpretation:

- Combined training proves the reusable performance baseline can run in Shadow using true ticks where local history exists.
- Only FBO reached accepted trade state in this window; BO/TP/MR participation is visible as rejected candidate rows, not accepted trade coverage.
- The negative result is recorded as an observed baseline only; it is not an optimization input and does not by itself prove or disprove strategy edge.

## Combined holdout baseline

Configuration: `QuantBeast.Perf.Combined.Holdout.XAUUSD.M5.20260629_20260703.ini`

First attempt status: invalid/incomplete. The run launched and appended journal rows, but the terminal/tester process did not produce the normal final tester footer (`final balance`, `OnTester result`, `test passed`, ticks/bars summary) and the signal suffix ended at `2026.06.29 21:55:00`, well before the configured end time `2026.07.03 00:00`.

Pre-run byte boundaries:

- SignalJournal.csv: 1428830
- OrderJournal.csv: 2028
- TradeJournal.csv: 3134
- Agent log: 397992
- Main tester log: 370548

Partial journal suffix metrics, preserved only as failed-run evidence:

- Signal rows: 1,248.
- Signal first/last times: 2026.06.29 06:00:00 to 2026.06.29 21:55:00.
- Signal status: 1,245 REJECTED, 3 ACCEPTED.
- Strategy coverage in the partial suffix: BO 312 rows, FBO 312 rows, TP 312 rows, MR 312 rows.
- Accepted signals: FBO BUY 2, FBO SELL 1.
- Signal IDs missing direction: 0.
- Order journal rows: 3 (`ORDER_TYPE_BUY` 2, `ORDER_TYPE_SELL` 1).
- Trade journal rows: 3 (`LONG` 2, `SHORT` 1).
- Closed-trade net sum: -12.74.
- Profit factor: 0.873284.

Evidence files:

- `combined_holdout_metrics.csv`
- `SignalJournal_combined_holdout_suffix.csv`
- `OrderJournal_combined_holdout_suffix.csv`
- `TradeJournal_combined_holdout_suffix.csv`
- `SignalJournal_combined_holdout_excerpt.txt`
- `OrderJournal_combined_holdout_excerpt.txt`
- `TradeJournal_combined_holdout_excerpt.txt`
- `accepted_signal_rows_combined_holdout.csv`

First-attempt interpretation:

- The holdout config exists and was partially exercised, but this is not a complete holdout pass.
- The likely operational blocker was stale/unstable terminal/tester state; no profitability or holdout verdict is claimed from this partial attempt.

## Combined holdout clean retry

Retry configuration: `QuantBeast.Perf.Combined.Holdout.Retry.XAUUSD.M5.20260629_20260703.ini`, staged temporarily in `MQL5/Profiles/Tester` and removed after the run.

Pre-run byte boundaries:

- SignalJournal.csv: 2071624
- OrderJournal.csv: 3572
- TradeJournal.csv: 5526
- Agent log: 431006
- Main tester log: 405784

Tester result from the new agent-log section:

- Model: every tick based on real ticks.
- Period: XAUUSD M5, 2026.06.29 00:00 to 2026.07.03 00:00.
- Ticks/bars: 1,464,441 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:12:54.454, plus history synchronization.
- Final balance: 10000.00 USD.
- OnTester result: 0.

New retry journal suffix metrics:

- Signal rows: 4,520.
- Signal first/last times: 2026.06.29 06:00:00 to 2026.07.02 21:55:00.
- Signal status: 4,510 REJECTED, 10 ACCEPTED.
- Strategy coverage: BO 1,130 rows, FBO 1,130 rows, TP 1,130 rows, MR 1,130 rows.
- Accepted signals: FBO BUY 8, FBO SELL 2.
- Signal IDs missing direction: 0.
- Order journal rows: 10 (`ORDER_TYPE_BUY` 8, `ORDER_TYPE_SELL` 2).
- Trade journal rows: 10 (`LONG` 8, `SHORT` 2).
- Closed-trade net sum: 64.66.
- Gross profit/loss: 279.82 / 215.16.
- Profit factor: 1.300521.
- Closed-trade running max drawdown: 114.62.

Evidence files:

- `combined_holdout_retry_metrics.csv`
- `SignalJournal_combined_holdout_retry_suffix.csv`
- `OrderJournal_combined_holdout_retry_suffix.csv`
- `TradeJournal_combined_holdout_retry_suffix.csv`
- `SignalJournal_combined_holdout_retry_excerpt.txt`
- `OrderJournal_combined_holdout_retry_excerpt.txt`
- `TradeJournal_combined_holdout_retry_excerpt.txt`
- `accepted_signal_rows_combined_holdout_retry.csv`

Retry interpretation:

- The clean retry completed the configured holdout window and produced a normal tester footer.
- This is still not a profitability claim. It is one untouched holdout baseline observation after a fixed configuration set; no parameter optimization was performed.
- Only FBO reached accepted trade state in this window; BO/TP/MR participation is visible as rejected candidate rows, not accepted trade coverage.

## Independent strategy training baselines

All four strategy-only train configs were run independently on the same XAUUSD M5 true-tick train window (`2026.06.22` to `2026.06.26`) in Shadow mode with challenge acknowledgement false and self-tests disabled. Temporary `Profiles/Tester` launcher copies were removed after each run.

### BO-only train

Configuration: `QuantBeast.Perf.BO.Train.XAUUSD.M5.20260622_20260626.ini`

- Ticks/bars: 1,736,377 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:14:38.163.
- Final balance: 10000.00 USD.
- Signal rows: 940.
- Signal status: 940 REJECTED, 0 ACCEPTED.
- Direction coverage: 470 BUY rejected, 470 SELL rejected.
- Signal IDs missing direction: 0.
- Order/trade rows: 0 / 0.
- Top rejection reasons: `Breakout: not eligible` 830, `Breakout Long: HTF bias is not up` 55, `Breakout Short: no trigger` 27, `Breakout Short: price not near lower boundary` 21.
- Evidence: `bo_train_metrics.csv`, `SignalJournal_bo_train_suffix.csv`, `OrderJournal_bo_train_suffix.csv`, `TradeJournal_bo_train_suffix.csv`, excerpts, and `accepted_signal_rows_bo_train.csv`.

### FBO-only train

Configuration: `QuantBeast.Perf.FBO.Train.XAUUSD.M5.20260622_20260626.ini`

- Ticks/bars: 1,736,377 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:12:51.170.
- Final balance: 10000.00 USD.
- Signal rows: 940.
- Signal status: 935 REJECTED, 5 ACCEPTED.
- Accepted signals: FBO BUY 3, FBO SELL 2.
- Direction coverage: BUY rejected 467 / accepted 3; SELL rejected 468 / accepted 2.
- Signal IDs missing direction: 0.
- Order/trade rows: 5 / 5.
- Closed-trade net sum: -193.03.
- Gross profit/loss: 115.26 / 308.29.
- Profit factor: 0.373869.
- Evidence: `fbo_train_metrics.csv`, `SignalJournal_fbo_train_suffix.csv`, `OrderJournal_fbo_train_suffix.csv`, `TradeJournal_fbo_train_suffix.csv`, excerpts, and `accepted_signal_rows_fbo_train.csv`.

### TP-only train

Configuration: `QuantBeast.Perf.TP.Train.XAUUSD.M5.20260622_20260626.ini`

- Ticks/bars: 1,736,377 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:13:01.403.
- Final balance: 10000.00 USD.
- Signal rows: 940.
- Signal status: 940 REJECTED, 0 ACCEPTED.
- Direction coverage: 470 BUY rejected, 470 SELL rejected.
- Signal IDs missing direction: 0.
- Order/trade rows: 0 / 0.
- Top rejection reasons: `TP: not eligible` 938, `TP Long: not uptrend` 1, `TP Short: low confidence` 1.
- Evidence: `tp_train_metrics.csv`, `SignalJournal_tp_train_suffix.csv`, `OrderJournal_tp_train_suffix.csv`, `TradeJournal_tp_train_suffix.csv`, excerpts, and `accepted_signal_rows_tp_train.csv`.

### MR-only train

Configuration: `QuantBeast.Perf.MR.Train.XAUUSD.M5.20260622_20260626.ini`

- Ticks/bars: 1,736,377 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:13:51.792.
- Final balance: 10000.00 USD.
- Signal rows: 940.
- Signal status: 940 REJECTED, 0 ACCEPTED.
- Direction coverage: 470 BUY rejected, 470 SELL rejected.
- Signal IDs missing direction: 0.
- Order/trade rows: 0 / 0.
- Top rejection reasons: `MR: not eligible` 882 plus insufficient-deviation BUY/SELL pairs.
- Evidence: `mr_train_metrics.csv`, `SignalJournal_mr_train_suffix.csv`, `OrderJournal_mr_train_suffix.csv`, `TradeJournal_mr_train_suffix.csv`, excerpts, and `accepted_signal_rows_mr_train.csv`.

Independent-strategy interpretation:

- The per-strategy train pass confirms each strategy-only configuration runs reproducibly in true-tick Shadow mode with direction-preserving signal IDs and without broker transmission.
- FBO is the only strategy that reached accepted trade state in this train window.
- BO, TP, and MR have negative evidence for accepted entries in this window: their filters produced only rejected signal rows. This is not a defect by itself, but it remains a strategy-reachability/performance limitation for broader organic testing.

## Independent strategy holdout baselines

All four strategy-only holdout configs were run independently on the same XAUUSD M5 true-tick holdout window (`2026.06.29` to `2026.07.03`) in Shadow mode with challenge acknowledgement false and self-tests disabled. Temporary `Profiles/Tester` launcher copies were removed after each run.

### BO-only holdout

Configuration: `QuantBeast.Perf.BO.Holdout.XAUUSD.M5.20260629_20260703.ini`

- Ticks/bars: 1,464,441 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:12:32.122.
- Final balance: 10000.00 USD.
- Signal rows: 1,130.
- Signal status: 1,130 REJECTED, 0 ACCEPTED.
- Direction coverage: 565 BUY rejected, 565 SELL rejected.
- Signal IDs missing direction: 0.
- Order/trade rows: 0 / 0.
- Top rejection reasons: `Breakout: not eligible` 992, plus HTF-bias, trigger, boundary, and risk stop-too-far rejections.
- Evidence: `bo_holdout_metrics.csv`, `SignalJournal_bo_holdout_suffix.csv`, `OrderJournal_bo_holdout_suffix.csv`, `TradeJournal_bo_holdout_suffix.csv`, excerpts, and `accepted_signal_rows_bo_holdout.csv`.

### FBO-only holdout

Configuration: `QuantBeast.Perf.FBO.Holdout.XAUUSD.M5.20260629_20260703.ini`

- Ticks/bars: 1,464,441 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:14:07.638.
- Final balance: 10000.00 USD.
- Signal rows: 1,130.
- Signal status: 1,120 REJECTED, 10 ACCEPTED.
- Accepted signals: FBO BUY 8, FBO SELL 2.
- Direction coverage: BUY rejected 557 / accepted 8; SELL rejected 563 / accepted 2.
- Signal IDs missing direction: 0.
- Order/trade rows: 10 / 10.
- Closed-trade net sum: 64.66.
- Gross profit/loss: 279.82 / 215.16.
- Profit factor: 1.300521.
- Evidence: `fbo_holdout_metrics.csv`, `SignalJournal_fbo_holdout_suffix.csv`, `OrderJournal_fbo_holdout_suffix.csv`, `TradeJournal_fbo_holdout_suffix.csv`, excerpts, and `accepted_signal_rows_fbo_holdout.csv`.

### TP-only holdout

Configuration: `QuantBeast.Perf.TP.Holdout.XAUUSD.M5.20260629_20260703.ini`

- Ticks/bars: 1,464,441 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:14:01.034.
- Final balance: 10000.00 USD.
- Signal rows: 1,130.
- Signal status: 1,130 REJECTED, 0 ACCEPTED.
- Direction coverage: 565 BUY rejected, 565 SELL rejected.
- Signal IDs missing direction: 0.
- Order/trade rows: 0 / 0.
- Top rejection reasons: `TP: not eligible` 1124, `TP Long: not uptrend` 3, `TP Short: configured trigger not confirmed` 2, `TP Short: low confidence` 1.
- Evidence: `tp_holdout_metrics.csv`, `SignalJournal_tp_holdout_suffix.csv`, `OrderJournal_tp_holdout_suffix.csv`, `TradeJournal_tp_holdout_suffix.csv`, excerpts, and `accepted_signal_rows_tp_holdout.csv`.

### MR-only holdout

Configuration: `QuantBeast.Perf.MR.Holdout.XAUUSD.M5.20260629_20260703.ini`

- Ticks/bars: 1,464,441 ticks, 1,104 bars.
- Result: test passed.
- Runtime: 0:12:53.861.
- Final balance: 10000.00 USD.
- Signal rows: 1,130.
- Signal status: 1,130 REJECTED, 0 ACCEPTED.
- Direction coverage: 565 BUY rejected, 565 SELL rejected.
- Signal IDs missing direction: 0.
- Order/trade rows: 0 / 0.
- Top rejection reasons: `MR: not eligible` 1094 plus insufficient-deviation and rejection-wick failures.
- Evidence: `mr_holdout_metrics.csv`, `SignalJournal_mr_holdout_suffix.csv`, `OrderJournal_mr_holdout_suffix.csv`, `TradeJournal_mr_holdout_suffix.csv`, excerpts, and `accepted_signal_rows_mr_holdout.csv`.

Independent-holdout interpretation:

- The per-strategy holdout pass confirms each strategy-only configuration runs reproducibly in true-tick Shadow mode with direction-preserving signal IDs and without broker transmission.
- FBO is the only strategy that reached accepted trade state in this holdout window.
- BO, TP, and MR have negative evidence for accepted entries in this holdout window: their filters produced only rejected signal rows. This remains a strategy-reachability/performance limitation for broader organic testing, not an optimization target before correctness gates are expanded.

## Limitations

- These runs are Strategy Tester evidence only. They do not validate live-terminal persistence or broker execution/restart behavior with actual positions.
- No broker orders were transmitted.
- Readiness remains capped at `READY FOR SHADOW MODE`.
