#!/bin/bash
# Stage A config generator: 8 strategies x 4 RR values = 32 .ini files.
# Uses parallel indexed arrays (not associative arrays) for macOS bash 3.2 compatibility.
set -euo pipefail

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STRAT_NAMES=(FastBreakout MediumBreakout SlowBreakout FastMedConfluence FastMedContext MedSlowContext NestedPullback WeightedEnsemble)
STRAT_FLAGS=(InpEnableFastBreakout InpEnableMediumBreakout InpEnableSlowBreakout InpEnableFastMedConfluence InpEnableFastMedContext InpEnableMedSlowContext InpEnableNestedPullback InpEnableWeightedEnsemble)

RR_VALUES=(1.0 1.5 2.0 3.0)

MAGIC_BASE=26072600

count=0
for i in "${!STRAT_NAMES[@]}"; do
   strat_name="${STRAT_NAMES[$i]}"
   strat_flag="${STRAT_FLAGS[$i]}"

   for rr in "${RR_VALUES[@]}"; do
      count=$((count+1))
      rr_label=$(echo "$rr" | tr -d '.')
      report_name="StageA_${strat_name}_RR${rr_label}"
      out_file="${OUT_DIR}/stageA_${strat_name}_RR${rr_label}.ini"
      magic=$((MAGIC_BASE + count))

      {
         echo ";Edge Discovery Sprint Stage A: ${strat_name} only, RiskReward=${rr}"
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
         echo "InpFastATRLen=14||0||0||0||N"
         echo "InpFastATRMult=1.0||0||0||0||N"
         echo "InpMedATRLen=14||0||0||0||N"
         echo "InpMedATRMult=2.0||0||0||0||N"
         echo "InpSlowATRLen=14||0||0||0||N"
         echo "InpSlowATRMult=3.5||0||0||0||N"

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
         echo "InpRiskReward=${rr}||0||0||0||N"
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
   done
done

echo "Generated $count config files"
