#!/bin/bash
# Stage B-lite config generator: one-factor-at-a-time ATR robustness.
# 8 strategies x 4 factors x 2 non-canonical levels each = 64 configs.
# RiskReward fixed at 2.0 throughout -- see DECISION_LOG.md D020.
# Canonical cell (ATR len 14, Fast 1.0, Med 2.0, Slow 3.5) is NOT
# regenerated here; it is reused from each strategy's Stage A RR2.0 run
# (or D019's research-mode RR2.0 run for FastBreakout) per D020's
# explicit exact-match reuse conditions.
set -euo pipefail

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STRAT_NAMES=(FastBreakout MediumBreakout SlowBreakout FastMedConfluence FastMedContext MedSlowContext NestedPullback WeightedEnsemble)
STRAT_FLAGS=(InpEnableFastBreakout InpEnableMediumBreakout InpEnableSlowBreakout InpEnableFastMedConfluence InpEnableFastMedContext InpEnableMedSlowContext InpEnableNestedPullback InpEnableWeightedEnsemble)

# Canonical: ATR length 14, Fast 1.0, Medium 2.0, Slow 3.5 -- never
# regenerated, only the two non-canonical levels per factor below.
RR=2.0
MAGIC_BASE=26072800
count=0

write_config() {
   local strat_name="$1" strat_flag="$2" factor_label="$3" magic="$4"
   local fast_len="$5" med_len="$6" slow_len="$7"
   local fast_mult="$8" med_mult="$9" slow_mult="${10}"

   local out_file="${OUT_DIR}/stageB_${strat_name}_${factor_label}.ini"
   local report_name="StageB_${strat_name}_${factor_label}"

   {
      echo ";Stage B-lite one-factor-at-a-time robustness: ${strat_name}, factor=${factor_label}, RiskReward=${RR}"
      echo "[Tester]"
      echo "Expert=MultiSpeedZigZagEA"
      echo "Symbol=XAUUSD"
      echo "Period=M5"
      echo "Optimization=0"
      echo "Model=2"
      echo "FromDate=2025.03.01"
      echo "ToDate=2026.07.24"
      echo "ForwardMode=0"
      echo "Deposit=10000"
      echo "Currency=USD"
      echo "Leverage=500"
      echo "ExecutionMode=0"
      echo "OptimizationCriterion=0"
      echo "Visual=0"
      echo "ShutdownTerminal=1"
      echo "Report=${report_name}"
      echo "ReplaceReport=1"
      echo "[TesterInputs]"
      echo "InpShadowOnly=false||false||0||true||N"
      echo "InpAllowLiveExecution=true||false||0||true||N"
      echo "InpAcknowledgeRisk=true||false||0||true||N"
      echo "InpMagic=${magic}||0||0||0||N"
      echo "InpHistoryBars=1500||300||0||3000||N"
      echo "InpFastATRLen=${fast_len}||0||0||0||N"
      echo "InpFastATRMult=${fast_mult}||0||0||0||N"
      echo "InpMedATRLen=${med_len}||0||0||0||N"
      echo "InpMedATRMult=${med_mult}||0||0||0||N"
      echo "InpSlowATRLen=${slow_len}||0||0||0||N"
      echo "InpSlowATRMult=${slow_mult}||0||0||0||N"

      for j in "${!STRAT_FLAGS[@]}"; do
         flag="${STRAT_FLAGS[$j]}"
         if [ "$flag" == "$strat_flag" ]; then
            echo "${flag}=true||false||0||true||N"
         else
            echo "${flag}=false||false||0||true||N"
         fi
      done

      echo "InpMinBarsBetween=3||0||0||0||N"
      echo "InpMinScore=5.0||0||0||0||N"
      if [ "$strat_name" == "FastBreakout" ]; then
         # D019: FastBreakout structurally cannot clear InpMinScore=5.0 in
         # isolation (base score 4.0) -- reuse the research eligibility
         # override so its own Stage B cells are comparable to its own
         # D019 canonical baseline, not silently 0-trade every time.
         echo "InpResearchMinScoreOverride=3.5||0||0||0||N"
         echo "InpAcknowledgeResearchOverride=true||false||0||true||N"
      fi
      echo "InpRiskReward=${RR}||0||0||0||N"
      echo "InpOneOwnedPositionPerSymbol=true||false||0||true||N"
      echo "InpSignalValidityBars=3||0||0||0||N"
      echo "InpFixedLots=0.01||0||0||0||N"
      echo "InpMaxSpreadPoints=80.0||0||0||0||N"
      echo "InpDeviationPoints=30||0||0||0||N"
      echo "InpExitOwnedOpposite=true||false||0||true||N"
      echo "InpMaxPersistentEvents=2000||0||0||0||N"
      echo "InpMarginBufferRatio=1.0||0||0||0||N"
      echo "InpKillSwitchEngaged=false||false||0||true||N"
      echo "InpMaxTradesPerDay=1000||0||0||0||N"
      echo "InpMaxDailyLossAmount=0.0||0||0||0||N"
      echo "InpWriteCSV=true||false||0||true||N"
      echo "InpVerboseLog=true||false||0||true||N"
   } > "$out_file"
   echo "wrote $out_file"
}

for i in "${!STRAT_NAMES[@]}"; do
   strat_name="${STRAT_NAMES[$i]}"
   strat_flag="${STRAT_FLAGS[$i]}"

   # Factor 1: ATR length -- all three speeds move together, multipliers canonical.
   for len in 10 20; do
      count=$((count+1))
      write_config "$strat_name" "$strat_flag" "atrlen_${len}" $((MAGIC_BASE+count)) \
         "$len" "$len" "$len" "1.0" "2.0" "3.5"
   done

   # Factor 2: Fast multiplier -- lengths canonical (14), other multipliers canonical.
   for mult in 0.8 1.2; do
      count=$((count+1))
      mult_label=$(echo "$mult" | tr -d '.')
      write_config "$strat_name" "$strat_flag" "fastmult_${mult_label}" $((MAGIC_BASE+count)) \
         "14" "14" "14" "$mult" "2.0" "3.5"
   done

   # Factor 3: Medium multiplier.
   for mult in 1.6 2.4; do
      count=$((count+1))
      mult_label=$(echo "$mult" | tr -d '.')
      write_config "$strat_name" "$strat_flag" "medmult_${mult_label}" $((MAGIC_BASE+count)) \
         "14" "14" "14" "1.0" "$mult" "3.5"
   done

   # Factor 4: Slow multiplier.
   for mult in 3.0 4.0; do
      count=$((count+1))
      mult_label=$(echo "$mult" | tr -d '.')
      write_config "$strat_name" "$strat_flag" "slowmult_${mult_label}" $((MAGIC_BASE+count)) \
         "14" "14" "14" "1.0" "2.0" "$mult"
   done
done

echo "Generated $count config files"
