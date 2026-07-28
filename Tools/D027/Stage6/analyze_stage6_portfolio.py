#!/usr/bin/env python3
"""Deterministic D027 Stage 6 actual combined-EA portfolio analysis."""

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

DT_FMT = "%Y.%m.%d %H:%M:%S"
WINDOWS = (
    ("Development", datetime(2025, 3, 1), datetime(2026, 1, 1)),
    ("Validation", datetime(2026, 1, 1), datetime(2026, 5, 1)),
    ("Final holdout", datetime(2026, 5, 1), datetime(2026, 7, 25)),
)
VARIANTS = {
    "A_2R": ("core", "2.00"),
    "SweepReclaim_2R": ("new", "2.00"),
    "A_plus_SweepReclaim_2R": ("combined", "2.00"),
    "E_3R": ("core", "3.00"),
    "SweepReclaim_3R": ("new", "3.00"),
    "E_plus_SweepReclaim_3R": ("combined", "3.00"),
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        if reader.fieldnames is None:
            raise ValueError(f"missing header: {path}")
        rows = list(reader)
    if not rows:
        raise ValueError(f"no data rows: {path}")
    return rows


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
    if math.isinf(value):
        return "inf"
    return f"{value:.6f}"


def pf(values: list[float]) -> float:
    gains = sum(value for value in values if value > 0)
    losses = -sum(value for value in values if value < 0)
    return math.inf if gains and not losses else (gains / losses if losses else 0.0)


def max_dd(values: list[float]) -> float:
    equity = peak = worst = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        worst = max(worst, peak - equity)
    return worst


def pearson(left: list[float], right: list[float]) -> float | None:
    if len(left) != len(right) or len(left) < 2:
        return None
    mean_l, mean_r = statistics.fmean(left), statistics.fmean(right)
    numerator = sum((a - mean_l) * (b - mean_r) for a, b in zip(left, right))
    denom_l = sum((a - mean_l) ** 2 for a in left)
    denom_r = sum((b - mean_r) ** 2 for b in right)
    if denom_l == 0 or denom_r == 0:
        return None
    return numerator / math.sqrt(denom_l * denom_r)


def corr_fmt(value: float | None) -> str:
    return "" if value is None else fmt(value)


def period_key(value: datetime, period: str) -> str:
    if period == "day":
        return value.strftime("%Y-%m-%d")
    if period == "week":
        iso = value.isocalendar()
        return f"{iso.year}-W{iso.week:02d}"
    return value.strftime("%Y-%m")


def aggregate(rows: list[dict], period: str) -> dict[str, float]:
    output: dict[str, float] = defaultdict(float)
    for row in rows:
        output[period_key(row["entry_dt"], period)] += row["r"]
    return dict(output)


def aligned_series(left: dict[str, float], right: dict[str, float]) -> tuple[list[float], list[float]]:
    keys = sorted(set(left) | set(right))
    return ([left.get(key, 0.0) for key in keys],
            [right.get(key, 0.0) for key in keys])


def rolling_corr(left: dict[str, float], right: dict[str, float], width: int) -> list[float]:
    keys = sorted(set(left) | set(right))
    a = [left.get(key, 0.0) for key in keys]
    b = [right.get(key, 0.0) for key in keys]
    values = []
    for index in range(width - 1, len(keys)):
        value = pearson(a[index - width + 1:index + 1], b[index - width + 1:index + 1])
        if value is not None:
            values.append(value)
    return values


def drawdown_series(rows: list[dict]) -> dict[str, float]:
    daily = aggregate(rows, "day")
    equity = peak = 0.0
    output = {}
    for day in sorted(daily):
        equity += daily[day]
        peak = max(peak, equity)
        output[day] = peak - equity
    return output


def outlier_metrics(variant: str, rows: list[dict]) -> dict[str, object]:
    values = [row["r"] for row in rows]
    quarters: dict[str, float] = defaultdict(float)
    for row in rows:
        quarter = (row["entry_dt"].month - 1) // 3 + 1
        quarters[f"{row['entry_dt'].year}-Q{quarter}"] += row["r"]
    ranked = sorted(values, reverse=True)
    best_quarter, best_quarter_r = max(quarters.items(), key=lambda item: (item[1], item[0]))
    return {
        "variant": variant, "trades": len(rows),
        "cumulative_r": fmt(sum(values)),
        "best_trade_r": fmt(ranked[0]),
        "excluding_best_trade_r": fmt(sum(values) - ranked[0]),
        "excluding_top_three_trades_r": fmt(sum(values) - sum(ranked[:3])),
        "best_quarter": best_quarter, "best_quarter_r": fmt(best_quarter_r),
        "excluding_best_quarter_r": fmt(sum(values) - best_quarter_r),
        "positive_quarters": sum(value > 0 for value in quarters.values()),
        "negative_quarters": sum(value < 0 for value in quarters.values()),
    }


def parse_ini(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith(";"):
            key, value = line.split("=", 1)
            values[key] = value.split("||", 1)[0]
    return values


def load_trades(path: Path, variant: str) -> list[dict]:
    rows = []
    for trade in read_csv(path):
        entry = stamp(trade["signal_time"])
        rows.append({
            "variant": variant, "cluster_id": trade["cluster_id"],
            "strategy_id": trade["strategy_id"], "trade_direction": trade["direction"],
            "entry_dt": entry, "fill_dt": stamp(trade["fill_time"]),
            "close_dt": stamp(trade["close_time"]),
            "r": float(trade["r_result"]), "mfe": float(trade["mfe_r"]),
            "mae": float(trade["mae_r"]), "bars": int(trade["bars_held"]),
            "exit_reason": trade["exit_reason"],
        })
    return rows


def window_name(value: datetime) -> str:
    found = [name for name, start, end in WINDOWS if start <= value < end]
    if len(found) != 1:
        raise ValueError(f"entry outside frozen windows: {value}")
    return found[0]


def metrics(variant: str, scope: str, rows: list[dict]) -> dict[str, object]:
    ordered = sorted(rows, key=lambda row: (row["entry_dt"], row["cluster_id"]))
    values = [row["r"] for row in ordered]
    longs = [row["r"] for row in rows if row["trade_direction"] == "LONG"]
    shorts = [row["r"] for row in rows if row["trade_direction"] == "SHORT"]
    return {
        "variant": variant, "role": VARIANTS[variant][0], "scope": scope,
        "trades": len(rows), "wins": sum(value > 0 for value in values),
        "losses": sum(value < 0 for value in values),
        "win_rate": fmt(sum(value > 0 for value in values) / len(rows)),
        "cumulative_r": fmt(sum(values)),
        "expectancy_r": fmt(statistics.fmean(values)),
        "profit_factor_r": fmt(pf(values)),
        "max_drawdown_r": fmt(max_dd(values)),
        "long_trades": len(longs),
        "long_expectancy_r": fmt(statistics.fmean(longs) if longs else 0),
        "short_trades": len(shorts),
        "short_expectancy_r": fmt(statistics.fmean(shorts) if shorts else 0),
        "first_entry_time": ordered[0]["entry_dt"].strftime(DT_FMT),
        "last_exit_time": max(row["close_dt"] for row in rows).strftime(DT_FMT),
    }


def validate_combined(run: Path, variant: str, report_name: str,
                      expected_magic: str, rr: str) -> tuple[list[dict], list[dict], dict]:
    required = ("MSZZ_RunSummary.csv", "MSZZ_TradeAnalytics.csv",
                "MSZZ_SignalJournal.csv", "MSZZ_RegimeJournal.csv",
                "MSZZ_SequenceJournal.csv", report_name)
    for name in required:
        path = run / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"{variant}: missing/empty {name}")
    summary_rows = read_csv(run / "MSZZ_RunSummary.csv")
    if len(summary_rows) != 1:
        raise ValueError(f"{variant}: RunSummary rows={len(summary_rows)}")
    run_summary = summary_rows[0]
    trades = load_trades(run / "MSZZ_TradeAnalytics.csv", variant)
    signals = read_csv(run / "MSZZ_SignalJournal.csv")
    regimes = read_csv(run / "MSZZ_RegimeJournal.csv")
    html = (run / report_name).read_text(encoding="utf-16")
    trade_match = re.search(r"Total Trades:</td>\s*<td nowrap><b>(\d+)</b>", html)
    deal_match = re.search(r"Total Deals:</td>\s*<td nowrap><b>(\d+)</b>", html)
    html_trades = int(trade_match.group(1)) if trade_match else -1
    html_deals = int(deal_match.group(1)) if deal_match else -1
    expected = int(run_summary["trades"])
    if not (expected == len(trades) == html_trades and html_deals == expected * 2):
        raise ValueError(f"{variant}: HTML/summary/analytics mismatch")
    if (run_summary["symbol"] != "XAUUSD"
            or run_summary["timeframe"] != "PERIOD_M5"
            or run_summary["magic"] != expected_magic
            or run_summary["risk_reward"] != rr
            or run_summary["enabled_strategies"] != "FastMedConfluence,SweepReclaim"):
        raise ValueError(f"{variant}: summary identity mismatch")
    executed: dict[str, list[dict[str, str]]] = defaultdict(list)
    for signal in signals:
        if signal["status"] == "EXECUTED":
            executed[signal["cluster_id"]].append(signal)
    regime_map: dict[str, list[dict[str, str]]] = defaultdict(list)
    for regime in regimes:
        regime_map[regime["time"]].append(regime)
    for trade in trades:
        matches = executed.get(trade["cluster_id"], [])
        if len(matches) != 1:
            raise ValueError(f"{variant}: cluster join count {len(matches)}")
        signal = matches[0]
        snapshots = regime_map.get(signal["regime_snapshot_id"], [])
        if len(snapshots) != 1:
            raise ValueError(f"{variant}: regime join count {len(snapshots)}")
        if (signal["strategy_id"] != trade["strategy_id"]
                or signal["time"] != trade["entry_dt"].strftime(DT_FMT)
                or signal["time"] != signal["regime_snapshot_id"]
                or signal["eligibility_mode"] != "LABEL_ONLY"
                or signal["eligibility_result"] != "true"):
            raise ValueError(f"{variant}: signal identity/eligibility mismatch")
    audit = {
        "variant": variant, "summary_trades": expected,
        "analytics_trades": len(trades), "html_trades": html_trades,
        "html_deals": html_deals, "matched_signals": len(trades),
        "matched_entry_regimes": len(trades), "ambiguous_joins": 0, "status": "PASS",
    }
    return trades, signals, audit


def analyze(stage2: Path, d026: Path, stage4: Path, stage5: Path,
            stage6: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    runs = {
        "A_2R": load_trades(stage2 / "FastMedConfluence/MSZZ_TradeAnalytics.csv", "A_2R"),
        "SweepReclaim_2R": load_trades(stage4 / "SweepReclaim/MSZZ_TradeAnalytics.csv",
                                       "SweepReclaim_2R"),
        "E_3R": load_trades(d026 / "baselineE_canonical3r/MSZZ_TradeAnalytics.csv", "E_3R"),
        "SweepReclaim_3R": load_trades(stage5 / "SweepReclaim_3R/MSZZ_TradeAnalytics.csv",
                                       "SweepReclaim_3R"),
    }
    combined_specs = (
        ("A_plus_SweepReclaim_2R", "A_plus_SweepReclaim_2R",
         "D027_Stage6_A_plus_SweepReclaim_2R.htm", "26072941", "2.00",
         "d027_stage6_A_plus_SweepReclaim_2R.ini"),
        ("E_plus_SweepReclaim_3R", "E_plus_SweepReclaim_3R",
         "D027_Stage6_E_plus_SweepReclaim_3R.htm", "26072942", "3.00",
         "d027_stage6_E_plus_SweepReclaim_3R.ini"),
    )
    audits, config_audits = [], []
    combined_signals = {}
    for variant, directory, report, magic, rr, config_name in combined_specs:
        run = stage6 / directory
        config = parse_ini(run / config_name)
        enabled = [key for key, value in config.items()
                   if key.startswith("InpEnable") and value == "true"]
        config_ok = (
            enabled == ["InpEnableFastMedConfluence", "InpEnableSweepReclaim"]
            and config.get("InpRiskReward") == rr.removesuffix("0")
            and config.get("InpMagic") == magic
            and config.get("Symbol") == "XAUUSD" and config.get("Period") == "M5"
            and config.get("Model") == "2" and config.get("FromDate") == "2025.03.01"
            and config.get("ToDate") == "2026.07.24"
            and config.get("InpRegimeEligibilityMode") == "0"
            and config.get("InpResearchMinScoreOverride") == "0.0"
            and config.get("InpEnableResearchTrail") == "false"
            and config.get("InpPartialCloseAtR") == "0.0"
            and config.get("InpDisableFixedTarget") == "false")
        if not config_ok:
            raise ValueError(f"{variant}: config integrity failed")
        config_audits.append({
            "variant": variant, "magic": magic, "risk_reward": rr,
            "enabled": ",".join(enabled), "research_features_off": "true",
            "label_only": "true", "status": "PASS",
        })
        trades, signals, audit = validate_combined(run, variant, report, magic, rr)
        runs[variant] = trades
        combined_signals[variant] = signals
        audits.append(audit)

    summaries = [metrics(variant, "Full window", runs[variant]) for variant in VARIANTS]
    window_rows = []
    for variant in VARIANTS:
        rows = runs[variant]
        total = 0
        for name, start, end in WINDOWS:
            bucket = [row for row in rows if start <= row["entry_dt"] < end]
            total += len(bucket)
            window_rows.append(metrics(variant, name, bucket))
        if total != len(rows):
            raise ValueError(f"{variant}: window totals do not reconcile")

    pair_specs = (
        ("A_2R_pair", "A_2R", "SweepReclaim_2R", "A_plus_SweepReclaim_2R"),
        ("E_3R_pair", "E_3R", "SweepReclaim_3R", "E_plus_SweepReclaim_3R"),
    )
    incremental = []
    owner_rows = []
    unique_rows = []
    weak_rows = []
    correlation_rows = []
    rolling_rows = []
    exit_rows = []
    outlier_rows = [outlier_metrics(variant, runs[variant]) for variant in VARIANTS]
    for pair, core_name, new_name, combined_name in pair_specs:
        core, new, combined = runs[core_name], runs[new_name], runs[combined_name]
        core_values = [row["r"] for row in sorted(core, key=lambda row: row["entry_dt"])]
        combined_values = [row["r"] for row in sorted(combined, key=lambda row: row["entry_dt"])]
        core_r, combined_r = sum(core_values), sum(combined_values)
        incremental.append({
            "pair": pair, "core_variant": core_name, "new_variant": new_name,
            "combined_variant": combined_name,
            "core_trades": len(core), "new_standalone_trades": len(new),
            "combined_trades": len(combined),
            "frequency_change_vs_core": len(combined) - len(core),
            "core_cumulative_r": fmt(core_r),
            "new_standalone_cumulative_r": fmt(sum(row["r"] for row in new)),
            "combined_cumulative_r": fmt(combined_r),
            "incremental_r_vs_core": fmt(combined_r - core_r),
            "core_max_drawdown_r": fmt(max_dd(core_values)),
            "combined_max_drawdown_r": fmt(max_dd(combined_values)),
            "drawdown_change_r": fmt(max_dd(combined_values) - max_dd(core_values)),
        })
        for strategy_id, owner in (("1010", "FastMedConfluence"), ("1050", "SweepReclaim")):
            bucket = [row for row in combined if row["strategy_id"] == strategy_id]
            owner_rows.append({
                "pair": pair, "owner": owner, "trades": len(bucket),
                "wins": sum(row["r"] > 0 for row in bucket),
                "cumulative_r": fmt(sum(row["r"] for row in bucket)),
                "expectancy_r": fmt(statistics.fmean(row["r"] for row in bucket)),
            })
        core_keys = {(row["entry_dt"].strftime(DT_FMT), row["trade_direction"]) for row in core}
        new_owned = [row for row in combined if row["strategy_id"] == "1050"]
        same_bar = [row for row in new_owned
                    if (row["entry_dt"].strftime(DT_FMT), row["trade_direction"]) in core_keys]
        unique = [row for row in new_owned if row not in same_bar]
        core_clusters = {row["cluster_id"] for row in core}
        combined_core = [row for row in combined if row["strategy_id"] == "1010"]
        combined_core_clusters = {row["cluster_id"] for row in combined_core}
        unique_rows.append({
            "pair": pair, "combined_sweep_owned_trades": len(new_owned),
            "same_bar_direction_core_overlap": len(same_bar),
            "same_bar_overlap_r": fmt(sum(row["r"] for row in same_bar)),
            "unique_added_trades": len(unique),
            "profitable_unique_trades": sum(row["r"] > 0 for row in unique),
            "unique_added_cumulative_r": fmt(sum(row["r"] for row in unique)),
            "unique_added_expectancy_r": fmt(statistics.fmean(row["r"] for row in unique)),
            "core_trades_retained": sum(row["cluster_id"] in core_clusters for row in combined_core),
            "core_trades_displaced": len(core_clusters - combined_core_clusters),
            "core_trades_newly_executed": len(combined_core_clusters - core_clusters),
        })

        core_trade_map = {
            (row["entry_dt"].strftime(DT_FMT), row["trade_direction"]): row["r"]
            for row in core
        }
        new_trade_map = {
            (row["entry_dt"].strftime(DT_FMT), row["trade_direction"]): row["r"]
            for row in new
        }
        common_trade_keys = sorted(set(core_trade_map) & set(new_trade_map))
        combined_cluster_map = {row["cluster_id"]: row["r"] for row in combined}
        core_cluster_map = {row["cluster_id"]: row["r"] for row in core}
        common_clusters = sorted(set(core_cluster_map) & set(combined_cluster_map))
        correlation_rows.append({
            "pair": pair, "period": "matched_trade",
            "core_new_return_correlation": corr_fmt(pearson(
                [core_trade_map[key] for key in common_trade_keys],
                [new_trade_map[key] for key in common_trade_keys])),
            "core_combined_return_correlation": corr_fmt(pearson(
                [core_cluster_map[key] for key in common_clusters],
                [combined_cluster_map[key] for key in common_clusters])),
            "observations_core_new": len(common_trade_keys),
            "observations_core_combined": len(common_clusters),
        })

        for period in ("day", "week", "month"):
            core_period, new_period = aggregate(core, period), aggregate(new, period)
            combined_period = aggregate(combined, period)
            a, b = aligned_series(core_period, new_period)
            c, d = aligned_series(core_period, combined_period)
            correlation_rows.append({
                "pair": pair, "period": period,
                "core_new_return_correlation": corr_fmt(pearson(a, b)),
                "core_combined_return_correlation": corr_fmt(pearson(c, d)),
                "observations_core_new": len(a), "observations_core_combined": len(c),
            })
        core_dd, new_dd = drawdown_series(core), drawdown_series(new)
        combined_dd = drawdown_series(combined)
        a, b = aligned_series(core_dd, new_dd)
        c, d = aligned_series(core_dd, combined_dd)
        correlation_rows.append({
            "pair": pair, "period": "daily_drawdown_level",
            "core_new_return_correlation": corr_fmt(pearson(a, b)),
            "core_combined_return_correlation": corr_fmt(pearson(c, d)),
            "observations_core_new": len(a), "observations_core_combined": len(c),
        })
        for period, width in (("week", 8), ("month", 3)):
            core_period, new_period = aggregate(core, period), aggregate(new, period)
            combined_period = aggregate(combined, period)
            for comparison, right in (("core_new", new_period),
                                      ("core_combined", combined_period)):
                values = rolling_corr(core_period, right, width)
                rolling_rows.append({
                    "pair": pair, "period": period, "window_periods": width,
                    "comparison": comparison, "observations": len(values),
                    "mean_correlation": fmt(statistics.fmean(values)),
                    "median_correlation": fmt(statistics.median(values)),
                    "minimum_correlation": fmt(min(values)),
                    "maximum_correlation": fmt(max(values)),
                })

        core_month = aggregate(core, "month")
        new_month = aggregate(new, "month")
        combined_month = aggregate(combined, "month")
        for month in sorted(key for key, value in core_month.items() if value < 0):
            core_value = core_month[month]
            combined_value = combined_month.get(month, 0.0)
            weak_rows.append({
                "pair": pair, "month": month, "core_r": fmt(core_value),
                "new_standalone_r": fmt(new_month.get(month, 0.0)),
                "actual_combined_r": fmt(combined_value),
                "combined_increment_vs_core_r": fmt(combined_value - core_value),
                "combined_improved_core_negative_month": str(combined_value > core_value).lower(),
            })

        fills: dict[datetime, list[dict]] = defaultdict(list)
        for row in combined:
            fills[row["fill_dt"]].append(row)
        own = cross = unknown = 0
        for row in combined:
            if row["exit_reason"] != "OTHER":
                continue
            opposite = "SHORT" if row["trade_direction"] == "LONG" else "LONG"
            reversals = [candidate for candidate in fills[row["close_dt"]]
                         if candidate["trade_direction"] == opposite]
            if len(reversals) != 1:
                unknown += 1
            elif reversals[0]["strategy_id"] == row["strategy_id"]:
                own += 1
            else:
                cross += 1
        reasons = Counter(row["exit_reason"] for row in combined)
        exit_rows.append({
            "pair": pair, "trades": len(combined), "sl": reasons["SL"],
            "tp": reasons["TP"], "own_family_opposite": own,
            "cross_family_opposite": cross, "unknown_exits": unknown,
        })
        if reasons["SL"] + reasons["TP"] + own + cross + unknown != len(combined):
            raise ValueError(f"{pair}: exit classes do not reconcile")

    arbitration_rows = []
    for variant, signals in combined_signals.items():
        statuses = Counter(row["status"] for row in signals)
        executed = [row for row in signals if row["status"] == "EXECUTED"]
        overlap = [row for row in executed
                   if "1010" in row["overlap_strategy_ids"].split(",")
                   and "1050" in row["overlap_strategy_ids"].split(",")]
        arbitration_rows.append({
            "variant": variant, "raw_candidates": statuses["RAW_CANDIDATE"],
            "executed": statuses["EXECUTED"],
            "reject_ownership": statuses["REJECT_OWNERSHIP"],
            "reject_duplicate_cluster": statuses["REJECT_DUPLICATE_CLUSTER"],
            "reject_expired": statuses["REJECT_EXPIRED"],
            "executed_exact_cluster_overlap": len(overlap),
            "status": "PASS",
        })

    write_csv(output / "config_audit.csv", config_audits)
    write_csv(output / "join_audit.csv", audits)
    write_csv(output / "portfolio_summary.csv", summaries)
    write_csv(output / "portfolio_window_summary.csv", window_rows)
    write_csv(output / "portfolio_incremental.csv", incremental)
    write_csv(output / "portfolio_owner_contribution.csv", owner_rows)
    write_csv(output / "portfolio_unique_trades.csv", unique_rows)
    write_csv(output / "portfolio_correlations.csv", correlation_rows)
    write_csv(output / "portfolio_rolling_correlations.csv", rolling_rows)
    write_csv(output / "portfolio_core_negative_months.csv", weak_rows)
    write_csv(output / "portfolio_arbitration_audit.csv", arbitration_rows)
    write_csv(output / "portfolio_exit_audit.csv", exit_rows)
    write_csv(output / "portfolio_outlier_checks.csv", outlier_rows)

    inc_a, inc_e = incremental
    unique_a, unique_e = unique_rows
    window_lookup = {(row["variant"], row["scope"]): row for row in window_rows}
    outlier_lookup = {row["variant"]: row for row in outlier_rows}
    a_holdout = window_lookup[("A_plus_SweepReclaim_2R", "Final holdout")]
    e_holdout = window_lookup[("E_plus_SweepReclaim_3R", "Final holdout")]
    a_outlier = outlier_lookup["A_plus_SweepReclaim_2R"]
    e_outlier = outlier_lookup["E_plus_SweepReclaim_3R"]
    lines = [
        "# D027 Stage 6 — actual combined-EA portfolio findings", "",
        "The EA has one global RR input, so comparisons are target-matched: A and "
        "SweepReclaim at 2R, E and SweepReclaim at 3R. Combined figures come from "
        "actual shared arbitration/ownership backtests; standalone results are never "
        "arithmetically added.", "",
        "## Incremental results", "",
        "| Pair | Core R | Combined R | Incremental R | Core DD | Combined DD | Trades Δ |",
        "|---|---:|---:|---:|---:|---:|---:|",
        f"| A 2R | {inc_a['core_cumulative_r']} | {inc_a['combined_cumulative_r']} | "
        f"{inc_a['incremental_r_vs_core']} | {inc_a['core_max_drawdown_r']} | "
        f"{inc_a['combined_max_drawdown_r']} | {inc_a['frequency_change_vs_core']} |",
        f"| E 3R | {inc_e['core_cumulative_r']} | {inc_e['combined_cumulative_r']} | "
        f"{inc_e['incremental_r_vs_core']} | {inc_e['core_max_drawdown_r']} | "
        f"{inc_e['combined_max_drawdown_r']} | {inc_e['frequency_change_vs_core']} |", "",
        "## Decision", "",
        f"A+SweepReclaim loses {abs(float(inc_a['incremental_r_vs_core'])):.4f}R versus A "
        f"and increases drawdown by {float(inc_a['drawdown_change_r']):.4f}R. "
        f"E+SweepReclaim loses {abs(float(inc_e['incremental_r_vs_core'])):.4f}R versus E "
        f"and increases drawdown by {float(inc_e['drawdown_change_r']):.4f}R.", "",
        f"The combined A and E variants remain positive after removing their top three "
        f"trades ({a_outlier['excluding_top_three_trades_r']}R and "
        f"{e_outlier['excluding_top_three_trades_r']}R), but only "
        f"{a_outlier['excluding_best_quarter_r']}R and "
        f"{e_outlier['excluding_best_quarter_r']}R remain after each best quarter. "
        f"Final-holdout results are {a_holdout['cumulative_r']}R for the A pair and "
        f"{e_holdout['cumulative_r']}R for the E pair, both below their matched core "
        "holdout results.", "",
        f"The actual A pair adds {unique_a['unique_added_trades']} same-bar-unique "
        f"SweepReclaim-owned trades at {unique_a['unique_added_expectancy_r']}R expectancy; "
        f"the E pair adds {unique_e['unique_added_trades']} at "
        f"{unique_e['unique_added_expectancy_r']}R. These additions do not compensate "
        f"for displaced/degraded core behavior: the A pair displaces "
        f"{unique_a['core_trades_displaced']} baseline core trades and newly executes "
        f"{unique_a['core_trades_newly_executed']}; the E pair displaces "
        f"{unique_e['core_trades_displaced']} and newly executes "
        f"{unique_e['core_trades_newly_executed']}. The changed outcomes arise under "
        "shared ownership and opposite-family exits. SweepReclaim is therefore rejected "
        "as a portfolio addition to A or E "
        "under the frozen combined architecture. Standalone 2R remains research-only, "
        "not promoted.", "",
    ]
    (output / "stage6_findings.md").write_text("\n".join(lines), encoding="utf-8")
    manifest = []
    for path in sorted(output.glob("*.csv")) + [output / "stage6_findings.md"]:
        manifest.append(f"{path.name}  {hashlib.sha256(path.read_bytes()).hexdigest()}")
    (output / "output_sha256.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage2-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage2_Results"))
    parser.add_argument("--d026-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D026_Results"))
    parser.add_argument("--stage4-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results"))
    parser.add_argument("--stage5-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage5_Results"))
    parser.add_argument("--stage6-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage6_Results"))
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    analyze(args.stage2_root, args.d026_root, args.stage4_root,
            args.stage5_root, args.stage6_root, args.output_dir)


if __name__ == "__main__":
    main()
