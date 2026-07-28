#!/usr/bin/env python3
"""D027 final deterministic entry-time regime threshold sensitivity."""

from __future__ import annotations

import argparse
import csv
import hashlib
import statistics
from collections import defaultdict
from datetime import datetime
from pathlib import Path

EXISTING = (
    "FastBreakout", "MediumBreakout", "SlowBreakout", "FastMedConfluence",
    "FastMedContext", "MedSlowContext", "NestedPullback", "WeightedEnsemble",
)
NEW = (
    "AlignedFastPullback", "BreakoutRetest", "SweepReclaim",
    "CompressionBreakout", "StructureTransition",
)
THRESHOLDS = (
    ("normalized_atr", "CONTRACTING", "lt", (0.75, 0.80, 0.85)),
    ("normalized_atr", "EXPANDING", "gt", (1.15, 1.20, 1.25)),
    ("directional_efficiency", "WEAK", "lt", (0.30, 0.35, 0.40)),
    ("directional_efficiency", "STRONG", "gt", (0.60, 0.65, 0.70)),
    ("compression_ratio", "LOW_COMPRESSION_RATIO", "lt", (0.30, 0.35, 0.40)),
)
STRATEGY_CATEGORIES = (
    ("FastBreakout", "RESEARCH_ONLY", "Positive only under the separately authorized score override; holdout negative."),
    ("MediumBreakout", "CONTEXT_SIGNAL_ONLY", "Negative direct entry; retained only as a causal context event."),
    ("SlowBreakout", "CONTEXT_SIGNAL_ONLY", "Weak direct entry with possible transition/context information."),
    ("FastMedConfluence", "STANDALONE_VALIDATION_CANDIDATE", "Robust benchmark and untouched A/E core; still lacks genuine independent OOS."),
    ("FastMedContext", "CONTEXT_SIGNAL_ONLY", "Positive headline but 91.1% core overlap and negative unique expectancy."),
    ("MedSlowContext", "CONTEXT_SIGNAL_ONLY", "Negative direct entry; possible higher-order context only."),
    ("NestedPullback", "REDESIGN_REQUIRED", "Negative overall with persistent long/short structural asymmetry."),
    ("WeightedEnsemble", "CONTEXT_SIGNAL_ONLY", "Positive headline inherited from core overlap; unique trades lose."),
    ("AlignedFastPullback", "REDESIGN_REQUIRED", "Negative standalone and frozen filter conjunction is unreachable."),
    ("BreakoutRetest", "REJECTED", "Negative standalone and still negative under its sole frozen filter."),
    ("SweepReclaim", "RESEARCH_ONLY", "Positive robust standalone evidence, but no genuine OOS, failed portfolio addition, unavailable frozen filter."),
    ("CompressionBreakout", "REJECTED", "Control negative; filtered positive subset fails top-three and best-quarter exclusions."),
    ("StructureTransition", "REJECTED", "Negative, only 21 trades, and filter is redundant."),
)
REGIME_CATEGORIES = (
    ("direction", "RETAINED", "Causal slow-structure observer; useful descriptive side/context label."),
    ("alignment_state", "EXPLORATORY", "Auditable but strongest buckets are counterintuitive and window rankings unstable."),
    ("trend_strength", "EXPLORATORY", "NORMAL/WEAK descriptors carry information; STRONG is often too sparse."),
    ("volatility_state", "RETAINED", "EXPANDING is stable for the core and adjacent-boundary sensitivity is reported; not production-gated."),
    ("market_phase", "EXPLORATORY", "Causal phase labels are informative, but filter hypotheses did not validate robust entries."),
    ("directional_efficiency", "EXPLORATORY", "Deterministic continuous input; categorical economic meaning remains unvalidated."),
    ("compression_ratio", "EXPLORATORY", "Causal continuous input; filtered compression result is concentrated."),
    ("swing_amplitudes", "EXPLORATORY", "Retained for audit and future research; no independent edge established."),
    ("swing_durations", "EXPLORATORY", "Retained for audit and future research; no independent edge established."),
    ("FAILED_BREAK", "REJECTED", "Not causally implemented in D027 and never emitted; no proxy substituted."),
    ("RESEARCH_FILTER_policy", "REJECTED", "No family filter met promotion standards; LABEL_ONLY remains default."),
)


def read(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle, delimiter=";"))


def write(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def read_optional(path: Path) -> list[dict[str, str]]:
    return read(path) if path.exists() else []


def joined(root: Path, strategy: str) -> list[dict]:
    trades = read(root / strategy / "MSZZ_TradeAnalytics.csv")
    signals: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in read(root / strategy / "MSZZ_SignalJournal.csv"):
        if row["status"] == "EXECUTED":
            signals[row["cluster_id"]].append(row)
    regimes: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in read(root / strategy / "MSZZ_RegimeJournal.csv"):
        regimes[row["time"]].append(row)
    output = []
    for trade in trades:
        signal_matches = signals[trade["cluster_id"]]
        if len(signal_matches) != 1:
            raise ValueError(f"{strategy}: signal join")
        signal = signal_matches[0]
        regime_matches = regimes[signal["regime_snapshot_id"]]
        if len(regime_matches) != 1 or signal["time"] != signal["regime_snapshot_id"]:
            raise ValueError(f"{strategy}: entry regime join")
        regime = regime_matches[0]
        output.append({
            "r": float(trade["r_result"]),
            "normalized_atr": float(regime["normalized_atr"]),
            "directional_efficiency": float(regime["directional_efficiency"]),
            "compression_ratio": float(regime["compression_ratio"]),
        })
    return output


def gated_joined(root: Path, strategy: str) -> list[dict]:
    trades = read_optional(root / strategy / "MSZZ_TradeAnalytics.csv")
    signals: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in read(root / strategy / "MSZZ_SignalJournal.csv"):
        if row["status"] == "EXECUTED":
            signals[row["cluster_id"]].append(row)
    output = []
    for trade in trades:
        matches = signals[trade["cluster_id"]]
        if len(matches) != 1:
            raise ValueError(f"{strategy}: gated signal join")
        signal = matches[0]
        output.append({
            "r": float(trade["r_result"]), "direction": trade["direction"],
            "entry": datetime.strptime(trade["signal_time"], "%Y.%m.%d %H:%M:%S"),
            "regimes": {
                "direction": signal["regime_direction"],
                "strength": signal["regime_strength"],
                "volatility": signal["regime_volatility"],
                "alignment": signal["regime_alignment"],
                "phase": signal["regime_phase"],
            },
        })
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage2-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage2_Results"))
    parser.add_argument("--stage4-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage4_Results"))
    parser.add_argument("--stage7-root", type=Path,
                        default=Path("/Users/matt/MT5-MSZZ-TEST/D027_Stage7_Results"))
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for strategy in EXISTING + NEW:
        trades = joined(args.stage2_root if strategy in EXISTING else args.stage4_root, strategy)
        for feature, bucket, operator, values in THRESHOLDS:
            for threshold in values:
                selected = [
                    trade for trade in trades
                    if (trade[feature] < threshold if operator == "lt" else trade[feature] > threshold)
                ]
                returns = [trade["r"] for trade in selected]
                rows.append({
                    "strategy": strategy, "feature": feature, "bucket": bucket,
                    "operator": operator, "threshold": f"{threshold:.2f}",
                    "canonical": str(threshold in (0.35, 0.65, 0.80, 1.20)).lower(),
                    "trades": len(selected), "cumulative_r": f"{sum(returns):.6f}",
                    "expectancy_r": f"{statistics.fmean(returns):.6f}" if returns else "",
                    "note": "offline entry-time sensitivity; classifier and executions unchanged",
                })
    write(args.output_dir / "threshold_neighborhoods.csv", rows)
    write(args.output_dir / "strategy_decision_categories.csv", [
        {"strategy": strategy, "category": category, "rationale": rationale}
        for strategy, category, rationale in STRATEGY_CATEGORIES
    ])
    write(args.output_dir / "regime_feature_categories.csv", [
        {"feature": feature, "category": category, "rationale": rationale}
        for feature, category, rationale in REGIME_CATEGORIES
    ])
    gated_rows, monthly_rows, quarterly_rows = [], [], []
    for strategy in NEW:
        trades = gated_joined(args.stage7_root, strategy)
        returns = sorted((trade["r"] for trade in trades), reverse=True)
        total = sum(returns)
        months: dict[str, float] = defaultdict(float)
        quarters: dict[str, float] = defaultdict(float)
        regime_buckets: dict[tuple[str, str], list[float]] = defaultdict(list)
        for trade in trades:
            months[trade["entry"].strftime("%Y-%m")] += trade["r"]
            quarter = (trade["entry"].month - 1) // 3 + 1
            quarters[f"{trade['entry'].year}-Q{quarter}"] += trade["r"]
            for dimension, value in trade["regimes"].items():
                regime_buckets[(dimension, value)].append(trade["r"])
        ranked_quarters = sorted(quarters.items(), key=lambda item: (item[1], item[0]), reverse=True)
        strongest = max(regime_buckets.items(), key=lambda item: (sum(item[1]), item[0]),
                        default=(("", ""), []))
        strongest_name = f"{strongest[0][0]}={strongest[0][1]}" if strongest[0][0] else ""
        strongest_r = sum(strongest[1])
        longs = [trade["r"] for trade in trades if trade["direction"] == "LONG"]
        shorts = [trade["r"] for trade in trades if trade["direction"] == "SHORT"]
        gated_rows.append({
            "strategy": strategy, "trades": len(trades), "cumulative_r": f"{total:.6f}",
            "top_1_contribution_r": f"{sum(returns[:1]):.6f}",
            "top_3_contribution_r": f"{sum(returns[:3]):.6f}",
            "top_5_contribution_r": f"{sum(returns[:5]):.6f}",
            "excluding_top_1_r": f"{total - sum(returns[:1]):.6f}",
            "excluding_top_3_r": f"{total - sum(returns[:3]):.6f}",
            "excluding_top_5_r": f"{total - sum(returns[:5]):.6f}",
            "best_quarter": ranked_quarters[0][0] if ranked_quarters else "",
            "best_quarter_r": f"{ranked_quarters[0][1]:.6f}" if ranked_quarters else "",
            "best_two_quarters_r": f"{sum(value for _, value in ranked_quarters[:2]):.6f}",
            "excluding_best_quarter_r": f"{total - sum(value for _, value in ranked_quarters[:1]):.6f}",
            "excluding_best_two_quarters_r": f"{total - sum(value for _, value in ranked_quarters[:2]):.6f}",
            "positive_quarters": sum(value > 0 for value in quarters.values()),
            "negative_quarters": sum(value < 0 for value in quarters.values()),
            "long_trades": len(longs),
            "long_expectancy_r": f"{statistics.fmean(longs):.6f}" if longs else "",
            "long_contribution_r": f"{sum(longs):.6f}",
            "short_trades": len(shorts),
            "short_expectancy_r": f"{statistics.fmean(shorts):.6f}" if shorts else "",
            "short_contribution_r": f"{sum(shorts):.6f}",
            "strongest_regime_descriptor": strongest_name,
            "strongest_regime_trades": len(strongest[1]),
            "strongest_regime_r": f"{strongest_r:.6f}",
            "strongest_regime_profit_pct": f"{strongest_r / total * 100:.6f}" if total else "",
            "excluding_strongest_regime_r": f"{total - strongest_r:.6f}",
        })
        for month, value in sorted(months.items()):
            monthly_rows.append({"strategy": strategy, "month": month, "cumulative_r": f"{value:.6f}"})
        for quarter, value in sorted(quarters.items()):
            quarterly_rows.append({"strategy": strategy, "quarter": quarter, "cumulative_r": f"{value:.6f}"})
    write(args.output_dir / "gated_variant_anti_overfit.csv", gated_rows)
    write(args.output_dir / "gated_variant_monthly.csv", monthly_rows)
    write(args.output_dir / "gated_variant_quarterly.csv", quarterly_rows)
    manifest = []
    for path in sorted(args.output_dir.glob("*.csv")):
        manifest.append(f"{path.name}  {hashlib.sha256(path.read_bytes()).hexdigest()}")
    (args.output_dir / "output_sha256.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
