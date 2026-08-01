#!/usr/bin/env python3
"""Synthetic-log self-tests for MSZZ_MQL5_RESULT_COLLECTOR_V2. Prove it fails
closed on every malformation and only accepts a complete, consistent,
cert-run-bound three-suite certification run."""
from __future__ import annotations

import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import collect_mql5_results as col  # noqa: E402

RUN = "MSZZ_SCREENING_CERT_RUN_V2_deadbeefdeadbeef"


def line(script: str, msg: str, t: str = "10:00:00") -> str:
    return f"XX\t0\t{t}.100\t{script} (XAUUSD,M5)\t{msg}"


def suite_lines(group: str, *, cert_run=RUN, failures=0, fixtures=None, gcount=None,
                markers=None, fixfail=0, harnessfail=0, ids=None,
                drop=0, dup=None, unknown=None, fail_marker=None,
                extra=None, t="10:00:00") -> list[str]:
    script, key, count, all_ids = col.SUITES[group]
    ids = list(all_ids if ids is None else ids)
    out = []
    used = ids[:len(ids) - drop]
    for fid in used:
        res = "FAIL" if fid == fail_marker else "PASS"
        out.append(line(script, f"FIXTURE_RESULT [{fid}] {res}", t))
    if dup:
        out.append(line(script, f"FIXTURE_RESULT [{dup}] PASS", t))
    if unknown:
        out.append(line(script, f"FIXTURE_RESULT [{unknown}] PASS", t))
    for e in (extra or []):
        out.append(line(script, e, t))
    fixtures = count if fixtures is None else fixtures
    gcount = count if gcount is None else gcount
    markers = len(used) + (1 if dup else 0) + (1 if unknown else 0) if markers is None else markers
    counts = {"f": 0, "jb": 0, "or": 0}
    counts[key] = gcount
    summ = (f"TEST_SUMMARY tests=100 failures={failures} fixtures={fixtures} "
            f"f={counts['f']} jb={counts['jb']} or={counts['or']} markers={markers} "
            f"fixture_failures={fixfail} harness_failures={harnessfail} cert_run={cert_run}")
    out.append(line(script, summ, t))
    return out


def all_valid(**over) -> list[str]:
    return (suite_lines("EXECUTION_CORE", **over.get("f", {}))
            + suite_lines("JOURNAL_BINDING", **over.get("jb", {}))
            + suite_lines("ORDERING", **over.get("or", {})))


def write_log(tmp: pathlib.Path, lines: list[str]) -> pathlib.Path:
    p = tmp / "log.log"
    p.write_bytes(("\n".join(lines) + "\n").encode("utf-16-le"))
    return p


class CollectorSelfTests(unittest.TestCase):
    def _tmp(self):
        import tempfile
        return pathlib.Path(tempfile.mkdtemp())

    def _ok(self, lines):
        r, cert, sha, _ = col.collect(write_log(self._tmp(), lines))
        return r, cert

    def _reject(self, lines):
        with self.assertRaises(col.CollectorError):
            col.collect(write_log(self._tmp(), lines))

    def test_valid_complete(self):
        r, cert = self._ok(all_valid())
        self.assertEqual(len(r), 95)
        self.assertEqual(cert, RUN)

    def test_failures_nonzero(self):
        self._reject(all_valid(f={"failures": 1}))

    def test_fixtures_count_wrong(self):
        self._reject(all_valid(jb={"fixtures": 23}))

    def test_group_count_wrong(self):
        self._reject(all_valid(**{"or": {"gcount": 12}}))

    def test_marker_count_wrong(self):
        self._reject(all_valid(f={"markers": 57}))

    def test_missing_f(self):
        self._reject(suite_lines("JOURNAL_BINDING") + suite_lines("ORDERING"))

    def test_missing_jb(self):
        self._reject(suite_lines("EXECUTION_CORE") + suite_lines("ORDERING"))

    def test_missing_or(self):
        self._reject(suite_lines("EXECUTION_CORE") + suite_lines("JOURNAL_BINDING"))

    def test_duplicate_marker(self):
        self._reject(all_valid(jb={"dup": "JB01"}))

    def test_unknown_id(self):
        self._reject(all_valid(f={"unknown": "F99"}))

    def test_explicit_fixture_fail(self):
        self._reject(all_valid(**{"or": {"fail_marker": "OR03"}}))

    def test_generic_fail_line(self):
        self._reject(all_valid(f={"extra": ["FAIL: something"]}))

    def test_harness_failure_line(self):
        self._reject(all_valid(jb={"extra": ["HARNESS_FAILURE [JOURNAL_BINDING] X y"], "harnessfail": 1}))

    def test_no_summary(self):
        # F suite has markers but no TEST_SUMMARY
        lines = [line("Test_MSZZ_ScreeningSimulatorV2", "FIXTURE_RESULT [F01] PASS")]
        lines += suite_lines("JOURNAL_BINDING") + suite_lines("ORDERING")
        self._reject(lines)

    def test_missing_marker(self):
        self._reject(all_valid(jb={"drop": 1}))

    def test_cert_run_mismatch(self):
        self._reject(all_valid(**{"or": {"cert_run": "MSZZ_SCREENING_CERT_RUN_V2_0000000000000000"}}))

    def test_old_invalid_then_latest_valid(self):
        # earlier failing F run, then a later valid one -> collector picks latest
        early = suite_lines("EXECUTION_CORE", failures=1, t="09:00:00")
        r, cert = self._ok(early + all_valid())
        self.assertEqual(len(r), 95)

    def test_old_valid_then_latest_incomplete(self):
        # valid F run, then a newer incomplete F run (markers after last summary)
        good = suite_lines("EXECUTION_CORE", t="09:00:00")
        incomplete = [line("Test_MSZZ_ScreeningSimulatorV2", "FIXTURE_RESULT [F01] PASS", "11:00:00")]
        self._reject(good + incomplete + suite_lines("JOURNAL_BINDING") + suite_lines("ORDERING"))

    def test_atomic_preserved_on_failure(self):
        tmp = self._tmp()
        # main-style flow: failing collect must not write
        sentinel = col.HERE / "mql5_results.csv"
        before = sentinel.read_bytes() if sentinel.exists() else None
        with self.assertRaises(col.CollectorError):
            col.collect(write_log(tmp, all_valid(f={"failures": 1})))
        after = sentinel.read_bytes() if sentinel.exists() else None
        self.assertEqual(before, after)

    def test_atomic_replace_on_success(self):
        r, cert, sha, _ = col.collect(write_log(self._tmp(), all_valid()))
        p = col.write_atomic(r, cert, sha)
        self.assertTrue(p.exists())
        self.assertFalse((col.HERE / "mql5_results.csv.tmp").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
