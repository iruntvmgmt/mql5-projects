#!/usr/bin/env python3
"""Finalize machine-readable D033 methodology evidence and hashes."""
import csv
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "Tools" / "D033" / "Methodology"
REGRESSION = Path("/private/tmp/d033_methodology_regression.tsv")


def read(path, delimiter=","):
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def write(name, fields, rows):
    with (OUT / name).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fields, extrasaction="ignore",
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


with REGRESSION.open(encoding="utf-8-sig") as handle:
    lines = [line.rstrip("\r\n").replace("\\t", "\t") for line in handle]
regression = list(csv.DictReader(lines, delimiter="\t"))
assert len(regression) == 32
assert all(row["result"] == "PASS" for row in regression)
assert all(int(row["fresh"]) > 0 for row in regression)
assert all(row["shutdown_timeout"] == "false" for row in regression)
write("test_summary.csv",
      ["suite", "fresh_lines", "shutdown_timeout", "result", "evidence"], [
    {"suite": row["suite"].removeprefix("regress_"),
     "fresh_lines": row["fresh"],
     "shutdown_timeout": row["shutdown_timeout"],
     "result": row["result"], "evidence": row["evidence"]}
    for row in regression
])

write("compile_summary.csv",
      ["source", "log_timestamp", "errors", "warnings", "fresh_log",
       "result"], [
    {"source": "Tests/MultiSpeedZigZag/Test_MSZZ_SessionSweepReversal.mq5",
     "log_timestamp": "2026.07.30 08:12:26.446", "errors": 0,
     "warnings": 0, "fresh_log": "true", "result": "PASS"},
    {"source": "Experts/MultiSpeedZigZagEA.mq5",
     "log_timestamp": "2026.07.30 08:11:10.823", "errors": 0,
     "warnings": 0, "fresh_log": "true", "result": "PASS"},
])

canonical_hash = (
    "9ebf2f41dae137199634521ee7b996e0ef6d8e7996a5c82806d554ef7605eb5f"
)
actual_hash = hashlib.sha256(
    Path("/private/tmp/d033_methodology_p4.csv").read_bytes()
).hexdigest()
assert actual_hash == canonical_hash
write("p4_parity_hashes.csv",
      ["artifact", "reference_sha256", "audit_sha256", "identical",
       "trades", "total_r", "pf"], [{
    "artifact": "MSZZ_PortfolioTradeAnalytics.csv",
    "reference_sha256": canonical_hash, "audit_sha256": actual_hash,
    "identical": "true", "trades": 330, "total_r": "47.6083",
    "pf": "1.2472",
}])

old = read(ROOT / "Tools" / "D033" / "ssr_standalone_headline.csv")[0]
corrected = read(ROOT / "Tools" / "D033" / "Remediation" /
                 "corrected_standalone_headline.csv")[0]
parity = read(OUT / "parity_standalone_headline.csv")[0]
write("run_comparison.csv",
      ["run", "execution_policy", "candidates", "trades", "pf",
       "expectancy_r", "total_r", "opposite_exits"], [
    {"run": "D032 synthetic", "execution_policy": "stop_target_only",
     "candidates": 2650, "trades": 822, "pf": "1.079",
     "expectancy_r": "0.051", "total_r": "", "opposite_exits": 0},
    {"run": "old D033", "execution_policy": "opposite_close_and_reverse",
     "candidates": old["production_candidates"], "trades": old["trade_count"],
     "pf": old["profit_factor_r"], "expectancy_r": old["expectancy_r"],
     "total_r": old["total_r"], "opposite_exits": 8},
    {"run": "corrected D033 467155e",
     "execution_policy": "opposite_close_and_reverse",
     "candidates": corrected["production_candidates"],
     "trades": corrected["broker_trades"],
     "pf": corrected["profit_factor_r"],
     "expectancy_r": corrected["expectancy_r"],
     "total_r": corrected["total_r"], "opposite_exits": 30},
    {"run": "controlled methodology parity",
     "execution_policy": "stop_target_only",
     "candidates": parity["production_candidates"],
     "trades": parity["broker_trades"], "pf": parity["profit_factor_r"],
     "expectancy_r": parity["expectancy_r"], "total_r": parity["total_r"],
     "opposite_exits": parity["opposite_signal_exits"]},
])

classifications = [
    {
        "classification": "SSR_VALID_REJECTION",
        "applies": "true",
        "reason": (
            "controlled stop/target-only broker run fails PF, holdout, "
            "and best-quarter-exclusion promotion gates"
        ),
    },
    {
        "classification": "D032_D033_METHODOLOGY_MISMATCH",
        "applies": "true",
        "reason": (
            "D032 rejects opposite signals while open; old and 467155e "
            "D033 close and immediately reverse"
        ),
    },
    {
        "classification": "D031_D032_EVENT_SEMANTICS_DEFECT",
        "applies": "true",
        "reason": (
            "1825 of 2650 emitted candidates are same-trigger-bar re-arms"
        ),
    },
]
write("final_classifications.csv",
      ["classification", "applies", "reason"], classifications)

(OUT / "methodology_verdict.md").write_text(
    "# D033 post-remediation methodology verdict\n\n"
    "All three bounded classifications apply:\n\n"
    "- **SSR_VALID_REJECTION** — the controlled stop/target-only broker "
    "run fails PF, holdout, and best-quarter-exclusion gates.\n"
    "- **D032_D033_METHODOLOGY_MISMATCH** — D032 never modeled the 30 "
    "opposite closes and immediate reversals present at `467155e`.\n"
    "- **D031_D032_EVENT_SEMANTICS_DEFECT** — 1,825/2,650 emitted "
    "candidates are same-trigger-bar re-arms, so economic uniqueness is "
    "not established.\n\n"
    "Canonical validity/target inputs now fail closed, regression is "
    "32/32, P4 is byte-identical, and parity accounting is clean. "
    "**D034 remains blocked.**\n",
    encoding="utf-8",
)

hashes = []
for path in sorted(OUT.iterdir()):
    if path.is_file() and path.name != "output_hashes.csv":
        hashes.append({
            "file": path.name,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })
write("output_hashes.csv", ["file", "sha256"], hashes)
print({"regression": len(regression), "p4_hash": actual_hash,
       "classifications": [row["classification"] for row in classifications]})
