#!/usr/bin/env python3
"""
QuantBeast deployment watchdog.

Read-only, alert-only. Polls (or single-shot checks, --once) the active
DeploymentLease.cfg and the terminal's own Journal/Experts log for signs of
drift or trouble: lease expiry, unexpected EA detach, emergency/kill-switch
latching, and broker-error/disconnect lines.

Deliberately does NOT parse MT5's binary Bases/<server>/trades/<login>/*.dat
files -- that is an undocumented, proprietary format and hand-parsing it
risks silently misreading real position state, which is worse than not
checking at all. Position/order-relevant signals here come from the same
human-readable Experts-log lines the EA itself prints (QBLogInfo/QBLogError),
which is exactly what Tools/quantbeast_deploy.py's own `verify` command
already relies on.

Never restarts, closes, or cancels anything -- matches the project's rule
that broker positions/orders are external state, and the user's own
instruction to never blindly restart with an unknown or unprotected
position. It only prints/logs.
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path
from typing import Dict, List

sys.path.insert(0, str(Path(__file__).resolve().parent))
from quantbeast_deploy import (  # noqa: E402
    DEFAULT_COMMON_FILES,
    DEFAULT_MT5_ROOT,
    LEASE_FILE_RELPATH,
    _decode_log,
    parse_lease_file,
)

ALERT_PATTERNS = [
    re.compile(r"QuantBeast\[ERROR\]"),
    re.compile(r"KILL-SWITCH STATE RESTORED"),
    re.compile(r"EMERGENCY"),
    re.compile(r"expert QuantBeastEA.*removed"),
    re.compile(r"connection to .* lost"),
    re.compile(r"Deployment lease gate blocked"),
]

# Self-tests deliberately construct synthetic failure/emergency/kill-switch
# scenarios (e.g. TEST 29 "Challenge safety flatten" logs a real
# "EMERGENCY: Equity floor breached" line via the shared QBLogError path,
# purely as part of exercising CKillSwitch.Emergency() against a throwaway
# local instance) -- these are indistinguishable from a genuine runtime
# alert by text alone. Confirmed empirically 2026-07-24: on a real live
# attach, self-test PASS/FAIL/warning noise sits entirely between the
# "Initializing" banner and "Self-tests complete:", so that whole span is
# excluded from alerting rather than matched line-by-line.
_INIT_BANNER = re.compile(r"Initializing ══")
_SELF_TEST_DONE = re.compile(r"Self-tests complete:")


def latest_log_paths(mt5_root: Path) -> List[Path]:
    """Two independent streams: the terminal-root Logs/ (Journal-level
    lifecycle events -- 'expert ... loaded/removed', connection status) and
    MQL5/Logs/ (the EA's own Print()/QBLogInfo output -- errors, emergency,
    lease gate). Confirmed empirically 2026-07-24 that these are genuinely
    different files, not two views of the same stream."""
    paths = []
    for logs_dir in (mt5_root / "Logs", mt5_root / "MQL5" / "Logs"):
        if not logs_dir.exists():
            continue
        candidates = sorted(logs_dir.glob("2*.log"), reverse=True)
        if candidates:
            paths.append(candidates[0])
    return paths


def check_lease() -> List[str]:
    lease_path = DEFAULT_COMMON_FILES / LEASE_FILE_RELPATH
    if not lease_path.exists():
        return []  # no lease is not itself an alert -- nothing should be live-armed
    lease = parse_lease_file(lease_path)
    expiry = int(lease.get("expiry", "0") or 0)
    if 0 < expiry < time.time():
        return [f"Deployment lease for {lease.get('deployment_id', '?')} expired at "
                f"{time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(expiry))} but the file "
                "is still present -- if an instance is still attached under it, that instance "
                "will fail closed on its next OnInit, not immediately."]
    return []


def check_log_tail(log_path: Path, last_size: int) -> tuple[List[str], int]:
    size = log_path.stat().st_size
    if size <= last_size:
        return [], size
    text = _decode_log(log_path)
    # Re-decoding the whole file each poll is wasteful for a long-running
    # watchdog but simple and correct; the alternative (byte-offset seeking
    # into a UTF-16 file) risks splitting a multi-byte character. Fine for
    # the polling cadence this tool is meant to run at (minutes, not ticks).
    alerts = []
    in_self_test = False
    # 1000 lines comfortably covers one full self-test burst (~110 lines
    # observed for 104 tests) with headroom; if a poll interval is long
    # enough to accumulate more than that in normal runtime activity plus a
    # burst, a self-test's opening banner could scroll out of this window
    # while its closing banner is still in it, which would leave that
    # burst's noise unsuppressed for one poll. Known, accepted edge case --
    # not worth stateful cross-poll tracking for an alert-only tool.
    for line in text.splitlines()[-1000:]:
        if _INIT_BANNER.search(line):
            in_self_test = True
            continue
        if _SELF_TEST_DONE.search(line):
            in_self_test = False
            continue
        if in_self_test:
            continue
        for pattern in ALERT_PATTERNS:
            if pattern.search(line):
                alerts.append(line.strip())
                break
    return alerts, size


def run_once(mt5_root: Path, last_sizes: Dict[Path, int]) -> Dict[Path, int]:
    alerts = check_lease()
    new_sizes: Dict[Path, int] = {}
    for log_path in latest_log_paths(mt5_root):
        log_alerts, new_size = check_log_tail(log_path, last_sizes.get(log_path, 0))
        alerts.extend(log_alerts)
        new_sizes[log_path] = new_size
    if alerts:
        print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {len(alerts)} alert(s):")
        for a in alerts:
            print(f"  ! {a}")
    return new_sizes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mt5-root", type=Path, default=DEFAULT_MT5_ROOT)
    ap.add_argument("--once", action="store_true", help="Check once and exit instead of polling")
    ap.add_argument("--interval", type=int, default=300, help="Poll interval in seconds (default 300)")
    args = ap.parse_args()

    if args.once:
        # A single check should inspect whatever's currently in each log's
        # tail, not "only lines written after this instant" -- start from an
        # empty size map so check_log_tail treats every current file as new
        # (it already caps the scan to the last 500 lines).
        run_once(args.mt5_root, {})
        return 0

    # Continuous polling starts from "now" -- only alert on genuinely new
    # activity, not the entire day's history on the first tick.
    last_sizes = {p: p.stat().st_size for p in latest_log_paths(args.mt5_root)}

    print(f"Watching (interval={args.interval}s, Ctrl-C to stop)...")
    try:
        while True:
            last_sizes = run_once(args.mt5_root, last_sizes)
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("Stopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
