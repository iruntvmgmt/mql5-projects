# Known Issues and Production Blockers

## Build verification

The previously validated MSZZ files compiled with 0 errors on MetaEditor builds 6033/6061; the EA carried one reviewed Market-version warning. The new ownership batch added after commit `31f13b0` is **compile-pending and runtime-pending** until pulled and validated locally.

## Fixed and verified in prior passes

- Illegal local reference in `OpportunityClusterEngine.mqh`.
- Unsafe `ZeroMemory()` use on string-containing structs and the follow-on uninitialized-field defect.
- Malformed cluster IDs, replaced by D004 `MSZZC1` length-prefixed encoding.

## Fixed and verified 2026-07-25 (second pass)

### Account-mode and position ownership — D005 — RESOLVED

Added:

- `Execution/PositionOwnership.mqh`
- `Execution/PositionOwnershipPolicy.mqh`
- `Test_MSZZ_Ownership.mq5`
- EA version `0.310` ownership integration

The implementation detects netting, hedging, exchange, and unsupported account modes; inventories symbol positions by ticket; classifies owned/manual/foreign positions by magic number; closes only owned opposite tickets; fails closed on selection ambiguity; blocks foreign/manual symbol exposure in netting or exchange mode; and applies the one-position limit only to owned MSZZ positions in hedging mode.

This supersedes the old "netting-account assumption" blocker previously listed here. All resolution criteria are met:

- the unsafe symbol-wide `PositionSelect(_Symbol)`/`CTrade::PositionClose(_Symbol)` path is gone (confirmed by repo-wide grep, zero matches);
- account mode is detected and logged (`AccountInfoInteger(ACCOUNT_MARGIN_MODE)`, verified to correctly resolve to `HEDGING` on the isolated demo account, matching the terminal's own connection log);
- ownership inventory works (read-only diagnostic: valid snapshot, zero false positives on empty position state);
- hedging policy passes (deterministic test: coexistence allowed when unowned, blocked at the owned-position limit, foreign/manual never counted as owned);
- netting/exchange policies pass deterministic tests (foreign/manual exposure blocks execution in both modes; no real netting/exchange broker account was available, so this is unit-test coverage only, documented as such — not real broker runtime coverage);
- EA compile (0 errors, 1 pre-existing reviewed warning) and shadow regression (zero orders/deals/trades, short and long windows) both pass.

**Narrower remaining issues** (replacing the old blocker):

- **Close-by-ticket execution against a real open position has not been demo-tested.** No positions were created during this pass (per instruction — shadow-only, zero orders). The `CTrade::PositionClose(ticket)` call path compiles and is exercised by zero live tickets; it has not been proven against an actual broker position.
- **`owned_longs`/`owned_shorts`/volume-total counting and same-symbol-vs-different-symbol exclusion** are implemented in `CMSZZPositionOwnership::Refresh()` (every field of `MSZZPositionRecord` is set explicitly — confirmed by source review, no uninitialized-field risk) but have only been exercised against a zero-position inventory; they are unverified against actual mixed-symbol or multi-position live state.
- **Order/deal history reconciliation is absent.** The ownership subsystem inventories only currently-open positions at startup; it does not reconstruct historical orders or deals.
- **Post-order persistence failure remains** (see below, unchanged by this batch).
- **Full position-management restart reconstruction remains absent** (see below, unchanged by this batch).

## Identified, not fixed

- **Event persistence failure after successful order submission:** an accepted order followed by `ConsumeEvent()` failure still has no intent-before-submit journal, recovery halt, or history reconciliation.
- **Full ownership reconstruction:** the current batch reconstructs live owned positions at startup, but does not yet map positions/orders/deals back to full cluster lifecycle records after restart.
- **Freeze-level conservatism:** initial stop validation uses `max(stops_level, freeze_level)`, which may reject valid initial protection distances.
- **Risk controls absent:** fixed lots only; no account-risk sizing, margin preflight, daily limits, exposure cap, or emergency kill switch.
- **Reserved strategies absent:** sequential confirmation, retest, sweep/reclaim, compression, and structure transition remain specifications.
- **Pine parity absent:** no completed Pine-side bar-for-bar comparison.
- **Trendline geometry unresolved:** elapsed-time versus bar-index projection remains open.
- **Cluster lifecycle persistence incomplete:** only consumed cluster IDs are persisted.
- **Full-history rebuild performance:** not measured or optimized.
- **Partial opposite-ticket closure is possible but undistinguished:** if multiple owned opposite tickets exist and one `CTrade::PositionClose(ticket)` call fails after an earlier one in the same loop succeeded, `CMSZZPositionOwnership::CloseOwnedOpposite` returns `false` with a reason describing only the failing ticket. This is fail-safe (no foreign/manual position is ever at risk, and the EA correctly aborts the new-entry attempt), but the failure reason does not distinguish "nothing was closed" from "some owned tickets closed, then one failed." Not exercised this pass (zero owned positions existed).

## Reviewed and accepted

The EA version remains below 1.0 and may trigger the known MQL5 Market publishing warning. This branch is not a Market product; reports must still disclose the warning rather than call the build warning-free.

## Production status

- Safe for continued shadow research — the ownership batch compiled clean and passed all regression tests (2026-07-25 second pass).
- Demo execution remains blocked by: no real-position close-by-ticket demo test, post-order persistence recovery, full order/deal reconstruction, risk sizing, margin preflight, and account safeguards.
- No edge or live-readiness claim is supported.