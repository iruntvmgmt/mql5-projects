#!/usr/bin/env python3
"""
QuantBeast journal gap-map report.

Reads tagged SignalJournal / CounterfactualJournal CSVs and summarizes:
  - family/template coverage
  - accepted vs rejected rows
  - top rejection reasons
  - template overlap hints within each family

The script is intentionally lightweight and dependency-free so it can run
directly against tester exports in the Common/Files/QuantBeast/Tester path.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Dict, Tuple


@dataclass
class Row:
    source: str
    strategy: str
    direction: str
    accepted: bool
    rejection_reason: str
    family: str
    template: str
    tags: str
    row: dict


def infer_family(strategy: str) -> str:
    mapping = {
        "BO": "breakout",
        "FBO": "failed_breakout",
        "TP": "trend_pullback",
        "MR": "mean_reversion",
    }
    return mapping.get(strategy, "unknown")


def infer_template(strategy: str) -> str:
    mapping = {
        "BO": "range_breakout",
        "FBO": "reclaim_reversal",
        "TP": "pullback_resume",
        "MR": "value_reversion",
    }
    return mapping.get(strategy, "unknown")


def read_rows(path: Path) -> List[Row]:
    text = path.read_text(encoding="utf-16")
    reader = csv.DictReader(text.splitlines())
    rows: List[Row] = []
    for raw in reader:
        strategy = raw.get("Strategy", "").strip()
        family = (raw.get("StrategyFamily") or "").strip() or infer_family(strategy)
        template = (raw.get("StrategyTemplate") or "").strip() or infer_template(strategy)
        tags = (raw.get("StrategyTags") or "").strip()
        accepted = (raw.get("Accepted") or "").strip().upper() == "ACCEPTED"
        rows.append(
            Row(
                source=path.name,
                strategy=strategy,
                direction=(raw.get("Direction") or "").strip(),
                accepted=accepted,
                rejection_reason=(raw.get("RejectionReason") or "").strip(),
                family=family,
                template=template,
                tags=tags,
                row=raw,
            )
        )
    return rows


def md_table(headers: List[str], rows: Iterable[Iterable[str]]) -> str:
    lines = ["| " + " | ".join(headers) + " |"]
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
    for row in rows:
      lines.append("| " + " | ".join(row) + " |")
    return "\n".join(lines)


def summarize(rows: List[Row]) -> str:
    by_family: Dict[str, Counter] = defaultdict(Counter)
    by_template: Dict[Tuple[str, str], Counter] = defaultdict(Counter)
    reasons: Counter = Counter()
    tag_sets: Dict[Tuple[str, str], set] = defaultdict(set)

    for r in rows:
        key = (r.family, r.template)
        by_family[r.family]["rows"] += 1
        by_family[r.family]["accepted"] += int(r.accepted)
        by_family[r.family]["rejected"] += int(not r.accepted)
        by_template[key]["rows"] += 1
        by_template[key]["accepted"] += int(r.accepted)
        by_template[key]["rejected"] += int(not r.accepted)
        if r.rejection_reason:
            reasons[r.rejection_reason] += 1
        if r.tags:
            tag_sets[key].add(r.tags)

    parts: List[str] = []
    parts.append("# QuantBeast gap-map report")
    parts.append("")
    parts.append(f"Rows analyzed: {len(rows)}")
    parts.append("")

    family_rows = []
    for family in sorted(by_family):
        c = by_family[family]
        family_rows.append([
            family,
            str(c["rows"]),
            str(c["accepted"]),
            str(c["rejected"]),
        ])
    parts.append("## Coverage by family")
    parts.append("")
    parts.append(md_table(["Family", "Rows", "Accepted", "Rejected"], family_rows))
    parts.append("")

    template_rows = []
    for (family, template) in sorted(by_template):
        c = by_template[(family, template)]
        template_rows.append([
            family,
            template,
            str(c["rows"]),
            str(c["accepted"]),
            str(c["rejected"]),
        ])
    parts.append("## Coverage by template")
    parts.append("")
    parts.append(md_table(["Family", "Template", "Rows", "Accepted", "Rejected"], template_rows))
    parts.append("")

    if reasons:
        reason_rows = [[reason, str(count)] for reason, count in reasons.most_common(10)]
        parts.append("## Top rejection reasons")
        parts.append("")
        parts.append(md_table(["Rejection reason", "Count"], reason_rows))
        parts.append("")

    overlap_rows = []
    for family in sorted(by_family):
        templates = sorted({template for (fam, template) in by_template if fam == family})
        if len(templates) > 1:
            overlap_rows.append([family, ", ".join(templates)])
    parts.append("## Template overlap hints")
    parts.append("")
    if overlap_rows:
        parts.append(md_table(["Family", "Templates"], overlap_rows))
    else:
        parts.append("No multi-template family overlap detected in the analyzed rows.")
    parts.append("")

    tag_rows = []
    for key, tags in sorted(tag_sets.items()):
        if len(tags) > 1:
            tag_rows.append([key[0], key[1], str(len(tags))])
    parts.append("## Tag cardinality hints")
    parts.append("")
    if tag_rows:
        parts.append(md_table(["Family", "Template", "Distinct tags"], tag_rows))
    else:
        parts.append("Each analyzed family/template combination used a single tag string in this sample.")
    parts.append("")

    return "\n".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", nargs="+", type=Path, help="Tagged journal CSVs to analyze")
    ap.add_argument("-o", "--output", type=Path, help="Write report to a file instead of stdout")
    args = ap.parse_args()

    rows: List[Row] = []
    for path in args.csv:
        rows.extend(read_rows(path))

    report = summarize(rows)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding="utf-8")
    else:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
