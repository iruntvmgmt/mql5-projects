//+------------------------------------------------------------------+
//| QuantBeastRestartProbe.mq5 - non-trading persistence harness     |
//+------------------------------------------------------------------+
#property strict
#property version "1.000"

#include <QuantBeast/Core/StateStore.mqh>

input int InpProbePhase = 1; // 1=seed persisted state, 2=verify and clear

bool g_probePassed = false;

int OnInit()
{
   if(InpProbePhase == 1)
   {
      ClearAllState();
      SaveStateVersion();
      GV_WriteDatetime(GV_DAILY_DATE, D'2026.07.15 00:00');
      GV_WriteDouble(GV_DAILY_START_EQUITY, 123.45);
      GV_WriteDouble(GV_DAILY_LOCK, 1.0);
      GV_WriteDouble(GV_CONSEC_LOSSES, 4.0);

      ChallengeState challenge;
      ZeroMemory(challenge);
      challenge.stage = CHALLENGE_STAGE_1;
      challenge.stage_start_equity = 130.0;
      challenge.stage_peak = 160.0;
      challenge.attempts_this_stage = 1;
      challenge.stage_target = 200.0;
      challenge.risk_percent = 2.5;
      challenge.profit_locked = 145.0;
      challenge.max_exposure = 0.25;
      challenge.cashflow_time_msc = 1784123456789;
      challenge.cashflow_ticket = 987654321;
      SaveChallengeState(challenge);

      KillSwitchState kill;
      ZeroMemory(kill);
      kill.entry_kill = true;
      kill.flatten_all = true;
      kill.strategy_kill[QB_STRAT_IDX_TP] = true;
      kill.emergency = true;
      SaveKillSwitchState(kill);
      GlobalVariablesFlush();

      g_probePassed = LoadStateVersion() == QB_STATE_VERSION_NUM;
      Print("QB_RESTART_PROBE PHASE1 ", g_probePassed ? "PASS" : "FAIL",
            " schema=", QB_STATE_VERSION_NUM);
      return g_probePassed ? INIT_SUCCEEDED : INIT_FAILED;
   }

   ChallengeState challenge;
   ZeroMemory(challenge);
   KillSwitchState kill;
   LoadKillSwitchState(kill);
   bool challengeLoaded = LoadChallengeState(challenge);
   g_probePassed = LoadStateVersion() == QB_STATE_VERSION_NUM &&
                   MathAbs(GV_ReadDouble(GV_DAILY_START_EQUITY, 0.0) - 123.45) < 1e-8 &&
                   GV_ReadDouble(GV_DAILY_LOCK, 0.0) > 0.5 &&
                   (int)GV_ReadDouble(GV_CONSEC_LOSSES, 0.0) == 4 &&
                   challengeLoaded && challenge.stage == CHALLENGE_STAGE_1 &&
                   challenge.cashflow_time_msc == 1784123456789 &&
                   challenge.cashflow_ticket == 987654321 &&
                   kill.entry_kill && kill.flatten_all && kill.emergency &&
                   kill.strategy_kill[QB_STRAT_IDX_TP];

   Print("QB_RESTART_PROBE PHASE2 ", g_probePassed ? "PASS" : "FAIL",
         " schema=", LoadStateVersion(),
         " cashflow_msc=", challenge.cashflow_time_msc,
         " emergency=", kill.emergency);
   ClearAllState();
   GlobalVariablesFlush();
   return g_probePassed ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick() {}

double OnTester()
{
   return g_probePassed ? 1.0 : -1.0;
}
