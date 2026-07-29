#!/usr/bin/env python3
import csv, math

TICK_SIZE = 0.01
TICK_VALUE = 1.00
CONTRACT_SIZE = 100.0
VOL_MIN = 0.01
VOL_STEP = 0.01
RISK_PCT = 0.25

rows = list(csv.DictReader(open('/Users/matt/MT5-MSZZ-TEST/D028_Stage5_Results/SR0/MSZZ_TradeAnalytics.csv'), delimiter=';'))
dists = [abs(float(r['entry'])-float(r['stop'])) for r in rows]
n = len(dists)

def normalize_down(vol, step):
    steps = math.floor(vol / step + 1e-9)
    return round(steps * step, 8)

def project(balance):
    requested_risk_money = balance * RISK_PCT / 100.0
    ge02 = 0
    exact5050 = 0
    mismatch = 0
    below_min = 0
    for d in dists:
        loss_per_lot = d * (TICK_VALUE / TICK_SIZE)
        raw_vol = requested_risk_money / loss_per_lot
        norm_vol = normalize_down(raw_vol, VOL_STEP)
        if norm_vol < VOL_MIN:
            below_min += 1
            continue
        if norm_vol >= 0.02:
            ge02 += 1
            # multiple of 0.02 (within fp tolerance) splits evenly 0.01/0.01 etc.
            steps02 = norm_vol / 0.02
            if abs(steps02 - round(steps02)) < 1e-6:
                exact5050 += 1
            else:
                mismatch += 1
    return dict(balance=balance, ge02_pct=100*ge02/n, exact5050_pct=100*exact5050/n,
                mismatch_pct=100*mismatch/n, below_min_pct=100*below_min/n)

candidates = [10000, 25000, 50000, 75000, 100000, 150000]
print(f"{'balance':>10} {'>=0.02%':>10} {'exact5050%':>12} {'mismatch%':>11} {'below_min%':>11}")
for b in candidates:
    r = project(b)
    print(f"{r['balance']:>10} {r['ge02_pct']:>9.2f}% {r['exact5050_pct']:>11.2f}% {r['mismatch_pct']:>10.2f}% {r['below_min_pct']:>10.2f}%")

# write CSV
with open('/private/tmp/claude-502/-Users-matt/d62aa486-4ac9-43cc-bedf-abdd8b592b8b/scratchpad/volume_resolution_summary.csv','w',newline='') as f:
    w = csv.writer(f)
    w.writerow(['candidate_balance','pct_ge_0.02_lots','pct_exact_50_50_split','pct_normalized_remainder_mismatch','pct_below_minimum_volume'])
    for b in candidates:
        r = project(b)
        w.writerow([b, round(r['ge02_pct'],2), round(r['exact5050_pct'],2), round(r['mismatch_pct'],2), round(r['below_min_pct'],2)])
