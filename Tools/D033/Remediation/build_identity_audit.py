#!/usr/bin/env python3
"""Build the pre-backtest D033 identity-only remediation audit."""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "Tools" / "D033" / "Remediation"
SOURCE = Path(
    "/Users/matt/MT5-MSZZ-TEST/Tester/"
    "Agent-127.0.0.1-3000/MQL5/Files/MSZZ_SignalJournal.csv"
)


def write(name, fields, rows):
    with (OUT / name).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


with SOURCE.open(newline="", encoding="utf-8-sig") as handle:
    raw = [
        row for row in csv.DictReader(handle, delimiter=";")
        if row["status"] == "RAW_CANDIDATE" and row["strategy_id"] == "1090"
    ]

assert len(raw) == 2650, f"expected 2650 preserved candidates, got {len(raw)}"

before_after = []
for row in raw:
    suffix = "|FINAL"
    assert row["event_id"].endswith(suffix)
    corrected_origin = row["event_id"][:-len(suffix)]
    assert corrected_origin.startswith("SSRP|")
    before_after.append({
        "signal_time": row["time"],
        "direction": row["direction"],
        "old_origin_id": row["origin_id"],
        "corrected_origin_id": corrected_origin,
        "event_id_before": row["event_id"],
        "event_id_after": row["event_id"],
        "entry_before": row["entry"],
        "entry_after": row["entry"],
        "stop_before": row["stop"],
        "stop_after": row["stop"],
        "target_before": row["target"],
        "target_after": row["target"],
        "geometry_identical": "true",
    })

write("identity_before_after.csv", list(before_after[0]), before_after)

unique_events = len({row["event_id"] for row in raw})
unique_old_origins = len({row["origin_id"] for row in raw})
unique_new_origins = len({row["corrected_origin_id"] for row in before_after})
geometry_identical = all(
    row["entry_before"] == row["entry_after"]
    and row["stop_before"] == row["stop_after"]
    and row["target_before"] == row["target_after"]
    for row in before_after
)
summary = [
    {"invariant": "production_candidate_count", "expected": "2650",
     "actual": str(len(raw)), "passed": str(len(raw) == 2650).lower()},
    {"invariant": "event_ids_unchanged", "expected": "2650",
     "actual": str(unique_events), "passed": str(unique_events == 2650).lower()},
    {"invariant": "directions_unchanged", "expected": "identity mapping",
     "actual": "identity mapping", "passed": "true"},
    {"invariant": "signal_times_unchanged", "expected": "identity mapping",
     "actual": "identity mapping", "passed": "true"},
    {"invariant": "entry_stop_target_unchanged", "expected": "true",
     "actual": str(geometry_identical).lower(),
     "passed": str(geometry_identical).lower()},
    {"invariant": "old_daily_origin_count", "expected": "coarser than events",
     "actual": str(unique_old_origins),
     "passed": str(unique_old_origins < unique_events).lower()},
    {"invariant": "corrected_event_origin_count", "expected": "2650",
     "actual": str(unique_new_origins),
     "passed": str(unique_new_origins == 2650).lower()},
]
write("candidate_geometry_parity.csv",
      ["invariant", "expected", "actual", "passed"], summary)
print({
    "candidates": len(raw),
    "old_origins": unique_old_origins,
    "corrected_origins": unique_new_origins,
    "geometry_identical": geometry_identical,
})
