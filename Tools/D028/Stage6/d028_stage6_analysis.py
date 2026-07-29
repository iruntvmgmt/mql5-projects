#!/usr/bin/env python3
import csv, statistics
from datetime import datetime
from collections import defaultdict

ROOT = "/Users/matt/MT5-MSZZ-TEST/D028_Stage6_Results"
VARIANTS = ["C_A_SR5", "C_E_SR5"]

DEV_START = datetime(2025,3,1); DEV_END = datetime(2025,12,31,23,59,59)
VAL_START = datetime(2026,1,1); VAL_END = datetime(2026,4,30,23,59,59)
HOLD_START = datetime(2026,5,1); HOLD_END = datetime(2026,7,24,23,59,59)

def parse_dt(s):
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")

def load(variant):
    path = f"{ROOT}/{variant}/MSZZ_PortfolioTradeAnalytics.csv"
    rows = list(csv.DictReader(open(path), delimiter=';'))
    for r in rows:
        r['exit_time_dt'] = parse_dt(r['exit_time'])
        r['entry_time_dt'] = parse_dt(r['entry_time'])
        r['realized_r'] = float(r['realized_r'])
    rows.sort(key=lambda r: r['exit_time_dt'])
    return rows

def expectancy(rows):
    return sum(r['realized_r'] for r in rows)/len(rows) if rows else 0.0

def pf(rows):
    g = sum(r['realized_r'] for r in rows if r['realized_r']>0)
    l = -sum(r['realized_r'] for r in rows if r['realized_r']<0)
    return g/l if l>0 else float('inf')

def maxdd(rows):
    eq=0.0; peak=0.0; dd=0.0
    for r in rows:
        eq+=r['realized_r']; peak=max(peak,eq); dd=max(dd,peak-eq)
    return dd

def wslice(rows,s,e):
    return [r for r in rows if s<=r['exit_time_dt']<=e]

for v in VARIANTS:
    rows = load(v)
    n=len(rows)
    cum=sum(r['realized_r'] for r in rows)
    fastmed = [r for r in rows if r['strategy_id']=='1010']
    sweep = [r for r in rows if r['strategy_id']=='1050']
    dev=wslice(rows,DEV_START,DEV_END); val=wslice(rows,VAL_START,VAL_END); hold=wslice(rows,HOLD_START,HOLD_END)

    # simultaneous-book episodes: overlapping entry/exit intervals across the two strategies
    fm_intervals = [(r['entry_time_dt'], r['exit_time_dt']) for r in fastmed]
    sw_intervals = [(r['entry_time_dt'], r['exit_time_dt']) for r in sweep]
    episodes = 0; hours = 0.0
    for fs,fe in fm_intervals:
        for ss,se in sw_intervals:
            os_, oe_ = max(fs,ss), min(fe,se)
            if os_ < oe_:
                episodes += 1
                hours += (oe_-os_).total_seconds()/3600.0

    print(f"\n{'='*60}\n{v}\n{'='*60}")
    print(f"total trades={n} cum_r={cum:.4f} expectancy={expectancy(rows):.4f} PF={pf(rows):.4f} maxDD={maxdd(rows):.4f}")
    print(f"FastMedConfluence n={len(fastmed)} cum={sum(r['realized_r'] for r in fastmed):.4f} exp={expectancy(fastmed):.4f}")
    print(f"SweepReclaim(SR5) n={len(sweep)} cum={sum(r['realized_r'] for r in sweep):.4f} exp={expectancy(sweep):.4f}")
    print(f"Dev n={len(dev)} cum={sum(r['realized_r'] for r in dev):.4f}")
    print(f"Val n={len(val)} cum={sum(r['realized_r'] for r in val):.4f}")
    print(f"Hold n={len(hold)} cum={sum(r['realized_r'] for r in hold):.4f}")
    print(f"simultaneous-book episodes={episodes} hours={hours:.4f}")
