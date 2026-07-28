#!/usr/bin/env python3
"""Deterministic D027 Stage 4 standalone fixed-2R analysis."""

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
STRATEGIES = {
    "AlignedFastPullback": ("PULLBACK", "1031", "InpEnableAlignedFastPullback", "26072931"),
    "BreakoutRetest": ("RETEST", "1040", "InpEnableBreakoutRetest", "26072932"),
    "SweepReclaim": ("REVERSAL", "1050", "InpEnableSweepReclaim", "26072933"),
    "CompressionBreakout": ("COMPRESSION", "1060", "InpEnableCompressionBreakout", "26072934"),
    "StructureTransition": ("REVERSAL", "1070", "InpEnableStructureTransition", "26072935"),
}
ENABLES = [item[2] for item in STRATEGIES.values()]
EXISTING_ENABLES = (
    "InpEnableFastBreakout", "InpEnableMediumBreakout", "InpEnableSlowBreakout",
    "InpEnableFastMedConfluence", "InpEnableFastMedContext",
    "InpEnableMedSlowContext", "InpEnableNestedPullback",
    "InpEnableWeightedEnsemble",
)
WINDOWS = (
    ("Development", datetime(2025, 3, 1), datetime(2026, 1, 1)),
    ("Validation", datetime(2026, 1, 1), datetime(2026, 5, 1)),
    ("Final holdout", datetime(2026, 5, 1), datetime(2026, 7, 25)),
)
REGIME_FIELDS = ("direction", "trend_strength", "volatility_state",
                 "alignment_state", "market_phase")


def read_csv(path: Path, allow_header_only: bool = False) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=";")
        if reader.fieldnames is None:
            raise ValueError(f"missing header: {path}")
        rows = list(reader)
    if not rows and not allow_header_only:
        raise ValueError(f"no data rows: {path}")
    return rows


def write_csv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def parse_ini(path: Path) -> dict[str, str]:
    values = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if "=" in raw and not raw.lstrip().startswith(";"):
            key, value = raw.split("=", 1)
            values[key] = value.split("||", 1)[0]
    return values


def stamp(value: str) -> datetime:
    return datetime.strptime(value, DT_FMT)


def num(value: str) -> float:
    return float(value)


def fmt(value: float) -> str:
    if math.isinf(value):
        return "inf"
    return f"{value:.6f}"


def window(entry: datetime) -> str:
    found = [name for name, start, end in WINDOWS if start <= entry < end]
    if len(found) != 1:
        raise ValueError(f"entry outside frozen windows: {entry}")
    return found[0]


def pf(values: list[float]) -> float:
    gains = sum(value for value in values if value > 0)
    losses = -sum(value for value in values if value < 0)
    if losses == 0:
        return math.inf if gains else 0.0
    return gains / losses


def drawdown(values: list[float]) -> float:
    equity = peak = worst = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        worst = max(worst, peak - equity)
    return worst


def percentile(values: list[float], proportion: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = (len(ordered) - 1) * proportion
    low, high = math.floor(index), math.ceil(index)
    if low == high:
        return ordered[low]
    return ordered[low] * (high - index) + ordered[high] * (index - low)


def sample_label(count: int) -> str:
    if count < 20:
        return "INSUFFICIENT"
    if count < 50:
        return "EXPLORATORY"
    if count < 100:
        return "MODERATE_SAMPLE"
    return "STRONGER_DESCRIPTIVE_SAMPLE"


def metrics(strategy: str, scope: str, rows: list[dict]) -> dict[str, object]:
    ordered = sorted(rows, key=lambda row: (row["entry_dt"], row["cluster_id"]))
    values = [row["r"] for row in ordered]
    wins = sum(value > 0 for value in values)
    longs = [row["r"] for row in rows if row["trade_direction"] == "LONG"]
    shorts = [row["r"] for row in rows if row["trade_direction"] == "SHORT"]
    held = [row["bars"] for row in rows]
    start = min(row["entry_dt"] for row in rows)
    end = max(row["close_dt"] for row in rows)
    wall_bars = max(1.0, (end - start).total_seconds() / 300.0)
    return {
        "strategy": strategy, "family": STRATEGIES[strategy][0], "scope": scope,
        "trades": len(rows), "wins": wins, "losses": sum(value < 0 for value in values),
        "win_rate": fmt(wins / len(rows)), "cumulative_r": fmt(sum(values)),
        "expectancy_r": fmt(statistics.fmean(values)), "profit_factor_r": fmt(pf(values)),
        "max_drawdown_r": fmt(drawdown(values)), "median_r": fmt(statistics.median(values)),
        "average_mfe_r": fmt(statistics.fmean(row["mfe"] for row in rows)),
        "average_mae_r": fmt(statistics.fmean(row["mae"] for row in rows)),
        "median_hold_bars": fmt(statistics.median(held)),
        "p90_hold_bars": fmt(percentile(held, .90)),
        "wall_clock_exposure_pct": fmt(100 * sum(held) / wall_bars),
        "long_trades": len(longs), "long_expectancy_r": fmt(statistics.fmean(longs) if longs else 0),
        "short_trades": len(shorts), "short_expectancy_r": fmt(statistics.fmean(shorts) if shorts else 0),
        "first_entry_time": start.strftime(DT_FMT), "last_exit_time": end.strftime(DT_FMT),
    }


def main_analysis(root: Path, core_root: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    trades_all: list[dict] = []
    config_audit: list[dict[str, object]] = []
    join_audit: list[dict[str, object]] = []
    exit_audit: list[dict[str, object]] = []

    core_signals = read_csv(core_root / "MSZZ_SignalJournal.csv")
    core_exec = [row for row in core_signals if row["status"] == "EXECUTED"]
    core_same_bar = {(row["time"], row["direction"]) for row in core_exec}
    core_origins = {row["origin_id"] for row in core_exec}

    for strategy, (_, strategy_id, enabled_key, expected_magic) in STRATEGIES.items():
        run = root / strategy
        ini_name = f"d027_stage4_{strategy}.ini"
        required = ("MSZZ_RunSummary.csv", "MSZZ_TradeAnalytics.csv",
                    "MSZZ_SignalJournal.csv", "MSZZ_RegimeJournal.csv",
                    f"D027_Stage4_{strategy}.htm", ini_name)
        missing = [name for name in required if not (run / name).is_file()
                   or (run / name).stat().st_size == 0]
        if missing:
            errors.append(f"{strategy}: missing/empty {', '.join(missing)}")
            continue

        config = parse_ini(run / ini_name)
        enabled = [key for key in ENABLES if config.get(key) == "true"]
        config_ok = (
            config.get("Symbol") == "XAUUSD" and config.get("Period") == "M5"
            and config.get("Model") == "2" and config.get("FromDate") == "2025.03.01"
            and config.get("ToDate") == "2026.07.24" and config.get("InpMagic") == expected_magic
            and enabled == [enabled_key] and config.get("InpRiskReward") == "2.0"
            and all(config.get(key) == "false" for key in EXISTING_ENABLES)
            and config.get("InpExitOwnedOpposite") == "true"
            and config.get("InpRegimeEligibilityMode") == "0"
            and config.get("InpResearchMinScoreOverride") == "0.0"
            and config.get("InpAcknowledgeResearchOverride") == "false"
            and config.get("InpDisableFixedTarget") == "false"
            and config.get("InpPartialCloseAtR") == "0.0"
            and config.get("InpEnableResearchTrail") == "false")
        config_audit.append({"strategy": strategy, "magic": expected_magic,
                             "enabled": ",".join(enabled), "status": "PASS" if config_ok else "FAIL"})
        if not config_ok:
            errors.append(f"{strategy}: config integrity failed")

        summary_rows = read_csv(run / "MSZZ_RunSummary.csv")
        analytics = read_csv(run / "MSZZ_TradeAnalytics.csv", allow_header_only=True)
        signals = read_csv(run / "MSZZ_SignalJournal.csv", allow_header_only=True)
        regimes = read_csv(run / "MSZZ_RegimeJournal.csv")
        if len(summary_rows) != 1:
            errors.append(f"{strategy}: summary rows={len(summary_rows)}")
            continue
        summary = summary_rows[0]
        expected = int(summary["trades"])
        html = (run / f"D027_Stage4_{strategy}.htm").read_text(encoding="utf-16")
        html_trades_match = re.search(r"Total Trades:</td>\s*<td nowrap><b>(\d+)</b>", html)
        html_deals_match = re.search(r"Total Deals:</td>\s*<td nowrap><b>(\d+)</b>", html)
        html_trades = int(html_trades_match.group(1)) if html_trades_match else -1
        html_deals = int(html_deals_match.group(1)) if html_deals_match else -1
        if html_trades != expected or html_deals != expected * 2:
            errors.append(f"{strategy}: HTML trades/deals={html_trades}/{html_deals}, expected {expected}/{expected * 2}")
        if summary["magic"] != expected_magic or summary["symbol"] != "XAUUSD" \
                or summary["timeframe"] != "PERIOD_M5" or summary["risk_reward"] != "2.00" \
                or summary["enabled_strategies"] != strategy:
            errors.append(f"{strategy}: run summary identity mismatch")
        if expected != len(analytics):
            errors.append(f"{strategy}: summary={expected}, analytics={len(analytics)}")

        executed: dict[str, list[dict[str, str]]] = defaultdict(list)
        raw_by_fill_minute_direction: set[tuple[datetime, str]] = set()
        for signal in signals:
            if signal["status"] == "EXECUTED":
                executed[signal["cluster_id"]].append(signal)
            if signal["status"] in ("RAW_CANDIDATE", "EXECUTED"):
                decision = stamp(signal["time"])
                raw_by_fill_minute_direction.add((decision.replace(second=0), signal["direction"]))
                raw_by_fill_minute_direction.add(
                    ((decision.replace(second=0).timestamp() + 300), signal["direction"]))
        regime_map: dict[str, list[dict[str, str]]] = defaultdict(list)
        for regime in regimes:
            regime_map[regime["time"]].append(regime)

        matched = missing_signal = duplicate_signal = missing_regime = duplicate_regime = 0
        own_opposite = unknown_other = test_end = 0
        for trade in analytics:
            sigs = executed.get(trade["cluster_id"], [])
            if len(sigs) != 1:
                missing_signal += len(sigs) == 0
                duplicate_signal += len(sigs) > 1
                continue
            signal = sigs[0]
            regs = regime_map.get(signal["regime_snapshot_id"], [])
            if len(regs) != 1:
                missing_regime += len(regs) == 0
                duplicate_regime += len(regs) > 1
                continue
            regime = regs[0]
            if signal["strategy_id"] != strategy_id or signal["eligibility_mode"] != "LABEL_ONLY" \
                    or signal["eligibility_result"] != "true":
                errors.append(f"{strategy}: signal identity/eligibility mismatch {trade['cluster_id']}")
                continue
            if signal["time"] != trade["signal_time"] or signal["time"] != signal["regime_snapshot_id"]:
                errors.append(f"{strategy}: entry-time snapshot mismatch {trade['cluster_id']}")
                continue
            if signal["regime_direction"] != regime["direction"] \
                    or signal["regime_alignment"] != regime["alignment_state"] \
                    or signal["regime_phase"] != regime["market_phase"]:
                errors.append(f"{strategy}: regime labels disagree {trade['cluster_id']}")
                continue
            entry_dt, close_dt = stamp(trade["signal_time"]), stamp(trade["close_time"])
            opposite = "SHORT" if trade["direction"] == "LONG" else "LONG"
            reason = trade["exit_reason"]
            exit_class = reason
            if reason == "OTHER":
                close_minute = close_dt.replace(second=0)
                # Signals are decided on a closed bar and fill/close on the next
                # bar. Retain a same-minute allowance for synthetic tester fills.
                fill_keys = {
                    (close_minute, opposite),
                    (close_minute.timestamp(), opposite),
                }
                if any(key in raw_by_fill_minute_direction for key in fill_keys):
                    exit_class = "OWN_FAMILY_OPPOSITE"
                    own_opposite += 1
                # The broker's last modeled tick for the declared 2026-07-24
                # tester end is stamped 2026-07-23 23:59:59.
                elif close_dt >= datetime(2026, 7, 23, 23, 50):
                    exit_class = "TEST_END"
                    test_end += 1
                else:
                    exit_class = "UNKNOWN_OTHER"
                    unknown_other += 1
            row = {
                "strategy": strategy, "cluster_id": trade["cluster_id"],
                "origin_id": signal["origin_id"], "trade_direction": trade["direction"],
                "entry_dt": entry_dt, "close_dt": close_dt, "window": window(entry_dt),
                "r": num(trade["r_result"]), "mfe": num(trade["mfe_r"]),
                "mae": num(trade["mae_r"]), "bars": int(trade["bars_held"]),
                "exit_class": exit_class,
            }
            for field in REGIME_FIELDS:
                row[field] = regime[field]
            row["core_same_bar"] = (signal["time"], signal["direction"]) in core_same_bar
            row["core_shared_origin"] = signal["origin_id"] in core_origins
            trades_all.append(row)
            matched += 1

        status = matched == len(analytics) == expected and not any(
            (missing_signal, duplicate_signal, missing_regime, duplicate_regime))
        join_audit.append({
            "strategy": strategy, "summary_trades": expected, "analytics_trades": len(analytics),
            "html_trades": html_trades, "html_deals": html_deals,
            "matched_trades": matched, "missing_signal": missing_signal,
            "duplicate_signal": duplicate_signal, "missing_regime": missing_regime,
            "duplicate_regime": duplicate_regime, "status": "PASS" if status else "FAIL"})
        exit_audit.append({
            "strategy": strategy, "sl": sum(r["exit_reason"] == "SL" for r in analytics),
            "tp": sum(r["exit_reason"] == "TP" for r in analytics),
            "own_family_opposite": own_opposite, "cross_family_opposite": 0,
            "test_end": test_end, "unknown_other": unknown_other})
        if (sum(r["exit_reason"] == "SL" for r in analytics)
                + sum(r["exit_reason"] == "TP" for r in analytics)
                + own_opposite + test_end + unknown_other != len(analytics)):
            errors.append(f"{strategy}: exit classes do not reconcile")
        if not status:
            errors.append(f"{strategy}: attribution join failed")

    write_csv(output / "config_audit.csv", config_audit,
              ["strategy", "magic", "enabled", "status"])
    write_csv(output / "trade_regime_join_audit.csv", join_audit,
              ["strategy", "summary_trades", "analytics_trades", "html_trades", "html_deals", "matched_trades",
               "missing_signal", "duplicate_signal", "missing_regime", "duplicate_regime", "status"])
    write_csv(output / "exit_audit.csv", exit_audit,
              ["strategy", "sl", "tp", "own_family_opposite", "cross_family_opposite",
               "test_end", "unknown_other"])
    if errors:
        raise RuntimeError("\n".join(errors))

    metric_fields = list(metrics(trades_all[0]["strategy"], "probe", [trades_all[0]]))
    totals, windows = [], []
    for strategy in STRATEGIES:
        rows = [row for row in trades_all if row["strategy"] == strategy]
        if not rows:
            continue
        totals.append(metrics(strategy, "Full window", rows))
        window_count = 0
        for name, _, _ in WINDOWS:
            subset = [row for row in rows if row["window"] == name]
            if subset:
                window_count += len(subset)
                windows.append(metrics(strategy, name, subset))
        if window_count != len(rows):
            raise RuntimeError(f"{strategy}: frozen-window counts do not reconcile")
        if sum(row["trade_direction"] == "LONG" for row in rows) \
                + sum(row["trade_direction"] == "SHORT" for row in rows) != len(rows):
            raise RuntimeError(f"{strategy}: long/short counts do not reconcile")
        window_r = sum(row["r"] for row in rows)
        partition_r = sum(row["r"] for row in rows
                          if row["window"] in {item[0] for item in WINDOWS})
        if abs(window_r - partition_r) > 1e-9:
            raise RuntimeError(f"{strategy}: frozen-window R does not reconcile")
    write_csv(output / "strategy_summary.csv", totals, metric_fields)
    write_csv(output / "strategy_window_summary.csv", windows, metric_fields)

    quarterly = []
    for strategy in STRATEGIES:
        groups: dict[str, list[dict]] = defaultdict(list)
        for row in trades_all:
            if row["strategy"] == strategy:
                groups[f"{row['entry_dt'].year}-Q{(row['entry_dt'].month - 1)//3 + 1}"].append(row)
        for quarter, rows in sorted(groups.items()):
            quarterly.append({"strategy": strategy, "quarter": quarter, "trades": len(rows),
                              "cumulative_r": fmt(sum(row["r"] for row in rows)),
                              "expectancy_r": fmt(statistics.fmean(row["r"] for row in rows))})
    write_csv(output / "strategy_quarterly.csv", quarterly,
              ["strategy", "quarter", "trades", "cumulative_r", "expectancy_r"])

    outliers, overlaps, regimes = [], [], []
    for strategy in STRATEGIES:
        rows = [row for row in trades_all if row["strategy"] == strategy]
        if not rows:
            continue
        values = sorted((row["r"] for row in rows), reverse=True)
        quarters = [num(row["cumulative_r"]) for row in quarterly if row["strategy"] == strategy]
        sorted_quarters = sorted(quarters, reverse=True)
        outliers.append({
            "strategy": strategy, "trades": len(rows), "cumulative_r": fmt(sum(values)),
            "excluding_top_1_r": fmt(sum(values[1:])), "excluding_top_3_r": fmt(sum(values[3:])),
            "excluding_top_5_r": fmt(sum(values[5:])),
            "excluding_best_quarter_r": fmt(sum(quarters) - max(quarters)),
            "excluding_best_two_quarters_r": fmt(sum(quarters) - sum(sorted_quarters[:2])),
            "positive_quarters": sum(value > 0 for value in quarters),
            "negative_quarters": sum(value < 0 for value in quarters)})
        same = [row for row in rows if row["core_same_bar"]]
        shared = [row for row in rows if row["core_shared_origin"]]
        unique = [row for row in rows if not row["core_same_bar"]]
        overlaps.append({
            "strategy": strategy, "trades": len(rows),
            "same_bar_direction_core_trades": len(same),
            "same_bar_direction_core_r": fmt(sum(row["r"] for row in same)),
            "shared_origin_core_trades": len(shared),
            "shared_origin_core_r": fmt(sum(row["r"] for row in shared)),
            "unique_vs_core_same_bar_trades": len(unique),
            "unique_vs_core_same_bar_r": fmt(sum(row["r"] for row in unique)),
            "unique_vs_core_same_bar_expectancy_r": fmt(
                statistics.fmean(row["r"] for row in unique) if unique else 0)})
        for field in REGIME_FIELDS:
            groups = defaultdict(list)
            for row in rows:
                groups[row[field]].append(row)
            for value, bucket in sorted(groups.items()):
                regimes.append({
                    "strategy": strategy, "dimension": field, "value": value,
                    "sample_label": sample_label(len(bucket)), "trades": len(bucket),
                    "percentage": fmt(100 * len(bucket) / len(rows)),
                    "cumulative_r": fmt(sum(row["r"] for row in bucket)),
                    "expectancy_r": fmt(statistics.fmean(row["r"] for row in bucket)),
                    "profit_factor_r": fmt(pf([row["r"] for row in bucket]))})
    write_csv(output / "strategy_outlier_checks.csv", outliers, list(outliers[0]))
    write_csv(output / "strategy_core_overlap.csv", overlaps, list(overlaps[0]))
    write_csv(output / "strategy_regime_summary.csv", regimes, list(regimes[0]))

    lines = [
        "# D027 Stage 4 deterministic standalone screen", "",
        "All five families were screened alone at fixed 2R on the frozen history split. "
        "Regimes are joined at the entry decision. No threshold was changed, no regime "
        "gate was applied, and no strategy was promoted by this analysis.", "",
        "## Full-window results", "",
        "| Strategy | Trades | Expectancy R | PF | Cumulative R | Max DD R |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for row in totals:
        lines.append(f"| {row['strategy']} | {row['trades']} | {row['expectancy_r']} | "
                     f"{row['profit_factor_r']} | {row['cumulative_r']} | {row['max_drawdown_r']} |")
    lines += ["", "## Window-separated results", "",
              "| Strategy | Window | Trades | Expectancy R | Cumulative R |",
              "|---|---|---:|---:|---:|"]
    for row in windows:
        lines.append(f"| {row['strategy']} | {row['scope']} | {row['trades']} | "
                     f"{row['expectancy_r']} | {row['cumulative_r']} |")
    lines += ["", "## Stage 5 eligibility screen", ""]
    by_name = {row["strategy"]: row for row in totals}
    out_by_name = {row["strategy"]: row for row in outliers}
    overlap_by_name = {row["strategy"]: row for row in overlaps}
    for strategy in STRATEGIES:
        row, out, overlap = by_name[strategy], out_by_name[strategy], overlap_by_name[strategy]
        qualifies = (num(row["expectancy_r"]) > 0 and num(row["profit_factor_r"]) > 1.05
                     and int(row["trades"]) >= 75 and num(out["excluding_top_3_r"]) > 0
                     and num(overlap["unique_vs_core_same_bar_r"]) > 0)
        lines.append(f"- `{strategy}`: **{'ELIGIBLE' if qualifies else 'NOT ELIGIBLE'}** "
                     f"for the later one-off 3R check under the frozen mechanical screen.")
    lines += ["", "Same-bar overlap means the canonical FastMedConfluence baseline emitted "
              "an executed signal with the same decision time and direction. Shared-origin "
              "overlap is reported separately. “Unique” uses the stricter practical same-bar "
              "definition and is descriptive, not proof of independent edge.", "",
              "Wall-clock exposure is summed holding bars divided by elapsed wall-clock M5 "
              "bars; it is not MT5 margin exposure. Spread is naturally present in tester "
              "fills; the configurations use the canonical 80-point spread guard and "
              "30-point deviation. No separate commission-R estimate is invented.", ""]
    (output / "stage4_findings.md").write_text("\n".join(lines), encoding="utf-8")

    manifest = []
    for path in sorted(output.glob("*.csv")) + [output / "stage4_findings.md"]:
        manifest.append(f"{path.name}  {hashlib.sha256(path.read_bytes()).hexdigest()}")
    (output / "output_sha256.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results"))
    parser.add_argument("--core-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage2_Results/FastMedConfluence"))
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    main_analysis(args.input_root, args.core_root, args.output_dir)


if __name__ == "__main__":
    main()
