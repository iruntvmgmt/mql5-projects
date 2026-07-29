#!/usr/bin/env python3
"""D029 audit remediation, Finding G: the original Phase 3 analyzer
(Tools/D029/Phase3/analyze_partials.py) labeled `abs(f-0.5)<0.02` as
"exact_50" internally -- wrong terminology for a 2-percentage-point
tolerance bucket, not floating-point exactness. This script reprocesses
the SAME MSZZ_PartialCloseJournal.csv data (SR3_PCT, SR4_PCT from Phase 3;
P3_SR3, P4_SR3 from Phase 4) with the corrected categories the handoff
requires: exact 50.0000% (to floating tolerance), within 1 percentage
point (excluding exact), within 2 percentage points (excluding within-1pp),
outside 2 percentage points, plus min/max/mean/median of the executed
fraction. Fails loudly on a missing input file; writes a deterministic CSV.
"""
import csv, statistics, sys

ROOTS = {
    "SR3_PCT": "/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/SR3_PCT",
    "SR4_PCT": "/Users/matt/MT5-MSZZ-TEST/D029_Phase3_Results/SR4_PCT",
    "P3_SR3": "/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/P3_SR3",
    "P4_SR3": "/Users/matt/MT5-MSZZ-TEST/D029_Phase4_Results/P4_SR3",
}
OUT = "/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Tools/D029/Audit"

EXACT_TOL = 1e-6      # floating-point exactness, not a percentage tolerance
ONE_PP = 0.01          # 1 percentage point == 0.01 of the fraction
TWO_PP = 0.02          # 2 percentage points == 0.02 of the fraction

rows_out = []

for variant, path in ROOTS.items():
    filename = f"{path}/MSZZ_PartialCloseJournal.csv"
    try:
        rows = list(csv.DictReader(open(filename), delimiter=';'))
    except FileNotFoundError:
        print(f"FATAL: missing required input {filename}")
        sys.exit(1)

    fractions = []
    for r in rows:
        original = float(r['original_volume'])
        executed = float(r['executed_partial_volume'])
        if original <= 0.0:
            print(f"FATAL: {variant} has a partial-close row with original_volume<=0")
            sys.exit(1)
        fractions.append(executed / original)

    n = len(fractions)
    if n == 0:
        print(f"FATAL: {variant} has zero partial-close events -- nothing to summarize")
        sys.exit(1)

    exact_50 = 0
    within_1pp = 0
    within_2pp = 0
    outside_2pp = 0
    for f in fractions:
        dist = abs(f - 0.5)
        if dist < EXACT_TOL:
            exact_50 += 1
        elif dist <= ONE_PP:
            within_1pp += 1
        elif dist <= TWO_PP:
            within_2pp += 1
        else:
            outside_2pp += 1

    row = dict(
        variant=variant,
        partial_events=n,
        exact_50_0000pct_count=exact_50,
        exact_50_0000pct_pct=round(100.0 * exact_50 / n, 4),
        within_1pp_count=within_1pp,
        within_1pp_pct=round(100.0 * within_1pp / n, 4),
        within_2pp_count=within_2pp,
        within_2pp_pct=round(100.0 * within_2pp / n, 4),
        outside_2pp_count=outside_2pp,
        outside_2pp_pct=round(100.0 * outside_2pp / n, 4),
        min_fraction=round(min(fractions), 6),
        max_fraction=round(max(fractions), 6),
        mean_fraction=round(statistics.mean(fractions), 6),
        median_fraction=round(statistics.median(fractions), 6),
    )
    rows_out.append(row)
    print(f"{variant}: n={n} exact={exact_50} within_1pp={within_1pp} within_2pp={within_2pp} "
          f"outside_2pp={outside_2pp} min={row['min_fraction']} max={row['max_fraction']} "
          f"mean={row['mean_fraction']} median={row['median_fraction']}")

fieldnames = ["variant","partial_events","exact_50_0000pct_count","exact_50_0000pct_pct",
              "within_1pp_count","within_1pp_pct","within_2pp_count","within_2pp_pct",
              "outside_2pp_count","outside_2pp_pct","min_fraction","max_fraction",
              "mean_fraction","median_fraction"]
with open(f"{OUT}/corrected_partial_fraction_summary.csv", "w", newline='') as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for r in rows_out:
        w.writerow(r)

print(f"\nWrote {OUT}/corrected_partial_fraction_summary.csv ({len(rows_out)} variants)")
sys.exit(0)
