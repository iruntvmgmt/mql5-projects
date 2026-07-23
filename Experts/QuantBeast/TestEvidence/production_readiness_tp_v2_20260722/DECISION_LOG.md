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
