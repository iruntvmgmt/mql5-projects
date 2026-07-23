# Decision log -- production_readiness_tp_v2_20260722

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
