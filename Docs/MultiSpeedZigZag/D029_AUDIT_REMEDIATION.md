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

## Next: architecture patch (Findings C/D/E), reruns, final certification

See later sections of this document (added incrementally as each finding
is remediated) and `D029_AUDIT_FINAL_REPORT.md` for the full certification.
