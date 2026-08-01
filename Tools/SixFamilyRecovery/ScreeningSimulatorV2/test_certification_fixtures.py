#!/usr/bin/env python3
"""Generator self-tests: prove the certification fixture artifacts are
byte-reproducible and canonical, and that the JB index / OR inventory / cert
run id are internally consistent."""
from __future__ import annotations

import csv
import io
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "JournalTransportV2"))
sys.path.insert(0, str(HERE.parent / "ScreeningExecutionV2"))

import journal_binding_fixtures as jbf
import make_certification_fixtures as mk
import ordering_fixtures as orf


def _records(data: bytes):
    text = data.decode("utf-8")
    return list(csv.reader(io.StringIO(text, newline="")))


class GeneratorSelfTests(unittest.TestCase):
    def setUp(self):
        self.a = mk.generate()

    def test_byte_reproducible(self):
        self.assertEqual(self.a, mk.generate())

    def test_canonical_properties(self):
        for name, data in self.a.items():
            if not (name.endswith(".csv")):
                continue
            self.assertNotIn(b"\xef\xbb\xbf", data[:3], f"{name} has BOM")
            self.assertTrue(data.endswith(b"\r\n"), f"{name} missing final CRLF")
            self.assertNotIn(b"\r\r", data, f"{name} bad CRLF")
            # no bare LF (every LF preceded by CR)
            for i, ch in enumerate(data):
                if ch == 0x0A:
                    self.assertEqual(data[i - 1], 0x0D, f"{name} bare LF at {i}")
            self.assertNotIn(b"\r\n\r\n", data.rstrip(b"\r\n") + b"\r\n", f"{name} trailing empty record")

    def test_index_inventory(self):
        rows = _records(self.a["journal_binding_fixture_index.csv"])
        self.assertEqual(rows[0], [mk.BINDING_INDEX_VERSION])
        header = rows[1]
        self.assertEqual(header[0], "fixture_id")
        data = rows[2:]
        ids = [r[0] for r in data]
        self.assertEqual(len(ids), 24)
        self.assertEqual(len(set(ids)), 24)
        self.assertEqual(set(ids), {f.id for f in jbf.FIXTURES})
        # frozen filename formula holds for all 24
        fn = {r[0]: r[2] for r in data}
        for i in ids:
            self.assertEqual(fn[i], f"cert_jb_{i}_journal.csv")
            self.assertIn(fn[i], self.a, f"journal file {fn[i]} not emitted")
        # tamper stages restricted to the known set
        stages = {r[4] for r in data}
        self.assertTrue(stages <= {"NONE", "PRE_TRANSPORT_BYTES", "POST_BUNDLE_MANIFEST",
                                   "POST_BUNDLE_CANDIDATE", "POST_BUNDLE_IDENTITY"}, stages)

    def test_ordering_inventory(self):
        rows = _records(self.a["ordering_fixtures.csv"])
        self.assertEqual(rows[0], [mk.ORDERING_VERSION])
        ids = {r[0] for r in rows[2:]}
        self.assertEqual(ids, {f.id for f in orf.FIXTURES})
        self.assertEqual(len(ids), 13)

    def test_cert_run_id_stable(self):
        rid = self.a["cert_run_id.txt"].decode().strip()
        self.assertTrue(rid.startswith(mk.CERT_RUN_PREFIX))
        self.assertEqual(rid, mk.generate()["cert_run_id.txt"].decode().strip())


if __name__ == "__main__":
    unittest.main(verbosity=2)
