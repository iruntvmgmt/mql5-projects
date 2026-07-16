# Broker fault matrix and protection close ownership — 2026-07-15

## Confirmed defect

**Severity: High.** `EnsurePositionProtection()` could attempt an immediate close after repair failure. Every production caller then invoked `ActivateProtectionEmergency()`, which immediately called the centralized close-all path. Before broker state converged, one protection failure could therefore submit two close requests in the same call chain.

Affected paths included market-fill protection, pending-fill reconciliation, and entry-deal transaction reconciliation.

## Repair

- Replaced implicit protection branching with a two-pass `accept -> repair -> emergency` decision policy shared by production and deterministic tests.
- Removed direct close transmission from `EnsurePositionProtection()`.
- The function now reports failure to `ActivateProtectionEmergency()`, the sole immediate close owner. Its persistent flatten latch and tick/timer dispatcher retain bounded retries while exposure remains.
- A filled but unprotected market result remains `ACKNOWLEDGED`, not falsely `CLOSED`, until broker position state proves closure.
- Centralized API-plus-server response classifiers for modify, close, delete, and retryable submission retcodes.
- Added Test 32 with injected missing/looser stop, rejected repair, rejected modify/close/delete, price-only retry, and fill-during-cancel outcomes. It sends no broker orders.

## Evidence

- Compile: `0 errors, 0 warnings, 9378 ms`.
- Shadow fixture: `34 passed, 0 failed`.
- Test 32: `protection=repair/emergency responses=server-confirmed cancel_fill=retained close_owner=central`.
- Tester: `5520 ticks`, `276 bars`, final balance unchanged at `10000.00`.
- No broker orders were transmitted.

## Hashes

- `QuantBeastEA.mq5`: `36ce8244a23d904fd7f7c35b0b6d546cd1facfc8878f9b88511cc9ada0d5946b`
- `QuantBeastEA.ex5`: `189dd97e138117005c3e7a9e3cc40e51f7ea3fac932b38412eacd773fdbd109d`
- `BrokerAdapter.mqh`: `18dda2119c97750d13839411c1ce64809c9b32fc7689748c036204fe0469807c`
- `SafetyTests.mqh`: `9c5557610a4978c41492eabd6d2f53dcc29e1882e8dfcd0d0820260c42932d95`

## Boundary

This is deterministic policy and production-wiring evidence. It does not induce an actual broker modify rejection, close rejection, cancellation race, requote, disconnect, or callback-order sequence. Live and Challenge operation remain prohibited.

