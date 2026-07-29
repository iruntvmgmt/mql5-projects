# D029 Audit Remediation — Evidence Certification and Partial-Exit State Safety

Branch `feature/d029-audit-remediation`, forked from D029's final SHA
`64f2e29f20a20f3fe362e073c8873262f2183d3e`. This is not a new strategy
study — it does not optimize entries, exits, thresholds, partial
fractions, targets, stops, or portfolio rules. Its purpose: verify D029's
evidence claims independently, repair a real execution-safety defect found
in the process, and issue a corrected certification.

## Finding A — candidate-stream identity: proven, not merely counted

`Tools/D029/Audit/analyze_candidate_streams.py` compares every
`RAW_CANDIDATE` row across SR0/SR3_PCT/SR4_PCT field-by-field (time,
strategy_id, setup, direction, score, entry, stop, target, origin_id,
event_id, strategy_family — every stable field actually present in
`MSZZ_SignalJournal.csv`), with frozen tolerances (prices <=1e-8, score
<=1e-10, timestamps/IDs exact), deterministic canonical serialization, and
a SHA-256 hash per run.

**Result: all three streams are byte-for-byte identical** — 376/376/376
rows, three matching canonical hashes, zero first-differing row. D029's
original claim ("RAW_CANDIDATE=376 for all three, proving zero effect on
candidate generation") was correct, and is now independently proven rather
than inferred from equal counts alone.

**Disclosed schema gap**: `MSZZ_SignalJournal.csv` does not export
`evaluation_time` or `expiry_time` as distinct fields at the RAW_CANDIDATE
stage — only `time` is captured. The comparison above uses every field
that genuinely exists; it does not fabricate the two requested-but-absent
fields.

**Extended check (not required by the handoff, same-class risk, cheap to
verify)**: applied the identical method to D029 Phase 2's D29-A vs D29-E
claim. Their candidate streams are **not** byte-identical — `target`
differs starting at the very first row (2.0R vs 3.0R, as configured) — but
every field upstream of target (time, strategy_id, setup, direction,
score, entry, stop) matches exactly. This is structurally expected (A and
E use different configured R-multiples) and does not contradict D029's
original Phase 2 language, which only compared candidate *counts* between
A and E, never claimed row-level identity. Documented here to preempt any
future misreading.

## Finding C — historical atomicity audit: one real, confirmed defect

`Tools/D029/Audit/audit_partial_atomicity.py` checks every historical
partial-close event in SR3_PCT, SR4_PCT, P3_SR3, and P4_SR3 for a matching
successful protection modify at the same book_id and timestamp (the EA
labels this action `STOP_MODIFY` for SR1/SR3 and `STRUCTURAL_TRAIL` for
SR2/SR4 — both checked).

**Result: exactly one unprotected partial in each of the four runs, all
at the identical timestamp `2025.03.25 15:25:00`** — the same underlying
SweepReclaim trade across all four variants (proven identical by Finding
A). The raw journal:

```text
2025.03.25 15:25:00;2;3;PARTIAL_CLOSE;1.0264;3018.70;3016.43;0.55;true;...
2025.03.25 15:25:00;2;3;STOP_MODIFY;1.0264;3018.70;3016.43;0.00;false;...
```

The partial close succeeded (0.55 lots closed at broker confirmation), but
the breakeven `PositionModify()` call was rejected by the broker. The
current (pre-remediation) code has no retry and no protection-state
check — it marks the partial "done" purely on the partial's own success,
leaving that remainder running at its **original** stop instead of
breakeven for the rest of its life. This is exactly the non-atomic failure
mode Finding C predicted, now confirmed as a real, reproducible historical
event (not hypothetical) — 1 out of 86/82/64/63 partials respectively.

**Per the handoff's own rerun-decision rule** ("No full rerun is required
only if all are true: ... all historical partials had successful matching
protection ...") — this condition is **false**. A full rerun of all seven
affected runs (`D29_SR0`, `SR3_PCT`, `SR4_PCT`, `D29_P3`, `D29_P4`,
`P3_SR3`, `P4_SR3`) is required once the architecture patch below lands,
per "do not selectively rerun favorable variants."

## Finding C — partial-protection state machine (architecture patch, partial)

Added `ENUM_MSZZ_PARTIAL_PROTECTION_STATE` (`MSZZ_PARTIAL_NOT_STARTED`,
`MSZZ_PARTIAL_CLOSE_PENDING`, `MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING`,
`MSZZ_PARTIAL_PROTECTED`, `MSZZ_PARTIAL_PROTECTION_FAILED`) and four new
`MSZZStrategyBookState` fields (`protection_state`,
`protection_retry_count`, `protection_target_stop`,
`protection_remove_target`) in `StrategyBook.mqh`, persisted via a new
`UpdatePartialProtectionState()` method guarded identically to the
existing `UpdateExitManagementState()`.

`MultiSpeedZigZagEA.mq5`'s partial-close handling now attempts the
protection `PositionModify()` (or `STRUCTURAL_TRAIL` removal for SR4)
**immediately inline** after a successful `PositionClosePartial()`, in the
same decision-bar call — this is what the historical journal already did,
just without a state to fall back on when the modify failed. On modify
failure the book now enters `MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING`
instead of being silently marked complete. A new `ProcessPendingProtection()`
function retries the modify on every subsequent closed bar
(`MSZZ_PROTECTION_MAX_RETRIES=3`, frozen), journaling every attempt via the
existing `JournalExitManagement()` call with a new `PROTECTION_RETRY`
action label. `ProcessOneBookExit()` skips calling
`CMSZZBookExitManager::Evaluate()` entirely while a book is in
`EXECUTED_PROTECTION_PENDING` — this blocks SR4's runner-phase progression
by construction, without any change to the already-tested pure
`CMSZZBookExitManager` class. After retry exhaustion, the remainder is
emergency-closed via `g_trade.PositionClose()`
(`PROTECTION_EMERGENCY_CLOSE` journal action); if that close also fails,
`g_recovery_required` is set and a `CRITICAL` journal line is written —
new entries are blocked project-wide via the existing D009
`g_recovery_required` mechanism.

**Side-effect gap found and fixed**: `ExecutePortfolioBookCandidate()`
(the multi-book path used by P3-SR3/P4-SR3) never checked
`g_recovery_required` at all — only the single-book `ExecuteCluster()`
path did. Since P3-SR3/P4-SR3 run exclusively through the multi-book path,
the new emergency-close-failure block would have been silently
unenforceable for exactly the configs Finding C targets. Fixed by adding
the identical guard to the top of `ExecutePortfolioBookCandidate()`.

**Still open for Finding C** (not yet done as of this commit): restart
persistence wiring (`ReconstructProtectionStateOnRestart()` exists on
`CMSZZStrategyBook` but is not yet called from `OnInit()`), and the 12
required runtime tests (partial+modify success/failure combinations, retry
exhaustion, emergency close, SR4 target-removal confirmation, runner
blocked before protection, restart-after-partial, own-family/broker
SL-TP races during pending protection, no duplicate partial/journal rows).
These will land in a follow-up checkpoint before any rerun is executed.

## Finding D — generic volume-min vs volume-step eligibility, fixed

`CMSZZPositionSizing::ComputePartialSplit()` previously took only
`volume_step` and silently assumed `volume_min==volume_step` — wrong
whenever a broker's minimum tradable size exceeds its step (e.g.
`min=0.10, step=0.01`), a case the original code never rejected. The
signature now requires `volume_min` and returns a `reason` string;
**both** legs (partial and remaining) are independently checked against
`volume_min`, not just the whole position against `2*volume_step`.
`Calculate()`'s `partial_capable` flag and the EA's
`ComputeSizedVolume()`/`ProcessOneBookExit()` call sites were updated to
fetch `SYMBOL_VOLUME_MIN` and use the corrected logic; the EA's
skipped-volume journal entry now records the actual rejection reason
instead of a generic hardcoded string.

All ten required test cases from the handoff (min==step splits, min>step
valid/invalid at two different step sizes, fraction 0/1 rejection, full-
consumption rejection, remainder-below-minimum isolated from
partial-below-minimum, odd-step determinism under min>step) were added to
`Tests/MultiSpeedZigZag/Test_MSZZ_PositionSizing.mq5` and pass:
`Test_MSZZ_PositionSizing: failures=0` (75 assertions total, including the
pre-existing D029 Phase 1/3 suite). XAUUSD's actual broker metadata has
`volume_min==volume_step==0.01`, so this fix changes no behavior for any
run XAUUSD ever produced under D029 — it only closes a latent correctness
gap for brokers/symbols where the two differ. Since no D029 volumes
change, this alone does not trigger a rerun; the rerun trigger is Finding
C's historical atomicity failure (see above).

**Regression**: all 29 `Test_MSZZ_*`/`Export_MSZZ_Parity` suites compiled
clean and passed on the isolated instance after this commit (`failures=0`
across the board, including `Test_MSZZ_StrategyBook` and
`Test_MSZZ_PositionSizing`), and `MultiSpeedZigZagEA.mq5` compiles with 0
errors/0 warnings.

## Next: Finding C completion, Finding E, reruns, final certification

See later sections of this document (added incrementally as each finding
is remediated) and `D029_AUDIT_FINAL_REPORT.md` for the full certification.
