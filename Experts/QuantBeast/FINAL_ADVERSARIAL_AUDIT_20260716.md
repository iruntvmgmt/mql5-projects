# QuantBeast Final Adversarial Audit - 2026-07-16

## Executive verdict

`READY FOR SHADOW MODE`

QuantBeast is not complete in the live-trading sense. It is, however, repaired to the broker-free Shadow readiness gate: the final compiled EA has `0 errors, 0 warnings`; the latest deterministic Shadow regression reports `45 passed, 0 failed`; live modes are gated to FBO-only market-order-only initialization with non-flattening unknown-position recovery; unknown positions are not adopted into active management unless ownership is recovered; alert controls are wired with tester-safe suppression; entry preflight gates enforce bar warmup and abnormal price-jump blocking; session/rollover exits have deterministic policy coverage; and the immediate signal-journal blocker is closed by an organic true-tick Shadow run with all strategies enabled and self-tests disabled.

Live, Conservative Live, Challenge research with broker transmission, and Challenge Live remain prohibited because this run did not authorize broker orders and therefore cannot provide real broker execution, callback, or restart evidence.

## Final build and hashes

- Compiler: MetaEditor build 6002.
- Final source SHA-256: `8312ffcd21e9e5a8d051315acd14398e3aba7b7488ab4a8888186957ffde34b8`.
- Final EX5 SHA-256: `834e063c510e940e2ff366a8deea4edda32511b06f3ec8ff2cfb4b7d361bd5a7`.
- EX5 timestamp: 2026-07-16 10:08:54 EDT.
- EX5 size: 443512 bytes.

## Defects repaired in this run

- Medium: signal-level `ACCEPTED` rows were emitted before final central preflight sizing, broker constraints, and margin checks. The controller now writes the accepted signal only after strategy, arbitration, and central risk accept it; post-preflight failures are logged as rejected.
- High: `OpenJournalFile()` opened existing CSV files at offset 0, allowing historical journal bytes to be overwritten. The journal opener now seeks to file end and fails closed if append positioning fails. One pre-fix shared Common `SignalJournal.csv` prefix was corrupted during proof work and is preserved honestly as historical damage.
- Medium: dashboard diagnostic text was suppressed by a second throttle check immediately after the main dashboard update. The redundant diagnostic throttle was removed.
- Medium: `TradeJournal::LogTrade()` skipped performance metric updates when the file journal was disabled. Performance now updates independently from CSV writing, while file output remains gated by configuration.

## Deterministic validation

Evidence: `TestEvidence/audit_final_20260716/`

- Compile: `0 errors, 0 warnings`.
- Latest deterministic gate run: `45 passed, 0 failed`.
- Test 35 proved final-decision signal writer rows for strategy rejects, arbitration loser, risk reject, and accepted BUY.
- Test 36 proved performance metrics update while `InpEnableTradeJournal=false`.
- Tester result: 22080 generated ticks, 1104 bars, normal completion, final balance `10000.00`.

## Organic true-tick signal-journal proof

Evidence: `TestEvidence/organic_true_ticks_20260716/`

Configuration:

- XAUUSD M5.
- Model: every tick based on real ticks.
- Window: 2026-06-22 00:00 to 2026-06-23 00:00.
- Mode: Shadow.
- All four strategies explicitly enabled.
- Self-tests disabled.
- Persistence/global variables/news/dashboard disabled.
- Signal, order, and trade journals enabled.

Runtime:

- Tester log reports real ticks beginning from 2026-06-19.
- Run completed normally: 417423 ticks, 276 bars, test passed in 0:03:06.272.
- `SignalJournal.csv` grew from byte `94740` to `348570`.
- `OrderJournal.csv` grew from byte `260` to `924`.
- `TradeJournal.csv` grew from byte `368` to `1400`.

Signal suffix summary:

- 880 newly appended organic signal rows.
- Accepted rows: FBO BUY = 1, FBO SELL = 2.
- Rejected rows include BO/FBO/TP/MR BUY and SELL paths.
- Risk-rejected winner example: `FBO_BUY_1782154500`, status `REJECTED`, reason `Risk: Stop too far: 1585.0 > 1000`.
- Strategy-level rejections remained rejected.
- Arbitration losers remained rejected.
- Signal IDs include direction, for example `FBO_BUY_1782111900` and `FBO_SELL_1782130500`.
- Order/fill outcomes stayed in `OrderJournal.csv` and `TradeJournal.csv`, not in `SignalJournal.csv`.

## Performance-readiness baseline

Evidence: `TestEvidence/performance_readiness_20260716/`

- Added reproducible Shadow-mode XAUUSD M5 true-tick configs for combined train/holdout and per-strategy train baselines.
- Combined train window `2026.06.22` to `2026.06.26` completed: `1,736,377` ticks, `1,104` bars, final tester footer present, test passed in `0:14:42.937`.
- Train suffix metrics: `3,760` signal rows, `5` accepted FBO signals, `5` Shadow orders/trades, closed-trade net `-193.03`, profit factor `0.373869`.
- Combined holdout first attempt `2026.06.29` to `2026.07.03` is not a pass: journals appended partial rows through `2026.06.29 21:55:00`, but no final tester footer was written and the configured date range did not complete.
- Combined holdout clean retry completed: `1,464,441` ticks, `1,104` bars, final tester footer present, test passed in `0:12:54.454`.
- Holdout retry suffix metrics: `4,520` signal rows, `10` accepted FBO signals, `10` Shadow orders/trades, closed-trade net `64.66`, profit factor `1.300521`.
- Independent per-strategy train baselines completed on the train window: BO `940` rejected / `0` accepted / `0` trades; FBO `935` rejected / `5` accepted / `5` trades / net `-193.03`; TP `940` rejected / `0` accepted / `0` trades; MR `940` rejected / `0` accepted / `0` trades.
- Independent per-strategy holdout baselines completed on the holdout window: BO `1,130` rejected / `0` accepted / `0` trades; FBO `1,120` rejected / `10` accepted / `10` trades / net `64.66`; TP `1,130` rejected / `0` accepted / `0` trades; MR `1,130` rejected / `0` accepted / `0` trades.
- Added production live-mode strategy, execution, and recovery gates: Conservative Live and acknowledged Challenge Live now initialize only with FBO enabled, BO/TP/MR disabled, market orders enabled, stop/limit pending orders disabled, `InpMaxPendingOrders=0`, and a non-flattening unknown-position policy. Evidence: `TestEvidence/live_strategy_gate_20260716/` and `TestEvidence/live_recovery_gate_20260716/`.
- Repaired persisted-state scope to use the effective adapter symbol rather than chart `_Symbol`; Evidence: `TestEvidence/state_scope_20260716/`.
- These are readiness/baseline mechanics only. No profitability, optimization, or edge claim is supported.

## Strategy-by-strategy verdict

- BO: deterministic long/short/rejection reachability passes; organic true-tick rows showed BO BUY/SELL rejections, no accepted BO entry in this one-day window.
- FBO: deterministic reachability passes; organic true-tick run produced accepted BUY and SELL Shadow entries and completed trade rows.
- TP: deterministic reachability passes; organic true-tick rows showed TP BUY/SELL rejections, no accepted TP entry in this one-day window.
- MR: deterministic reachability passes; organic true-tick rows showed MR BUY/SELL rejections, no accepted MR entry in this one-day window.

No strategy has a proven edge. This audit proves mechanical routing and selected lifecycle behavior, not profitability.

## Regime and arbitration verdict

Regime classification has deterministic coverage and ran in the organic true-tick pipeline. Arbitration now finalizes lower-ranked, duplicate, cooldown, conflict, confluence, and exposure outcomes as explicit rejections. Organic true-tick signal rows show final decisions after strategy/arbitration/risk routing.

## Risk assessment

Central risk preflight, sizing, exposure, drawdown locks, daily/weekly locks, kill priority, Challenge cash-flow quarantine, and fail-closed Challenge restore policies have deterministic broker-free coverage. Organic true-tick evidence includes accepted Shadow entries and one central-risk rejection. Real broker margin, stop/freeze-level, slippage, and rejected-order behavior remain external-evidence blockers.

## Execution assessment

Shadow market entries, stops, targets, time exits, MFE/MAE, cost accounting, completed trade journaling, partial/breakeven/trailing paths, emergency policies, and deterministic broker fault adapters are covered by fixtures. No real broker orders were transmitted. Broker callback ordering, filling modes, actual requotes, invalid stop handling, freeze-level rejection, delayed/partial fills, and reconnect behavior remain unproven.

## Persistence and recovery assessment

State schema quarantine, risk-state restore, Challenge restore, cash-flow cursoring, rejection streak persistence, and explicit global flush are deterministically covered. A two-process Strategy Tester probe showed tester-global isolation/reset and is not live-terminal persistence proof. Actual broker-position restart validation requires explicit authorization to create demo or live broker exposure.

## Known limitations

- Shadow pending orders are explicitly rejected; activation, expiry, and cancellation simulation are not implemented.
- Owned broker pending orders are cancelled fail-closed on startup rather than restored.
- Alert routing is wired for key signal/order/protection events and tester-suppressed for validation; real terminal/push delivery remains unverified outside Strategy Tester.
- Several declared inputs remain inactive or partial, including close-before-session/rollover controls and some strategy-specific target/pullback/compression variants.
- Historical shared Common signal journal contains pre-repair rows and a pre-fix corrupted prefix. Current proof uses byte-bounded suffixes only.
- Performance baselines are mechanically started: the combined training baseline, a clean combined holdout retry, and independent BO/FBO/TP/MR train and holdout baselines completed, while the first holdout attempt remains preserved as invalid/incomplete evidence. No edge claim is supported.

## Final readiness classification

`READY FOR SHADOW MODE`
