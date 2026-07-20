# QuantBeast Live Deployment Checklist

**Current decision:** **DO NOT DEPLOY LIVE**  
This checklist is a release gate, not general advice. Every applicable item requires recorded evidence.

**Latest safe readiness:** `READY FOR SHADOW MODE` as of 2026-07-20. Compile, deterministic Shadow fixtures, organic true-tick Shadow journal proof, manual/MCP demo broker open-close lifecycle, and real Conservative Live restart-recovery evidence (owned position, pending order, unknown position, corrupt state -- see `TestEvidence/restart_recovery_20260719/`) all passed. Broader organic BO/TP/MR acceptance, fault-injection, and prolonged demo-forward evidence remain absent.

Current live-mode code gate: Conservative Live and acknowledged Challenge Live initialize only when `InpAcknowledgeLiveBrokerRisk=true`, the enabled strategy set is FBO-only, and execution is market-order-only with pending orders disabled. Live startup also rejects `UNKNOWN_FLATTEN`; use `UNKNOWN_QUARANTINE` until explicit operator-approved flatten handling is implemented and proven. BO, TP, MR, and pending orders must remain disabled for any future explicitly authorized demo/live execution until accepted-entry, lifecycle, pending-order, and restart evidence exists.

## A. Source and build gate

- [ ] Bug audit completed and all critical/high defects resolved.
- [ ] Required modules contain real implementations; no live-path stubs.
- [ ] All configuration inputs either work or are removed/documented as unsupported.
- [ ] All preset keys match real EA inputs.
- [ ] MetaEditor compile result is zero errors and zero warnings.
- [ ] `.ex5`, compile log, source hash, MT5 build, and timestamp are archived.
- [ ] `BUILD_AUDIT.md` reflects the compiled revision.

## B. Architecture gate

- [ ] Strategies never call broker/order functions.
- [ ] Every signal passes arbitration and centralized risk.
- [ ] Every final lot size is validated against actual risk limits.
- [ ] Every live order passes the broker adapter.
- [ ] Global entry, symbol, cancel-all, flatten-all, and emergency kills work.
- [ ] Shadow and live use the same lifecycle except transmission.
- [ ] `OnTradeTransaction` handles fills, partial fills, closes, and rejections.
- [ ] Position callbacks, journals, risk counters, and persistence receive close events.

## C. Broker/symbol gate

- [ ] Attached symbol is the intended broker gold symbol.
- [ ] Digits, point, tick size/value, contract size, lot limits/step verified.
- [ ] Stop level and freeze level verified.
- [ ] Filling modes and market/limit/stop permissions verified.
- [ ] Hedging versus netting behavior explicitly supported and tested.
- [ ] Margin calculation matches a manual reference order.
- [ ] Trading sessions and market-close behavior verified.
- [ ] Broker UTC offset and DST flag verified.

## D. Data and signal gate

- [ ] Bar cache has sufficient ordered data for every configured timeframe.
- [ ] Quote freshness and maximum price-jump controls are active.
- [ ] All feature-buffer/copy failures block entries safely.
- [ ] Opening range and session high/low use real session boundaries.
- [ ] Breakout, reclaim, displacement, and structure features are calculated.
- [ ] Confirmed swings do not use future information.
- [ ] Each strategy passes valid and invalid long/short tests.
- [ ] Unsupported trigger modes cannot silently fall back.
- [ ] News timestamps are populated and verified, or news trading is explicitly prohibited.

## E. Risk gate

- [ ] Risk-percent calculation verified for the exact symbol/account currency.
- [ ] Actual proposed trade risk is below `InpMaxRiskPerTrade`.
- [ ] Daily, weekly, HWM, consecutive-loss, equity-floor, margin, and exposure locks tested.
- [ ] Projected post-trade exposure is checked.
- [ ] Per-strategy trade limits use real counters.
- [ ] Risk counters update on close and survive restart.
- [ ] Deposits/withdrawals do not corrupt drawdown and challenge-stage tracking.
- [ ] Maximum leverage is enforced.
- [ ] Pyramiding is disabled for conservative live mode.

## F. Execution and protection gate

- [ ] Entry price, SL, TP, and volume are normalized legally.
- [ ] Stop/freeze constraints are revalidated immediately before transmission.
- [ ] Retry count is bounded and every retry revalidates signal, spread, price, risk, margin, and stops.
- [ ] Market, pending, rejection, expiration, and partial-fill paths tested.
- [ ] Every fill is checked for protective SL/TP.
- [ ] Failed protection triggers correction, emergency close, alert, and entry lock.
- [ ] Broker-side tickets are mapped correctly to position contexts.
- [ ] EA operations cannot modify manual or other-EA positions.

## G. Position-management gate

- [ ] Original risk remains immutable after stop movement.
- [ ] Break-even includes configured costs and does not distort R calculations.
- [ ] Partial close uses legal remaining and closed volumes and fires once.
- [ ] ATR/swing/chandelier trails only reduce risk.
- [ ] Time, session-end, rollover, pre-news, momentum, and regime exits behave as configured.
- [ ] Every close has an exit reason and full trade-journal row.
- [ ] MFE/MAE and realized slippage are accurate.

## H. Recovery gate

- [x] Open EA positions reconstruct after restart. Proven 2026-07-20 against a real Conservative Live terminal restart: strategy, entry, and original stop correctly recovered (`TestEvidence/restart_recovery_20260719/`).
- [x] Pending EA orders reconstruct after restart. Proven 2026-07-20: owned pending orders are now reconstructed from live broker state (strategy, type, price, sl, tp, true setup time) when exactly one is found with a resolvable comment; cancellation fail-closed is preserved only for unresolvable-comment/ambiguous (>1) cases (`TestEvidence/pending_order_reconstruction_20260720/`).
- [ ] Strategy owner, signal ID, original risk, partial state, and scale-in state restore. Partially proven 2026-07-20: strategy owner and original stop/target restore correctly. Durable signal ID beyond the journal string, exact partial-exit count, and scale-in state still do not survive restart.
- [x] All reconstructed positions are checked for protection. Proven 2026-07-20: `ReconstructFromBroker()` now calls `EnsurePositionProtection()` (the same contract live fills use) for every recovered position, escalating to `ActivateProtectionEmergency()` on failure. A deliberately-unprotected fixture position was correctly detected and closed on a real terminal restart (`TestEvidence/protection_verification_reconstruction_20260720/`).
- [x] Persisted/broker mismatch blocks entries and is reported. Proven 2026-07-20: a corrupted state-version Global Variable correctly triggered fail-closed quarantine and entry kill on real restart (`TestEvidence/restart_recovery_20260719/`).
- [ ] Unknown-position policy works for ignore/report/quarantine; explicit flatten remains blocked in live startup until separately authorized and proven. `UNKNOWN_REPORT` proven 2026-07-20 against a real restart (correctly logged, left unmanaged, no destructive action; `TestEvidence/restart_recovery_20260719/`). `UNKNOWN_IGNORE` and `UNKNOWN_QUARANTINE` remain unit-tested only.
- [ ] Daily/weekly locks, HWM, challenge stage, cooldowns, and signal IDs survive restart. Daily/weekly start equity and HWM proven 2026-07-20 against a real terminal restart (`TestEvidence/risk_state_restart_20260720/`). Lock booleans and consec-loss count share the same load path but weren't independently re-verified; challenge stage needs separate Challenge Live authorization; arbitration cooldowns and signal IDs remain unproven against a real restart.

## I. Journaling, UI, and alert gate

- [ ] Full signal CSV includes accepted and rejected signals, including arbitration/risk rejections.
- [ ] Full order CSV includes every attempt, retcode, retry, fill, and final state.
- [ ] Full trade CSV includes costs, net P/L, R, MFE, MAE, regimes, spread, slippage, and exit reason.
- [ ] Performance metrics reconcile with MT5 history.
- [ ] Dashboard displays connection, permissions, risk, daily/weekly P/L, drawdown, kills, and last execution error.
- [ ] Alerts are wired, deduplicated, and tested.

## J. Tester and demo gate

- [ ] Diagnostic mode sends zero orders.
- [ ] Shadow mode sends zero orders and completes theoretical trade lifecycles.
- [ ] Development and non-overlapping holdout backtests completed.
- [ ] High-volatility, quiet-market, spread, slippage, and gap stress tests completed.
- [ ] Restart/recovery test evidence archived.
- [ ] Conservative demo forward test completed for at least two continuous weeks.
- [ ] No unresolved critical/high defects.

Current broker-free evidence satisfies parts of the Shadow/journal gate only: `TestEvidence/organic_true_ticks_20260716/` proves signal/order/trade CSV separation and final-decision rows in Shadow. It does not satisfy live execution, demo, recovery, or performance gates.

## K. Conservative live approval

- [ ] Written approval records EA version/hash, broker, symbol, account, preset, and maximum loss.
- [ ] `InpAcknowledgeLiveBrokerRisk=true` set deliberately for this specific demo/live validation window.
- [ ] Enabled strategies are exactly FBO-only unless BO/TP/MR accepted-entry and lifecycle evidence has been added and this checklist is revised.
- [ ] Execution is market-order-only with stop/limit pending orders disabled and `InpMaxPendingOrders=0` unless pending-order lifecycle/restart evidence has been added and this checklist is revised. Restart-recovery evidence now exists (2026-07-20, `TestEvidence/pending_order_reconstruction_20260720/`); live activation, cancellation, and fill-during-cancel-race evidence for ordinary pending-order trading are still needed before this gate can be revised.
- [ ] Risk is minimum legal lot or independently verified low fixed risk.
- [ ] One position maximum; pyramiding off.
- [ ] Strict spread, daily loss, weekly loss, drawdown, and equity floor enabled.
- [ ] Major-news and rollover restrictions active.
- [ ] Human monitoring and emergency shutdown procedure available.

## L. Challenge-mode approval

Challenge approval is separate and cannot inherit conservative-live approval.

- [ ] `InpAcknowledgeChallengeRisk=true` set deliberately at launch.
- [ ] Stage transitions, drawdown, attempts, profit lock, leverage, and persistence tested.
- [ ] Pyramiding, if enabled, adds only to profitable protected positions.
- [ ] Maximum planned account loss accepted in writing.
- [ ] Dashboard visibly displays challenge warning and stage.
- [ ] Independent kill/flatten test completed immediately before deployment.

## Rollback procedure

If any live gate fails:

1. Block entries.
2. Verify or close protected positions according to the approved runbook.
3. Cancel EA pending orders.
4. Return to Diagnostic or Shadow mode.
5. Archive logs and broker history.
6. Open a defect with exact version, time, symbol, state, and reproduction steps.
