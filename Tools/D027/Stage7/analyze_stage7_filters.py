#!/usr/bin/env python3
"""Deterministic D027 Stage 7 frozen regime-filter analysis."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import re
import statistics
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

DT = "%Y.%m.%d %H:%M:%S"
WINDOWS = (
    ("Development", datetime(2025, 3, 1), datetime(2026, 1, 1)),
    ("Validation", datetime(2026, 1, 1), datetime(2026, 5, 1)),
    ("Final holdout", datetime(2026, 5, 1), datetime(2026, 7, 25)),
)
SPECS = {
    "AlignedFastPullback": ("1031", "PULLBACK", "26072951"),
    "BreakoutRetest": ("1040", "RETEST", "26072952"),
    "SweepReclaim": ("1050", "REVERSAL", "26072953"),
    "CompressionBreakout": ("1060", "COMPRESSION", "26072954"),
    "StructureTransition": ("1070", "REVERSAL", "26072955"),
}
RAW_FIELDS = (
    "time", "symbol", "timeframe", "strategy_id", "setup", "direction",
    "score", "entry", "stop", "target", "origin_id", "event_id", "reason",
    "strategy_family", "regime_snapshot_id", "regime_direction",
    "regime_strength", "regime_volatility", "regime_alignment", "regime_phase",
)


def read_csv(path: Path, allow_missing: bool = False) -> list[dict[str, str]]:
    if allow_missing and not path.exists():
        return []
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        if reader.fieldnames is None:
            raise ValueError(f"missing header: {path}")
        return list(reader)


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        raise ValueError(f"empty output: {path}")
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def parse_ini(path: Path) -> dict[str, str]:
    output = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith(";"):
            key, value = line.split("=", 1)
            output[key] = value.split("||", 1)[0]
    return output


def html_counts(path: Path) -> tuple[int, int]:
    text = path.read_text(encoding="utf-16")
    values = []
    for label in ("Total Trades:", "Total Deals:"):
        match = re.search(re.escape(label) + r"</td>\s*<td nowrap><b>(\d+)</b>", text)
        if not match:
            raise ValueError(f"missing {label}: {path}")
        values.append(int(match.group(1)))
    return values[0], values[1]


def load_trades(path: Path) -> list[dict]:
    output = []
    for row in read_csv(path, allow_missing=True):
        output.append({
            **row,
            "entry_dt": datetime.strptime(row["signal_time"], DT),
            "close_dt": datetime.strptime(row["close_time"], DT),
            "r": float(row["r_result"]),
        })
    return output


def pf(values: list[float]) -> float:
    gains = sum(value for value in values if value > 0)
    losses = -sum(value for value in values if value < 0)
    return math.inf if gains and not losses else (gains / losses if losses else 0.0)


def max_dd(rows: list[dict]) -> float:
    equity = peak = worst = 0.0
    for row in sorted(rows, key=lambda item: (item["entry_dt"], item["cluster_id"])):
        equity += row["r"]
        peak = max(peak, equity)
        worst = max(worst, peak - equity)
    return worst


def fmt(value: float) -> str:
    return "inf" if math.isinf(value) else f"{value:.6f}"


def metrics(strategy: str, mode: str, scope: str, rows: list[dict]) -> dict[str, object]:
    values = [row["r"] for row in rows]
    longs = [row["r"] for row in rows if row["direction"] == "LONG"]
    shorts = [row["r"] for row in rows if row["direction"] == "SHORT"]
    return {
        "strategy": strategy, "mode": mode, "scope": scope, "trades": len(rows),
        "wins": sum(value > 0 for value in values),
        "losses": sum(value < 0 for value in values),
        "win_rate": fmt(sum(value > 0 for value in values) / len(values)) if values else "",
        "cumulative_r": fmt(sum(values)), "expectancy_r": fmt(statistics.fmean(values)) if values else "",
        "profit_factor_r": fmt(pf(values)) if values else "",
        "max_drawdown_r": fmt(max_dd(rows)),
        "long_trades": len(longs),
        "long_expectancy_r": fmt(statistics.fmean(longs)) if longs else "",
        "short_trades": len(shorts),
        "short_expectancy_r": fmt(statistics.fmean(shorts)) if shorts else "",
        "first_entry_time": min((row["entry_dt"] for row in rows), default=None).strftime(DT) if rows else "",
        "last_exit_time": max((row["close_dt"] for row in rows), default=None).strftime(DT) if rows else "",
    }


def outliers(strategy: str, mode: str, rows: list[dict]) -> dict[str, object]:
    values = sorted((row["r"] for row in rows), reverse=True)
    quarters: dict[str, float] = defaultdict(float)
    for row in rows:
        quarter = (row["entry_dt"].month - 1) // 3 + 1
        quarters[f"{row['entry_dt'].year}-Q{quarter}"] += row["r"]
    best_name, best_value = max(quarters.items(), key=lambda item: (item[1], item[0])) if quarters else ("", 0.0)
    return {
        "strategy": strategy, "mode": mode, "trades": len(rows),
        "cumulative_r": fmt(sum(values)),
        "excluding_best_trade_r": fmt(sum(values) - sum(values[:1])),
        "excluding_top_three_trades_r": fmt(sum(values) - sum(values[:3])),
        "best_quarter": best_name, "best_quarter_r": fmt(best_value),
        "excluding_best_quarter_r": fmt(sum(values) - best_value),
        "positive_quarters": sum(value > 0 for value in quarters.values()),
        "negative_quarters": sum(value < 0 for value in quarters.values()),
    }


def analyze(stage4: Path, stage7: Path, configs: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    config_rows, trigger_rows, status_rows, join_rows = [], [], [], []
    summary_rows, window_rows, outlier_rows, path_rows = [], [], [], []
    all_runs: dict[tuple[str, str], list[dict]] = {}

    for strategy, (strategy_id, family, magic) in SPECS.items():
        config_name = f"d027_stage7_{strategy}_Filter.ini"
        config = parse_ini(configs / config_name)
        enabled = [key for key, value in config.items()
                   if key.startswith("InpEnable") and value == "true"]
        expected_enable = f"InpEnable{strategy}"
        config_ok = (
            enabled == [expected_enable] and config.get("InpMagic") == magic
            and config.get("InpRegimeEligibilityMode") == "1"
            and config.get("InpRiskReward") == "2.0"
            and config.get("Symbol") == "XAUUSD" and config.get("Period") == "M5"
            and config.get("Model") == "2" and config.get("FromDate") == "2025.03.01"
            and config.get("ToDate") == "2026.07.24"
            and config.get("InpResearchMinScoreOverride") == "0.0"
            and config.get("InpEnableResearchTrail") == "false"
            and config.get("InpPartialCloseAtR") == "0.0"
            and config.get("InpDisableFixedTarget") == "false")
        if not config_ok:
            raise ValueError(f"{strategy}: config integrity")
        config_rows.append({
            "strategy": strategy, "strategy_id": strategy_id, "family": family,
            "magic": magic, "enabled_input": expected_enable,
            "research_filter": "true", "other_research_features_off": "true",
            "status": "PASS",
        })

        control_dir, filtered_dir = stage4 / strategy, stage7 / strategy
        report = filtered_dir / f"D027_Stage7_{strategy}_Filter.htm"
        for required in (report, filtered_dir / "MSZZ_SignalJournal.csv",
                         filtered_dir / "MSZZ_RegimeJournal.csv", filtered_dir / config_name):
            if not required.is_file() or required.stat().st_size == 0:
                raise ValueError(f"{strategy}: missing/empty {required.name}")
        control_signals = read_csv(control_dir / "MSZZ_SignalJournal.csv")
        filtered_signals = read_csv(filtered_dir / "MSZZ_SignalJournal.csv")
        control_raw = [row for row in control_signals if row["status"] == "RAW_CANDIDATE"]
        filtered_raw = [row for row in filtered_signals if row["status"] == "RAW_CANDIDATE"]
        control_fingerprint = [tuple(row[field] for field in RAW_FIELDS) for row in control_raw]
        filtered_fingerprint = [tuple(row[field] for field in RAW_FIELDS) for row in filtered_raw]
        if control_fingerprint != filtered_fingerprint:
            raise ValueError(f"{strategy}: raw trigger stream differs")
        trigger_rows.append({
            "strategy": strategy, "control_raw_candidates": len(control_raw),
            "filtered_raw_candidates": len(filtered_raw),
            "field_count_compared": len(RAW_FIELDS),
            "ordered_stream_identical": "true", "status": "PASS",
        })
        counts = Counter(row["status"] for row in filtered_signals)
        reasons = Counter(row["eligibility_reason"] for row in filtered_signals
                          if row["status"] == "REJECT_REGIME")
        status_rows.append({
            "strategy": strategy, "raw_candidates": counts["RAW_CANDIDATE"],
            "reject_regime": counts["REJECT_REGIME"], "executed": counts["EXECUTED"],
            "reject_ownership": counts["REJECT_OWNERSHIP"],
            "reject_duplicate_cluster": counts["REJECT_DUPLICATE_CLUSTER"],
            "reject_spread": counts["REJECT_SPREAD"],
            "regime_rejection_reasons": " | ".join(
                f"{reason} [{count}]" for reason, count in sorted(reasons.items())),
        })

        control = load_trades(control_dir / "MSZZ_TradeAnalytics.csv")
        filtered = load_trades(filtered_dir / "MSZZ_TradeAnalytics.csv")
        all_runs[(strategy, "LABEL_ONLY")] = control
        all_runs[(strategy, "RESEARCH_FILTER")] = filtered
        html_trades, html_deals = html_counts(report)
        if html_trades != len(filtered) or html_deals != len(filtered) * 2:
            raise ValueError(f"{strategy}: HTML/analytics mismatch")
        summary_file = filtered_dir / "MSZZ_RunSummary.csv"
        if filtered:
            run_summary = read_csv(summary_file)
            if len(run_summary) != 1 or int(run_summary[0]["trades"]) != len(filtered):
                raise ValueError(f"{strategy}: RunSummary mismatch")
        elif summary_file.exists():
            raise ValueError(f"{strategy}: unexpected zero-trade RunSummary")

        executed: dict[str, list[dict[str, str]]] = defaultdict(list)
        for row in filtered_signals:
            if row["status"] == "EXECUTED":
                executed[row["cluster_id"]].append(row)
        regimes: dict[str, list[dict[str, str]]] = defaultdict(list)
        for row in read_csv(filtered_dir / "MSZZ_RegimeJournal.csv"):
            regimes[row["time"]].append(row)
        for trade in filtered:
            signals = executed.get(trade["cluster_id"], [])
            if len(signals) != 1:
                raise ValueError(f"{strategy}: executed join")
            signal = signals[0]
            if (signal["strategy_id"] != strategy_id or signal["eligibility_mode"] != "RESEARCH_FILTER"
                    or signal["eligibility_result"] != "true"
                    or signal["time"] != signal["regime_snapshot_id"]
                    or len(regimes.get(signal["regime_snapshot_id"], [])) != 1):
                raise ValueError(f"{strategy}: signal/regime identity")
        join_rows.append({
            "strategy": strategy, "html_trades": html_trades, "html_deals": html_deals,
            "analytics_trades": len(filtered), "executed_signal_joins": len(filtered),
            "entry_regime_joins": len(filtered), "missing_or_ambiguous": 0, "status": "PASS",
        })

        control_clusters = {row["cluster_id"]: row for row in control}
        filtered_clusters = {row["cluster_id"]: row for row in filtered}
        if not set(filtered_clusters) <= set(control_clusters):
            raise ValueError(f"{strategy}: filtered execution not a control subset")
        retained_changed = sum(
            filtered_clusters[key]["r_result"] != control_clusters[key]["r_result"]
            or filtered_clusters[key]["close_time"] != control_clusters[key]["close_time"]
            for key in filtered_clusters
        )
        path_rows.append({
            "strategy": strategy, "control_trades": len(control),
            "filtered_trades": len(filtered), "retained_cluster_ids": len(filtered_clusters),
            "removed_cluster_ids": len(control_clusters) - len(filtered_clusters),
            "new_cluster_ids": 0, "retained_close_or_r_changed": retained_changed,
            "status": "PASS" if retained_changed == 0 else "PATH_DEPENDENT",
        })

    for (strategy, mode), rows in all_runs.items():
        summary_rows.append(metrics(strategy, mode, "Full window", rows))
        outlier_rows.append(outliers(strategy, mode, rows))
        total = 0
        for scope, start, end in WINDOWS:
            bucket = [row for row in rows if start <= row["entry_dt"] < end]
            total += len(bucket)
            window_rows.append(metrics(strategy, mode, scope, bucket))
        if total != len(rows):
            raise ValueError(f"{strategy}/{mode}: window reconciliation")

    comparison_rows = []
    for strategy in SPECS:
        control = next(row for row in summary_rows
                       if row["strategy"] == strategy and row["mode"] == "LABEL_ONLY")
        filtered = next(row for row in summary_rows
                        if row["strategy"] == strategy and row["mode"] == "RESEARCH_FILTER")
        comparison_rows.append({
            "strategy": strategy, "control_trades": control["trades"],
            "filtered_trades": filtered["trades"],
            "retention_rate": fmt(filtered["trades"] / control["trades"]),
            "control_cumulative_r": control["cumulative_r"],
            "filtered_cumulative_r": filtered["cumulative_r"],
            "cumulative_r_change": fmt(float(filtered["cumulative_r"]) - float(control["cumulative_r"])),
            "control_expectancy_r": control["expectancy_r"],
            "filtered_expectancy_r": filtered["expectancy_r"],
            "control_max_drawdown_r": control["max_drawdown_r"],
            "filtered_max_drawdown_r": filtered["max_drawdown_r"],
        })

    write_csv(output / "config_audit.csv", config_rows)
    write_csv(output / "trigger_equivalence_audit.csv", trigger_rows)
    write_csv(output / "filter_status_audit.csv", status_rows)
    write_csv(output / "trade_regime_join_audit.csv", join_rows)
    write_csv(output / "trade_path_audit.csv", path_rows)
    write_csv(output / "filter_comparison.csv", comparison_rows)
    write_csv(output / "filter_summary.csv", summary_rows)
    write_csv(output / "filter_window_summary.csv", window_rows)
    write_csv(output / "filter_outlier_checks.csv", outlier_rows)

    lookup = {row["strategy"]: row for row in comparison_rows}
    windows = {(row["strategy"], row["mode"], row["scope"]): row for row in window_rows}
    lines = [
        "# D027 Stage 7 — frozen regime-filter findings", "",
        "Five fixed-2R S1–S5 controls were compared with their sole predeclared "
        "`RESEARCH_FILTER` counterpart. Raw candidate streams are identical; only "
        "the frozen eligibility policy changes.", "",
        "| Strategy | Control trades | Filtered trades | Control R | Filtered R | R change |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for strategy in SPECS:
        row = lookup[strategy]
        lines.append(
            f"| {strategy} | {row['control_trades']} | {row['filtered_trades']} | "
            f"{row['control_cumulative_r']} | {row['filtered_cumulative_r']} | "
            f"{row['cumulative_r_change']} |")
    compression_windows = [
        windows[("CompressionBreakout", "RESEARCH_FILTER", scope)]["cumulative_r"]
        for scope, _, _ in WINDOWS
    ]
    lines += [
        "", "## Decision", "",
        "AlignedFastPullback is filtered to zero because the frozen policy's aligned "
        "requirement is incompatible with the classifier's causally emitted PULLBACK "
        "state. SweepReclaim is filtered to zero exactly as predeclared because "
        "`FAILED_BREAK` is not implemented. BreakoutRetest remains negative. "
        "StructureTransition is unchanged, so its filter adds no selectivity.", "",
        f"CompressionBreakout improves to {lookup['CompressionBreakout']['filtered_cumulative_r']}R "
        f"over {lookup['CompressionBreakout']['filtered_trades']} trades, with development / "
        f"validation / holdout R of {' / '.join(compression_windows)}. This is a filtered "
        "subset of a losing Stage 4 strategy and is not rescued or promoted by one "
        "regime rule.", "",
        "No frozen regime filter is accepted for production or for A/E. SweepReclaim "
        "2R remains the only positive standalone new family, but its frozen filter is "
        "unavailable; LABEL_ONLY remains the global default.", "",
    ]
    (output / "stage7_findings.md").write_text("\n".join(lines), encoding="utf-8")
    manifest = []
    for path in sorted(output.glob("*.csv")) + [output / "stage7_findings.md"]:
        manifest.append(f"{path.name}  {hashlib.sha256(path.read_bytes()).hexdigest()}")
    (output / "output_sha256.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage4-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results"))
    parser.add_argument("--stage7-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage7_Results"))
    parser.add_argument("--config-root", type=Path,
                        default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    analyze(args.stage4_root, args.stage7_root, args.config_root, args.output_dir)


if __name__ == "__main__":
    main()
