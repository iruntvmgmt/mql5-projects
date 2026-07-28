#!/bin/bash
# Launch one Stage A backtest against the ISOLATED test instance ONLY.
# Never touches the live terminal (identified by "Program Files" in its command line).
set -euo pipefail

CONFIG_NAME="$1"   # e.g. stageA_MediumBreakout_RR10.ini (relative to StageA_Configs/)
TEST_DIR="$HOME/MT5-MSZZ-TEST"
WINE_BIN="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
export WINEPREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5"

# The Tester can spin up its MetaTester Agent on a DIFFERENT port
# (Agent-127.0.0.1-3001, -3002, ...) if a prior agent process didn't tear
# down cleanly -- confirmed to actually happen after a forceful `pkill`
# mid-batch. Hardcoding port 3000 silently read/deleted the WRONG (stale)
# directory while real data landed elsewhere. Operate on ALL agent
# directories that exist, never assume which port is "the" one.
agent_files_dirs() {
   find "$HOME/MT5-MSZZ-TEST/Tester" -mindepth 3 -maxdepth 3 -type d -path "*/Agent-*/MQL5/Files" 2>/dev/null
}

isolated_pids() {
   ps aux | grep "terminal64.exe" | grep -v "Program Files" | grep -v grep | awk '{print $2}'
}

for pid in $(isolated_pids); do
   echo "Killing lingering isolated terminal pid $pid"
   kill "$pid" 2>/dev/null || true
done
sleep 3

# Delete any leftover sandbox output BEFORE launching, from EVERY agent
# directory. Without this, a run that fails to execute (e.g. a network
# hiccup) leaves the PREVIOUS run's files sitting there, and they get
# silently mistaken for this run's fresh output -- exactly what happened
# during the mid-batch wifi drop (and, separately, what happened when the
# active agent silently moved to a different port mid-batch).
while IFS= read -r d; do
   rm -f "$d/MSZZ_TradeAnalytics.csv" "$d/MSZZ_RunSummary.csv"
done < <(agent_files_dirs)

RUN_START_EPOCH=$(date +%s)
CONFIG_PATH="Z:\\Users\\matt\\MT5-MSZZ-TEST\\StageA_Configs\\${CONFIG_NAME}"

# Baseline count BEFORE launching. The log file accumulates every run of
# the whole day, so just checking "does the success line appear anywhere"
# would trivially pass once ANY earlier run that day succeeded -- even if
# THIS run genuinely fails outright (e.g. the original wifi-drop failure
# mode). Only an INCREASE beyond this baseline proves THIS run completed.
LOG="$HOME/MT5-MSZZ-TEST/logs/$(date +%Y%m%d).log"
BASELINE_COUNT=0
if [ -f "$LOG" ]; then
   BASELINE_COUNT=$(iconv -f UTF-16LE -t UTF-8 "$LOG" 2>/dev/null | grep -c 'last test passed with result "successfully finished"' || true)
fi

cd "$TEST_DIR"
echo "Launching isolated terminal with config: $CONFIG_NAME"
"$WINE_BIN" terminal64.exe /portable /config:"$CONFIG_PATH" > /tmp/stageA_wine_launch.log 2>&1 &
WINE_PID=$!
echo "wine launcher pid: $WINE_PID"

sleep 8
for i in $(seq 1 170); do
   if [ -z "$(isolated_pids)" ]; then
      echo "Isolated terminal process no longer running after grace+${i}x2s polls."
      break
   fi
   sleep 2
done

# Verify actual completion via the terminal's own log, not just process
# exit -- and specifically that THIS run added a new success line beyond
# the pre-launch baseline (see above). Observed run durations vary by over
# a minute run to run (2:15 to 3:26+), so a single fixed settle delay
# after process exit is unreliable -- confirmed empirically (a fixed 5s
# delay was sometimes enough, sometimes not). Poll instead of guessing.
VERIFIED=0
for j in $(seq 1 15); do
   CURRENT_COUNT=$(iconv -f UTF-16LE -t UTF-8 "$LOG" 2>/dev/null | grep -c 'last test passed with result "successfully finished"' || true)
   if [ "$CURRENT_COUNT" -gt "$BASELINE_COUNT" ]; then
      VERIFIED=1
      break
   fi
   sleep 2
done
if [ "$VERIFIED" -eq 1 ]; then
   echo "VERIFIED: terminal log confirms a NEW successful test completion for this run (baseline=$BASELINE_COUNT, now=$CURRENT_COUNT)."
else
   echo "WARNING: terminal log does not show a new successful completion for this run (still at baseline=$BASELINE_COUNT)."
fi

# Report whichever agent directory actually received fresh output this
# run (there should be at most one, since every agent dir was cleared
# before launch) so the caller doesn't have to guess a port number.
ACTIVE_SANDBOX=""
while IFS= read -r d; do
   if [ -f "$d/MSZZ_TradeAnalytics.csv" ]; then
      ACTIVE_SANDBOX="$d"
   fi
done < <(agent_files_dirs)
echo "ACTIVE_SANDBOX=${ACTIVE_SANDBOX}"

echo "=== Run finished (or timed out) for $CONFIG_NAME ==="
