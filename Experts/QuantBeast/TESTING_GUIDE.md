# QuantBeast Testing Guide

**Current evidence status:** Evidence is under `TestEvidence/*_20260715/` and `TestEvidence/*_20260716/`; compile is `0 errors, 0 warnings`, and the latest validated Shadow fixture passed 51 startup tests with no broker orders. The current source now adds family/template/tag metadata to emitted strategy signals, writes those tags into the tester signal/counterfactual journals, and includes a batch strategy metadata/reachability validator (TEST 61); the latest tester rerun confirms `TEST 61 PASS` and `Self-tests complete: 63 passed, 0 failed`. A batch gap-map report script now summarizes tester journals into `TestEvidence/gap_map_report.md` for overlap and rejection analysis. Organic true-tick Shadow data reached accepted FBO BUY/SELL entries and final-decision CSV proof. Manual/MCP demo broker lifecycle evidence exists, but QuantBeast EA-autonomous demo execution remains unproven. A combined true-tick training baseline, clean holdout retry, and independent BO/FBO/TP/MR train and holdout baselines completed under `TestEvidence/performance_readiness_20260716/`; the first holdout attempt is preserved as invalid/incomplete evidence. Current boundary and wiring proof also lives under `TestEvidence/current_regression_20260716/`, `TestEvidence/bo_compression_pct_20260716/`, `TestEvidence/tp_pullback_age_20260716/`, `TestEvidence/mr_target_band_20260716/`, and `TestEvidence/fbo_target_variants_20260716/`. Only FBO reached accepted trade state in these baseline windows. Strategy edge, real restart recovery, and actual broker failures remain unproven.
**Rule:** A successful compile or profitable backtest alone is not completion.

The audit and test program must follow `PROJECT_MISSION_AND_AUDIT_CONTEXT.md`. In particular, it must preserve independent strategy engines, examine Challenge Mode as a deterministic bounded-risk system, and avoid treating architectural sophistication as evidence of trading edge.

## Test stages

Run stages in order. Stop when a blocking stage fails.

### Stage 1: Static source and configuration audit

- Confirm all includes resolve.
- Confirm all preset keys match actual input names.
- Identify unused inputs and unreachable modules.
- Search for TODOs, stubs, unconditional pass conditions, and placeholder comments.
- Verify strategies contain no `CTrade`, `OrderSend`, `Buy`, `Sell`, or position modification calls.
- Verify no future-bar or unconfirmed-pivot usage.
- Check array boundaries, series direction, ticket types, and broker ownership filters.

Record findings in `BUILD_AUDIT.md` and the dedicated bug audit.

### Stage 2: Compile gate

Compile `Experts/QuantBeast/QuantBeastEA.mq5` in the installed MetaEditor.

Required result:

```text
0 errors, 0 warnings
```

Preserve:

- `QuantBeastEA.ex5`
- MetaEditor compile log
- MT5/MetaEditor build number
- Compile timestamp

Do not suppress warnings without understanding them.

> [!NOTE]
> If the direct `wine metaeditor64.exe /compile:...` invocation silently
> produces no log and no `.ex5`, see the known workaround in `AGENTS.md`
> under "Compilation contract" (use `wine start /Unix` with a relative path).

### Stage 3: Automated unit/scenario tests

The current embedded checks are insufficient. Add deterministic tests for the following groups.

#### Symbol and normalization

- Point, tick size/value, contract size, digits
- Min/max/step lot
- Price and volume normalization
- Stop and freeze levels
- Filling mode and trade permissions

#### Risk and sizing

- All four sizing modes
- Zero/excessive stop rejection
- Min/max/step enforcement
- Risk tolerance after estimated costs
- Insufficient margin
- Daily, weekly, HWM, and consecutive-loss locks
- Projected exposure

#### Feature and regime

- Confirmed swing without future leakage
- Compression and expansion
- Breakout distance and bars beyond
- Failed breakout and reclaim
- Session and opening ranges
- VWAP/deviation calculations
- Trend, volatility, liquidity, structure, and event classifications

#### Strategies

- Valid and invalid long/short scenario for BO, FBO, TP, and MR
- Every supported trigger mode
- Excess spread, stale quote, event lockout, and ineligible regime
- Conflicting and duplicate signals

#### Execution state machine

- Invalid volume/stops
- Stale/displaced signal
- Duplicate order
- Market and pending order intent
- Expired pending order
- Bounded retry and revalidation
- Full/partial fill event
- Rejection and timeout
- Unprotected-fill emergency response

#### Recovery

- Restart with protected open position
- Restart with unprotected open position
- Restart with pending order
- Persisted daily/weekly lock
- Unknown manual/other-EA position
- Persisted/broker mismatch
- Partial-exit and strategy ownership restoration

### Stage 4: Diagnostic-mode attachment

Attach to the exact broker gold symbol with Algo Trading disabled.

Verify:

- EA initializes and remains attached.
- No order requests occur.
- Symbol properties and account mode are correct.
- Tick arrival, spread, quote age, session, features, regimes, and eligibility update.
- All automated tests report accurate pass/fail counts.
- A deliberately failed test is reported as a failure.

### Stage 5: Shadow-mode functional test

Shadow mode must never send broker orders. Market-intent virtual positions now track complete exits; pending-order intents remain explicitly unsupported and must be tested as rejections.

For each shadow trade verify journaled:

- Strategy, direction, signal ID/time
- Entry, stop, target, volume, risk/reward
- Regime, session, volatility, spread, confidence
- MFE, MAE, theoretical costs
- Exit time/price/reason
- Net hypothetical P/L and R

Compare several trades manually against visual tester prices.

### Stage 6: Strategy Tester baseline

Recommended first configuration:

- Symbol: broker’s actual XAUUSD variant
- Timeframe: M5
- Model: Every tick based on real ticks
- Deposit: representative of intended account
- Fixed spread: off when real-tick data provides spread
- Mode: Shadow first, then Conservative Live inside tester only
- Optimization: disabled

Use at least:

1. Development window
2. Non-overlapping holdout window with clean terminal/tester start, full configured date coverage, and final tester footer
3. High-volatility window
4. Quiet/range window
5. Spread-stress and delayed-execution variants

Record trade count, net result, profit factor, expectancy, max balance/equity drawdown, longest losing streak, exposure, rejected-signal counts, and performance by strategy/direction/session/regime.

### Stage 7: Restart/recovery test

Use the normal MT5 terminal on demo. Do not use Strategy Tester Terminal Global Variables as persistence evidence in this environment: the captured two-process probe under `TestEvidence/restart_probe_20260715/` loaded schema `0` after a fresh tester/Wine process tree, despite a phase-1 flush and verification.

1. Open or simulate an EA-owned protected position.
2. Stop/restart terminal or remove/reattach EA.
3. Confirm reconstruction before entries resume.
4. Confirm strategy owner, original risk, stop, target, partial state, and risk counters.
5. Repeat with a pending order.
6. Repeat with an unknown position and each configured policy.

### Stage 8: Demo forward test

Run Conservative Live on demo only after Stages 1–7 pass.

Minimum evidence:

- Two continuous weeks
- Terminal restart event
- Connection-loss event
- Rejected order or deliberately simulated invalid request
- News lockout event
- Daily rollover and DST/session check
- Broker-side stop verification after every fill

### Stage 9: Live approval

Live approval is a separate written decision. Challenge mode requires an additional dedicated approval after conservative live evidence.

## Evidence directory convention

Create a non-source evidence directory when testing begins:

```text
Experts/QuantBeast/TestEvidence/
  compile/
  self-tests/
  scenarios/
  tester-configs/
  backtests/
  recovery/
  demo-forward/
```

Each run should record date, EA hash/version, preset, symbol specification, broker/server, tester model, period, and result.

## Current test debt

- `Include/QuantBeast/Testing/SafetyTests.mqh` covers only series direction, closed-bar order, one session boundary, and a broker-aware sizing bound.
- Startup fixtures have captured runtime output: 51 passed, 0 failed, including deterministic regime and all arbitration enum modes/ranking, duplicate, restored duplicate/cooldown persistence, opposing, exposure, lower-ranked rejection coverage, final-decision signal writing, performance updates with file trade journaling disabled, live-mode strategy/execution gates, live broker-transmission acknowledgement gating, state symbol scoping, live recovery no-passive-flatten gating, unknown-position no-adoption behavior, alert-routing behavior, entry preflight controls, session/rollover exit policy, self-test detail logging control, chart-object toggle policy, fill/reconciliation alert categories, and strategy-counter same-day restore policy.
- Direct deterministic long/short/rejection reachability fixtures now exist for BO, FBO, TP, and MR, and rejected shorts retain SELL direction. Organic true-tick data reached accepted FBO BUY/SELL through final Shadow entries and completed FBO trade rows; BO/TP/MR accepted organic lifecycles are still unproven across 6 distinct organic windows as of 2026-07-19 (`TestEvidence/organic_multiwindow_20260719/`), with the eligibility gate itself (not window selection) accounting for 88-100% of BO/TP/MR rejections in every window tested.
- Deterministic state-version quarantine, risk restoration, pending partial-fill, deferred close/deduplication, hedge-only admission, protection repair/emergency, server-response, and cancel/fill-race tests now exist. These inject pure outcomes without broker transmission; actual callback ordering, broker faults, and normal-terminal restart recovery remain unproven.
- The two-process tester probe is a recorded negative test-environment result, not a live-terminal restart result. Production persistence now explicitly calls `GlobalVariablesFlush()` and passed the latest 40/0 Shadow regression, with arbitration persistence, strategy-counter persistence, and the latest 51/0 current-regression proof captured separately in `TestEvidence/arbitration_persistence_20260716/`, `TestEvidence/strategy_counter_persistence_20260716/`, and `TestEvidence/current_regression_20260716/`.
- The current code now adds family/template/tag metadata to every emitted strategy signal and a batch metadata/reachability validator (TEST 61). That path has compile evidence only so far; it still needs a fresh tester rerun before it can be promoted into the validated evidence set.
- Emergency cancel/flatten policy is live-mode-only, timer-serviced, and retry-bounded in deterministic fixtures. Consecutive broker rejection counting is wired and persisted under state schema v4, but actual broker rejection/failure/reconnect behavior remains unproven.
- Core market-position Shadow branches are proven, including costs, multiple positions, drawdown lock, and transient-gate recovery. Organic feature/regime-generated lifecycle sequences remain unproven.
- Final signal-decision routing through strategy, arbitration, and central risk is deterministically covered, and direction-qualified IDs are implemented. A completed organic post-repair true-tick run is inspected at the CSV suffix level under `TestEvidence/organic_true_ticks_20260716/`; historical pre-repair rows are not valid current evidence.
- A Conservative Live Strategy Tester attempt under `TestEvidence/conservative_live_tester_fbo_20260716/` did not reach tester order routing because the native tester did not apply `InpAcknowledgeLiveBrokerRisk=true`; the EA failed closed at initialization. Treat this as live-ack gate evidence and as a blocker for tester-only Conservative Live execution proof through the current launcher path.
- Shadow pending-order activation and expiry are not implemented; pending intents are rejected.
- `OnTradeTransaction` live/broker lifecycle remains without runtime evidence. `OnTester` executed, but no strategy performance claim is valid.
- The tester API's run identifier/status is unreliable; local agent logs proved the Shadow fixture completed.
