#!/bin/zsh
set -u

instance=/Users/matt/MT5-MSZZ-TEST
wine="/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine"
raw_log=$instance/MQL5/Logs/20260730.log
output=/private/tmp/d033_methodology_regression.tsv

print -r -- $'suite\tbaseline\tafter\tfresh\tshutdown_timeout\tresult\tevidence' > "$output"
for config in $instance/regress_Test_MSZZ_*.ini(N); do
  suite=${config:t:r}
  baseline=$(wc -l < "$raw_log" | tr -d ' ')
  "$wine" "$instance/terminal64.exe" /portable \
    "/config:Z:\\Users\\matt\\MT5-MSZZ-TEST\\${config:t}" \
    >"/private/tmp/${suite}.methodology.wine.log" 2>&1 &
  run_pid=$!
  shutdown_timeout=false
  for i in {1..75}; do
    if ! kill -0 "$run_pid" 2>/dev/null; then
      wait "$run_pid" 2>/dev/null
      break
    fi
    sleep 1
  done
  if kill -0 "$run_pid" 2>/dev/null; then
    kill "$run_pid"
    wait "$run_pid" 2>/dev/null
    shutdown_timeout=true
  fi
  after=$(wc -l < "$raw_log" | tr -d ' ')
  fresh=$((after-baseline))
  fresh_file="/private/tmp/${suite}.methodology.fresh.log"
  if (( fresh > 0 )); then
    iconv -f UTF-16LE -t UTF-8 "$raw_log" | tail -n "$fresh" > "$fresh_file"
  else
    : > "$fresh_file"
  fi
  evidence=$(rg 'TEST_SUMMARY|test complete failures=|equivalence test complete failures=|TEST PASS: deterministic rebuild|Test_MSZZ_PositionSizing: failures=' \
    "$fresh_file" | tail -1 | tr '\t' ' ' || true)
  if (( fresh <= 0 )); then
    result=TOOLING_NO_OP
  elif [[ -z "$evidence" ]]; then
    result=NO_FRESH_SUMMARY
  elif print -r -- "$evidence" | rg -q \
    'failures=0|TEST PASS: deterministic rebuild'; then
    result=PASS
  else
    result=FAIL
  fi
  print -r -- "${suite}"$'\t'"${baseline}"$'\t'"${after}"$'\t'"${fresh}"$'\t'"${shutdown_timeout}"$'\t'"${result}"$'\t'"${evidence}" \
    >> "$output"
  print -r -- "${suite} ${result} fresh=${fresh} timeout=${shutdown_timeout}"
done
