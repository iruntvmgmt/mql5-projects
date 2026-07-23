#!/usr/bin/env python3
"""Decompose TP V2 lifecycle rows from a bounded SignalJournal slice.

Parses the `lifecycleVersion=2 lifecycle=<phase> lifecycleBars=<n>
lifecycleDirection=<dir> reasonCode=<code> impulseStart=<epoch>
retracementDepth=<depth> invalidationLevel=<level>` tag every TPV2
Evaluate call appends (see TrendPullbackV2Engine.mqh MakeLifecycleRejected()
and TP_V2_REASON_CODES.md). Mirrors tp_structure_report.py's approach for
V1 but reads V2's already-structured reasonCode instead of re-deriving
predicate failures from free text.
"""

from __future__ import annotations

import argparse
import re
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median

from acceptance_funnel_report import rows

LIFECYCLE_V2 = re.compile(
    r"lifecycleVersion=2 lifecycle=(?P<lifecycle>[a-z_]+) lifecycleBars=(?P<lifecycle_bars>[0-9]+) "
    r"lifecycleDirection=(?P<direction>up|down|none) reasonCode=(?P<reason_code>[A-Za-z0-9_]+) "
    r"impulseStart=(?P<start>-?[0-9]+) retracementDepth=(?P<depth>-?[0-9.]+) "
    r"invalidationLevel=(?P<invalidation>[0-9.]+)",
    re.IGNORECASE,
)
# The lifecycle tag's reasonCode is the state-TRANSITION code (e.g.
# TRIG_ENTER_TRIGGERED_REJECTION_CONFIRM), frozen at whichever bar last
# changed phase -- it is NOT the geometry outcome. Geometry-outcome markers
# (GEOM_ACCEPT / GEOM_REJECT_* / TPV2_EXPERIMENTAL_DISABLED) are appended by
# BuildTriggeredSignal() into the free-text prefix, before " lifecycleVersion=".
GEOMETRY_MARKERS = (
    "GEOM_ACCEPT", "TPV2_EXPERIMENTAL_DISABLED", "GEOM_REJECT_SPREAD",
    "GEOM_REJECT_INSUFFICIENT_RR", "GEOM_REJECT_LOW_CONFIDENCE",
)


def geometry_outcome(reason: str) -> str:
    prefix = reason.split(" lifecycleVersion=")[0]
    for marker in GEOMETRY_MARKERS:
        if marker in prefix:
            return marker
    return "UNKNOWN"


def table(headers, body):
    output = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    output.extend("| " + " | ".join(map(str, line)) + " |" for line in body)
    return "\n".join(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--offset", type=int, required=True)
    parser.add_argument("--end-offset", type=int, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    phases = Counter()
    phase_reason_codes = defaultdict(Counter)
    directions = Counter()
    phase_bars = defaultdict(list)
    depths = defaultdict(list)
    triggered_rows = []
    matched = 0
    total_rows = 0

    for row in rows(args.csv, args.offset, args.end_offset):
        if row.get("Strategy", "").strip() != "TPV2":
            continue
        total_rows += 1
        reason = row.get("RejectionReason", "") or ""
        match = LIFECYCLE_V2.search(reason)
        if match is None:
            continue
        matched += 1
        phase = match.group("lifecycle").lower()
        phases[phase] += 1
        phase_reason_codes[phase][match.group("reason_code")] += 1
        direction = match.group("direction").lower()
        directions[direction] += 1
        phase_bars[phase].append(int(match.group("lifecycle_bars")))
        depth = float(match.group("depth"))
        if phase in ("pullback_active", "resumption_armed", "triggered") and depth >= 0:
            depths[phase].append(depth)
        if phase == "triggered":
            triggered_rows.append({
                "Timestamp": row.get("Timestamp", ""),
                "Direction": row.get("Direction", ""),
                "Accepted": row.get("Accepted", ""),
                "reason_code": match.group("reason_code"),
                "geometry_outcome": geometry_outcome(reason),
                "depth": depth,
                "invalidation": float(match.group("invalidation")),
                "entry": row.get("Entry", ""),
                "stop": row.get("Stop", ""),
                "target": row.get("Target", ""),
                "expected_r": row.get("ExpectedR", ""),
            })

    report = [
        "# TP V2 lifecycle decomposition", "",
        f"Total TPV2 rows in slice: {total_rows}; rows with a parseable lifecycle tag: {matched}", "",
        "## Lifecycle phase distribution", "",
        table(["Phase", "Rows", "Median phase-age (bars)", "Max phase-age (bars)"], [
            [phase, count, f"{median(phase_bars[phase]):.1f}", max(phase_bars[phase])]
            for phase, count in phases.most_common()
        ]) if phases else "No TPV2 lifecycle rows in this slice.", "",
        "## Nominated direction distribution", "",
        table(["Direction", "Rows"], directions.most_common()) if directions else "n/a", "",
        "## Reason code by phase", "",
    ]
    for phase, counter in sorted(phase_reason_codes.items()):
        report.append(f"**{phase}:**")
        report.append("")
        report.append(table(["ReasonCode", "Rows"], counter.most_common()))
        report.append("")

    report.append("## Retracement depth distribution (pullback_active / resumption_armed / triggered rows)")
    report.append("")
    for phase in ("pullback_active", "resumption_armed", "triggered"):
        values = depths.get(phase, [])
        if values:
            report.append(f"- **{phase}**: n={len(values)}, min={min(values):.3f}, median={median(values):.3f}, max={max(values):.3f}")
        else:
            report.append(f"- **{phase}**: no rows.")
    report.append("")

    report.append("## TRIGGERED rows -- organic geometry reachability evidence")
    report.append("")
    if triggered_rows:
        report.append(table(
            ["Timestamp", "Direction", "Accepted", "TriggerCode", "GeometryOutcome", "Depth", "Invalidation", "Entry", "Stop", "Target", "ExpectedR"],
            [[r["Timestamp"], r["Direction"], r["Accepted"], r["reason_code"], r["geometry_outcome"], f"{r['depth']:.3f}",
              f"{r['invalidation']:.5f}", r["entry"], r["stop"], r["target"], r["expected_r"]]
             for r in triggered_rows],
        ))
        outcome_counts = Counter(r["geometry_outcome"] for r in triggered_rows)
        report.append("")
        report.append(f"Of {len(triggered_rows)} TRIGGERED rows, geometry outcome breakdown: " +
                       ", ".join(f"{code}={count}" for code, count in outcome_counts.most_common()) + ". " +
                       "GEOM_ACCEPT or TPV2_EXPERIMENTAL_DISABLED both mean geometry/spread/confidence all passed "
                       "(would trade if InpEnableTPV2Experimental were true); any GEOM_REJECT_* means the trigger "
                       "fired but geometry/spread/confidence itself failed.")
    else:
        report.append("No TRIGGERED rows in this slice -- TP V2 did not organically reach its trigger state in this window.")
    report.append("")

    text = "\n".join(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
