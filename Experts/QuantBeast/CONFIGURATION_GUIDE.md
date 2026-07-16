# QuantBeast Configuration Guide

**Status:** Documents current inputs, including inputs that are presently inactive.  
**Safety default:** Shadow mode.  
**Live-use status:** Not approved.

**Latest evidence:** 2026-07-16 Shadow regression `39 passed, 0 failed`; organic true-tick CSV proof exists under `TestEvidence/organic_true_ticks_20260716/`, and live-mode strategy/execution gates are covered under `TestEvidence/live_strategy_gate_20260716/`.

## Loading presets

Preset files are stored beside `QuantBeastEA.mq5`. Always inspect the loaded Inputs tab after applying a preset.

The conservative and challenge preset risk keys were corrected to `InpRiskPercent` on 2026-07-15. They remain prohibited for live use because runtime validation is incomplete.

As of 2026-07-16, production live modes are additionally gated to FBO-only and market-order-only. Conservative Live and acknowledged Challenge Live fail initialization unless `InpFBO_Enabled=true`, `InpBO_Enabled=false`, `InpTP_Enabled=false`, `InpMR_Enabled=false`, `InpUseMarketOrders=true`, `InpUseStopOrders=false`, `InpUseLimitOrders=false`, and `InpMaxPendingOrders=0`. This preserves Shadow/Diagnostic research flexibility while preventing unproven BO/TP/MR and pending-order live transmission.

## General and operating mode

| Input | Default | Current behavior |
|---|---:|---|
| `InpMode` | Shadow | Diagnostic, Shadow, Conservative Live, or Challenge Live. |
| `InpAcknowledgeChallengeRisk` | `false` | Challenge request falls back to Shadow unless explicitly true. |

Never set a live mode until all gates in `LIVE_DEPLOYMENT_CHECKLIST.md` pass.

## Symbol and broker

| Input | Default | Current behavior/status |
|---|---:|---|
| `InpPrimarySymbol` | empty | Empty uses attached chart `_Symbol`; override is supported. |
| `InpBrokerUTCOffsetHours` | `2` | Stored for diagnostics/configuration; session boundaries are currently entered directly in broker-server time. |
| `InpBrokerIsDST` | `true` | Stored/manual; it does not automatically shift session inputs. |
| `InpMaxSpreadPoints` | `50` | Used by global pre-trade validation. Individual strategies also contain hardcoded tighter limits. |
| `InpStaleQuoteMs` | `5000` | Passed into market-snapshot freshness checks. |

## Timeframes

Defaults are M5 execution, M1 short, M15 medium, H1 long, H4 higher timeframe, and D1 daily. The bar cache initializes these six configured slots. The specification’s full M1/M3/M5/M15/M30/H1/H4/D1 support has not been explicitly tested.

## Sessions

Asia, London pre-open/open, New York pre-open/open/afternoon, rollover, and Friday-close inputs are passed to `SessionEngine`.

Operator requirements:

1. Confirm the broker server clock.
2. Set UTC offset and DST flag.
3. Verify the displayed session classification across a full day.
4. Recheck after DST changes.

## Data quality

| Input | Status |
|---|---|
| `InpRequireDataQuality` | Active during startup. |
| `InpCheckBarSequence` | Passed into startup checks. |
| `InpMinBarsRequired` | Passed into startup checks. |
| `InpMaxPriceJumpPoints` | Declared but unused. |
| `InpBarWarmup` | Declared but unused. |

## Regime engine

ATR period, trend lookback/slope threshold, compression settings, expansion bars, and shock multiplier initialize feature/regime services. Directional failed auctions, reclaim, displacement, prior-range breakouts, session levels, and closed-bar trend features are populated; runtime classification evidence is still required.

## Strategy inputs

### Breakout (`InpBO_*`)

Controls enablement, compression, trigger enum, displacement, ATR stop, target R, confidence, and HTF bias. Candle-close/displacement modes use the completed primary bar and prior range. `InpBO_CompressionPct` does not yet calculate an independent strategy-specific percentile; global compression features drive eligibility.

### Failed breakout (`InpFBO_*`)

Controls penetration, age, reclaim threshold, trigger enum, sweep stop, targets, and confidence. Required directional failed-auction fields are populated. Separate midpoint/VWAP target-policy behavior is still incomplete and runtime reachability is unproven.

### Trend pullback (`InpTP_*`)

Controls directional efficiency, persistence, HTF agreement, pullback depth/duration, extension target, structural stop, trigger enum, and confidence. Trigger mode is active; the maximum pullback-bar input still lacks a dedicated pullback-age feature.

### Mean reversion (`InpMR_*`)

Controls trend ceiling, VWAP deviation, directional wick threshold, targets, emergency stop, and confidence. Deviation now uses a weighted standard deviation around VWAP and trigger mode is active. A distinct opposite-band target policy remains incomplete.

## Arbitration

The arbitration method, cooldown, duplicate window, opposite-signal rule, and same-direction stacking rule are active in the arbitrator. Signal journal IDs include direction and final decision rows are proven in deterministic and organic true-tick evidence. Cooldown and prior signal IDs are not persisted across restart.

## Position sizing

| Input | Purpose |
|---|---|
| `InpLotMode` | Fixed lots, fixed account-currency risk, risk percent, or volatility adjusted. |
| `InpFixedLots` | Used only in fixed-lot mode. |
| `InpFixedRiskCurrency` | Used only in fixed-risk mode. |
| `InpRiskPercent` | Used in percentage-risk mode; challenge mode can replace it dynamically. |
| `InpVolAdjRiskTarget` | Used in volatility-adjusted mode. |
| `InpMinLotSize` / `InpMaxLotSize` | User caps combined with broker constraints. |
| `InpSlippageAllowancePts` | Included in sizing estimates. |
| `InpCommissionEstimate` | Included in sizing estimates. |

All sizing modes require deterministic tests before live use.

## Trade and account risk

Configured controls include stop-distance limits, minimum reward:risk, daily/weekly loss, high-water drawdown, consecutive losses, margin level, emergency equity floor, position/pending limits, and aggregate lot exposure.

Current implementation updates per-strategy daily counts, close-event consecutive losses, daily/weekly equity periods, high-water drawdown, sized trade risk, and projected exposure. All require deterministic runtime tests before live use.

## Challenge mode

Stage targets and risk percentages, stage drawdown, attempts, profit-lock percentage, and pyramiding preference are configurable. Not all are enforced end to end. Challenge mode must remain disabled until its dedicated scenario suite passes.

## Execution

| Input | Status |
|---|---|
| `InpMaxRetries` | Bounds retries for known no-fill price retcodes. |
| `InpRetryDelayMs` | Used between live retries; skipped in Strategy Tester. |
| `InpMaxConsecutiveBrokerFailures` | Latches the entry kill after this many consecutive broker-attempted, rejected submission cycles; values below one are treated as one. A server-confirmed acceptance resets the streak. |
| `InpOrderExpirySeconds` | Used for pending-order expiry tracking. |
| `InpUseMarketOrders` | Selects market versus pending execution. |
| `InpUseStopOrders` | Enforced when a pending entry is stop-class. |
| `InpUseLimitOrders` | Enforced when a pending entry is limit-class. |
| `InpFillMode` | Validated against broker-supported filling flags; zero selects auto. |

## Position management

Breakeven, partial close, ATR trail, and time stop are wired. Stop modifications cannot loosen risk and post-fill SL/TP protection is verified with a fail-closed exit. `InpCloseBeforeSessionEnd` and `InpCloseBeforeRollover` remain incomplete, as do swing/chandelier, news, momentum-failure, and regime-deterioration exits.

## News lockout

When enabled, manually enter comma-separated broker-server timestamps:

```text
2026.07.15 08:30,2026.07.15 10:00
```

An empty list means no events are blocked even though `InpNewsEnabled=true`. No automatic economic calendar is present.

## Persistence

Persistence is enabled only when both `InpPersistState` and `InpUseGlobalVars` are true. Terminal Global Variables are the only implemented persistence backend.

Daily/weekly dates and equity, locks, high-water mark, consecutive losses, consecutive broker-submission failures, challenge state, and kill state are represented. The current fail-closed state schema is v4. Broker history recovers part of position ownership/initial risk; see `KNOWN_LIMITATIONS.md` for remaining restart gaps.

## Logging and dashboard

Signal, order, and trade journal inputs open their respective files. Existing CSV files append at end and fail closed if append positioning fails. Owned final-close transactions feed completed-trade rows and rolling metrics, and performance metrics update even when file trade journaling is disabled. Organic true-tick suffix evidence proves final signal decisions, separate order rows, and separate trade rows. Dashboard enablement, location, font size, and color are active. `InpShowChartObjects` is unused.

## Alerts

All alert inputs are currently inactive because `CAlerts` is not instantiated by the EA. Do not rely on terminal or push notifications.

## Testing and unknown positions

`InpSelfTestOnInit` is active and runs symbol, normalization, stop, series-direction, closed-bar, session, and broker-aware sizing fixtures. `InpLogSelfTestDetails` is not yet used to suppress details. `InpUnknownPosPolicy` is enforced during startup reconstruction.

## Preset intent

| Preset | Intended use | Current status |
|---|---|---|
| `XAUUSD_Diagnostic.set` | Startup checks only | Approved; equivalent startup fixtures passed in the Shadow tester run. |
| `XAUUSD_Shadow.set` | Broker-free research simulation | Approved for market-intent mechanical research; pending-order intents are rejected and profitability remains unvalidated. |
| `XAUUSD_Conservative_Live.set` | Future explicitly authorized FBO-only demo/live validation | FBO-only, market-order-only, pending disabled, tighter risk; still not approved. |
| `XAUUSD_Challenge_Example.set` | Explicit aggressive example | Key corrected; still not approved and Challenge validation incomplete. |
