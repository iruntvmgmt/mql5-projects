#!/usr/bin/env python3
"""Decompose TP structure rejections from a bounded SignalJournal slice."""

from __future__ import annotations

import argparse
import re
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median

from acceptance_funnel_report import rows


DETAIL = re.compile(
    r"structure not impulse/pullback state=(?P<state>[A-Z0-9_]+) slope=(?P<slope>[0-9.]+) "
    r"dirEff=(?P<eff>[0-9.]+) displacement=(?P<disp>[0-9.]+) "
    r"equilibrium=(?P<equil>[0-9.]+) returning=(?P<returning>yes|no)"
    r"(?: movingToward=(?P<moving>yes|no) valueProgress=(?P<progress>-?[0-9.]+)"
    r" crossedValue=(?P<crossed>yes|no))?"
    r"(?: lifecycle=(?P<lifecycle>[a-z_]+) lifecycleBars=(?P<lifecycle_bars>[0-9]+))?",
    re.IGNORECASE,
)
LIFECYCLE = re.compile(
    r"lifecycle=(?P<lifecycle>[a-z_]+) lifecycleBars=(?P<lifecycle_bars>[0-9]+)"
    r"(?: lifecycleSeed=(?P<seed>[a-z_]+) impulseStart=(?P<start>[0-9]+)"
    r" impulseStartPrice=(?P<start_price>[0-9.]+) impulseExtreme=(?P<extreme>[0-9.]+)"
    r" impulseSpanATR=(?P<span_atr>[0-9.]+))?",
    re.IGNORECASE,
)


def table(headers, body):
    output = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    output.extend("| " + " | ".join(map(str, line)) + " |" for line in body)
    return "\n".join(output)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path)
    parser.add_argument("--offset", type=int, required=True)
    parser.add_argument("--end-offset", type=int, required=True)
    parser.add_argument("--slope", type=float, required=True)
    parser.add_argument("--displacement", type=float, default=1.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    failures = Counter()
    combinations = Counter()
    states = Counter()
    state_combinations = Counter()
    observed = {name: [] for name in ("slope", "eff", "disp", "equil")}
    displacement_only = []
    movement = Counter()
    progress = []
    diagnostic_rows = 0
    lifecycle_phases = Counter()
    lifecycle_bars = defaultdict(list)
    lifecycle_seeds = Counter()
    impulse_spans = defaultdict(list)
    matched = 0
    for row in rows(args.csv, args.offset, args.end_offset):
        if row.get("Strategy", "").strip() != "TP":
            continue
        reason = row.get("RejectionReason", "")
        lifecycle_match = LIFECYCLE.search(reason)
        if lifecycle_match is not None:
            phase = lifecycle_match.group("lifecycle").lower()
            lifecycle_phases[phase] += 1
            lifecycle_bars[phase].append(int(lifecycle_match.group("lifecycle_bars")))
            if lifecycle_match.group("seed") is not None:
                seed = lifecycle_match.group("seed").lower()
                lifecycle_seeds[seed] += 1
                if seed != "none":
                    impulse_spans[seed].append(float(lifecycle_match.group("span_atr")))
        match = DETAIL.search(reason)
        if not match:
            continue
        matched += 1
        states[match.group("state")] += 1
        values = {key: float(match.group(key)) for key in ("slope", "eff", "disp", "equil")}
        for name in observed:
            observed[name].append(values[name])
        returning = match.group("returning").lower() == "yes"
        if match.group("moving") is not None:
            diagnostic_rows += 1
            is_moving = match.group("moving").lower() == "yes"
            is_crossed = match.group("crossed").lower() == "yes"
            movement["moving_toward"] += int(is_moving)
            movement["not_moving_toward"] += int(not is_moving)
            movement["crossed_into_value"] += int(is_crossed)
            movement["near_value_but_departing"] += int(returning and not is_moving)
            progress.append(float(match.group("progress")))
        if (values["slope"] > args.slope and values["eff"] > 0.4 and
                values["disp"] <= args.displacement):
            displacement_only.append(values["disp"])
        failed = []
        checks = (
            ("slope", values["slope"] <= args.slope),
            ("impulse_efficiency", values["eff"] <= 0.4),
            ("impulse_displacement", values["disp"] <= args.displacement),
            ("pullback_equilibrium", values["equil"] <= 0.5),
            ("pullback_returning", not returning),
        )
        for name, did_fail in checks:
            if did_fail:
                failures[name] += 1
                failed.append(name)
        combinations[" + ".join(failed) or "none"] += 1
        state_combinations[(match.group("state"), " + ".join(failed) or "none")] += 1

    report = [
        "# TP structure rejection decomposition", "",
        f"Rows matched: {matched}",
        f"Configured slope threshold: {args.slope:.3f}", "",
        f"Configured displacement threshold: {args.displacement:.3f}", "",
        "Counts are overlapping predicate failures; one rejected observation may appear in several rows.", "",
        "## Predicate failures", "",
        table(["Predicate", "Failed rows", "Share"], [
            [name, count, f"{count / matched:.1%}" if matched else "n/a"]
            for name, count in failures.most_common()
        ]), "", "## Preempting structural states", "",
        table(["State", "Rows"], states.most_common()), "",
        "## Observed feature distribution", "",
        table(["Feature", "Minimum", "Median", "Maximum"], [
            [name, f"{min(values):.3f}", f"{median(values):.3f}", f"{max(values):.3f}"]
            for name, values in observed.items() if values
        ]), "", "## Otherwise impulse-qualified displacement", "",
        (f"Rows: {len(displacement_only)}; minimum: {min(displacement_only):.3f}; "
         f"median: {median(displacement_only):.3f}; maximum: {max(displacement_only):.3f}"
         if displacement_only else "No rows."), "",
        "## Value-return movement diagnostics", "",
        (table(["Diagnostic", "Rows", "Share of diagnostic rows"], [
            [name, count, f"{count / diagnostic_rows:.1%}"]
            for name, count in movement.items()
        ]) if diagnostic_rows else
         "No movement fields were present; this is a legacy journal slice."),
        ("\n\nProgress distribution: minimum " + f"{min(progress):.3f}" +
         ", median " + f"{median(progress):.3f}" +
         ", maximum " + f"{max(progress):.3f}" + "."
         if progress else ""), "",
        "## Observational lifecycle phases", "",
        (table(["Phase", "Rows", "Median phase bars", "Maximum phase bars"], [
            [phase, count, f"{median(lifecycle_bars[phase]):.1f}",
             max(lifecycle_bars[phase])]
            for phase, count in lifecycle_phases.most_common()
        ]) if lifecycle_phases else
         "No lifecycle fields were present; this is a pre-lifecycle journal slice."), "",
        "## Observational impulse seeds", "",
        (table(["Seed source", "Rows", "Median span ATR", "Maximum span ATR"], [
            [seed, count,
             (f"{median(impulse_spans[seed]):.3f}" if impulse_spans[seed] else "n/a"),
             (f"{max(impulse_spans[seed]):.3f}" if impulse_spans[seed] else "n/a")]
            for seed, count in lifecycle_seeds.most_common()
        ]) if lifecycle_seeds else
         "No impulse-seed fields were present."), "",
        "## Failure combinations", "",
        table(["Combination", "Rows"], combinations.most_common()), "",
        "## State and failure combination", "",
        table(["State", "Combination", "Rows"], [
            [state, combination, count]
            for (state, combination), count in state_combinations.most_common()
        ]), "",
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
