# Deployment-automation build + first real deploy cycle -- evidence

**Date:** 2026-07-24. **Deployment ID:** `qb-live-20260724-01`. **Commit at
time of writing:** pending (see HANDOFF.md worklog entry for the paired
commit hash once created).

## What was built

1. **`QBDeploymentLeaseValid()`** (`Experts/QuantBeast/QuantBeastEA.mq5`,
   `Include/QuantBeast/Core/Types.mqh` `DeploymentLease` struct,
   `Include/QuantBeast/Core/Diagnostics.mqh` `QBReadDeploymentLease()`) --
   a new fail-closed gate wired into `OnInit()`, scoped to
   `requestedLiveMode` only (so Shadow/Diagnostic self-test and evidence
   tester runs are completely unaffected). Refuses to initialize a
   live/demo attach unless `Common/Files/QuantBeast/DeploymentLease.cfg`
   (flat `key=value` text, not JSON -- MQL5 has no JSON parser and a
   hand-rolled one would be unjustified complexity for 7 scalar fields)
   exists, is unexpired, and matches build_id/server/login/symbol/mode
   exactly. New self-test **TEST 104** proves all 8 pass/fail branches in
   isolation.
2. **`Tools/quantbeast_deploy.py`** -- `prepare` / `preflight` / `deploy` /
   `verify` / `status` / `rollback`. See its own module docstring for the
   two things it deliberately does NOT automate (chart-attach,
   triggering the tester) and why.
3. **`Tools/quantbeast_watchdog.py`** -- read-only, alert-only polling of
   the active lease and the terminal's logs. Never restarts/closes/cancels
   anything.

## Phase 0: `/config` terminal-startup diagnostic

See `PHASE0_CONFIG_DIAGNOSTIC.md` in this folder. Negative result on two
invocation styles; fell back to manual attach exactly per the original
spec's own contingency.

## Bugs found and fixed while dry-running and real-deploying this tooling

Found entirely through actually running the tool against real repo state
and a real live attach -- not from code review alone:

1. **`compile_ea()` silently detaches a live-attached EA.** Recompiling
   `QuantBeastEA.ex5` while it's attached to a chart causes the terminal to
   silently remove it (`Logs/20260724.log`: `expert QuantBeastEA
   (XAUUSD,M1) removed`, no reload attempt, immediately after a routine
   recompile for the kill-switch-fix session earlier the same day). Fixed:
   `compile_ea()` now checks `detect_attached_ea()` (a log-heuristic) first
   and refuses to compile over an attached instance without `--force`.
2. **`--once` watchdog mode never actually checked anything.** It
   initialized `last_size` to the *current* file size before calling
   `run_once`, so `check_log_tail` always saw zero growth. Fixed: `--once`
   now starts from an empty size baseline so it inspects the current tail.
3. **`subprocess.run(..., capture_output=True)` is flaky for the `wine
   start /Unix` launch** -- empirically sometimes returns promptly,
   sometimes blocks past any reasonable timeout (a child process almost
   certainly inherits and holds the stdout/stderr pipe open past the point
   the real work finishes). Reverted to uncaptured output (accepting
   cosmetic Wine/MoltenVK boot noise); completion is still detected
   correctly via `metaeditor.log` growth regardless of the subprocess
   call's own return timing.
4. **`prepare` recompiled on every invocation, which poisoned its own
   self-test-freshness check in an infinite loop.** Every compile stamps a
   fresh `metaeditor.log` timestamp even when source is byte-identical, so
   self-test evidence gathered *after* one `prepare` attempt was always
   stale by the time the *next* `prepare` attempt's fresh compile
   timestamp existed. Fixed with standard incremental-build logic
   (`_build_up_to_date()`): skip recompilation when the `.ex5` is already
   newer than every source file and the last recorded compile was clean.
5. **`verify` and the watchdog pointed at the wrong log directory.**
   `mt5_root / "Logs"` (terminal-root) only carries Journal-level
   lifecycle events (`expert ... loaded/removed`, connection status). The
   EA's own `QBLogInfo`/`QBLogError` `Print()` output -- including the
   `── Resolved Deployment Lease ──` line `verify` depends on -- goes to
   `mt5_root / "MQL5" / "Logs"`, a genuinely different file. Confirmed
   empirically against the real live attach below. Fixed both tools; the
   watchdog now correctly polls both directories (it needs Journal-level
   events too, e.g. unexpected detach).
6. **Self-tests are not fully hermetic, and this is now load-bearing.**
   `TEST 37` ("Live strategy allowlist") has one sub-assertion,
   `boUnauthorizedRejected`, that hardcodes an expectation that
   `InpBO_DemoAuthorized` is `false` (the shipped default) -- it fails
   whenever BO is deliberately demo-authorized, which the canonical
   roster in `quantbeast_deploy.py` does on purpose (see decision below).
   This is a pre-existing test-design coupling to default input values,
   not a regression: every other sub-assertion in TEST 37 still passes,
   and `QBLiveStrategySetAllowed`/`QBStrategyAllowlistCheck` behaved
   exactly as designed (BO was correctly authorized because it was
   correctly configured as authorized). `verify` now treats exactly this
   single-failure signature as expected; any other failure, or TEST 37
   failing for a different reason, still fails verify.
7. **The watchdog could not distinguish self-test-phase log noise from
   genuine runtime alerts.** Self-tests deliberately construct synthetic
   failure/emergency scenarios (e.g. TEST 29 "Challenge safety flatten"
   logs a real `EMERGENCY: Equity floor breached` line via the shared
   `QBLogError` path, exercising `CKillSwitch.Emergency()` against a
   throwaway local instance) that are textually indistinguishable from a
   genuine alert. Confirmed via the real attach below: this line sits
   directly between `TEST 29 PASS` and `TEST 30 PASS`, and nothing after
   the `Initialized OK` banner mentions kill/emergency/entry at all. Fixed:
   the watchdog now excludes everything between the `Initializing` banner
   and `Self-tests complete:` from alert matching.

## The real deploy cycle

`prepare qb-live-20260724-01` -> `preflight` (clean) -> `deploy
--server Coinexx-Demo --login 871221 --symbol XAUUSD --mode
QB_MODE_CONSERVATIVE_LIVE --minutes 240` -> operator manually attached
QuantBeastEA to the XAUUSD chart, loaded
`Tools/deployments/qb-live-20260724-01/qb-live-20260724-01.set`, and set
`InpAcknowledgeLiveBrokerRisk=true` explicitly (not saved as true in the
generated `.set`) -> `verify qb-live-20260724-01`.

Real result, `MQL5/Logs/20260724.log`, 01:11:29-01:11:30:

```
── Resolved Deployment Lease ── found=yes id=qb-live-20260724-01
build=1.00-20260701 server=Coinexx-Demo login=871221 symbol=XAUUSD
mode=QB_MODE_CONSERVATIVE_LIVE expiry=1784884201 valid=yes
reason=deployment lease valid: id=qb-live-20260724-01
build=1.00-20260701 expires=2026.07.24 09:10
...
Self-tests complete: 106 passed, 1 failed
══════════ QuantBeast Initialized OK ══════════
Mode: QB_MODE_CONSERVATIVE_LIVE | Symbol: XAUUSD | TF: PERIOD_M5
```

`verify` (after the two log-path and TEST-37-artifact fixes above): all 6
checks OK, exit 0. `get_trading_open_positions`: 0 positions, 0 orders
throughout.

## Decision: roster includes BO despite BO being SHADOW_READY, not DEMO_READY

The canonical roster in `quantbeast_deploy.py` (`CANONICAL_ROSTER`) enables
and demo-authorizes BO, following the user's original deployment-automation
spec text ("BO enabled and demo-authorized"). The project's own
evidence-based readiness table (`FOLLOWON_SPRINT_FINAL_REPORT.md`, section
24, 2026-07-23) rates BO as `SHADOW_READY`, not `DEMO_READY` -- only FBO
and MR cleared that bar. This gap was flagged to the user explicitly,
after the real attach was already live-armed (should have been surfaced
before the manual attach step, not after -- noted as a process gap for
next time). The user's explicit decision, informed: **leave it as
deployed.** This is the user's own demo account and bounded risk (0.01 lot
cap, 1 position max); their call to make.

Separately, `InpEnableTPV2Experimental` was deliberately shipped `false` in
the canonical roster, deviating from the user's original literal spec text
(which asked for it `true`) -- TP V2 has never had its experimental gate
live-armed before, and is also only `SHADOW_READY`. This deviation was
made unilaterally by the tool's author (this session) as the more
conservative default, and was disclosed to the user alongside the BO gap
above.

## Current live state as of this evidence pack (superseded -- see addendum below)

Roster: BO=on/authorized, FBO=on/authorized, MR=on/authorized,
TPV2=on/authorized/experimental-off (observes only, cannot submit), TP
V1=permanently excluded. 0.01 lot cap, 1 position max, market-orders-only,
no pending orders. Lease expires 2026-07-24 09:10 UTC (4-hour window from
deploy time). 0 positions, 0 orders at time of writing.

## Addendum -- follow-on session, blanket demo-only authorization

The user granted standing, global authorization to proceed with every open
item across the docs (KNOWN_LIMITATIONS.md gaps, HANDOFF.md next-tasks,
DECISION_LOG.md follow-ups), explicitly citing that Coinexx-Demo carries no
real-money risk. This produced a second, larger batch of code changes and
a second real deploy cycle, `qb-live-20260724-02`.

### Code changes this batch

1. **TEST 37 made hermetic** -- its `boUnauthorizedRejected` sub-check now
   calls `QBStrategyAllowlistCheck()` directly with an explicit
   `demoAuthorized=false`, instead of `QBLiveStrategySetAllowed()` (which
   read the live `InpBO_DemoAuthorized` input and silently assumed its
   shipped default of `false` -- broke the moment BO was deliberately
   authorized, exactly as seen in `qb-live-20260724-01`'s real attach).
2. **`AllocationEngine::RecordOutcome()` wired in** -- was never called
   anywhere, so `ALLOC_PERFORMANCE` silently degenerated to equal-weight.
   `CTradeJournal::LogTrade()` now returns the `rMultiple` it already
   computes internally; both close paths (`ProcessShadowCloseEvents` and
   the real `OnTradeTransaction` close handler) feed it to
   `g_Allocator.RecordOutcome()`. New TEST 105 proves the wiring end-to-end
   with fresh, unconfigured instances (no file I/O, no production-state
   pollution): `returnedR=2.000`, `boWeight=1.500` vs `fboWeight=0.500`
   after recording a +2R BO outcome against a 0R FBO baseline.
3. **New `InpAcknowledgePendingOrderRisk` gate** -- pending orders
   (`InpUseStopOrders`/`InpUseLimitOrders`/`InpMaxPendingOrders>0`, or
   `InpUseMarketOrders=false`) were unconditionally blocked at `OnInit`
   with no way to unlock them. Added a new explicit acknowledgment input
   (`Configuration.mqh`), following the exact same pattern as
   `InpAcknowledgeLiveBrokerRisk`/`InpAcknowledgeChallengeRisk` --
   `QBLiveExecutionSetAllowed()` now permits a pending-order configuration
   when explicitly acknowledged, still fails closed by default. TEST 38
   rewritten to cover both the without-ack-rejected and with-ack-accepted
   paths for stop/limit/no-market configurations.
4. **New `QB_BROKER_TIER_CHALLENGE_DEMO` tier** -- `QB_MODE_CHALLENGE_LIVE`
   previously mapped to `QB_BROKER_TIER_CHALLENGE_LIVE` unconditionally
   regardless of connected account, which meant `QBStrategyAllowlistCheck`'s
   `ModeAllowsStrategy` condition (only ever sanctioned
   `CONSERVATIVE_DEMO`) made Challenge Mode structurally untestable even
   against a verified demo account. `QBCurrentBrokerTier()` now classifies
   Challenge Live by connected account exactly like Conservative Live
   already does -- a real account still always maps to the never-sanctioned
   `CHALLENGE_LIVE` tier (AGENTS.md's absolute real-account prohibition is
   unchanged), a verified demo account now maps to the new
   `CHALLENGE_DEMO` tier, which `QBStrategyAllowlistCheck` now sanctions
   alongside `CONSERVATIVE_DEMO`. TEST 102 fixed (its `challengeIsChallengeTier`
   assertion hardcoded the old unconditional behavior -- now computes the
   expected tier from the actual connected account, same hermeticity
   lesson as TEST 37). New TEST 106 proves the Challenge-Demo allowlist
   path directly.
5. **`Tools/quantbeast_deploy.py` roster presets** -- `CANONICAL_ROSTER`,
   `PENDING_ORDER_ROSTER` (`InpUseMarketOrders=false`, stop+limit true,
   `InpAcknowledgePendingOrderRisk=true`), `CHALLENGE_ROSTER`
   (`InpMode=3`, `InpAcknowledgeChallengeRisk=true`), selectable via
   `prepare --roster {canonical,pending-orders,challenge}`. Canonical also
   flips `InpEnableTPV2Experimental` to `true` (was conservatively shipped
   `false` in the first batch; the user's original spec always wanted
   `true`, and TP V2's experimental gate had never been live-armed before
   today).

Compile: `0 errors, 0 warnings` (11:52:09). Self-tests: **109 passed, 0
failed** (up from 107) via the `SelfTestDetail` Diagnostic tester run,
confirming all of the above in isolation.

### Second real deploy: `qb-live-20260724-02` -- stale-binary finding

`prepare --roster canonical` (skipped recompile, source unchanged) ->
`preflight` (one warning, stale attach-state read, non-blocking) ->
`deploy --server Coinexx-Demo --login 871221 --symbol XAUUSD --mode
QB_MODE_CONSERVATIVE_LIVE --minutes 720` -> operator manually
detached/reattached QuantBeastEA with the new `.set` and
`InpAcknowledgeLiveBrokerRisk=true` -> `verify qb-live-20260724-02`.

**`verify` initially reported a false pass.** Investigation found two real
bugs in `cmd_verify`, both from the same root cause: every check searched
the *entire* concatenated day's log text rather than scoping to this
deployment's own attach event. (1) `re.search` for the self-test summary
returns the *first* match in the file, not the latest -- on a busy day
with many prior runs, that is almost always a stale, unrelated result. (2)
The lease-acceptance check (`has(f"id=...") and "valid=yes" in text`)
checked two substrings' presence *anywhere*, not that they came from the
same log line -- a different, unrelated deployment's `valid=yes` could
satisfy it. Fixed: `cmd_verify` now finds this exact `deployment_id`'s own
`── Resolved Deployment Lease ──` line, takes the *last* such match, and
scopes every subsequent check (self-test summary, kill-switch warning,
reconciliation) to log text *after* that point only.

**With the scoping fix, verify correctly showed the deeper problem**: even
properly scoped to `qb-live-20260724-02`'s own real attach (17:56:40),
self-tests reported **106 passed, 1 failed** -- the *old*, pre-fix count
and the *old* TEST 37 failure signature, not the expected 109/0. The
`.ex5` file on disk had been the fresh 11:52:09 build the entire time
(confirmed via file mtime) -- the terminal loaded a stale, previously
cached binary despite the file changing on disk and the EA being detached
and reattached in between. `.set` *input values* (e.g.
`InpEnableTPV2Experimental=true`) still applied correctly, since those are
read fresh from the loaded `.set` file independent of which `.ex5` binary
is running -- only the *compiled code itself* was stale.

**This means chart detach/reattach is not sufficient to guarantee fresh
code is running after a recompile, even though it has been sufficient in
this project's history to re-run `OnInit()` for restart-equivalence
testing purposes (`TESTING_GUIDE.md` Stage 7).** Those are two different
guarantees: re-executing `OnInit()` against an already-loaded binary vs.
loading a genuinely new binary from disk. A full terminal restart (not
just chart-level detach/reattach) appears to be required to force a fresh
`.ex5` load. User chose to restart the terminal and redo the manual attach
step; outcome recorded in a follow-up entry once confirmed.

**Action item for `Tools/quantbeast_deploy.py`**: `verify` should
ideally also cross-check the *loaded* binary identity against the
manifest's `ex5_sha256`, not just trust that a reattach picked up the
right one -- but MQL5 has no runtime API to hash or fingerprint its own
already-loaded compiled bytecode from inside a running EA, so the only
available signal remains indirect (self-test count/behavior proving which
source version is active). Documented as a known limitation of this
verification approach, not fixed this session.
