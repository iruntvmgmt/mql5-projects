# MT5 Failure Recovery Matrix

## 1. Purpose

This matrix converts known MT5/macOS/Wine failure modes into mandatory, bounded recovery procedures. Agents must not improvise across runtime boundaries.

## 2. Matrix

| Symptom | Likely cause | Required action | Forbidden response |
|---|---|---|---|
| Direct MetaEditor command exits 0 but no fresh log/binary | Wine/MetaEditor no-op launch | Use isolated `wine start /Unix metaeditor64.exe /portable /compile:... /log`; poll once | Claim compile success from exit code |
| First compile log appears late | Cold-start latency | Poll bounded time; inspect process; retry exact compile once only after no active compiler remains | Launch many duplicate compilers |
| MT5 app/main terminal is not running | Application stopped | Use documented application launch and readiness polling when the ticket targets main terminal | Declare blocked without launch attempt |
| MCP has no `run_script` tool | MCP scope limitation | Use isolated portable `[StartUp] Script=` bridge | Copy script to main terminal or misuse tester tool |
| Portable script process remains running | `[StartUp]` terminal does not auto-close | Read fresh log markers/artifacts; then kill ticket-owned PID only | Treat survival as script failure |
| Dated terminal log missing immediately | Startup delay or different terminal date | Confirm PID; poll logs directory; discover actual file | Immediate blocker or repeated launch |
| Raw grep shows unreadable output | UTF-16LE log | Decode with `iconv` or Python | Treat log as corrupt |
| Tester MCP returns ambiguous `job_id: 0` | MCP ambiguity | Use local process, tester-agent log, report, and artifacts as authority | Start a second tester request |
| Second tester request cancels synchronization | Duplicate launch | One launch per run; monitor read-only | Retry while first process is active |
| Tester log contains old PASS markers | Cumulative daily log | Slice from pre-run byte/line boundary or unique marker | Count whole log |
| Expected CSV not in `<ISO>/MQL5/Files` | Tester uses agent sandbox | Search bounded `<ISO>/Tester/Agent-*/MQL5/Files` | Declare output absent without checking tester sandbox |
| `$!` exits but terminal remains | Wine launcher spawned child | Discover exact process by isolated root and `/config:` argument | Assume process ended |
| More than one matching portable process | Duplicate/orphaned run | Stop; collect state; terminate only proven ticket-owned duplicates after authorization | Continue and merge outputs |
| Staged destination SHA differs | Copy error or mutation | Stop, quarantine, restage from exact source after owner review | Compile mismatched source |
| Output existed before run and remains unchanged | Stale artifact | Reject as new evidence; quarantine before authorized rerun | Claim current output |
| Python and MQL files are byte-identical but same process authored both | False independence | Reject cross-language parity | Call identical copies parity |
| Shell reports `read-only variable: status` | zsh reserved name | Use Bash shebang or rename variable | Disable shell safety globally |
| Script needs runtime state unavailable in fixtures | Observation gap | Implementation owner may authorize side-effect-free diagnostic probe | Runtime engineer invents strategy changes |
| No real netting account/live position exists | Environment limitation | Deterministic policy tests + source review + documented unverified runtime gap | Fabricate full certification |
| Main terminal receives isolated harness files | Runtime boundary breach | Stop; inventory contamination; quarantine/remove only with authorization; invalidate run | Continue using main terminal |
| Bearer token printed | Secret exposure | Stop; redact; rotate token; remove tracked/plaintext use | Repeat token or continue normally |

## 3. Recovery attempt limit

Unless the active ticket says otherwise:

- one initial launch;
- one bounded observation period;
- one documented retry only for a proven no-op or cold-start condition;
- then stop and report.

A retry must not overlap an active process.

## 4. Blocked-state requirements

`RUNTIME_BLOCKED` requires:

- exact command, redacted;
- exit code or tool error;
- stdout/stderr;
- process state;
- log paths and fresh boundaries;
- recovery steps attempted;
- exact missing capability;
- reason continued attempts would risk evidence integrity.

These are not blockers by themselves:

- MT5 initially stopped;
- log not created immediately;
- MCP lacks script execution;
- tester job ID ambiguous;
- direct compiler no-op before `start /Unix` fallback;
- expected file not found in the first guessed directory.

## 5. Runtime boundary breach report

When a task crosses into the wrong terminal/runtime, report:

- files copied;
- source/destination hashes;
- binaries created;
- INIs created;
- processes launched;
- logs/artifacts created;
- whether any script/EA executed;
- whether broker state changed;
- why evidence is invalid;
- required cleanup owner.

Do not perform broad cleanup without authorization.

## 6. Escalation owner

- Runtime mechanics: Runtime Engineer reports to active Lead.
- Harness/source defect: Lead owns repair or spec escalation.
- Evidence ambiguity: Independent Reviewer decides admissibility.
- Secret exposure: user/security owner must rotate credentials.
- Live/broker impact: stop immediately and escalate to user.
