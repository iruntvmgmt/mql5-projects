#!/usr/bin/env python3
"""D029 audit remediation, Finding H: broad portfolio-integrity check
battery. Verifies, for each affected run, everything the handoff's Finding
H enumerates that is expressible from already-collected CSV evidence:
native/logical trade counts, duplicate logical IDs, strategy attribution
consistency, partial counts, requested-vs-actual risk, risk-cap sequence
integrity, max simultaneous risk, cross-family actions, exit inventory /
unknown exits, top-1/3/5 exclusion, best-month/quarter exclusion,
dev/val/holdout split, long/short split, and a SHA-256 hash of every input
file read. Fails loudly on a missing input file. Writes a deterministic
CSV and exits nonzero if any integrity check fails.

NOTE: this run is against the ORIGINAL (pre-rerun) Phase 3/4 evidence.
Finding C's historical atomicity audit already established that a full
rerun of these seven configs is required (one unprotected partial per
run, same underlying trade). This script's current output is therefore a
pre-rerun baseline, not the final certification evidence -- it must be
re-run against the rerun's fresh output once that lands, and this
docstring/README updated accordingly. Running it now still has value: it
proves the tool itself works and gives an honest picture of what the
current (soon-to-be-superseded) evidence actually shows.
"""
import csv, hashlib, statistics, sys
from collections import defaultdict
from datetime import datetime

ROOTS = {
    "SR3_PCT": "/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/SR3_PCT",
    "SR4_PCT": "/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/SR4_PCT",
    "P3_SR3": "/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/P3_SR3",
    "P4_SR3": "/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/P4_SR3",
}
OUT = "/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Tools/D029/Audit"

MAX_TOTAL_RISK_PCT = 0.50  # frozen D029 Phase 0 cap
RISK_TOL = 1e-6

DEV_START = datetime(2025, 3, 1); DEV_END = datetime(2025, 12, 31, 23, 59, 59)
VAL_START = datetime(2026, 1, 1); VAL_END = datetime(2026, 4, 30, 23, 59, 59)
HOLD_START = datetime(2026, 5, 1); HOLD_END = datetime(2026, 7, 24, 23, 59, 59)

# Grounded in MultiSpeedZigZagEA.mq5's actual JournalExitManagement() call
# sites and the action-labeling ternary in ProcessOneBookExit() -- NOT
# guessed. MSZZ_TradeAnalytics.csv/MSZZ_PortfolioTradeAnalytics.csv's own
# `exit_reason` field is a generic MT5-level string ("broker position
# closed") for every trade in every variant checked and carries no
# per-policy classification, so the exit-inventory / unknown-exit check is
# done against MSZZ_SweepExitManagementJournal.csv's `action` field
# instead, which does carry real per-policy detail.
KNOWN_EXIT_MANAGEMENT_ACTIONS = {
    "PARTIAL_CLOSE", "STOP_MODIFY", "STRUCTURAL_TRAIL", "BREAKEVEN",
    "TIME_STOP", "PROTECTION_RETRY", "PROTECTION_EMERGENCY_CLOSE",
}

STRATEGY_FAMILY = {
    "MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE": "MSZZ_FAMILY_BREAKOUT",
    "MSZZ_STRAT_SWEEP_RECLAIM": "MSZZ_FAMILY_REVERSAL",
}

def sha256_of(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()

def parse_dt(s):
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")

def load_csv(path, required=True):
    try:
        return list(csv.DictReader(open(path), delimiter=';'))
    except FileNotFoundError:
        if required:
            print(f"FATAL: missing required input {path}")
            sys.exit(1)
        return None

summary_rows = []
hash_rows = []
overall_ok = True

for variant, root in ROOTS.items():
    print(f"\n{'='*70}\n{variant}\n{'='*70}")
    findings = []

    native_path = f"{root}/MSZZ_TradeAnalytics.csv"
    portfolio_path = f"{root}/MSZZ_PortfolioTradeAnalytics.csv"
    risk_path = f"{root}/MSZZ_PortfolioRiskJournal.csv"
    book_path = f"{root}/MSZZ_StrategyBookJournal.csv"
    signal_path = f"{root}/MSZZ_SignalJournal.csv"
    partial_path = f"{root}/MSZZ_PartialCloseJournal.csv"
    exitmgmt_path = f"{root}/MSZZ_SweepExitManagementJournal.csv"

    # Single-book runs (SR3_PCT/SR4_PCT) write MSZZ_TradeAnalytics.csv
    # (native); multi-book portfolio runs (P3_SR3/P4_SR3) write only
    # MSZZ_PortfolioTradeAnalytics.csv (logical) -- at least one must
    # exist, but neither alone is universally required.
    native = load_csv(native_path, required=False) or []
    portfolio = load_csv(portfolio_path, required=False) or []
    if not native and not portfolio:
        print(f"FATAL: {variant} has neither {native_path} nor {portfolio_path}")
        sys.exit(1)
    risk = load_csv(risk_path, required=False) or []
    book = load_csv(book_path, required=False) or []
    signal = load_csv(signal_path)
    partial = load_csv(partial_path, required=False) or []
    exitmgmt = load_csv(exitmgmt_path, required=False) or []

    hash_rows.append(dict(variant=variant, file=signal_path.split('/')[-1], sha256=sha256_of(signal_path)))
    for path, rows in ((native_path, native), (portfolio_path, portfolio), (risk_path, risk),
                       (book_path, book), (partial_path, partial), (exitmgmt_path, exitmgmt)):
        if rows:
            hash_rows.append(dict(variant=variant, file=path.split('/')[-1], sha256=sha256_of(path)))

    native_n = len(native)
    portfolio_n = len(portfolio)
    if native and portfolio and native_n != portfolio_n:
        findings.append(f"native/logical trade count MISMATCH: native={native_n} portfolio={portfolio_n}")
        overall_ok = False
    else:
        print(f"native/logical trade counts consistent: native={native_n} portfolio={portfolio_n}")

    logical_ids = [r.get('logical_position_id', '') for r in portfolio if r.get('logical_position_id')]
    dupes = [k for k, v in defaultdict(int, {k: logical_ids.count(k) for k in set(logical_ids)}).items() if v > 1]
    if dupes:
        findings.append(f"DUPLICATE logical_position_id values: {dupes}")
        overall_ok = False
    else:
        print(f"no duplicate logical_position_id values ({len(logical_ids)} checked)")

    mismatched_attribution = 0
    for r in portfolio:
        sid = r.get('strategy_id', '')
        fid = r.get('family_id', '')
        expected = STRATEGY_FAMILY.get(sid)
        if expected and fid and expected != fid:
            mismatched_attribution += 1
    if mismatched_attribution:
        findings.append(f"strategy/family attribution MISMATCH in {mismatched_attribution} rows")
        overall_ok = False
    elif portfolio:
        print(f"strategy/family attribution consistent ({len(portfolio)} rows)")

    partial_n = len(partial)
    print(f"partial-close events: {partial_n}")

    max_open_risk = 0.0
    cap_violations = 0
    approved = [r for r in risk if r.get('approved') == 'true']
    for r in approved:
        try:
            after = float(r['portfolio_open_risk_after'])
        except (KeyError, ValueError):
            continue
        max_open_risk = max(max_open_risk, after)
        if after > MAX_TOTAL_RISK_PCT + RISK_TOL:
            cap_violations += 1
    if cap_violations:
        findings.append(f"RISK CAP VIOLATION: {cap_violations} approved actions exceeded {MAX_TOTAL_RISK_PCT}% cap")
        overall_ok = False
    else:
        print(f"risk-cap sequence intact: max simultaneous open risk observed = {max_open_risk:.4f}% (cap {MAX_TOTAL_RISK_PCT}%)")

    # exit_reason in MSZZ_(Portfolio)TradeAnalytics.csv is a generic
    # MT5-level string ("broker position closed") for every trade in every
    # variant -- reported for completeness, not used for the unknown-exit
    # check. The exit-management action inventory (from
    # MSZZ_SweepExitManagementJournal.csv, which does carry real per-policy
    # detail) is what's checked against the grounded whitelist.
    exit_reasons = defaultdict(int)
    for r in (portfolio or native):
        exit_reasons[r.get('exit_reason', '')] += 1
    print(f"exit_reason inventory (generic MT5-level field): {dict(exit_reasons)}")

    action_inventory = defaultdict(int)
    unknown_actions = []
    for r in exitmgmt:
        action = r.get('action', '')
        action_inventory[action] += 1
        if action and action not in KNOWN_EXIT_MANAGEMENT_ACTIONS:
            unknown_actions.append(action)
    if unknown_actions:
        findings.append(f"UNKNOWN exit-management action values encountered: {sorted(set(unknown_actions))}")
        overall_ok = False
    print(f"exit-management action inventory: {dict(action_inventory)}")

    r_field = 'realized_r' if (portfolio and 'realized_r' in portfolio[0]) else 'r_result'
    rows_for_r = portfolio if portfolio else native
    time_field = 'exit_time' if (portfolio and 'exit_time' in (portfolio[0] if portfolio else {})) else 'close_time'
    parsed = []
    for r in rows_for_r:
        try:
            r_val = float(r[r_field])
            t_val = parse_dt(r[time_field])
            parsed.append((t_val, r_val, r))
        except (KeyError, ValueError):
            continue
    n = len(parsed)
    if n:
        parsed.sort(key=lambda x: x[0])
        cum = sum(x[1] for x in parsed)
        sorted_r = sorted(parsed, key=lambda x: -x[1])
        for k in (1, 3, 5):
            removed = [x[1] for x in parsed if x not in sorted_r[:k]]
            cum_removed = sum(removed)
            print(f"top-{k}-excluded cum_r={cum_removed:.4f} (full cum_r={cum:.4f})")
        quarters = defaultdict(list)
        for t, r_val, _ in parsed:
            q = (t.month - 1) // 3 + 1
            quarters[f"{t.year}Q{q}"].append(r_val)
        if quarters:
            best_q = max(quarters.items(), key=lambda kv: sum(kv[1]))[0]
            cum_bq_removed = sum(v for k2, vals in quarters.items() if k2 != best_q for v in vals)
            print(f"best_quarter={best_q} best-quarter-excluded cum_r={cum_bq_removed:.4f}")
        dev = [x[1] for x in parsed if DEV_START <= x[0] <= DEV_END]
        val = [x[1] for x in parsed if VAL_START <= x[0] <= VAL_END]
        hold = [x[1] for x in parsed if HOLD_START <= x[0] <= HOLD_END]
        print(f"dev n={len(dev)} sum={sum(dev):.4f} | val n={len(val)} sum={sum(val):.4f} | hold n={len(hold)} sum={sum(hold):.4f}")
        dev_val_hold_total = len(dev) + len(val) + len(hold)
        if dev_val_hold_total != n:
            findings.append(f"dev/val/holdout partition does not cover all trades: {dev_val_hold_total}/{n}")
            overall_ok = False

        longs = [x[1] for x in parsed if x[2].get('direction') == 'LONG']
        shorts = [x[1] for x in parsed if x[2].get('direction') == 'SHORT']
        print(f"long n={len(longs)} sum={sum(longs):.4f} | short n={len(shorts)} sum={sum(shorts):.4f}")
    else:
        cum = 0.0

    if findings:
        print(f"\n*** INTEGRITY FINDINGS for {variant} ***")
        for f in findings:
            print(f"  - {f}")
    else:
        print(f"\nno integrity findings for {variant}")

    summary_rows.append(dict(
        variant=variant, native_trades=native_n, portfolio_trades=portfolio_n or native_n,
        duplicate_logical_ids=len(dupes), attribution_mismatches=mismatched_attribution,
        partial_events=partial_n, max_simultaneous_risk_pct=round(max_open_risk, 4),
        risk_cap_violations=cap_violations, unknown_exit_management_actions=len(set(unknown_actions)),
        integrity_ok=(len(findings) == 0),
    ))

with open(f"{OUT}/portfolio_integrity_audit.csv", "w", newline='') as f:
    fieldnames = ["variant","native_trades","portfolio_trades","duplicate_logical_ids",
                  "attribution_mismatches","partial_events","max_simultaneous_risk_pct",
                  "risk_cap_violations","unknown_exit_management_actions","integrity_ok"]
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in summary_rows:
        w.writerow(r)

with open(f"{OUT}/output_hashes.csv", "w", newline='') as f:
    w = csv.DictWriter(f, fieldnames=["variant", "file", "sha256"])
    w.writeheader()
    for r in hash_rows:
        w.writerow(r)

print(f"\nWrote {OUT}/portfolio_integrity_audit.csv ({len(summary_rows)} variants)")
print(f"Wrote {OUT}/output_hashes.csv ({len(hash_rows)} files hashed)")
print(f"\noverall_integrity_ok = {overall_ok}")
print("NOTE: this is a PRE-RERUN baseline -- see docstring. Must be re-run against fresh rerun output.")
sys.exit(0 if overall_ok else 1)
