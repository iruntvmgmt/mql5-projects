//+------------------------------------------------------------------+
//|                                        QuantBeast/ChallengeMode.mqh|
//|                          XAUUSD Quant Beast EA - Challenge Mode   |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_CHALLENGEMODE_MQH
#define QB_CHALLENGEMODE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

bool QBIsRestorableChallengeState(const ChallengeState &saved, int maxAttempts)
{
   int stage = (int)saved.stage;
   if(stage == (int)CHALLENGE_STAGE_FAILED ||
      stage == (int)CHALLENGE_STAGE_COMPLETE)
      return saved.attempts_this_stage >= 0;

   if(stage < (int)CHALLENGE_STAGE_0 || stage > (int)CHALLENGE_STAGE_4)
      return false;
   if(!MathIsValidNumber(saved.stage_start_equity) ||
      !MathIsValidNumber(saved.stage_peak) ||
      !MathIsValidNumber(saved.profit_locked))
      return false;
   if(saved.stage_start_equity <= 0.0 ||
      saved.stage_peak < saved.stage_start_equity - QB_EPSILON)
      return false;
   if(saved.attempts_this_stage < 0 ||
      saved.attempts_this_stage > MathMax(0, maxAttempts))
      return false;
   if(saved.profit_locked > 0.0 &&
      (saved.profit_locked < saved.stage_start_equity - QB_EPSILON ||
       saved.profit_locked > saved.stage_peak + QB_EPSILON))
      return false;
   return true;
}

bool QBIsExternalCashFlowDealType(ENUM_DEAL_TYPE type)
{
   return type == DEAL_TYPE_BALANCE || type == DEAL_TYPE_CREDIT ||
          type == DEAL_TYPE_CHARGE || type == DEAL_TYPE_CORRECTION ||
          type == DEAL_TYPE_BONUS;
}

//+------------------------------------------------------------------+
//| Challenge Mode - aggressive small-account growth                  |
//+------------------------------------------------------------------+
class CChallengeMode
{
private:
   bool     m_enabled;
   bool     m_acknowledged;

   // Stage targets
   double   m_stageTargets[5];
   double   m_stageRiskPcts[5];
   double   m_maxStageDD;
   int      m_maxAttempts;
   double   m_profitLockPct;
   bool     m_allowPyramiding;

   // Current state
   ChallengeState m_state;
   bool           m_active;
   string         m_failureReason;

public:
   //+------------------------------------------------------------------+
   CChallengeMode()
   {
      m_enabled     = false;
      m_acknowledged = false;
      m_active      = false;
      m_failureReason = "";

      // Default stage targets
      m_stageTargets[0] = 130.0;
      m_stageTargets[1] = 200.0;
      m_stageTargets[2] = 350.0;
      m_stageTargets[3] = 600.0;
      m_stageTargets[4] = 1000.0;

      m_stageRiskPcts[0] = 3.0;
      m_stageRiskPcts[1] = 2.5;
      m_stageRiskPcts[2] = 2.0;
      m_stageRiskPcts[3] = 1.5;
      m_stageRiskPcts[4] = 1.0;

      m_maxStageDD    = 30.0;
      m_maxAttempts   = 3;
      m_profitLockPct = 50.0;
      m_allowPyramiding = false;

      ZeroMemory(m_state);
   }

   //+------------------------------------------------------------------+
   void Init(bool enabled, bool acknowledged,
             double t0, double t1, double t2, double t3, double t4,
             double r0, double r1, double r2, double r3, double r4,
             double maxStageDD, int maxAttempts, double profitLockPct,
             bool allowPyramiding)
   {
      m_enabled     = enabled;
      m_acknowledged = acknowledged;

      m_stageTargets[0] = t0; m_stageTargets[1] = t1;
      m_stageTargets[2] = t2; m_stageTargets[3] = t3;
      m_stageTargets[4] = t4;

      m_stageRiskPcts[0] = r0; m_stageRiskPcts[1] = r1;
      m_stageRiskPcts[2] = r2; m_stageRiskPcts[3] = r3;
      m_stageRiskPcts[4] = r4;

      m_maxStageDD     = maxStageDD;
      m_maxAttempts    = maxAttempts;
      m_profitLockPct  = profitLockPct;
      m_allowPyramiding = allowPyramiding;

      m_active = (m_enabled && m_acknowledged);

      if(m_active)
         QBLogWarn("CHALLENGE MODE ACTIVE - Aggressive risk profile");
   }

   //+------------------------------------------------------------------+
   //| Determine current stage from equity                               |
   //+------------------------------------------------------------------+
   ENUM_CHALLENGE_STAGE DetermineStage(double equity)
   {
      if(!m_active) return CHALLENGE_STAGE_COMPLETE;

      if(equity >= m_stageTargets[4]) return CHALLENGE_STAGE_COMPLETE;
      if(equity >= m_stageTargets[3]) return CHALLENGE_STAGE_4;
      if(equity >= m_stageTargets[2]) return CHALLENGE_STAGE_3;
      if(equity >= m_stageTargets[1]) return CHALLENGE_STAGE_2;
      if(equity >= m_stageTargets[0]) return CHALLENGE_STAGE_1;
      return CHALLENGE_STAGE_0;
   }

   //+------------------------------------------------------------------+
   //| Update challenge state                                            |
   //+------------------------------------------------------------------+
   void Update(double equity, double balance, bool logEvents = true)
   {
      if(!m_active) return;

      string cashflowReason = "";
      int cashflowStatus = ScanExternalCashFlows(TimeCurrent(), cashflowReason, logEvents);
      if(cashflowStatus != 0) return;

      if(m_state.stage_start_equity <= 0 || m_state.risk_percent <= 0)
      {
         m_state.stage = DetermineStage(equity);
         if(m_state.stage == CHALLENGE_STAGE_COMPLETE)
         {
            m_active = false;
            return;
         }
         int initialIdx = (int)m_state.stage;
         m_state.stage_start_equity = equity;
         m_state.stage_peak = equity;
         m_state.stage_target = m_stageTargets[initialIdx];
         m_state.risk_percent = m_stageRiskPcts[initialIdx];
         m_state.max_attempts = m_maxAttempts;
         m_state.attempts_this_stage = 0;
         m_state.profit_locked = 0;
      }

      ENUM_CHALLENGE_STAGE newStage = DetermineStage(equity);

      if(newStage == CHALLENGE_STAGE_COMPLETE)
      {
         m_state.stage = newStage;
         m_state.risk_percent = 0;
         m_active = false;
         QBLogInfo("Challenge target completed; new entries disabled");
         return;
      }

      // Stage changed
      if(newStage != m_state.stage)
      {
         if(newStage > m_state.stage)
         {
            QBLogInfo("Challenge: Stage advanced! " +
                      IntegerToString(m_state.stage) + " -> " + IntegerToString(newStage));
            m_state.stage = newStage;
            m_state.stage_start_equity = equity;
            m_state.stage_peak = equity;
            m_state.attempts_this_stage = 0;
            m_state.profit_locked = 0;

            // Set risk for new stage
            int stageIdx = (int)newStage;
            if(stageIdx >= 0 && stageIdx < 5)
               m_state.risk_percent = m_stageRiskPcts[stageIdx];

            m_state.stage_target = (stageIdx < 5) ? m_stageTargets[stageIdx] : 0;
         }
      }

      // Update peak
      if(equity > m_state.stage_peak)
      {
         m_state.stage_peak = equity;
         m_state.profit_locked = m_state.stage_start_equity +
                                  (equity - m_state.stage_start_equity) * m_profitLockPct / 100.0;
      }

      // Check stage drawdown
      if(m_state.stage_peak > 0)
      {
         double stageDD = (m_state.stage_peak - equity) / m_state.stage_peak * 100.0;
         if(stageDD >= m_maxStageDD)
         {
            if(logEvents)
               QBLogWarn("Challenge: Stage drawdown limit hit! " +
                         DoubleToString(stageDD, 1) + "%");
            // Stage failed - reset to stage start or lower
            m_state.stage = CHALLENGE_STAGE_FAILED;
            m_state.attempts_this_stage++;
            m_state.risk_percent = 0;
            m_active = false;
            if(logEvents)
               QBLogError("Challenge stage failed; manual review/reset required");
            return;
         }
      }

      // Set exposure limits
      m_state.max_exposure = 0.02 * equity / 10.0; // Conservative estimate
      if(m_state.max_exposure < 0.01) m_state.max_exposure = 0.01;
   }

   //+------------------------------------------------------------------+
   //| Get current risk percent for position sizing                      |
   //+------------------------------------------------------------------+
   double GetRiskPercent()
   {
      if(!m_active) return 1.0;
      return m_state.risk_percent;
   }

   bool IsTradeAllowed(double equity, string &reason)
   {
      if(!m_enabled || !m_acknowledged)
      {
         reason = "Challenge mode is not enabled and acknowledged";
         return false;
      }
      if(!m_active || m_state.stage == CHALLENGE_STAGE_FAILED ||
         m_state.stage == CHALLENGE_STAGE_COMPLETE || m_state.risk_percent <= 0)
      {
         reason = "Challenge is inactive, failed, or complete";
         return false;
      }
      // Per-stage attempt lockout: once the configured retries for this stage
      // are exhausted, no further entries until the stage advances (which
      // resets attempts_this_stage to 0).
      if(m_state.max_attempts > 0 && m_state.attempts_this_stage >= m_state.max_attempts)
      {
         reason = "Challenge max attempts for stage exhausted (" +
                  IntegerToString(m_state.attempts_this_stage) + "/" +
                  IntegerToString(m_state.max_attempts) + ")";
         return false;
      }
      if(m_state.profit_locked > 0 && equity < m_state.profit_locked)
      {
         reason = "Challenge profit-lock floor breached";
         return false;
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Pyramiding gate: only when challenge mode is active, pyramiding   |
   //| is configured on, and the candidate add is to a winning, already |
   //| protected position (breakeven or better).                        |
   //+------------------------------------------------------------------+
   bool IsPyramidingAllowed(bool positionIsWinning, bool positionIsProtected) const
   {
      if(!m_active || !m_allowPyramiding) return false;
      return positionIsWinning && positionIsProtected;
   }

   bool AllowsPyramiding() const { return m_active && m_allowPyramiding; }

   // A Challenge floor must protect existing exposure, not merely block the
   // next entry. The caller routes a true result through the central flatten
   // path so broker ownership and retry rules remain centralized.
   bool ConsumeSafetyBreach(double equity, string &reason, bool logEvent = true)
   {
      if(m_state.stage == CHALLENGE_STAGE_FAILED)
      {
         reason = (m_failureReason != "") ? m_failureReason :
                  "Challenge stage drawdown failed";
         return true;
      }

      if(m_active && m_state.profit_locked > 0.0 &&
         equity < m_state.profit_locked - QB_EPSILON)
      {
         m_state.stage = CHALLENGE_STAGE_FAILED;
         m_state.attempts_this_stage++;
         m_state.risk_percent = 0.0;
         m_active = false;
         reason = "Challenge profit-lock floor breached";
         if(logEvent) QBLogError(reason);
         return true;
      }

      reason = "";
      return false;
   }

   bool ApplyExternalCashFlow(double amount, string &reason, bool logEvent = true)
   {
      if(MathAbs(amount) <= QB_EPSILON)
      {
         reason = "";
         return false;
      }

      m_state.stage = CHALLENGE_STAGE_FAILED;
      m_state.risk_percent = 0.0;
      m_active = false;
      m_failureReason = "Challenge external cash flow detected: " +
                        DoubleToString(amount, 2);
      reason = m_failureReason;
      if(logEvent) QBLogError(m_failureReason);
      return true;
   }

   // Returns 0=no cash flow, 1=external flow detected, -1=history unavailable.
   int ScanExternalCashFlows(datetime now, string &reason, bool logEvent = true)
   {
      long nowMsc = (long)now * 1000;
      if(m_state.cashflow_time_msc <= 0)
      {
         // Baseline the initial account funding; only later adjustments
         // contaminate an active Challenge attempt.
         m_state.cashflow_time_msc = nowMsc;
         m_state.cashflow_ticket = 0;
         reason = "";
         return 0;
      }

      datetime from = (datetime)MathMax(0, m_state.cashflow_time_msc / 1000 - 1);
      if(!HistorySelect(from, now))
      {
         m_state.stage = CHALLENGE_STAGE_FAILED;
         m_state.risk_percent = 0.0;
         m_active = false;
         m_failureReason = "Challenge cash-flow history unavailable";
         reason = m_failureReason;
         if(logEvent) QBLogError(m_failureReason);
         return -1;
      }

      double externalAmount = 0.0;
      long newestMsc = m_state.cashflow_time_msc;
      ulong newestTicket = m_state.cashflow_ticket;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long dealMsc = (long)HistoryDealGetInteger(ticket, DEAL_TIME_MSC);
         if(dealMsc < m_state.cashflow_time_msc ||
            (dealMsc == m_state.cashflow_time_msc && ticket <= m_state.cashflow_ticket))
            continue;

         if(dealMsc > newestMsc || (dealMsc == newestMsc && ticket > newestTicket))
         {
            newestMsc = dealMsc;
            newestTicket = ticket;
         }

         ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(QBIsExternalCashFlowDealType(type))
            externalAmount += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }

      m_state.cashflow_time_msc = MathMax(newestMsc, nowMsc);
      m_state.cashflow_ticket = (m_state.cashflow_time_msc == newestMsc) ? newestTicket : 0;
      if(MathAbs(externalAmount) > QB_EPSILON)
         return ApplyExternalCashFlow(externalAmount, reason, logEvent) ? 1 : 0;

      reason = "";
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get state                                                         |
   //+------------------------------------------------------------------+
   ChallengeState GetState()       const { return m_state; }
   bool           IsActive()       const { return m_active; }
   bool           IsEnabled()      const { return m_enabled; }
   bool           IsAcknowledged() const { return m_acknowledged; }

   //+------------------------------------------------------------------+
   //| Restore state from persistence                                    |
   //+------------------------------------------------------------------+
   bool RestoreState(const ChallengeState &saved, bool logFailure = true)
   {
      if(!QBIsRestorableChallengeState(saved, m_maxAttempts))
      {
         ZeroMemory(m_state);
         m_state.stage = CHALLENGE_STAGE_FAILED;
         m_state.risk_percent = 0.0;
         m_active = false;
         m_failureReason = "Invalid persisted Challenge state";
         if(logFailure) QBLogError("Invalid persisted Challenge state rejected");
         return false;
      }

      m_state = saved;
      m_failureReason = "";
      int idx = (int)m_state.stage;
      if(idx >= 0 && idx < 5)
      {
         // Runtime configuration, not persisted values, is authoritative for
         // risk and targets. This prevents stale/corrupt state from silently
         // escalating risk after a restart or configuration change.
         m_state.risk_percent = m_stageRiskPcts[idx];
         m_state.stage_target = m_stageTargets[idx];
         m_state.max_attempts = m_maxAttempts;
      }
      if(m_state.stage == CHALLENGE_STAGE_FAILED ||
         m_state.stage == CHALLENGE_STAGE_COMPLETE)
         m_active = false;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get next stage target                                             |
   //+------------------------------------------------------------------+
   double GetNextStageTarget()
   {
      int idx = (int)m_state.stage;
      if(idx >= 0 && idx < 5) return m_stageTargets[idx];
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get stage info string for dashboard                               |
   //+------------------------------------------------------------------+
   string GetStageInfo()
   {
      if(!m_active) return "Challenge: OFF";
      return "Stage " + IntegerToString(m_state.stage) +
             " | Target: $" + DoubleToString(GetNextStageTarget(), 0) +
             " | Risk: " + DoubleToString(m_state.risk_percent, 1) + "%";
   }
};

#endif // QB_CHALLENGEMODE_MQH
