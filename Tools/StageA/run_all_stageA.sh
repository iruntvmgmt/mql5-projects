#!/bin/bash
# Run every Stage A config not yet completed, copying results out of the
# Tester Agent sandbox after each run. Each run deletes stale sandbox
# output before launching (see run_stageA.sh) and waits for a settle
# delay after process exit, so file-existence after a run genuinely means
# THIS run wrote it. A run is only ever trusted -- for either a real
# result OR a genuine 0-trade result -- if run_stageA.sh's own log check
# printed VERIFIED. If it printed WARNING (run did not actually complete,
# e.g. a network hiccup or a flush-timing race), that's always a retry,
# never a 0-trade acceptance.
set -uo pipefail

CONFIG_DIR="$HOME/MT5-MSZZ-TEST/StageA_Configs"
RESULTS_DIR="$HOME/MT5-MSZZ-TEST/StageA_Results"
RUN_SCRIPT="/private/tmp/claude-502/-Users-matt/d62aa486-4ac9-43cc-bedf-abdd8b592b8b/scratchpad/run_stageA.sh"
EXPECTED_YEAR_MONTH="2026.07"   # ToDate=2026.07.24 in every Stage A config

for cfg in "$CONFIG_DIR"/stageA_*.ini; do
   name=$(basename "$cfg" .ini)
   name=${name#stageA_}
   outdir="$RESULTS_DIR/$name"

   if [ -f "$outdir/MSZZ_RunSummary.csv" ] || [ -f "$outdir/NO_TRADES_PRODUCED" ]; then
      echo "SKIP $name (already have verified results)"
      continue
   fi

   attempt=1
   success=0
   while [ "$attempt" -le 3 ]; do
      echo "=== RUNNING $name (attempt $attempt) ==="
      run_output=$(bash "$RUN_SCRIPT" "stageA_${name}.ini" 2>&1)
      echo "$run_output"

      if ! echo "$run_output" | grep -q "^VERIFIED:"; then
         echo "NOT VERIFIED: $name attempt $attempt did not confirm completion in the terminal log. Retrying."
         attempt=$((attempt+1))
         continue
      fi

      # Which agent port actually received this run's output -- never
      # assume a fixed port, it has been observed to move mid-session.
      sandbox=$(echo "$run_output" | grep "^ACTIVE_SANDBOX=" | tail -1 | cut -d= -f2-)

      if [ -z "$sandbox" ] || [ ! -f "$sandbox/MSZZ_TradeAnalytics.csv" ]; then
         echo "Verified completion with no trades for $name (attempt $attempt) -- genuine 0-trade result."
         mkdir -p "$outdir"
         touch "$outdir/NO_TRADES_PRODUCED"
         success=1
         break
      fi

      last_close=$(tail -1 "$sandbox/MSZZ_TradeAnalytics.csv" | cut -d';' -f8)
      case "$last_close" in
         ${EXPECTED_YEAR_MONTH}*)
            mkdir -p "$outdir"
            cp "$sandbox/MSZZ_TradeAnalytics.csv" "$outdir/"
            [ -f "$sandbox/MSZZ_RunSummary.csv" ] && cp "$sandbox/MSZZ_RunSummary.csv" "$outdir/"
            REPORT="$HOME/MT5-MSZZ-TEST/StageA_${name}.htm"
            [ -f "$REPORT" ] && cp "$REPORT" "$outdir/"
            echo "COPIED verified results for $name (last close_time=$last_close)"
            success=1
            ;;
         *)
            echo "SUSPECT: $name last close_time=$last_close does not reach $EXPECTED_YEAR_MONTH despite VERIFIED completion -- likely truncated. Retrying."
            attempt=$((attempt+1))
            continue
            ;;
      esac
      break
   done

   if [ "$success" -ne 1 ]; then
      echo "FAILED: $name did not produce a verified complete run after 3 attempts -- flagging for manual investigation."
      mkdir -p "$outdir"
      touch "$outdir/NEEDS_MANUAL_RERUN"
   fi

   echo "=== DONE $name ==="
done

echo "=== ALL STAGE A RUNS COMPLETE ==="
