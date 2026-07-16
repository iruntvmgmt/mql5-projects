# QuantBeast Risk Specification

**Status:** Partial implementation; not live validated.  
**Authority:** All trades must pass centralized risk validation and centralized sizing.

**Latest evidence:** 2026-07-16 deterministic Shadow regression `45 passed, 0 failed`; organic true-tick Shadow evidence includes accepted FBO BUY/SELL entries and a central-risk rejection for excessive stop distance. Live-mode initialization is gated to FBO-only, market-order-only operation and non-flattening unknown-position recovery until broader evidence exists.

## Risk flow

```text
StrategySignal
  -> SignalArbitrator
  -> RiskEngine.ValidateTrade
  -> PositionSizer.CalculateLots
  -> margin validation
  -> shadow/broker execution
  -> fill protection verification
  -> close-event risk update and persistence
```

All listed stages are connected in source. Deterministic and organic Shadow evidence proves broker-free routing, accepted FBO entries, and central-risk rejection journaling. Broker-fill protection, close-event accounting, and persistence still require live-path fault-injection evidence before any live approval.

## Position sizing modes

The sizer represents:

1. Fixed lots
2. Fixed account-currency risk
3. Percentage of equity risk
4. Volatility-adjusted risk

All results should be normalized to broker minimum, maximum, and step. Sizing must include tick value/tick size, stop distance, estimated commission, spread/slippage allowance, and broker margin requirements.

### Required sizing tests

- Two-digit and three-digit XAUUSD symbols
- Different contract sizes, tick sizes, tick values, account currencies, and lot steps
- Zero, negative, too-small, and too-large stop distances
- Requested risk below the broker minimum tradable risk
- Min/max user cap interaction with broker limits
- Fixed, percentage, currency-risk, and volatility modes
- Insufficient margin
- Expected loss tolerance after costs

## Implemented pre-trade checks

`CRiskEngine.ValidateTrade` currently checks:

- Entry/daily/weekly/drawdown lock state internal to RiskEngine
- Emergency equity floor
- Margin level
- Daily and weekly equity loss
- High-water drawdown
- Consecutive losses
- Maximum positions and pending orders
- Current aggregate lot exposure
- Per-strategy positions and nominal daily trades
- Minimum/maximum stop distance
- Minimum expected R:R
- Minimum confidence

## Known enforcement gaps

- Sized orders are revalidated with `OrderCalcProfit()`-based broker loss estimates plus configured costs, `InpMaxRiskPerTrade`, and projected post-trade lot exposure before submission.
- Close events now call `UpdateAfterClose`, and material risk state is persisted when persistence is enabled and version-compatible. Duplicate/out-of-order broker transaction behavior still lacks fault-injection evidence.
- KillSwitch entry, symbol, strategy, cancel, flatten, and emergency states are connected to the main control paths; live runtime proof is pending.
- Per-strategy daily-trade accounting is connected in memory but is not persisted across restart.
- Daily/weekly period rollover and persisted start-equity semantics have deterministic state restoration coverage but not a real multi-session restart test.
- Maximum holding is enforced by position management; pending lifetime is not authoritative because Shadow pending intents are rejected and live pending recovery is fail-closed cancellation.
- Maximum leverage is not enforced as an independent configured cap.
- Pending partial-fill and deferred/deduplicated close transitions are deterministic-tested. Actual broker callback ordering, protection-repair, and retry sequences are not yet proven at runtime.

## Account protections

| Protection | Code exists | End-to-end wired | Tested |
|---|---:|---:|---:|
| Emergency equity floor | Yes | Yes pre-trade | No live-path scenario evidence |
| Daily loss lock | Yes | Yes | Deterministic Shadow/state fixture |
| Weekly loss lock | Yes | Yes | Deterministic state fixture |
| High-water drawdown | Yes | Yes | Deterministic Shadow/state fixture |
| Consecutive loss lock | Yes | Yes close-event update | Deterministic state restore fixture |
| Margin-level block | Yes | Yes pre-trade | No scenario evidence |
| Position limit | Yes | Yes pre-trade | No |
| Pending-order limit | Yes | Yes pre-trade | No |
| Aggregate lot exposure | Yes | Yes, including proposed order | Deterministic and Shadow organic evidence; no live-path scenario evidence |
| Strategy position limit | Yes | Partial after restart | No |
| Strategy daily-trade limit | Yes | In-memory only | No restart evidence |
| Max leverage | No | No | No |
| Unprotected-fill emergency | Yes | Two-pass repair then centralized emergency close/flatten latch | Deterministic fault matrix passes; no actual broker fault evidence |

## Kill-switch hierarchy

Required independent states:

- Strategy kill
- Entry kill
- Symbol kill
- Cancel all
- Flatten all
- Emergency

The main EA enforces strategy, entry, and symbol kills before new entries and continues management of existing positions. Cancel-all, flatten-all, and emergency actions are processed independently of entry data quality.

Required triggers include stale quote, repeated rejection, stop-placement failure, equity/drawdown limits, disconnect, state mismatch, unknown positions, margin emergency, abnormal spread, and impossible market data. Repeated broker rejection now uses a persisted consecutive failed-submission-cycle counter and configurable threshold; only an actual broker attempt can increment it, while server-confirmed acceptance resets it. Actual broker rejection and reconnect behavior remain unproven.

## Challenge mode

Challenge mode requires explicit acknowledgment and contains five target/risk stages. It must never use martingale or add to losing positions.

Before challenge mode can be called complete, implement and test:

- Correct initial stage initialization
- Stage target advancement
- Hard stage drawdown response
- Attempt counting and reset semantics
- Daily attempt limit
- Profit-lock enforcement, not just calculation
- Maximum total leverage
- Projected aggregate risk
- Pyramiding only into profitable and already-protected positions
- Immediate persistence of stage transitions
- Safe behavior after restart and account deposits/withdrawals

## Position management risk

Currently wired:

- Fixed broker-side SL/TP at entry request
- Breakeven plus points
- One partial close flag
- ATR trailing stop
- Time stop
- Post-fill SL/TP verification, one repair attempt, and fail-safe close/emergency latch
- Close-event risk/analytics updates through `OnTradeTransaction`

Still required:

- Runtime fault evidence for post-fill verification, repair, and emergency close
- Full broker freeze-level behavior proof before every modification
- Break-even plus actual costs
- Swing and chandelier trails
- Session-end, rollover, pre-news, momentum-failure, and regime-deterioration exits
- Broader trade-close reason coverage and duplicate/partial transaction proof
- Pyramiding controls
- Complete restart restoration of original signal/regime/MFE/MAE/partial state where broker history cannot reconstruct it

## Risk acceptance gate

Live approval requires evidence that:

1. Every proposed lot size stays within configured and broker risk limits.
2. Global kill states prevent all new entries.
3. Every live fill is protected or immediately closed.
4. Risk counters update on every close and survive restart.
5. Daily/weekly/HWM locks trigger and persist in deterministic tests.
6. Projected exposure includes the proposed order.
7. Unknown positions cannot be modified accidentally.
8. Netting and hedging accounts are both explicitly handled or one is rejected safely. Current live policy rejects netting/exchange accounts and admits hedging only.
9. Challenge mode passes a dedicated destructive-edge-case test suite.
