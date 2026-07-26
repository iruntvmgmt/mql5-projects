# Known Issues and Production Blockers

## Build verification

The previously validated MSZZ files compiled with 0 errors on MetaEditor builds 6033/6061; the EA carried one reviewed Market-version warning. The new ownership batch added after commit `31f13b0` is **compile-pending and runtime-pending** until pulled and validated locally.

## Fixed and verified in prior passes

- Illegal local reference in `OpportunityClusterEngine.mqh`.
- Unsafe `ZeroMemory()` use on string-containing structs and the follow-on uninitialized-field defect.
- Malformed cluster IDs, replaced by D004 `MSZZC1` length-prefixed encoding.

## Implemented in current batch, awaiting compile/runtime evidence

### Account-mode and position ownership — D005

Added:

- `Execution/PositionOwnership.mqh`
- `Execution/PositionOwnershipPolicy.mqh`
- `Test_MSZZ_Ownership.mq5`
- EA version `0.310` ownership integration

The implementation detects netting, hedging, exchange, and unsupported account modes; inventories symbol positions by ticket; classifies owned/manual/foreign positions by magic number; closes only owned opposite tickets; fails closed on selection ambiguity; blocks foreign/manual symbol exposure in netting or exchange mode; and applies the one-position limit only to owned MSZZ positions in hedging mode.

This item is not considered resolved until Claude reports:

- clean compilation of the two new headers, ownership test, and EA;
- deterministic ownership test `failures=0`;
- hedging-account shadow regression with zero orders;
- controlled demo fixtures proving manual and foreign positions are never closed;
- netting-mode verification or a documented inability to obtain a netting test account.

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

## Reviewed and accepted

The EA version remains below 1.0 and may trigger the known MQL5 Market publishing warning. This branch is not a Market product; reports must still disclose the warning rather than call the build warning-free.

## Production status

- Safe for continued shadow research only after the current ownership batch compiles and passes regression tests.
- Demo execution remains blocked by post-order persistence recovery, full order/deal reconstruction, risk sizing, margin preflight, and account safeguards.
- No edge or live-readiness claim is supported.