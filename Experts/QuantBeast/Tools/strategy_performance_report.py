#!/usr/bin/env python3
"""Canonical per-strategy/direction/session/regime performance report (Part F).

Reads exact byte-bounded TradeJournal.csv and SignalJournal.csv slices from
the SAME run and joins each completed trade back to the SignalJournal row
that accepted it, so every accepted trade is traceable from candidate
(SignalJournal: setup/trigger codes, regime, session, confidence) through
exit (TradeJournal: R multiple, MFE/MAE, exit reason). This is the report
explicitly flagged as missing in KNOWN_LIMITATIONS.md ("No per-strategy/
direction/session/regime report exists").

Join key: (Strategy, Direction, Timestamp==EntryTime). This project's
execution model fills market orders immediately (XAUUSD Stop/Freeze level
0, confirmed in KNOWN_LIMITATIONS.md), so a signal's acceptance time and
its resulting position's entry time are the same OnTick() pass in every
case this report has been run against. TradeJournal.SignalID is NOT used
for the join -- it is ctx.signal_id (PositionContext's internal numeric
id), a documented separate/incomplete identifier
(STRATEGY_SPEC.md: "Valid signals do not carry a durable numeric signal ID
beyond the journal string ID"), not the same value as SignalJournal's
string SignalID. A trade with no exact-timestamp match is reported as
UNMATCHED, never silently dropped or guessed.

This script computes descriptive statistics only. It does not, and must
not be used to, claim a profitability edge from any result it prints --
see the accompanying report's "Known limitations" section for sample-size
caveats specific to each run.
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from acceptance_funnel_report import decode  # noqa: E402

csv.field_size_limit(sys.maxsize)

TRADE_COLUMNS = [
    "Strategy", "SignalID", "EntryTime", "ExitTime", "Direction", "Entry", "Exit",
    "Volume", "Stop", "Target", "GrossPnL", "Commission", "Swap", "NetPnL",
    "RMultiple", "MFE", "MAE", "ExitReason", "EntryRegime", "ExitRegime",
    "EntrySpread", "Slippage",
]
SIGNAL_COLUMNS = [
    "Timestamp", "Symbol", "Mode", "Strategy", "Direction", "SignalID",
    "SetupCode", "TriggerCode", "Accepted", "RejectionCode",
    "RejectionReason", "RegimeTrend", "RegimeVol", "Session", "Spread",
    "ATR_Points", "Entry", "Stop", "Target", "ExpectedR", "Confidence",
    "StrategyFamily", "StrategyTemplate", "StrategyTags",
]


def _rows(path: Path, offset: int, end_offset: int | None, columns: list[str], sentinel_cols: tuple[str, str]):
    lines = [line for line in decode(path, offset, end_offset).splitlines() if line.strip()]
    if not lines:
        return
    first = [cell.strip() for cell in next(csv.reader([lines[0]]))]
    headered = sentinel_cols[0] in first and sentinel_cols[1] in first
    if headered:
        yield from csv.DictReader(lines)
        return
    for raw in csv.reader(lines):
        yield dict(zip(columns, raw))


def trade_rows(path: Path, offset: int = 0, end_offset: int | None = None):
    yield from _rows(path, offset, end_offset, TRADE_COLUMNS, ("Strategy", "RMultiple"))


def signal_rows(path: Path, offset: int = 0, end_offset: int | None = None):
    yield from _rows(path, offset, end_offset, SIGNAL_COLUMNS, ("Strategy", "Accepted"))


def to_float(row: dict, key: str, default: float = 0.0) -> float:
    value = row.get(key, "")
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def table(headers, body) -> str:
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    out.extend("| " + " | ".join(str(cell) for cell in row) + " |" for row in body)
    return "\n".join(out)


def summarize(group: list[dict]) -> dict:
    n = len(group)
    r_multiples = [to_float(t, "RMultiple") for t in group]
    net_pnls = [to_float(t, "NetPnL") for t in group]
    mfes = [to_float(t, "MFE") for t in group]
    maes = [to_float(t, "MAE") for t in group]
    wins = sum(1 for r in r_multiples if r > 0)
    return {
        "n": n,
        "win_rate": (wins / n) if n else float("nan"),
        "mean_r": statistics.fmean(r_multiples) if n else float("nan"),
        "median_r": statistics.median(r_multiples) if n else float("nan"),
        "total_net_pnl": sum(net_pnls),
        "mean_mfe": statistics.fmean(mfes) if n else float("nan"),
        "mean_mae": statistics.fmean(maes) if n else float("nan"),
    }


def fmt_row(key_label: str, stats: dict) -> list:
    def f(x):
        return "n/a" if isinstance(x, float) and x != x else f"{x:.3f}" if isinstance(x, float) else x

    return [key_label, stats["n"], f(stats["win_rate"]), f(stats["mean_r"]), f(stats["median_r"]),
            f(stats["total_net_pnl"]), f(stats["mean_mfe"]), f(stats["mean_mae"])]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--trade-journal", required=True, type=Path)
    parser.add_argument("--trade-offset", type=int, default=0)
    parser.add_argument("--trade-end-offset", type=int, default=None)
    parser.add_argument("--signal-journal", required=True, type=Path)
    parser.add_argument("--signal-offset", type=int, default=0)
    parser.add_argument("--signal-end-offset", type=int, default=None)
    parser.add_argument("--run-id", default="", help="Label for the report heading / provenance")
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()

    trades = list(trade_rows(args.trade_journal, args.trade_offset, args.trade_end_offset))
    signals = list(signal_rows(args.signal_journal, args.signal_offset, args.signal_end_offset))
    accepted_signals = {
        (s.get("Strategy", "").strip(), s.get("Direction", "").strip(), s.get("Timestamp", "").strip()): s
        for s in signals if s.get("Accepted", "").strip() == "ACCEPTED"
    }

    joined = []
    unmatched = []
    for t in trades:
        strat = t.get("Strategy", "").strip()
        raw_dir = t.get("Direction", "").strip()  # TradeJournal uses LONG/SHORT
        sig_dir = "BUY" if raw_dir == "LONG" else "SELL" if raw_dir == "SHORT" else raw_dir
        key = (strat, sig_dir, t.get("EntryTime", "").strip())
        sig = accepted_signals.get(key)
        if sig is None:
            unmatched.append(t)
            continue
        row = dict(t)
        row["Session"] = sig.get("Session", "")
        row["RegimeTrend_Signal"] = sig.get("RegimeTrend", "")
        row["RegimeVol_Signal"] = sig.get("RegimeVol", "")
        row["SetupCode"] = sig.get("SetupCode", "")
        row["TriggerCode"] = sig.get("TriggerCode", "")
        row["Confidence"] = sig.get("Confidence", "")
        joined.append(row)

    lines = [
        f"# Strategy performance report -- {args.run_id or 'unlabeled run'}",
        "",
        "## Provenance",
        "",
        f"- Generator: `Tools/strategy_performance_report.py`",
        f"- TradeJournal source: `{args.trade_journal}` bytes [{args.trade_offset},{args.trade_end_offset})",
        f"- SignalJournal source: `{args.signal_journal}` bytes [{args.signal_offset},{args.signal_end_offset})",
        f"- Trade rows read: {len(trades)}; accepted-signal rows read: {len(accepted_signals)}",
        f"- Joined (traceable candidate->exit): {len(joined)}; unmatched (no exact Strategy/Direction/Timestamp match): {len(unmatched)}",
        "- Join key: (Strategy, Direction, Timestamp==EntryTime) -- see module docstring for why TradeJournal.SignalID is not used.",
        "- Dedup rule: none applied -- every TradeJournal row is one closed position, already deduplicated by construction.",
        "",
    ]

    if unmatched:
        lines.append("**Unmatched trades (excluded from session/regime breakdown, included in per-strategy/direction totals below):**")
        lines.append("")
        lines.append(table(
            ["Strategy", "Direction", "EntryTime", "RMultiple"],
            [[t.get("Strategy", ""), t.get("Direction", ""), t.get("EntryTime", ""), t.get("RMultiple", "")] for t in unmatched],
        ))
        lines.append("")

    lines.append("## Per-strategy / direction (all trades, joined or not)")
    lines.append("")
    by_strat_dir = defaultdict(list)
    for t in trades:
        by_strat_dir[(t.get("Strategy", ""), t.get("Direction", ""))].append(t)
    body = [fmt_row(f"{k[0]} {k[1]}", summarize(v)) for k, v in sorted(by_strat_dir.items())]
    lines.append(table(["Strategy Direction", "n", "WinRate", "MeanR", "MedianR", "TotalNetPnL", "MeanMFE", "MeanMAE"], body))
    lines.append("")

    lines.append("## Per-strategy / direction / session (joined trades only)")
    lines.append("")
    by_sds = defaultdict(list)
    for t in joined:
        by_sds[(t.get("Strategy", ""), t.get("Direction", ""), t.get("Session", ""))].append(t)
    body = [fmt_row(f"{k[0]} {k[1]} {k[2]}", summarize(v)) for k, v in sorted(by_sds.items())]
    lines.append(table(["Strategy Direction Session", "n", "WinRate", "MeanR", "MedianR", "TotalNetPnL", "MeanMFE", "MeanMAE"], body) if body else "No joined trades.")
    lines.append("")

    lines.append("## Per-strategy / direction / entry regime trend (joined trades only)")
    lines.append("")
    by_sdr = defaultdict(list)
    for t in joined:
        by_sdr[(t.get("Strategy", ""), t.get("Direction", ""), t.get("RegimeTrend_Signal", ""))].append(t)
    body = [fmt_row(f"{k[0]} {k[1]} {k[2]}", summarize(v)) for k, v in sorted(by_sdr.items())]
    lines.append(table(["Strategy Direction RegimeTrend", "n", "WinRate", "MeanR", "MedianR", "TotalNetPnL", "MeanMFE", "MeanMAE"], body) if body else "No joined trades.")
    lines.append("")

    lines.append("## Known limitations")
    lines.append("")
    lines.append("- Descriptive statistics only -- no claim of edge is made or should be inferred from any n shown here.")
    lines.append("- `RegimeTrend`/`RegimeVol` are the enum's raw integer values (SignalJournal does not serialize enum names); cross-reference `Core/Enums.mqh` `ENUM_TREND_REGIME`/`ENUM_VOLATILITY_REGIME` to interpret them.")
    lines.append("- Session/regime context comes from the accepted SignalJournal row at entry only -- no exit-time session/regime breakdown is computed here (TradeJournal's own ExitRegime is per-trade, not aggregated by this report).")

    text = "\n".join(lines)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
