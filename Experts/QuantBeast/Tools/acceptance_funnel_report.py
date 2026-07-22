#!/usr/bin/env python3
"""Build a combined QuantBeast acceptance funnel from SignalJournal CSVs."""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter, defaultdict
from pathlib import Path

csv.field_size_limit(sys.maxsize)


def decode(path: Path, offset: int = 0, end_offset: int | None = None) -> str:
    data = path.read_bytes()[offset:end_offset]
    encodings = []
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        encodings.append("utf-16")
    elif len(data) >= 4:
        odd_nuls = data[1::2].count(0)
        even_nuls = data[0::2].count(0)
        pairs = max(1, len(data) // 2)
        if odd_nuls / pairs > 0.25:
            encodings.append("utf-16le")
        elif even_nuls / pairs > 0.25:
            encodings.append("utf-16be")
    encodings.extend(("utf-8-sig", "utf-8", "utf-16"))
    for encoding in encodings:
        try:
            return data.decode(encoding)
        except UnicodeError:
            pass
    raise UnicodeError(f"Unable to decode {path}")


def rows(path: Path, offset: int = 0, end_offset: int | None = None):
    lines = [line for line in decode(path, offset, end_offset).splitlines() if line.strip()]
    if not lines:
        return
    first = [cell.strip() for cell in next(csv.reader([lines[0]]))]
    headered = "Strategy" in first and "Accepted" in first
    if headered:
        yield from csv.DictReader(lines)
        return
    names = [
        "Timestamp", "Symbol", "Mode", "Strategy", "Direction", "SignalID",
        "SetupCode", "TriggerCode", "Accepted", "RejectionCode",
        "RejectionReason", "RegimeTrend", "RegimeVol", "Session", "Spread",
        "ATR_Points", "Entry", "Stop", "Target", "ExpectedR", "Confidence",
        "StrategyFamily", "StrategyTemplate", "StrategyTags",
    ]
    for raw in csv.reader(lines):
        yield dict(zip(names, raw))


def stage(row: dict) -> str:
    if row.get("Accepted", "").strip().upper() == "ACCEPTED":
        return "accepted"
    reason = row.get("RejectionReason", "").strip().lower()
    try:
        code = int(row.get("RejectionCode", "-1"))
    except ValueError:
        code = -1
    if code == 22 or "arbitration" in reason:
        return "arbitration"
    if code == 8 or reason.startswith("risk:") or reason.startswith("sized risk:"):
        return "risk_stop"
    if code == 20 or reason.startswith("size:"):
        return "sizing"
    if code == 19 or reason.startswith("broker constraints:"):
        return "broker_constraints"
    if code in (5, 23, 24):
        return "strategy"
    return "other"


def number(row: dict, key: str) -> float | None:
    try:
        return float(row.get(key, ""))
    except (TypeError, ValueError):
        return None


def risk_category(reason: str) -> str:
    text = reason.lower()
    for needle, label in (
        ("stop too far", "stop_too_far"),
        ("stop too close", "stop_too_close"),
        ("reward:risk too low", "reward_risk"),
        ("max consecutive losses", "consecutive_loss_lock"),
        ("daily loss", "daily_loss_lock"),
        ("weekly loss", "weekly_loss_lock"),
        ("drawdown", "drawdown_lock"),
        ("max positions", "position_capacity"),
        ("max exposure", "exposure_capacity"),
        ("actual risk", "sized_risk"),
    ):
        if needle in text:
            return label
    return "other_risk"


def eligibility_category(reason: str) -> str:
    text = reason.lower()
    for needle, label in (
        ("compression bars", "compression"),
        ("no failed breakout or reclaim", "failed_breakout_or_reclaim"),
        ("trend not directional", "directional_trend"),
        ("directional efficiency", "directional_efficiency"),
        ("trend persistence", "trend_persistence"),
        ("structure not impulse/pullback", "impulse_pullback_structure"),
        ("structure not balanced", "balanced_structure"),
        ("trend strength", "trend_strength"),
        ("volatility", "volatility"),
        ("trend exhausted", "trend_exhaustion"),
        ("breakout structure active", "breakout_structure"),
        ("htf not aligned", "htf_alignment"),
        ("htf bias is not", "htf_direction"),
        ("liquidity unsafe", "liquidity"),
        ("spread", "spread"),
        ("event state", "event_state"),
        ("disabled", "disabled"),
        ("price not near", "setup_location"),
        ("no downside failed auction", "directional_setup"),
        ("no upside failed auction", "directional_setup"),
        ("not uptrend", "directional_setup"),
        ("not downtrend", "directional_setup"),
        ("pullback age", "pullback_age"),
        ("pullback depth", "pullback_depth"),
        ("pullback not ending", "pullback_completion"),
        ("insufficient deviation", "vwap_deviation"),
        ("no rejection wick", "rejection_wick"),
        ("no trigger", "trigger"),
        ("trigger not confirmed", "trigger"),
        ("configured trigger not confirmed", "trigger"),
        ("insufficient penetration", "penetration"),
        ("penetration too old", "penetration_age"),
        ("reclaim depth too small", "reclaim_depth"),
        ("price not reclaimed", "reclaim"),
        ("no valid level", "level_availability"),
        ("insufficient r:r", "reward_risk"),
        ("low confidence", "confidence"),
    ):
        if needle in text:
            return label
    return "other_strategy"


def table(headers, body):
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    out.extend("| " + " | ".join(map(str, line)) + " |" for line in body)
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", nargs="+", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    parser.add_argument(
        "--offset", action="append", default=[], metavar="FILE=BYTES",
        help="Start one input at an exact byte offset (repeatable)",
    )
    parser.add_argument(
        "--end-offset", action="append", default=[], metavar="FILE=BYTES",
        help="End one input before an exact byte offset (repeatable)",
    )
    args = parser.parse_args()

    offsets = {}
    for spec in args.offset:
        name, separator, value = spec.rpartition("=")
        if not separator or not name or not value.isdigit():
            parser.error(f"invalid --offset value: {spec}")
        offsets[str(Path(name).resolve())] = int(value)

    end_offsets = {}
    for spec in args.end_offset:
        name, separator, value = spec.rpartition("=")
        if not separator or not name or not value.isdigit():
            parser.error(f"invalid --end-offset value: {spec}")
        end_offsets[str(Path(name).resolve())] = int(value)

    for name, end_offset in end_offsets.items():
        if end_offset < offsets.get(name, 0):
            parser.error(f"end offset precedes start offset: {name}")

    counts = defaultdict(Counter)
    risk_reasons = defaultdict(Counter)
    risk_categories = defaultdict(Counter)
    strategy_categories = defaultdict(Counter)
    stop_distances = defaultdict(list)
    total = 0
    for path in args.csv:
        resolved = str(path.resolve())
        offset = offsets.get(resolved, 0)
        end_offset = end_offsets.get(resolved)
        for row in rows(path, offset, end_offset):
            strategy = row.get("Strategy", "").strip() or "unknown"
            bucket = stage(row)
            counts[strategy][bucket] += 1
            if bucket == "risk_stop":
                rejection = row.get("RejectionReason", "").strip()
                risk_reasons[strategy][rejection] += 1
                risk_categories[strategy][risk_category(rejection)] += 1
            elif bucket == "strategy":
                rejection = row.get("RejectionReason", "").strip()
                strategy_categories[strategy][eligibility_category(rejection)] += 1
            total += 1
            if bucket == "risk_stop":
                entry, stop = number(row, "Entry"), number(row, "Stop")
                if entry is not None and stop is not None and entry > 0 and stop > 0:
                    stop_distances[strategy].append(abs(entry - stop))

    order = ["strategy", "arbitration", "risk_stop", "sizing", "broker_constraints", "accepted", "other"]
    body = []
    for strategy in sorted(counts):
        c = counts[strategy]
        body.append([strategy, sum(c.values()), *[c[name] for name in order]])

    report = [
        "# QuantBeast acceptance funnel",
        "",
        f"Input journals: {len(args.csv)}",
        f"Offset-scoped inputs: {sum(1 for value in offsets.values() if value > 0)}",
        f"End-bounded inputs: {len(end_offsets)}",
        f"Signal rows analyzed: {total}",
        "",
        table(["Strategy", "Rows", "Strategy", "Arbitration", "Risk/stop", "Sizing", "Broker", "Accepted", "Other"], body),
        "",
        "## Risk/stop detail",
        "",
    ]
    risk_body = []
    for strategy in sorted(counts):
        risk_count = counts[strategy]["risk_stop"]
        distances = stop_distances[strategy]
        mean_distance = f"{sum(distances) / len(distances):.5f}" if distances else "n/a"
        top = next(iter(risk_reasons[strategy].most_common(1)), ("", 0))
        risk_body.append([strategy, risk_count, len(distances), mean_distance, top[0], top[1]])
    report.append(table(["Strategy", "Risk/stop rejects", "With geometry", "Mean price distance", "Top risk/stop reason", "Count"], risk_body))
    report.extend(["", "## Risk/stop rejection categories", ""])
    category_body = []
    for strategy in sorted(risk_categories):
        for category, count in risk_categories[strategy].most_common():
            category_body.append([strategy, category, count])
    report.append(table(["Strategy", "Category", "Count"], category_body) if category_body else "No risk/stop rejections.")
    report.extend(["", "## Strategy rejection categories", ""])
    strategy_body = []
    for strategy in sorted(strategy_categories):
        for category, count in strategy_categories[strategy].most_common():
            strategy_body.append([strategy, category, count])
    report.append(table(["Strategy", "Category", "Count"], strategy_body) if strategy_body else "No strategy-stage rejections.")
    report.extend([
        "",
        "## Interpretation boundary",
        "",
        "Inputs without byte bounds may contain overlapping combined and isolated strategy runs. Start-and-end-bounded inputs contain only rows within the recorded run slice.",
        "",
        "This report starts at emitted strategy decisions. Tick/data-quality preflight blocks occur before journal emission and must be measured from the matching tester-agent log. Do not infer that absent journal rows are strategy or risk rejections.",
        "",
    ])
    text = "\n".join(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
