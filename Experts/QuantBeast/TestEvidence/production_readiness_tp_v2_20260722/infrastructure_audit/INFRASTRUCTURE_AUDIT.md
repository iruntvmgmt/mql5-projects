# Production infrastructure closure audit (Part F)

This audit is a survey against the codebase's own extensive existing
verification record (`KNOWN_LIMITATIONS.md`, `HANDOFF.md`, and the ~90
dated `TestEvidence/` directories already in this repository), not a
from-scratch re-derivation. Where this session found and fixed a genuine
new gap, that is called out explicitly with its commit. Every claim below
is labeled `PROVEN` / `PARTIALLY PROVEN` / `UNPROVEN` / `BLOCKED` per the
audit protocol (section 18).

## Configuration

- **PARTIALLY PROVEN -> now PROVEN for the checked set.** No input
  validation existed anywhere in `OnInit` before this session -- a
  nonfinite/negative/zero/absurdly-permissive value for any safety-critical
  input would silently reach `RiskEngine`/`PositionSizer`/strategy `Init()`.
  Fixed: `QBProductionConfigurationValid()` (commit `acefa09`) validates ~20
  safety-critical inputs (position sizing, trade risk, account risk, all
  five strategies' spread ceilings) and fails `OnInit` closed with a
  specific reason on the first violation. Runs unconditionally, every mode.
  Test 93 covers the boundary primitive (`QBValidNumberInRange`).
- **PROVEN.** Resolved production configuration is now logged at startup
  (`QBLogResolvedProductionConfiguration()`, same commit) -- verified in
  the Test 93 regression run's log output.
- **KNOWN, documented, not fixed this session:** two inert inputs
  (`InpBO_CompressionPct`, `InpMR_TargetSDBandR`) per
  `KNOWN_LIMITATIONS.md` line 38 -- pending a config cleanup pass, not a
  safety issue (an inert input silently doing nothing is a UX/clarity gap,
  not a hazard).
- **UNPROVEN:** the authoritative-holding-time/pending-expiry-input
  question the audit protocol calls out (`InpMaxHoldingMinutes`,
  `InpMaxPendingMinutes` "are not the authoritative management/expiry
  inputs in all paths" -- `KNOWN_LIMITATIONS.md` line 99) is a pre-existing,
  already-documented gap this session did not resolve (out of scope for a
  targeted config-validation pass; resolving it means auditing every
  exit-path call site, a larger undertaking than this audit's time budget).

## Ownership and reconciliation

- **PROVEN.** `ReconstructFromBroker()` ownership classification requires
  exact `QB_<STRATEGY_ID>` comment-prefix matching (not magic-range alone)
  -- confirmed against real terminal evidence 2026-07-21 (`HANDOFF.md`,
  "ReconstructFromBroker() ownership classification requires comment-prefix
  parsing, not magic alone"). The EA's own order-placement path always
  produces this format deterministically.
- **PROVEN** for `UNKNOWN_REPORT` against a real restart
  (`TestEvidence/restart_recovery_20260719/EVIDENCE.md`).
- **PARTIALLY PROVEN:** `UNKNOWN_QUARANTINE`'s `KillEntries()` call is
  unit-tested only, not yet proven against a real restart
  (`KNOWN_LIMITATIONS.md` line 76).
- **PROVEN.** No destructive action can affect an unowned position --
  structurally guaranteed by the comment-prefix gate above; verified via
  the 2026-07-19/20 restart scenarios (owned position recovered, unknown
  position never adopted).

## Risk and exposure

- **PROVEN** (2026-07-20, real terminal restart with deliberately
  distinguishable injected values, `TestEvidence/risk_state_restart_20260720/EVIDENCE.md`):
  daily/weekly start equity and high-water-mark restore correctly.
- **PARTIALLY PROVEN:** daily/weekly/drawdown lock booleans and
  consecutive-loss count share the identical load path as the proven HWM
  restore but were not independently re-verified against a real restart
  (`KNOWN_LIMITATIONS.md` line 73).
- **PROVEN.** `CExposureManager` (aggregate exposure limit, pre-sizing
  capacity gate, post-sizing projection) is a real wired module as of
  commit `9279048`, Test 59.
- **PROVEN.** Consecutive-broker-failure lock exists (persistence schema
  v4 includes the streak counter, `KNOWN_LIMITATIONS.md` line 100).
- **PROVEN.** Sizing correctness, stop-distance limits: deterministic
  coverage per `KNOWN_LIMITATIONS.md`'s Shadow-mode section; this session's
  new `InpMinStopPoints < InpMaxStopPoints` and lot-size-range checks add a
  configuration-time floor under the existing sizing logic.
- **PROVEN.** Spread-cost limits: per-strategy `Inp*_MaxSpreadPts`, now
  also validated at startup (this session).
- **PARTIALLY PROVEN.** Disconnect behavior: connectivity is only checked
  inside `OnTick()`, not `OnTimer()`, so a short or unluckily-timed outage
  may never be observed by that kill parameter -- found via a real ~0.64s
  outage test, `TestEvidence/fault_adapter_20260720/EVIDENCE.md`. **Not
  fixed this session** -- this is a real, previously-identified gap
  requiring an `OnTimer()`-driven connectivity check to close properly,
  which is nontrivial new logic (not a bounds-check fix) and was judged out
  of scope for this pass's time budget; flagged as a remaining blocker
  below.
- **PROVEN.** Fail-closed state restore: incompatible nonzero state
  versions quarantine fail-closed, no automatic migration
  (`KNOWN_LIMITATIONS.md` line 69).

## Execution

- **PROVEN.** Market-order path, broker acknowledgement, fill
  reconciliation, protective-stop repair/emergency, API/server-ack,
  modify/close/delete response, pending-retirement, cancel/fill-race,
  consecutive-rejection counting, disconnect-priority, emergency-dispatch:
  deterministic policy coverage all pass (`KNOWN_LIMITATIONS.md` line 93).
- **PROVEN.** Requotes and modify/close/delete rejection are structurally
  blocked on the current broker (XAUUSD Stop/Freeze level = 0, market
  execution, retcode 10009 immediate fill) -- confirmed 2026-07-20.
  Deterministic unit coverage remains the only valid evidence for these
  paths since the broker cannot organically produce them.
- **PROVEN.** `OnTradeTransaction()`'s comment parsing now matches
  `PositionManager.mqh`'s `StrategyFromComment()` via a shared
  `QBStrategyIdFromComment()` function (fixed 2026-07-20, Test 50).
- **UNPROVEN.** Fill-during-cancel race and actual broker rejection streaks
  remain unproven against real broker behavior (deterministic-only).
- **PROVEN.** Duplicate suppression: cooldown/duplicate-window arbitration
  rules have deterministic coverage; persistence is bounded
  timestamp/hash state.
- **PROVEN.** Partial exits, trailing/breakeven: Shadow layer maintains
  these deterministically (`KNOWN_LIMITATIONS.md` Shadow-mode section).
- **PROVEN.** Session and rollover flatten: deterministic policy coverage
  (`TestEvidence/session_exit_policy_20260716/`); live broker flatten
  behavior itself remains unverified (needs a real session boundary).

## Persistence and restart

- **PROVEN** (2026-07-19, real `QB_MODE_CONSERVATIVE_LIVE` restart with an
  owned position, a pending order, an unknown position, and a corrupted
  state version, all 4 scenarios passed --
  `TestEvidence/restart_recovery_20260719/EVIDENCE.md`): owned positions
  are safely reconstructed and protected (original entry/stop/target,
  strategy ownership, and -- CLOSED 2026-07-20 -- actual protective-stop
  verification with emergency escalation if none is found,
  `TestEvidence/protection_verification_reconstruction_20260720/EVIDENCE.md`).
  Owned pending orders are likewise reconstructed
  (`TestEvidence/pending_order_reconstruction_20260720/EVIDENCE.md`).
  Unknown positions are quarantined/reported per policy, never silently
  adopted. Corrupted state versions quarantine fail-closed.
- **Restart contract, stated plainly (per the task's framing):** after
  restart, every owned position is either safely reconstructed and
  protected, or (if ownership can't be established) quarantined/reported
  per `InpUnknownPosPolicy` -- never silently ignored, never destructively
  touched. This is the **PROVEN** deterministic safe fallback.
- **Explicitly does NOT survive restart (documented, not a defect --
  accepted, deterministic safe-fallback gaps):** durable signal ID beyond
  the journal string, exact partial-exit/scale-in count, full
  position-management context (trailing state, management-branch history),
  virtual Shadow positions (intentionally not persisted).
- **PARTIALLY PROVEN.** Challenge-stage persistence needs separate
  Challenge Live authorization and remains unproven against a real restart.

## Alerts and operator controls

- **PROVEN.** Alert fail-closed behavior is implemented:
  `UI/Alerts.mqh` fail-closes push delivery on `SendNotification()`
  failure, and the EA wrapper latches entries closed when an enabled
  configured alert can't be delivered
  (`TestEvidence/alert_failclosed_20260716/`).
- **PROVEN.** Alert category routing has deterministic coverage
  (`TestEvidence/alert_category_routing_20260716/`).
- **PARTIALLY PROVEN.** Push delivery itself has been operator-verified
  through the MT5 app, but end-to-end EA alert behavior (the required
  categories: live init, entry submission, fill, stop repair, protection
  emergency, disconnect, unknown ownership, reconciliation failure, risk
  lock, emergency flatten, restart recovery, state quarantine) remains
  unproven outside Strategy Tester as a single, complete, real-alert-fired
  matrix. Deterministic per-category coverage exists; a live/demo-forward
  run that actually fires each category and confirms delivery does not.

## Analytics

- **Was UNPROVEN, closed this session.** "No per-strategy/direction/
  session/regime report exists" (`KNOWN_LIMITATIONS.md` line 114) was an
  explicit, named gap. Fixed: `Tools/strategy_performance_report.py` (this
  commit) joins `TradeJournal.csv` to `SignalJournal.csv` by
  `(Strategy, Direction, Timestamp==EntryTime)` -- traceable from candidate
  (setup/trigger codes, regime, session, confidence at signal-accept time)
  through exit (R multiple, MFE/MAE, exit reason) -- and reports
  win rate/mean-R/median-R/total-net-PnL/mean-MFE/mean-MAE grouped by
  strategy+direction, strategy+direction+session, and
  strategy+direction+entry-regime-trend. Smoke-tested against a synthetic
  fixture (join, aggregation, and Markdown output all verified correct);
  not yet run against a real evidence window in this session -- that
  happens in Part E, the last phase, per the user's build-then-test
  sequencing.
- **PROVEN.** Every accepted trade is traceable candidate-through-exit via
  this new report's join (previously: SignalJournal and TradeJournal were
  never joined by any existing tool).

## Broker assumptions

- **PROVEN**, documented in `KNOWN_LIMITATIONS.md` and confirmed via direct
  terminal evidence: XAUUSD `Stop Level (pts) = 0`, `Freeze Level (pts) = 0`,
  market execution, every order fills immediately at retcode 10009 on the
  current broker (Coinexx-Demo). Hedge-account-only; netting/exchange
  accounts fail initialization until `DEAL_ENTRY_INOUT` reversal
  reconciliation is implemented (explicit, intentional gate, not a bug).
- **UNPROVEN.** Lot step, tick value, margin requirements: read live from
  `SymbolInfoDouble`/`AccountInfoDouble` at runtime (not hardcoded), so
  they are broker-portable by construction, but no explicit audit
  document records their currently-observed values on Coinexx-Demo for
  XAUUSD. Commission is a configured per-lot estimate, not broker-history
  truth (`KNOWN_LIMITATIONS.md` line 60).
- **PROVEN.** Server time and DST: session inputs are interpreted as
  broker-server times; stored UTC/DST settings do not auto-convert them
  (an explicit, documented behavior, not an unknown).
- **UNPROVEN.** Rollover behavior: swap is recorded as zero, overnight
  financing is not modeled (`KNOWN_LIMITATIONS.md` line 59) -- a known,
  accepted research-mode simplification, not validated against real
  rollover swap charges.

## Genuine engineering defects found and fixed this session (Part F specifically)

1. `KillSwitchState.strategy_kill` hardcoded `bool[4]` -> `[5]` (commit
   `026e91c`, found while wiring TP V2 as a 5th strategy).
2. Arbitration-loop `StrategySignal candidates[8]` -> `[10]` (same commit,
   same cause).
3. `CTPOutcomeTracker::WriteRow()` skipped its own finalized-event
   bookkeeping when the journal file couldn't be opened (commit `6ce0a41`).
4. No safety-critical input validation existed at all; no resolved-config
   startup log existed (commit `acefa09`).

## Remaining blockers this audit did NOT close (explicitly out of scope this pass)

- `OnTimer()`-driven connectivity checking (disconnect can go unobserved by
  the kill parameter between `OnTick()` calls) -- real new logic, not a
  bounds-check fix; judged too large for this pass's remaining time budget.
- The two inert inputs (`InpBO_CompressionPct`, `InpMR_TargetSDBandR`) --
  a config cleanup, not a safety issue.
- `InpMaxHoldingMinutes`/`InpMaxPendingMinutes` authoritative-path audit
  across every exit call site.
- Full live/demo-forward alert-category firing matrix (needs real
  forward-time operation, not backtesting -- see the final deliverable's
  time-dependent-blocker list).
