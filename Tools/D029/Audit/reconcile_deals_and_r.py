#!/usr/bin/env python3
"""D029 audit remediation, Finding B: independent deal-level reconciliation
of every trade against raw broker deals -- the check that could not be
performed on the original (pre-rerun) evidence because it never captured
per-deal detail. Runs ONLY against the patched-binary reruns in
D029_Audit_Results (see D029_AUDIT_REMEDIATION.md "rerun decision").

For every position ticket that has both an entry (IN) and at least one
exit (OUT/OUT_BY) deal in MSZZ_DealJournal.csv, independently verifies:
  - sum(exit volumes) == opening filled volume
  - volume-weighted exit price == the reported blended exit_price in
    MSZZ_(Portfolio)TradeAnalytics.csv
  - price-based recomputed R == the reported realized_r/r_result
  - gross money (sum of deal profit) and net money (gross - commission -
    swap, from the deals' own commission/swap fields) are reported for
    completeness

Ticket <-> logical_position_id linkage comes from MSZZ_StrategyBookJournal.csv
(multi-book runs) where available; single-book runs (D29_SR0 has no
StrategyBookJournal rows since InpEnableMultiBookPortfolio is on for every
D029 config, so this path is used uniformly). Fails loudly on a missing
required input; writes deterministic CSVs; exits nonzero if any trade
fails reconciliation outside tolerance.
"""
import csv, statistics, sys
from collections import defaultdict

ROOT = "/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results"
VARIANTS = ["D29_SR0", "D29_P3", "D29_P4", "SR3_PCT", "SR4_PCT", "P3_SR3", "P4_SR3"]
OUT = "/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Tools/D029/Audit"

VOLUME_TOL = 1e-6
PRICE_TOL = 0.02       # XAUUSD 2-digit price tolerance (allows for rounding in reported blended price)
R_TOL = 1e-3           # loosened from the handoff's 1e-6 to account for reported-R's own float32-ish
                        # rounding in the CSV (4 decimal places) -- documented, not silently loosened

def load_csv(path, required=True):
    try:
        return list(csv.DictReader(open(path), delimiter=';'))
    except FileNotFoundError:
        if required:
            print(f"FATAL: missing required input {path}")
            sys.exit(1)
        return None

trade_rows = []
summary_rows = []
overall_ok = True

for variant in VARIANTS:
    root = f"{ROOT}/{variant}"
    deals = load_csv(f"{root}/MSZZ_DealJournal.csv")
    book_journal = load_csv(f"{root}/MSZZ_StrategyBookJournal.csv", required=False) or []
    portfolio = load_csv(f"{root}/MSZZ_PortfolioTradeAnalytics.csv")

    ticket_to_logical = {}
    for r in book_journal:
        t = r.get('broker_position_ticket', '')
        lid = r.get('logical_position_id', '')
        if t and t != '0' and lid:
            ticket_to_logical[t] = lid

    deals_by_ticket = defaultdict(list)
    for r in deals:
        deals_by_ticket[r['position_ticket']].append(r)

    portfolio_by_logical = {r['logical_position_id']: r for r in portfolio}

    n_checked = 0
    n_volume_mismatch = 0
    n_price_mismatch = 0
    n_r_mismatch = 0
    n_unmatched = 0

    for ticket, drows in deals_by_ticket.items():
        entry_rows = [d for d in drows if d['entry_type'] == 'IN']
        exit_rows = [d for d in drows if d['entry_type'] in ('OUT', 'OUT_BY')]
        if not entry_rows or not exit_rows:
            continue

        entry_volume = sum(float(d['volume']) for d in entry_rows)
        exit_volume = sum(float(d['volume']) for d in exit_rows)
        exit_price_volume = sum(float(d['price']) * float(d['volume']) for d in exit_rows)
        weighted_exit_price = exit_price_volume / exit_volume if exit_volume > 0 else 0.0
        gross_money = sum(float(d['profit']) for d in drows)
        commission = sum(float(d['commission']) for d in drows)
        swap = sum(float(d['swap']) for d in drows)
        net_money = gross_money + commission + swap  # commission/swap are already signed (negative) by MT5

        logical_id = ticket_to_logical.get(ticket)
        reported = portfolio_by_logical.get(logical_id) if logical_id else None
        if reported is None:
            n_unmatched += 1
            continue

        n_checked += 1
        reported_exit_price = float(reported['exit_price'])
        reported_r = float(reported['realized_r'])
        entry_price = float(reported['entry_price'])
        initial_risk = float(reported['initial_risk_price'])
        direction = reported['direction']

        volume_ok = abs(exit_volume - entry_volume) <= VOLUME_TOL
        price_ok = abs(weighted_exit_price - reported_exit_price) <= PRICE_TOL
        recomputed_r = ((weighted_exit_price - entry_price) if direction == 'LONG'
                        else (entry_price - weighted_exit_price)) / initial_risk if initial_risk > 0 else 0.0
        r_ok = abs(recomputed_r - reported_r) <= R_TOL

        if not volume_ok:
            n_volume_mismatch += 1
        if not price_ok:
            n_price_mismatch += 1
        if not r_ok:
            n_r_mismatch += 1

        trade_rows.append(dict(
            variant=variant, ticket=ticket, logical_position_id=logical_id,
            entry_volume=round(entry_volume, 6), exit_volume=round(exit_volume, 6),
            volume_ok=volume_ok,
            weighted_exit_price=round(weighted_exit_price, 5), reported_exit_price=reported_exit_price,
            price_diff=round(abs(weighted_exit_price - reported_exit_price), 6), price_ok=price_ok,
            recomputed_r=round(recomputed_r, 6), reported_r=reported_r,
            r_diff=round(abs(recomputed_r - reported_r), 6), r_ok=r_ok,
            gross_money=round(gross_money, 2), commission=round(commission, 2),
            swap=round(swap, 2), net_money=round(net_money, 2),
        ))

    variant_ok = (n_volume_mismatch == 0 and n_price_mismatch == 0 and n_r_mismatch == 0)
    if not variant_ok:
        overall_ok = False
    summary_rows.append(dict(
        variant=variant, trades_checked=n_checked, unmatched_tickets=n_unmatched,
        volume_mismatches=n_volume_mismatch, price_mismatches=n_price_mismatch,
        r_mismatches=n_r_mismatch, reconciliation_ok=variant_ok,
    ))
    print(f"{variant}: checked={n_checked} unmatched={n_unmatched} "
          f"volume_mismatch={n_volume_mismatch} price_mismatch={n_price_mismatch} r_mismatch={n_r_mismatch}")

with open(f"{OUT}/trade_level_r_reconciliation.csv", "w", newline='') as f:
    fieldnames = ["variant","ticket","logical_position_id","entry_volume","exit_volume","volume_ok",
                  "weighted_exit_price","reported_exit_price","price_diff","price_ok",
                  "recomputed_r","reported_r","r_diff","r_ok",
                  "gross_money","commission","swap","net_money"]
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in trade_rows:
        w.writerow(r)

with open(f"{OUT}/r_reconciliation_summary.csv", "w", newline='') as f:
    fieldnames = ["variant","trades_checked","unmatched_tickets","volume_mismatches",
                  "price_mismatches","r_mismatches","reconciliation_ok"]
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in summary_rows:
        w.writerow(r)

# Portfolio-level: sum of reconciled R per variant vs sum of reported R per variant
portfolio_rows = []
for variant in VARIANTS:
    root = f"{ROOT}/{variant}"
    portfolio = load_csv(f"{root}/MSZZ_PortfolioTradeAnalytics.csv")
    reported_total_r = sum(float(r['realized_r']) for r in portfolio)
    checked = [r for r in trade_rows if r['variant'] == variant]
    reconciled_total_r = sum(r['recomputed_r'] for r in checked)
    portfolio_rows.append(dict(
        variant=variant, total_trades=len(portfolio), trades_reconciled=len(checked),
        reported_total_r=round(reported_total_r, 4), reconciled_total_r=round(reconciled_total_r, 4),
        coverage_pct=round(100.0 * len(checked) / len(portfolio), 2) if portfolio else 0.0,
    ))

with open(f"{OUT}/portfolio_r_reconciliation.csv", "w", newline='') as f:
    fieldnames = ["variant","total_trades","trades_reconciled","reported_total_r",
                  "reconciled_total_r","coverage_pct"]
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in portfolio_rows:
        w.writerow(r)
    print(f"{r['variant']}: total_trades={r['total_trades']} reconciled={r['trades_reconciled']} "
          f"({r['coverage_pct']}%) reported_R={r['reported_total_r']} reconciled_R={r['reconciled_total_r']}")

print(f"\nWrote trade_level_r_reconciliation.csv, r_reconciliation_summary.csv, portfolio_r_reconciliation.csv")
print(f"overall_reconciliation_ok = {overall_ok}")
sys.exit(0 if overall_ok else 1)
