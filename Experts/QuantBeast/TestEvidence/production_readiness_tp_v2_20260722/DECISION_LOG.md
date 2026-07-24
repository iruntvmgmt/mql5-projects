# Decision log -- production_readiness_tp_v2_20260722

---

Decision ID: D011
Date/time: 2026-07-23, restricted FBO+MR Conservative-Demo activation
Question: Under the user's explicit instruction to "activate the
restricted FBO+MR Coinexx demo candidate while BO and TP V2 continue in
Shadow," `QB_CONSERVATIVE_LIVE_FBO_MR.tpl` was built (derived from the
existing FBO-only Conservative-Live template) and applied to a live
XAUUSD chart by the operator (the agent's own attempt via
`chart_apply_template` was denied by the Claude Code auto-mode
classifier -- a hard, deliberate client-side guardrail on autonomously
attaching a broker-order-capable EA; the agent did not attempt to route
around it, per the denial's own instructions). Same for `git push`,
initially blocked by the classifier and only completed after the
operator explicitly updated their own Claude Code permission settings.
First two init attempts failed closed correctly (config combinations not
yet matching intent: TP V1 enabled, then TPV2 enabled-but-unauthorized).
Third attempt initialized successfully with the intended FBO+MR-only
roster -- but then exhibited a real bug: `ProcessKillSwitchActions()`
fired `CancelAllPending()`/`CloseAllPositions()` every second
indefinitely (harmless only because 0 positions/orders existed to act
on). Root cause: `CKillSwitch::IsFlattenAll()` returns true if EITHER
`flatten_all` OR `emergency` is set, and `emergency` has no automatic
clear by design (a deliberate fail-safe latch). `LoadKillSwitchState()`
had restored `emergency=true` from a stale, pre-existing
`QB_Emergency_871221_XAUUSD` GlobalVariable -- not a fresh trigger (real
equity 999.64 was nowhere near the 50.00 emergency floor) -- almost
certainly a leftover from an earlier, unrelated session/test that this
was the first live-attached, `InpUseGlobalVars=true` instance to ever
actually load and act on. Once latched, `IsEntryKill()` also returns
true, meaning the EA was silently unable to trade at all during this
window, not merely noisy.
Decision: instructed the operator to remove the EA from the chart
immediately (stops the 1-second timer); operator manually cleared the
stale `QB_Emergency_871221_XAUUSD` GlobalVariable (and checked the four
sibling kill keys) via MT5's Tools -> Global Variables dialog -- no code
change made to resolve this instance, since no MCP tool exposes
GlobalVariable read/write and the fix was a one-time data correction,
not a logic error requiring a source change to unblock this activation.
Reattaching afterward produced a clean init: no EMERGENCY line from the
real `g_KillSwitch`, no repeating CancelAll/CloseAll, self-tests
105/105, "0 positions reconstructed [clean]", confirmed roster
(FBO=on/MR=on, BO/TP/TPV2=off, DemoAuthorized FBO=yes/MR=yes,
BrokerTier=QB_BROKER_TIER_CONSERVATIVE_DEMO).
Reason: per the user's own instruction, this is intentionally NOTED as a
known issue rather than fixed in code this session -- the immediate
activation was unblocked by clearing the stale data, and a proper code
hardening (e.g., loudly surfacing a restored emergency at startup rather
than silently entering the retry loop, or requiring explicit operator
re-acknowledgment to resume after a restored emergency/flatten/cancel
latch) is deferred to a future pass if this recurs.
Trading-behavior impact: none from a broker-order perspective (0
positions/orders existed throughout; zero orders transmitted by this
sequence) -- but real: the EA was completely unable to enter any trade
during the ~35-minute window before the stale flag was cleared, which
would have silently suppressed any genuine FBO/MR organic signal that
occurred in that window had one occurred.
Files affected: none (data-only fix via MT5 GUI, no source changed).
Commit: (pending, this decision-log entry)
Follow-up: **KNOWN ISSUE, not yet fixed in code** -- if
`ProcessKillSwitchActions()` is ever observed hammering
CancelAll/CloseAll again on a fresh live attach, check
`QB_Emergency_871221_XAUUSD` (and `QB_KillFlatten_...`/`QB_KillCancel_...`/
`QB_KillEntries_...`/`QB_KillSymbol_...`) first before assuming a fresh
real trigger. Candidate hardening for a future pass: log the loaded
kill-switch state explicitly and loudly at `OnInit` (not just implicitly
via the retry spam), and/or require a distinct, explicit operator
acknowledgment input before a *restored* (not freshly-triggered)
emergency/flatten/cancel latch is allowed to actually execute broker
actions on a live attach.

---

Decision ID: D012
Date/time: 2026-07-23, kill-switch restore-warning hardening (follow-up to D011)
Question: D011 documented a known, deliberately-deferred defect --
`LoadKillSwitchState()` restoring a stale `emergency`/`entry_kill`/
`symbol_kill`/`cancel_all`/`flatten_all` latch from a prior session's
GlobalVariable silently blocked all entries and made
`ProcessKillSwitchActions()` loop `CancelAllPending()`/
`CloseAllPositions()` indefinitely, with zero log output explaining why.
Should this session (a) add loud `OnInit` logging of a restored latch,
(b) add an explicit operator re-acknowledgment gate before a restored
latch is allowed to execute broker actions, or (c) both?
Decision: Implemented (a) only -- a new pure formatter
`QBKillSwitchRestoreWarning(const KillSwitchState &state)`
(`Include/QuantBeast/Core/StateStore.mqh`, immediately after
`LoadKillSwitchState()`) returns a detailed, non-empty warning string
whenever any of `emergency`/`entry_kill`/`symbol_kill`/`cancel_all`/
`flatten_all` is set on the state just loaded from persistence, quoting
`emergency_reason` and pointing the operator at the `QB_Emergency`/
`QB_Kill*` GlobalVariables to check. `OnInit()`
(`Experts/QuantBeast/QuantBeastEA.mq5`, right after
`g_KillSwitch.RestoreState(savedKill)`) now calls it and logs the result
via `QBLogError()` when non-empty. New self-test
`QBTestKillSwitchRestoreWarning` (`Include/QuantBeast/Testing/
SafetyTests.mqh`), registered as TEST 103, proves: a clean state stays
silent, an emergency-latched state warns and includes the reason string,
and an entry-kill-only state (no emergency) also warns -- covering both
halves of the original silent-failure mode. (b), the re-acknowledgment
gate, was deliberately NOT implemented this pass -- see Reason.
Reason: (a) is a strictly additive observability fix with zero change to
any control-flow/safety decision, directly matching AGENTS.md's "never
weaken... kill-switch controls" rule and the "smallest coherent fix"
change-discipline. (b) would change real trading behavior: gating a
restored latch's cancel/flatten actions behind a fresh operator
acknowledgment could, in a genuine restart-during-a-real-emergency
scenario (e.g., terminal crash while equity-floor emergency was active
and positions were still open), delay or block the exact flatten action
the kill switch exists to guarantee -- an unacceptable safety regression
for an unconfirmed benefit, since D011's own incident caused no trading
harm (0 positions/orders throughout) and was already fully addressed by
making the state visible. (b) remains a candidate for a future pass if a
restored-latch incident recurs and loud logging alone proves
insufficient.
Verification: compile via `wine start /Unix metaeditor64.exe
/compile:"MQL5\Experts\QuantBeast\QuantBeastEA.mq5"` -- `0 errors, 0
warnings` (metaeditor.log, 2026.07.23 23:11:24). Self-test-only tester
run (`Profiles/Tester/QuantBeast.SelfTestDetail.20260722.ini` --
Diagnostic mode, `InpPersistState=false`, `InpUseGlobalVars=false`, no
journals, unmodified from its prior use) --
`Tester/Agent-127.0.0.1-3000/logs/20260723.log`: `Self-tests complete:
106 passed, 0 failed` (up from the pre-existing 105), `TEST 103 PASS:
Kill-switch restore warning cleanIsSilent=yes emergencyWarns=yes
entryOnlyWarns=yes`, zero `FAIL` lines anywhere in the run, `TEST 102`
and all prior tests still pass -- no regression. No broker orders
possible or attempted (Diagnostic mode, no persistence).
Trading-behavior impact: none -- purely additive logging; no change to
`IsEntryKill()`/`IsFlattenAll()`/`IsCancelAll()`/`ProcessKillSwitchActions()`
semantics.
Files affected: `Experts/QuantBeast/QuantBeastEA.mq5`,
`Include/QuantBeast/Core/StateStore.mqh`,
`Include/QuantBeast/Testing/SafetyTests.mqh`.
Commit: (pending operator approval to commit)
Follow-up: D011 is now **partially resolved** -- the silent-restore
observability gap is closed. The re-acknowledgment gate (D011's option
(b)) remains open/deferred by deliberate choice, not oversight; revisit
only if a restored-latch incident recurs and the loud `OnInit` log proves
insufficient in practice.

---

Decision ID: D008
Date/time: 2026-07-23, Phase 1 of the follow-on sprint (`QuantBeast_Production_Readiness_Sprint.md`)
Question: Independently verify the prior sprint's documented final state
before making any change, per the new sprint's explicit Phase 1 instruction.
What was checked and what, if anything, disagrees with the briefing document?
Evidence considered:
- HEAD: confirmed `4ad4031152b316ca88785e4437e9939910b2a482f` (matches).
- TP V1 tag: `quantbeast-tp-v1-research-freeze-20260722` resolves to
  `953c2d057ed4578b18244a1b24fab9a5c78f20e1`, exactly matching the documented
  freeze commit (matches).
- Compile: independently rebuilt, `0 errors, 0 warnings` (matches).
- Tests: independently reran the Model=1 self-test regression,
  `96 passed, 0 failed` (matches).
- Six-window/TP V2 totals: cross-checked the pooled `geometry outcome
  breakdown` lines across all 3 windows with TRIGGERED rows (6+4+8=18 rows
  = 9 unique episodes; TPV2_EXPERIMENTAL_DISABLED count = 1+1+2 = 4) against
  committed evidence files -- exactly matches "9 unique triggered episodes,
  4 fully qualifying" (matches).
- Readiness labels: cross-checked against
  `final_readiness/FINAL_PRODUCTION_READINESS_REPORT.md` section 13 --
  BO/FBO/MR/TP-V1/TP-V2 labels exactly match the briefing document (matches).
- TP V1/V2 isolation: both engines still reference distinct
  `QB_TP_LIFECYCLE_VERSION`/`QB_TPV2_LIFECYCLE_VERSION` constants and tag
  every diagnostic accordingly (matches).
- Working tree: unchanged pre-existing unrelated files only (matches).
- Open positions/orders: confirmed empty (matches, "no broker orders" claim holds).

**Two discrepancies found, documented here per the explicit instruction to
record any before proceeding:**

1. **Commit count.** The briefing states "current sprint contains 10
   commits." The actual count from the TP V1 freeze commit to the
   documented HEAD is **11** (`6ce0a41` through `4ad4031` inclusive). The
   likely explanation: the briefing was drafted counting only through
   `e22bfd0` (10 commits), before the final `4ad4031` "close out session
   manifest" commit landed. Not a defect -- just a one-commit undercount in
   the briefing, noted for the record.
2. **Ahead/behind `github/main`.** The briefing states "1 commit ahead."
   Actual, freshly measured: **3 ahead, 0 behind**. More importantly:
   `git reflog show github/main` shows `github/main` was moved by actual
   `update by push` events, most recently landing on `cce55a2` -- meaning
   something pushed local commits to the remote. **This was not done by any
   `git push` command run in either this or the prior session** (none was
   ever issued). The most likely mechanism is the MT5 terminal's own
   integrated "MQL5 Algo Forge" Git feature (seen activating in the
   terminal log at prior session start: "Git MQL5 Algo Forge activated...
   Git 1 personal projects found"), which appears to auto-sync commits to
   the configured remote independent of any explicit push command from
   either agent session. This is flagged transparently rather than treated
   as a violation of "do not push unless explicitly instructed" -- that
   instruction has been honored on the agent side (zero `git push` commands
   issued); the repository's own tooling is doing something outside agent
   control. Not attempting to disable or reverse this (no destructive/
   configuration-altering action taken) -- documenting only.
Decision: Proceed with the sprint. Both discrepancies are explainable,
non-blocking, and do not indicate any repository-state conflict with the
documented starting point (Phase 16's stop condition). Neither required
touching the remote, tags, or any destructive command.
Trading behavior affected: None -- read-only verification.
Files affected: none (verification only).
Commit: (pending, verification-phase commit)
Follow-up: if github/main's auto-sync behavior is ever a concern, that is
an operator-level MT5/Git-Forge configuration question, out of scope for
this agent to change unilaterally.

---

Decision ID: D009
Date/time: 2026-07-23, Phase 3 (TP V2 Shadow promotion gate)
Question: A dedicated Shadow profile with `InpEnableTPV2Experimental=true`
was built and run against the 2025-01-06 window (reproducing the exact
tick/bar counts of the original evidence run: 240,447 ticks, 276 bars,
natural completion). The known-qualifying SELL episode at 2025.01.06
07:15:00 still shows `TPV2_EXPERIMENTAL_DISABLED` in `SignalJournal.csv`,
and the new startup config log (`QBLogResolvedProductionConfiguration`,
added in the prior sprint's Part F) explicitly confirms
`TPV2Experimental=off` was the value actually applied at `OnInit` --
proving this is not a misread of the journal, it is a real input-
non-application. Stop and report, or diagnose further/restart unilaterally?
Evidence considered: this matches, in exact kind, a previously documented
finding (`tp_displacement_matrix_20260722/README.md`): "The first attempted
0.8 run was invalid: MT5 omitted the new input from its effective schema
and reproduced the 1.0 funnel... After restart, the effective-input log
explicitly recorded 0.8." `InpEnableTPV2Experimental` is itself a genuinely
new input (added this sprint, commit `026e91c`), consistent with the same
"MetaEditor/terminal's cached effective-input schema doesn't yet recognize
a just-compiled new input inside the tester" class of issue. The `.ini`
line format used (`InpEnableTPV2Experimental=true||false||0||true||N`)
exactly matches every other working boolean input's serialization in this
same profile family (verified against `InpAcknowledgeLiveBrokerRisk`,
`InpTP_Enabled`, etc.), ruling out a simple formatting mistake.
Options considered: (a) restart the MT5 terminal myself (the documented
prior fix) and continue Phase 3 immediately; (b) stop and report before
restarting.
Decision: (b). Phase 16 of this sprint's own instructions explicitly lists
"a normal terminal restart may restore a live-armed chart" as a stop
condition requiring the agent to halt and report rather than act
unilaterally. Current state is low-risk (zero open positions/orders
confirmed immediately before this run and again now; the one open chart,
XAUUSD H1, shows no attached EA in `list_open_charts`) but "appears
low-risk" is not the same as explicit authorization for a stop-listed
action, so proceeding without asking would not honor the instruction's own
terms.
Trading behavior affected: None -- read-only diagnosis only; the
experimental flag never actually applied, so TP V2 never reached a valid
signal in this run either (confirmed: zero TPV2 ACCEPTED rows).
Files affected: none this decision (profiles created, no source changed).
Commit: (pending)
Follow-up: pause and report to the user; await explicit authorization
before any terminal restart.

---

Decision ID: D001
Date/time: 2026-07-22, session start
Question: Should TP V1 be preserved via a Git tag alone, or also kept as a
selectable runtime implementation alongside V2?
Evidence considered: Protocol section 6 ("prefer retaining a selectable V1
implementation if practical; otherwise ensure exact checkout/build recovery
through tag and documentation"). V1's `CTrendPullbackEngine` /
`CTPOutcomeTracker` are already wired into `QuantBeastEA.mq5` as the live TP
strategy (Strategy 3). V2 is a new, structurally different engine (8-state
lifecycle vs V1's 6-state) that will coexist alongside V1, not replace it in
this sprint.
Options considered: (a) tag only, V1 code removed/replaced by V2; (b) tag +
keep V1 engine wired exactly as-is, add V2 as an independent, separately-
switched engine; (c) build a runtime selector input that swaps between V1/V2
implementations in the same engine class.
Decision: (b). Keep V1's engine and tracker wired unchanged (available for
future passive larger-window verification, per the user's explicit
instruction), add V2 as a new, independent engine/tracker pair behind its own
experimental default-OFF input.
Reason: V1 and V2 model fundamentally different lifecycles; forcing them
into one class via a runtime selector would blur the "no direct dependency on
regime.structure as sole authority" redesign V2 requires, and would risk
V1/V2 state cross-contamination. Two independent classes, two independent
journals, an explicit `LifecycleVersion` tag, and a Git tag together satisfy
the preservation requirement without a runtime selector's added complexity/risk.
Trading behavior affected: None (both V1 and V2 remain non-authoritative /
experimental-off by default).
Files affected: (pending V2 implementation)
Commit: (pending)
Follow-up: none.

---

Decision ID: D002
Date/time: 2026-07-22
Question: Where should the `LifecycleVersion` field live, and does adding it
require a schema-version bump?
Evidence considered: `TPOutcomeJournal.csv`'s header is written once, at file
creation (`OpenJournalFile()`'s `!exists` branch) -- appending a new column to
an already-existing physical file's live header would silently misalign all
future rows against the old header line for a byte-0 read.
Options considered: (a) add the column without bumping `SchemaVersion`,
accept the misalignment risk for any pre-existing physical journal; (b) bump
`SchemaVersion` 1->2, rotate the live (untracked, non-evidence) journal files
so the new header is written fresh, and make `tp_outcome_report.py` schema-
aware (column count fallback) for any historical schema-v1 slice.
Decision: (b).
Reason: The live `TPOutcomeJournal.csv`/`Tester/TPOutcomeJournal.csv` files
are runtime infrastructure, not committed evidence -- their entire byte range
was already independently verified to be fully captured in the committed
`tp_forward_outcome_20260722/` evidence before rotation (tester file:
`[0,23708)` on disk == last recorded end-offset in that evidence's README;
terminal file: header-only, 1 line). Rotating them loses nothing already
captured and avoids leaving a live file whose on-disk header silently
disagrees with the rows appended after this change.
Trading behavior affected: None.
Files affected: `Include/QuantBeast/Analytics/TPOutcomeTracker.mqh`,
`Include/QuantBeast/Strategies/TrendPullbackEngine.mqh`,
`Experts/QuantBeast/Tools/tp_outcome_report.py`,
`Experts/QuantBeast/Tools/tp_rejection_attribution_report.py`.
Commit: (pending, this phase's commit)
Follow-up: none.

---

Decision ID: D003
Date/time: 2026-07-22
Question: A live journal file rotation via host-level `mv` (bypassing MCP
file tools) was followed by that same file becoming permanently unable to
reopen (`FileOpen` error 5004) across three subsequent tester runs. Root
cause and fix?
Evidence considered: Deleting and letting the file recreate fresh via the
proper MCP `delete_file` tool (instead of host `mv`) did **not** resolve the
failure -- it reproduced identically on a file that had never been touched by
host tools at all. This ruled out the host-`mv` theory. Further evidence: in
the same failing run, `CounterfactualJournal.csv` (a pre-existing, previously
untouched file, reopened via the normal global-tracker-Init-once-per-run
pattern) wrote successfully. The failure is specific to the TP-outcome
self-tests' pattern of ten separate local `CTPOutcomeTracker` instances each
calling `Init()`/opening the same filename back-to-back within one process
(Tests 65-74) -- a pattern no other test in this codebase uses, since every
other tracker is a single global instance `Init()`'d once per `OnInit()`.
Options considered: (a) root-cause and fix the underlying Wine/MQL5 file-
handle behavior itself (open-ended, may not be fixable from EA-side code);
(b) accept the self-test-only flakiness as an environment characteristic and
fix the resulting real defect it exposed instead -- `WriteRow()`'s early
return on invalid handle was *also* skipping `m_totalFinalized`/
`m_lastFinalized` bookkeeping, which is a genuine observability bug
independent of this specific flakiness (a production run with a transient
journal-open failure would silently and permanently misreport finalized-
event counts).
Decision: (b). Moved the bookkeeping above the handle-validity check in
`WriteRow()` so it always reflects true in-memory finalization state; the
file write itself remains conditional on a valid handle, as before.
Reason: The flakiness only reproduces under a ten-instances-one-process
pattern unique to this self-test block; the real production/evidence-run
pattern (one global tracker, `Init()` once per run, matching every other
journal in this codebase across dozens of prior successful evidence runs) is
unaffected. Chasing the Wine-level root cause further was judged
disproportionate to its real-world impact, whereas the bookkeeping fix is a
genuine, narrowly-scoped correctness improvement regardless of environment.
Trading behavior affected: None (observation-only tracker, no
signal/risk/arbitration path).
Files affected: `Include/QuantBeast/Analytics/TPOutcomeTracker.mqh`.
Commit: (pending, this phase's commit)
Follow-up: If this flakiness is ever observed in a real evidence-gathering
tester run (not just the self-test block), re-open the file-handle
investigation -- it has not been seen there in this or any prior session.

---

Decision ID: D004
Date/time: 2026-07-22
Question: Which of the four predefined TP V2 trigger types should be the
default (`InpTPV2_TriggerMode` default value)?
Evidence considered: The economic hypothesis text itself ("demonstrates
renewed directional control through an explicit resumption trigger"). No
historical trade-count comparison across the four variants was run or
consulted before this decision -- by design, per the audit protocol's
explicit instruction not to select a default based on which produces the
most historical trades.
Options considered: (1) closed-bar micro-structure break -- simplest, but a
bare break of a small local extreme is weak evidence of "control" specifically
(price moving is not the same as a market rejecting adverse movement); (3)
displacement reclaim -- requires a large committed bar, may fire well after
control was already re-established, understating how early genuine control
can be observed; (4) break-retest -- a reasonable two-phase confirmation but
strictly a refinement of (1), inheriting its weakness on the initial break;
(2) rejection + directional confirmation -- a rejection wick against further
retracement, confirmed by a directional close, is the most direct measurement
of the market *rejecting* continued adverse movement at a specific point.
Decision: (2), rejection + directional confirmation, is the default. The
other three remain explicit, individually selectable research variants.
Reason: (2) most literally matches the hypothesis's own wording about
"renewed directional control" being *demonstrated*, not merely inferred from
price having moved a certain distance.
Trading behavior affected: None yet -- TP V2 ships with
`InpEnableTPV2Experimental=false`; this only fixes which trigger fires first
when the experimental flag is eventually enabled and evidence supports it.
Files affected: `Include/QuantBeast/Strategies/TrendPullbackV2Engine.mqh` (pending implementation)
Commit: (pending, spec commit)
Follow-up: If organic evidence in `../unified_strategy_matrix/` shows the
default trigger never organically fires while others would have, that is
itself evidence worth recording -- not grounds to silently swap the default
without a new decision entry.

---

Decision ID: D005
Date/time: 2026-07-22
Question: Adding TP V2 as a 5th strategy (QB_STRAT_COUNT 4->5) surfaced two
fixed-size arrays sized for exactly 4 strategies. Fix immediately or defer?
Evidence considered: `KillSwitchState.strategy_kill` was `bool[4]` (Types.mqh)
-- writing `strategy_kill[4]` for TPV2 would silently overrun. The
arbitration loop's `StrategySignal candidates[8]` (QuantBeastEA.mq5, 4
strategies x 2 directions) would silently overrun once a 5th strategy could
produce 2 more candidates in the same bar.
Options considered: (a) defer TPV2's strategy-array wiring to a later pass
to avoid touching these; (b) fix both bounds immediately as part of wiring
TPV2 in.
Decision: (b), fixed immediately.
Reason: Per the audit protocol, "engineering safety defects may be fixed
immediately" -- these are exactly that category: silent fixed-array overruns
newly reachable the moment a 5th strategy exists, unrelated to any economic
threshold or trading-behavior choice. Leaving them would make TPV2's mere
presence in the strategy roster a latent memory-safety hazard regardless of
whether InpEnableTPV2Experimental is ever turned on.
Trading behavior affected: None -- both fixes only widen array bounds to
match the new strategy count; no logic changed.
Files affected: `Include/QuantBeast/Core/Types.mqh`,
`Experts/QuantBeast/QuantBeastEA.mq5`.
Commit: `026e91c`
Follow-up: Part F (infrastructure audit) should grep for any other
per-strategy fixed-size arrays this pass may have missed.

---

Decision ID: D006
Date/time: 2026-07-22
Question: Should the restricted all-strategy Conservative Demo candidate
(Part G) include TP V1, TP V2, both, or neither, and should
`QBLiveStrategySetAllowed()` (the FBO-only live gate) be updated to let the
prepared candidate actually initialize?
Evidence considered: TP V1's own frozen evidence found "no reliable
directional information" (`tp_v1_freeze/README.md`) -- there is no basis to
include it in a trading candidate. TP V2 has zero organic evidence yet
(Part E, the unified matrix, has not run -- it is deliberately last in this
sprint). `QBLiveStrategySetAllowed()` explicitly documents its own
restriction as evidence-gated ("BO/TP/MR accepted-entry evidence is not
complete"), and the task instructions explicitly prohibit weakening gates
to make a strategy trade.
Options considered: (a) include V1 in the roster since it's already wired
and enabled elsewhere; (b) include V2 with its experimental flag ON,
banking on this sprint's implementation alone as sufficient evidence; (c)
include V2 with the experimental flag OFF (lifecycle observes, never
trades), exclude V1 entirely from this trading candidate, and leave
`QBLiveStrategySetAllowed()` untouched.
Decision: (c).
Reason: V1 has a completed, negative research result -- putting it in a
"candidate" roster would misrepresent settled research as still-open.
V2 has an implementation but zero organic reachability evidence yet (a unit
fixture generating a signal is explicitly NOT sufficient per the task's own
Part H rule) -- shipping it with the experimental flag on would be
promoting on code existing, not on evidence. Leaving the live gate
untouched keeps this a genuinely PREPARED-not-ACTIVATED artifact: loading
it today fails closed at `OnInit` with the same "Live strategy gate blocked
initialization" message any non-FBO-only config gets, which is correct,
not a bug in the preset.
Trading behavior affected: None -- the preset is a new, uncommitted-until-
staged `.set` file; nothing about its existence changes any running
behavior, and it cannot currently initialize in a live-armed mode at all.
Files affected: `Experts/QuantBeast/XAUUSD_Conservative_Demo_AllStrategy.set`
Commit: (pending, Part G commit)
Follow-up: once `../unified_strategy_matrix/` evidence exists (Part E),
revisit whether TP V2's experimental flag and/or
`QBLiveStrategySetAllowed()` should change -- as its own decision entry,
evidence-cited, not a silent edit to this preset.

---

Decision ID: D007
Date/time: 2026-07-22, before launching any Part E evidence run
Question: Which XAUUSD M5 windows should the unified all-strategy matrix
use, and how many?
Evidence considered: the task requires previously-tested windows
(regression reproduction), untouched windows, and windows chosen for
high-volatility/quiet/London-NY-overlap/mixed-regime coverage, without
optimizing against untouched windows. V1's forward-outcome sprint
(`tp_forward_outcome_20260722/README.md`) used 6 windows at comparable
scope and that was judged proportionate evidence for a similarly-bounded
research question.
Decision (fixed BEFORE running anything, in order):
1. `2026-01-05_20260106` -- reused (V1 evidence), regression reproduction.
2. `2025-01-06_20250107` -- reused (V1 evidence), regression reproduction,
   different year/session mix.
3. `2026-02-16_20260220` -- reused (V1 evidence), largest-n TP V1 window,
   distinct regime.
4. `2026-06-20_20260624` -- reused (V1 evidence), regression reproduction.
5. `2026-03-30_20260407` -- untouched by any prior TP research, full week,
   different month/quarter.
6. `2026-06-22_20260623` -- untouched, single day, different session
   composition from the others.
Reason: reusing 4 already-characterized windows gives true regression
reproduction (proves nothing silently changed for BO/FBO/MR/TP-V1's
already-observed behavior when TPV2 was added to the roster) while 2 new
windows give genuine untouched validation, matching V1's precedent scale
without expanding scope further given the size of this sprint already.
This list is fixed before any window is run -- if a later window shows an
interesting result, it is reported as-is, not used to justify adding or
dropping windows after the fact.
Trading behavior affected: None -- Shadow-mode evidence gathering only, no
broker orders transmitted, InpEnableTPV2Experimental=false throughout.
Files affected: none (evidence-gathering decision, not a code change).
Commit: (pending, Part E evidence commit)
Follow-up: none -- this list is final for this sprint's Part E pass.

---

Decision ID: D010
Date/time: 2026-07-23, following the user's explicit demo-broker-order
authorization ("Continue through all remaining phases now... I explicitly
authorize broker-order transmission on the connected Coinexx demo
account for bounded production-readiness testing")
Question: How to use the granted authorization to accelerate Phases 7-10
(real broker-path proof for submission, ack, fill, SL/TP, modification,
close) without an established mechanism to programmatically attach a live
EA instance to an MT5 chart (no precedent found this session; only
generic indicator `.tpl` templates exist under `Profiles/Templates/`; the
one historical live EA activation in this project was done manually by
the operator via the GUI Inputs-tab Load button)?
Evidence considered: the authorization's own text distinguishes
`CONTROLLED_EXECUTION_FIXTURE` (bounded diagnostic signal exercising
broker infrastructure) from `ORGANIC_DEMO_EVIDENCE` (a real strategy
signal that naturally qualifies and is submitted by the running EA) and
explicitly permits using controlled fixtures "for rare management
branches... rather than waiting for an organic strategy trade." The
authorized bounds (XAUUSD only, 0.01 lots max, one position max, market
orders only, mandatory SL) match exactly what the direct MCP trade tools
can safely exercise without any EA attachment.
Options considered: (a) attempt to construct or modify a chart template
to auto-attach the EA in a live-armed state programmatically, to also
prove OnTradeTransaction/EA-side reconstruction; (b) scope this pass to
direct-MCP-tool CONTROLLED_EXECUTION_FIXTURE proof only (order submit,
ack, fill, SL/TP, modification, close), and explicitly document
EA-attached-live proof as a separate open item.
Decision: (b).
Reason: (a) has no safe precedent in this project and risks an
unintended live-armed EA state on a chart outside the pre-flight
verification this sprint requires before every broker-sensitive action;
(b) directly satisfies the authorization's own stated purpose ("use
demo transmission to accelerate these phases") for every infrastructure
item that does not require EA-side code to be running, while leaving
the EA-attachment gap honestly reported rather than worked around.
Trading behavior affected: One bounded fixture position opened and
closed (see `run_manifests/run_ce01_20260723_broker_fixture.md`) --
0.01 lots XAUUSD, protected throughout, flattened at the end. No
strategy threshold, arbitration, or risk logic touched or exercised.
Files affected: `run_manifests/run_ce01_20260723_broker_fixture.md` (new).
Commit: (pending)
Follow-up: EA-attached-live proof (OnTradeTransaction recognition,
EA-side protection repair, restart+reconstruction against a real
position, organic autonomous submission) remains open, pending either
operator action to attach the EA to a live chart, or further explicit
guidance on a safe programmatic attachment method.

---
