#!/usr/bin/env python3
import csv, statistics, hashlib
from datetime import datetime
from collections import defaultdict

ROOT = "/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results"
VARIANTS = ["SR0", "SR3_PCT", "SR4_PCT"]

DEV_START = datetime(2025,3,1); DEV_END = datetime(2025,12,31,23,59,59)
VAL_START = datetime(2026,1,1); VAL_END = datetime(2026,4,30,23,59,59)
HOLD_START = datetime(2026,5,1); HOLD_END = datetime(2026,7,24,23,59,59)

def parse_dt(s):
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")

def load_trades(variant):
    path = f"{ROOT}/{variant}/MSZZ_TradeAnalytics.csv"
    rows = list(csv.DictReader(open(path), delimiter=';'))
    for r in rows:
        r['close_time_dt'] = parse_dt(r['close_time'])
        r['entry_time_dt'] = parse_dt(r['fill_time']) if r['fill_time'] else r['close_time_dt']
        r['r_result'] = float(r['r_result'])
        r['mfe_r'] = float(r['mfe_r'])
        r['mae_r'] = float(r['mae_r'])
        r['bars_held'] = float(r['bars_held'])
    rows.sort(key=lambda r: r['close_time_dt'])
    return rows

def expectancy(rows):
    return sum(r['r_result'] for r in rows)/len(rows) if rows else 0.0

def pf(rows):
    g = sum(r['r_result'] for r in rows if r['r_result'] > 0)
    l = -sum(r['r_result'] for r in rows if r['r_result'] < 0)
    return g/l if l>0 else float('inf')

def maxdd(rows):
    eq=0.0; peak=0.0; dd=0.0
    for r in rows:
        eq+=r['r_result']; peak=max(peak,eq); dd=max(dd,peak-eq)
    return dd

def wslice(rows,s,e):
    return [r for r in rows if s<=r['close_time_dt']<=e]

def quarter_key(dt):
    q=(dt.month-1)//3+1
    return f"{dt.year}Q{q}"

def analyze(variant):
    rows = load_trades(variant)
    n=len(rows)
    cum=sum(r['r_result'] for r in rows)
    dev=wslice(rows,DEV_START,DEV_END); val=wslice(rows,VAL_START,VAL_END); hold=wslice(rows,HOLD_START,HOLD_END)
    longs=[r for r in rows if r['direction']=='LONG']; shorts=[r for r in rows if r['direction']=='SHORT']
    sorted_r=sorted(rows,key=lambda r:-r['r_result'])
    top3_ids=set(id(x) for x in sorted_r[:3])
    top3_removed=[r for r in rows if id(r) not in top3_ids]
    top5_ids=set(id(x) for x in sorted_r[:5])
    top5_removed=[r for r in rows if id(r) not in top5_ids]
    quarters=defaultdict(list)
    for r in rows: quarters[quarter_key(r['close_time_dt'])].append(r)
    best_q=max(quarters.items(),key=lambda kv: sum(x['r_result'] for x in kv[1]))[0] if quarters else None
    bq_removed=[r for r in rows if quarter_key(r['close_time_dt'])!=best_q]
    exit_reasons=defaultdict(int)
    for r in rows: exit_reasons[r['exit_reason']]+=1
    hold_bars=[r['bars_held'] for r in rows]
    mean_hold=statistics.mean(hold_bars) if hold_bars else 0.0
    median_hold=statistics.median(hold_bars) if hold_bars else 0.0
    p90_hold=sorted(hold_bars)[int(0.9*(len(hold_bars)-1))] if hold_bars else 0.0
    mfe_ge = {t: sum(1 for r in rows if r['mfe_r']>=t)/n if n else 0 for t in (0.5,1.0,2.0)}
    avg_mfe = statistics.mean([r['mfe_r'] for r in rows]) if rows else 0.0
    avg_giveback = statistics.mean([r['mfe_r']-r['r_result'] for r in rows]) if rows else 0.0

    h = hashlib.sha256(open(f"{ROOT}/{variant}/MSZZ_TradeAnalytics.csv",'rb').read()).hexdigest()

    print(f"\n{'='*70}\n{variant}\n{'='*70}")
    print(f"trades={n} cum_r={cum:.4f} expectancy={expectancy(rows):.4f} PF={pf(rows):.4f} maxDD={maxdd(rows):.4f} win_rate={sum(1 for r in rows if r['r_result']>0)/n:.4f}")
    print(f"mean_hold={mean_hold:.2f} median_hold={median_hold:.2f} p90_hold={p90_hold:.2f}")
    print(f"Dev n={len(dev)} cum={sum(r['r_result'] for r in dev):.4f} exp={expectancy(dev):.4f}")
    print(f"Val n={len(val)} cum={sum(r['r_result'] for r in val):.4f} exp={expectancy(val):.4f}")
    print(f"Hold n={len(hold)} cum={sum(r['r_result'] for r in hold):.4f} exp={expectancy(hold):.4f}")
    print(f"Long n={len(longs)} exp={expectancy(longs):.4f} | Short n={len(shorts)} exp={expectancy(shorts):.4f}")
    print(f"top3-removed cum={sum(r['r_result'] for r in top3_removed):.4f} exp={expectancy(top3_removed):.4f}")
    print(f"top5-removed cum={sum(r['r_result'] for r in top5_removed):.4f} exp={expectancy(top5_removed):.4f}")
    print(f"best_quarter={best_q} best-quarter-removed cum={sum(r['r_result'] for r in bq_removed):.4f} exp={expectancy(bq_removed):.4f}")
    print(f"exit_reasons={dict(exit_reasons)}")
    print(f"mfe>=0.5R={mfe_ge[0.5]:.4f} mfe>=1.0R={mfe_ge[1.0]:.4f} mfe>=2.0R={mfe_ge[2.0]:.4f}")
    print(f"avg_mfe={avg_mfe:.4f} avg_giveback={avg_giveback:.4f}")
    print(f"MSZZ_TradeAnalytics.csv SHA-256={h}")
    return dict(variant=variant,n=n,cum=cum,exp=expectancy(rows),pf=pf(rows),dd=maxdd(rows),
                dev_n=len(dev),dev_exp=expectancy(dev),val_n=len(val),val_exp=expectancy(val),
                hold_n=len(hold),hold_exp=expectancy(hold),
                top3_exp=expectancy(top3_removed),bq_exp=expectancy(bq_removed),sha=h)

def analyze_sizing(variant):
    path=f"{ROOT}/{variant}/MSZZ_SizingJournal.csv"
    rows=list(csv.DictReader(open(path),delimiter=';'))
    total=len(rows)
    ok=[r for r in rows if r['sizing_result']=='OK']
    rejected=[r for r in rows if r['sizing_result']=='REJECTED']
    reject_reasons=defaultdict(int)
    for r in rejected: reject_reasons[r['reject_reason']]+=1
    print(f"\n--- {variant} volume resolution ---")
    print(f"sizing decisions={total} OK={len(ok)} REJECTED={len(rejected)} reasons={dict(reject_reasons)}")

def analyze_signal(variant):
    path=f"{ROOT}/{variant}/MSZZ_SignalJournal.csv"
    rows=list(csv.DictReader(open(path),delimiter=';'))
    status=defaultdict(int)
    for r in rows: status[r['status']]+=1
    print(f"--- {variant} signal status: {dict(status)}")
    return status.get('RAW_CANDIDATE',0)

def analyze_partial(variant):
    path=f"{ROOT}/{variant}/MSZZ_PartialCloseJournal.csv"
    try:
        rows=list(csv.DictReader(open(path),delimiter=';'))
    except FileNotFoundError:
        print(f"--- {variant}: no MSZZ_PartialCloseJournal.csv (no partial policy active) ---")
        return
    n=len(rows)
    for r in rows:
        r['original_volume']=float(r['original_volume'])
        r['executed_partial_volume']=float(r['executed_partial_volume'])
        r['remaining_volume']=float(r['remaining_volume'])
    exact_recon=sum(1 for r in rows if abs(r['executed_partial_volume']+r['remaining_volume']-r['original_volume'])<1e-6)
    fractions=[r['executed_partial_volume']/r['original_volume'] for r in rows if r['original_volume']>0]
    exact_50 = sum(1 for f in fractions if abs(f-0.5)<0.02)
    print(f"\n--- {variant} partial accounting ---")
    print(f"partial events={n} exact_volume_reconciliation={exact_recon}/{n}")
    if fractions:
        print(f"executed_fraction: mean={statistics.mean(fractions):.4f} min={min(fractions):.4f} max={max(fractions):.4f} within_2pct_of_50%={exact_50}/{n}")

def check_partial_volume_ineligible(variant):
    path=f"{ROOT}/{variant}/MSZZ_SignalJournal.csv"
    rows=list(csv.DictReader(open(path),delimiter=';'))
    n=sum(1 for r in rows if r['status']=='REJECT_PARTIAL_VOLUME_INELIGIBLE')
    print(f"--- {variant}: REJECT_PARTIAL_VOLUME_INELIGIBLE count = {n}")

results={}
for v in VARIANTS:
    results[v]=analyze(v)
    analyze_sizing(v)
    check_partial_volume_ineligible(v)
    analyze_partial(v)

print("\n=== Same-signal proof (RAW_CANDIDATE counts) ===")
for v in VARIANTS:
    n=analyze_signal(v)
    print(f"{v}: RAW_CANDIDATE={n}")
