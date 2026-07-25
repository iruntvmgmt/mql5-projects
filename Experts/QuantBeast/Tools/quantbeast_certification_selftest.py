#!/usr/bin/env python3
"""Self-validation for quantbeast_certification.py (Level-1 Edge
Certification Sprint, Stage 2).

Recomputes stats against `TestEvidence/performance_readiness_20260716/
TradeJournal_combined_train_suffix.csv` (5 real trades from an earlier,
unrelated report) and asserts they match the independently-computed
reference numbers already recorded in that folder's own
`combined_train_metrics.csv` (net_sum, gross_profit, gross_loss,
profit_factor, wins, losses, closed_trade_running_max_dd). That reference
file was produced by different code, for a different purpose, before this
certification sprint existed -- agreement here is real evidence the new
formulas are not silently wrong, not just internal self-consistency.

Also hand-verifies longest_losing_streak against the same 5 trades
(sequence is W,L,L,L,L by NetPnL sign in ExitTime order -> streak of 4),
which has no prior-script reference to check against.

Exit code 0 and "ALL CHECKS PASSED" only if every assertion holds.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from quantbeast_certification import certification_stats, load_trades  # noqa: E402

FIXTURE = (
    Path(__file__).resolve().parent.parent
    / "TestEvidence" / "performance_readiness_20260716" / "TradeJournal_combined_train_suffix.csv"
)

# Reference values transcribed verbatim from combined_train_metrics.csv,
# generated 2026-07-16 by unrelated code, before this sprint existed.
REFERENCE = {
    "n": 5,
    "wins": 1,
    "losses": 4,
    "gross_profit": 115.26,
    "gross_loss": 308.29,
    "net_pnl": -193.03,
    "profit_factor": 0.373869,
    "max_drawdown_currency": 308.29,
}

TOLERANCE = 0.01


def check(label: str, actual: float, expected: float, tol: float = TOLERANCE) -> bool:
    ok = abs(actual - expected) <= tol
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {label}: actual={actual} expected={expected} (tol={tol})")
    return ok


def main() -> int:
    if not FIXTURE.exists():
        print(f"FIXTURE MISSING: {FIXTURE}")
        return 1

    trades = load_trades(FIXTURE)
    stats = certification_stats(trades)

    results = [
        check("n", stats["n"], REFERENCE["n"], tol=0),
        check("wins", stats["wins"], REFERENCE["wins"], tol=0),
        check("losses", stats["losses"], REFERENCE["losses"], tol=0),
        check("gross_profit", stats["gross_profit"], REFERENCE["gross_profit"]),
        check("gross_loss", stats["gross_loss"], REFERENCE["gross_loss"]),
        check("net_pnl", stats["net_pnl"], REFERENCE["net_pnl"]),
        check("profit_factor", stats["profit_factor"], REFERENCE["profit_factor"], tol=1e-4),
        check("max_drawdown_currency", stats["max_drawdown_currency"], REFERENCE["max_drawdown_currency"]),
    ]

    # Hand-verified, no prior-script reference: trades in ExitTime order have
    # NetPnL signs [+, -, -, -, -] -> one win followed by four losses.
    results.append(check("longest_losing_streak", stats["longest_losing_streak"], 4, tol=0))

    # Sanity bounds only (no external reference exists for these): win_rate
    # must be exactly 1/5, and the bootstrap CI must actually contain the
    # point estimate.
    results.append(check("win_rate", stats["win_rate"], 0.2, tol=1e-9))
    ci = stats["bootstrap_expectancy_r_ci"]
    ci_ok = ci["low"] <= ci["point"] <= ci["high"]
    print(f"[{'PASS' if ci_ok else 'FAIL'}] bootstrap CI contains point estimate: "
          f"[{ci['low']:.4f}, {ci['high']:.4f}] point={ci['point']:.4f}")
    results.append(ci_ok)

    if all(results):
        print("\nALL CHECKS PASSED")
        return 0
    print(f"\n{results.count(False)} CHECK(S) FAILED")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
