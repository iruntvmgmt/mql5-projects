# QuantBeast Architecture

**Version:** 1.00 documentation baseline  
**Status:** Incomplete framework; not approved for live trading  
**Source specification:** `XAUUSD Quant Beast EA.docx`  
**Mission and audit context:** `PROJECT_MISSION_AND_AUDIT_CONTEXT.md`

## Purpose

QuantBeast is intended to be one deployable MT5 Expert Advisor with internally separated market-data, feature, regime, strategy, arbitration, risk, execution, position-management, persistence, analytics, and UI responsibilities.

Its research mission includes a separate, explicitly acknowledged Challenge mandate for bounded high-risk account-growth experiments. That mandate does not alter the centralized-control architecture and does not allow martingale, averaging down, uncontrolled leverage, missing stops, or bypassed account protection.

This document distinguishes the intended architecture from the code that currently exists. A component being present on disk does not mean its complete behavior is implemented or tested.

## Intended pipeline

```text
Market snapshot
  -> bar/tick/session cache
  -> feature engine
  -> regime engine
  -> four independent strategy engines
  -> signal arbitrator
  -> centralized risk validation
  -> position sizing
  -> Shadow virtual portfolio or broker execution adapter
  -> position manager
  -> transaction reconciliation, journals, persistence, dashboard, alerts
```

Strategies may only produce `StrategySignal` values. They must not place or modify orders directly. The broker adapter is the only intended live-order boundary.

## Current runtime flow

### Startup (`OnInit`)

1. Select effective operating mode and downgrade unacknowledged challenge mode to shadow.
2. Initialize symbol, tick, bar, session, and data-quality services.
3. Initialize feature and regime engines.
4. Initialize all four strategies and signal arbitration.
5. Initialize sizing, risk, challenge, kill-switch, broker, and position-management services.
6. Open CSV journals and initialize the dashboard.
7. Load selected terminal-global state.
8. Reconstruct EA-magic open positions at a basic level.
9. Run embedded startup checks.
10. Start the one-second timer.

### Tick processing (`OnTick`)

1. Capture market snapshot and update tick/bar/session state.
2. Detect a new execution-timeframe bar.
3. Run pre-trade data validation.
4. Recalculate heavy features on a new bar.
5. Classify regime.
6. Update challenge mode and live tracked positions.
7. Evaluate automatic kill conditions.
8. On a new bar, evaluate strategies, arbitrate, validate risk, size, and execute.
9. Update dashboard and pending-order status.

### Trade transactions

`OnTradeTransaction` processes owned entries/exits, pending partial fills, deferred final-close reconciliation, trade journaling, and risk updates. Deterministic ownership and state-transition fixtures pass, but real broker callback ordering remains unproven.

### Timer

The timer checks terminal connectivity and periodically saves limited state. It does not perform full maintenance, alert deduplication, session-end handling, or state reconciliation.

## Module status

| Layer | Module | Current status | Notes |
|---|---|---:|---|
| Core | Enums, Types, Constants | Substantive | Strongly typed structures exist. Some fields are never populated. |
| Core | Configuration | Partial | Extensive inputs exist; many safety and operator controls are now wired and tested, while advanced strategy/exit variants and research controls remain partial or explicitly documented. |
| Core | Time/Math/Diagnostics | Substantive | Utility functions exist; require bug and boundary review. |
| Core | StateStore | Partial | Saves scoped risk/challenge/kill values, strategy daily counts, broker-rejection streaks, and bounded arbitration duplicate/cooldown state; full per-position lifecycle context is not yet durable. |
| Data | MarketData | Substantive | Dynamic symbol properties and market snapshots exist. |
| Data | BarCache | Substantive | Centralized cache exists for configured timeframes. Required timeframe and sequencing tests are absent. |
| Data | TickState | Substantive | Rolling tick/spread measurements exist. |
| Data | SessionEngine | Partial | Session classifications exist; DST remains manual. |
| Data | DataQuality | Partial | Basic checks exist; several configured checks are not wired. |
| Data | FeatureEngine | Partial | Many features exist, but critical breakout/reclaim/structure fields are never calculated. |
| Data | NewsInterface | Partial | Manual timestamp lockout only. |
| Regime | Four classifiers and engine | Partial | Structural inputs are populated from closed bars; classifier thresholds and switching still require runtime/scenario proof. |
| Strategies | BO, FBO, TP, MR | Partial | Real long/short methods exist; required trigger/exit variations are incomplete. |
| Portfolio | SignalArbitrator | Substantive | Scoring, cooldown, duplicate, conflict, exposure, lower-ranked rejection, all arbitration enum modes, and bounded restart persistence for accepted-signal hashes/timestamps are implemented and deterministically tested. Organic true-tick CSV suffix proof exists. |
| Portfolio | AllocationEngine | Stub | Constructor only. |
| Portfolio | ExposureManager | Stub | Constructor only; some single-symbol exposure checks live in RiskEngine. |
| Risk | PositionSizer | Substantive | Four sizing modes are represented; requires broker and formula tests. |
| Risk | RiskEngine | Partial | Pre-trade checks exist; close-event updates and some configured limits are disconnected. |
| Risk | ChallengeMode | Partial | Stage structure exists; leverage, attempt, profit-lock, and pyramiding enforcement are incomplete. |
| Risk | KillSwitch | Partial | State and actions exist; global entry/symbol gates and several triggers are not wired into entry flow. |
| Execution | BrokerAdapter | Partial | Central CTrade wrapper has bounded price retries, server-confirmed responses, post-fill protection repair, and centralized fail-closed emergency ownership; actual broker fault behavior remains unproven. |
| Execution | PositionManager | Partial | Live path has breakeven, partial, ATR trail, and time stop; session/rollover exit and branch-level runtime proof remain incomplete. |
| Execution | ShadowPortfolio | Substantive | Broker-free market fills, stops, targets, partial, breakeven, ATR trail, time stop, costs, equity/exposure, MFE/MAE, flatten, and close events; pending orders unsupported. |
| Execution | Reconciliation | Stub | Constructor only. |
| Execution | RecoveryEngine | Stub | Constructor only. |
| Analytics | TradeJournal | Partial | Signal/order/trade writers exist and completed tracked closes can reach `LogTrade`. Signal decisions are now written only after their final strategy/arbitration/risk outcome, rejected direction is preserved, and signal IDs include direction; organic true-tick suffix proof is under `TestEvidence/organic_true_ticks_20260716/`. |
| Analytics | CounterfactualTracker | Stub | Constructor only. |
| Testing | SafetyTests | Partial | Embedded deterministic fixtures cover 51 policies/lifecycles, including rejected-signal direction, regime safety, all arbitration enum modes, duplicate/cooldown persistence, final-decision signal writing, performance without file journaling, live-mode gates, live acknowledgement gating, state scoping, unknown-position no-adoption, alert routing, preflight, session/rollover exits, chart-object suppression, strategy-counter persistence, and strategy-input wiring. Organic true-tick data reached accepted FBO BUY/SELL; BO/TP/MR accepted lifecycles, actual broker faults, and normal-terminal restart remain unproven. |
| UI | Dashboard | Partial | Basic dashboard exists; not every required field is displayed. |
| UI | Alerts | Partial | Terminal/push helper is included and wired for key signal, order, protection, fill, and reconciliation categories with Strategy Tester emission suppression. Source now propagates enabled delivery failure into an entry kill, but this latest change still needs fresh compile and Shadow fixture evidence; real EA terminal/push delivery remains unproven. |

## Operating-mode contract

| Mode | Live broker orders | Current behavior | Required remaining work |
|---|---:|---|---|
| Diagnostic | Never | Entry evaluation is skipped; startup checks and dashboard run. | Expand feature, risk, strategy, execution, and recovery tests. |
| Shadow | Never | Runs signal/risk pipeline and virtual market-position lifecycle with synthetic equity/exposure and journals. | Add pending-order policy/simulation and deterministic evidence for every management branch. |
| Conservative live | Yes | Uses live broker adapter. | Do not enable until compile, scenario, tester, restart, protection, and demo gates pass. |
| Challenge live | Yes after acknowledgment | Adjusts sizing risk by stage. | Complete and test hard stage DD, daily attempts, leverage, profit lock, and safe pyramiding enforcement. |

## Ownership and state

EA-owned orders and positions are identified by a magic-number range. Order comments include a strategy token when initially placed. Startup reconstruction can recover selected strategy ownership and original risk from broker history where available; unknown positions follow the configured non-adoption/quarantine/report policy. Owned pending orders are cancelled fail-closed on startup rather than restored.

Persistent state now includes scoped risk/challenge/kill values, same-day strategy counters, broker-rejection streaks, and bounded arbitration cooldown/duplicate memory. State that is not yet fully preserved includes durable signal IDs beyond journal strings, partial-exit detail, scale-in counts, pending-order lifecycle state, full position-management context, and automatic migration for old schemas.

## Non-negotiable architectural gates

Before live approval, the following must be demonstrated:

- Shadow and live market-entry paths model the same core stop/target/partial/breakeven/trail/time lifecycle except broker transmission; pending orders and some session/rollover behavior are not yet at parity.
- Every entry is blocked by global entry and symbol kills.
- Every fill is verified to have legal protective stops; failures trigger emergency handling.
- `OnTradeTransaction` updates positions, risk, journals, strategy callbacks, and reconciliation.
- Restart recovery reconstructs positions and pending orders and verifies broker protection.
- Unknown-position policy is enforced.
- Every declared strategy dependency is calculated from confirmed, non-future data.
- Automated tests cover data, sizing, all four strategies, arbitration, execution states, and recovery.

## Change-control rule

When implementation changes, update this document, `KNOWN_LIMITATIONS.md`, and `BUILD_AUDIT.md` in the same change. A feature must not be marked complete until its runtime path and test evidence both exist.
