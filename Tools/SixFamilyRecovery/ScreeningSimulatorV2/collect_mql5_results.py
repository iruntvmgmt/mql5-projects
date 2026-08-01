#!/usr/bin/env python3
"""MSZZ_MQL5_RESULT_COLLECTOR_V2

Aggregate the three isolated-runtime certification suites (F / JB / OR) from a
MetaTrader daily log into a validated mql5_results.csv. Fail-closed:

  * select each suite's LATEST run block (bounded by its own TEST_SUMMARY);
  * reject a suite whose latest run is incomplete (markers after its summary);
  * require the exact strict summary grammar with failures=0,
    fixture_failures=0, harness_failures=0 and the exact group/marker counts;
  * parse only explicit FIXTURE_RESULT [ID] PASS|FAIL markers, requiring the
    exact ID set per suite with no duplicate/missing/unknown/malformed marker
    and no PASS/FAIL conflict;
  * reject any fresh generic "FAIL:" or "HARNESS_FAILURE" line in a block;
  * require ALL THREE suites to carry the same cert_run id;
  * write output atomically (tmp + os.replace); leave the previous file
    untouched on any failure.

Usage: collect_mql5_results.py <daily_log_utf16le>
Exit 0 only when all three suites validate and agree.
"""
from __future__ import annotations

import hashlib
import io
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import journal_binding_fixtures as jbf   # noqa: E402
import ordering_fixtures as orf          # noqa: E402

COLLECTOR_VERSION = "MSZZ_MQL5_RESULT_COLLECTOR_V2"

F_IDS = [f"F{i:02d}" for i in range(1, 59)]
JB_IDS = [f.id for f in jbf.FIXTURES]
OR_IDS = [f.id for f in orf.FIXTURES]

SUITES = {
    "EXECUTION_CORE": ("Test_MSZZ_ScreeningSimulatorV2", "f", 58, F_IDS),
    "JOURNAL_BINDING": ("Test_MSZZ_ScreeningJournalBindingV2", "jb", 24, JB_IDS),
    "ORDERING": ("Test_MSZZ_ScreeningOrderingV2", "or", 13, OR_IDS),
}

SUMMARY_RE = re.compile(
    r"TEST_SUMMARY tests=(\d+) failures=(\d+) fixtures=(\d+) f=(\d+) jb=(\d+) or=(\d+) "
    r"markers=(\d+) fixture_failures=(\d+) harness_failures=(\d+) cert_run=(\S+)")
MARKER_RE = re.compile(r"FIXTURE_RESULT \[([A-Za-z0-9]+)\] (PASS|FAIL)")
LINE_RE = re.compile(r"\t(\d\d:\d\d:\d\d)\.\d+\t([A-Za-z0-9_]+) \([^)]*\)\t(.*)")


class CollectorError(ValueError):
    pass


def _script_lines(text: str, script: str):
    out = []
    for ln in text.splitlines():
        m = LINE_RE.search(ln)
        if m and m.group(2) == script:
            out.append((m.group(1), m.group(3)))
    return out


def _latest_block(lines, script: str):
    """(summary_msg, marker_lines) for the latest completed run of a script."""
    summary_idx = [i for i, (_, msg) in enumerate(lines) if "TEST_SUMMARY" in msg]
    if not summary_idx:
        raise CollectorError(f"{script}: no TEST_SUMMARY (suite missing or incomplete)")
    last = summary_idx[-1]
    # markers appearing AFTER the last summary => a newer incomplete run
    for _, msg in lines[last + 1:]:
        if "FIXTURE_RESULT" in msg or "TEST_SUMMARY" in msg:
            raise CollectorError(f"{script}: latest run incomplete (content after last summary)")
    start = (summary_idx[-2] + 1) if len(summary_idx) > 1 else 0
    return lines[last][1], lines[start:last + 1]


def _validate_suite(group: str, block, summary_msg: str):
    script, key, count, ids = SUITES[group]
    m = SUMMARY_RE.search(summary_msg)
    if not m:
        raise CollectorError(f"{group}: malformed summary")
    (tests, failures, fixtures, f, jb, orc, markers, fixfail, harnessfail, cert_run) = m.groups()
    counts = {"f": int(f), "jb": int(jb), "or": int(orc)}
    if int(failures) != 0:
        raise CollectorError(f"{group}: failures={failures}")
    if int(fixfail) != 0:
        raise CollectorError(f"{group}: fixture_failures={fixfail}")
    if int(harnessfail) != 0:
        raise CollectorError(f"{group}: harness_failures={harnessfail}")
    if int(fixtures) != count or counts[key] != count or int(markers) != count:
        raise CollectorError(f"{group}: count mismatch fixtures={fixtures} {key}={counts[key]} markers={markers}")
    # no fresh generic failure / harness lines anywhere in the block
    seen: dict[str, str] = {}
    for _, msg in block:
        if msg.startswith("FAIL:") or "HARNESS_FAILURE" in msg or "FIXTURE_FAILURE" in msg:
            raise CollectorError(f"{group}: fresh failure line: {msg[:60]}")
        mm = MARKER_RE.search(msg)
        if mm:
            fid, res = mm.group(1), mm.group(2)
            if fid in seen:
                raise CollectorError(f"{group}: duplicate marker {fid}")
            seen[fid] = res
    if set(seen) != set(ids):
        missing = set(ids) - set(seen)
        unknown = set(seen) - set(ids)
        raise CollectorError(f"{group}: id set mismatch missing={sorted(missing)} unknown={sorted(unknown)}")
    if any(v != "PASS" for v in seen.values()):
        raise CollectorError(f"{group}: non-PASS marker present")
    return cert_run, int(tests), int(failures), [(fid, ids) for fid in ids]


def collect(log_path: pathlib.Path):
    raw = log_path.read_bytes()
    log_sha = hashlib.sha256(raw).hexdigest()
    text = raw.decode("utf-16-le", "replace")
    results = []
    cert_runs = set()
    per_suite_summary = {}
    for group, (script, key, count, ids) in SUITES.items():
        lines = _script_lines(text, script)
        summary_msg, block = _latest_block(lines, script)
        cert_run, tests, failures, _ = _validate_suite(group, block, summary_msg)
        cert_runs.add(cert_run)
        per_suite_summary[group] = (tests, failures, cert_run)
        for fid in ids:
            results.append((group, fid, "PASS"))
    if len(cert_runs) != 1:
        raise CollectorError(f"cert_run mismatch across suites: {sorted(cert_runs)}")
    return results, cert_runs.pop(), log_sha, per_suite_summary


def write_atomic(results, cert_run, log_sha):
    out = io.StringIO()
    import csv
    w = csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
    w.writerow(["collector_version", "cert_run", "fixture_group", "fixture_id",
                "mql5_result", "source_log_sha256"])
    for group, fid, res in results:
        w.writerow([COLLECTOR_VERSION, cert_run, group, fid, res, log_sha])
    data = out.getvalue().encode("utf-8")
    final = HERE / "mql5_results.csv"
    tmp = HERE / "mql5_results.csv.tmp"
    tmp.write_bytes(data)
    os.replace(tmp, final)
    return final


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    try:
        results, cert_run, log_sha, summaries = collect(pathlib.Path(sys.argv[1]))
    except CollectorError as exc:
        print(f"COLLECTOR_REJECT: {exc}", file=sys.stderr)
        return 1
    write_atomic(results, cert_run, log_sha)
    print(f"collector OK: 95 markers, cert_run={cert_run}")
    for group, (tests, failures, cr) in summaries.items():
        print(f"  {group:16} tests={tests} failures={failures}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
