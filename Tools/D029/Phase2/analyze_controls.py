#!/usr/bin/env python3
import csv, statistics
from datetime import datetime
from collections import defaultdict

ROOT = "/Users/matt/MT5-MSZZ-TEST/D029_Phase2_Results"

DEV_START = datetime(2025,3,1); DEV_END = datetime(2025,12,31,23,59,59)
VAL_START = datetime(2026,1,1); VAL_END = datetime(2026,4,30,23,59,59)
HOLD_START = datetime(2026,5,1); HOLD_END = datetime(2026,7,24,23,59,59)

def parse_dt(s):
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")

def expectancy(rows,key):
    return sum(r[key] for r in rows)/len(rows) if rows else 0.0

def pf(rows,key):
    g=sum(r[key] for r in rows if r[key]>0); l=-sum(r[key] for r in rows if r[key]<0)
    return g/l if l>0 else float('inf')

def maxdd(rows,key):
    eq=0.0;peak=0.0;dd=0.0
    for r in rows:
        eq+=r[key]; peak=max(peak,eq); dd=max(dd,peak-eq)
    return dd

def wslice(rows,s,e,tkey):
    return [r for r in rows if s<=r[tkey]<=e]

def analyze_single(name):
    path=f"{ROOT}/{name}/MSZZ_TradeAnalytics.csv"
    rows=list(csv.DictReader(open(path),delimiter=';'))
    for r in rows:
        r['close_time_dt']=parse_dt(r['close_time'])
        r['r_result']=float(r['r_result'])
    rows.sort(key=lambda r:r['close_time_dt'])
    n=len(rows)
    cum=sum(r['r_result'] for r in rows)
    dev=wslice(rows,DEV_START,DEV_END,'close_time_dt')
    val=wslice(rows,VAL_START,VAL_END,'close_time_dt')
    hold=wslice(rows,HOLD_START,HOLD_END,'close_time_dt')
    longs=[r for r in rows if r['direction']=='LONG']; shorts=[r for r in rows if r['direction']=='SHORT']
    sorted_r=sorted(rows,key=lambda r:-r['r_result'])
    top3_removed=[r for r in rows if r not in sorted_r[:3]]
    quarters=defaultdict(list)
    for r in rows:
        q=(r['close_time_dt'].month-1)//3+1
        quarters[f"{r['close_time_dt'].year}Q{q}"].append(r)
    best_q=max(quarters.items(),key=lambda kv: sum(x['r_result'] for x in kv[1]))[0] if quarters else None
    bq_removed=[r for r in rows if not (( (r['close_time_dt'].month-1)//3+1 ) and f"{r['close_time_dt'].year}Q{(r['close_time_dt'].month-1)//3+1}"==best_q)]
    exit_reasons=defaultdict(int)
    for r in rows: exit_reasons[r['exit_reason']]+=1

    print(f"\n{'='*70}\n{name} (single-book)\n{'='*70}")
    print(f"trades={n} cum_r={cum:.4f} expectancy={expectancy(rows,'r_result'):.4f} PF={pf(rows,'r_result'):.4f} maxDD={maxdd(rows,'r_result'):.4f}")
    print(f"win_rate={sum(1 for r in rows if r['r_result']>0)/n:.4f}" if n else "win_rate=n/a")
    print(f"Dev n={len(dev)} cum={sum(r['r_result'] for r in dev):.4f} | Val n={len(val)} cum={sum(r['r_result'] for r in val):.4f} | Hold n={len(hold)} cum={sum(r['r_result'] for r in hold):.4f}")
    print(f"Long n={len(longs)} exp={expectancy(longs,'r_result'):.4f} | Short n={len(shorts)} exp={expectancy(shorts,'r_result'):.4f}")
    print(f"top3-removed cum={sum(r['r_result'] for r in top3_removed):.4f}")
    print(f"best_quarter={best_q} best-quarter-removed cum={sum(r['r_result'] for r in bq_removed):.4f}")
    print(f"exit_reasons={dict(exit_reasons)}")
    return rows

def analyze_sizing(name):
    path=f"{ROOT}/{name}/MSZZ_SizingJournal.csv"
    rows=list(csv.DictReader(open(path),delimiter=';'))
    for r in rows:
        r['actual_risk_pct']=float(r['actual_risk_pct'])
        r['normalized_volume']=float(r['normalized_volume'])
        r['risk_underallocation_pct']=float(r['risk_underallocation_pct'])
    ok=[r for r in rows if r['sizing_result']=='OK']
    rejected=[r for r in rows if r['sizing_result']=='REJECTED']
    reject_reasons=defaultdict(int)
    for r in rejected: reject_reasons[r['reject_reason']]+=1
    at_min=[r for r in ok if abs(r['normalized_volume']-0.01)<1e-9]
    partial_capable=[r for r in ok if r['partial_capable']=='true']
    print(f"\n--- {name} sizing journal ---")
    print(f"total_decisions={len(rows)} OK={len(ok)} REJECTED={len(rejected)}")
    print(f"reject_reasons={dict(reject_reasons)}")
    if ok:
        risks=[r['actual_risk_pct'] for r in ok]
        print(f"actual_risk_pct: mean={statistics.mean(risks):.4f} median={statistics.median(risks):.4f} min={min(risks):.4f} max={max(risks):.4f}")
        underalloc=[r['risk_underallocation_pct'] for r in ok]
        print(f"mean_under_risk_pct_of_equity={statistics.mean(underalloc):.4f}")
        print(f"pct_at_minimum_lot={100*len(at_min)/len(ok):.2f}% pct_partial_capable={100*len(partial_capable)/len(ok):.2f}%")
        vols=[r['normalized_volume'] for r in ok]
        print(f"volume: min={min(vols):.2f} median={statistics.median(vols):.2f} mean={statistics.mean(vols):.4f} max={max(vols):.2f}")

def analyze_portfolio(name):
    path=f"{ROOT}/{name}/MSZZ_PortfolioTradeAnalytics.csv"
    rows=list(csv.DictReader(open(path),delimiter=';'))
    for r in rows:
        r['exit_time_dt']=parse_dt(r['exit_time'])
        r['realized_r']=float(r['realized_r'])
    rows.sort(key=lambda r:r['exit_time_dt'])
    n=len(rows); cum=sum(r['realized_r'] for r in rows)
    fastmed=[r for r in rows if r['strategy_id']=='1010']
    sweep=[r for r in rows if r['strategy_id']=='1050']
    dev=wslice(rows,DEV_START,DEV_END,'exit_time_dt'); val=wslice(rows,VAL_START,VAL_END,'exit_time_dt'); hold=wslice(rows,HOLD_START,HOLD_END,'exit_time_dt')
    print(f"\n{'='*70}\n{name} (multi-book)\n{'='*70}")
    print(f"trades={n} cum_r={cum:.4f} expectancy={expectancy(rows,'realized_r'):.4f} PF={pf(rows,'realized_r'):.4f} maxDD={maxdd(rows,'realized_r'):.4f}")
    print(f"FastMedConfluence n={len(fastmed)} cum={sum(r['realized_r'] for r in fastmed):.4f} exp={expectancy(fastmed,'realized_r'):.4f}")
    print(f"SweepReclaim n={len(sweep)} cum={sum(r['realized_r'] for r in sweep):.4f} exp={expectancy(sweep,'realized_r'):.4f}")
    print(f"Dev cum={sum(r['realized_r'] for r in dev):.4f} | Val cum={sum(r['realized_r'] for r in val):.4f} | Hold cum={sum(r['realized_r'] for r in hold):.4f}")

def reconcile(name,cert_trades):
    sig_path=f"{ROOT}/{name}/MSZZ_SignalJournal.csv"
    rows=list(csv.DictReader(open(sig_path),delimiter=';'))
    status_counts=defaultdict(int)
    for r in rows: status_counts[r['status']]+=1
    executed=status_counts.get('EXECUTED',0)
    print(f"\n--- {name} reconciliation vs D028 certified fixed-lot ({cert_trades} trades) ---")
    print(f"D029 percent-equity executed={executed}, delta={executed-cert_trades}")
    print(f"status breakdown={dict(status_counts)}")

for n in ["D29_A","D29_E","D29_SR0"]:
    analyze_single(n)
    analyze_sizing(n)

for n in ["D29_P3","D29_P4"]:
    analyze_portfolio(n)
    analyze_sizing(n)

reconcile("D29_A",224)
reconcile("D29_E",213)
reconcile("D29_SR0",190)
