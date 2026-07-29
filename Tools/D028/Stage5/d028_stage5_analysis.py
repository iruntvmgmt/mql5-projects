#!/usr/bin/env python3
import csv, sys, statistics
from datetime import datetime
from collections import defaultdict

ROOT = "/Users/matt/MT5-MSZZ-TEST/D028_Stage5_Results"
VARIANTS = ["SR0", "SR1", "SR2", "SR3", "SR4", "SR5"]

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
        r['r_result'] = float(r['r_result'])
        r['mfe_r'] = float(r['mfe_r'])
        r['mae_r'] = float(r['mae_r'])
        r['bars_held'] = float(r['bars_held'])
    rows.sort(key=lambda r: r['close_time_dt'])
    return rows

def expectancy(rows):
    if not rows: return 0.0
    return sum(r['r_result'] for r in rows) / len(rows)

def profit_factor(rows):
    gains = sum(r['r_result'] for r in rows if r['r_result'] > 0)
    losses = -sum(r['r_result'] for r in rows if r['r_result'] < 0)
    if losses == 0: return float('inf') if gains > 0 else 0.0
    return gains / losses

def max_drawdown(rows):
    equity = 0.0; peak = 0.0; maxdd = 0.0
    for r in rows:
        equity += r['r_result']
        peak = max(peak, equity)
        maxdd = max(maxdd, peak - equity)
    return maxdd

def win_rate(rows):
    if not rows: return 0.0
    return sum(1 for r in rows if r['r_result'] > 0) / len(rows)

def median(vals):
    return statistics.median(vals) if vals else 0.0

def p90(vals):
    if not vals: return 0.0
    s = sorted(vals)
    idx = min(len(s)-1, int(round(0.9*(len(s)-1))))
    return s[idx]

def window_slice(rows, start, end):
    return [r for r in rows if start <= r['close_time_dt'] <= end]

def quarter_key(dt):
    q = (dt.month-1)//3 + 1
    return f"{dt.year}Q{q}"

def analyze(variant):
    rows = load_trades(variant)
    n = len(rows)
    cum_r = sum(r['r_result'] for r in rows)
    exp = expectancy(rows)
    pf = profit_factor(rows)
    dd = max_drawdown(rows)
    wr = win_rate(rows)
    med_r = median([r['r_result'] for r in rows])
    hold = [r['bars_held'] for r in rows]
    mean_hold = statistics.mean(hold) if hold else 0.0
    med_hold = median(hold)
    p90_hold = p90(hold)

    dev = window_slice(rows, DEV_START, DEV_END)
    val = window_slice(rows, VAL_START, VAL_END)
    hold_w = window_slice(rows, HOLD_START, HOLD_END)

    longs = [r for r in rows if r['direction'] == 'LONG']
    shorts = [r for r in rows if r['direction'] == 'SHORT']

    quarters = defaultdict(list)
    for r in rows:
        quarters[quarter_key(r['close_time_dt'])].append(r)
    quarter_stats = {q: (len(v), sum(x['r_result'] for x in v), expectancy(v)) for q,v in sorted(quarters.items())}

    # Top-3 trade removal
    sorted_by_r = sorted(rows, key=lambda r: -r['r_result'])
    top3_removed = rows_minus(rows, sorted_by_r[:3])
    top3_cum = sum(r['r_result'] for r in top3_removed)
    top3_exp = expectancy(top3_removed)

    # Best-quarter removal
    best_q = max(quarter_stats.items(), key=lambda kv: kv[1][1])[0] if quarter_stats else None
    best_q_removed = [r for r in rows if quarter_key(r['close_time_dt']) != best_q]
    bq_cum = sum(r['r_result'] for r in best_q_removed)
    bq_exp = expectancy(best_q_removed)

    exit_reasons = defaultdict(int)
    for r in rows:
        exit_reasons[r['exit_reason']] += 1

    mfe_ge = {t: sum(1 for r in rows if r['mfe_r']>=t)/n if n else 0 for t in (0.5,1.0,2.0)}
    avg_mfe = statistics.mean([r['mfe_r'] for r in rows]) if rows else 0.0
    avg_giveback = statistics.mean([r['mfe_r']-r['r_result'] for r in rows]) if rows else 0.0

    return dict(variant=variant, n=n, cum_r=cum_r, exp=exp, pf=pf, dd=dd, wr=wr, med_r=med_r,
                mean_hold=mean_hold, med_hold=med_hold, p90_hold=p90_hold,
                dev_n=len(dev), dev_cum=sum(r['r_result'] for r in dev), dev_exp=expectancy(dev),
                val_n=len(val), val_cum=sum(r['r_result'] for r in val), val_exp=expectancy(val),
                hold_n=len(hold_w), hold_cum=sum(r['r_result'] for r in hold_w), hold_exp=expectancy(hold_w),
                long_n=len(longs), long_exp=expectancy(longs), short_n=len(shorts), short_exp=expectancy(shorts),
                quarter_stats=quarter_stats, top3_cum=top3_cum, top3_exp=top3_exp,
                best_q=best_q, bq_cum=bq_cum, bq_exp=bq_exp,
                exit_reasons=dict(exit_reasons), mfe_ge=mfe_ge, avg_mfe=avg_mfe, avg_giveback=avg_giveback)

def rows_minus(rows, remove):
    remove_ids = set(id(x) for x in remove)
    return [r for r in rows if id(r) not in remove_ids]

if __name__ == "__main__":
    results = {}
    for v in VARIANTS:
        results[v] = analyze(v)

    for v in VARIANTS:
        d = results[v]
        print(f"\n{'='*70}\n{v}\n{'='*70}")
        print(f"trades={d['n']} cum_r={d['cum_r']:.4f} expectancy={d['exp']:.4f} PF={d['pf']:.4f} maxDD={d['dd']:.4f} win_rate={d['wr']:.4f}")
        print(f"median_r={d['med_r']:.4f} mean_hold={d['mean_hold']:.2f} median_hold={d['med_hold']:.2f} p90_hold={d['p90_hold']:.2f}")
        print(f"DEV   n={d['dev_n']:3d} cum={d['dev_cum']:8.4f} exp={d['dev_exp']:.4f}")
        print(f"VAL   n={d['val_n']:3d} cum={d['val_cum']:8.4f} exp={d['val_exp']:.4f}")
        print(f"HOLD  n={d['hold_n']:3d} cum={d['hold_cum']:8.4f} exp={d['hold_exp']:.4f}")
        print(f"LONG  n={d['long_n']:3d} exp={d['long_exp']:.4f}   SHORT n={d['short_n']:3d} exp={d['short_exp']:.4f}")
        print(f"top3-removed cum={d['top3_cum']:.4f} exp={d['top3_exp']:.4f}")
        print(f"best_quarter={d['best_q']} best-quarter-removed cum={d['bq_cum']:.4f} exp={d['bq_exp']:.4f}")
        print(f"exit_reasons={d['exit_reasons']}")
        print(f"mfe>=0.5R={d['mfe_ge'][0.5]:.4f} mfe>=1.0R={d['mfe_ge'][1.0]:.4f} mfe>=2.0R={d['mfe_ge'][2.0]:.4f}")
        print(f"avg_mfe={d['avg_mfe']:.4f} avg_giveback(mfe-realized)={d['avg_giveback']:.4f}")
        print("quarters:", {k: (n_,round(c,3),round(e,4)) for k,(n_,c,e) in d['quarter_stats'].items()})
