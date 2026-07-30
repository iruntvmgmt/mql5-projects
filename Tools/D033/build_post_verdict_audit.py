#!/usr/bin/env python3
"""Classify D033 duplicate-cluster rejections without changing SSR rules."""
import csv
from collections import defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Tools" / "D033"
AGENT = Path("/Users/matt/MT5-MSZZ-TEST/Tester/Agent-127.0.0.1-3000/MQL5/Files")


def read(path, delimiter=","):
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f, delimiter=delimiter))


def write(path, fields, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fields, extrasaction="ignore", lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


signals = read(AGENT / "MSZZ_SignalJournal.csv", ";")
trades = {r["cluster_id"]: r for r in read(AGENT / "MSZZ_TradeAnalytics.csv", ";")}
synthetic = {
    r["event_id"] for r in read(ROOT / "Tools/D032/out/simulated_trades.csv")
    if r["strategy_id"] == "1200"
}
clusters = defaultdict(list)
for r in signals:
    if r["status"] in ("EXECUTED", "REJECT_DUPLICATE_CLUSTER"):
        clusters[r["cluster_id"]].append(r)

parse = lambda value: datetime.strptime(value, "%Y.%m.%d %H:%M:%S")
rows = []
for r in (x for x in signals if x["status"] == "REJECT_DUPLICATE_CLUSTER"):
    first = clusters[r["cluster_id"]][0]
    trade = trades[r["cluster_id"]]
    research_event = r["event_id"].replace("SSRP|", "SSR|", 1)
    after_close = parse(r["time"]) > parse(trade["close_time"])
    d032_accepted = research_event in synthetic
    rows.append({
        "cluster_id": r["cluster_id"],
        "cluster_origin_id": r["origin_id"],
        "consumed_event_id": first["event_id"],
        "rejected_event_id": r["event_id"],
        "consumed_signal_time": first["time"],
        "rejected_signal_time": r["time"],
        "minutes_after_consumed_signal":
            int((parse(r["time"]) - parse(first["time"])).total_seconds() / 60),
        "first_trade_close_time": trade["close_time"],
        "after_first_trade_close": str(after_close).lower(),
        "d032_accepted_as_trade": str(d032_accepted).lower(),
        "exact_event_duplicate": str(r["event_id"] == first["event_id"]).lower(),
        "event_identity_class": "DISTINCT_TIMESTAMPED_REARM_EVENT",
        "execution_eligibility_class":
            ("D032_ACCEPTED_DISTINCT_TRADE" if d032_accepted else
             "D032_REJECTED_BY_SAME_FAMILY_STACKING"),
        "audit_verdict": "DISTINCT_SETUP_SUPPRESSION",
    })

write(OUT / "ssr_cluster_rejection_audit.csv", list(rows[0]), rows)
summary = [
    ("duplicate_cluster_rejections", len(rows)),
    ("exact_event_duplicates", sum(r["exact_event_duplicate"] == "true" for r in rows)),
    ("distinct_timestamped_rearm_events", sum(r["exact_event_duplicate"] == "false" for r in rows)),
    ("after_first_trade_close", sum(r["after_first_trade_close"] == "true" for r in rows)),
    ("d032_accepted_as_distinct_trades", sum(r["d032_accepted_as_trade"] == "true" for r in rows)),
    ("after_close_and_d032_accepted", sum(
        r["after_first_trade_close"] == "true" and r["d032_accepted_as_trade"] == "true"
        for r in rows)),
    ("cross_session_from_consumed_event", sum(
        (int(r["consumed_signal_time"][11:13]) < 16) !=
        (int(r["rejected_signal_time"][11:13]) < 16) for r in rows)),
]
write(OUT / "ssr_cluster_rejection_summary.csv", ["metric", "value"],
      [{"metric": k, "value": v} for k, v in summary])
print(dict(summary))
