# Pending-order restart reconstruction — 2026-07-20

## Purpose

HANDOFF item #4, Phase A (see approved plan reasoning in this session):
implement genuine restart reconstruction for owned pending orders,
replacing the previous unconditional fail-closed cancellation. This is one
of the four evidence gaps (activation, expiry, cancellation, fill-race,
restart) cited by `QBLiveExecutionSetAllowed()`
(`QuantBeastEA.mq5:492-512`), which keeps live modes market-order-only.
Live activation/cancellation/fill-race evidence for ordinary (non-restart)
pending-order trading and any decision to relax that gate remain explicitly
out of scope for this change.

## Design

Mirrors `PositionManager.mqh`'s `ReconstructFromBroker()`: recovers
everything directly from live broker order state at `OnInit()`, with no
new persisted Global Variable schema and no state-version bump. Every
`ExecutionRecord` field needed except `request_id` (a purely local,
never-transmitted value) is read straight from the broker order
(`ORDER_TYPE`, `ORDER_PRICE_OPEN/SL/TP`, `ORDER_COMMENT` via
`QBStrategyIdFromComment()`, `ORDER_TIME_SETUP`). The reconstructed record
uses the order ticket as a stable `request_id` substitute -- the same
accepted gap already documented for `PositionContext.signal_id` on the
position-recovery side.

Because `g_ActiveOrder`/`g_OrderPending` are scalars (only one pending
order is ever tracked in memory; confirmed `InpMaxPendingOrders` only gates
the broker-side count, never indexes multiple local records),
reconstruction fails closed on anything that doesn't fit that model:
0 found -> no-op; exactly 1 with a resolvable comment -> reconstruct;
exactly 1 with an unresolvable comment -> cancel (today's prior behavior,
preserved for this case only); more than 1 -> cancel all and
`KillEntries()` (not the broader `ActivateProtectionEmergency`, which would
also force-close unrelated positions -- this case has nothing left to
protect once cleanly cancelled, matching the existing unknown-position
quarantine precedent).

`request_time` on the reconstructed record uses the broker's true
`ORDER_TIME_SETUP`, not "now" -- using "now" would let repeated restarts
silently extend a pending order's effective `InpOrderExpirySeconds` budget
indefinitely.

## Implementation

- `Include/QuantBeast/Execution/BrokerAdapter.mqh`: added
  `CBrokerAdapter::FindSingleOwnedPendingOrder(ulong &foundTicket)` (same
  magic-range scan pattern as `CountPendingOrders`/`CancelAllPending`) and
  the pure free function `QBBuildPendingExecutionRecord(...)`.
- `Experts/QuantBeast/QuantBeastEA.mq5`: added
  `ReconstructPendingOrder(ulong ticket, ExecutionRecord &rec, string &reason)`;
  replaced the unconditional `CancelAllPending()` startup block with the
  0/1-known/1-unknown/>1 branch described above.
- `Include/QuantBeast/Testing/SafetyTests.mqh`: added
  `QBTestPendingExecutionRecordBuild()` (TEST 51), covering field mapping,
  `request_id`/ticket substitution, `request_time` = setup time (not now),
  and round-trip resolution through `QBStrategyIdFromComment()`.

## Verification

- Compile: `0 errors, 0 warnings`, MetaEditor build 6033, 2026.07.20 00:47:39.
- Source SHA-256: `4e4ee57811e2204a24181ed9511ed128848ed255cddb3951737284b39a393771`
- EX5 SHA-256: `64628d99e134851fa964129e93af5843a5ae60e3e1c66379e4f652d7ae666d27`
- `BrokerAdapter.mqh` SHA-256: `774a4aef2f41fd6ba73a276e4ae2c5f68bf452f3775b25eca475fd2361ac8071`
- `SafetyTests.mqh` SHA-256: `b8fad8e26906cfd8becba6d2c1a657babbae1a34281852ae2a51bc790e6ac1dc`
- Shadow regression (Model=4, self-tests enabled): `Self-tests complete: 54 passed, 0 failed` (was 53; new TEST 51 passes), including `TEST 51 PASS: Pending order reconstruction mapping ticket=matched type=matched prices=matched time=setup strategy=FBO`. Final balance unchanged 10000.00, `OnTester result 0`, normal tester footer.

## Live restart evidence (real Conservative Live terminal restart)

Fixture: `QuantBeastRestartFixture` `CMD_PLACE_PENDING` placed a BUY LIMIT
0.01 XAUUSD @3961.55, magic=20260801 (in QB range), comment=
`QB_FBO_fixture_pending` (ticket 34687162), while QuantBeastEA was
detached. Re-attaching QuantBeastEA (Conservative Live, FBO-only/
market-only preset) produced:
```
Reconstructed pending order: ticket=34687162 strategy=FBO type=ORDER_TYPE_BUY_LIMIT price=3961.55
Startup reconciliation: 0 positions reconstructed
```
-- confirming the new code correctly recovered strategy, type, and price
from live broker state instead of the previous unconditional cancellation.

**Bonus finding**: real wall-clock time elapsed between the fixture placing
the order and the EA being re-attached (ordinary session back-and-forth),
exceeding `InpOrderExpirySeconds`. Because `request_time` was correctly set
from the order's true `ORDER_TIME_SETUP` rather than the moment of
reconstruction, the very next tick's existing expiry-check logic in
`CheckOrderStatus()` correctly detected the order as overdue and deleted it
cleanly:
```
Pending order expiry deletion confirmed: ticket=34687162
```
This is a real, organic demonstration of two things at once: reconstruction
feeding correctly into the pre-existing expiry-management path, and the
safety property the design was built for (a restart cannot be used to
silently extend a stale pending order's lifetime). Final broker state after
this sequence: 0 positions, 0 orders (confirmed).

## Scope and safety notes

- No new persisted Global Variable schema; `QB_STATE_VERSION_NUM` unchanged
  at 4.
- `QBLiveExecutionSetAllowed()` was **not** modified -- live modes remain
  market-order-only. This change only fixes what happens if a pending
  order is somehow found at startup (today that can only occur via a
  manually-placed fixture or externally-created order, since the live gate
  itself prevents QuantBeast from ever placing one); it does not enable new
  live trading behavior.
- All activity ran on Coinexx-Demo (account 871221); no BO/TP/MR or
  pending-order live transmission occurred by the EA itself.
- Readiness remains exactly `READY FOR SHADOW MODE`.
