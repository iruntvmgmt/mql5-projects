#!/usr/bin/env python3
"""Deterministic D028 Stage 4 portfolio reconciliation."""

from __future__ import annotations

import argparse
import csv
import html
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path

DT = "%Y.%m.%d %H:%M:%S"
WINDOWS = (
    ("Development", datetime(2025, 3, 1), datetime(2026, 1, 1)),
    ("Validation", datetime(2026, 1, 1), datetime(2026, 5, 1)),
    ("Final holdout", datetime(2026, 5, 1), datetime(2026, 7, 25)),
    ("Full window", datetime(2025, 3, 1), datetime(2026, 7, 25)),
)
STRATEGIES = {1010: "FastMedConfluence", 1050: "SweepReclaim"}


def args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--results", type=Path,
        default=Path("/Users/matt/MT5-MSZZ-TEST/D028_Stage4_Results"))
    parser.add_argument("--output", type=Path, default=Path(__file__).parent)
    return parser.parse_args()


def rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle, delimiter=";"))


def metrics(trades: list[dict[str, str]]) -> dict[str, object]:
    ordered = sorted(trades, key=lambda row: datetime.strptime(row["exit_time"], DT))
    values = [float(row["realized_r"]) for row in ordered]
    total = sum(values)
    gross_profit = sum(value for value in values if value > 0)
    gross_loss = -sum(value for value in values if value < 0)
    equity = peak = drawdown = 0.0
    for value in values:
        equity += value
        peak = max(peak, equity)
        drawdown = max(drawdown, peak - equity)
    return {
        "trades": len(trades),
        "cumulative_r": total,
        "expectancy_r": total / len(trades) if trades else 0.0,
        "profit_factor_r": gross_profit / gross_loss if gross_loss else 0.0,
        "max_drawdown_r": drawdown,
        "wins": sum(value > 0 for value in values),
        "losses": sum(value < 0 for value in values),
        "long_trades": sum(row["direction"] == "LONG" for row in trades),
        "short_trades": sum(row["direction"] == "SHORT" for row in trades),
    }


def native_counts(report: Path) -> tuple[int, int]:
    text=report.read_text(encoding="utf-16")
    trades=re.search(r"Total Trades:</td>\s*<td nowrap><b>(\d+)</b>",text)
    deals=re.search(r"Total Deals:</td>\s*<td nowrap><b>(\d+)</b>",text)
    if not trades or not deals:
        raise SystemExit(f"native trade/deal counts not found: {report}")
    return int(trades.group(1)),int(deals.group(1))


def exposure(trades: list[dict[str, str]]) -> dict[str, object]:
    events: list[tuple[datetime, int, int, str]] = []
    for row in trades:
        sid=int(row["strategy_id"])
        events.append((datetime.strptime(row["entry_time"],DT),1,sid,row["direction"]))
        events.append((datetime.strptime(row["exit_time"],DT),-1,sid,row["direction"]))
    events.sort(key=lambda item:(item[0],item[1]))
    active: dict[int,str] = {}
    last=events[0][0]
    multi_seconds=opposing_seconds=same_seconds=0.0
    episodes=0
    was_multi=False
    max_open=0
    for time,kind,sid,direction in events:
        seconds=(time-last).total_seconds()
        if len(active)>=2:
            multi_seconds+=seconds
            directions=set(active.values())
            if len(directions)>1: opposing_seconds+=seconds
            else: same_seconds+=seconds
        if kind<0: active.pop(sid,None)
        else: active[sid]=direction
        is_multi=len(active)>=2
        if is_multi and not was_multi: episodes+=1
        was_multi=is_multi
        max_open=max(max_open,len(active))
        last=time
    span=(events[-1][0]-events[0][0]).total_seconds()
    return {
        "max_open_books":max_open,
        "multi_book_episodes":episodes,
        "multi_book_hours":multi_seconds/3600.0,
        "multi_book_time_pct":100.0*multi_seconds/span if span else 0.0,
        "opposing_hours":opposing_seconds/3600.0,
        "same_direction_hours":same_seconds/3600.0,
        "max_initial_risk_pct":0.25*max_open,
    }


def write(path: Path, fields: list[str], data: list[dict[str, object]]) -> None:
    with path.open("w",newline="",encoding="utf-8") as handle:
        writer=csv.DictWriter(handle,fieldnames=fields,lineterminator="\n")
        writer.writeheader(); writer.writerows(data)


def main() -> None:
    options=args(); options.output.mkdir(parents=True,exist_ok=True)
    runs=(
        ("P2_Independent_NoOpposing","D028_Stage4_P2_Independent_NoOpposing.htm"),
        ("P3_Independent_Opposing","D028_Stage4_P3_Independent_Opposing.htm"),
        ("P4_Independent_E3R_Sweep2R","D028_Stage4_P4_Independent_E3R_Sweep2R.htm"),
    )
    summary=[]; strategy=[]; windows=[]; integrity=[]; exposures=[]
    for name,report_name in runs:
        root=options.results/name
        trades=rows(root/"MSZZ_PortfolioTradeAnalytics.csv")
        allocations=rows(root/"MSZZ_ExecutionAllocationJournal.csv")
        books=rows(root/"MSZZ_StrategyBookJournal.csv")
        signals=rows(root/"MSZZ_SignalJournal.csv")
        native_trades,native_deals=native_counts(root/report_name)
        ids=[row["logical_position_id"] for row in trades]
        allocation_ids=[row["logical_position_id"] for row in allocations]
        magics=defaultdict(set)
        for row in trades: magics[int(row["strategy_id"])].add(int(row["magic"]))
        open_rows=[row for row in books if row["action"]=="OPEN"]
        close_rows=[row for row in books if row["action"]=="CLOSED"]
        reconciliation_rejects=sum(
            row["status"]=="REJECT_OWN_BOOK_RECONCILIATION" for row in signals)
        cross_family_actions=sum(
            row["cross_family_action"] not in ("", "NONE") for row in allocations)
        own_family_exits=sum(
            row["exit_reason"]=="OWN_FAMILY_OPPOSITE" for row in trades)
        target_errors=0
        expected={1010:(3.0 if name.startswith("P4") else 2.0),1050:2.0}
        for row in open_rows:
            sid=int(row["strategy_id"])
            risk=abs(float(row["entry_price"])-float(row["stop_price"]))
            ratio=(abs(float(row["target_price"])-float(row["entry_price"]))/risk
                   if risk else -1.0)
            if abs(ratio-expected[sid])>1e-6: target_errors+=1
        status=(
            len(ids)==native_trades==len(allocations)
            and native_deals==2*native_trades
            and len(ids)==len(set(ids))
            and len(allocation_ids)==len(set(allocation_ids))
            and set(ids)==set(allocation_ids)
            and all(len(value)==1 for value in magics.values())
            and len({next(iter(value)) for value in magics.values()})==2
            and target_errors==0
            and len(close_rows)==len(trades)
            and reconciliation_rejects==0
            and cross_family_actions==0
        )
        if not status: raise SystemExit(f"{name}: integrity reconciliation failed")
        run_metrics=metrics(trades)
        summary.append({"run":name,**run_metrics})
        integrity.append({
            "run":name,"native_trades":native_trades,"native_deals":native_deals,
            "logical_trades":len(trades),"allocation_opens":len(allocations),
            "unique_logical_ids":len(set(ids)),
            "duplicate_logical_ids":len(ids)-len(set(ids)),
            "fastmed_magic":next(iter(magics[1010])),
            "sweep_magic":next(iter(magics[1050])),
            "target_policy_errors":target_errors,
            "own_family_exits":own_family_exits,
            "reconciliation_rejects":reconciliation_rejects,
            "cross_family_exits":cross_family_actions,"status":"PASS",
        })
        exposures.append({"run":name,**exposure(trades)})
        for sid,label in STRATEGIES.items():
            selected=[row for row in trades if int(row["strategy_id"])==sid]
            strategy.append({"run":name,"strategy":label,**metrics(selected)})
        for label,start,end in WINDOWS:
            selected=[
                row for row in trades
                if start<=datetime.strptime(row["entry_time"],DT)<end]
            windows.append({"run":name,"window":label,**metrics(selected)})

    p1_trade_rows=rows(
        options.results/"P1_Legacy_A_Sweep_2R"/"MSZZ_TradeAnalytics.csv")
    p1_adapted=[
        {
            "realized_r":row["r_result"],"exit_time":row["close_time"],
            "direction":row["direction"],
        } for row in p1_trade_rows
    ]
    p1_metrics=metrics(p1_adapted)
    legacy=[{"run":"P1_Legacy_A_Sweep_2R",**p1_metrics,"status":"PASS"}]
    write(options.output/"portfolio_summary.csv",list(summary[0]),summary)
    write(options.output/"strategy_contribution.csv",list(strategy[0]),strategy)
    write(options.output/"portfolio_window_summary.csv",list(windows[0]),windows)
    write(options.output/"portfolio_integrity_audit.csv",list(integrity[0]),integrity)
    write(options.output/"portfolio_exposure_summary.csv",list(exposures[0]),exposures)
    write(options.output/"legacy_control.csv",list(legacy[0]),legacy)

    lines=[
        "# D028 Stage 4 — Independent-Book Portfolio Results","",
        "| Run | Trades | Cumulative R | Expectancy R | PF | Max DD R |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for row in summary:
        lines.append(
            f"| {row['run']} | {row['trades']} | {row['cumulative_r']:.4f} | "
            f"{row['expectancy_r']:.4f} | {row['profit_factor_r']:.4f} | "
            f"{row['max_drawdown_r']:.4f} |")
    lines += [
        "",
        "All independent runs reconcile native trades, native deals, logical",
        "trades, allocation opens, distinct magics, and per-book targets.",
        "Cross-family exits are zero by construction and audit.",
        "",
    ]
    (options.output/"stage4_findings.md").write_text(
        "\n".join(lines),encoding="utf-8",newline="\n")


if __name__=="__main__":
    main()
