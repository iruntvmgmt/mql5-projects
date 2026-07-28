#!/usr/bin/env python3
"""Deterministic D027 Stage 5 SweepReclaim 2R-versus-3R comparison."""

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
REGIMES = ("direction", "trend_strength", "volatility_state",
           "alignment_state", "market_phase")


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


def parse_ini(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith(";"):
            key, value = line.split("=", 1)
            result[key] = value.split("||", 1)[0]
    return result


def stamp(value: str) -> datetime:
    return datetime.strptime(value, DT_FMT)


def fmt(value: float) -> str:
    if math.isinf(value):
        return "inf"
    return f"{value:.6f}"


def profit_factor(values: list[float]) -> float:
    gains = sum(value for value in values if value > 0)
    losses = -sum(value for value in values if value < 0)
    return math.inf if not losses and gains else (gains / losses if losses else 0.0)


def max_drawdown(values: list[float]) -> float:
    equity = peak = worst = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        worst = max(worst, peak - equity)
    return worst


def percentile(values: list[int], proportion: float) -> float:
    ordered = sorted(values)
    index = (len(ordered) - 1) * proportion
    low, high = math.floor(index), math.ceil(index)
    if low == high:
        return float(ordered[low])
    return ordered[low] * (high - index) + ordered[high] * (index - low)


def window_name(value: datetime) -> str:
    found = [name for name, start, end in WINDOWS if start <= value < end]
    if len(found) != 1:
        raise ValueError(f"entry outside frozen windows: {value}")
    return found[0]


def summary(rr: str, scope: str, rows: list[dict]) -> dict[str, object]:
    ordered = sorted(rows, key=lambda row: (row["entry_dt"], row["cluster_id"]))
    values = [row["r"] for row in ordered]
    longs = [row["r"] for row in rows if row["trade_direction"] == "LONG"]
    shorts = [row["r"] for row in rows if row["trade_direction"] == "SHORT"]
    held = [row["bars"] for row in rows]
    elapsed_bars = max(
        1.0,
        (max(row["close_dt"] for row in rows)
         - min(row["entry_dt"] for row in rows)).total_seconds() / 300.0,
    )
    return {
        "variant": rr, "scope": scope, "trades": len(rows),
        "wins": sum(value > 0 for value in values),
        "losses": sum(value < 0 for value in values),
        "win_rate": fmt(sum(value > 0 for value in values) / len(rows)),
        "cumulative_r": fmt(sum(values)),
        "expectancy_r": fmt(statistics.fmean(values)),
        "profit_factor_r": fmt(profit_factor(values)),
        "max_drawdown_r": fmt(max_drawdown(values)),
        "median_r": fmt(statistics.median(values)),
        "average_mfe_r": fmt(statistics.fmean(row["mfe"] for row in rows)),
        "average_mae_r": fmt(statistics.fmean(row["mae"] for row in rows)),
        "median_hold_bars": fmt(statistics.median(held)),
        "p90_hold_bars": fmt(percentile(held, .90)),
        "wall_clock_exposure_pct": fmt(100 * sum(held) / elapsed_bars),
        "long_trades": len(longs),
        "long_expectancy_r": fmt(statistics.fmean(longs)),
        "short_trades": len(shorts),
        "short_expectancy_r": fmt(statistics.fmean(shorts)),
        "first_entry_time": ordered[0]["entry_dt"].strftime(DT_FMT),
        "last_exit_time": max(row["close_dt"] for row in rows).strftime(DT_FMT),
    }


def load_variant(label: str, run: Path, report: str, expected_rr: str,
                 expected_magic: str) -> tuple[list[dict], list[dict], dict]:
    required = ("MSZZ_RunSummary.csv", "MSZZ_TradeAnalytics.csv",
                "MSZZ_SignalJournal.csv", "MSZZ_RegimeJournal.csv",
                "MSZZ_SequenceJournal.csv", report)
    for name in required:
        path = run / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"{label}: missing/empty {name}")
    summaries = read_csv(run / "MSZZ_RunSummary.csv")
    if len(summaries) != 1:
        raise ValueError(f"{label}: RunSummary rows={len(summaries)}")
    run_summary = summaries[0]
    analytics = read_csv(run / "MSZZ_TradeAnalytics.csv")
    signals = read_csv(run / "MSZZ_SignalJournal.csv")
    regimes = read_csv(run / "MSZZ_RegimeJournal.csv")
    expected = int(run_summary["trades"])
    html = (run / report).read_text(encoding="utf-16")
    trades_match = re.search(r"Total Trades:</td>\s*<td nowrap><b>(\d+)</b>", html)
    deals_match = re.search(r"Total Deals:</td>\s*<td nowrap><b>(\d+)</b>", html)
    html_trades = int(trades_match.group(1)) if trades_match else -1
    html_deals = int(deals_match.group(1)) if deals_match else -1
    if not (len(analytics) == expected == html_trades and html_deals == expected * 2):
        raise ValueError(f"{label}: HTML/summary/analytics mismatch")
    if (run_summary["symbol"] != "XAUUSD"
            or run_summary["timeframe"] != "PERIOD_M5"
            or run_summary["magic"] != expected_magic
            or run_summary["risk_reward"] != expected_rr
            or run_summary["enabled_strategies"] != "SweepReclaim"):
        raise ValueError(f"{label}: summary identity mismatch")

    executed: dict[str, list[dict[str, str]]] = defaultdict(list)
    for signal in signals:
        if signal["status"] == "EXECUTED":
            executed[signal["cluster_id"]].append(signal)
    regime_map: dict[str, list[dict[str, str]]] = defaultdict(list)
    for regime in regimes:
        regime_map[regime["time"]].append(regime)
    joined = []
    for trade in analytics:
        matches = executed.get(trade["cluster_id"], [])
        if len(matches) != 1:
            raise ValueError(f"{label}: cluster has {len(matches)} executed rows")
        signal = matches[0]
        snapshots = regime_map.get(signal["regime_snapshot_id"], [])
        if len(snapshots) != 1:
            raise ValueError(f"{label}: snapshot has {len(snapshots)} rows")
        regime = snapshots[0]
        if (signal["strategy_id"] != "1050"
                or signal["eligibility_mode"] != "LABEL_ONLY"
                or signal["eligibility_result"] != "true"
                or signal["time"] != trade["signal_time"]
                or signal["time"] != signal["regime_snapshot_id"]):
            raise ValueError(f"{label}: signal identity/snapshot mismatch")
        if (signal["regime_direction"] != regime["direction"]
                or signal["regime_alignment"] != regime["alignment_state"]
                or signal["regime_phase"] != regime["market_phase"]):
            raise ValueError(f"{label}: signal/regime disagreement")
        entry = stamp(trade["signal_time"])
        row = {
            "variant": label, "cluster_id": trade["cluster_id"],
            "origin_id": signal["origin_id"], "event_id": signal["event_id"],
            "trade_direction": trade["direction"], "entry_dt": entry,
            "close_dt": stamp(trade["close_time"]), "window": window_name(entry),
            "r": float(trade["r_result"]), "mfe": float(trade["mfe_r"]),
            "mae": float(trade["mae_r"]), "bars": int(trade["bars_held"]),
            "exit_reason": trade["exit_reason"],
        }
        for field in REGIMES:
            row[field] = regime[field]
        joined.append(row)
    audit = {
        "variant": label, "summary_trades": expected,
        "analytics_trades": len(analytics), "html_trades": html_trades,
        "html_deals": html_deals, "matched_entry_regimes": len(joined),
        "missing_or_duplicate_joins": 0, "status": "PASS",
    }
    return joined, signals, audit


def analyze(stage4: Path, stage5: Path, core: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    run3 = stage5 / "SweepReclaim_3R"
    config = parse_ini(run3 / "d027_stage5_SweepReclaim_3R.ini")
    enabled = [key for key, value in config.items()
               if key.startswith("InpEnable") and value == "true"]
    config_ok = (
        enabled == ["InpEnableSweepReclaim"]
        and config.get("Symbol") == "XAUUSD" and config.get("Period") == "M5"
        and config.get("Model") == "2" and config.get("FromDate") == "2025.03.01"
        and config.get("ToDate") == "2026.07.24"
        and config.get("InpMagic") == "26072936"
        and config.get("InpRiskReward") == "3.0"
        and config.get("InpExitOwnedOpposite") == "true"
        and config.get("InpRegimeEligibilityMode") == "0"
        and config.get("InpResearchMinScoreOverride") == "0.0"
        and config.get("InpDisableFixedTarget") == "false"
        and config.get("InpPartialCloseAtR") == "0.0"
        and config.get("InpEnableResearchTrail") == "false")
    if not config_ok:
        raise ValueError("3R config integrity failed")
    config_audit = [{
        "variant": "3R", "magic": "26072936", "enabled": ",".join(enabled),
        "risk_reward": "3.0", "label_only": "true",
        "research_features_off": "true", "status": "PASS",
    }]

    rows2, signals2, audit2 = load_variant(
        "2R", stage4 / "SweepReclaim", "D027_Stage4_SweepReclaim.htm", "2.00", "26072933")
    rows3, signals3, audit3 = load_variant(
        "3R", run3, "D027_Stage5_SweepReclaim_3R.htm", "3.00", "26072936")

    raw_fields = ("time", "strategy_id", "direction", "score", "entry", "stop",
                  "origin_id", "event_id", "reason", "regime_snapshot_id",
                  "regime_direction", "regime_alignment", "regime_phase")
    raw2 = [tuple(row[field] for field in raw_fields)
            for row in signals2 if row["status"] == "RAW_CANDIDATE"]
    raw3 = [tuple(row[field] for field in raw_fields)
            for row in signals3 if row["status"] == "RAW_CANDIDATE"]
    sequence_equal = (
        (stage4 / "SweepReclaim/MSZZ_SequenceJournal.csv").read_bytes()
        == (run3 / "MSZZ_SequenceJournal.csv").read_bytes())
    signal_audit = [{
        "raw_candidates_2r": len(raw2), "raw_candidates_3r": len(raw3),
        "raw_candidate_sets_equal": str(raw2 == raw3).lower(),
        "sequence_journals_byte_equal": str(sequence_equal).lower(),
        "executed_2r": len(rows2), "executed_3r": len(rows3),
        "status": "PASS" if raw2 == raw3 and sequence_equal else "FAIL",
    }]
    if raw2 != raw3 or not sequence_equal:
        raise ValueError("RR change altered frozen trigger/sequence generation")

    summaries = [summary("2R", "Full window", rows2),
                 summary("3R", "Full window", rows3)]
    windows = []
    for label, rows in (("2R", rows2), ("3R", rows3)):
        for name, _, _ in WINDOWS:
            subset = [row for row in rows if row["window"] == name]
            windows.append(summary(label, name, subset))
        if sum(int(row["trades"]) for row in windows if row["variant"] == label) != len(rows):
            raise ValueError(f"{label}: window count mismatch")

    monthly = []
    quarterly = []
    outliers = []
    for label, rows in (("2R", rows2), ("3R", rows3)):
        groups: dict[str, list[dict]] = defaultdict(list)
        month_groups: dict[str, list[dict]] = defaultdict(list)
        for row in rows:
            quarter = f"{row['entry_dt'].year}-Q{(row['entry_dt'].month - 1)//3 + 1}"
            groups[quarter].append(row)
            month_groups[row["entry_dt"].strftime("%Y-%m")].append(row)
        for month, bucket in sorted(month_groups.items()):
            monthly.append({
                "variant": label, "month": month, "trades": len(bucket),
                "cumulative_r": fmt(sum(row["r"] for row in bucket)),
                "expectancy_r": fmt(statistics.fmean(row["r"] for row in bucket)),
            })
        quarter_values = []
        for quarter, bucket in sorted(groups.items()):
            total = sum(row["r"] for row in bucket)
            quarter_values.append(total)
            quarterly.append({
                "variant": label, "quarter": quarter, "trades": len(bucket),
                "cumulative_r": fmt(total),
                "expectancy_r": fmt(statistics.fmean(row["r"] for row in bucket)),
            })
        values = sorted((row["r"] for row in rows), reverse=True)
        sorted_quarters = sorted(quarter_values, reverse=True)
        outliers.append({
            "variant": label, "trades": len(rows), "cumulative_r": fmt(sum(values)),
            "excluding_top_1_r": fmt(sum(values[1:])),
            "excluding_top_3_r": fmt(sum(values[3:])),
            "excluding_top_5_r": fmt(sum(values[5:])),
            "excluding_best_quarter_r": fmt(sum(values) - max(quarter_values)),
            "excluding_best_two_quarters_r": fmt(sum(values) - sum(sorted_quarters[:2])),
            "positive_quarters": sum(value > 0 for value in quarter_values),
            "negative_quarters": sum(value < 0 for value in quarter_values),
        })

    core_signals = read_csv(core / "MSZZ_SignalJournal.csv")
    core_keys = {(row["time"], row["direction"]) for row in core_signals
                 if row["status"] == "EXECUTED"}
    overlaps = []
    for label, rows in (("2R", rows2), ("3R", rows3)):
        same = [row for row in rows
                if (row["entry_dt"].strftime(DT_FMT), row["trade_direction"]) in core_keys]
        unique = [row for row in rows if row not in same]
        overlaps.append({
            "variant": label, "trades": len(rows), "core_same_bar_trades": len(same),
            "core_same_bar_r": fmt(sum(row["r"] for row in same)),
            "unique_trades": len(unique),
            "unique_cumulative_r": fmt(sum(row["r"] for row in unique)),
            "unique_expectancy_r": fmt(statistics.fmean(row["r"] for row in unique)),
        })

    path_comparison = [{
        "executed_2r": len(rows2), "executed_3r": len(rows3),
        "common_cluster_ids": len({row["cluster_id"] for row in rows2}
                                  & {row["cluster_id"] for row in rows3}),
        "only_2r_cluster_ids": len({row["cluster_id"] for row in rows2}
                                   - {row["cluster_id"] for row in rows3}),
        "only_3r_cluster_ids": len({row["cluster_id"] for row in rows3}
                                   - {row["cluster_id"] for row in rows2}),
        "note": "Execution subsets may differ because target distance changes ownership duration",
    }]

    exit_rows = []
    for label, rows, signals in (("2R", rows2, signals2), ("3R", rows3, signals3)):
        counts = Counter(row["exit_reason"] for row in rows)
        candidate_fills = set()
        for signal in signals:
            if signal["status"] in ("RAW_CANDIDATE", "EXECUTED"):
                decision = stamp(signal["time"]).replace(second=0)
                candidate_fills.add((decision.timestamp() + 300, signal["direction"]))
        own_opposite = test_end = unknown = 0
        for row in rows:
            if row["exit_reason"] != "OTHER":
                continue
            opposite = "SHORT" if row["trade_direction"] == "LONG" else "LONG"
            close_minute = row["close_dt"].replace(second=0)
            if (close_minute.timestamp(), opposite) in candidate_fills:
                own_opposite += 1
            elif row["close_dt"] >= datetime(2026, 7, 23, 23, 50):
                test_end += 1
            else:
                unknown += 1
        exit_rows.append({
            "variant": label, "trades": len(rows), "sl": counts["SL"],
            "tp": counts["TP"], "own_family_opposite": own_opposite,
            "cross_family_opposite": 0, "test_end": test_end,
            "unknown_exits": unknown,
        })
        if counts["SL"] + counts["TP"] + own_opposite + test_end + unknown != len(rows):
            raise ValueError(f"{label}: exit classes do not reconcile")

    regimes = []
    for label, rows in (("2R", rows2), ("3R", rows3)):
        for field in REGIMES:
            groups = defaultdict(list)
            for row in rows:
                groups[row[field]].append(row)
            for value, bucket in sorted(groups.items()):
                regimes.append({
                    "variant": label, "dimension": field, "value": value,
                    "trades": len(bucket), "percentage": fmt(100 * len(bucket) / len(rows)),
                    "cumulative_r": fmt(sum(row["r"] for row in bucket)),
                    "expectancy_r": fmt(statistics.fmean(row["r"] for row in bucket)),
                    "profit_factor_r": fmt(profit_factor([row["r"] for row in bucket])),
                })

    write_csv(output / "config_audit.csv", config_audit)
    write_csv(output / "join_audit.csv", [audit2, audit3])
    write_csv(output / "signal_equivalence_audit.csv", signal_audit)
    write_csv(output / "strategy_2r_3r_summary.csv", summaries)
    write_csv(output / "strategy_2r_3r_window_summary.csv", windows)
    write_csv(output / "strategy_2r_3r_monthly.csv", monthly)
    write_csv(output / "strategy_2r_3r_quarterly.csv", quarterly)
    write_csv(output / "strategy_2r_3r_outlier_checks.csv", outliers)
    write_csv(output / "strategy_2r_3r_core_overlap.csv", overlaps)
    write_csv(output / "strategy_2r_3r_trade_path.csv", path_comparison)
    write_csv(output / "strategy_2r_3r_exit_audit.csv", exit_rows)
    write_csv(output / "strategy_2r_3r_regime_summary.csv", regimes)

    s2, s3 = summaries
    o2, o3 = outliers
    lines = [
        "# D027 Stage 5 — limited SweepReclaim 3R screen", "",
        "SweepReclaim was the only Stage 4 family eligible for this single predefined "
        "3R run. The frozen trigger and sequence journals are unchanged; only the "
        "fixed target changes from 2R to 3R.", "",
        "## Headline comparison", "",
        "| Variant | Trades | Expectancy R | PF | Cumulative R | Max DD R |",
        "|---|---:|---:|---:|---:|---:|",
        f"| 2R | {s2['trades']} | {s2['expectancy_r']} | {s2['profit_factor_r']} | "
        f"{s2['cumulative_r']} | {s2['max_drawdown_r']} |",
        f"| 3R | {s3['trades']} | {s3['expectancy_r']} | {s3['profit_factor_r']} | "
        f"{s3['cumulative_r']} | {s3['max_drawdown_r']} |", "",
        "## Decision", "",
        "The 3R variant remains positive full-window and after its top three trades, "
        f"but it falls to {o3['excluding_best_quarter_r']}R without its best quarter "
        "and is negative in the final holdout. It also lowers cumulative R, expectancy, "
        "and PF while increasing maximum drawdown versus 2R. Therefore 3R is rejected "
        "as the preferred fixed target; frozen 2R remains the research candidate for "
        "Stage 6 portfolio testing. This is not production promotion.", "",
        "Raw candidate sets are identical and sequence journals are byte-identical. "
        "The executed trade counts differ only because the wider target changes how "
        "long ownership remains occupied, which causally changes later execution "
        "eligibility. No standalone returns are arithmetically combined.", "",
    ]
    (output / "stage5_findings.md").write_text("\n".join(lines), encoding="utf-8")
    manifest = []
    for path in sorted(output.glob("*.csv")) + [output / "stage5_findings.md"]:
        manifest.append(f"{path.name}  {hashlib.sha256(path.read_bytes()).hexdigest()}")
    (output / "output_sha256.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage4-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results"))
    parser.add_argument("--stage5-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage5_Results"))
    parser.add_argument("--core-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage2_Results/FastMedConfluence"))
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    analyze(args.stage4_root, args.stage5_root, args.core_root, args.output_dir)


if __name__ == "__main__":
    main()
