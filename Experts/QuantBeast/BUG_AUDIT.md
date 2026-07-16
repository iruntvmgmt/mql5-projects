# QuantBeast Focused Bug Audit

> **Historical baseline:** This file records the untouched generated-code audit and its original FAIL verdict. It is intentionally preserved as before/after evidence. The current repaired-state verdict is in [REPAIR_AUDIT_20260715.md](REPAIR_AUDIT_20260715.md). Do not use the compile status below as the current build status.

**Audit date:** 2026-07-15  
**Audited source:** `QuantBeastEA.mq5` plus all active `Include/QuantBeast` modules and four presets  
**Source SHA-256 before and after compile:** `c9af4de0b05775e855f4f9bd737a8484fd0e613e9044bda14d71cf00cc7bebd3`  
**Audit mode:** Read-only; no `.mq5`, `.mqh`, or `.set` repair was made

## Executive verdict

**FAIL**

The current source does not compile. MetaEditor produced **23 errors and 15 warnings**, generated no `QuantBeastEA.ex5`, and left the exact compiler transcript in `QuantBeastEA.log`; a preserved copy and evidence manifest are under `TestEvidence/compile_20260715/`. Static tracing also confirms safety and correctness defects that would remain after a compile-only repair: entry and symbol kills are not enforced, data-quality rejection bypasses position management and emergency checks, trade-close events never update risk or analytics, sizing can exceed the configured risk budget, restart state is not reliable, broker fills are not reconciled to position tickets, and challenge protections are incomplete.

The architecture is recognizable and worth preserving, but most of its safety claims are not yet implemented end to end. Profitability and execution behavior are untested.

The project is below Diagnostic and Strategy Tester readiness until compilation and the critical test-validity defects below are repaired. It is not authorized for live or challenge operation. The mandatory readiness class appears in the final section.

## Evidence classification

- **Confirmed static defect:** Proven directly by compiler output or by a complete source path that cannot perform the documented behavior.
- **Runtime-proof-required risk:** The source exposes a credible fault, but broker/account/runtime evidence is required to quantify or confirm the actual outcome.
- **Unimplemented feature:** A documented capability has no functioning code path. It is not called a bug unless another component relies on it for safety or validity.

## Compile blockers

The untouched compile at 2026-07-15 09:39 local time produced the following groups:

| Group | Evidence | Result |
|---|---|---|
| Custom order-state names collide with built-in `ENUM_ORDER_STATE` identifiers | `Core/Enums.mqh:119-132` | 3 errors plus unsafe enum-conversion warnings |
| Lot-mode enum is declared after configuration tries to use it | `Core/Configuration.mqh:158`; enum actually exists in `Risk/PositionSizer.mqh:22-28` | declaration error and `InpLotMode` undeclared at `QuantBeastEA.mq5:230` |
| Mean-reversion trigger input is absent | `QuantBeastEA.mq5:215`; no `InpMR_TriggerMode` declaration | undeclared identifier / enum conversion errors |
| Dynamic array passed without required reference syntax | `Data/BarCache.mqh:59` | array-reference error |
| MQL5 disallows the returned `CTrade&` reference | `Execution/BrokerAdapter.mqh:374` | reference error |
| Const method calls a non-const helper | `Data/SessionEngine.mqh:235-258` calling line 73 | 8 errors |
| Invalid account-connectivity API and invalid `SymbolExist` argument | `Data/DataQuality.mqh:67,71,172` | 5 errors |

Compiler warnings also show lossy integer conversions and conversions between the built-in and custom order-state enums. The warnings are not cosmetic because order lifecycle decisions depend on those states.

## Critical defects

### C-01 — The project cannot compile

**Classification:** Confirmed static defect  
**Evidence:** `QuantBeastEA.log`; final line is `Result: 23 errors, 15 warnings`. `QuantBeastEA.ex5` is absent.  
**Consequence:** No deterministic diagnostic, shadow, tester, recovery, or live evidence can be produced from this source.

### C-02 — Entry and symbol kill switches do not block entry

**Classification:** Confirmed static defect  
**Evidence:** `Risk/KillSwitch.mqh:181-182` exposes `IsEntryKill()` and `IsSymbolKill()`, but `EvaluateAndTrade()` only checks per-strategy kills at `QuantBeastEA.mq5:503-507`. No caller enforces the two global kill states.  
**Consequence:** A stale quote, disconnect, daily/weekly event, abnormal spread, or operator symbol kill can set a dashboard-visible lock while later signals still reach risk sizing and order execution. The separate `RiskEngine` entry flag is never synchronized with `KillSwitch`.

### C-03 — Data-quality rejection skips protection and emergency logic

**Classification:** Confirmed static defect  
**Evidence:** `QuantBeastEA.mq5:407-409` returns before position management at lines 433-434 and kill-switch processing at lines 436-461.  
**Consequence:** During stale quotes, spread spikes, disconnect states, disabled AutoTrading, or invalid quotes, the EA stops managing existing positions and does not execute cancel/flatten actions. Broker-side stops may limit some exposure, but the design promise of every-tick protection is false exactly during stressed conditions.

### C-04 — Position sizing is not broker-unit safe and can force excess risk

**Classification:** Confirmed unit defect; broker-dependent magnitude  
**Evidence:** `Risk/PositionSizer.mqh:87-165` multiplies a distance measured in points by `SYMBOL_TRADE_TICK_VALUE` without converting points to ticks using `SYMBOL_TRADE_TICK_SIZE`. `Data/MarketData.mqh:68-69` stores both values, but the sizer ignores tick size. Lines 176-180 normalize and clamp every computed result upward to the configured/broker minimum instead of rejecting an unaffordable minimum lot.  
**Consequence:** Whenever tick size differs from point size, risk is miscalculated. On a small account, minimum-lot clamping can knowingly exceed the requested risk percentage. `OrderCalcProfit()` is not used to validate worst-case loss.

### C-05 — Maximum risk per trade is never enforced

**Classification:** Confirmed static defect  
**Evidence:** `Risk/RiskEngine.mqh:30,101` stores `m_maxRiskPerTradePct`; lines 321-323 estimate only the risk of 0.01 lot and never compare it with equity or the configured maximum. Actual lots are calculated later at `QuantBeastEA.mq5:581-585` and are never sent back through a risk-budget check.  
**Consequence:** Fixed-lot, fixed-currency, volatility-adjusted, challenge, and minimum-lot results can exceed `InpMaxRiskPerTrade` without rejection.

### C-06 — Trade lifecycle events do not update risk, journals, or ownership

**Classification:** Confirmed static defect  
**Evidence:** `OnTradeTransaction()` is empty at `QuantBeastEA.mq5:772-785`. There are no callers of `RiskEngine.UpdateAfterClose()`, `TradeJournal.LogTrade()`, or strategy open/update/close callbacks. `PositionManager.UpdateAll()` silently removes missing positions at `Execution/PositionManager.mqh:140-145`.  
**Consequence:** Consecutive-loss limits never advance, high-water state is not updated by closes, trade journals remain empty, exit reasons are unknown, strategy performance cannot be measured, and `OnTester()` has no valid performance data.

### C-07 — Fill success and position identity are not reconciled safely

**Classification:** Confirmed API/control defect; exact broker outcome requires runtime proof  
**Evidence:** `Execution/BrokerAdapter.mqh:104-136` treats the `CTrade` method's boolean return as a filled trade and does not require a successful dealing-server retcode. `QuantBeastEA.mq5:657-663` registers `rec.order_ticket` as both the position ticket and order ticket. Pending fills repeat that error at lines 698-730 and label ownership as `"PENDING"`.  
**Consequence:** Rejected, placed, partially filled, netting, or hedging transactions can be misclassified; position management may track a non-position ticket and immediately drop the real position. Filled pending orders usually leave the active-order pool, so the polling path can clear them without registration.

### C-08 — Protection is assumed, never verified

**Classification:** Confirmed missing safety path; occurrence requires runtime proof  
**Evidence:** Orders carry SL/TP parameters, but neither `BrokerAdapter` nor `OnTradeTransaction` selects the resulting position and verifies actual `POSITION_SL`. There is no emergency close if a fill is unprotected. `ValidateStopDistance()` exists at `Data/DataQuality.mqh:263-285` but is not called before order submission or stop modification.  
**Consequence:** Invalid stop/freeze distances, normalization effects, broker rejection, partial fills, or modification failures can leave a live position without the intended protection.

### C-09 — Daily and weekly risk persistence is structurally wrong

**Classification:** Confirmed static defect  
**Evidence:** `Risk/RiskEngine.mqh:137-172` accepts saved equity values, casts those currency values to datetimes, and compares their derived days/weeks. `Core/StateStore.mqh:79-85` writes weekly start equity as zero. Main startup reads equity fields without their saved date fields at `QuantBeastEA.mq5:280-285`. No continuous day/week rollover routine exists.  
**Consequence:** Restart can reset loss baselines; a continuously running EA can retain yesterday's baseline indefinitely; daily and weekly loss protections do not implement their stated periods.

### C-10 — Challenge Mode starts with zero risk state and does not enforce its protection fields

**Classification:** Confirmed static defect  
**Evidence:** `Risk/ChallengeMode.mqh:64` zeroes state. `Init()` never initializes stage-0 risk/target/peak. On an account below target 0, `Update()` sees no stage change at lines 118-139, so `GetRiskPercent()` returns zero. Profit lock and max exposure are calculated at lines 141-170 but never enforced anywhere. Attempts are reset on advancement and the failed-stage transition has no controlled retry/reset workflow.  
**Consequence:** A fresh challenge can size zero lots; restored or later stages can pursue risk without the documented profit lock/exposure enforcement. Challenge behavior is neither deterministic nor bounded as specified.

## High-priority defects

### H-01 — Trend direction is inverted

**Classification:** Confirmed static defect  
**Evidence:** Bar arrays are newest-first (`Data/BarCache.mqh:113-118,215-228`). `RegressionSlope()` assigns increasing X values to increasing array indices (`Core/MathUtils.mqh:117-135`), meaning X moves backward in time. `FeatureEngine` uses that slope directly at lines 313-343, while `TrendState` interprets positive as up and negative as down (`Regime/TrendState.mqh:44-73`).  
**Consequence:** Rising markets are classified as falling and vice versa. Trend-pullback direction and any directional regime dependence are invalid.

### H-02 — Features and signals use the forming bar despite closed-bar design claims

**Classification:** Confirmed static defect; live/tester divergence requires runtime quantification  
**Evidence:** ATR, ranges, wicks, abnormal candles, VWAP, and regression start at shift/index 0 (`FeatureEngine.mqh:178-180,297-304,313-318,459-495,519-530`). Strategies evaluate only on the first tick of a new bar (`QuantBeastEA.mq5:393-415,464-468`) using that new, incomplete bar.  
**Consequence:** Results are based on current-bar opens/initial highs and can differ from the documented close-confirmed logic. Multi-timeframe bar 0 values are also unconfirmed.

### H-03 — Breakout boundaries contain the price being tested

**Classification:** Confirmed strategy-logic defect  
**Evidence:** Current range includes indices 0-19 (`FeatureEngine.mqh:459-462`). Breakout tests compare current mid with that same range at `Strategies/BreakoutEngine.mqh:101-136,175-208`.  
**Consequence:** A real close beyond the prior range is not implemented. Signals may be impossible on same-price data or may be triggered by bid/mid/spread differences rather than a structural breakout. Candle-close mode is identical to immediate mode.

### H-04 — Failed-breakout strategy and structural regimes are unreachable

**Classification:** Confirmed static defect  
**Evidence:** `FeatureSnapshot` declares `breakout_dist`, `bars_beyond_level`, `failed_breakout`, `reclaim_detected`, `displacement`, `higher_low`, and `lower_high`, but `FeatureEngine` never assigns them. FBO eligibility requires failed/reclaim flags (`FailedBreakoutEngine.mqh:56-64`); structural breakout/failed-breakout/impulse states require those fields (`Regime/StructuralState.mqh:31-55`).  
**Consequence:** FBO cannot become eligible, and the regime engine cannot classify most of the structural states on which the architecture depends.

### H-05 — Session, opening-range, and time-zone features are placeholders

**Classification:** Confirmed static defect  
**Evidence:** Session high/low are copied from a rolling 20-bar range and opening range from the most recent four bars (`FeatureEngine.mqh:474-487`). `brokerUTCOffsetHours` and `brokerIsDST` are stored/logged but never applied by `SessionEngine`; classification uses raw server time (`SessionEngine.mqh:81-147`). `IsTradeableSession()` is not enforced in the entry pipeline.  
**Consequence:** Session-dependent theses, rollover/Friday restrictions, and any session-level breakout analysis are invalid or broker-time dependent.

### H-06 — Risk locks do not reset or persist correctly

**Classification:** Confirmed static defect  
**Evidence:** RiskEngine has activation methods but no day/week reset routine (`Risk/RiskEngine.mqh:353-386`). Periodic persistence saves HWM and kill state only (`QuantBeastEA.mq5:745-766`); daily/weekly locks and consecutive losses are not stored.  
**Consequence:** Locks can last forever during continuous operation or disappear on restart, depending on path.

### H-07 — Total exposure is checked before adding the proposed trade

**Classification:** Confirmed static defect  
**Evidence:** `RiskEngine.mqh:276-281` rejects only when existing exposure is already at the cap. Proposed lots do not exist yet and are never added to the comparison. Challenge `max_exposure` is also unused.  
**Consequence:** Each new order can push aggregate exposure above its configured maximum.

### H-08 — Daily strategy trade limit is permanently bypassed

**Classification:** Confirmed static defect  
**Evidence:** `QuantBeastEA.mq5:553-554` hardcodes `stratTradesToday = 0`.  
**Consequence:** `m_maxDailyPerStrategy` can never block a strategy.

### H-09 — Position management changes its R denominator after moving the stop

**Classification:** Confirmed static defect  
**Evidence:** `PositionContext.original_risk` is stored at registration (`PositionManager.mqh:122-125`) but current R is calculated from `abs(entry-current_stop)` (`PositionManager.mqh:163-176`).  
**Consequence:** Break-even or trailing changes the denominator, can collapse it toward zero, and distorts later partial/trailing/time logic. Management is not based on original R.

### H-10 — Position recovery loses essential ownership and management state

**Classification:** Confirmed static defect  
**Evidence:** Startup reconstruction restores only ticket, entry, current SL/TP, and entry time; it sets strategy to `UNKNOWN` and fixed-stop state (`PositionManager.mqh:303-341`). It does not restore direction, original stop/risk, partial exits, MFE/MAE, signal ID, strategy ownership, or pending orders. `InpUnknownPosPolicy` is unused.  
**Consequence:** Restart changes risk and management behavior, strategy limits become wrong, and unknown positions are neither quarantined nor handled per configuration.

### H-11 — Shadow mode is not a simulator

**Classification:** Confirmed unimplemented feature affecting test validity  
**Evidence:** Shadow execution creates one synthetic filled order row (`QuantBeastEA.mq5:607-629`) but never registers a virtual position, evaluates stops/targets, applies costs, logs a trade, or updates risk.  
**Consequence:** Shadow mode cannot validate expectancy, drawdown, lifecycle, risk locks, or strategy degradation.

### H-12 — Arbitration records acceptance before risk and execution

**Classification:** Confirmed static defect  
**Evidence:** `SignalArbitrator.mqh:245-315` records the ID and cooldown immediately after selection. Risk validation, sizing, margin checks, and order submission happen afterward.  
**Consequence:** A temporarily invalid size, margin state, or risk rejection suppresses a later executable signal even though no trade was placed.

### H-13 — Two arbitration modes are not implemented and one contradicts its comment

**Classification:** Confirmed static defect  
**Evidence:** `ARBITRATION_REGIME_PRIORITY` and `ARBITRATION_REQUIRE_CONFLUENCE` have no cases. `ARBITRATION_REJECT_CONFLICTS` falls through to `default`, which takes the first candidate rather than the documented highest score (`SignalArbitrator.mqh:245-317`).  
**Consequence:** Input selection does not reliably change behavior as documented; strategy order can determine the winner.

### H-14 — A successful `CTrade` wrapper call is not sufficient execution proof

**Classification:** Confirmed API misuse; broker outcome requires runtime proof  
**Evidence:** Market, pending, close, modify, and delete functions primarily trust the boolean result and do not classify all server retcodes (`BrokerAdapter.mqh:104-136,184-204,210-263`). Retry messages are emitted at `QuantBeastEA.mq5:680-686`, but no retry is scheduled or executed.  
**Consequence:** Requests can be mislabeled as fills/closes, rejected operations can remain unresolved, and `InpMaxRetries`/`InpRetryDelayMs` are not operational.

### H-15 — Order-type permissions and fill-mode input are disconnected

**Classification:** Confirmed static defect  
**Evidence:** `InpUseStopOrders`, `InpUseLimitOrders`, and `InpFillMode` are unused. If market orders are disabled, `PlaceStopOrder()` silently creates a limit order when price lies on the other side (`BrokerAdapter.mqh:164-186`) regardless of permission.  
**Consequence:** The EA can construct an order class explicitly disabled by configuration.

### H-16 — Regime safety is advisory only

**Classification:** Confirmed static defect  
**Evidence:** `RegimeEngine.IsSafeForTrading()` exists at `RegimeEngine.mqh:104-123` but is never called by main. Strategies contain inconsistent subsets of liquidity, shock, event, and session checks.  
**Consequence:** A regime classified unsafe does not produce a central hard gate.

## Medium-priority defects

1. **M-01 — Higher-timeframe alignment has no direction.** `htf_aligned` only means both inverted slopes have the same sign (`FeatureEngine.mqh:336-344`). Breakout uses the same boolean for long and short, so it does not require the HTF bias to match the proposed side.
2. **M-02 — Trend persistence can read uninitialized zeros.** `FeatureEngine.mqh:351-360` resizes a full segment but near the end copies fewer than `m_trendLookback` values, then regresses the full array.
3. **M-03 — “Standard-deviation distance” is an ATR proxy.** `FeatureEngine.mqh:546-548` assigns normalized ATR distance; MR thresholds and documentation call it SD.
4. **M-04 — Rejection wick is non-directional and forming-bar based.** MR long and short consume the same maximum wick (`FeatureEngine.mqh:489-498`), so an upper wick can confirm a long and a lower wick can confirm a short.
5. **M-05 — Trend pullback ignores configured trigger mode and max pullback bars.** Both are stored but not used in setup logic (`TrendPullbackEngine.mqh:20-56,100-203`).
6. **M-06 — Mean reversion ignores trigger mode and opposite-band target.** `m_targetSDBandR` and `m_triggerMode` do not affect entries/exits (`MeanReversionEngine.mqh:20-53,95-208`).
7. **M-07 — Failed-breakout reclaim threshold and target-VWAP R do not drive logic.** Values are stored but objective reclaim sequencing is absent.
8. **M-08 — Breakout compression input is stored but not used.** `m_compressionPct` does not affect eligibility; the global feature threshold does.
9. **M-09 — Signal duplicate ID changes every minute.** `SignalArbitrator.mqh:76-99` embeds minute time and ignores entry; repeated economic setups on later minutes are new IDs.
10. **M-10 — Rejections created inside arbitration are not re-journaled.** Main journals before arbitration (`QuantBeastEA.mq5:508-537`), so cooldown/conflict/stacking/arbitration-lost outcomes are missing from signal evidence.
11. **M-11 — HTF score alignment can reduce the arithmetic score.** The arbitrator adds only 0.2 but increments the denominator (`SignalArbitrator.mqh:150-157`).
12. **M-12 — Trade journal header and rows disagree.** Header has 22 fields; `LogTrade()` writes 20 and omits entry spread/slippage (`TradeJournal.mqh:89-95,182-205`). It also queries position type/volume without selecting a position and after a close may have no position selected.
13. **M-13 — Performance statistics are incomplete.** Expectancy, averages, and max drawdown are never calculated; `avg_r` is overwritten by the last trade (`TradeJournal.mqh:215-238`). `OnTester()` therefore cannot produce the documented fitness.
14. **M-14 — Ticket logging uses `IntegerToString` for `ulong`.** Numerous execution and position paths can truncate or misrepresent 64-bit tickets.
15. **M-15 — State keys are not scoped by account, symbol, chart, or magic.** `Core/StateStore.mqh:19-36` uses global `QB_*` names, allowing collisions between accounts/instances.
16. **M-16 — State version mismatch does not migrate, quarantine, or fail safe.** `StateStoreInit()` merely writes the new version (`StateStore.mqh:236-245`).
17. **M-17 — Challenge deposits/withdrawals are not modeled.** Absolute equity targets determine stages and the `balance` parameter is unused (`ChallengeMode.mqh:99-170`).
18. **M-18 — Data-quality initialization requires live trading permissions.** `RunAllChecks()` treats disabled account/expert trading as fatal (`DataQuality.mqh:130-140`), which can prevent Diagnostic or Shadow mode from attaching when trading is intentionally disabled.
19. **M-19 — Configured stale-quote threshold is unused.** Market freshness uses a fixed constant (`MarketData.mqh:280-283`), and feature stale detection hardcodes 5000 ms (`FeatureEngine.mqh:577-578`).
20. **M-20 — Self-test 5 always passes.** `QuantBeastEA.mq5:881-887` contains `|| true`, so it cannot detect feature-engine failure.

## Low-priority and maintainability defects

1. **L-01 — 22 inputs are declared but never referenced outside configuration:** `InpStaleQuoteMs`, `InpMaxPriceJumpPoints`, `InpBarWarmup`, `InpRetryDelayMs`, `InpUseStopOrders`, `InpUseLimitOrders`, `InpFillMode`, `InpCloseBeforeSessionEnd`, `InpCloseBeforeRollover`, `InpUseGlobalVars`, `InpShowChartObjects`, nine alert toggles/channels, `InpLogSelfTestDetails`, and `InpUnknownPosPolicy`.
2. **L-02 — Two live presets contain an invalid key.** `XAUUSD_Conservative_Live.set:9` and `XAUUSD_Challenge_Example.set:10` use `InpRskPercent`, so the intended risk override is ignored.
3. **L-03 — Alert inputs and `UI/Alerts.mqh` are disconnected.** The main EA neither includes nor instantiates the alert class.
4. **L-04 — Five named architectural modules are empty shells:** allocation, exposure, reconciliation, recovery, and counterfactual tracking.
5. **L-05 — Six timeframes each reload up to 2,000 bars on every tick.** `BarCache.Update()` calls full `CopyRates` for every active TF (`BarCache.mqh:124-166`), creating avoidable tester/live overhead.
6. **L-06 — FeatureEngine bypasses its cache for VWAP.** `FeatureEngine.mqh:519-530` calls `CopyRates` again.
7. **L-07 — PositionManager has a fixed 20-record array without reconciliation on overflow.** A real EA-owned position can become unmanaged if registration reaches that cap (`PositionManager.mqh:98-102`).
8. **L-08 — Dashboard and active-order polling do not run on data-quality failures.** They are downstream of the early return.

## Architecture assessment

| Architectural property | Verdict | Evidence-based assessment |
|---|---|---|
| Separate strategy classes | Preserved structurally | BO, FBO, TP, and MR remain independent classes and do not call the broker directly. |
| Central risk | Present but bypassable/incomplete | Entry flows through RiskEngine, but actual lot risk, proposed exposure, daily counts, close updates, and kill synchronization are absent. |
| Central execution | Preserved structurally | Broker calls are centralized, but lifecycle/retcode/protection handling is incomplete. |
| Position ownership | Fails operationally | All strategies use the base magic; order tickets are treated as position tickets; restart assigns `UNKNOWN`. |
| Persistence | Partial and unsafe | Some terminal globals exist, but date logic, scoping, locks, challenge fields, and position state are incomplete. |
| Reconciliation | Fails requirements | Only open positions in the magic range are shallowly reconstructed; pending orders and unknown-position policy are absent. |
| Shared tester/live logic | Nominal only | The same code would execute, but source does not compile and shadow/test analytics do not model lifecycle. |

The intended separation should not be collapsed during repair. The defect is missing end-to-end contracts between the layers, not the existence of layers.

## Regime-engine assessment

**Verdict: Not test-ready.**

- Trend direction is inverted because of newest-first regression.
- Volatility and most structural inputs include forming bars.
- Breakout, failed-breakout, reclaim, displacement, higher-low, and lower-high features are not populated.
- Session levels and opening range are rolling approximations rather than session constructs.
- Structural confidence often defaults because required fields remain zero.
- Overall confidence averages values whose semantics are not comparable.
- `IsSafeForTrading()` is not a hard gate.
- There is no hysteresis/debounce, so rapid regime switching remains a runtime-proof-required risk after calculation fixes.

## Strategy-by-strategy verdict

| Strategy | Implemented | Reachable | Long/short | Lookahead/repaint | Test readiness |
|---|---|---|---|---|---|
| Breakout | Partial | Structurally evaluated, valid trigger unreliable/mostly self-contradictory | Superficially symmetric; HTF bias is not directional | Uses forming bar and a range containing that bar | **Not ready** |
| Failed Breakout | Partial | **No** under current FeatureEngine because eligibility fields stay zero | Source is superficially symmetric; no directional event history exists | Would use current quote/forming structures | **Not ready** |
| Trend Pullback | Partial | Narrowly possible after compile, but trend sign is inverted and impulse structure is unreachable | Formulas are broadly mirrored | Uses forming/MTF bar 0 and unconfirmed structure | **Not ready** |
| Mean Reversion | Partial | Potentially reachable after compile | Broadly mirrored; rejection wick is not directional | Uses forming bar; “SD” is ATR proxy | **Not ready** |

No strategy has a complete, objective setup-trigger-invalidation lifecycle matching `STRATEGY_SPEC.md`. No strategy has runtime evidence.

## Signal-arbitration assessment

**Verdict: Partial and not test-ready.** Hard risk does remain downstream of arbitration, which is the right architectural ordering, but acceptance is recorded too early, two modes are absent, conflict fallback is wrong, scores are not meaningfully calibrated across engines, duplicate identity is weak, and proposed exposure is not aggregated. Multiple candidates rejected by arbitration are not journaled with their final result.

## Risk assessment

| Requirement | Verdict |
|---|---|
| Broker-correct lot sizing | Fail: tick/point conversion assumption and minimum-lot forcing |
| Maximum trade risk | Fail: configured cap never compared with actual lots |
| Daily/weekly loss limits | Fail: date persistence and continuous rollover broken |
| High-water drawdown | Partial: static check exists; update/persistence paths are inconsistent |
| Open equity included | Yes at validation time, but validation occurs only when a new signal exists |
| Consecutive-loss lock | Fail: close hook is never called |
| Strategy trade limits | Fail: daily count hardcoded zero |
| Exposure limits | Fail: proposed order is not added |
| Challenge stages | Fail: initialization and enforcement incomplete |
| Locks survive restart | Fail |
| Kill switches | Fail: key global states are not enforced |

## Execution assessment

| Requirement | Verdict |
|---|---|
| Dynamic broker properties | Partial: properties are read, but sizing and validation do not use them correctly |
| Price/volume normalization | Partial: digits and volume step are applied; price is not rounded explicitly to tick size |
| Stops/freeze validation | Fail: helper exists but is not in order/modify path |
| Filling modes | Partial and unverified; configured preference unused |
| Safe retries | Fail: messages only, no retry state machine |
| Duplicate prevention | Partial and not persisted |
| Position-ticket reconciliation | Fail |
| Protective-stop guarantee | Fail |
| Partial fills | Fail |
| Netting and hedging | Unvalidated; current ticket assumptions are unsafe for both |
| Ownership-restricted emergency actions | Magic-range filtering is present, but all strategies share one base magic and ownership metadata is lost |

## Persistence and recovery assessment

### Terminal or VPS restart

The EA reloads a few terminal global variables and shallowly scans open positions. Daily and weekly baselines are interpreted incorrectly, several locks disappear, challenge risk/target/profit-lock/max-exposure fields are not restored, arbitrator cooldowns disappear, and pending-order state is lost.

### Open position recovery

Positions in the magic range are found, but strategy/signal ownership, original risk, direction in context, partial-exit state, management state, MFE/MAE, entry spread, and regime context are not reconstructed. A moved stop becomes the only stop known after restart, changing R logic.

### Pending-order recovery

Not implemented. `g_OrderPending` and `g_ActiveOrder` are process memory only.

### Corrupted state

No validation, checksum, atomic version migration, quarantine, or fail-closed policy exists. A version mismatch is simply overwritten.

### Unknown positions

`InpUnknownPosPolicy` is unused. Positions outside the magic range are ignored; positions inside are adopted as `UNKNOWN` without the configured report/quarantine/flatten behavior.

## Test evidence

### Performed

1. Read mission, agent rules, handoff, architecture, strategy, risk, testing, deployment, limitations, and build-audit documents.
2. Enumerated and hashed the main EA and all 40 include modules.
3. Compiled the untouched source with the bundled MT5 MetaEditor under the correct Wine prefix.
4. Confirmed source hash was unchanged after compilation.
5. Preserved MetaEditor output in `QuantBeastEA.log` and `TestEvidence/compile_20260715/QuantBeastEA.log`, with a manifest in `TestEvidence/compile_20260715/EVIDENCE.md`.
6. Confirmed `QuantBeastEA.ex5` was not generated.
7. Traced main runtime paths and searched all modules for required callbacks, gates, feature writers, input consumers, and stubs.
8. Counted 169 inputs and confirmed 22 are unused.

### Not performed / blocked

- Unit/scenario tests: no harness exists and the project does not compile.
- Diagnostic attachment: blocked by compilation.
- Strategy Tester baseline or holdout: blocked and would be invalid before lifecycle/feature repairs.
- Shadow lifecycle: implementation absent.
- Restart/pending-order recovery tests: blocked by compilation and missing recovery paths.
- Broker matrix, netting/hedging, disconnect, partial-fill, rejected-stop, and unprotected-fill tests: not run.
- Demo forward or live: prohibited.

## Known limitations separated by type

### Bugs

All confirmed compile, control, sizing, persistence, lifecycle, feature, regime, and strategy defects listed above.

### Unimplemented features

- Allocation and standalone exposure engines
- Full reconciliation and recovery engines
- Counterfactual simulation
- Real shadow-position lifecycle
- Alerts integration
- Automated news calendar
- Full strategy trigger/exit variants
- Strategy-specific magic/ownership and performance callbacks
- Automated scenario tests

### Broker limitations / runtime-proof-required risks

- OTC tick volume is not centralized volume.
- Commission, swap, tick value, conversion currency, and filling semantics vary by broker.
- Exact behavior of stop rejection, partial fills, netting/hedging tickets, market execution, and RETURN filling requires broker-specific tests.
- XAUUSD digits, point, tick size, contract size, stop/freeze levels, and symbol suffixes vary.

### Strategy Tester limitations

- Tester fills and latency do not prove live execution safety.
- Manual news strings and broker-server session time must be aligned to the tested history.
- Current-bar and MTF indexing errors can create tester/live divergence.
- Optimization fitness is unusable until trade lifecycle statistics are correctly populated.

### Unvalidated strategy assumptions

- None of the four engines has demonstrated positive expectancy.
- Regime confidence and arbitration scoring are uncalibrated.
- Session approximations, ATR-based “SD,” and raw tick-volume VWAP are research proxies, not proven edges.
- Aggressive-growth or Challenge objectives are mission goals, not evidence.

## Minimal repair sequence

1. **Restore a zero-error, zero-warning compile** without changing trading intent: namespace custom enums, move/shared-declare lot mode, add MR trigger input, fix array/reference/const/API calls, and correct DataQuality APIs.
2. **Add a deterministic test harness before behavior changes:** symbol-adapter math, closed-bar/MTF indexing, session rollover/DST, long-short fixtures, sizing across point/tick specifications, and transaction-state fixtures.
3. **Repair transaction and protection invariants:** server-retcode classification, deal/order/position mapping, partial fills, SL verification, emergency close, and ownership-safe `OnTradeTransaction` handling.
4. **Repair central risk:** use `OrderCalcProfit` for actual proposed lots, reject unaffordable minimum lots, enforce max risk and post-trade exposure, wire close events, daily counters, lock resets, and persistent account-scoped state.
5. **Repair feature/regime validity:** closed bars only, correct chronological regression, stable MTF mapping, real session/opening ranges, and implement or remove every structural feature dependency.
6. **Repair each strategy independently** with objective setup/trigger/invalidation tests and no shared parameter optimization.
7. **Repair arbitration and shadow analytics:** record final disposition only after risk/execution, model virtual positions/costs, complete journals/performance, and make `OnTester` trustworthy.
8. **Repair recovery and presets:** pending orders, unknown-position policy, full context persistence, valid preset keys, and unused-input disposition.
9. **Run gates in order:** compile → unit/scenario → Diagnostic → Shadow → tester train/holdout → restart/recovery → demo forward. Do not skip to optimization or live challenge testing.

## Compile-risk assessment for repairs

- **Low compile risk:** renaming custom order-state members; adding the missing MR input; correcting preset keys.
- **Medium compile risk:** moving the lot-mode enum, correcting MQL const/reference signatures, and replacing invalid connectivity APIs.
- **High behavioral risk:** transaction reconciliation, sizing, position ticket mapping, persistence, feature chronology, and strategy reachability. These changes can materially alter every backtest and therefore require fixture tests before any performance comparison.

## Final readiness

```text
NOT SAFE TO TEST
```

The next authorized task should be a compile-and-safety repair pass, not optimization. The source should remain live-disabled throughout that work.
