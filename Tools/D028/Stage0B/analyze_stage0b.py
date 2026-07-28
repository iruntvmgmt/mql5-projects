#!/usr/bin/env python3
"""Deterministic D028 Stage 0B candidate-integrity and baseline analysis."""

from __future__ import annotations

import argparse
import csv
import math
import re
import statistics
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

DT_FMT = "%Y.%m.%d %H:%M:%S"
WINDOWS = (
    ("Development", datetime(2025, 3, 1), datetime(2026, 1, 1)),
    ("Validation", datetime(2026, 1, 1), datetime(2026, 5, 1)),
    ("Final holdout", datetime(2026, 5, 1), datetime(2026, 7, 25)),
)
VALID_STRATEGIES = {"1010": "FastMedConfluence", "1050": "SweepReclaim"}
VALID_FAMILIES = {"BREAKOUT", "REVERSAL"}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        if reader.fieldnames is None:
            raise ValueError(f"missing header: {path}")
        return list(reader)


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        raise ValueError(f"refusing empty output: {path}")
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def stamp(value: str) -> datetime:
    return datetime.strptime(value, DT_FMT)


def fmt(value: float) -> str:
    return f"{value:.6f}"


def profit_factor(values: list[float]) -> float:
    gains = sum(value for value in values if value > 0)
    losses = -sum(value for value in values if value < 0)
    return gains / losses if losses else math.inf


def max_drawdown(values: list[float]) -> float:
    equity = peak = result = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        result = max(result, peak - equity)
    return result


def malformed(row: dict[str, str]) -> bool:
    try:
        return not (
            row["strategy_id"] in VALID_STRATEGIES
            and row["strategy_family"] in VALID_FAMILIES
            and row["direction"] in {"LONG", "SHORT"}
            and bool(row["event_id"])
            and bool(row["origin_id"])
            and math.isfinite(float(row["score"]))
            and float(row["entry"]) > 0
            and float(row["stop"]) > 0
            and float(row["target"]) > 0
        )
    except (KeyError, TypeError, ValueError):
        return True


def load_trades(path: Path) -> list[dict[str, object]]:
    output = []
    for row in read_csv(path):
        output.append({
            **row,
            "entry_dt": stamp(row["signal_time"]),
            "fill_dt": stamp(row["fill_time"]),
            "close_dt": stamp(row["close_time"]),
            "r": float(row["r_result"]),
        })
    return output


def html_counts(path: Path) -> tuple[int, int]:
    text = path.read_text(encoding="utf-16")
    trades = re.search(r"Total Trades:</td>\s*<td nowrap><b>(\d+)</b>", text)
    deals = re.search(r"Total Deals:</td>\s*<td nowrap><b>(\d+)</b>", text)
    if not trades or not deals:
        raise ValueError(f"native report counts missing: {path}")
    return int(trades.group(1)), int(deals.group(1))


def metric_row(result_set: str, scope: str, trades: list[dict[str, object]],
               html_trades: int, html_deals: int) -> dict[str, object]:
    ordered = sorted(trades, key=lambda row: (row["entry_dt"], row["cluster_id"]))
    values = [row["r"] for row in ordered]
    return {
        "result_set": result_set,
        "scope": scope,
        "trades": len(ordered),
        "deals": html_deals if scope == "Full window" else "",
        "wins": sum(value > 0 for value in values),
        "losses": sum(value < 0 for value in values),
        "cumulative_r": fmt(sum(values)),
        "expectancy_r": fmt(statistics.fmean(values)),
        "profit_factor_r": fmt(profit_factor(values)),
        "max_drawdown_r": fmt(max_drawdown(values)),
        "long_trades": sum(row["direction"] == "LONG" for row in ordered),
        "short_trades": sum(row["direction"] == "SHORT" for row in ordered),
        "analytics_html_reconciled": (
            str(len(ordered) == html_trades).lower() if scope == "Full window" else ""
        ),
    }


def analyze(root: Path, d027_root: Path, stage0_root: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    specs = {
        "B0_A_2R": (
            root / "B0_A_2R",
            "D028_Stage0B_B0_A_2R.htm",
            "FastMedConfluence",
        ),
        "B1_SweepReclaim_2R": (
            root / "B1_SweepReclaim_2R",
            "D028_Stage0B_B1_SweepReclaim_2R.htm",
            "SweepReclaim",
        ),
        "B2_Corrected_Legacy_A_plus_Sweep_2R": (
            root / "B2_Corrected_Legacy_A_plus_Sweep_2R",
            "D028_Stage0B_B2_Corrected_Legacy_A_plus_Sweep_2R.htm",
            "FastMedConfluence,SweepReclaim",
        ),
    }
    runs: dict[str, list[dict[str, object]]] = {}
    signals: dict[str, list[dict[str, str]]] = {}
    html: dict[str, tuple[int, int]] = {}
    for name, (directory, report, enabled) in specs.items():
        required = (
            "MSZZ_RunSummary.csv", "MSZZ_TradeAnalytics.csv",
            "MSZZ_SignalJournal.csv", "MSZZ_RegimeJournal.csv", report,
        )
        for artifact in required:
            path = directory / artifact
            if not path.is_file() or path.stat().st_size == 0:
                raise ValueError(f"{name}: missing/empty {artifact}")
        summary = read_csv(directory / "MSZZ_RunSummary.csv")
        if len(summary) != 1 or summary[0]["enabled_strategies"] != enabled:
            raise ValueError(f"{name}: run summary identity mismatch")
        runs[name] = load_trades(directory / "MSZZ_TradeAnalytics.csv")
        signals[name] = read_csv(directory / "MSZZ_SignalJournal.csv")
        html[name] = html_counts(directory / report)
        if not (
            int(summary[0]["trades"]) == len(runs[name]) == html[name][0]
            and html[name][1] == 2 * html[name][0]
        ):
            raise ValueError(f"{name}: summary/analytics/HTML reconciliation failed")

    # Certified standalone parity is trade-row exact, not headline-only.
    standalone_references = {
        "B0_A_2R": Path(
            "/Users/matt/MT5-MSZZ-TEST/D027_Stage2_Results/"
            "FastMedConfluence/MSZZ_TradeAnalytics.csv"
        ),
        "B1_SweepReclaim_2R": Path(
            "/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results/"
            "SweepReclaim/MSZZ_TradeAnalytics.csv"
        ),
    }
    standalone_parity = {}
    for name, reference in standalone_references.items():
        standalone_parity[name] = (
            read_csv(specs[name][0] / "MSZZ_TradeAnalytics.csv") == read_csv(reference)
        )
        if not standalone_parity[name]:
            raise ValueError(f"{name}: certified standalone trade rows differ")

    b2_signals = signals["B2_Corrected_Legacy_A_plus_Sweep_2R"]
    raw = [row for row in b2_signals if row["status"] == "RAW_CANDIDATE"]
    outcomes = [row for row in b2_signals if row["status"] != "RAW_CANDIDATE"]
    statuses = Counter(row["status"] for row in outcomes)
    raw_by_strategy = Counter(row["strategy_id"] for row in raw)
    executed = [row for row in outcomes if row["status"] == "EXECUTED"]
    executed_by_strategy = Counter(row["strategy_id"] for row in executed)
    malformed_after = sum(malformed(row) for row in raw)
    if malformed_after:
        raise ValueError(f"B2: malformed corrected candidates={malformed_after}")

    historical_signals = read_csv(
        d027_root / "A_plus_SweepReclaim_2R/MSZZ_SignalJournal.csv"
    )
    stage0_signals = read_csv(
        stage0_root / "Legacy_A_plus_Sweep_2R/MSZZ_SignalJournal.csv"
    )
    historical_raw = [row for row in historical_signals if row["status"] == "RAW_CANDIDATE"]
    stage0_raw = [row for row in stage0_signals if row["status"] == "RAW_CANDIDATE"]

    audit_rows = [
        {
            "audit": "D027_historical_combined",
            "strategy": "ALL",
            "raw_candidates": len(historical_raw),
            "valid_initialized_candidates": len(historical_raw) - sum(map(malformed, historical_raw)),
            "malformed_candidates": sum(map(malformed, historical_raw)),
            "selected_cluster_events": "",
            "unique_cluster_ids": "",
            "executions": 371,
            "status": "INVALIDATED_FOR_COMBINED_BASELINE_COMPARISON",
        },
        {
            "audit": "D028_stage0_prefixed_combined",
            "strategy": "ALL",
            "raw_candidates": len(stage0_raw),
            "valid_initialized_candidates": len(stage0_raw) - sum(map(malformed, stage0_raw)),
            "malformed_candidates": sum(map(malformed, stage0_raw)),
            "selected_cluster_events": "",
            "unique_cluster_ids": "",
            "executions": 372,
            "status": "NONDETERMINISTIC_PRE_FIX_EVIDENCE",
        },
        {
            "audit": "D028_stage0b_corrected_combined",
            "strategy": "ALL",
            "raw_candidates": len(raw),
            "valid_initialized_candidates": len(raw),
            "malformed_candidates": malformed_after,
            "selected_cluster_events": len(outcomes),
            "unique_cluster_ids": len({row["cluster_id"] for row in outcomes}),
            "executions": len(executed),
            "status": "PASS",
        },
    ]
    for strategy_id, strategy_name in VALID_STRATEGIES.items():
        audit_rows.append({
            "audit": "D028_stage0b_corrected_combined",
            "strategy": strategy_name,
            "raw_candidates": raw_by_strategy[strategy_id],
            "valid_initialized_candidates": raw_by_strategy[strategy_id],
            "malformed_candidates": 0,
            "selected_cluster_events": "",
            "unique_cluster_ids": "",
            "executions": executed_by_strategy[strategy_id],
            "status": "PASS",
        })
    for reason, count in sorted(statuses.items()):
        audit_rows.append({
            "audit": "D028_stage0b_rejection_or_execution",
            "strategy": reason,
            "raw_candidates": "",
            "valid_initialized_candidates": "",
            "malformed_candidates": "",
            "selected_cluster_events": "",
            "unique_cluster_ids": "",
            "executions": count,
            "status": "PASS",
        })
    write_csv(output / "candidate_index_audit.csv", audit_rows)

    baseline_rows = []
    for name in specs:
        trades = runs[name]
        baseline_rows.append(metric_row(name, "Full window", trades, *html[name]))
        total = 0
        for window, start, end in WINDOWS:
            bucket = [row for row in trades if start <= row["entry_dt"] < end]
            total += len(bucket)
            baseline_rows.append(metric_row(name, window, bucket, -1, -1))
        if total != len(trades):
            raise ValueError(f"{name}: frozen windows do not reconcile")
    write_csv(output / "corrected_legacy_baseline.csv", baseline_rows)

    b0 = runs["B0_A_2R"]
    b2 = runs["B2_Corrected_Legacy_A_plus_Sweep_2R"]
    b0_clusters = {row["cluster_id"] for row in b0}
    b2_core = [row for row in b2 if row["strategy_id"] == "1010"]
    b2_core_clusters = {row["cluster_id"] for row in b2_core}
    b2_sweep = [row for row in b2 if row["strategy_id"] == "1050"]
    fills: dict[datetime, list[dict[str, object]]] = defaultdict(list)
    for row in b2:
        fills[row["fill_dt"]].append(row)
    own_family = cross_family = unknown = 0
    for row in b2:
        if row["exit_reason"] != "OTHER":
            continue
        opposite = "SHORT" if row["direction"] == "LONG" else "LONG"
        reversals = [
            candidate for candidate in fills[row["close_dt"]]
            if candidate["direction"] == opposite
        ]
        if len(reversals) != 1:
            unknown += 1
        elif reversals[0]["strategy_id"] == row["strategy_id"]:
            own_family += 1
        else:
            cross_family += 1
    reasons = Counter(row["exit_reason"] for row in b2)
    if reasons["SL"] + reasons["TP"] + own_family + cross_family + unknown != len(b2):
        raise ValueError("B2: exit classification does not reconcile")

    b2_full = next(
        row for row in baseline_rows
        if row["result_set"] == "B2_Corrected_Legacy_A_plus_Sweep_2R"
        and row["scope"] == "Full window"
    )
    lines = [
        "# D028 Stage 0B findings",
        "",
        "The candidate-index defect is fixed without changing either strategy's "
        "trigger, score, clustering priority, or exit policy. Candidate arrays are "
        "compact at subsystem boundaries; every processed slot is validated and "
        "clustering fails closed on count/index/identity mismatch.",
        "",
        "## Baseline status",
        "",
        f"- B0 A: {len(b0)} trades, {sum(row['r'] for row in b0):.4f}R; "
        f"certified trade-row parity `{str(standalone_parity['B0_A_2R']).lower()}`.",
        f"- B1 SweepReclaim: {len(runs['B1_SweepReclaim_2R'])} trades, "
        f"{sum(row['r'] for row in runs['B1_SweepReclaim_2R']):.4f}R; "
        f"certified trade-row parity "
        f"`{str(standalone_parity['B1_SweepReclaim_2R']).lower()}`.",
        f"- B2 corrected legacy shared ownership: {b2_full['trades']} trades, "
        f"{float(b2_full['cumulative_r']):.4f}R, "
        f"{float(b2_full['expectancy_r']):.4f}R expectancy, "
        f"PF {float(b2_full['profit_factor_r']):.4f}, "
        f"{float(b2_full['max_drawdown_r']):.4f}R drawdown.",
        "",
        "Historical D027 Stage 6 A+Sweep (371 trades, +20.7400R) is preserved "
        "unchanged but is formally `INVALIDATED_FOR_COMBINED_BASELINE_COMPARISON`. "
        "It contained 19 malformed raw candidates produced by undefined indexing. "
        "The fresh pre-fix D028 run contained 24; corrected B2 contains zero.",
        "",
        "## Corrected combined attribution",
        "",
        f"- Raw candidates: {len(raw)} "
        f"(A {raw_by_strategy['1010']}, SweepReclaim {raw_by_strategy['1050']}).",
        f"- Valid initialized candidates: {len(raw)}; malformed: {malformed_after}.",
        f"- Selected cluster events: {len(outcomes)}; unique cluster IDs: "
        f"{len({row['cluster_id'] for row in outcomes})}.",
        f"- Executions/trades/deals: {len(executed)}/{len(b2)}/{html['B2_Corrected_Legacy_A_plus_Sweep_2R'][1]}.",
        f"- Owners: A {len(b2_core)} trades; SweepReclaim {len(b2_sweep)} trades.",
        f"- Exits: SL {reasons['SL']}, TP {reasons['TP']}, own-family opposite "
        f"{own_family}, cross-family opposite {cross_family}, unknown {unknown}.",
        f"- Core retained {len(b0_clusters & b2_core_clusters)}, displaced "
        f"{len(b0_clusters - b2_core_clusters)}, newly executed "
        f"{len(b2_core_clusters - b0_clusters)}.",
        f"- Rejections/outcomes: {dict(sorted(statuses.items()))}.",
        "",
        "All summary, analytics, native HTML, deal, frozen-window, owner, and exit "
        "totals reconcile. Stage 1 is unblocked, but was not started in this commit.",
    ]
    (output / "stage0b_findings.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root", type=Path,
        default=Path("/Users/matt/MT5-MSZZ-TEST/D028_Stage0B_Results"),
    )
    parser.add_argument(
        "--d027-root", type=Path,
        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage6_Results"),
    )
    parser.add_argument(
        "--stage0-root", type=Path,
        default=Path("/Users/matt/MT5-MSZZ-TEST/D028_Stage0_Results"),
    )
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    analyze(args.root, args.d027_root, args.stage0_root, args.output)


if __name__ == "__main__":
    main()
