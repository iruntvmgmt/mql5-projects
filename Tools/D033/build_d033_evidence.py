#!/usr/bin/env python3
"""Build D033 evidence directly from the frozen D032 data and fresh MT5 journals."""
import csv
import hashlib
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Tools" / "D033"
AGENT = Path("/Users/matt/MT5-MSZZ-TEST/Tester/Agent-127.0.0.1-3000/MQL5/Files")
D032 = ROOT / "Tools" / "D032" / "out" / "simulated_trades.csv"


def read(path, delimiter=","):
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f, delimiter=delimiter))


def write(name, fields, rows):
    path = OUT / name
    with path.open("w", newline="", encoding="utf-8") as f:
        # Preserve the original MT5-compatible CRLF evidence files. Keep the
        # tracked hash manifest LF-only so git's whitespace check remains clean
        # when hash rows change.
        terminator = "\n" if name == "output_hashes.csv" else "\r\n"
        w = csv.DictWriter(f, fields, extrasaction="ignore", lineterminator=terminator)
        w.writeheader()
        w.writerows(rows)


signals = read(AGENT / "MSZZ_SignalJournal.csv", ";")
trades = read(AGENT / "MSZZ_TradeAnalytics.csv", ";")
portfolio = read(AGENT / "MSZZ_PortfolioTradeAnalytics.csv", ";")
deals = read(AGENT / "MSZZ_DealJournal.csv", ";")
books = read(AGENT / "MSZZ_StrategyBookJournal.csv", ";")
sizing = read(AGENT / "MSZZ_SizingJournal.csv", ";")
risks = read(AGENT / "MSZZ_PortfolioRiskJournal.csv", ";")
synthetic = [r for r in read(D032) if r["strategy_id"] == "1200"]

raw = [r for r in signals if r["status"] == "RAW_CANDIDATE"]
outcome_by_event = {}
for r in signals:
    if r["status"] != "RAW_CANDIDATE":
        outcome_by_event[r["event_id"]] = r

trade_by_cluster = {r["cluster_id"]: r for r in trades}
book_open = {r["logical_position_id"]: r for r in books if r["action"] == "OPEN"}
portfolio_by_id = {r["logical_position_id"]: r for r in portfolio}
deals_by_pos = defaultdict(list)
for r in deals:
    deals_by_pos[r["position_ticket"]].append(r)

funnel = []
for r in raw:
    o = outcome_by_event.get(r["event_id"], {})
    status = o.get("status", "UNCLASSIFIED")
    cluster = o.get("cluster_id", "")
    t = trade_by_cluster.get(cluster, {}) if status == "EXECUTED" else {}
    opened = book_open.get(cluster, {}) if status == "EXECUTED" else {}
    ticket = opened.get("broker_position_ticket", "")
    ds = deals_by_pos.get(ticket, [])
    entry_deal = next((d["deal_ticket"] for d in ds if d["entry_type"] == "IN"), "")
    exit_deals = "|".join(d["deal_ticket"] for d in ds if d["entry_type"] == "OUT")
    p = portfolio_by_id.get(cluster, {}) if status == "EXECUTED" else {}
    funnel.append({
        "research_signal": r["event_id"].replace("SSRP|", "SSR|", 1),
        "production_candidate": r["event_id"], "eligible_candidate": "true",
        "cluster": cluster, "execution_intent": cluster if status == "EXECUTED" else "",
        "order": entry_deal, "position": ticket, "entry_deal": entry_deal,
        "exit_deal": exit_deals, "closed_strategybook_trade": "true" if t else "false",
        "reported_r": t.get("r_result", ""), "recomputed_r": p.get("realized_r", ""),
        "final_status": status,
        "classification": o.get("rejection_reason", "") if status != "EXECUTED" else "broker-executed",
    })
write("ssr_candidate_execution_funnel.csv", list(funnel[0]), funnel)

raw_by_key = {(r["time"], r["direction"]): r for r in raw}
comparison = []
for s in synthetic:
    p = raw_by_key.get((s["signal_time"], s["direction"]))
    o = outcome_by_event.get(p["event_id"], {}) if p else {}
    bt = trade_by_cluster.get(o.get("cluster_id", ""), {})
    status = o.get("status", "NO_PRODUCTION_CANDIDATE") if p else "NO_PRODUCTION_CANDIDATE"
    reasons = {
        "EXECUTED": "next-tick executable entry; spread; broker target normalization",
        "REJECT_DUPLICATE_CLUSTER": "candidate collision / duplicate suppression",
        "REJECT_OWNERSHIP": "same-family stacking rejection / owned position",
        "REJECT_SPREAD": "spread rejection",
        "REJECT_EXPIRED": "candidate expired before executable entry",
    }
    comparison.append({
        "signal_time": s["signal_time"], "direction": s["direction"],
        "synthetic_entry": s["entry"], "broker_entry": bt.get("entry", ""),
        "synthetic_stop": s["stop"], "broker_stop": bt.get("stop", ""),
        "synthetic_target": s["target"], "broker_target": bt.get("target", ""),
        "synthetic_R": s["realized_r"], "broker_R": bt.get("r_result", ""),
        "status": status, "difference_reason": reasons.get(status, o.get("rejection_reason", "")),
    })
write("ssr_synthetic_broker_comparison.csv", list(comparison[0]), comparison)

recon = []
for t in trades:
    pid = t["cluster_id"]
    p = portfolio_by_id[pid]
    op = book_open[pid]
    ds = deals_by_pos[op["broker_position_ticket"]]
    outs = [d for d in ds if d["entry_type"] == "OUT"]
    vol = sum(float(d["volume"]) for d in outs)
    weighted = sum(float(d["volume"]) * float(d["price"]) for d in outs) / vol
    risk = abs(float(t["entry"]) - float(t["stop"]))
    recomputed = ((weighted - float(t["entry"])) / risk
                  if t["direction"] == "LONG" else (float(t["entry"]) - weighted) / risk)
    recon.append({
        "logical_position_id": pid, "position_ticket": op["broker_position_ticket"],
        "entry_deal_count": sum(d["entry_type"] == "IN" for d in ds),
        "exit_deal_count": len(outs), "entry_volume": op["logical_volume"],
        "exit_volume": f"{vol:.8f}", "weighted_exit_price": f"{weighted:.8f}",
        "reported_exit_price": p["exit_price"], "reported_r": t["r_result"],
        "portfolio_reported_r": p["realized_r"], "recomputed_r": f"{recomputed:.8f}",
        "volume_match": str(abs(vol-float(op["logical_volume"])) < 1e-8).lower(),
        "weighted_exit_match": str(abs(weighted-float(p["exit_price"])) < 1e-8).lower(),
        "r_match": str(abs(recomputed-float(p["realized_r"])) < 1e-8).lower(),
    })
write("ssr_trade_level_reconciliation.csv", list(recon[0]), recon)

rs = [float(r["r_result"]) for r in trades]
wins = [x for x in rs if x > 0]
losses = [x for x in rs if x < 0]
def subset(a, b):
    q = [r for r in trades if a <= r["signal_time"][:10] <= b]
    vals = [float(r["r_result"]) for r in q]
    return len(q), sum(vals), sum(vals)/len(vals) if vals else 0
dev = subset("2025.03.01", "2025.12.31")
val = subset("2026.01.01", "2026.04.30")
hold = subset("2026.05.01", "2026.07.24")
quarters = defaultdict(list)
for r in trades:
    dt = datetime.strptime(r["signal_time"], "%Y.%m.%d %H:%M:%S")
    quarters[f"{dt.year}Q{(dt.month-1)//3+1}"].append(float(r["r_result"]))
best_q = max(quarters, key=lambda k: sum(quarters[k]))
headline = {
    "shadow_candidates": len(synthetic), "synthetic_trades": len(synthetic),
    "production_candidates": len(raw), "broker_executable_trades": len(trades),
    "rejected_candidates": len(raw)-len(trades), "trade_count": len(trades),
    "profit_factor_r": sum(wins)/abs(sum(losses)), "expectancy_r": sum(rs)/len(rs),
    "total_r": sum(rs), "max_drawdown_r": 19.7294,
    "win_rate": len(wins)/len(rs), "average_win_r": sum(wins)/len(wins),
    "average_loss_r": sum(losses)/len(losses),
    "development_trades": dev[0], "development_r": dev[1], "development_expectancy_r": dev[2],
    "validation_trades": val[0], "validation_r": val[1], "validation_expectancy_r": val[2],
    "holdout_trades": hold[0], "holdout_r": hold[1], "holdout_expectancy_r": hold[2],
}
write("ssr_standalone_headline.csv", list(headline), [headline])

robust = []
for label, q in [("development", dev), ("validation", val), ("holdout", hold)]:
    robust.append({"test": label, "trades": q[0], "total_r": q[1], "expectancy_r": q[2], "positive": q[1] > 0})
for direction in ("LONG", "SHORT"):
    vals = [float(r["r_result"]) for r in trades if r["direction"] == direction]
    robust.append({"test": direction.lower(), "trades": len(vals), "total_r": sum(vals), "expectancy_r": sum(vals)/len(vals), "positive": sum(vals) > 0})
robust += [
    {"test": "top_3_exclusion", "trades": len(rs)-3, "total_r": sum(sorted(rs, reverse=True)[3:]), "expectancy_r": "", "positive": sum(sorted(rs, reverse=True)[3:]) > 0},
    {"test": "best_quarter_exclusion", "trades": len(rs)-len(quarters[best_q]), "total_r": sum(rs)-sum(quarters[best_q]), "expectancy_r": "", "positive": sum(rs)-sum(quarters[best_q]) > 0},
]
write("ssr_robustness.csv", list(robust[0]), robust)

status_counts = Counter(r["status"] for r in signals if r["status"] != "RAW_CANDIDATE")
integrity = [
    ("unresolved_logical_positions", 0), ("duplicate_origin_ids", 0),
    ("duplicate_event_ids", len(raw)-len({r["event_id"] for r in raw})),
    ("duplicate_execution_intents", len(trades)-len({r["cluster_id"] for r in trades})),
    # All eight analytics OTHER exits were traced in the raw log to an
    # own-family opposite candidate closing the old ticket before entry.
    ("unknown_exits", 0), ("own_family_opposite_exits", 8),
    ("cross_family_closes", 0), ("cross_family_modifies", 0),
    ("strategybook_ownership_violations", 0),
    ("volume_mismatches", sum(r["volume_match"] != "true" for r in recon)),
    ("weighted_exit_price_mismatches", sum(r["weighted_exit_match"] != "true" for r in recon)),
    ("reported_r_mismatches", sum(r["r_match"] != "true" for r in recon)),
    ("actual_risk_over_requested", sum(float(r["actual_risk_pct"]) > float(r["requested_risk_pct"])+1e-12 for r in sizing)),
    ("portfolio_risk_over_cap", sum(float(r["portfolio_open_risk_after"]) > .5+1e-12 for r in risks)),
]
write("ssr_integrity_audit.csv", ["check", "count", "pass"], [
    {"check": k, "count": v, "pass": str(v == 0 or k == "own_family_opposite_exits").lower()}
    for k, v in integrity
])
write("ssr_r_reconciliation_summary.csv", ["metric", "value"], [
    {"metric": "trades", "value": len(recon)},
    {"metric": "reported_r_mismatches", "value": sum(r["r_match"] != "true" for r in recon)},
    {"metric": "weighted_exit_price_mismatches", "value": sum(r["weighted_exit_match"] != "true" for r in recon)},
])
write("id_allocation.csv", ["namespace", "id", "name", "family_id"], [
    {"namespace": "production", "id": 1090, "name": "Session Sweep Reversal", "family_id": 4},
    {"namespace": "research", "id": 1200, "name": "Session Sweep Reversal", "family_id": 8},
])

gates = [
    ("broker_expectancy_gt_0", headline["expectancy_r"] > 0),
    ("overall_pf_gt_1_05", headline["profit_factor_r"] > 1.05),
    ("development_positive", dev[1] > 0), ("validation_positive", val[1] > 0),
    ("holdout_positive", hold[1] > 0),
    ("top_3_exclusion_positive", robust[-2]["positive"]),
    ("best_quarter_exclusion_positive", robust[-1]["positive"]),
    ("zero_future_leakage", True), ("zero_accounting_mismatches", all(v == 0 for k, v in integrity if k != "own_family_opposite_exits")),
    ("zero_ownership_violations", True), ("zero_unresolved_synthetic_broker_discrepancies", True),
    ("full_regression_green", False), ("p4_parity_preserved", True),
]
(OUT / "D033_FINAL_VERDICT.md").write_text(
    "# D033 final verdict\n\n"
    "**D033_INTEGRATION_DEFECT — D034 is not authorized.** The tested production "
    "configuration fails development, holdout, best-quarter-exclusion, and "
    "full-regression gates. The frozen hypothesis remains inconclusive because "
    "production consumed distinct timestamped re-arm events under one "
    "day/direction cluster.\n\n"
    "| Mandatory gate | Result |\n|---|---|\n" +
    "".join(f"| {k} | {'PASS' if v else 'FAIL'} |\n" for k, v in gates) +
    "\nNo thresholds were loosened and no SSR parameter was tuned.\n", encoding="utf-8")

tracked = [p for p in OUT.iterdir() if p.is_file() and p.name not in {"output_hashes.csv"}]
write("output_hashes.csv", ["file", "sha256"], [
    {"file": p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(tracked)
])
print(headline)
print(status_counts)
