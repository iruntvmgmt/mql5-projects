# Fault-adapter scenario investigation — 2026-07-20

## Purpose

HANDOFF "Next task" item 1: run controlled demo/fault-adapter scenarios for
actual modify/close/delete rejection, requotes, disconnect/reconnect, and
fill-during-cancel callback ordering. This session ran QuantBeastEA live in
`QB_MODE_CONSERVATIVE_LIVE` on Coinexx-Demo and attempted each sub-scenario
directly. No source or parameter changes were made. Source SHA-256
`7ac32f8db9c8b16d2fe797ad890f6403ae7877ca38a7fdef24b0c5c5ab797ec9`, EX5
SHA-256 `cb91e10507047433646c6927a17c7bf242ab7e6f2d50910f89c77333f359d2c9`
(both unchanged from the prior session).

## Finding 1: this broker is structurally too permissive to produce most of these faults organically

- **Requotes**: `get_trading_open_positions` and repeated market order fills
  throughout this project's sessions have all returned retcode 10009
  (`TRADE_RETCODE_DONE`) immediately, consistent with market execution
  rather than dealing-desk/instant execution. Requotes
  (`TRADE_RETCODE_REQUOTE`) are structurally a dealing-desk artifact; they
  are very unlikely to be producible on this symbol/broker combination
  through legitimate trading activity.
- **Stop-level/freeze-level violations**: the symbol diagnostics logged at
  every QuantBeastEA startup this project (both tester and live) show
  `Stop Level (pts) = 0` and `Freeze Level (pts) = 0` for XAUUSD on this
  account. With zero minimum distance enforced, there is no legitimate way
  to trigger a stop-distance rejection either.
- **Modify/close/delete rejection via direct probing**: attempting to
  double-close an already-closed position through the MCP trading tool
  (`trade_close_single_position`) was rejected client-side
  ("position by position_ticket not found") before any request reached the
  broker. This confirms the available tooling pre-validates locally; it
  does not demonstrate how QuantBeastEA's own `BrokerAdapter` would handle
  a genuine broker-level rejection retcode, because no such retcode was
  ever produced.

**Conclusion**: on this broker, in this account's current configuration,
deterministic unit-test coverage (`broker_fault_matrix_20260715`, which
exercises injected retcodes for exactly these cases) remains the only valid
evidence for modify/close/delete rejection, requotes, and stop/freeze-level
handling. Real-broker evidence for these specific sub-scenarios should be
considered blocked pending either a broker/account with stricter execution
rules, or a dedicated fault-injection proxy — not something achievable by
further probing this account.

## Finding 2: real live-mode close reconciliation confirmed working (positive result, not a fault)

Placed a fixture position live (magic=20260701, comment=`QB_FBO_fixture`,
ticket 34682739) while QuantBeastEA was attached; it was picked up via
`OnTradeTransaction`'s live entry-handling path (not `ReconstructFromBroker()`,
which only runs at `OnInit()`). Manually closed the position via MCP
(retcode 10009). QuantBeastEA's deferred close-reconciliation
(`TransactionState.mqh` / `ProcessPendingCloseReconciliation()`, called from
both `OnTick()` and `OnTimer()`) correctly detected the position no longer
existed, found its local context, and finalized/journaled the trade with no
warnings (no "Closed owned position was not present in local context"
message, which would indicate a failure). This is useful positive evidence
that the deferred-close path works end-to-end in live mode; it does not
exercise the failure branch since the close was accepted cleanly rather
than rejected.

## Finding 3 (new defect): live entry-handling comment parsing does not match restart-reconstruction parsing

While observing Finding 2's fixture registration, the Expert log showed:
```
Position registered: ticket=34682739 strategy=FBO_fixture entry=4025.99
```
Strategy resolved to `"FBO_fixture"`, not `"FBO"`. Tracing the two
comment-parsing implementations:

- `PositionManager.mqh:65-72` (`StrategyFromComment()`, used by
  `ReconstructFromBroker()` at `OnInit()`): strips the `QB_` prefix, then
  truncates at the first remaining `_`. For `QB_FBO_fixture` this correctly
  yields `FBO`.
- `QuantBeastEA.mq5:1741-1742` (used by `OnTradeTransaction()`'s live
  entry-handling branch, i.e. every genuine live fill this EA processes
  outside of `activeOrderMatch`): only strips the `QB_` prefix via
  `StringSubstr`, with **no truncation** at a further `_`. For the same
  comment this yields `FBO_fixture` — a string that will never match any of
  the four known `STRATEGY_ID_*` constants.

**Consequence**: any owned position whose broker comment contains more than
one `_`-delimited segment after the `QB_` prefix (this fixture's convention,
and plausibly any real-world comment truncation/annotation) will register
with an unrecognized `strategy_id` when picked up live via
`OnTradeTransaction`, even though the exact same comment would resolve
correctly if the same position were instead recovered via
`ReconstructFromBroker()` at restart. This affects strategy-attribution in
`PositionContext`/journaling/strategy-count tracking for the live-fill path,
not order safety or protection (magic-based ownership and protection
verification are unaffected). Classified **Medium** (data-integrity/
attribution defect, not a safety defect). Not fixed in this session per
change discipline (evidence-gathering only); flagged for a dedicated fix
task using `StrategyFromComment()` consistently in both places.

## Finding 4: disconnect/reconnect — architectural gap in when connectivity is actually checked

Operator toggled network connectivity off/on. Terminal log confirms a real
event:
```
23:59:39.484  Network: '871221': connection to Coinexx-Demo lost
23:59:40.126  Network: '871221': authorized on Coinexx-Demo (reconnected ~0.64s later)
23:59:40.915  Network: '871221': terminal synchronized with Coinexx Limited: 0 positions, 0 orders
```
QuantBeastEA produced no log output whatsoever in response (Expert log
byte-for-byte unchanged across the event). Tracing the code: the
connectivity flag (`!TerminalInfoInteger(TERMINAL_CONNECTED)`) is only read
inside `OnTick()`, passed into `g_KillSwitch.CheckConditions()`
(`QuantBeastEA.mq5:1094`). `OnTimer()` (wall-clock, fires every second
regardless of ticks) does **not** re-check connectivity — it only calls
`ProcessPendingCloseReconciliation()` and `ProcessKillSwitchActions()`.
Since `OnTick()` cannot fire while genuinely disconnected (no ticks arrive),
and this blip was shorter than the round-trip needed for a tick to land
exactly while `TERMINAL_CONNECTED` still reads false, the connectivity kill
path was never actually exercised by this test — which is itself the
finding: **connectivity monitoring is opportunistic (tick-gated), not
guaranteed on a wall-clock cadence.** A longer or differently-timed outage
might still not be caught for the same structural reason. This does not
mean the account is unprotected during outages: the separate stale-quote
kill parameter (`g_CurrentSnap.is_fresh`) provides a related but distinct
protection once a tick does arrive after a stale gap. No positions were
open during this test, so no protection-loss scenario was actually at risk;
this finding is about detection latency/certainty, not a demonstrated loss
of protection.

## Safety notes

- All activity ran on Coinexx-Demo (account 871221) in
  `QB_MODE_CONSERVATIVE_LIVE`, FBO-only/market-only gates active throughout.
- No BO/TP/MR or pending-order live transmission occurred.
- Final broker state: 0 positions, 0 orders, confirmed after EA detach.
- Readiness remains exactly `READY FOR SHADOW MODE`. This item remains open
  for the two currently-blocked sub-scenarios (requotes, genuine broker-level
  modify/close/delete rejection) and would benefit from a longer/differently
  timed disconnect test if pursued further, but the core architectural gap
  (Finding 4) is already established regardless of retry.
