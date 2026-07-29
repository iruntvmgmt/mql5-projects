#!/usr/bin/env python3
"""Deterministic D028 Stage 3 single-book equivalence audit."""

from __future__ import annotations

import argparse
import csv
import hashlib
from datetime import datetime
from pathlib import Path

WINDOWS = (
    ("Development", datetime(2025, 3, 1), datetime(2026, 1, 1)),
    ("Validation", datetime(2026, 1, 1), datetime(2026, 5, 1)),
    ("Final holdout", datetime(2026, 5, 1), datetime(2026, 7, 25)),
    ("Full window", datetime(2025, 3, 1), datetime(2026, 7, 25)),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--results", type=Path,
        default=Path("/Users/matt/MT5-MSZZ-TEST/D028_Stage3_Results"))
    parser.add_argument(
        "--stage0b", type=Path,
        default=Path("/Users/matt/MT5-MSZZ-TEST/D028_Stage0B_Results"))
    parser.add_argument(
        "--d026", type=Path,
        default=Path("/Users/matt/MT5-MSZZ-TEST/D026_Results"))
    parser.add_argument("--output", type=Path, default=Path(__file__).parent)
    return parser.parse_args()


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle, delimiter=";"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def metric(rows: list[dict[str, str]]) -> dict[str, object]:
    results = [float(row["r_result"]) for row in rows]
    cumulative = sum(results)
    positive = sum(value for value in results if value > 0)
    negative = -sum(value for value in results if value < 0)
    equity = peak = drawdown = 0.0
    for value in results:
        equity += value
        peak = max(peak, equity)
        drawdown = max(drawdown, peak - equity)
    return {
        "trades": len(rows),
        "cumulative_r": cumulative,
        "expectancy_r": cumulative / len(rows) if rows else 0.0,
        "profit_factor_r": positive / negative if negative else 0.0,
        "max_drawdown_r": drawdown,
        "long_trades": sum(row["direction"] == "LONG" for row in rows),
        "short_trades": sum(row["direction"] == "SHORT" for row in rows),
        "first_entry_time": rows[0]["fill_time"] if rows else "",
        "last_exit_time": rows[-1]["close_time"] if rows else "",
    }


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    runs = (
        ("A_2R", args.results / "A_2R",
         args.stage0b / "B0_A_2R"),
        ("E_3R", args.results / "E_3R",
         args.d026 / "baselineE_canonical3r"),
        ("SweepReclaim_2R", args.results / "SweepReclaim_2R",
         args.stage0b / "B1_SweepReclaim_2R"),
    )

    equivalence: list[dict[str, object]] = []
    windows: list[dict[str, object]] = []
    audit: list[dict[str, object]] = []
    for name, result_dir, baseline_dir in runs:
        result_path = result_dir / "MSZZ_TradeAnalytics.csv"
        baseline_path = baseline_dir / "MSZZ_TradeAnalytics.csv"
        portfolio_path = result_dir / "MSZZ_PortfolioTradeAnalytics.csv"
        for required in (result_path, baseline_path, portfolio_path,
                         result_dir / "MSZZ_RunSummary.csv",
                         result_dir / "MSZZ_StrategyBookJournal.csv",
                         result_dir / "MSZZ_PortfolioRiskJournal.csv"):
            if not required.is_file() or required.stat().st_size == 0:
                raise SystemExit(f"missing or empty required artifact: {required}")
        result_rows = read_rows(result_path)
        baseline_rows = read_rows(baseline_path)
        portfolio_rows = read_rows(portfolio_path)
        byte_equal = result_path.read_bytes() == baseline_path.read_bytes()
        row_equal = result_rows == baseline_rows
        if not byte_equal or not row_equal:
            raise SystemExit(f"{name}: trade analytics are not exactly equivalent")
        if len(portfolio_rows) != len(result_rows):
            raise SystemExit(f"{name}: portfolio trade journal count mismatch")
        summary = metric(result_rows)
        equivalence.append({
            "run": name,
            "baseline_path": str(baseline_path),
            "result_path": str(result_path),
            "baseline_sha256": sha256(baseline_path),
            "result_sha256": sha256(result_path),
            "byte_identical": "true",
            **summary,
        })
        result_ids = [row["cluster_id"] for row in result_rows]
        portfolio_ids = [row["logical_position_id"] for row in portfolio_rows]
        direction_mismatches = sum(
            left["direction"] != right["direction"]
            for left, right in zip(result_rows, portfolio_rows))
        entry_time_mismatches = sum(
            left["fill_time"] != right["entry_time"]
            for left, right in zip(result_rows, portfolio_rows))
        exit_time_mismatches = sum(
            left["close_time"] != right["exit_time"]
            for left, right in zip(result_rows, portfolio_rows))
        max_abs_r_difference = max(
            (abs(float(left["r_result"]) - float(right["realized_r"]))
             for left, right in zip(result_rows, portfolio_rows)),
            default=0.0)
        audit.append({
            "run": name,
            "trade_rows": len(result_rows),
            "portfolio_trade_rows": len(portfolio_rows),
            "unique_trade_ids": len(set(result_ids)),
            "unique_portfolio_ids": len(set(portfolio_ids)),
            "missing_portfolio_ids": len(set(result_ids) - set(portfolio_ids)),
            "unexpected_portfolio_ids": len(set(portfolio_ids) - set(result_ids)),
            "duplicate_trade_ids": len(result_ids) - len(set(result_ids)),
            "duplicate_portfolio_ids": len(portfolio_ids) - len(set(portfolio_ids)),
            "direction_mismatches": direction_mismatches,
            "entry_time_mismatches": entry_time_mismatches,
            "exit_time_mismatches": exit_time_mismatches,
            "max_abs_r_difference": max_abs_r_difference,
            "status": "PASS" if (
                result_ids == portfolio_ids and direction_mismatches == 0
                and entry_time_mismatches == 0 and exit_time_mismatches == 0
                and max_abs_r_difference <= 0.0001
            ) else "FAIL",
        })
        if audit[-1]["status"] != "PASS":
            raise SystemExit(f"{name}: logical trade attribution mismatch")

        for window, start, end in WINDOWS:
            selected = [
                row for row in result_rows
                if start <= datetime.strptime(row["fill_time"], "%Y.%m.%d %H:%M:%S") < end
            ]
            windows.append({"run": name, "window": window, **metric(selected)})

    eq_fields = list(equivalence[0])
    window_fields = list(windows[0])
    audit_fields = list(audit[0])
    write_csv(args.output / "single_book_equivalence.csv", eq_fields, equivalence)
    write_csv(args.output / "single_book_window_summary.csv", window_fields, windows)
    write_csv(args.output / "single_book_join_audit.csv", audit_fields, audit)

    findings = [
        "# D028 Stage 3 — Single-Book Equivalence",
        "",
        "All three active single-book runs are byte-identical to their certified controls.",
        "",
        "| Run | Trades | Cumulative R | Expectancy R | PF | Max DD R | Long | Short |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in equivalence:
        findings.append(
            f"| {row['run']} | {row['trades']} | {row['cumulative_r']:.4f} | "
            f"{row['expectancy_r']:.4f} | {row['profit_factor_r']:.4f} | "
            f"{row['max_drawdown_r']:.4f} | {row['long_trades']} | "
            f"{row['short_trades']} |")
    findings += [
        "",
        "Every portfolio logical-position ID matches the corresponding certified",
        "trade cluster ID in chronological order. There are no missing, unexpected,",
        "or duplicate logical trades.",
        "",
        "No combined strategy configuration was run. Stage 4 remains blocked until",
        "this Stage 3 checkpoint is committed and pushed.",
        "",
    ]
    (args.output / "stage3_findings.md").write_text(
        "\n".join(findings), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
