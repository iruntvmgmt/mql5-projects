# Phase 3 — risk / execution hardening — 2026-07-20/21

## Purpose

Third phase of the full EA build-out: finish the *Partial* risk/execution
items in `ARCHITECTURE.md` — ChallengeMode enforcement gaps, the Shadow
pending-order lifecycle (the last "not implemented" code path), and the
session/rollover exits.

## What was built

- **ChallengeMode enforcement** (`Risk/ChallengeMode.mqh`):
  - **Attempt lockout** added to `IsTradeAllowed`: once
    `attempts_this_stage >= max_attempts` for the current stage, entries are
    blocked (the counter resets to 0 only when a stage advances). Previously
    `attempts_this_stage` was incremented on stage failure but never consulted.
  - **Pyramiding gate**: `IsPyramidingAllowed(winning, protected)` and
    `AllowsPyramiding()` now wire the previously-dead `m_allowPyramiding`
    member — pyramiding is permitted only when challenge mode is active, the
    flag is on, and the candidate add is to a winning + protected position.
- **Shadow pending-order lifecycle** (`QuantBeastEA.mq5` ~line 1451): the
  `"Shadow pending-order lifecycle is not implemented"` rejection was replaced
  with real virtual placement via `g_Shadow.OpenPending(...)`. The order is
  classified stop vs limit by entry-vs-current-price, gated by the same
  `InpUseStopOrders`/`InpUseLimitOrders` permissions as the live path, with
  expiry from `InpOrderExpirySeconds`. `ShadowPortfolio.Update()` already
  activates/fills/expires/cancels these orders, so `InpUseStopOrders` now
  functions end-to-end in Shadow mode.
- **Session/rollover exits**: confirmed already complete —
  `ProcessSessionExitPolicy()` (wired in `OnTick`, using
  `InpCloseBeforeSessionEnd`/`InpCloseBeforeRollover`) plus its deterministic
  TEST 43. No change required; the `ARCHITECTURE.md` "incomplete" note was
  stale.

## Verification

- Compile: **0 errors, 0 warnings**.
- Self-tests: **59 passed, 0 failed** (was 58). New `TEST 56 PASS: Challenge
  pyramiding gate offBlocks=ok onWinProt=ok onLosing=ok onUnprot=ok
  inactive=ok`. `TEST 49` (shadow pending lifecycle place/fill/cancel) still
  passes; `TEST 43` (session exit policy) still passes.
- **Baseline preservation** (journaled Apr 20-24, default config = market
  orders, challenge off, extended exits off): ACCEPTED **BO 2, FBO 9, TP 0,
  MR 5** — unchanged.
- **Shadow pending validation** (journaled Apr 20-24 with
  `InpUseMarketOrders=false`, `InpUseStopOrders=true`,
  `InpUseLimitOrders=true`): **6 `SHADOW PENDING:` placements** logged (e.g.
  `BO ORDER_TYPE_SELL_LIMIT lots=0.12 price=4791.71`,
  `FBO ORDER_TYPE_BUY_LIMIT`, `MR ORDER_TYPE_SELL_LIMIT`), confirming the new
  wiring places virtual pending orders where the old build hard-rejected with
  "not implemented". Run completed normally (final balance 10000.00).

## Source state

- `QuantBeastEA.ex5` SHA-256:
  `b9a6816c40d47464dfed7bcf0db592dacaf53212bddd48fa2a6baf6377087260`

No broker orders (Shadow mode). Readiness remains `READY FOR SHADOW MODE`.
