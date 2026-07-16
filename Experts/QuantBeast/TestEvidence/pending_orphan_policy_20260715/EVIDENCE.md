# Pending-Orphan Fail-Closed Policy — 2026-07-15

## Defects

Two High-severity pending-order transitions retired local tracking without proving broker resolution:

1. Expiry called `DeleteOrder()` and cleared `g_OrderPending` regardless of deletion success.
2. When a pending ticket was absent from the current order pool, the EA cleared tracking even if history was unavailable or a fill could not be safely reconciled.

Either path could leave an untracked broker order capable of filling later, or lose the ownership context needed to protect a filled position.

## Repair

- Added `QBPendingHistoryResolved()` so tracking retires only for confirmed canceled/expired/rejected history, or for a filled/partial order whose position was reconciled, protected, and registered.
- Added `QBPendingTrackingAfterDelete()` so failed expiry deletion preserves tracking.
- Unresolved history and failed expiry deletion now latch cancel-all, persist state, and return without clearing the active-order context.
- Extended deterministic Test 27 with missing-history, unsafe-fill, terminal-history, delete-success, and delete-failure transitions.

## Verification

- Compile: `0 errors, 0 warnings, 13175 ms`, X64 Regular.
- Runtime Test 27: `pending_state=fail-closed`.
- Full suite: `32 passed, 0 failed`.
- One-day Shadow run: `5520 ticks`, `276 bars`, `9.942 s`.
- Final balance unchanged: `10000.00 USD`.

## Boundary

The state policies and compiled controller wiring are proven without transmitting broker orders. Actual delete rejection, delayed history propagation, disconnect, and fill-during-cancel races still require a controlled fault adapter or demo broker scenario.

Readiness remains `READY FOR SHADOW MODE`; live and Challenge operation remain prohibited.
