# Run manifest -- FBO+MR restricted Conservative-Demo activation

- **Evidence class**: activation event. Any future organic FBO/MR fills
  from this attached instance are `ORGANIC_DEMO_EVIDENCE`, distinct from
  this session's earlier `CONTROLLED_EXECUTION_FIXTURE` (`run_ce01`).
- **Template**: `Profiles/Templates/QB_CONSERVATIVE_LIVE_FBO_MR.tpl`
  (built from `QB_CONSERVATIVE_LIVE_SET.tpl`; roster restricted to FBO+MR,
  `InpMaxLotSize`/`InpMaxTotalExposureLots` tightened to 0.01 to actually
  enforce the 0.01-lot cap under risk-percent sizing).
- **Account**: Coinexx-Demo, login 871221, verified DEMO immediately
  before and after activation.
- **Commit / EX5 at activation**: `04ef9bf` /
  `640d1eebe3358a46840aeefbd18c59ff39577435b3c396533dc1da581d0eadcb`
  (unchanged since the Phase 7-14 batch; no source edits between build
  and this activation).
- **Attachment method**: manual, by the operator, via MT5 GUI Load
  Template -- the agent's own `chart_apply_template` attempt was denied
  by the Claude Code auto-mode classifier and not routed around (see
  Decision D011).

## Init attempts

| # | Time | Result | Reason |
|---|---|---|---|
| 1 | 13:32:23 | INIT_FAILED | TP (V1) enabled -- permanently excluded, fail-closed as designed |
| 2 | 13:34:07 | INIT_FAILED | TPV2 enabled but not demo-authorized -- fail-closed as designed |
| 3 | 13:35:34 | INIT_FAILED | Same as #2 (template not yet corrected client-side) |
| 4 | 13:39:28 | Initialized OK, but bugged | Correct roster; real `g_KillSwitch.emergency` restored true from a stale GlobalVariable -- `ProcessKillSwitchActions()` fired CancelAll/CloseAll every second, 0/0 effect (see Decision D011) |
| 5 | 14:05:41 | **Initialized OK, clean** | Operator cleared `QB_Emergency_871221_XAUUSD` via MT5 Global Variables dialog; no EMERGENCY line, no repeating CancelAll/CloseAll |

## Confirmed state at successful activation (14:05:41)

- Mode=QB_MODE_CONSERVATIVE_LIVE, EffectiveMode unchanged.
- Strategies: BO=off FBO=on TP=off MR=on TPV2=off.
- DemoAuthorized: BO=no FBO=yes MR=yes TPV2=no (TP V1 permanently excluded).
- BrokerTier=QB_BROKER_TIER_CONSERVATIVE_DEMO (account correctly
  classified as demo).
- MaxLot=0.01, MaxPositions=1, MaxPendingOrders=0, UseMarketOrders=yes,
  UseStopOrders=no, UseLimitOrders=no.
- Startup reconciliation: 0 positions reconstructed [clean].
- Self-tests: 105 passed, 0 failed.
- `get_trading_open_positions` (post-activation check): 0 positions, 0
  orders.

## Known issue found during this activation (not fixed in code this session)

See `DECISION_LOG.md` D011 in full. Summary: a stale, pre-existing
`QB_Emergency_871221_XAUUSD` GlobalVariable (unrelated to this sprint's
own changes) caused the EA's kill-switch to load latched-emergency at
startup, which both silently blocked all entries and caused a harmless
but incorrect once-per-second CancelAll/CloseAll retry loop. Fixed for
this instance by clearing the stale data via the MT5 GUI. Left as a
documented, not-yet-hardened known issue per explicit user instruction
("note that bug incase it returns we should fix it") -- candidate future
fix: loud startup logging of restored kill-switch state, and/or a
distinct operator re-acknowledgment gate for a *restored* (vs.
freshly-triggered) emergency/flatten/cancel latch before it's allowed to
execute broker actions.

## Result

**Genuinely activated.** FBO and MR are now live on the Coinexx-Demo
account, correctly bounded (0.01 lots, 1 position max, market orders
only), with BO/TP V1/TP V2 excluded from this instance (BO and TP V2
continue to be evidenced via Shadow-mode tester runs, not a parallel
live-attached chart -- running two simultaneous instances on the same
account+symbol was deliberately avoided, since `SetStateScopeSymbol`
scopes all persisted state by account+symbol only, not by mode, and
would cause the two instances' kill-switch/trade-counter/arbitration
state to collide).

**Broker orders transmitted by this activation event itself: none** (0
positions/orders before, during, and after). Any future fill is real
organic demo evidence, not a controlled fixture.
