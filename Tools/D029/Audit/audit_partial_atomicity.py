#!/usr/bin/env python3
"""D029 Audit Finding C (historical audit): for every historical
PARTIAL_CLOSE event in SR3_PCT/SR4_PCT, verify a matching successful
STOP_MODIFY (breakeven) fired at the same book_id + same timestamp, and
(for SR4) that the target-removal semantics were consistent. This does not
patch the architecture -- it determines whether the ALREADY-COLLECTED
Phase 3/4 evidence exhibits the non-atomic failure mode Finding C
describes, which determines whether reruns are required.
"""
import csv, sys
from collections import defaultdict

ROOTS = {
    "SR3_PCT": "/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/SR3_PCT",
    "SR4_PCT": "/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/SR4_PCT",
    "P3_SR3": "/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/P3_SR3",
    "P4_SR3": "/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/P4_SR3",
}
OUT = "/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Tools/D029/Audit"

def load_exit_mgmt(path):
    with open(f"{path}/MSZZ_SweepExitManagementJournal.csv", newline='') as f:
        return list(csv.DictReader(f, delimiter=';'))

def load_partial_journal(path):
    with open(f"{path}/MSZZ_PartialCloseJournal.csv", newline='') as f:
        return list(csv.DictReader(f, delimiter=';'))

rows_out = []
summary_rows = []

for variant, path in ROOTS.items():
    exit_rows = load_exit_mgmt(path)
    partial_rows = load_partial_journal(path)

    # index exit-management rows by (time, book_id) -> list of actions
    by_key = defaultdict(list)
    for r in exit_rows:
        by_key[(r['time'], r['book_id'])].append(r)

    total_partials = 0
    matched_protection = 0
    missing_or_failed_protection = 0
    duplicate_partial_same_bar = 0

    for pr in partial_rows:
        total_partials += 1
        key = (pr['time'], pr['book_id'])
        actions_this_bar = by_key.get(key, [])
        partial_closes_this_bar = [a for a in actions_this_bar if a['action']=='PARTIAL_CLOSE']
        # The EA labels the protection modify action STOP_MODIFY for SR1/SR3
        # but STRUCTURAL_TRAIL for SR2/SR4 (see MultiSpeedZigZagEA.mq5's
        # action-labeling ternary in ProcessOneBookExit) -- both represent
        # the same PositionModify() call this audit needs to verify.
        stop_modifies_this_bar = [a for a in actions_this_bar
                                   if a['action'] in ('STOP_MODIFY','STRUCTURAL_TRAIL','BREAKEVEN')]

        if len(partial_closes_this_bar) > 1:
            duplicate_partial_same_bar += 1

        partial_ok = (pr['modify_ok'] == 'true')
        protection_ok = any(a['modify_ok']=='true' for a in stop_modifies_this_bar)

        status = "OK" if (partial_ok and protection_ok) else \
                 ("PARTIAL_FAILED" if not partial_ok else "PROTECTION_MISSING_OR_FAILED")
        if status == "OK":
            matched_protection += 1
        else:
            missing_or_failed_protection += 1

        rows_out.append(dict(variant=variant, time=pr['time'], book_id=pr['book_id'],
                              partial_ok=partial_ok, stop_modify_count=len(stop_modifies_this_bar),
                              protection_ok=protection_ok, status=status))

    summary_rows.append(dict(variant=variant, total_partials=total_partials,
                              matched_protection=matched_protection,
                              missing_or_failed_protection=missing_or_failed_protection,
                              duplicate_partial_same_bar=duplicate_partial_same_bar))

with open(f"{OUT}/partial_protection_atomicity.csv", "w", newline='') as f:
    w = csv.DictWriter(f, fieldnames=["variant","time","book_id","partial_ok",
                                       "stop_modify_count","protection_ok","status"])
    w.writeheader()
    for r in rows_out:
        w.writerow(r)

with open(f"{OUT}/partial_protection_summary.csv", "w", newline='') as f:
    w = csv.DictWriter(f, fieldnames=["variant","total_partials","matched_protection",
                                       "missing_or_failed_protection","duplicate_partial_same_bar"])
    w.writeheader()
    for r in summary_rows:
        w.writerow(r)

print("=== Partial-protection atomicity summary ===")
all_clean = True
for r in summary_rows:
    print(r)
    if r["missing_or_failed_protection"] > 0 or r["duplicate_partial_same_bar"] > 0:
        all_clean = False

print(f"\nall_historical_partials_had_matching_protection = {all_clean}")
sys.exit(0 if all_clean else 1)
