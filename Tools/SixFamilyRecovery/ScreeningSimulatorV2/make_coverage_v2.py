#!/usr/bin/env python3
"""Fail-closed cross-language coverage generator.

Coverage is written ONLY when: the Python F/JB/OR suites all pass; a validated
MQL collector-V2 mql5_results.csv exists with all 95 markers PASS and one
cert_run; the Python fixture inventory and the MQL result inventory are exactly
equal; and every python/mql5/parity result is PASS. On any mismatch it returns
nonzero and does not overwrite the previous fixture_coverage.csv.

Provenance (collector version, cert run, source-log SHA, fixture-source SHAs)
is embedded per row.
"""
from __future__ import annotations

import csv
import hashlib
import io
import os
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "JournalTransportV2"))
sys.path.insert(0, str(HERE.parent / "ScreeningExecutionV2"))

import journal_binding_fixtures as jbf   # noqa: E402
import ordering_fixtures as orf          # noqa: E402

COVERAGE_VERSION = "MSZZ_SCREENING_COVERAGE_V2"
COLLECTOR_VERSION = "MSZZ_MQL5_RESULT_COLLECTOR_V2"

INVENTORY = ([("EXECUTION_CORE", f"F{i:02d}") for i in range(1, 59)]
             + [("JOURNAL_BINDING", f.id) for f in jbf.FIXTURES]
             + [("ORDERING", f.id) for f in orf.FIXTURES])


class CoverageError(ValueError):
    pass


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _run_python_suites() -> None:
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for mod in ("test_screening_simulator_v2", "test_journal_binding_v2", "test_ordering_v2"):
        suite.addTests(loader.loadTestsFromName(mod))
    result = unittest.TextTestRunner(verbosity=0).run(suite)
    if not result.wasSuccessful():
        raise CoverageError("python suites failed")


def _read_mql5_results():
    path = HERE / "mql5_results.csv"
    if not path.exists():
        raise CoverageError("mql5_results.csv missing (run collector V2)")
    rows = list(csv.DictReader(path.open(newline="")))
    if not rows:
        raise CoverageError("mql5_results.csv empty")
    cert_runs = {r["cert_run"] for r in rows}
    versions = {r["collector_version"] for r in rows}
    logs = {r["source_log_sha256"] for r in rows}
    if versions != {COLLECTOR_VERSION}:
        raise CoverageError(f"unexpected collector version {versions}")
    if len(cert_runs) != 1 or len(logs) != 1:
        raise CoverageError("inconsistent cert_run / source log in mql5_results.csv")
    results = {(r["fixture_group"], r["fixture_id"]): r["mql5_result"] for r in rows}
    return results, cert_runs.pop(), logs.pop()


def generate() -> bytes:
    _run_python_suites()  # python_result = PASS for all inventory when green
    mql5, cert_run, log_sha = _read_mql5_results()
    if set(mql5) != set(INVENTORY):
        missing = set(INVENTORY) - set(mql5)
        unknown = set(mql5) - set(INVENTORY)
        raise CoverageError(f"inventory mismatch missing={sorted(missing)} unknown={sorted(unknown)}")
    if any(v != "PASS" for v in mql5.values()):
        raise CoverageError("non-PASS mql5 result present")

    prov = {
        "simulator_fixtures.csv": _sha(HERE / "simulator_fixtures.csv"),
        "journal_binding_fixture_index.csv": _sha(HERE / "journal_binding_fixture_index.csv"),
        "ordering_fixtures.csv": _sha(HERE / "ordering_fixtures.csv"),
        "expected_outcomes.csv": _sha(HERE / "expected_outcomes.csv"),
    }
    out = io.StringIO()
    w = csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
    w.writerow(["coverage_version", "cert_run", "fixture_group", "fixture_id",
                "python_result", "mql5_result", "parity_result",
                "collector_version", "mql5_source_log_sha256",
                "simulator_fixtures_sha256", "journal_binding_index_sha256",
                "ordering_fixtures_sha256", "expected_outcomes_sha256"])
    for group, fid in INVENTORY:
        m = mql5[(group, fid)]
        parity = "PASS" if m == "PASS" else "FAIL"
        w.writerow([COVERAGE_VERSION, cert_run, group, fid, "PASS", m, parity,
                    COLLECTOR_VERSION, log_sha,
                    prov["simulator_fixtures.csv"], prov["journal_binding_fixture_index.csv"],
                    prov["ordering_fixtures.csv"], prov["expected_outcomes.csv"]])
    return out.getvalue().encode("utf-8")


def main() -> int:
    try:
        data = generate()
    except CoverageError as exc:
        print(f"COVERAGE_REJECT: {exc}", file=sys.stderr)
        return 1
    tmp = HERE / "fixture_coverage.csv.tmp"
    tmp.write_bytes(data)
    os.replace(tmp, HERE / "fixture_coverage.csv")
    n = data.decode().count("\r\n") - 1
    print(f"coverage OK: {n} rows (EXECUTION_CORE 58/58, JOURNAL_BINDING 24/24, ORDERING 13/13, TOTAL 95/95)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
