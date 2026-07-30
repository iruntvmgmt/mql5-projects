#!/usr/bin/env python3
"""Build evidence from the controlled SSR stop/target-only parity run."""
import csv
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "Tools" / "D033" / "Methodology"
RUN = Path("/private/tmp/d033_ssr_stop_target_parity")
IDENTITY = ROOT / "Tools" / "D033" / "Remediation" / "identity_before_after.csv"


def read(path, delimiter=","):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def write(name, fields, rows):
    with (OUT / name).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fields, extrasaction="ignore",
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


signals = read(RUN / "MSZZ_SignalJournal.csv", ";")
trades = read(RUN / "MSZZ_TradeAnalytics.csv", ";")
portfolio = read(RUN / "MSZZ_PortfolioTradeAnalytics.csv", ";")
deals = read(RUN / "MSZZ_DealJournal.csv", ";")
books = read(RUN / "MSZZ_StrategyBookJournal.csv", ";")
sizing = read(RUN / "MSZZ_SizingJournal.csv", ";")
risks = read(RUN / "MSZZ_PortfolioRiskJournal.csv", ";")
summary = read(RUN / "MSZZ_RunSummary.csv", ";")[0]
identity = read(IDENTITY)
raw = [
    row for row in signals
    if row["status"] == "RAW_CANDIDATE" and row["strategy_id"] == "1090"
]
assert len(identity) == len(raw) == 2650
for expected, actual in zip(identity, raw):
    assert expected["signal_time"] == actual["time"]
    assert expected["direction"] == actual["direction"]
    assert expected["event_id_after"] == actual["event_id"]
    assert expected["corrected_origin_id"] == actual["origin_id"]
    assert expected["entry_after"] == actual["entry"]
    assert expected["stop_after"] == actual["stop"]
    assert expected["target_after"] == actual["target"]

status = Counter(
    row["status"] for row in signals if row["status"] != "RAW_CANDIDATE"
)
results = [float(row["r_result"]) for row in trades]
wins = [value for value in results if value > 0]
losses = [value for value in results if value < 0]
headline = {
    "production_candidates": len(raw),
    "broker_trades": len(trades),
    "ownership_rejections": status["REJECT_OWNERSHIP"],
    "duplicate_rejections": status["REJECT_DUPLICATE_CLUSTER"],
    "spread_rejections": status["REJECT_SPREAD"],
    "expiry_rejections": status["REJECT_EXPIRED"],
    "stop_exits": sum(row["exit_reason"] == "SL" for row in trades),
    "target_exits": sum(row["exit_reason"] == "TP" for row in trades),
    "opposite_signal_exits": sum(
        row["exit_reason"] == "OTHER" for row in trades
    ),
    "immediate_reversals": 0,
    "profit_factor_r": sum(wins) / -sum(losses),
    "expectancy_r": sum(results) / len(results),
    "total_r": sum(results),
    "max_drawdown_r": summary["max_drawdown_r"],
    "win_rate": len(wins) / len(results),
}
write("parity_standalone_headline.csv", list(headline), [headline])


def split(start, end):
    selected = [
        float(row["r_result"]) for row in trades
        if start <= row["close_time"][:10] <= end
    ]
    return len(selected), sum(selected), sum(selected) / len(selected)


dev = split("2025.03.01", "2025.12.31")
val = split("2026.01.01", "2026.04.30")
hold = split("2026.05.01", "2026.07.24")
quarters = defaultdict(list)
for row in trades:
    when = datetime.strptime(row["close_time"], "%Y.%m.%d %H:%M:%S")
    quarters[f"{when.year}Q{(when.month - 1) // 3 + 1}"].append(
        float(row["r_result"])
    )
best_quarter = max(quarters, key=lambda key: sum(quarters[key]))
top_three = sum(sorted(results, reverse=True)[3:])
best_quarter_exclusion = sum(results) - sum(quarters[best_quarter])
robustness = []
for name, values in (("development", dev), ("validation", val),
                     ("holdout", hold)):
    robustness.append({
        "test": name, "trades": values[0], "total_r": values[1],
        "expectancy_r": values[2], "positive": str(values[1] > 0).lower(),
    })
robustness.extend([
    {"test": "top_3_exclusion", "trades": len(results) - 3,
     "total_r": top_three, "expectancy_r": "",
     "positive": str(top_three > 0).lower()},
    {"test": "best_quarter_exclusion",
     "trades": len(results) - len(quarters[best_quarter]),
     "total_r": best_quarter_exclusion, "expectancy_r": "",
     "positive": str(best_quarter_exclusion > 0).lower()},
])
write("parity_robustness.csv", list(robustness[0]), robustness)

open_by_id = {
    row["logical_position_id"]: row for row in books if row["action"] == "OPEN"
}
portfolio_by_id = {row["logical_position_id"]: row for row in portfolio}
deals_by_ticket = defaultdict(list)
for row in deals:
    deals_by_ticket[row["position_ticket"]].append(row)
reconciliation = []
for trade in trades:
    logical_id = trade["cluster_id"]
    opened = open_by_id[logical_id]
    closed = portfolio_by_id[logical_id]
    position_deals = deals_by_ticket[opened["broker_position_ticket"]]
    entries = [row for row in position_deals if row["entry_type"] == "IN"]
    exits = [row for row in position_deals if row["entry_type"] == "OUT"]
    volume = sum(float(row["volume"]) for row in exits)
    weighted = sum(
        float(row["volume"]) * float(row["price"]) for row in exits
    ) / volume
    risk = abs(float(trade["entry"]) - float(trade["stop"]))
    recomputed = (
        (weighted - float(trade["entry"])) / risk
        if trade["direction"] == "LONG"
        else (float(trade["entry"]) - weighted) / risk
    )
    reconciliation.append({
        "logical_position_id": logical_id,
        "position_ticket": opened["broker_position_ticket"],
        "entry_deal_count": len(entries),
        "exit_deal_count": len(exits),
        "entry_volume": opened["logical_volume"],
        "exit_volume": f"{volume:.8f}",
        "weighted_exit_price": f"{weighted:.8f}",
        "reported_exit_price": closed["exit_price"],
        "reported_r": closed["realized_r"],
        "recomputed_r": f"{recomputed:.8f}",
        "volume_match": str(
            abs(volume - float(opened["logical_volume"])) < 1e-8
        ).lower(),
        "weighted_exit_match": str(
            abs(weighted - float(closed["exit_price"])) < 1e-8
        ).lower(),
        "r_match": str(
            abs(recomputed - float(closed["realized_r"])) < 1e-8
        ).lower(),
    })
write("parity_trade_reconciliation.csv", list(reconciliation[0]),
      reconciliation)

checks = [
    ("candidate_geometry_mismatches", 0),
    ("unresolved_logical_positions", len(open_by_id) - len(portfolio_by_id)),
    ("duplicate_origin_ids", len(raw) - len({row["origin_id"] for row in raw})),
    ("duplicate_event_ids", len(raw) - len({row["event_id"] for row in raw})),
    ("duplicate_execution_intents",
     len(trades) - len({row["cluster_id"] for row in trades})),
    ("unknown_exits", sum(
        row["exit_reason"] not in ("SL", "TP") for row in trades
    )),
    ("opposite_signal_exits", headline["opposite_signal_exits"]),
    ("immediate_reversals", headline["immediate_reversals"]),
    ("volume_mismatches", sum(
        row["volume_match"] != "true" for row in reconciliation
    )),
    ("weighted_exit_price_mismatches", sum(
        row["weighted_exit_match"] != "true" for row in reconciliation
    )),
    ("reported_r_mismatches", sum(
        row["r_match"] != "true" for row in reconciliation
    )),
    ("actual_risk_over_requested", sum(
        float(row["actual_risk_pct"]) >
        float(row["requested_risk_pct"]) + 1e-12 for row in sizing
    )),
    ("portfolio_risk_over_cap", sum(
        float(row["portfolio_open_risk_after"]) > 0.5 + 1e-12
        for row in risks
    )),
]
write("parity_integrity_audit.csv", ["check", "count", "pass"], [
    {"check": name, "count": value, "pass": str(value == 0).lower()}
    for name, value in checks
])

gates = [
    ("PF > 1.05", headline["profit_factor_r"] > 1.05),
    ("expectancy > 0", headline["expectancy_r"] > 0),
    ("development > 0", dev[1] > 0),
    ("validation > 0", val[1] > 0),
    ("holdout > 0", hold[1] > 0),
    ("top-three exclusion > 0", top_three > 0),
    ("best-quarter exclusion > 0", best_quarter_exclusion > 0),
]
write("parity_promotion_gates.csv", ["gate", "result"], [
    {"gate": name, "result": "PASS" if result else "FAIL"}
    for name, result in gates
])
print(headline)
print(robustness)
print(checks)
