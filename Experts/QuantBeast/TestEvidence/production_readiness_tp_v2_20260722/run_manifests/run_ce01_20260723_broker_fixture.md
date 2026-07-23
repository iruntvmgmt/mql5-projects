# Run manifest -- CONTROLLED_EXECUTION_FIXTURE ce01 (real Coinexx-Demo broker order)

- **Purpose:** Phases 7-10 acceleration per explicit user authorization --
  prove real broker-path infrastructure (submission, acknowledgement,
  fill, SL/TP registration, SL modification, close/flatten) using a
  bounded diagnostic order, NOT an organic strategy signal.
- **Evidence class:** `CONTROLLED_EXECUTION_FIXTURE` -- must never be used
  as evidence of strategy edge, organic reachability, or profitability.
- **Account:** Coinexx-Demo, login 871221, verified DEMO
  (`account_trade_mode == ACCOUNT_TRADE_MODE_DEMO`) immediately before
  submission via `get_trading_account_info`.
- **Pre-flight checks (all passed immediately before order submission):**
  - Account type = demo, server = Coinexx-Demo, login = 871221.
  - Symbol = XAUUSD, `trade_mode=full`, `volume_min=0.01`,
    `trade_stops_level=0`, `trade_freeze_level=0`.
  - Zero open positions, zero pending orders (`get_trading_open_positions`
    returned empty immediately prior).
  - Algo Trading enabled intentionally for this test.
  - Git commit `76f8564ec81d0cb6a92ae70c668d31970e983f0d`, EX5 SHA-256
    `cfc38c818e2d54761d37e22ee6ab197b7723b24f2d4d6d319343632d61e5ec5d`
    recorded before submission.
- **Volume cap:** 0.01 lots (== authorized max == symbol `volume_min`).
  Max one position. Market order. No pyramiding.

## Order lifecycle

| Step | Action | Result |
|---|---|---|
| 1 | Submit BUY 0.01 XAUUSD, SL 4045.09, TP 4055.09, comment `QB_TPV2_fixture` | `retcode 10009` ("Done at 0.00"), order `34851713` |
| 2 | Verify open position | position_id `34851713`, price_open 4047.98, stop_loss 4045.09, take_profit 4055.09, comment exact match, volume 0.01 |
| 3 | Modify SL to breakeven-plus (4047.98) while price had moved to bid 4050.11 | `retcode 10016` "Invalid stops" -- rejected; recorded as real, observed broker rejection behavior, not a defect (requested SL value was stale relative to the then-current quote) |
| 4 | Retry: modify SL to 4048.00 | `retcode 10009` "Done" -- confirmed via position refresh: stop_loss now 4048.00, take_profit unchanged 4055.09 |
| 5 | Close position | `retcode 10009` "Done at 4050.31", deal `31862025`, order `34851866` |
| 6 | Verify flat | `get_trading_open_positions` empty; `get_trading_history_positions` shows closed record: open 4047.98 -> close 4050.31, commission -0.02, profit +2.33 |

## Infrastructure proven (real broker path, this fixture)

- Order submission and broker acknowledgement (retcode handling, success case).
- A real rejection retcode observed and handled (10016, "Invalid stops") --
  proves the EA-facing tool surface and this evidence process correctly
  distinguish rejected from accepted requests rather than assuming success.
- Actual fill price vs. requested price (4047.98 vs. market at request time) --
  real slippage/execution behavior, not simulated.
- Initial SL/TP placement and verification against the live position record.
- SL modification (breakeven-style) verified by position-state diff.
- Position close/flatten, verified both via open-position emptiness and
  history-record reconciliation (open/close price, commission, profit all
  internally consistent).
- Ownership comment (`QB_TPV2_fixture`) preserved end-to-end through
  modify and close.

## Explicitly NOT proven by this fixture

- Partial close -- not exercisable at the 0.01-lot cap, since 0.01 is both
  `volume_min` and `volume_step` for XAUUSD on this account.
- EA-side `OnTradeTransaction` recognition, EA-side protection
  verification/repair, and restart+reconstruction against a real running
  EA instance -- this order was submitted directly via the broker-facing
  MCP tool, not by a live-attached EA reacting to its own signal. No safe,
  precedented mechanism was found this session for programmatically
  attaching a live EA instance to an MT5 chart (only generic indicator
  `.tpl` templates exist under `Profiles/Templates/`; the one historical
  live EA activation in this project was performed manually by the human
  operator via the terminal GUI). This remains an open item requiring
  either operator action or further explicit guidance.
- Organic strategy-originated submission -- this was a diagnostic fixture
  signal, not a real BO/FBO/MR/TP-V2 candidate that passed arbitration and
  risk sizing.

## Pre-existing account history observed (not part of this fixture)

While reconciling via `get_trading_history_positions`, closed trade
records from 2026-07-14 through 2026-07-20 were observed on this same
demo account, predating this sprint: several tagged `QB fixture owned`,
`QB_FBO_fixture`, and one `FIXTURE_UNKNOWN`, plus two trades with blank
comments and `open_reason: "Client"` (manual-looking, not EA-originated).
All are historical and already closed; none were open at any pre-flight
check performed this session. Documented here for transparency and
evidence-separation purposes -- not investigated further, as it falls
outside this sprint's fixture and no currently-open unowned position was
ever encountered.

## Result

Real Coinexx-Demo broker-path proof obtained for order submission,
acknowledgement (success and rejection retcodes), fill, initial
protection, SL modification, and clean close -- all within the
authorized 0.01-lot / one-position / market-order-only bounds. Account
left flat (zero open positions, zero pending orders) at the end of this
fixture.

**This is CONTROLLED_EXECUTION_FIXTURE evidence only. It proves broker
infrastructure, not strategy edge, organic reachability, or
profitability.**
