"""Parse the isolated /portable runtime log for the latest
Test_MSZZ_ScreeningSimulatorV2 run and emit mql5_results.csv
(fixture_id, mql5_result) for every fixture in the shared matrix.

A fixture is PASS unless the latest run printed a `FAIL: [<id>]` line for
it. The MQL5 parity test asserts each fixture's run-status and byte-identical
canonical outcome SHA-256 against the Python reference (expected_outcomes.csv),
so an MQL5 PASS is simultaneously the cross-language parity result.

Usage:
    python3 collect_mql5_results.py <isolated_runtime_log_utf16le>
"""
import csv
import io
import pathlib
import re
import sys

import simulator_fixtures as fx

ROOT = pathlib.Path(__file__).parent
TEST = "Test_MSZZ_ScreeningSimulatorV2"


def _decode(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    try:
        return raw.decode("utf-16-le")
    except UnicodeDecodeError:
        return raw.decode("utf-8", "replace")


def latest_run_lines(text: str) -> list[str]:
    lines = [ln for ln in text.splitlines() if TEST in ln]
    # a run ends with TEST_SUMMARY; take the block ending at the last one
    ends = [i for i, ln in enumerate(lines) if "TEST_SUMMARY" in ln]
    if not ends:
        return []
    end = ends[-1]
    start = ends[-2] + 1 if len(ends) > 1 else 0
    return lines[start:end + 1]


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    text = _decode(pathlib.Path(sys.argv[1]))
    block = latest_run_lines(text)
    if not block:
        print("no Test_MSZZ_ScreeningSimulatorV2 run found", file=sys.stderr)
        return 1
    summary = block[-1]
    failed = set(re.findall(r"FAIL: \[(F\d+)\]", "\n".join(block)))
    rows = [("fixture_id", "mql5_result")]
    for f in fx.FIXTURES:
        rows.append((f.id, "FAIL" if f.id in failed else "PASS"))
    out = io.StringIO()
    w = csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
    for r in rows:
        w.writerow(r)
    (ROOT / "mql5_results.csv").write_bytes(out.getvalue().encode("utf-8"))
    m = re.search(r"TEST_SUMMARY tests=(\d+) failures=(\d+)", summary)
    print("wrote mql5_results.csv from:", summary.strip().split("\t")[-1])
    print("failed fixtures:", sorted(failed) or "none",
          "| summary:", m.group(0) if m else "?")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
