#!/usr/bin/env python3
import csv, statistics
from datetime import datetime
from collections import defaultdict

ROOT = "/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results"
CTRL_ROOT = "/Users/matt/MT5-MSZZ-TEST/D029_Phase2_Results"

DEV_START = datetime(2025,3,1); DEV_END = datetime(2025,12,31,23,59,59)
VAL_START = datetime(2026,1,1); VAL_END = datetime(2026,4,30,23,59,59)
HOLD_START = datetime(2026,5,1); HOLD_END = datetime(2026,7,24,23,59,59)

def parse_dt(s):
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")

def load(root,name):
    path = f"{root}/{name}/MSZZ_PortfolioTradeAnalytics.csv"
    rows = list(csv.DictReader(open(path), delimiter=';'))
    for r in rows:
        r['entry_time_dt']=parse_dt(r['entry_time'])
        r['exit_time_dt']=parse_dt(r['exit_time'])
        r['realized_r']=float(r['realized_r'])
    rows.sort(key=lambda r:r['exit_time_dt'])
    return rows

def expectancy(rows):
    return sum(r['realized_r'] for r in rows)/len(rows) if rows else 0.0

def pf(rows):
    g=sum(r['realized_r'] for r in rows if r['realized_r']>0); l=-sum(r['realized_r'] for r in rows if r['realized_r']<0)
    return g/l if l>0 else float('inf')

def maxdd(rows):
    eq=0.0;peak=0.0;dd=0.0
    for r in rows:
        eq+=r['realized_r']; peak=max(peak,eq); dd=max(dd,peak-eq)
    return dd

def wslice(rows,s,e):
    return [r for r in rows if s<=r['exit_time_dt']<=e]

def monthly(rows):
    m=defaultdict(float)
    for r in rows:
        key=f"{r['exit_time_dt'].year}-{r['exit_time_dt'].month:02d}"
        m[key]+=r['realized_r']
    return m

def simultaneous_episodes(fastmed,sweep):
    episodes=0; hours=0.0; opposing=0; same_dir=0
    for f in fastmed:
        for s in sweep:
            os_,oe_=max(f['entry_time_dt'],s['entry_time_dt']),min(f['exit_time_dt'],s['exit_time_dt'])
            if os_<oe_:
                episodes+=1
                hours+=(oe_-os_).total_seconds()/3600.0
                if f['direction']!=s['direction']: opposing+=1
                else: same_dir+=1
    return episodes,hours,opposing,same_dir

def analyze(name, is_sr3):
    rows = load(ROOT if is_sr3 else CTRL_ROOT, name)
    n=len(rows); cum=sum(r['realized_r'] for r in rows)
    fastmed=[r for r in rows if r['strategy_id']=='1010']
    sweep=[r for r in rows if r['strategy_id']=='1050']
    dev=wslice(rows,DEV_START,DEV_END); val=wslice(rows,VAL_START,VAL_END); hold=wslice(rows,HOLD_START,HOLD_END)
    episodes,hours,opposing,same_dir=simultaneous_episodes(fastmed,sweep)
    sorted_r=sorted(rows,key=lambda r:-r['realized_r'])
    top3_ids=set(id(x) for x in sorted_r[:3])
    top3_removed=[r for r in rows if id(r) not in top3_ids]

    print(f"\n{'='*70}\n{name}\n{'='*70}")
    print(f"trades={n} cum_r={cum:.4f} expectancy={expectancy(rows):.4f} PF={pf(rows):.4f} maxDD={maxdd(rows):.4f}")
    print(f"FastMed n={len(fastmed)} cum={sum(r['realized_r'] for r in fastmed):.4f} exp={expectancy(fastmed):.4f}")
    print(f"Sweep   n={len(sweep)} cum={sum(r['realized_r'] for r in sweep):.4f} exp={expectancy(sweep):.4f}")
    print(f"Dev cum={sum(r['realized_r'] for r in dev):.4f} | Val cum={sum(r['realized_r'] for r in val):.4f} | Hold cum={sum(r['realized_r'] for r in hold):.4f}")
    print(f"top3-removed cum={sum(r['realized_r'] for r in top3_removed):.4f}")
    print(f"simultaneous episodes={episodes} hours={hours:.2f} opposing={opposing} same_dir={same_dir}")
    return dict(name=name,n=n,cum=cum,dd=maxdd(rows),fastmed_n=len(fastmed),fastmed_cum=sum(r['realized_r'] for r in fastmed),
                sweep_n=len(sweep),sweep_cum=sum(r['realized_r'] for r in sweep),
                dev_cum=sum(r['realized_r'] for r in dev),val_cum=sum(r['realized_r'] for r in val),hold_cum=sum(r['realized_r'] for r in hold),
                episodes=episodes,hours=hours,monthly=monthly(rows))

def weak_core_months(core_name):
    core_rows=load(CTRL_ROOT if core_name.startswith("D29") else ROOT, core_name)
    m=monthly(core_rows)
    return {k:v for k,v in m.items() if v<0}

p3_ctrl = analyze("D29_P3", False)
p3_sr3 = analyze("P3_SR3", True)
p4_ctrl = analyze("D29_P4", False)
p4_sr3 = analyze("P4_SR3", True)

print("\n=== Incremental comparison ===")
print(f"P3-SR3 vs P3 ctrl: dR={p3_sr3['cum']-p3_ctrl['cum']:.4f} dDD={p3_sr3['dd']-p3_ctrl['dd']:.4f} dTrades={p3_sr3['n']-p3_ctrl['n']}")
print(f"P4-SR3 vs P4 ctrl: dR={p4_sr3['cum']-p4_ctrl['cum']:.4f} dDD={p4_sr3['dd']-p4_ctrl['dd']:.4f} dTrades={p4_sr3['n']-p4_ctrl['n']}")

print("\n=== Weak-core-month behavior (A alone monthly negative months) ===")
a_rows = list(csv.DictReader(open(f"{CTRL_ROOT}/D29_A/MSZZ_TradeAnalytics.csv"), delimiter=';'))
for r in a_rows:
    r['close_time_dt']=parse_dt(r['close_time']); r['r_result']=float(r['r_result'])
a_monthly=defaultdict(float)
for r in a_rows:
    key=f"{r['close_time_dt'].year}-{r['close_time_dt'].month:02d}"
    a_monthly[key]+=r['r_result']
weak_months=sorted([k for k,v in a_monthly.items() if v<0])
print(f"D29-A weak months: {weak_months}")
for wm in weak_months:
    p3c = p3_ctrl['monthly'].get(wm,0.0); p3s = p3_sr3['monthly'].get(wm,0.0)
    print(f"  {wm}: A_alone={a_monthly[wm]:.4f} P3_ctrl={p3c:.4f} P3_SR3={p3s:.4f} -> {'improved' if p3s>p3c else ('worsened' if p3s<p3c else 'unchanged')}")
