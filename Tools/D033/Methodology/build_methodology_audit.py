#!/usr/bin/env python3
"""Audit D032/D033 policy parity and SSR re-arm semantics without changing them."""
import calendar
import csv
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "Tools" / "D033" / "Methodology"
RATES = ROOT / "Tools" / "D032" / "D032_Rates_XAUUSD_M5.csv"
RESEARCH = ROOT / "Tools" / "D032" / "D032_SixFamilyResearchJournal_source.csv"
IDENTITY = ROOT / "Tools" / "D033" / "Remediation" / "identity_before_after.csv"
CURRENT = Path("/private/tmp/d033_remediation_ssr")


def read(path, delimiter=","):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def write(name, fields, rows):
    with (OUT / name).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fields, extrasaction="ignore",
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def parse(value):
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


rates = read(RATES, ";")
for row in rates:
    row["dt"] = parse(row["time"])
    for field in ("open", "high", "low", "close"):
        row[field] = float(row[field])

# The D032 rates export starts after the Asian window on its first day.
# Recover that one frozen range from the preserved research journal's
# structural context. Every later day is independently rebuilt from rates.
first_day_seed = {}
with RESEARCH.open(encoding="utf-8-sig") as handle:
    header = handle.readline()
    for line in handle:
        parts = line.rstrip("\n").split(";")
        if parts[0] != "1200":
            continue
        day = parts[3][:10]
        context = ";".join(parts[18:-3])
        values = {}
        for token in context.replace("|", ";").split(";"):
            if "=" in token:
                key, value = token.split("=", 1)
                values[key] = value
        if "asian_high" in values and "asian_low" in values:
            first_day_seed[day] = (
                float(values["asian_high"]), float(values["asian_low"])
            )

tr = []
for index, row in enumerate(rates):
    if index == 0:
        value = row["high"] - row["low"]
    else:
        previous = rates[index - 1]["close"]
        value = max(
            row["high"] - row["low"],
            abs(row["high"] - previous),
            abs(row["low"] - previous),
        )
    tr.append(value)
    row["atr"] = sum(tr[index - 13:index + 1]) / 14.0 if index >= 13 else 0.0

candidate_rows = read(IDENTITY)
candidate_by_origin = {
    row["corrected_origin_id"]: row for row in candidate_rows
}


def epoch(when):
    return calendar.timegm(when.timetuple())


states = {
    "LONG": {"active": False, "terminal_state": "NONE",
             "terminal_time": None, "inside_since_terminal": True},
    "SHORT": {"active": False, "terminal_state": "NONE",
              "terminal_time": None, "inside_since_terminal": True},
}
anchor_day = None
asian_high = asian_low = 0.0
asian_frozen = False
previous_outside = {"LONG": False, "SHORT": False}
all_arms = []
matched = {}

for bar in rates:
    day_text = bar["time"][:10]
    day_key = int(day_text.replace(".", ""))
    hour = bar["dt"].hour
    if day_key != anchor_day:
        anchor_day = day_key
        asian_frozen = False
        asian_high = bar["high"]
        asian_low = bar["low"]
        for state in states.values():
            state.update(active=False, terminal_state="NONE",
                         terminal_time=None, inside_since_terminal=True)
        previous_outside = {"LONG": False, "SHORT": False}
    if hour < 8 and not asian_frozen:
        asian_high = max(asian_high, bar["high"])
        asian_low = min(asian_low, bar["low"])
    else:
        if not asian_frozen and day_text in first_day_seed:
            asian_high, asian_low = first_day_seed[day_text]
        asian_frozen = True

    atr = bar["atr"]
    if atr <= 0:
        continue
    threshold = {
        "LONG": asian_low - atr * 0.15,
        "SHORT": asian_high + atr * 0.15,
    }
    outside = {
        "LONG": bar["low"] <= threshold["LONG"],
        "SHORT": bar["high"] >= threshold["SHORT"],
    }
    for direction, state in states.items():
        if not outside[direction]:
            state["inside_since_terminal"] = True

    # Exact production ordering: terminal evaluation occurs before Arm().
    for direction, state in states.items():
        if not state["active"]:
            continue
        terminal = None
        if bar["dt"] > state["expiry_time"]:
            terminal = "EXPIRED"
        else:
            if direction == "LONG":
                state["extreme"] = min(state["extreme"], bar["low"])
                acceptance = bar["close"] < state["level"] - atr * 0.50
                reclaimed = bar["close"] > state["level"] + atr * 0.05
            else:
                state["extreme"] = max(state["extreme"], bar["high"])
                acceptance = bar["close"] > state["level"] + atr * 0.50
                reclaimed = bar["close"] < state["level"] - atr * 0.05
            if acceptance:
                terminal = "INVALIDATED"
            elif reclaimed:
                terminal = "TRIGGERED"
                origin = state["sequence_id"]
                if origin in candidate_by_origin:
                    matched[origin] = state["arm_record"]
        if terminal:
            state["active"] = False
            state["terminal_state"] = terminal
            state["terminal_time"] = bar["dt"]
            state["inside_since_terminal"] = False

    if hour < 8 or not asian_frozen:
        previous_outside = outside
        continue

    for direction, state in states.items():
        if state["active"] or not outside[direction]:
            previous_outside[direction] = outside[direction]
            continue
        fresh_cross = not previous_outside[direction]
        same_bar = state["terminal_time"] == bar["dt"]
        if same_bar:
            classification = "SAME_TRIGGER_BAR_REARM"
        elif (state["terminal_state"] == "EXPIRED"
              and not state["inside_since_terminal"]):
            classification = "STILL_OUTSIDE_AFTER_EXPIRY_REARM"
        elif (state["terminal_state"] == "INVALIDATED"
              and not state["inside_since_terminal"]):
            classification = "STILL_OUTSIDE_AFTER_INVALIDATION_REARM"
        elif state["inside_since_terminal"] and state["terminal_state"] != "NONE":
            classification = "FRESH_CROSS_AFTER_NEUTRAL_RESET"
        elif fresh_cross:
            classification = "FRESH_CROSS_FROM_INSIDE"
        else:
            classification = "OTHER"
        level_type = "ASIA_LOW" if direction == "LONG" else "ASIA_HIGH"
        origin = f"SSRP|{level_type}|{day_key}|{epoch(bar['dt'])}"
        record = {
            "origin_id": origin,
            "event_id": origin + "|FINAL",
            "direction": direction,
            "arm_time": bar["time"],
            "prior_terminal_state": state["terminal_state"],
            "prior_terminal_time": (
                state["terminal_time"].strftime("%Y.%m.%d %H:%M:%S")
                if state["terminal_time"] else ""
            ),
            "same_bar_as_prior_terminal": str(same_bar).lower(),
            "price_crossed_back_inside_before_this_arm":
                str(state["inside_since_terminal"]).lower(),
            "fresh_threshold_crossing_occurred": str(fresh_cross).lower(),
            "classification": classification,
        }
        all_arms.append(record)
        state.update(
            active=True,
            expiry_time=bar["dt"] + timedelta(minutes=30),
            level=asian_low if direction == "LONG" else asian_high,
            extreme=bar["low"] if direction == "LONG" else bar["high"],
            sequence_id=origin,
            arm_record=record,
            inside_since_terminal=False,
        )
        previous_outside[direction] = True

missing = sorted(set(candidate_by_origin) - set(matched))
assert not missing, f"{len(missing)} production candidates did not match replay"
classified = [matched[row["corrected_origin_id"]] for row in candidate_rows]
assert len(classified) == 2650
write("ssr_rearm_classification.csv", list(classified[0]), classified)

trades = read(CURRENT / "MSZZ_TradeAnalytics.csv", ";")
signals = read(CURRENT / "MSZZ_SignalJournal.csv", ";")
executed_event = {
    row["cluster_id"]: row["event_id"]
    for row in signals if row["status"] == "EXECUTED"
}
trade_by_origin = {}
for trade in trades:
    for origin in candidate_by_origin:
        if trade["cluster_id"].endswith(origin):
            trade_by_origin[origin] = trade
            break

classification_metrics = []
for name, count in sorted(Counter(
        row["classification"] for row in classified).items()):
    selected = [
        trade_by_origin[row["origin_id"]]
        for row in classified
        if row["classification"] == name and row["origin_id"] in trade_by_origin
    ]
    results = [float(row["r_result"]) for row in selected]
    gains = sum(value for value in results if value > 0)
    losses = -sum(value for value in results if value < 0)
    classification_metrics.append({
        "classification": name,
        "candidate_count": count,
        "broker_trade_count": len(selected),
        "total_r": sum(results),
        "profit_factor": gains / losses if losses else "",
        "expectancy_r": sum(results) / len(results) if results else "",
    })

parity_path = Path("/private/tmp/d033_ssr_stop_target_parity")
if parity_path.exists():
    parity_trades = read(parity_path / "MSZZ_TradeAnalytics.csv", ";")
    parity_by_origin = {}
    for trade in parity_trades:
        for origin in candidate_by_origin:
            if trade["cluster_id"].endswith(origin):
                parity_by_origin[origin] = trade
                break
    for metric in classification_metrics:
        selected = [
            parity_by_origin[row["origin_id"]]
            for row in classified
            if row["classification"] == metric["classification"]
            and row["origin_id"] in parity_by_origin
        ]
        values = [float(row["r_result"]) for row in selected]
        gains = sum(value for value in values if value > 0)
        losses = -sum(value for value in values if value < 0)
        metric["parity_trade_count"] = len(selected)
        metric["parity_total_r"] = sum(values)
        metric["parity_profit_factor"] = gains / losses if losses else ""
        metric["parity_expectancy_r"] = (
            sum(values) / len(values) if values else ""
        )
write("ssr_rearm_classification_summary.csv",
      list(classification_metrics[0]), classification_metrics)

rate_times = [row["dt"] for row in rates]


def stop_target_outcome(trade):
    import bisect
    start = bisect.bisect_right(rate_times, parse(trade["fill_time"]))
    direction = trade["direction"]
    stop = float(trade["stop"])
    target = float(trade["target"])
    for bar in rates[start:]:
        stop_hit = bar["low"] <= stop if direction == "LONG" else bar["high"] >= stop
        target_hit = bar["high"] >= target if direction == "LONG" else bar["low"] <= target
        if stop_hit:
            return "STOP", bar["time"], -1.0
        if target_hit:
            return "TARGET", bar["time"], 2.0
    return "OPEN_AT_TEST_END", rates[-1]["time"], ""


opposite_rows = []
for trade in (row for row in trades if row["exit_reason"] == "OTHER"):
    reversals = [
        row for row in trades
        if row["fill_time"] == trade["close_time"]
        and row["direction"] != trade["direction"]
    ]
    reversal = reversals[0] if reversals else None
    outcome, outcome_time, outcome_r = stop_target_outcome(trade)
    opposite_rows.append({
        "trade_id": trade["cluster_id"],
        "entry_time": trade["fill_time"],
        "opposite_signal_time": reversal["signal_time"] if reversal else "",
        "exit_price": trade["exit"],
        "r_at_opposite_close": trade["r_result"],
        "subsequent_reversal_entered": str(bool(reversal)).lower(),
        "event_id": executed_event.get(
            reversal["cluster_id"], "") if reversal else "",
        "stop_target_only_outcome": outcome,
        "stop_target_only_exit_time": outcome_time,
        "stop_target_only_r": outcome_r,
    })
assert len(opposite_rows) == 30
write("opposite_close_counterfactual.csv", list(opposite_rows[0]),
      opposite_rows)

policy = [
    ("same-direction candidate while open", "REJECT", "REJECT_OWNERSHIP",
     "REJECT_OWNERSHIP"),
    ("opposite-direction candidate while open", "REJECT",
     "CLOSE_AND_REVERSE", "CLOSE_AND_REVERSE"),
    ("stop exit", "YES", "YES", "YES"),
    ("target exit", "YES", "YES", "YES"),
    ("opposite-signal exit", "NO", "YES", "YES"),
    ("immediate reversal", "NO", "YES", "YES"),
    ("test-end exit", "EXCLUDED_FROM_RESULTS", "BROKER_TEST_END_CLOSE",
     "BROKER_TEST_END_CLOSE"),
]
write("execution_policy_matrix.csv",
      ["behavior", "d032_simulator", "old_d033", "corrected_d033_467155e"],
      [{"behavior": row[0], "d032_simulator": row[1], "old_d033": row[2],
        "corrected_d033_467155e": row[3]} for row in policy])

write("audit_counts.csv", ["metric", "value"], [
    {"metric": "all_state_machine_arms", "value": len(all_arms)},
    {"metric": "emitted_candidates_classified", "value": len(classified)},
    {"metric": "unmatched_emitted_candidates", "value": len(missing)},
    {"metric": "same_bar_rearms", "value": sum(
        row["classification"] == "SAME_TRIGGER_BAR_REARM"
        for row in classified)},
    {"metric": "still_outside_expiry_rearms", "value": sum(
        row["classification"] == "STILL_OUTSIDE_AFTER_EXPIRY_REARM"
        for row in classified)},
    {"metric": "still_outside_invalidation_rearms", "value": sum(
        row["classification"] == "STILL_OUTSIDE_AFTER_INVALIDATION_REARM"
        for row in classified)},
    {"metric": "opposite_signal_closes", "value": len(opposite_rows)},
])

print(Counter(row["classification"] for row in classified))
print(classification_metrics)
print(Counter(row["stop_target_only_outcome"] for row in opposite_rows))
