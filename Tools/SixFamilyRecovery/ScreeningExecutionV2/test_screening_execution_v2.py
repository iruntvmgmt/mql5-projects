import csv
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from screening_execution_v2 import (Exit, Reject, canonical, candidate_status,
                                    gross_r, normalize_stop, normalize_target,
                                    resolve_bar, validate)

HERE = pathlib.Path(__file__).parent

class ScreeningExecutionV2Tests(unittest.TestCase):
    def test_canonical_policy(self):
        validate(canonical())

    def test_fixtures(self):
        with (HERE / "cross_language_parity_fixtures.csv").open(newline="") as f:
            for row in csv.DictReader(f):
                direction = int(row["direction"])
                self.assertEqual(normalize_stop(direction, float(row["raw_stop"]), float(row["entry"]), float(row["tick_size"])), float(row["normalized_stop"]), row["fixture"])
                self.assertEqual(normalize_target(direction, float(row["raw_target"]), float(row["entry"]), float(row["tick_size"])), float(row["normalized_target"]), row["fixture"])
                status = candidate_status(row["family_open"] == "true", int(row["entry_time"]), int(row["expiry_time"]))
                self.assertEqual(status.name, row["status"], row["fixture"])
                if row["status"] == "ACCEPT":
                    result = resolve_bar(direction, float(row["normalized_stop"]), float(row["normalized_target"]), float(row["high"]), float(row["low"]))
                    self.assertEqual(result.name, row["exit"], row["fixture"])
                    self.assertAlmostEqual(gross_r(direction, float(row["entry"]), float(row["exit_price"]), float(row["normalized_stop"])), float(row["gross_r"]), places=9)

if __name__ == "__main__":
    unittest.main()
