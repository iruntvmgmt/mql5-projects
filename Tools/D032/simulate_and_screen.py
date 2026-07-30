#!/usr/bin/env python3
"""D032: standalone synthetic screening of the six D031 shadow families.

One shared simulator, frozen assumptions, applied identically to all six
families:
  - entry: the family's own emitted `entry` price (bar-close at signal
    confirmation) -- this is the same execution model the production
    strategies already use (D027StrategyFamilies.mqh's own Emit() uses
    bar.close directly), not a new, undocumented shifted-entry model.
  - canonical stop / canonical target: the family's own emitted stop/target
    (no re-optimization, no sweep).
  - same spread/cost assumptions as the candidate journal already reflects
    (spread_to_risk_ratio was computed from the real bar's spread at
    signal time -- see ResearchCandidateTypes.mqh).
  - same sizing basis: R-multiples throughout, 1R = the candidate's own
    entry-to-stop distance (identical convention P4's own RMultiple() uses).
  - one logical position per family, no same-family stacking: candidates
    are processed in signal_time order per family; a new candidate is
    rejected while that family already has an unresolved open position.
  - no future leakage: outcomes are resolved by walking the closed-bar
    price series strictly forward from the bar AFTER signal_time.

Same-bar stop/target ambiguity: per RESEARCH_JOURNAL_SCHEMA.md's own rule
("do not assume the favorable outcome"), if a single bar's range contains
both the stop and the target, the stop is assumed to have been hit first
(conservative, matches Range Rotation's own MQL5 same-bar handling
elsewhere in this codebase).

Trades still open when the price series ends are excluded from closed-
trade statistics and reported separately, not scored as wins or losses.
"""
import csv
import statistics
from collections import defaultdict
from datetime import datetime

HERE = "/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Tools/D032"
RATES_PATH = f"{HERE}/D032_Rates_XAUUSD_M5.csv"
CANDIDATES_PATH = f"{HERE}/D032_SixFamilyResearchJournal_source.csv"
REGIME_PATH = f"{HERE}/D032_RegimeJournal_source.csv"
P4_REFERENCE_PATH = f"{HERE}/D032_P4_TradeAnalytics_reference.csv"
OUT = f"{HERE}/out"

DEV_START = datetime(2025, 3, 1); DEV_END = datetime(2025, 12, 31, 23, 59, 59)
VAL_START = datetime(2026, 1, 1); VAL_END = datetime(2026, 4, 30, 23, 59, 59)
HOLD_START = datetime(2026, 5, 1); HOLD_END = datetime(2026, 7, 24, 23, 59, 59)

FAMILY_NAMES = {
    "1200": "Session Sweep Reversal", "1201": "Momentum Continuation",
    "1202": "Break-Retest Continuation", "1203": "Compression Breakout (Research)",
    "1204": "Trend Pullback", "1205": "Range Rotation",
}


def parse_dt(s):
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")


def split_label(dt):
    if DEV_START <= dt <= DEV_END:
        return "development"
    if VAL_START <= dt <= VAL_END:
        return "validation"
    if HOLD_START <= dt <= HOLD_END:
        return "holdout"
    return "outside_frozen_windows"


def load_rates():
    with open(RATES_PATH, newline="") as f:
        rows = list(csv.DictReader(f, delimiter=";"))
    for r in rows:
        r["dt"] = parse_dt(r["time"])
        r["open"] = float(r["open"]); r["high"] = float(r["high"])
        r["low"] = float(r["low"]); r["close"] = float(r["close"])
    return rows


CANDIDATE_HEAD_COLS = ["strategy_id", "family_id", "setup_name", "signal_time", "expiry_time",
                       "direction", "entry", "stop", "target", "score", "origin_id", "event_id",
                       "reason", "canonical_variant_id", "hypothesis_version", "regime_id",
                       "session_id", "reference_level_type"]  # 18 fields, positions 0-17


def load_candidates():
    """MSZZ_SixFamilyResearchJournal.csv's structural_context field embeds
    its OWN ';'-separated sub-fields (e.g. "compression_high=X;compression_low=Y"),
    which collides with the CSV's own ';' delimiter -- MQL5's FileWrite
    does not quote/escape delimiter characters inside a field. Every row's
    trailing columns (structural_context onward) are misaligned as a
    result, by however many extra ';' that row's structural_context
    happens to contain. This is a real bug in Research/Families/*.mqh
    (fixed going forward -- see the source files), worked around here for
    this already-generated evidence: the first 18 fields (up to
    reference_level_type) and the LAST 3 fields (stop_distance_points,
    target_r, spread_to_risk_ratio, always plain numbers) are reliably
    positioned; everything in between is structural_context with its
    internal ';' separators restored."""
    with open(CANDIDATES_PATH, newline="") as f:
        header = f.readline()
        lines = f.readlines()
    rows = []
    for line in lines:
        parts = line.rstrip("\n").split(";")
        head = parts[:18]
        tail = parts[-3:]
        structural_context = ";".join(parts[18:-3])
        r = dict(zip(CANDIDATE_HEAD_COLS, head))
        r["structural_context"] = structural_context
        r["stop_distance_points"], r["target_r"], r["spread_to_risk_ratio"] = tail
        r["signal_dt"] = parse_dt(r["signal_time"])
        r["entry"] = float(r["entry"]); r["stop"] = float(r["stop"]); r["target"] = float(r["target"])
        r["target_r"] = float(r["target_r"])
        rows.append(r)
    rows.sort(key=lambda r: r["signal_dt"])
    return rows


def simulate_family(candidates, rates, rate_index_by_time, rate_times_sorted):
    """Walk each candidate forward through the bar series. Returns list of
    resolved trade dicts plus a count of still-open (excluded) candidates."""
    import bisect
    trades = []
    open_until = None  # this family's currently-open position resolves at/after this bar index
    still_open = 0
    rejected_stacked = 0

    for c in candidates:
        # Find the first bar strictly AFTER signal_time (entry already
        # happened at the signal bar's own close per the frozen assumption
        # above; outcome resolution starts walking from the next bar).
        idx = bisect.bisect_right(rate_times_sorted, c["signal_dt"])
        if idx >= len(rates):
            continue  # signal too close to the end of the series, no forward data at all

        if open_until is not None and idx <= open_until:
            rejected_stacked += 1
            continue  # no same-family stacking: this family already has an open position

        direction = c["direction"]
        entry, stop, target = c["entry"], c["stop"], c["target"]
        risk = abs(entry - stop)
        resolved = False
        for j in range(idx, len(rates)):
            bar = rates[j]
            hit_stop = (bar["low"] <= stop) if direction == "LONG" else (bar["high"] >= stop)
            hit_target = (bar["high"] >= target) if direction == "LONG" else (bar["low"] <= target)
            if hit_stop and hit_target:
                r = -1.0
            elif hit_stop:
                r = -1.0
            elif hit_target:
                r = c["target_r"]
            else:
                continue
            # MFE/MAE across the trade's actual lifetime [idx, j]
            if direction == "LONG":
                mfe_price = max(rates[k]["high"] for k in range(idx, j + 1))
                mae_price = min(rates[k]["low"] for k in range(idx, j + 1))
                mfe_r = (mfe_price - entry) / risk if risk > 0 else 0.0
                mae_r = (mae_price - entry) / risk if risk > 0 else 0.0
            else:
                mfe_price = min(rates[k]["low"] for k in range(idx, j + 1))
                mae_price = max(rates[k]["high"] for k in range(idx, j + 1))
                mfe_r = (entry - mfe_price) / risk if risk > 0 else 0.0
                mae_r = (entry - mae_price) / risk if risk > 0 else 0.0
            trades.append({
                "strategy_id": c["strategy_id"], "family_id": c["family_id"],
                "direction": direction, "signal_time": c["signal_time"],
                "entry_time": c["signal_time"], "exit_time": rates[j]["time"],
                "entry": entry, "stop": stop, "target": target,
                "realized_r": r, "target_r": c["target_r"],
                "mfe_r": round(mfe_r, 4), "mae_r": round(mae_r, 4),
                "holding_bars": j - idx + 1,
                "session_id": c["session_id"], "regime_id": c["regime_id"],
                "origin_id": c["origin_id"], "event_id": c["event_id"],
            })
            open_until = j
            resolved = True
            break
        if not resolved:
            still_open += 1
    return trades, still_open, rejected_stacked


def pf(rs):
    g = sum(r for r in rs if r > 0); l = -sum(r for r in rs if r < 0)
    if l <= 0:
        return -1.0 if g > 0 else 0.0
    return g / l


def max_dd(rs):
    eq = 0.0; peak = 0.0; dd = 0.0
    for r in rs:
        eq += r; peak = max(peak, eq); dd = max(dd, peak - eq)
    return dd


def load_p4_windows():
    with open(P4_REFERENCE_PATH, newline="") as f:
        rows = list(csv.DictReader(f, delimiter=";"))
    out = []
    for r in rows:
        out.append((parse_dt(r["entry_time"]), parse_dt(r["exit_time"]), r["direction"]))
    return out


def load_regime_by_time():
    with open(REGIME_PATH, newline="") as f:
        rows = list(csv.DictReader(f, delimiter=";"))
    by_time = {}
    for r in rows:
        by_time[r["time"]] = r
    return by_time


def overlap_with_p4(trade_entry_dt, trade_exit_dt, p4_windows):
    episodes = 0
    for (ps, pe, pdir) in p4_windows:
        os_, oe_ = max(trade_entry_dt, ps), min(trade_exit_dt, pe)
        if os_ < oe_:
            episodes += 1
    return episodes


def screen_family(sid, trades, still_open, rejected_stacked, p4_windows, regime_by_time):
    rows_out = []
    name = FAMILY_NAMES[sid]
    rs = [t["realized_r"] for t in trades]
    n = len(rs)

    def split_stats(label):
        sub = [t for t in trades if split_label(parse_dt(t["exit_time"])) == label]
        srs = [t["realized_r"] for t in sub]
        return len(sub), (round(statistics.mean(srs), 4) if srs else None), (round(sum(srs), 4) if srs else None)

    dev_n, dev_exp, dev_tot = split_stats("development")
    val_n, val_exp, val_tot = split_stats("validation")
    hold_n, hold_exp, hold_tot = split_stats("holdout")

    longs = [t["realized_r"] for t in trades if t["direction"] == "LONG"]
    shorts = [t["realized_r"] for t in trades if t["direction"] == "SHORT"]

    winners = [r for r in rs if r > 0]; losers = [r for r in rs if r < 0]

    rs_sorted_desc = sorted(rs, reverse=True)
    def excl(k):
        remaining = rs_sorted_desc[k:]
        return round(sum(remaining), 4), round(pf(remaining), 4), (sum(remaining) > 0)

    top1 = excl(1); top3 = excl(3); top5 = excl(5)

    months = defaultdict(list)
    quarters = defaultdict(list)
    for t in trades:
        dt = parse_dt(t["exit_time"])
        mk = f"{dt.year}-{dt.month:02d}"
        qk = f"{dt.year}-Q{(dt.month-1)//3+1}"
        months[mk].append(t["realized_r"]); quarters[qk].append(t["realized_r"])
    if months:
        best_month = max(months, key=lambda m: sum(months[m]))
        rem_month = [r for m, rr in months.items() if m != best_month for r in rr]
        best_month_excl_positive = sum(rem_month) > 0 if rem_month else None
    else:
        best_month_excl_positive = None
    if quarters:
        best_q = max(quarters, key=lambda q: sum(quarters[q]))
        rem_q = [r for q, rr in quarters.items() if q != best_q for r in rr]
        best_quarter_excl_positive = sum(rem_q) > 0 if rem_q else None
    else:
        best_quarter_excl_positive = None

    session_stats = defaultdict(list)
    for t in trades:
        session_stats[t["session_id"]].append(t["realized_r"])

    regime_stats = defaultdict(list)
    for t in trades:
        reg = regime_by_time.get(t["regime_id"])
        key = reg["market_phase"] if reg else "UNKNOWN"
        regime_stats[key].append(t["realized_r"])

    overlap_episodes = sum(1 for t in trades if overlap_with_p4(parse_dt(t["entry_time"]), parse_dt(t["exit_time"]), p4_windows) > 0)

    expectancy = round(statistics.mean(rs), 4) if rs else 0.0
    total_r = round(sum(rs), 4)
    the_pf = round(pf(rs), 4)

    gates = {
        "min_100_trades": n >= 100,
        "positive_total_expectancy": expectancy > 0,
        "pf_gt_1.05": the_pf > 1.05,
        "positive_dev_expectancy": (dev_exp or 0) > 0,
        "positive_val_expectancy": (val_exp or 0) > 0,
        "positive_holdout_expectancy": (hold_exp or 0) > 0,
        "top3_exclusion_positive": top3[2],
        "best_quarter_exclusion_positive": bool(best_quarter_excl_positive),
    }
    all_gates_pass = all(gates.values())
    pf_gte_1_15 = the_pf >= 1.15

    summary = {
        "strategy_id": sid, "family_id": trades[0]["family_id"] if trades else "",
        "family_name": name,
        "trade_count": n, "still_open_excluded": still_open, "rejected_same_family_stacking": rejected_stacked,
        "win_rate": round(len(winners) / n, 4) if n else 0.0,
        "expectancy_r": expectancy, "pf": the_pf, "total_r": total_r,
        "max_drawdown_r": round(max_dd(rs), 4),
        "avg_winner_r": round(statistics.mean(winners), 4) if winners else None,
        "avg_loser_r": round(statistics.mean(losers), 4) if losers else None,
        "dev_trades": dev_n, "dev_expectancy_r": dev_exp, "dev_total_r": dev_tot,
        "val_trades": val_n, "val_expectancy_r": val_exp, "val_total_r": val_tot,
        "holdout_trades": hold_n, "holdout_expectancy_r": hold_exp, "holdout_total_r": hold_tot,
        "long_trades": len(longs), "long_expectancy_r": round(statistics.mean(longs), 4) if longs else None,
        "short_trades": len(shorts), "short_expectancy_r": round(statistics.mean(shorts), 4) if shorts else None,
        "top1_excl_total_r": top1[0], "top1_excl_pf": top1[1], "top1_excl_positive": top1[2],
        "top3_excl_total_r": top3[0], "top3_excl_pf": top3[1], "top3_excl_positive": top3[2],
        "top5_excl_total_r": top5[0], "top5_excl_pf": top5[1], "top5_excl_positive": top5[2],
        "best_month_excl_positive": best_month_excl_positive,
        "best_quarter_excl_positive": best_quarter_excl_positive,
        "avg_mfe_r": round(statistics.mean([t["mfe_r"] for t in trades]), 4) if trades else None,
        "avg_mae_r": round(statistics.mean([t["mae_r"] for t in trades]), 4) if trades else None,
        "avg_holding_bars": round(statistics.mean([t["holding_bars"] for t in trades]), 2) if trades else None,
        "p4_overlap_episodes": overlap_episodes,
        "p4_overlap_pct_of_trades": round(100.0 * overlap_episodes / n, 2) if n else 0.0,
        "gate_min_100_trades": gates["min_100_trades"],
        "gate_positive_total_expectancy": gates["positive_total_expectancy"],
        "gate_pf_gt_1.05": gates["pf_gt_1.05"],
        "gate_positive_dev_expectancy": gates["positive_dev_expectancy"],
        "gate_positive_val_expectancy": gates["positive_val_expectancy"],
        "gate_positive_holdout_expectancy": gates["positive_holdout_expectancy"],
        "gate_top3_exclusion_positive": gates["top3_exclusion_positive"],
        "gate_best_quarter_exclusion_positive": gates["best_quarter_exclusion_positive"],
        "ALL_MANDATORY_GATES_PASS": all_gates_pass,
        "optional_pf_gte_1.15": pf_gte_1_15,
    }
    return summary, session_stats, regime_stats


def main():
    rates = load_rates()
    rate_times_sorted = [r["dt"] for r in rates]
    candidates = load_candidates()
    p4_windows = load_p4_windows()
    regime_by_time = load_regime_by_time()

    by_family = defaultdict(list)
    for c in candidates:
        by_family[c["strategy_id"]].append(c)

    all_summaries = []
    all_trades_rows = []
    all_session_rows = []
    all_regime_rows = []

    for sid in ["1200", "1201", "1202", "1203", "1204", "1205"]:
        fam_candidates = by_family.get(sid, [])
        trades, still_open, rejected = simulate_family(fam_candidates, rates, None, rate_times_sorted)
        if not trades:
            all_summaries.append({
                "strategy_id": sid, "family_id": "", "family_name": FAMILY_NAMES[sid],
                "trade_count": 0, "still_open_excluded": still_open,
                "rejected_same_family_stacking": rejected,
                "ALL_MANDATORY_GATES_PASS": False,
            })
            continue
        summary, session_stats, regime_stats = screen_family(sid, trades, still_open, rejected, p4_windows, regime_by_time)
        all_summaries.append(summary)
        for t in trades:
            all_trades_rows.append(t)
        for sess, rs in session_stats.items():
            all_session_rows.append({
                "strategy_id": sid, "session": sess, "trade_count": len(rs),
                "expectancy_r": round(statistics.mean(rs), 4), "total_r": round(sum(rs), 4),
                "pf": round(pf(rs), 4),
            })
        for reg, rs in regime_stats.items():
            all_regime_rows.append({
                "strategy_id": sid, "market_phase": reg, "trade_count": len(rs),
                "expectancy_r": round(statistics.mean(rs), 4), "total_r": round(sum(rs), 4),
                "pf": round(pf(rs), 4),
            })

    # Write outputs
    cols = ["strategy_id", "family_id", "family_name", "trade_count", "still_open_excluded",
            "rejected_same_family_stacking", "win_rate", "expectancy_r", "pf", "total_r",
            "max_drawdown_r", "avg_winner_r", "avg_loser_r", "dev_trades", "dev_expectancy_r",
            "dev_total_r", "val_trades", "val_expectancy_r", "val_total_r", "holdout_trades",
            "holdout_expectancy_r", "holdout_total_r", "long_trades", "long_expectancy_r",
            "short_trades", "short_expectancy_r", "top1_excl_total_r", "top1_excl_pf",
            "top1_excl_positive", "top3_excl_total_r", "top3_excl_pf", "top3_excl_positive",
            "top5_excl_total_r", "top5_excl_pf", "top5_excl_positive", "best_month_excl_positive",
            "best_quarter_excl_positive", "avg_mfe_r", "avg_mae_r", "avg_holding_bars",
            "p4_overlap_episodes", "p4_overlap_pct_of_trades", "gate_min_100_trades",
            "gate_positive_total_expectancy", "gate_pf_gt_1.05", "gate_positive_dev_expectancy",
            "gate_positive_val_expectancy", "gate_positive_holdout_expectancy",
            "gate_top3_exclusion_positive", "gate_best_quarter_exclusion_positive",
            "ALL_MANDATORY_GATES_PASS", "optional_pf_gte_1.15"]
    with open(f"{OUT}/screening_summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for s in all_summaries:
            w.writerow({c: s.get(c) for c in cols})

    trade_cols = ["strategy_id", "family_id", "direction", "signal_time", "entry_time", "exit_time",
                  "entry", "stop", "target", "realized_r", "target_r", "mfe_r", "mae_r",
                  "holding_bars", "session_id", "regime_id", "origin_id", "event_id"]
    with open(f"{OUT}/simulated_trades.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=trade_cols)
        w.writeheader()
        w.writerows(all_trades_rows)

    with open(f"{OUT}/session_attribution.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["strategy_id", "session", "trade_count", "expectancy_r", "total_r", "pf"])
        w.writeheader(); w.writerows(all_session_rows)

    with open(f"{OUT}/regime_attribution.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["strategy_id", "market_phase", "trade_count", "expectancy_r", "total_r", "pf"])
        w.writeheader(); w.writerows(all_regime_rows)

    for s in all_summaries:
        print(f"{s['strategy_id']} {s['family_name']:35s} trades={s['trade_count']:>4} "
              f"pf={s.get('pf')} exp={s.get('expectancy_r')} totR={s.get('total_r')} "
              f"gates_pass={s.get('ALL_MANDATORY_GATES_PASS')} still_open={s['still_open_excluded']} "
              f"rejected_stacked={s['rejected_same_family_stacking']}")


if __name__ == "__main__":
    main()
