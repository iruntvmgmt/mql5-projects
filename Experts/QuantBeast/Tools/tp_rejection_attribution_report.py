#!/usr/bin/env python3
"""Phase 6: per-event TP production rejection-path attribution.

For each TPOutcomeJournal.csv resume_candidate event, joins against the
paired BUY/SELL SignalJournal.csv rows for TP at the same bar timestamp
(both always exist -- BUY and SELL are always both evaluated) and reports:
nominated vs. evaluated direction, trend/structure/session/spread, directional
efficiency/slope/displacement/returning-to-value (parsed from the free-text
RejectionReason, only present when EligibilityFailure()'s structure check was
reached), pullback depth (only present when eligibility passed and the
pullback-depth check itself ran), HTF/trigger status, the first production
rejection reason, and whether valid entry/stop geometry was ever computed.

Columns that were never populated because EligibilityFailure() returned
earlier in its check order are reported as "not observed (rejected
upstream)" -- never coerced to a blank or zero that could read as a
measured value.

Join key: TPOutcomeJournal's RegistrationTime and SignalJournal's Timestamp
both derive from the same OnTick() pass's TimeCurrent() call for that bar,
so they match exactly as strings.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from acceptance_funnel_report import rows as signal_rows  # noqa: E402
from tp_outcome_report import rows as tp_rows  # noqa: E402
from tp_structure_report import DETAIL  # noqa: E402

NOT_OBSERVED = "not observed (rejected upstream)"
PULLBACK_DEPTH = re.compile(r"pullback depth (?P<depth>[0-9.]+)")


def table(headers, body) -> str:
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    out.extend("| " + " | ".join(str(cell) for cell in row) + " |" for row in body)
    return "\n".join(out)


def find_signal_rows(signal_entries, timestamp):
    matches = [
        r for r in signal_entries
        if r.get("Strategy", "").strip() == "TP" and r.get("Timestamp", "").strip() == timestamp
    ]
    buy = next((r for r in matches if r.get("Direction") == "BUY"), None)
    sell = next((r for r in matches if r.get("Direction") == "SELL"), None)
    return buy, sell


def geometry_status(row) -> str:
    if row is None:
        return NOT_OBSERVED
    try:
        entry_v = float(row.get("Entry", ""))
        stop_v = float(row.get("Stop", ""))
    except (TypeError, ValueError):
        return "not computed (rejected upstream of geometry)"
    if entry_v > 0 and stop_v > 0:
        return "constructible (Entry/Stop present)"
    return "not computed (rejected upstream of geometry)"


def htf_status(reason: str) -> str:
    if "HTF not aligned" in reason:
        return "misaligned (failing reason)"
    return NOT_OBSERVED


def trigger_status(reason: str) -> str:
    lower = reason.lower()
    if "configured trigger not confirmed" in lower:
        return "not confirmed (failing reason)"
    if "pullback not ending" in lower:
        return "pullback not ending (failing reason)"
    return NOT_OBSERVED


def pullback_depth(reason: str) -> str:
    m = PULLBACK_DEPTH.search(reason)
    return m.group("depth") if m else NOT_OBSERVED


def structure_detail(reason: str):
    m = DETAIL.search(reason)
    return m.groupdict() if m else None


def first_rejection_reason(row) -> str:
    if row is None:
        return NOT_OBSERVED
    reason = row.get("RejectionReason", "")
    # Strip the always-appended lifecycle= tag block to show only the
    # actual production rejection reason, matching what a human reading
    # "why was this rejected" would want -- the lifecycle tag is observation
    # metadata, not the rejection cause.
    cut = reason.find(" lifecycle=")
    return reason[:cut].strip() if cut >= 0 else reason.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tp-outcome", required=True, type=Path, help="TPOutcomeJournal.csv slice (whole-file or extracted per-window)")
    parser.add_argument("--signal", required=True, type=Path, help="SignalJournal.csv path")
    parser.add_argument("--offset", type=int, default=0, help="SignalJournal byte offset for this window")
    parser.add_argument("--end-offset", type=int, default=None, help="SignalJournal end byte offset for this window")
    parser.add_argument("--window", default="", help="Window label for the report heading")
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()

    tp_events = list(tp_rows(args.tp_outcome))
    signal_entries = list(signal_rows(args.signal, args.offset, args.end_offset))

    lines = [
        f"# TP production rejection-path attribution -- {args.window or args.tp_outcome.stem}",
        "",
        f"Events: {len(tp_events)}",
        "",
    ]

    summary_body = []
    for event in tp_events:
        timestamp = event.get("RegistrationTime", "")
        buy, sell = find_signal_rows(signal_entries, timestamp)

        lines.append(f"## {event.get('EventID')} ({timestamp})")
        lines.append("")
        rows_body = []
        for label, row in (("BUY", buy), ("SELL", sell)):
            if row is None:
                rows_body.append([label, "no matching SignalJournal row"] + [""] * 10)
                continue
            reason = row.get("RejectionReason", "")
            detail = structure_detail(reason)
            rows_body.append([
                label,
                row.get("RegimeTrend", ""),
                row.get("RegimeVol", ""),
                row.get("Session", ""),
                row.get("Spread", ""),
                detail["eff"] if detail else NOT_OBSERVED,
                detail["slope"] if detail else NOT_OBSERVED,
                detail["disp"] if detail else NOT_OBSERVED,
                detail["returning"] if detail else NOT_OBSERVED,
                pullback_depth(reason),
                htf_status(reason),
                trigger_status(reason),
            ])
        lines.append(table(
            ["Eval", "RegimeTrend", "RegimeVol", "Session", "Spread", "DirEff", "Slope",
             "Displacement", "Returning", "PullbackDepth", "HTF", "Trigger"],
            rows_body,
        ))
        lines.append("")
        buy_reason = first_rejection_reason(buy)
        sell_reason = first_rejection_reason(sell)
        lines.append(f"- Nominated lifecycle direction: **{event.get('Direction')}**")
        lines.append(f"- First production rejection reason (BUY): {buy_reason}")
        lines.append(f"- First production rejection reason (SELL): {sell_reason}")
        lines.append(f"- Geometry constructible (BUY): {geometry_status(buy)}")
        lines.append(f"- Geometry constructible (SELL): {geometry_status(sell)}")
        lines.append("")

        nominated_row = buy if event.get("Direction") == "up" else sell
        summary_body.append([
            event.get("EventID"), event.get("Direction"),
            first_rejection_reason(nominated_row),
            geometry_status(nominated_row),
        ])

    lines.append("## Summary -- rejection reason on the side matching the nominated direction")
    lines.append("")
    lines.append(table(["EventID", "Nominated direction", "First rejection reason", "Geometry"], summary_body))
    lines.append("")

    text = "\n".join(lines)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
