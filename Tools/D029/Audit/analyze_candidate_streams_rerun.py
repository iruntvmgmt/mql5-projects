#!/usr/bin/env python3
"""D029 Audit Finding A, RERUN VERIFICATION: re-proves ordered candidate-
stream identity on the patched-binary reruns in D029_Audit_Results, using
D29_SR0/SR3_PCT/SR4_PCT (verified byte-identical apart from
InpSweepExitPolicy/InpMagic/Report -- see D029_AUDIT_REMEDIATION.md).
This does not replace analyze_candidate_streams.py's original pre-rerun
result (kept as-is, see candidate_stream_*.csv) -- it is the equivalent
check on the final evidence the certification is actually based on.
Writes candidate_stream_hashes_rerun.csv, candidate_stream_diff_rerun.csv,
candidate_stream_summary_rerun.csv.
"""
import csv, hashlib, sys

ROOT = "/Users/matt/MT5-MSZZ-TEST/D029_Audit_Results"
VARIANTS = ["D29_SR0", "SR3_PCT", "SR4_PCT"]
OUT = "/Users/matt/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Tools/D029/Audit"

PRICE_TOL = 1e-8
SCORE_TOL = 1e-10

FIELDS = ["time","strategy_id","setup","direction","score","entry","stop",
          "target","origin_id","event_id","strategy_family"]

def load_raw_candidates(variant):
    path = f"{ROOT}/{variant}/MSZZ_SignalJournal.csv"
    rows = []
    with open(path, newline='') as f:
        reader = csv.DictReader(f, delimiter=';')
        for r in reader:
            if r['status'] == 'RAW_CANDIDATE':
                rows.append(r)
    return rows

def canonical_row(r):
    parts = []
    for f in FIELDS:
        v = r.get(f, "")
        if f in ("score", "entry", "stop", "target"):
            try:
                v = f"{float(v):.10f}"
            except (ValueError, TypeError):
                v = str(v)
        parts.append(str(v))
    return "\x1f".join(parts)

def row_hash(rows):
    h = hashlib.sha256()
    for r in rows:
        h.update(canonical_row(r).encode('utf-8'))
        h.update(b"\x1e")
    return h.hexdigest()

def numeric_close(a, b, tol):
    try:
        return abs(float(a) - float(b)) <= tol
    except (ValueError, TypeError):
        return a == b

def compare(base_rows, other_rows, base_name, other_name):
    n = min(len(base_rows), len(other_rows))
    first_diff = None
    for i in range(n):
        br, orow = base_rows[i], other_rows[i]
        for f in FIELDS:
            bv, ov = br.get(f, ""), orow.get(f, "")
            if f == "score":
                ok = numeric_close(bv, ov, SCORE_TOL)
            elif f in ("entry", "stop", "target"):
                ok = numeric_close(bv, ov, PRICE_TOL)
            else:
                ok = (bv == ov)
            if not ok:
                first_diff = dict(index=i, field=f, base_value=bv, other_value=ov,
                                   base_time=br.get('time'), other_time=orow.get('time'))
                break
        if first_diff:
            break
    count_mismatch = (len(base_rows) != len(other_rows))
    return dict(base=base_name, other=other_name,
                base_count=len(base_rows), other_count=len(other_rows),
                count_mismatch=count_mismatch,
                identical=(first_diff is None and not count_mismatch),
                first_diff=first_diff)

def main():
    data = {v: load_raw_candidates(v) for v in VARIANTS}
    hashes = {v: row_hash(data[v]) for v in VARIANTS}

    with open(f"{OUT}/candidate_stream_hashes_rerun.csv", "w", newline='') as f:
        w = csv.writer(f)
        w.writerow(["variant", "raw_candidate_count", "canonical_sha256"])
        for v in VARIANTS:
            w.writerow([v, len(data[v]), hashes[v]])

    comparisons = [
        compare(data["D29_SR0"], data["SR3_PCT"], "D29_SR0", "SR3_PCT"),
        compare(data["D29_SR0"], data["SR4_PCT"], "D29_SR0", "SR4_PCT"),
        compare(data["SR3_PCT"], data["SR4_PCT"], "SR3_PCT", "SR4_PCT"),
    ]

    with open(f"{OUT}/candidate_stream_diff_rerun.csv", "w", newline='') as f:
        w = csv.writer(f)
        w.writerow(["base","other","base_count","other_count","count_mismatch",
                    "identical","first_diff_index","first_diff_field",
                    "first_diff_base_value","first_diff_other_value",
                    "first_diff_base_time","first_diff_other_time"])
        for c in comparisons:
            fd = c["first_diff"] or {}
            w.writerow([c["base"], c["other"], c["base_count"], c["other_count"],
                        c["count_mismatch"], c["identical"],
                        fd.get("index",""), fd.get("field",""),
                        fd.get("base_value",""), fd.get("other_value",""),
                        fd.get("base_time",""), fd.get("other_time","")])

    all_identical = all(c["identical"] for c in comparisons)
    all_hashes_equal = len(set(hashes.values())) == 1

    with open(f"{OUT}/candidate_stream_summary_rerun.csv", "w", newline='') as f:
        w = csv.writer(f)
        w.writerow(["check","result"])
        w.writerow(["fields_compared", "|".join(FIELDS)])
        w.writerow(["price_tolerance", PRICE_TOL])
        w.writerow(["score_tolerance", SCORE_TOL])
        w.writerow(["all_pairwise_streams_identical", all_identical])
        w.writerow(["all_canonical_hashes_equal", all_hashes_equal])
        for v in VARIANTS:
            w.writerow([f"{v}_sha256", hashes[v]])

    print(f"all_identical={all_identical} all_hashes_equal={all_hashes_equal}")
    for c in comparisons:
        print(c["base"], "vs", c["other"], "-> identical=", c["identical"], "counts:", c["base_count"], c["other_count"])
        if c["first_diff"]:
            print("  first_diff:", c["first_diff"])

    return 0 if (all_identical and all_hashes_equal) else 1

if __name__ == "__main__":
    sys.exit(main())
