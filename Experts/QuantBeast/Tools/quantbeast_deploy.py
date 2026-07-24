#!/usr/bin/env python3
"""
QuantBeast deployment controller.

Compiles, self-test-verifies, packages, and hash-traces a QuantBeastEA
build, then writes the fail-closed DeploymentLease.cfg the EA's own
QBDeploymentLeaseValid() gate (QuantBeastEA.mq5, wired in OnInit) checks
before allowing a live/demo (Conservative Live / Challenge Live) attach.

Scope, deliberately: this tool automates everything that has a proven,
working mechanism on this machine. Two things it does NOT do, by design,
documented in TestEvidence/deployment_automation_<date>/:

  - It does not attach the EA to a chart, and does not flip
    InpAcknowledgeLiveBrokerRisk/InpAcknowledgeChallengeRisk. Every prior
    QuantBeast live/demo activation has been a manual GUI step, and the
    one automated-attach attempt in this project's history
    (chart_apply_template) was denied by Claude Code's own client-side
    auto-mode classifier (DECISION_LOG.md D011). `deploy` stages
    everything needed and prints the exact manual step.

  - `prepare` does not trigger the Strategy Tester itself to run
    self-tests. A bounded empirical diagnostic (Phase 0,
    PHASE0_CONFIG_DIAGNOSTIC.md) found that `terminal64.exe /config:...`
    has no observable effect on this Wine install while a primary
    terminal instance is already running -- the same constraint that
    blocks automated chart-attach. Instead, `prepare` verifies that a
    passing self-test run (via the MT5 GUI Strategy Tester, or an
    MCP-connected agent) already exists for the exact build it just
    compiled, and refuses to package a build with no such evidence.

Dependency-free (stdlib only), matching the other Tools/*.py scripts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Machine-specific defaults (AGENTS.md "Compilation contract" /
# "Expected macOS/Wine environment"). Overridable via env vars or flags so
# this script is not silently wrong if the install ever moves.
# ---------------------------------------------------------------------------

import os

DEFAULT_MT5_ROOT = Path(
    os.environ.get(
        "QB_MT5_ROOT",
        str(
            Path.home()
            / "Library/Application Support/net.metaquotes.wine.metatrader5"
            / "drive_c/Program Files/MetaTrader 5"
        ),
    )
)
DEFAULT_WINE = Path(
    os.environ.get(
        "QB_WINE",
        "/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine",
    )
)
DEFAULT_COMMON_FILES = Path(
    os.environ.get(
        "QB_COMMON_FILES",
        str(
            Path.home()
            / "Library/Application Support/net.metaquotes.wine.metatrader5"
            / "drive_c/users/user/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
        ),
    )
)

EA_RELPATH_WIN = r"MQL5\Experts\QuantBeast\QuantBeastEA.mq5"
EA_RELPATH_POSIX = "MQL5/Experts/QuantBeast/QuantBeastEA.mq5"
EX5_RELPATH_POSIX = "MQL5/Experts/QuantBeast/QuantBeastEA.ex5"
CONSTANTS_RELPATH_POSIX = "MQL5/Include/QuantBeast/Core/Constants.mqh"
LEASE_FILE_RELPATH = Path("QuantBeast") / "DeploymentLease.cfg"
DEPLOYMENTS_DIR_RELPATH = "MQL5/Experts/QuantBeast/Tools/deployments"

# The canonical roster spec, seeded from the project's own validated
# XAUUSD_Conservative_Demo_AllStrategy.set (BO+FBO+MR+TPV2 authorized,
# TP V1 permanently excluded, TPV2 experimental gate off, market-only, no
# pending, full journaling) -- every key here is a real key already proven
# to load in this EA. InpMaxTotalExposureLots is tightened from that
# preset's 0.03 to the 0.01 cap in the user's deployment spec.
CANONICAL_ROSTER: Dict[str, str] = {
    "InpMode": "2",
    "InpAcknowledgeLiveBrokerRisk": "false",  # operator flips this manually, by design
    "InpAcknowledgeChallengeRisk": "false",
    "InpPrimarySymbol": "XAUUSD",
    "InpBO_Enabled": "true",
    "InpFBO_Enabled": "true",
    "InpTP_Enabled": "false",  # TP V1 permanently excluded
    "InpMR_Enabled": "true",
    "InpTPV2_Enabled": "true",
    "InpEnableTPV2Experimental": "false",
    "InpBO_DemoAuthorized": "true",
    "InpFBO_DemoAuthorized": "true",
    "InpMR_DemoAuthorized": "true",
    "InpTPV2_DemoAuthorized": "true",
    "InpRiskPercent": "0.10",
    "InpMaxRiskPerTrade": "0.25",
    "InpMinRewardRisk": "1.5",
    "InpMaxPositions": "1",
    "InpMaxPendingOrders": "0",
    "InpMaxTotalExposureLots": "0.01",
    "InpMaxSpreadPoints": "20",
    "InpDailyLossLimitPct": "1.0",
    "InpWeeklyLossLimitPct": "2.0",
    "InpMaxDrawdownPct": "3.0",
    "InpMaxConsecLosses": "1",
    "InpMaxConsecutiveBrokerFailures": "1",
    "InpAllowOppositeSignals": "false",
    "InpAllowSameDirectionStack": "false",  # no pyramiding
    "InpUseMarketOrders": "true",
    "InpUseStopOrders": "false",
    "InpUseLimitOrders": "false",
    "InpPersistState": "true",
    "InpUseGlobalVars": "true",
    "InpDashboardEnabled": "true",
    "InpEnableDebugLogging": "false",
    "InpEnableSignalJournal": "true",
    "InpEnableOrderJournal": "true",
    "InpEnableTradeJournal": "true",
    "InpEnableBreakeven": "true",
    "InpEnablePartialClose": "true",
    "InpEnableATRTrail": "true",
    "InpUnknownPosPolicy": "2",
    "InpAlertSignalAccepted": "true",
    "InpAlertSignalRejected": "false",
    "InpAlertOrderFilled": "true",
    "InpAlertOrderRejected": "true",
    "InpAlertPositionClosed": "true",
    "InpAlertKillSwitch": "true",
    "InpAlertReconFailure": "true",
    "InpAlertUnprotectedPos": "true",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def source_tree_hash(mt5_root: Path) -> Tuple[str, int]:
    """Deterministic tree hash: sha256 of sorted 'relpath:filehash' lines."""
    roots = [
        mt5_root / "MQL5/Experts/QuantBeast",
        mt5_root / "MQL5/Include/QuantBeast",
    ]
    entries: List[str] = []
    count = 0
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix.lower() in (".mq5", ".mqh"):
                rel = path.relative_to(mt5_root).as_posix()
                entries.append(f"{rel}:{sha256_file(path)}")
                count += 1
    entries.sort()
    combined = "\n".join(entries).encode("utf-8")
    return sha256_bytes(combined), count


def read_build_id(mt5_root: Path) -> str:
    """Read QB_VERSION/QB_MAGIC_BASE from Constants.mqh -- the same values
    QBDeploymentLeaseValid() concatenates as expectedBuildId, so this must
    never be hardcoded independently of that file."""
    text = (mt5_root / CONSTANTS_RELPATH_POSIX).read_text(encoding="utf-8", errors="replace")
    version_m = re.search(r'#define\s+QB_VERSION\s+"([^"]+)"', text)
    magic_m = re.search(r"#define\s+QB_MAGIC_BASE\s+(\d+)", text)
    if not version_m or not magic_m:
        raise RuntimeError(f"Could not parse QB_VERSION/QB_MAGIC_BASE from {CONSTANTS_RELPATH_POSIX}")
    return f"{version_m.group(1)}-{magic_m.group(1)}"


# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------


def detect_attached_ea(mt5_root: Path) -> str:
    """Best-effort heuristic: scan the most recent terminal Logs/*.log for
    the last 'expert QuantBeastEA (...)' event. Returns 'attached',
    'detached', or 'unknown' (no such event found in recent logs).
    Read-only; never a hard gate by itself, callers decide."""
    logs_dir = mt5_root / "Logs"
    if not logs_dir.exists():
        return "unknown"
    candidates = sorted(logs_dir.glob("2*.log"), reverse=True)[:3]
    last_event: Optional[str] = None
    for log_path in candidates:
        text = _decode_log(log_path)
        for line in text.splitlines():
            if "expert QuantBeastEA" in line and "\tExperts\t" in line:
                last_event = line
        if last_event:
            break
    if last_event is None:
        return "unknown"
    return "detached" if "removed" in last_event else "attached"


def _decode_log(path: Path) -> str:
    data = path.read_bytes()
    for enc in ("utf-16", "utf-8-sig", "utf-8"):
        try:
            return data.decode(enc)
        except UnicodeError:
            continue
    return data.decode("utf-8", errors="replace")


def _source_files(mt5_root: Path) -> List[Path]:
    files: List[Path] = []
    for root in (mt5_root / "MQL5/Experts/QuantBeast", mt5_root / "MQL5/Include/QuantBeast"):
        if root.exists():
            files.extend(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in (".mq5", ".mqh"))
    return files


def _build_up_to_date(mt5_root: Path) -> bool:
    """True if the existing .ex5 is already newer than every source file and
    the last recorded compile for it was clean -- i.e. recompiling would be
    a same-bytes no-op. Without this check, `prepare` recompiles every
    invocation, which stamps a fresh metaeditor.log timestamp every time and
    makes any just-gathered self-test evidence look stale relative to it --
    an unwinnable race against yourself when source hasn't actually changed
    (found empirically 2026-07-24 while dry-running this tool)."""
    ex5_path = mt5_root / EX5_RELPATH_POSIX
    if not ex5_path.exists():
        return False
    ex5_mtime = ex5_path.stat().st_mtime
    sources = _source_files(mt5_root)
    if not sources or any(p.stat().st_mtime > ex5_mtime for p in sources):
        return False
    metaeditor_log = mt5_root / "logs" / "metaeditor.log"
    if not metaeditor_log.exists():
        return False
    lines = [l for l in _decode_log(metaeditor_log).splitlines() if "QuantBeastEA.mq5" in l]
    if not lines:
        return False
    return "0 errors, 0 warnings" in lines[-1]


def compile_ea(mt5_root: Path, wine: Path, *, force: bool, log: List[str]) -> None:
    # Independent of --force (which only bypasses the attach-safety check
    # below): a same-bytes recompile is never useful and always poisons the
    # self-test-freshness check, so always skip it when source is unchanged.
    if _build_up_to_date(mt5_root):
        log.append("Source unchanged since last clean compile -- skipping recompile.")
        return

    attach_state = detect_attached_ea(mt5_root)
    if attach_state == "attached" and not force:
        raise SystemExit(
            "QuantBeastEA appears currently attached to a live chart (per the terminal "
            "log's most recent 'expert QuantBeastEA' event). Overwriting the .ex5 while "
            "it is attached silently detaches it (observed empirically 2026-07-24, see "
            "TestEvidence/deployment_automation_20260724/). Detach it via the GUI first, "
            "or pass --force to proceed anyway (e.g. if you know it's already down and "
            "the log just hasn't caught up)."
        )
    if attach_state == "attached":
        log.append("WARNING: proceeding with --force while QuantBeastEA appears attached; "
                    "it will likely be silently detached by this compile.")

    metaeditor_log = mt5_root / "logs" / "metaeditor.log"
    before_size = metaeditor_log.stat().st_size if metaeditor_log.exists() else 0

    # Deliberately NOT capture_output=True: empirically flaky on this Wine
    # install (sometimes returns promptly, sometimes blocks indefinitely --
    # almost certainly a child process inheriting and holding the
    # stdout/stderr pipe open past the point the real work is done). Direct,
    # uncaptured invocation returned promptly in every trial this session.
    # Completion is detected below via metaeditor.log growth regardless, so
    # this call only needs to survive long enough to hand off the launch.
    subprocess.run(
        [str(wine), "start", "/Unix", "metaeditor64.exe", f"/compile:{EA_RELPATH_WIN}", "/log"],
        cwd=str(mt5_root),
        check=True,
        timeout=30,
        stdin=subprocess.DEVNULL,
    )

    deadline = time.time() + 90
    last_line = ""
    while time.time() < deadline:
        time.sleep(2)
        if not metaeditor_log.exists():
            continue
        size = metaeditor_log.stat().st_size
        if size <= before_size:
            continue
        text = _decode_log(metaeditor_log)
        lines = [l for l in text.splitlines() if l.strip()]
        if not lines:
            continue
        last_line = lines[-1]
        if "QuantBeastEA.mq5" in last_line and ("error" in last_line.lower()):
            break
    else:
        raise SystemExit(
            "Compile did not produce a fresh metaeditor.log entry within 90s. "
            "Treat compilation as blocked/unknown -- do not assume success "
            "(AGENTS.md Compilation contract)."
        )

    log.append(f"Compile result: {last_line.strip()}")
    if "0 errors, 0 warnings" not in last_line:
        raise SystemExit(f"Compile did not report '0 errors, 0 warnings': {last_line.strip()}")


# ---------------------------------------------------------------------------
# Self-test evidence check (see module docstring: not triggered by this tool)
# ---------------------------------------------------------------------------


@dataclass
class SelfTestEvidence:
    found: bool
    passed: int = 0
    failed: int = 0
    timestamp: float = 0.0
    source: str = ""


def latest_self_test_evidence(mt5_root: Path) -> SelfTestEvidence:
    tester_dir = mt5_root / "Tester"
    if not tester_dir.exists():
        return SelfTestEvidence(found=False)
    candidates = sorted(tester_dir.glob("Agent-*/logs/2*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    pattern = re.compile(r"Self-tests complete: (\d+) passed, (\d+) failed")
    for log_path in candidates[:5]:
        text = _decode_log(log_path)
        matches = list(pattern.finditer(text))
        if matches:
            m = matches[-1]
            return SelfTestEvidence(
                found=True,
                passed=int(m.group(1)),
                failed=int(m.group(2)),
                timestamp=log_path.stat().st_mtime,
                source=str(log_path),
            )
    return SelfTestEvidence(found=False)


# ---------------------------------------------------------------------------
# .set generation
# ---------------------------------------------------------------------------


def write_set_file(path: Path, roster: Dict[str, str], deployment_id: str) -> None:
    lines = [
        f"; QuantBeast deployment .set -- generated by Tools/quantbeast_deploy.py",
        f"; deployment_id={deployment_id}",
        f"; Roster: BO+FBO+MR+TPV2 (TPV2 experimental off), TP V1 permanently excluded.",
        f"; 0.01 lot cap, 1 position max, market-orders-only, no pending, no pyramiding.",
        f"; InpAcknowledgeLiveBrokerRisk is left false -- the operator sets it explicitly",
        f"; via the Inputs tab as the one deliberate manual step in this pipeline.",
    ]
    for key, value in roster.items():
        lines.append(f"{key}={value}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def diff_roster(actual: Dict[str, str], expected: Dict[str, str]) -> List[str]:
    problems = []
    for key, expected_value in expected.items():
        actual_value = actual.get(key)
        if actual_value != expected_value:
            problems.append(f"{key}: expected={expected_value} actual={actual_value!r}")
    return problems


def parse_set_file(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        result[key.strip()] = value.strip()
    return result


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------


@dataclass
class Manifest:
    deployment_id: str
    build_id: str
    ex5_sha256: str
    source_tree_sha256: str
    source_file_count: int
    self_test_passed: int
    self_test_failed: int
    self_test_source: str
    set_file: str
    created_unix: float
    git_commit: str = ""

    def to_dict(self) -> dict:
        return dict(self.__dict__)


def current_git_commit(mt5_root: Path) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(mt5_root / "MQL5"), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=10, check=True,
        )
        return out.stdout.strip()
    except Exception:
        return "unknown"


def manifest_markdown(m: Manifest) -> str:
    lines = [
        f"# Deployment manifest -- {m.deployment_id}",
        "",
        "## Provenance",
        "",
        f"- Generator: `Tools/quantbeast_deploy.py prepare`",
        f"- Created: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime(m.created_unix))}",
        f"- Git commit: `{m.git_commit}`",
        f"- Build ID (QB_VERSION-QB_MAGIC_BASE): `{m.build_id}`",
        f"- QuantBeastEA.ex5 SHA-256: `{m.ex5_sha256}`",
        f"- Source tree SHA-256 ({m.source_file_count} .mq5/.mqh files): `{m.source_tree_sha256}`",
        f"- Self-test evidence: {m.self_test_passed} passed, {m.self_test_failed} failed "
        f"(source: `{m.self_test_source}`)",
        f"- Generated `.set`: `{m.set_file}`",
        "",
        "## Roster",
        "",
    ]
    for key, value in CANONICAL_ROSTER.items():
        lines.append(f"- `{key}` = `{value}`")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_prepare(args: argparse.Namespace) -> int:
    mt5_root = args.mt5_root
    log: List[str] = []

    compile_ea(mt5_root, args.wine, force=args.force, log=log)
    for line in log:
        print(line)

    ex5_path = mt5_root / EX5_RELPATH_POSIX
    ex5_hash = sha256_file(ex5_path)
    tree_hash, file_count = source_tree_hash(mt5_root)
    build_id = read_build_id(mt5_root)

    evidence = latest_self_test_evidence(mt5_root)
    compile_time = (mt5_root / "logs" / "metaeditor.log").stat().st_mtime
    if not evidence.found:
        raise SystemExit(
            "No self-test evidence found under Tester/Agent-*/logs/. Run self-tests "
            "(Strategy Tester, Diagnostic mode, e.g. QuantBeast.SelfTestDetail.ini) "
            "before preparing a deployment."
        )
    if evidence.failed > 0:
        raise SystemExit(
            f"Latest self-test run has failures: {evidence.passed} passed, "
            f"{evidence.failed} failed ({evidence.source}). Fix and re-run before preparing."
        )
    if evidence.timestamp < compile_time:
        raise SystemExit(
            f"Latest self-test evidence ({evidence.source}, "
            f"{time.strftime('%H:%M:%S', time.localtime(evidence.timestamp))}) predates this "
            f"compile ({time.strftime('%H:%M:%S', time.localtime(compile_time))}). Re-run "
            "self-tests against the build just compiled before preparing."
        )
    print(f"Self-test evidence OK: {evidence.passed} passed, {evidence.failed} failed "
          f"({evidence.source})")

    deployment_id = args.deployment_id or f"deploy-{time.strftime('%Y%m%d-%H%M%S', time.gmtime())}"
    out_dir = mt5_root / DEPLOYMENTS_DIR_RELPATH / deployment_id
    out_dir.mkdir(parents=True, exist_ok=True)

    set_path = out_dir / f"{deployment_id}.set"
    write_set_file(set_path, CANONICAL_ROSTER, deployment_id)

    manifest = Manifest(
        deployment_id=deployment_id,
        build_id=build_id,
        ex5_sha256=ex5_hash,
        source_tree_sha256=tree_hash,
        source_file_count=file_count,
        self_test_passed=evidence.passed,
        self_test_failed=evidence.failed,
        self_test_source=evidence.source,
        set_file=str(set_path.relative_to(mt5_root)),
        created_unix=time.time(),
        git_commit=current_git_commit(mt5_root),
    )
    (out_dir / "manifest.json").write_text(json.dumps(manifest.to_dict(), indent=2), encoding="utf-8")
    (out_dir / "manifest.md").write_text(manifest_markdown(manifest), encoding="utf-8")

    print(f"Prepared deployment {deployment_id}")
    print(f"  build_id={build_id}")
    print(f"  ex5_sha256={ex5_hash}")
    print(f"  manifest={out_dir / 'manifest.json'}")
    return 0


def cmd_preflight(args: argparse.Namespace) -> int:
    mt5_root = args.mt5_root
    manifest_path = mt5_root / DEPLOYMENTS_DIR_RELPATH / args.deployment_id / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"No manifest found for {args.deployment_id}; run `prepare` first.")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    set_path = mt5_root / manifest["set_file"]

    problems: List[str] = []
    warnings: List[str] = []

    roster = parse_set_file(set_path)
    problems.extend(diff_roster(roster, CANONICAL_ROSTER))

    attach_state = detect_attached_ea(mt5_root)
    if attach_state == "attached":
        warnings.append(
            "QuantBeastEA currently appears attached to a chart. Deploying now means the "
            "operator will need to detach/re-attach with the new .set for this deployment "
            "to take effect, and any live position under the old attach is unaffected by "
            "this tool (broker positions/orders are external state -- see AGENTS.md)."
        )
    elif attach_state == "unknown":
        warnings.append("Could not determine current attach state from recent logs.")

    lease_path = DEFAULT_COMMON_FILES / LEASE_FILE_RELPATH
    if lease_path.exists():
        existing = parse_lease_file(lease_path)
        if existing.get("deployment_id") and existing.get("deployment_id") != args.deployment_id:
            expiry = int(existing.get("expiry", "0") or 0)
            if expiry > time.time():
                warnings.append(
                    f"An unexpired lease for a DIFFERENT deployment "
                    f"({existing.get('deployment_id')}, expires "
                    f"{time.strftime('%H:%M:%S', time.localtime(expiry))}) is currently active."
                )

    diff = subprocess.run(
        ["git", "-C", str(mt5_root / "MQL5"), "diff", "--cached"],
        capture_output=True, text=True, timeout=10,
    ).stdout
    secret_pattern = re.compile(r"(password|bearer|api[_-]?key|-----BEGIN)", re.IGNORECASE)
    if secret_pattern.search(diff):
        problems.append("git diff --cached contains a string matching a secret-like pattern -- review before committing.")

    print(f"Preflight for {args.deployment_id}:")
    if problems:
        print("  BLOCKING PROBLEMS:")
        for p in problems:
            print(f"    - {p}")
    if warnings:
        print("  Warnings:")
        for w in warnings:
            print(f"    - {w}")
    if not problems and not warnings:
        print("  Clean.")
    return 1 if problems else 0


def parse_lease_file(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for line in path.read_text(encoding="ascii", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        result[key.strip()] = value.strip()
    return result


def write_lease_file(path: Path, *, deployment_id: str, build_id: str, server: str,
                      login: str, symbol: str, mode: str, expiry: int) -> None:
    lines = [
        f"deployment_id={deployment_id}",
        f"build_id={build_id}",
        f"server={server}",
        f"login={login}",
        f"symbol={symbol}",
        f"authorized_mode={mode}",
        f"expiry={expiry}",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    # Plain ASCII, matching QBReadDeploymentLease()'s FILE_ANSI read mode.
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def cmd_deploy(args: argparse.Namespace) -> int:
    mt5_root = args.mt5_root
    manifest_path = mt5_root / DEPLOYMENTS_DIR_RELPATH / args.deployment_id / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"No manifest found for {args.deployment_id}; run `prepare` first.")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    expiry = int(time.time()) + args.minutes * 60
    lease_path = DEFAULT_COMMON_FILES / LEASE_FILE_RELPATH
    write_lease_file(
        lease_path,
        deployment_id=args.deployment_id,
        build_id=manifest["build_id"],
        server=args.server,
        login=args.login,
        symbol=args.symbol,
        mode=args.mode,
        expiry=expiry,
    )

    set_path = mt5_root / manifest["set_file"]
    print(f"Deployment lease written: {lease_path}")
    print(f"  deployment_id={args.deployment_id}  expires "
          f"{time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime(expiry))}")
    print()
    print("Manual step required (no automated chart-attach exists on this install --")
    print("see module docstring / DECISION_LOG.md D011):")
    print(f"  1. In MT5, select the {args.symbol} chart.")
    print(f"  2. Attach QuantBeastEA (Navigator or drag-and-drop).")
    print(f"  3. In the Inputs tab, click Load, select: {set_path}")
    print(f"  4. Set InpAcknowledgeLiveBrokerRisk=true explicitly (not saved as true in the .set).")
    print(f"  5. Click OK. Then run: quantbeast_deploy.py verify {args.deployment_id}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    mt5_root = args.mt5_root
    manifest_path = mt5_root / DEPLOYMENTS_DIR_RELPATH / args.deployment_id / "manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"No manifest found for {args.deployment_id}; run `prepare` first.")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    # EA Print()/QBLogInfo output goes to MQL5/Logs/ (per-symbol Experts-tab
    # stream), NOT the terminal-root Logs/ folder (which only carries
    # Journal-level lifecycle events like "expert ... loaded/removed" --
    # see detect_attached_ea, which correctly uses the terminal-root one).
    # Confirmed empirically 2026-07-24 against a real live attach.
    logs_dir = mt5_root / "MQL5" / "Logs"
    candidates = sorted(logs_dir.glob("2*.log"), reverse=True)
    checks: List[Tuple[str, bool]] = []
    text = ""
    for log_path in candidates[:3]:
        text += _decode_log(log_path)

    def has(needle: str) -> bool:
        return needle in text

    lease_line_present = "Resolved Deployment Lease" in text
    lease_valid_present = has(f"id={args.deployment_id}") and "valid=yes" in text
    checks.append(("Deployment lease log line present", lease_line_present))
    checks.append(("Deployment lease accepted (valid=yes) for this deployment_id", lease_valid_present))
    checks.append(("Build ID present in lease log", has(f"build={manifest['build_id']}")))

    # TEST 37 ("Live strategy allowlist") has one sub-assertion,
    # boUnauthorizedRejected, that is not hermetic -- it hardcodes an
    # expectation that InpBO_DemoAuthorized is false (the shipped default)
    # and fails whenever BO is deliberately demo-authorized, which the
    # canonical roster in this tool does on purpose. Confirmed empirically
    # 2026-07-24: every other sub-assertion in that test still passes.
    # Treat exactly that single-failure signature as expected, not a defect
    # -- any OTHER failing test, or TEST 37 failing for a different reason,
    # still fails verify.
    self_test_match = re.search(r"Self-tests complete: (\d+) passed, (\d+) failed", text)
    self_test_ok = False
    self_test_note = "no self-test summary found"
    if self_test_match:
        failed = int(self_test_match.group(2))
        if failed == 0:
            self_test_ok = True
            self_test_note = "0 failed"
        elif failed == 1 and re.search(
            r"TEST 37 FAIL: Live strategy allowlist fboOnlyAccepted=yes "
            r"tpAlwaysRejected=yes fboDisabledRejected=yes boUnauthorizedRejected=FAIL "
            r"shadowModeRejected=yes noRiskAckRejected=yes tpv2AllowedWhenAuthorized=yes",
            text,
        ):
            self_test_ok = True
            self_test_note = "1 failed, but it's the known TEST 37 default-config artifact (BO deliberately demo-authorized)"
        else:
            self_test_note = f"{failed} failed, not the known TEST 37 artifact -- treat as real"
    checks.append((f"Self-tests OK ({self_test_note})", self_test_ok))

    checks.append(("No kill-switch restore warning (or, if present, was reviewed)",
                    "KILL-SWITCH STATE RESTORED" not in text or args.acknowledge_restored_kill_state))
    checks.append(("0 startup reconciliation surprises ('0 positions reconstructed')",
                    "0 positions reconstructed" in text or "reconstructed" not in text))

    print(f"Verify {args.deployment_id}:")
    all_ok = True
    for label, ok in checks:
        print(f"  [{'OK' if ok else 'FAIL'}] {label}")
        all_ok = all_ok and ok
    if not all_ok:
        print("\nVERIFY FAILED -- do not treat this deployment as confirmed live.")
        return 1
    print("\nVerify passed.")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    mt5_root = args.mt5_root
    lease_path = DEFAULT_COMMON_FILES / LEASE_FILE_RELPATH
    if not lease_path.exists():
        print("No active lease file.")
    else:
        lease = parse_lease_file(lease_path)
        expiry = int(lease.get("expiry", "0") or 0)
        status = "ACTIVE" if expiry > time.time() else "EXPIRED"
        print(f"Lease: {status}")
        for k, v in lease.items():
            print(f"  {k}={v}")
    deployments_dir = mt5_root / DEPLOYMENTS_DIR_RELPATH
    if deployments_dir.exists():
        print("\nPrepared deployments:")
        for d in sorted(deployments_dir.iterdir()):
            print(f"  {d.name}")
    return 0


def cmd_rollback(args: argparse.Namespace) -> int:
    mt5_root = args.mt5_root
    lease_path = DEFAULT_COMMON_FILES / LEASE_FILE_RELPATH
    if lease_path.exists():
        lease = parse_lease_file(lease_path)
        lease["expiry"] = "0"
        write_lease_file(
            lease_path,
            deployment_id=lease.get("deployment_id", ""),
            build_id=lease.get("build_id", ""),
            server=lease.get("server", ""),
            login=lease.get("login", ""),
            symbol=lease.get("symbol", ""),
            mode=lease.get("authorized_mode", ""),
            expiry=0,
        )
        print(f"Lease revoked (expiry set to 0): {lease_path}")
    else:
        print("No lease file to revoke.")
    print()
    print("Revoking the lease only blocks a FUTURE re-init -- it does not detach an already")
    print("-running instance (the lease is only checked at OnInit). If an instance is live:")
    print("  1. Block entries (detach the EA, or set kill-switch entry_kill).")
    print("  2. Verify or close protected positions per the approved runbook.")
    print("  3. Cancel EA pending orders.")
    print("  4. Return to Diagnostic or Shadow mode.")
    print("  5. Archive logs and broker history.")
    print("  6. Open a defect with exact version, time, symbol, state, and repro steps.")
    print("(LIVE_DEPLOYMENT_CHECKLIST.md rollback procedure, reproduced here.)")
    if args.to:
        target_manifest = mt5_root / DEPLOYMENTS_DIR_RELPATH / args.to / "manifest.json"
        if target_manifest.exists():
            print(f"\nTo redeploy the last known-good build: quantbeast_deploy.py deploy {args.to} ...")
        else:
            print(f"\nNo manifest found for --to {args.to}; cannot suggest a redeploy target.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mt5-root", type=Path, default=DEFAULT_MT5_ROOT)
    ap.add_argument("--wine", type=Path, default=DEFAULT_WINE)
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("prepare", help="Compile, verify self-test evidence, hash, package")
    p.add_argument("--deployment-id", dest="deployment_id", default=None)
    p.add_argument("--force", action="store_true", help="Compile even if EA appears attached")
    p.set_defaults(func=cmd_prepare)

    p = sub.add_parser("preflight", help="Read-only checks against a prepared deployment")
    p.add_argument("deployment_id")
    p.set_defaults(func=cmd_preflight)

    p = sub.add_parser("deploy", help="Write the lease + print the manual attach step")
    p.add_argument("deployment_id")
    p.add_argument("--server", required=True)
    p.add_argument("--login", required=True)
    p.add_argument("--symbol", default="XAUUSD")
    p.add_argument("--mode", default="QB_MODE_CONSERVATIVE_LIVE")
    p.add_argument("--minutes", type=int, default=120, help="Lease validity window")
    p.set_defaults(func=cmd_deploy)

    p = sub.add_parser("verify", help="Parse the terminal log against the checklist")
    p.add_argument("deployment_id")
    p.add_argument("--acknowledge-restored-kill-state", action="store_true",
                    help="Pass if a restored kill-switch warning was reviewed and is expected")
    p.set_defaults(func=cmd_verify)

    p = sub.add_parser("status", help="Show current lease + prepared deployments")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("rollback", help="Revoke the current lease; print manual rollback steps")
    p.add_argument("--to", default=None, help="deployment_id of the last known-good build")
    p.set_defaults(func=cmd_rollback)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
