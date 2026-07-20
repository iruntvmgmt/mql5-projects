# Protection verification on restart-reconstructed positions — 2026-07-20

## Defect

Found while auditing the "long tail" of unclosed evidence items:
`ReconstructFromBroker()` (`PositionManager.mqh:417-499`) read `POSITION_SL`
directly into `ctx.current_stop` with no check that it was actually a valid
(>0) protective stop before accepting the position into tracking. Unlike a
live fill -- which always goes through `EnsurePositionProtection()`
(`BrokerAdapter.mqh:333-386`) via `OnTradeTransaction()` -- a position
recovered at restart with no stop loss at all (e.g. manually removed while
the EA was down, or opened without one) was silently treated as protected.
This is a real safety gap, not just missing test coverage: `LIVE_DEPLOYMENT_
CHECKLIST.md` section H explicitly requires "All reconstructed positions are
checked for protection," and it was not being done.

Severity: High (a genuinely unprotected position could sit untracked-as-a-
problem after a restart, with no repair or emergency response, until some
other check happened to notice).

## Fix

Added a protection-verification call for every position that reaches
tracking in `ReconstructFromBroker()`:
```
m_broker.EnsurePositionProtection(ticket, ctx.current_stop, ctx.initial_target)
```
Passing the position's own currently-observed stop/target as both "actual"
and "expected" means this call never attempts a repair modification here
(they trivially match if non-zero) -- it purely enforces
`EnsurePositionProtection()`'s existing "no valid protective stop" fail
path when `ctx.current_stop <= 0`. This reuses the exact same protection
contract the live-fill path already relies on, rather than inventing new
logic.

`ReconstructFromBroker()`'s signature gained a fourth out-parameter,
`unprotectedCount`, following the same pattern as the existing
`unknownCount`. The sole caller (`QuantBeastEA.mq5` `OnInit()`) now escalates
via the existing `ActivateProtectionEmergency()` (not a narrower
`KillEntries()`, since this genuinely is "could not verify a safe state,"
matching the live-fill precedent) when any reconstructed position fails
verification.

No new persisted schema; no state-version bump. Only one call site existed
(`QuantBeastEA.mq5` `OnInit()`); no other callers needed updating.

## Verification

- Compile: `0 errors, 0 warnings`, MetaEditor build 6033, 2026.07.20 01:43:09.
- Source SHA-256: `23e16ebb560c022cd42ea56cf97ed3fbf1a58825cf81ac068aab22957f7a12be`
- EX5 SHA-256: `f4107718ee637356cf4c2131daedd6da80e27bf317e9c41f49df264dffa29642`
- `PositionManager.mqh` SHA-256: `db7ae511f7b3e0a68416c0408a481323da6c01fd6501aa098c0d4633ac3cc2e0`
- Shadow regression (Model=4, self-tests enabled): `54 passed, 0 failed`, unchanged from prior session -- confirms no regression. No new deterministic unit test was added: this integration is fundamentally broker-state-dependent (like `ReconstructFromBroker()` itself always has been), and the underlying `EnsurePositionProtection()` decision logic is already deterministically covered elsewhere (`TestEvidence/broker_fault_matrix_20260715/`). Verification is compile + regression + real evidence, the same standard `ReconstructFromBroker()` itself has always been held to.

## Live restart evidence (real Conservative Live terminal restart)

Extended `MQL5/Scripts/QuantBeastRestartFixture.mq5` with a new command,
`CMD_PLACE_OWNED_NO_SL` (value 8), placing a magic-owned, correctly-commented
position with `sl=0` (no protective stop). Placed while QuantBeastEA was
detached (ticket 34687773, magic=20260701, comment=`QB_FBO_fixture`,
entry=4009.32). Re-attaching QuantBeastEA (Conservative Live) produced:
```
Protection verification failed: no valid protective stop
Reconstructed position has no verified protective stop: ticket=34687773 strategy=FBO sl=0.00
Reconstructed position: ticket=34687773 strategy=FBO entry=4009.32 originalSL=0.00
Startup reconciliation: 1 positions reconstructed
QuantBeast KILL: EMERGENCY: Reconstructed position(s) found with no verified protective stop: 1
Position closed: ticket=34687773 price=4009.73
CloseAll: closed 1 positions
```
The gap was caught and the centralized emergency-close path
(`ActivateProtectionEmergency` -> `CloseAllPositions`) correctly closed the
unprotected position. Final broker state confirmed clean: 0 positions,
0 orders.

## Scope and safety notes

- Fixture script change (`QuantBeastRestartFixture.mq5`) is a test asset
  only, outside `QuantBeastEA.mq5`'s own source; SHA-256:
  `331e873999c327934ce5e75a78b8f35fcec3d1614af80625eaaddc56768b1dba`.
- No strategy logic, risk parameters, or execution behavior changed beyond
  this one verification call and its escalation path.
- All activity ran on Coinexx-Demo (account 871221); no BO/TP/MR or
  pending-order live transmission occurred.
- Readiness remains exactly `READY FOR SHADOW MODE`.
