# D029 Audit Remediation — Tools

Scripts supporting the D029 audit-remediation pass on branch
`feature/d029-audit-remediation` (forked from D029's final SHA
`64f2e29f20a20f3fe362e073c8873262f2183d3e`). See
`Docs/MultiSpeedZigZag/D029_AUDIT_REMEDIATION.md` for the full narrative
and results; see `D029_AUDIT_FINAL_REPORT.md` (once written) for the
certification decision. All scripts fail loudly (nonzero exit, printed
`FATAL:` message) on missing input files or a failed certification
condition, and write deterministic CSV output.

## Scripts

- **`analyze_candidate_streams.py`** (Finding A) — compares every
  `RAW_CANDIDATE` row across SR0/SR3_PCT/SR4_PCT field-by-field with
  frozen tolerances, canonical serialization, and a SHA-256 hash per run.
  Produces `candidate_stream_hashes.csv`, `candidate_stream_diff.csv`,
  `candidate_stream_summary.csv`. **Result: all three streams byte-for-
  byte identical.**

- **`audit_partial_atomicity.py`** (Finding C, historical audit) —
  checks every historical `PARTIAL_CLOSE` event in SR3_PCT/SR4_PCT/
  P3_SR3/P4_SR3 for a matching successful protection modify
  (`STOP_MODIFY`/`STRUCTURAL_TRAIL`/`BREAKEVEN`) at the same book_id and
  timestamp. Produces `partial_protection_atomicity.csv`,
  `partial_protection_summary.csv`. **Result: exactly 1 unprotected
  partial in each of the 4 runs, same underlying trade
  (2025.03.25 15:25:00) — this is why a full rerun is required.**

- **`corrected_partial_fraction_analysis.py`** (Finding G) — reprocesses
  `MSZZ_PartialCloseJournal.csv` for SR3_PCT/SR4_PCT/P3_SR3/P4_SR3 with
  corrected terminology: exact 50.0000% (floating tolerance), within 1pp,
  within 2pp, outside 2pp, min/max/mean/median fraction — replacing the
  original Phase 3 analyzer's mislabeled `abs(f-0.5)<0.02` "exact_50".
  Produces `corrected_partial_fraction_summary.csv`.

- **`audit_portfolios.py`** (Finding H) — native/logical trade count
  consistency, duplicate logical IDs, strategy/family attribution,
  partial counts, risk-cap sequence integrity, exit-management action
  inventory (whitelist grounded in the EA's real action labels, not
  guessed), top-1/3/5 and best-quarter exclusion, dev/val/holdout split,
  long/short split, output hashes. Produces `portfolio_integrity_audit.csv`,
  `output_hashes.csv`. **Result on current (pre-rerun) evidence:
  `overall_integrity_ok = True`** for all four variants — this is a
  pre-rerun baseline and must be re-run against fresh rerun output.

## Still to be written (see D029_AUDIT_REMEDIATION.md "Next" sections)

- `reconcile_deals_and_r.py` (Finding B) — independent deal-level
  weighted-R reconciliation. Blocked on adding a durable per-deal export
  journal to the EA (the original Phase 3/4 runs never captured this).
- `analyze_d029_audit.py` (Finding H) — umbrella script tying A/C/G/H's
  individual outputs into one pass/fail summary.
- `sizing_reconciliation.csv`, `final_audit_decision.csv` —
  final-certification deliverables, written once the rerun decision is
  executed.

## Running

Each script is standalone (`python3 <script>.py`), reads directly from
the original Phase 3/4 result directories under
`/Users/matt/MT5-MSZZ-TEST/D029_Phase{3,4}_Results/`, and writes its CSV
output into this directory. None of these scripts execute trades or touch
MT5 — they are pure offline analysis of already-collected CSV evidence.
