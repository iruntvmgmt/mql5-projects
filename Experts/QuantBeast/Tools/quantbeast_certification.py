#!/usr/bin/env python3
"""QuantBeast Level-1 Edge Certification -- statistics toolkit (Stage 2).

Computes the extended trade-level statistics required by the Level-1 Edge
Certification Sprint (see TestEvidence/level1_edge_certification_20260724/)
on top of the same byte-bounded TradeJournal.csv/SignalJournal.csv reading
pipeline already proven by `strategy_performance_report.py`: expectancy,
profit factor, win rate, average win/loss, Sharpe, Sortino, max drawdown,
recovery factor, longest losing streak, exposure time, monthly/session/
regime attribution, cost attribution, profit concentration, and a bootstrap
confidence interval for expectancy.

This module intentionally does NOT compute Deflated Sharpe Ratio,
Probability of Backtest Overfitting, Monte Carlo trade-order reshuffling,
or walk-forward splits -- those are portfolio/multi-run robustness checks
that require the full certification run-matrix and the research-trial
ledger's conservative trial count, and are scoped to a later stage of the
same sprint, not this per-run stats module.

Every formula here is self-validated against `TestEvidence/
performance_readiness_20260716/TradeJournal_combined_train_suffix.csv`
(5 real trades) whose independently-computed reference numbers already
exist in `combined_train_metrics.csv` from an earlier, unrelated report --
see `Tools/quantbeast_certification_selftest.py`. Do not trust a number
from this module for a certification verdict unless that selftest passes.

Descriptive statistics only, exactly like `strategy_performance_report.py`.
No output of this script constitutes a profitability claim by itself --
that judgment is made only by the Stage 4 predeclared-gate evaluation
against a full certification run, never against a single ad hoc run.

Dependency-free (stdlib only), matching the other Tools/*.py scripts.
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
from strategy_performance_report import (  # noqa: E402
    signal_rows,
    table,
    to_float,
    trade_rows,
)

MT5_TIME_FMT = "%Y.%m.%d %H:%M:%S"


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------


def parse_mt5_time(value: str) -> Optional[datetime]:
    value = (value or "").strip()
    if not value:
        return None
    try:
        return datetime.strptime(value, MT5_TIME_FMT)
    except ValueError:
        return None


def load_trades(path: Path, offset: int = 0, end_offset: Optional[int] = None) -> List[dict]:
    """Trades ordered by ExitTime (falls back to file order if unparseable),
    matching the chronological-equity-curve assumption every stat below
    depends on."""
    rows = list(trade_rows(path, offset, end_offset))
    for r in rows:
        r["_exit_dt"] = parse_mt5_time(r.get("ExitTime", ""))
        r["_entry_dt"] = parse_mt5_time(r.get("EntryTime", ""))
        r["_net"] = to_float(r, "NetPnL")
        r["_r"] = to_float(r, "RMultiple")
    # Stable sort: rows with unparseable timestamps keep their file order,
    # appended after any parseable ones -- never silently reordered further.
    with_dt = [r for r in rows if r["_exit_dt"] is not None]
    without_dt = [r for r in rows if r["_exit_dt"] is None]
    with_dt.sort(key=lambda r: r["_exit_dt"])
    return with_dt + without_dt


# ---------------------------------------------------------------------------
# Core per-trade statistics
# ---------------------------------------------------------------------------


def profit_factor(net_pnls: Sequence[float]) -> float:
    gross_profit = sum(p for p in net_pnls if p > 0)
    gross_loss = -sum(p for p in net_pnls if p < 0)
    if gross_loss == 0:
        return float("inf") if gross_profit > 0 else float("nan")
    return gross_profit / gross_loss


def max_drawdown_currency(net_pnls_in_order: Sequence[float]) -> float:
    """Running-peak drawdown over the cumulative NetPnL equity curve, in the
    same order as `combined_train_metrics.csv`'s `closed_trade_running_max_dd`
    (file/EntryTime order) -- reproduced exactly as the selftest baseline."""
    cum = 0.0
    peak = 0.0
    max_dd = 0.0
    for p in net_pnls_in_order:
        cum += p
        peak = max(peak, cum)
        max_dd = max(max_dd, peak - cum)
    return max_dd


def longest_losing_streak(net_pnls_in_order: Sequence[float]) -> int:
    longest = current = 0
    for p in net_pnls_in_order:
        if p < 0:
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return longest


def sharpe_per_trade(r_multiples: Sequence[float]) -> float:
    """Trade-level Sharpe: mean(R) / stdev(R). NOT an annualized Sharpe --
    there is no fixed trade frequency to annualize against, and mixing that
    up is exactly the kind of overstated-confidence mistake this sprint
    exists to avoid. Report as-is, label it "per-trade" everywhere it's
    surfaced."""
    if len(r_multiples) < 2:
        return float("nan")
    sd = statistics.stdev(r_multiples)
    if sd == 0:
        return float("nan")
    return statistics.fmean(r_multiples) / sd


def sortino_per_trade(r_multiples: Sequence[float]) -> float:
    """Same per-trade caveat as sharpe_per_trade, but downside deviation
    only (over losing trades' R, against a 0 minimum acceptable return)."""
    if len(r_multiples) < 2:
        return float("nan")
    downside = [min(0.0, r) for r in r_multiples]
    downside_sq_mean = statistics.fmean(x * x for x in downside)
    dd = downside_sq_mean ** 0.5
    if dd == 0:
        return float("nan")
    return statistics.fmean(r_multiples) / dd


def bootstrap_ci_mean(values: Sequence[float], iterations: int = 5000,
                       alpha: float = 0.05, seed: int = 20260724) -> Dict[str, float]:
    """Percentile bootstrap CI for the mean. Fixed seed so a re-run of the
    same input reproduces the identical interval -- required for the
    evidence pack's "reproducible with the recorded seed" discipline."""
    n = len(values)
    if n == 0:
        return {"low": float("nan"), "high": float("nan"), "point": float("nan")}
    rng = random.Random(seed)
    means = []
    for _ in range(iterations):
        sample = [values[rng.randrange(n)] for _ in range(n)]
        means.append(statistics.fmean(sample))
    means.sort()
    lo_idx = int((alpha / 2) * iterations)
    hi_idx = int((1 - alpha / 2) * iterations) - 1
    return {
        "low": means[max(0, lo_idx)],
        "high": means[min(iterations - 1, hi_idx)],
        "point": statistics.fmean(values),
        "iterations": iterations,
        "seed": seed,
    }


def exposure_seconds(trade: dict) -> Optional[float]:
    if trade["_entry_dt"] is None or trade["_exit_dt"] is None:
        return None
    return (trade["_exit_dt"] - trade["_entry_dt"]).total_seconds()


def month_key(trade: dict) -> str:
    dt = trade["_exit_dt"]
    return dt.strftime("%Y-%m") if dt else "UNKNOWN"


# ---------------------------------------------------------------------------
# Aggregate report
# ---------------------------------------------------------------------------


def certification_stats(trades: List[dict]) -> dict:
    """Full stat block for one group of trades, already ordered by ExitTime
    (see load_trades). Every trade-count-dependent stat returns NaN/None
    cleanly on n=0 rather than raising -- callers (including the Stage 3/4
    gate evaluator) must check `n` before trusting anything else here."""
    n = len(trades)
    net_pnls = [t["_net"] for t in trades]
    r_multiples = [t["_r"] for t in trades]
    wins = [p for p in net_pnls if p > 0]
    losses = [p for p in net_pnls if p < 0]
    breakeven = n - len(wins) - len(losses)

    gross_profit = sum(wins)
    gross_loss = -sum(losses)
    net_total = sum(net_pnls)
    commission_total = sum(to_float(t, "Commission") for t in trades)
    swap_total = sum(to_float(t, "Swap") for t in trades)

    by_month: Dict[str, List[dict]] = defaultdict(list)
    for t in trades:
        by_month[month_key(t)].append(t)
    monthly_net = {m: sum(x["_net"] for x in ts) for m, ts in sorted(by_month.items())}
    nonneg_months = sum(1 for v in monthly_net.values() if v >= 0)

    exposures = [e for e in (exposure_seconds(t) for t in trades) if e is not None]

    best_trade = max(net_pnls, default=0.0)
    best_month = max(monthly_net.values(), default=0.0)

    stats = {
        "n": n,
        "wins": len(wins),
        "losses": len(losses),
        "breakeven": breakeven,
        "win_rate": (len(wins) / n) if n else float("nan"),
        "expectancy_r": statistics.fmean(r_multiples) if n else float("nan"),
        "median_r": statistics.median(r_multiples) if n else float("nan"),
        "avg_win": statistics.fmean(wins) if wins else float("nan"),
        "avg_loss": statistics.fmean(losses) if losses else float("nan"),
        "gross_profit": gross_profit,
        "gross_loss": gross_loss,
        "net_pnl": net_total,
        "profit_factor": profit_factor(net_pnls),
        "commission_total": commission_total,
        "swap_total": swap_total,
        "broker_cost_total": commission_total + swap_total,
        "max_drawdown_currency": max_drawdown_currency(net_pnls),
        "recovery_factor": (net_total / max_drawdown_currency(net_pnls))
        if max_drawdown_currency(net_pnls) > 0 else float("nan"),
        "longest_losing_streak": longest_losing_streak(net_pnls),
        "sharpe_per_trade": sharpe_per_trade(r_multiples),
        "sortino_per_trade": sortino_per_trade(r_multiples),
        "months_tested": len(monthly_net),
        "months_nonnegative": nonneg_months,
        "months_nonnegative_pct": (nonneg_months / len(monthly_net)) if monthly_net else float("nan"),
        "monthly_net": monthly_net,
        "best_trade_pnl": best_trade,
        "best_trade_pct_of_gross_profit": (best_trade / gross_profit) if gross_profit > 0 else float("nan"),
        "best_month_pnl": best_month,
        "best_month_pct_of_net": (best_month / net_total) if net_total != 0 else float("nan"),
        "exposure_seconds_total": sum(exposures) if exposures else float("nan"),
        "exposure_seconds_mean": statistics.fmean(exposures) if exposures else float("nan"),
        "exposure_missing_count": n - len(exposures),
        "bootstrap_expectancy_r_ci": bootstrap_ci_mean(r_multiples) if n else None,
    }
    return stats


def fmt(x) -> str:
    if x is None:
        return "n/a"
    if isinstance(x, float):
        if x != x:  # NaN
            return "n/a"
        if x in (float("inf"), float("-inf")):
            return str(x)
        return f"{x:.4f}"
    return str(x)


def stats_table(label: str, stats: dict) -> str:
    keys = [
        "n", "wins", "losses", "breakeven", "win_rate", "expectancy_r", "median_r",
        "avg_win", "avg_loss", "gross_profit", "gross_loss", "net_pnl", "profit_factor",
        "commission_total", "swap_total", "broker_cost_total", "max_drawdown_currency",
        "recovery_factor", "longest_losing_streak", "sharpe_per_trade", "sortino_per_trade",
        "months_tested", "months_nonnegative", "months_nonnegative_pct",
        "best_trade_pnl", "best_trade_pct_of_gross_profit", "best_month_pnl",
        "best_month_pct_of_net", "exposure_seconds_mean", "exposure_missing_count",
    ]
    body = [[k, fmt(stats.get(k))] for k in keys]
    ci = stats.get("bootstrap_expectancy_r_ci")
    if ci:
        body.append(["bootstrap_expectancy_r_ci",
                      f"[{fmt(ci['low'])}, {fmt(ci['high'])}] (point={fmt(ci['point'])}, "
                      f"n_iter={ci['iterations']}, seed={ci['seed']})"])
    return table(["Metric", label], body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--trade-journal", required=True, type=Path)
    parser.add_argument("--trade-offset", type=int, default=0)
    parser.add_argument("--trade-end-offset", type=int, default=None)
    parser.add_argument("--run-id", default="", help="Label for the report heading / provenance")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of a markdown table")
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()

    trades = load_trades(args.trade_journal, args.trade_offset, args.trade_end_offset)
    stats = certification_stats(trades)

    if args.json:
        text = json.dumps(stats, default=str, indent=2)
    else:
        lines = [
            f"# Certification statistics -- {args.run_id or 'unlabeled run'}",
            "",
            "## Provenance",
            "",
            "- Generator: `Tools/quantbeast_certification.py`",
            f"- TradeJournal source: `{args.trade_journal}` bytes "
            f"[{args.trade_offset},{args.trade_end_offset})",
            f"- Trades read: {len(trades)}",
            "- Ordering: by ExitTime (chronological equity-curve assumption); "
            "unparseable timestamps appended in file order, never dropped.",
            "- Sharpe/Sortino here are PER-TRADE (mean/stdev of R across trades), "
            "not annualized -- do not compare directly to an annualized equity-curve Sharpe.",
            "",
            stats_table(args.run_id or "value", stats),
        ]
        text = "\n".join(lines)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
