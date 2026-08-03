# MT5 Operational Command Cookbook

These are templates, not blanket authorization. Replace only ticket-defined values. Never paste secrets into commands or logs.

## 1. Environment variables

```bash
#!/usr/bin/env bash
set -u

WINE="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
MAIN_ROOT="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5"
CANONICAL_MQL5="$MAIN_ROOT/MQL5"
ISO="/Users/matt/MT5-MSZZ-TEST"
EVIDENCE_DIR="$HOME/OpenClawEvidence/<ticket-id>"
mkdir -p "$EVIDENCE_DIR"
```

Do not use `status` as a variable name under zsh.

## 2. Record process baseline

```bash
ps aux | grep '[t]erminal64.exe' | tee "$EVIDENCE_DIR/processes_before.txt"
ps aux | grep '[m]etaeditor64.exe' | tee "$EVIDENCE_DIR/metaeditor_before.txt"
```

## 3. Hash a file

```bash
shasum -a 256 "$FILE"
stat -f 'size=%z mtime=%m path=%N' "$FILE"
```

## 4. Hash-verified copy

```bash
SRC="<canonical-source>"
DST="<isolated-destination>"
mkdir -p "$(dirname "$DST")"
SRC_SHA=$(shasum -a 256 "$SRC" | awk '{print $1}')
cp "$SRC" "$DST"
DST_SHA=$(shasum -a 256 "$DST" | awk '{print $1}')
[ "$SRC_SHA" = "$DST_SHA" ] || { echo "SHA mismatch" >&2; exit 1; }
printf '%s\t%s\t%s\n' "$SRC_SHA" "$SRC" "$DST" >> "$EVIDENCE_DIR/staging.tsv"
```

## 5. Compile in isolated MetaEditor

```bash
cd "$ISO"
"$WINE" start /Unix metaeditor64.exe \
  /portable \
  /compile:"MQL5\\Scripts\\MultiSpeedZigZagTests\\Test_Name.mq5" \
  /log
```

Then poll for the expected `.log`; decode it before evaluating.

## 6. Decode UTF-16LE log

```bash
iconv -f utf-16le -t utf-8 "$LOG" > "$EVIDENCE_DIR/$(basename "$LOG").utf8.txt"
```

Original log must remain unchanged and must be hashed separately.

## 7. Record fresh log boundary

```bash
if [ -f "$LOG" ]; then
  wc -c < "$LOG" > "$EVIDENCE_DIR/log_start_bytes.txt"
  shasum -a 256 "$LOG" > "$EVIDENCE_DIR/log_start_sha256.txt"
else
  printf 'ABSENT\n' > "$EVIDENCE_DIR/log_start_state.txt"
fi
```

## 8. Create script startup INI

```bash
cat > "$ISO/certified_journal_start.ini" <<'EOF'
[StartUp]
Script=MultiSpeedZigZagTests\Test_MSZZ_MC_CANON2_CertifiedJournal
Symbol=XAUUSD
Period=M5
EOF
shasum -a 256 "$ISO/certified_journal_start.ini"
```

## 9. Launch isolated script

```bash
"$WINE" "$ISO/terminal64.exe" \
  /portable \
  /config:certified_journal_start.ini &
LAUNCHER_PID=$!
printf 'launcher_pid=%s\n' "$LAUNCHER_PID" > "$EVIDENCE_DIR/launch_pid.txt"
```

Then identify the final process by exact command line:

```bash
ps aux | grep '[t]erminal64.exe' | grep '/portable' | grep 'certified_journal_start.ini'
```

Require exactly one match.

## 10. Poll for a dated terminal log

```bash
for _ in $(seq 1 90); do
  LOG=$(find "$ISO/MQL5/logs" -maxdepth 1 -type f -name '*.log' -print 2>/dev/null | sort | tail -1)
  [ -n "${LOG:-}" ] && break
  sleep 1
done
[ -n "${LOG:-}" ] || { echo "No terminal log after timeout" >&2; exit 1; }
```

## 11. Extract appended bytes

```bash
START_BYTES=$(cat "$EVIDENCE_DIR/log_start_bytes.txt" 2>/dev/null || printf '0')
tail -c "+$((START_BYTES + 1))" "$LOG" > "$EVIDENCE_DIR/current_run.raw"
iconv -f utf-16le -t utf-8 "$EVIDENCE_DIR/current_run.raw" > "$EVIDENCE_DIR/current_run.txt"
```

If byte slicing begins mid-code-unit, use decoded line boundary or unique run marker instead.

## 12. Launch Strategy Tester

```bash
"$WINE" "$ISO/terminal64.exe" \
  /portable \
  /config:ticket_tester.ini &
```

Do not launch again while a matching process is active.

## 13. Discover tester artifacts

```bash
find "$ISO/Tester" -maxdepth 6 -type f \
  \( -name '*.log' -o -name '*.csv' -o -name '*.html' -o -name '*.xml' \) \
  -print | sort
```

## 14. Hash evidence tree

```bash
find "$EVIDENCE_DIR" -type f -print0 | sort -z | while IFS= read -r -d '' f; do
  shasum -a 256 "$f"
done > "$EVIDENCE_DIR/SHA256SUMS"
```

Run this before adding `SHA256SUMS` itself, or exclude that file.

## 15. Safe portable-process termination

```bash
TEST_PID="<verified-ticket-owned-pid>"
kill -TERM "$TEST_PID"
for _ in $(seq 1 20); do
  ps -p "$TEST_PID" >/dev/null 2>&1 || break
  sleep 1
done
ps -p "$TEST_PID" >/dev/null 2>&1 && echo "Process still active; escalate"
```

Never use broad process-name termination.

## 16. Verify main terminal survived

```bash
MAIN_PID=$(awk -F= '/MAIN_TERMINAL_PID/{print $2}' "$EVIDENCE_DIR/main_terminal_pid.env")
ps -p "$MAIN_PID" -o pid=,command=
```

## 17. Search for completion markers

```bash
grep -F 'CERTIFIED_JOURNAL_START' "$EVIDENCE_DIR/current_run.txt"
grep -F 'CERTIFIED_JOURNAL_COMPLETE' "$EVIDENCE_DIR/current_run.txt"
grep -E 'failures=0|assertions_failed=0' "$EVIDENCE_DIR/current_run.txt"
```

The exact markers must come from the ticket.

## 18. Security reminder

Do not run commands that print MCP configuration, authorization headers, broker credentials, or account passwords. Health checks must redact authentication material.
