#!/usr/bin/env python3
"""D030: P4 loss-cluster and uncovered-regime map.

Reads ONLY certified D029 audit-final-rerun evidence
(/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4/*.csv) for the trade
population, plus the D028 Stage4 P4 run's bar-level MSZZ_RegimeJournal.csv
(the only full bar-by-bar regime census available on disk covering the
D029 dev/val/holdout window -- see README.md "Provenance" for why this
substitution is safe: the Layer 1 regime classifier is a pure, frozen
function of price structure only, unchanged between D028 and D029, and
both runs replay the same broker XAUUSD M5 history).

Read-only. Never mutates strategy code, D029 evidence, or existing docs.
Deterministic: same input files always produce byte-identical output CSVs.
"""
import csv
import hashlib
import statistics
from collections import defaultdict
from datetime import datetime

P4_ROOT = "/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results/D29_P4"
REGIME_CENSUS_PATH = "/Users/matt/MT5-MSZZ-TEST/D028_Stage4_Results/P4_Independent_E3R_Sweep2R/MSZZ_RegimeJournal.csv"
OUT = "/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Tools/D030/out"

DEV_START = datetime(2025, 3, 1); DEV_END = datetime(2025, 12, 31, 23, 59, 59)
VAL_START = datetime(2026, 1, 1); VAL_END = datetime(2026, 4, 30, 23, 59, 59)
HOLD_START = datetime(2026, 5, 1); HOLD_END = datetime(2026, 7, 24, 23, 59, 59)

BOOK_NAMES = {"1": "FastMedConfluence_E3R", "2": "SweepReclaim_2R"}


def parse_dt(s):
    return datetime.strptime(s, "%Y.%m.%d %H:%M:%S")


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def read_csv(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f, delimiter=";"))


# Reuses the exact frozen definition from
# Include/MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh
# CMSZZTradeAnalyticsPolicy::SessionBucket -- three fixed non-overlapping
# 8-hour buckets on broker server time. Not redefined here.
def session_bucket(hour_of_day):
    h = hour_of_day % 24
    if h < 8:
        return "ASIAN"
    if h < 16:
        return "LONDON"
    return "NEWYORK"


def split_label(dt):
    if DEV_START <= dt <= DEV_END:
        return "development"
    if VAL_START <= dt <= VAL_END:
        return "validation"
    if HOLD_START <= dt <= HOLD_END:
        return "holdout"
    return "outside_frozen_windows"


def decile_labels(values, value_key):
    """Assign decile 1..10 (1=lowest) by rank; ties broken by stable sort order."""
    order = sorted(range(len(values)), key=lambda i: values[i][value_key])
    n = len(order)
    labels = [None] * n
    for rank, idx in enumerate(order):
        decile = min(10, int(rank * 10 / n) + 1)
        labels[idx] = decile
    return labels


def load_trades():
    rows = read_csv(f"{P4_ROOT}/MSZZ_PortfolioTradeAnalytics.csv")
    for r in rows:
        r["entry_time_dt"] = parse_dt(r["entry_time"])
        r["exit_time_dt"] = parse_dt(r["exit_time"])
        r["realized_r"] = float(r["realized_r"])
        r["initial_risk_price"] = float(r["initial_risk_price"])
        r["logical_volume"] = float(r["logical_volume"])
        r["book_name"] = BOOK_NAMES.get(r["book_id"], r["book_id"])
        r["hour"] = r["entry_time_dt"].hour
        r["session"] = session_bucket(r["hour"])
        r["day_of_week"] = r["entry_time_dt"].strftime("%A")
        r["month"] = r["entry_time_dt"].strftime("%Y-%m")
        r["split"] = split_label(r["exit_time_dt"])
        r["holding_time_hours"] = (r["exit_time_dt"] - r["entry_time_dt"]).total_seconds() / 3600.0
    rows.sort(key=lambda r: r["exit_time_dt"])
    return rows


def join_regime_at_entry(trades):
    """SignalJournal EXECUTED rows: cluster_id == logical_position_id.
    regime_snapshot_id on that row is the ENTRY-time regime snapshot (the
    CLOSE-side StrategyBookJournal row re-stamps regime_snapshot_id at exit
    time instead, which is why SignalJournal, not PortfolioTradeAnalytics'
    own regime_snapshot_id column, is used for entry-regime attribution)."""
    sig = read_csv(f"{P4_ROOT}/MSZZ_SignalJournal.csv")
    by_cluster = {}
    for r in sig:
        if r["status"] != "EXECUTED":
            continue
        by_cluster[r["cluster_id"]] = r
    matched = 0
    for t in trades:
        s = by_cluster.get(t["logical_position_id"])
        if s is None:
            t["regime_direction"] = t["regime_strength"] = t["regime_volatility"] = None
            t["regime_alignment"] = t["regime_phase"] = None
            continue
        matched += 1
        t["regime_direction"] = s["regime_direction"]
        t["regime_strength"] = s["regime_strength"]
        t["regime_volatility"] = s["regime_volatility"]
        t["regime_alignment"] = s["regime_alignment"]
        t["regime_phase"] = s["regime_phase"]
    return matched, len(trades)


def join_sizing(trades):
    siz = read_csv(f"{P4_ROOT}/MSZZ_SizingJournal.csv")
    by_pos = {}
    for r in siz:
        if r["sizing_result"] != "OK":
            continue
        if r["logical_position_id"] not in by_pos:
            by_pos[r["logical_position_id"]] = r  # first OK sizing row = original entry sizing
    matched = 0
    for t in trades:
        s = by_pos.get(t["logical_position_id"])
        if s is None:
            t["stop_distance_points"] = None
            t["requested_risk_money"] = None
            continue
        matched += 1
        t["stop_distance_points"] = float(s["stop_distance_points"])
        t["requested_risk_money"] = float(s["requested_risk_money"])
    return matched, len(trades)


def join_cost_proxy(trades):
    """No per-trade spread cost exists in this evidence: execution_cost is
    uniformly 0.0 across all 330 D29_P4 trades (verified before writing
    this script). DealJournal commission+swap is the closest real broker
    cost signal available, joined position_ticket -> broker_position_ticket
    (StrategyBookJournal) -> logical_position_id. Reported as
    cost_to_risk_decile, explicitly NOT the literal spread/risk metric the
    handoff asks for -- see D030_P4_LOSS_MAP.md 'Data limitations'."""
    sbj = read_csv(f"{P4_ROOT}/MSZZ_StrategyBookJournal.csv")
    ticket_to_pos = {}
    for r in sbj:
        if r["action"] == "OPEN":
            ticket_to_pos[(r["book_id"], r["broker_position_ticket"])] = r["logical_position_id"]

    deals = read_csv(f"{P4_ROOT}/MSZZ_DealJournal.csv")
    cost_by_pos = defaultdict(float)
    for d in deals:
        pos = ticket_to_pos.get((d["book_id"], d["position_ticket"]))
        if pos is None:
            continue
        cost_by_pos[pos] += abs(float(d["commission"])) + abs(float(d["swap"]))

    matched = 0
    for t in trades:
        cost = cost_by_pos.get(t["logical_position_id"])
        risk_money = t.get("requested_risk_money")
        if cost is None or not risk_money:
            t["cost_to_risk_ratio"] = None
            continue
        matched += 1
        t["cost_to_risk_ratio"] = cost / risk_money
    return matched, len(trades)


def join_simultaneous_exposure(trades):
    """PortfolioRiskJournal action=OPEN rows carry open_books (count of the
    OTHER book already open) at the moment risk was approved for this
    trade, joined on (book_id, time == entry_time). This is an existing
    frozen journal field, not a new computation."""
    risk = read_csv(f"{P4_ROOT}/MSZZ_PortfolioRiskJournal.csv")
    by_key = {}
    for r in risk:
        if r["action"] != "OPEN":
            continue
        key = (r["book_id"], r["time"])
        by_key.setdefault(key, r)  # first match if duplicates
    matched = 0
    for t in trades:
        key = (t["book_id"], t["entry_time"])
        r = by_key.get(key)
        if r is None:
            t["simultaneous_exposure"] = None
            continue
        matched += 1
        t["simultaneous_exposure"] = "CONCURRENT" if int(r["open_books"]) > 0 else "SOLO"
    return matched, len(trades)


def apply_deciles(trades):
    have_stop = [t for t in trades if t.get("stop_distance_points") is not None]
    for t, d in zip(have_stop, decile_labels(have_stop, "stop_distance_points")):
        t["stop_distance_decile"] = d
    for t in trades:
        t.setdefault("stop_distance_decile", None)

    have_cost = [t for t in trades if t.get("cost_to_risk_ratio") is not None]
    for t, d in zip(have_cost, decile_labels(have_cost, "cost_to_risk_ratio")):
        t["cost_to_risk_decile"] = d
    for t in trades:
        t.setdefault("cost_to_risk_decile", None)

    for t, d in zip(trades, decile_labels(trades, "holding_time_hours")):
        t["holding_time_decile"] = d


def write_trades_enriched(trades):
    cols = [
        "logical_position_id", "book_id", "book_name", "strategy_id", "family_id",
        "direction", "entry_time", "exit_time", "entry_price", "exit_price",
        "logical_volume", "initial_risk_price", "realized_r", "exit_policy", "exit_reason",
        "hour", "session", "day_of_week", "month", "split", "holding_time_hours",
        "holding_time_decile", "stop_distance_points", "stop_distance_decile",
        "cost_to_risk_ratio", "cost_to_risk_decile", "simultaneous_exposure",
        "regime_direction", "regime_strength", "regime_volatility", "regime_alignment",
        "regime_phase",
    ]
    with open(f"{OUT}/trades_enriched.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for t in trades:
            w.writerow({c: t.get(c) for c in cols})


def pf(rs):
    g = sum(r for r in rs if r > 0)
    l = -sum(r for r in rs if r < 0)
    if l <= 0:
        return -1.0 if g > 0 else 0.0
    return g / l


def bucket_stats(rows, dim, key):
    groups = defaultdict(list)
    for r in rows:
        groups[r.get(key)].append(r)
    out = []
    for bucket_val, trs in sorted(groups.items(), key=lambda kv: (kv[0] is None, str(kv[0]))):
        rs = [t["realized_r"] for t in trs]
        gp = sum(r for r in rs if r > 0)
        gl = -sum(r for r in rs if r < 0)
        dev = [t["realized_r"] for t in trs if t["split"] == "development"]
        val = [t["realized_r"] for t in trs if t["split"] == "validation"]
        hold = [t["realized_r"] for t in trs if t["split"] == "holdout"]
        longs = sum(1 for t in trs if t["direction"] == "LONG")
        shorts = sum(1 for t in trs if t["direction"] == "SHORT")
        out.append({
            "dimension": dim,
            "bucket": bucket_val,
            "trade_count": len(trs),
            "gross_profit_r": round(gp, 4),
            "gross_loss_r": round(gl, 4),
            "pf": round(pf(rs), 4),
            "expectancy_r": round(statistics.mean(rs), 4) if rs else 0.0,
            "total_r": round(sum(rs), 4),
            "win_rate": round(sum(1 for r in rs if r > 0) / len(rs), 4) if rs else 0.0,
            "long_count": longs,
            "short_count": shorts,
            "dev_count": len(dev), "dev_expectancy_r": round(statistics.mean(dev), 4) if dev else None,
            "val_count": len(val), "val_expectancy_r": round(statistics.mean(val), 4) if val else None,
            "holdout_count": len(hold), "holdout_expectancy_r": round(statistics.mean(hold), 4) if hold else None,
        })
    return out


def write_bucket_summary(trades):
    dims = [
        ("strategy_book", "book_name"),
        ("direction", "direction"),
        ("hour", "hour"),
        ("session", "session"),
        ("day_of_week", "day_of_week"),
        ("month", "month"),
        ("regime_direction", "regime_direction"),
        ("trend_strength", "regime_strength"),
        ("volatility_state", "regime_volatility"),
        ("alignment_state", "regime_alignment"),
        ("market_phase", "regime_phase"),
        ("stop_distance_decile", "stop_distance_decile"),
        ("cost_to_risk_decile_SUBSTITUTE_FOR_SPREAD_RISK", "cost_to_risk_decile"),
        ("holding_time_decile", "holding_time_decile"),
        ("exit_reason", "exit_reason"),
        ("simultaneous_exposure", "simultaneous_exposure"),
    ]
    all_rows = []
    for dim, key in dims:
        all_rows.extend(bucket_stats(trades, dim, key))
    cols = list(all_rows[0].keys())
    with open(f"{OUT}/bucket_summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(all_rows)
    return all_rows


def write_monthly_summary(trades):
    rows = bucket_stats(trades, "month", "month")
    cols = list(rows[0].keys())
    with open(f"{OUT}/monthly_summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    return rows


def write_concentration(trades):
    rs_sorted_desc = sorted(trades, key=lambda t: -t["realized_r"])
    total_r = sum(t["realized_r"] for t in trades)
    rows = []

    def excl_top(n):
        remaining = [t["realized_r"] for t in rs_sorted_desc[n:]]
        return {
            "cut": f"top-{n}_exclusion",
            "trades_removed": n,
            "remaining_total_r": round(sum(remaining), 4),
            "remaining_pf": round(pf(remaining), 4),
            "still_positive": sum(remaining) > 0,
        }

    for n in (1, 3, 5):
        rows.append(excl_top(n))

    months = defaultdict(list)
    for t in trades:
        months[t["month"]].append(t["realized_r"])
    best_month = max(months, key=lambda m: sum(months[m]))
    remaining = [r for m, rs in months.items() if m != best_month for r in rs]
    rows.append({
        "cut": f"best_month_exclusion({best_month})",
        "trades_removed": len(months[best_month]),
        "remaining_total_r": round(sum(remaining), 4),
        "remaining_pf": round(pf(remaining), 4),
        "still_positive": sum(remaining) > 0,
    })

    def quarter_of(month_str):
        y, m = month_str.split("-")
        q = (int(m) - 1) // 3 + 1
        return f"{y}-Q{q}"

    quarters = defaultdict(list)
    for t in trades:
        quarters[quarter_of(t["month"])].append(t["realized_r"])
    best_q = max(quarters, key=lambda q: sum(quarters[q]))
    remaining = [r for q, rs in quarters.items() if q != best_q for r in rs]
    rows.append({
        "cut": f"best_quarter_exclusion({best_q})",
        "trades_removed": len(quarters[best_q]),
        "remaining_total_r": round(sum(remaining), 4),
        "remaining_pf": round(pf(remaining), 4),
        "still_positive": sum(remaining) > 0,
    })

    rows.insert(0, {
        "cut": "baseline_all_trades", "trades_removed": 0,
        "remaining_total_r": round(total_r, 4), "remaining_pf": round(pf([t["realized_r"] for t in trades]), 4),
        "still_positive": total_r > 0,
    })

    cols = ["cut", "trades_removed", "remaining_total_r", "remaining_pf", "still_positive"]
    with open(f"{OUT}/concentration.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    return rows


def write_regime_coverage(trades):
    """Bar-level census (D028 P4 regime journal) vs trade-level regime-at-
    entry, both restricted to the frozen D029 dev/val/holdout window so the
    denominators cover the same calendar period."""
    bars = read_csv(REGIME_CENSUS_PATH)
    census = defaultdict(int)
    total_bars_in_window = 0
    for b in bars:
        dt = parse_dt(b["time"])
        if split_label(dt) == "outside_frozen_windows":
            continue
        if b["valid"] != "true":
            continue
        total_bars_in_window += 1
        key = (b["direction"], b["trend_strength"], b["volatility_state"], b["alignment_state"], b["market_phase"])
        census[key] += 1

    trade_counts = defaultdict(list)
    for t in trades:
        if t["regime_direction"] is None:
            continue
        key = (t["regime_direction"], t["regime_strength"], t["regime_volatility"], t["regime_alignment"], t["regime_phase"])
        trade_counts[key].append(t["realized_r"])

    all_keys = set(census) | set(trade_counts)
    rows = []
    for key in all_keys:
        bar_count = census.get(key, 0)
        rs = trade_counts.get(key, [])
        rows.append({
            "regime_direction": key[0], "trend_strength": key[1], "volatility_state": key[2],
            "alignment_state": key[3], "market_phase": key[4],
            "bar_count": bar_count,
            "bar_pct_of_window": round(100.0 * bar_count / total_bars_in_window, 4) if total_bars_in_window else 0.0,
            "trade_count": len(rs),
            "expectancy_r": round(statistics.mean(rs), 4) if rs else None,
            "total_r": round(sum(rs), 4) if rs else None,
            "trades_per_1000_bars": round(1000.0 * len(rs) / bar_count, 4) if bar_count else None,
        })
    rows.sort(key=lambda r: -r["bar_count"])
    cols = list(rows[0].keys())
    with open(f"{OUT}/regime_coverage.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    return rows, total_bars_in_window


def write_regime_dimension_coverage(trades):
    """Single-dimension roll-up of the same bar-census-vs-trade comparison
    (market_phase, volatility_state, alignment_state, regime_direction,
    trend_strength each in isolation) -- the 5-way combo table is too
    sparse per-cell to call anything 'uncovered' cleanly; collapsing to
    one dimension at a time is where genuine coverage gaps show up."""
    bars = read_csv(REGIME_CENSUS_PATH)
    dims = {
        "regime_direction": "direction",
        "trend_strength": "trend_strength",
        "volatility_state": "volatility_state",
        "alignment_state": "alignment_state",
        "market_phase": "market_phase",
    }
    bar_totals = {d: 0 for d in dims}
    bar_counts = {d: defaultdict(int) for d in dims}
    total_bars_in_window = 0
    for b in bars:
        dt = parse_dt(b["time"])
        if split_label(dt) == "outside_frozen_windows" or b["valid"] != "true":
            continue
        total_bars_in_window += 1
        for out_name, src_col in dims.items():
            bar_counts[out_name][b[src_col]] += 1
            bar_totals[out_name] += 1

    trade_cols = {
        "regime_direction": "regime_direction", "trend_strength": "regime_strength",
        "volatility_state": "regime_volatility", "alignment_state": "regime_alignment",
        "market_phase": "regime_phase",
    }
    rows = []
    for out_name in dims:
        tcol = trade_cols[out_name]
        trade_rs = defaultdict(list)
        for t in trades:
            if t[tcol] is not None:
                trade_rs[t[tcol]].append(t["realized_r"])
        all_vals = set(bar_counts[out_name]) | set(trade_rs)
        for val in all_vals:
            bc = bar_counts[out_name].get(val, 0)
            rs = trade_rs.get(val, [])
            rows.append({
                "dimension": out_name, "value": val,
                "bar_count": bc,
                "bar_pct": round(100.0 * bc / bar_totals[out_name], 4) if bar_totals[out_name] else 0.0,
                "trade_count": len(rs),
                "trades_per_1000_bars": round(1000.0 * len(rs) / bc, 4) if bc else None,
                "expectancy_r": round(statistics.mean(rs), 4) if rs else None,
                "total_r": round(sum(rs), 4) if rs else None,
            })
    rows.sort(key=lambda r: (r["dimension"], -r["bar_count"]))
    cols = list(rows[0].keys())
    with open(f"{OUT}/regime_dimension_coverage.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    return rows


def write_book_overlap(trades):
    """Same overlap-episode computation D029 Phase4's analyze_portfolios.py
    already uses for FastMedConfluence vs SweepReclaim (episodes, hours
    overlapped, opposing vs same-direction split) -- reused, not
    reinvented, per the handoff's redundancy-analysis intent."""
    fastmed = [t for t in trades if t["book_id"] == "1"]
    sweep = [t for t in trades if t["book_id"] == "2"]
    episodes = 0; hours = 0.0; opposing = 0; same_dir = 0
    for f in fastmed:
        for s in sweep:
            os_, oe_ = max(f["entry_time_dt"], s["entry_time_dt"]), min(f["exit_time_dt"], s["exit_time_dt"])
            if os_ < oe_:
                episodes += 1
                hours += (oe_ - os_).total_seconds() / 3600.0
                if f["direction"] != s["direction"]:
                    opposing += 1
                else:
                    same_dir += 1
    rows = [{
        "fastmed_trades": len(fastmed), "sweep_trades": len(sweep),
        "overlap_episodes": episodes, "overlap_hours_total": round(hours, 2),
        "opposing_direction_episodes": opposing, "same_direction_episodes": same_dir,
    }]
    with open(f"{OUT}/book_overlap.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    return rows[0]


def write_input_hashes():
    paths = [
        f"{P4_ROOT}/MSZZ_PortfolioTradeAnalytics.csv",
        f"{P4_ROOT}/MSZZ_SignalJournal.csv",
        f"{P4_ROOT}/MSZZ_SizingJournal.csv",
        f"{P4_ROOT}/MSZZ_StrategyBookJournal.csv",
        f"{P4_ROOT}/MSZZ_DealJournal.csv",
        f"{P4_ROOT}/MSZZ_PortfolioRiskJournal.csv",
        REGIME_CENSUS_PATH,
    ]
    rows = [{"file": p, "sha256": sha256_of(p)} for p in paths]
    with open(f"{OUT}/input_hashes.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["file", "sha256"])
        w.writeheader()
        w.writerows(rows)
    return rows


def main():
    trades = load_trades()
    assert len(trades) == 330, f"expected 330 certified D29_P4 trades, got {len(trades)}"

    m_regime, n = join_regime_at_entry(trades)
    m_sizing, _ = join_sizing(trades)
    m_cost, _ = join_cost_proxy(trades)
    m_risk, _ = join_simultaneous_exposure(trades)
    apply_deciles(trades)

    write_trades_enriched(trades)
    bucket_rows = write_bucket_summary(trades)
    monthly_rows = write_monthly_summary(trades)
    conc_rows = write_concentration(trades)
    regime_rows, total_bars = write_regime_coverage(trades)
    dim_rows = write_regime_dimension_coverage(trades)
    overlap = write_book_overlap(trades)
    hashes = write_input_hashes()

    print(f"trades: {n}")
    print(f"regime-at-entry matched: {m_regime}/{n}")
    print(f"sizing matched: {m_sizing}/{n}")
    print(f"cost-proxy matched: {m_cost}/{n}")
    print(f"simultaneous-exposure matched: {m_risk}/{n}")
    print(f"bucket_summary rows: {len(bucket_rows)}")
    print(f"monthly rows: {len(monthly_rows)}")
    print(f"regime_coverage rows: {len(regime_rows)} (bars in window: {total_bars})")
    print(f"regime_dimension_coverage rows: {len(dim_rows)}")
    print(f"book_overlap: {overlap}")
    print(f"total_r all trades: {round(sum(t['realized_r'] for t in trades), 4)}")
    print(f"pf all trades: {round(pf([t['realized_r'] for t in trades]), 4)}")
    negative_months = [r for r in monthly_rows if r['total_r'] is not None and r['total_r'] < 0]
    print(f"negative-expectancy months: {len(negative_months)} -> {[r['bucket'] for r in negative_months]}")


if __name__ == "__main__":
    main()
