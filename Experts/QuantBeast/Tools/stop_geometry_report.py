#!/usr/bin/env python3
"""Report accepted and risk-rejected stop geometry from bounded journal slices."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median

from acceptance_funnel_report import number, rows, stage


def table(headers, body):
    out = ["| " + " | ".join(headers) + " |",
           "| " + " | ".join(["---"] * len(headers)) + " |"]
    out.extend("| " + " | ".join(map(str, line)) + " |" for line in body)
    return "\n".join(out)


def summary(values):
    if not values:
        return ("n/a", "n/a", "n/a")
    return tuple(f"{value:.2f}" for value in
                 (min(values), median(values), max(values)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path)
    parser.add_argument(
        "--slice", action="append", required=True, metavar="LABEL:START:END",
        help="Exact byte-bounded journal slice; repeat for each completed run",
    )
    parser.add_argument("--point", type=float, required=True)
    parser.add_argument("--max-stop-points", type=float, required=True)
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()

    if args.point <= 0 or args.max_stop_points <= 0:
        parser.error("--point and --max-stop-points must be positive")

    slices = []
    for spec in args.slice:
        try:
            label, start, end = spec.rsplit(":", 2)
            start, end = int(start), int(end)
        except ValueError:
            parser.error(f"invalid --slice value: {spec}")
        if not label or start < 0 or end <= start:
            parser.error(f"invalid --slice bounds: {spec}")
        slices.append((label, start, end))

    counts = defaultdict(Counter)
    stop_points = defaultdict(list)
    stop_atr = defaultdict(list)
    excess_points = defaultdict(list)
    window_counts = defaultdict(Counter)

    for label, start, end in slices:
        for row in rows(args.csv, start, end):
            bucket = stage(row)
            if bucket not in ("accepted", "risk_stop"):
                continue
            strategy = row.get("Strategy", "").strip() or "unknown"
            entry, stop = number(row, "Entry"), number(row, "Stop")
            atr_points = number(row, "ATR_Points")
            if not entry or not stop:
                continue
            distance_points = abs(entry - stop) / args.point
            outcome = "accepted" if bucket == "accepted" else "risk_rejected"
            key = (strategy, outcome)
            counts[strategy][outcome] += 1
            window_counts[(label, strategy)][outcome] += 1
            stop_points[key].append(distance_points)
            if atr_points and atr_points > 0:
                stop_atr[key].append(distance_points / atr_points)
            if distance_points > args.max_stop_points:
                excess_points[strategy].append(distance_points - args.max_stop_points)

    distribution = []
    for key in sorted(stop_points):
        strategy, outcome = key
        point_stats = summary(stop_points[key])
        atr_stats = summary(stop_atr[key])
        distribution.append([
            strategy, outcome, len(stop_points[key]),
            *point_stats, *atr_stats,
        ])

    by_window = []
    for (label, strategy), values in sorted(window_counts.items()):
        by_window.append([
            label, strategy, values["accepted"], values["risk_rejected"],
        ])

    excess = []
    for strategy in sorted(excess_points):
        stats = summary(excess_points[strategy])
        excess.append([strategy, len(excess_points[strategy]), *stats])

    report = [
        "# QuantBeast stop-geometry report", "",
        f"Completed journal slices: {len(slices)}", "",
        f"Point size: {args.point:g}", "",
        f"Central maximum stop: {args.max_stop_points:.0f} points", "",
        "Only accepted signals and central risk/stop rejections with proposed geometry are included.", "",
        "## Geometry distribution", "",
        table([
            "Strategy", "Outcome", "Rows", "Min points", "Median points",
            "Max points", "Min ATR", "Median ATR", "Max ATR",
        ], distribution), "",
        "## Counts by completed window", "",
        table(["Window", "Strategy", "Accepted", "Risk rejected"], by_window), "",
        "## Excess over central maximum", "",
        (table(["Strategy", "Rows", "Min excess", "Median excess", "Max excess"], excess)
         if excess else "No stop exceeded the central maximum."), "",
        "## Interpretation boundary", "",
        "This is conditional on signals that reached final geometry. It does not describe strategy-rejected observations and does not prove that a wider stop would be profitable. The central safety limit must not be changed from this report alone.", "",
    ]
    text = "\n".join(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
