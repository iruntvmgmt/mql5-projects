#!/usr/bin/env python3
"""TP resume-candidate forward outcome report.

Reads TPOutcomeJournal.csv (a real structured, header-having CSV -- not the
free-text lifecycle= tags tp_structure_report.py parses) and reports, per
horizon and per window plus pooled: sample size, median/mean MFE_ATR,
median/mean MAE_ATR, favorable/adverse ratio, target-before-adverse rate, and
whether any pooled effect depends on a single window or a single event.

Also computes Baseline B (direction-shuffled TP events): a pure post-hoc
relabeling of each event as if the opposite direction had been nominated,
using the tracker's own mirror-symmetric MFE<->MAE math. Baselines A/C/D
(random bars, trend-direction-without-lifecycle, non-resuming impulse) are
NOT computed here -- they require forward OHLC at arbitrary non-
resume_candidate anchor bars this journal does not carry.

Horizons (3/6/12/24 completed M5 bars) and thresholds (+-0.25/0.50/1.00 ATR)
are the TPOutcomeTracker's fixed schema, declared before any evidence was
collected. This script must not be used to pick different horizons after
seeing results.
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from acceptance_funnel_report import decode  # noqa: E402

csv.field_size_limit(sys.maxsize)

HORIZONS = ("H3", "H6", "H12", "H24")

# TPOutcomeJournal.csv writes its header exactly once, at file creation --
# never at the start of an exact-byte-bounded evidence slice, which always
# starts after some prior baseline offset. So a slice's first line is almost
# always a data row, not a header; only a read starting at byte 0 sees the
# real header. Detect that case explicitly rather than assume DictReader's
# default (treat line 1 as header), which would silently drop a real event
# and misalign every field into the wrong column.
CONTEXT_COLUMNS = [
    "EventID", "Symbol", "SchemaVersion", "LifecycleVersion", "RegistrationTime", "Direction", "RefPrice", "ATR_Ref",
    "SeedSource", "ImpulseStartTime", "ImpulseStartPrice", "ImpulseExtreme", "ImpulseSpanATR",
    "RetracementDepth", "LifecycleBars", "RegimeTrend", "RegimeVol", "RegimeStructure", "Session",
    "SpreadPoints", "DirEfficiency", "TrendPersistence", "SlopeNorm", "Displacement", "FinalizeReason",
]
# Schema v1 rows (pre TP_LIFECYCLE_V1 freeze, 2026-07-22) have no
# LifecycleVersion column -- 76 fields instead of 77. All such rows are
# already fully captured in TestEvidence/tp_forward_outcome_20260722/ and the
# live journals were rotated at the freeze, so this fallback exists only for
# reproducing that historical evidence from its original extracted slices.
CONTEXT_COLUMNS_SCHEMA_V1 = [c for c in CONTEXT_COLUMNS if c != "LifecycleVersion"]
HORIZON_COLUMNS = [
    suffix.format(h=h)
    for h in HORIZONS
    for suffix in (
        "{h}_MFE_ATR", "{h}_MAE_ATR", "{h}_CloseReturn_ATR",
        "{h}_Reached_p25", "{h}_Reached_p50", "{h}_Reached_p100",
        "{h}_ReachedNeg_p25", "{h}_ReachedNeg_p50", "{h}_ReachedNeg_p100",
        "{h}_FirstThreshold", "{h}_BarsToMFE", "{h}_BarsToMAE", "{h}_Status",
    )
]
TP_OUTCOME_COLUMNS = CONTEXT_COLUMNS + HORIZON_COLUMNS
TP_OUTCOME_COLUMNS_SCHEMA_V1 = CONTEXT_COLUMNS_SCHEMA_V1 + HORIZON_COLUMNS


def rows(path: Path, offset: int = 0, end_offset: int | None = None):
    lines = [line for line in decode(path, offset, end_offset).splitlines() if line.strip()]
    if not lines:
        return
    first = [cell.strip() for cell in next(csv.reader([lines[0]]))]
    headered = "EventID" in first and "H3_MFE_ATR" in first
    if headered:
        yield from csv.DictReader(lines)
        return
    for raw in csv.reader(lines):
        columns = TP_OUTCOME_COLUMNS if len(raw) == len(TP_OUTCOME_COLUMNS) else TP_OUTCOME_COLUMNS_SCHEMA_V1
        yield dict(zip(columns, raw))


def to_float(row: dict, key: str):
    value = row.get(key, "")
    if value in (None, ""):
        return None
    try:
        return float(value)
    except ValueError:
        return None


def shuffle_direction(row: dict) -> dict:
    """As if the opposite direction had been nominated for this same bar
    sequence: swap MFE<->MAE and Reached<->ReachedNeg, negate CloseReturn,
    and flip FAVORABLE<->ADVERSE -- exact mirrors of UpdatePending's own
    favorable/adverse formulas in TPOutcomeTracker.mqh. No new data."""
    shuffled = dict(row)
    shuffled["Direction"] = "down" if row.get("Direction") == "up" else "up"
    for h in HORIZONS:
        mfe_key, mae_key = f"{h}_MFE_ATR", f"{h}_MAE_ATR"
        shuffled[mfe_key], shuffled[mae_key] = row.get(mae_key), row.get(mfe_key)
        for suffix in ("p25", "p50", "p100"):
            pos_key, neg_key = f"{h}_Reached_{suffix}", f"{h}_ReachedNeg_{suffix}"
            shuffled[pos_key], shuffled[neg_key] = row.get(neg_key), row.get(pos_key)
        close_key = f"{h}_CloseReturn_ATR"
        close_return = to_float(row, close_key)
        shuffled[close_key] = "" if close_return is None else str(-close_return)
        first_key = f"{h}_FirstThreshold"
        flip = {"FAVORABLE": "ADVERSE", "ADVERSE": "FAVORABLE"}
        shuffled[first_key] = flip.get(row.get(first_key, ""), row.get(first_key, ""))
    return shuffled


def horizon_stats(entries: list[dict], horizon: str) -> dict:
    mfe = [v for v in (to_float(e, f"{horizon}_MFE_ATR") for e in entries) if v is not None]
    mae = [v for v in (to_float(e, f"{horizon}_MAE_ATR") for e in entries) if v is not None]
    complete = [e for e in entries if e.get(f"{horizon}_Status") == "COMPLETE"]
    truncated = [e for e in entries if e.get(f"{horizon}_Status") == "TRUNCATED"]
    close_returns = [v for v in (to_float(e, f"{horizon}_CloseReturn_ATR") for e in complete) if v is not None]
    thresholds = [e.get(f"{horizon}_FirstThreshold", "") for e in entries]
    resolved = [t for t in thresholds if t]
    favorable_first = sum(1 for t in resolved if t == "FAVORABLE")
    ambiguous = sum(1 for t in resolved if t == "AMBIGUOUS_SAME_BAR")

    def med(xs):
        return statistics.median(xs) if xs else None

    def mean(xs):
        return statistics.fmean(xs) if xs else None

    median_mfe, median_mae = med(mfe), med(mae)
    ratio = (median_mfe / median_mae) if (median_mfe is not None and median_mae not in (None, 0)) else None

    return {
        "n": len(entries),
        "n_complete": len(complete),
        "n_truncated": len(truncated),
        "median_mfe": median_mfe,
        "mean_mfe": mean(mfe),
        "median_mae": median_mae,
        "mean_mae": mean(mae),
        "median_close_return": med(close_returns),
        "mean_close_return": mean(close_returns),
        "fav_adv_ratio": ratio,
        "n_resolved_threshold": len(resolved),
        "target_before_adverse_rate": (favorable_first / len(resolved)) if resolved else None,
        "n_ambiguous_same_bar": ambiguous,
    }


def fmt(value, digits: int = 3) -> str:
    return "n/a" if value is None else f"{value:.{digits}f}"


def table(headers, body) -> str:
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    out.extend("| " + " | ".join(map(str, line)) + " |" for line in body)
    return "\n".join(out)


def report_group(label: str, entries: list[dict]) -> list[str]:
    lines = [f"### {label} (n={len(entries)} events)", ""]
    if not entries:
        lines.append("No events.")
        return lines
    body = []
    for horizon in HORIZONS:
        s = horizon_stats(entries, horizon)
        body.append([
            horizon, s["n"], s["n_complete"], s["n_truncated"],
            fmt(s["median_mfe"]), fmt(s["mean_mfe"]),
            fmt(s["median_mae"]), fmt(s["mean_mae"]),
            fmt(s["fav_adv_ratio"]),
            fmt(s["median_close_return"]), fmt(s["mean_close_return"]),
            s["n_resolved_threshold"],
            fmt(s["target_before_adverse_rate"], 2),
            s["n_ambiguous_same_bar"],
        ])
    lines.append(table(
        ["Horizon", "n", "n_complete", "n_truncated", "Median MFE", "Mean MFE",
         "Median MAE", "Mean MAE", "Fav/Adv ratio", "Median close-ret", "Mean close-ret",
         "n resolved", "Target-before-adverse rate", "n ambiguous"],
        body,
    ))
    if len(entries) < 10:
        lines.append("")
        lines.append(f"**Caution: n={len(entries)} is too small for statistical significance. Treat as descriptive only.**")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
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
    parser.add_argument(
        "--window", action="append", default=[], metavar="LABEL=FILE",
        help="Assign a window label to a file for per-window breakdown (repeatable). "
             "Defaults to the file's stem if not given.",
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

    window_labels = {}
    for spec in args.window:
        name, separator, label = spec.partition("=")
        if not separator:
            parser.error(f"invalid --window value: {spec}")
        window_labels[str(Path(name).resolve())] = label

    per_window: dict[str, list[dict]] = defaultdict(list)
    pooled: list[dict] = []
    for path in args.csv:
        resolved = str(path.resolve())
        offset = offsets.get(resolved, 0)
        end_offset = end_offsets.get(resolved)
        label = window_labels.get(resolved, path.stem)
        for row in rows(path, offset, end_offset):
            per_window[label].append(row)
            pooled.append(row)

    report = [
        "# TP resume-candidate forward outcome report",
        "",
        f"Input journals: {len(args.csv)}",
        f"Windows: {', '.join(sorted(per_window)) if per_window else 'none'}",
        f"Total events (pooled): {len(pooled)}",
        "",
        "Horizons (3/6/12/24 completed M5 bars) and thresholds (+-0.25/0.50/1.00 ATR) were "
        "declared before any evidence was collected and are not re-chosen here.",
        "",
        "## Pooled -- TP resume_candidate events",
        "",
    ]
    report.extend(report_group("Pooled", pooled))

    report.extend(["", "## Per-window -- TP resume_candidate events", ""])
    for label in sorted(per_window):
        report.extend(report_group(label, per_window[label]))
        report.append("")

    shuffled_pooled = [shuffle_direction(row) for row in pooled]
    report.extend([
        "", "## Baseline B: direction-shuffled TP events (pooled)", "",
        "Pure post-hoc relabeling of the same bars as if the opposite direction had been "
        "nominated (MFE<->MAE, Reached<->ReachedNeg, FirstThreshold flipped, CloseReturn "
        "negated). No new data; a sanity baseline only, not an independent sample.", "",
    ])
    report.extend(report_group("Direction-shuffled pooled", shuffled_pooled))

    single_window = len(per_window) <= 1
    single_event = len(pooled) <= 1
    report.extend([
        "",
        "## Effect-direction-by-window check",
        "",
        "Whether any pooled effect depends on a single window or a single event:",
        "",
        f"- Windows contributing events: {len(per_window)}"
        + (" (SINGLE WINDOW -- any effect cannot be attributed to more than one window)" if single_window else ""),
        f"- Total events: {len(pooled)}"
        + (" (SINGLE EVENT -- any effect cannot be attributed to more than one observation)" if single_event else ""),
        "",
        "## Baselines A/C/D (random bars, trend-direction-without-lifecycle, non-resuming impulse)",
        "",
        "Not computed by this script -- they require forward OHLC at arbitrary non-"
        "resume_candidate anchor bars, which this journal does not carry. See the evidence "
        "README for the chart-history retrieval attempt per window.",
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
