//+------------------------------------------------------------------+
//|                                           QuantBeast/RiskEngine.mqh|
//|                          XAUUSD Quant Beast EA - Centralized Risk |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_RISKENGINE_MQH
#define QB_RISKENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/MathUtils.mqh"
#include "../Data/MarketData.mqh"
#include "../Portfolio/ExposureManager.mqh"
#include "PositionSizer.mqh"

//+------------------------------------------------------------------+
//| Risk Engine - centralized pre-trade risk validation               |
//+------------------------------------------------------------------+
class CRiskEngine
{
private:
   CSymbolAdapter*   m_adapter;
   CPositionSizer*   m_sizer;

   // Trade-level limits
   double   m_maxRiskPerTradePct;
   double   m_minRewardRisk;
   int      m_minStopPoints;
   int      m_maxStopPoints;
   int      m_maxHoldingMinutes;
   int      m_maxPendingMinutes;

   // Account-level limits
   double   m_dailyLossLimitPct;
   double   m_weeklyLossLimitPct;
   double   m_maxDrawdownPct;
   int      m_maxConsecLosses;
   double   m_minMarginLevelPct;
   double   m_emergencyEquityFloor;
   int      m_maxPositions;
   int      m_maxPendingOrders;
   double   m_maxTotalExposureLots;
   CExposureManager m_exposure;     // Owns the aggregate-exposure limit policy

   // Strategy-level limits
   int      m_maxPerStrategy;       // Max concurrent per strategy
   int      m_maxDailyPerStrategy;  // Max daily trades per strategy

   // State
   double   m_dailyStartEquity;
   double   m_weeklyStartEquity;
   datetime m_dailyPeriodStart;
   datetime m_weeklyPeriodStart;
   double   m_highWaterMark;
   int      m_consecLosses;
   double   m_currentDrawdownPct;
   bool     m_dailyLockActive;
   bool     m_weeklyLockActive;
   bool     m_drawdownLockActive;
   bool     m_entryKill;

public:
   //+------------------------------------------------------------------+
   CRiskEngine()
   {
      m_adapter     = NULL;
      m_sizer       = NULL;
      m_maxRiskPerTradePct = 2.0;
      m_minRewardRisk      = 1.0;
      m_minStopPoints      = 50;
      m_maxStopPoints      = 1000;
      m_maxHoldingMinutes  = 1440;
      m_maxPendingMinutes  = 60;
      m_dailyLossLimitPct  = 5.0;
      m_weeklyLossLimitPct = 10.0;
      m_maxDrawdownPct     = 20.0;
      m_maxConsecLosses    = 5;
      m_minMarginLevelPct  = 200.0;
      m_emergencyEquityFloor = 50.0;
      m_maxPositions       = 3;
      m_maxPendingOrders   = 2;
      m_maxTotalExposureLots = 2.0;
      m_maxPerStrategy     = 2;
      m_maxDailyPerStrategy = 10;
      m_exposure.Init(m_maxTotalExposureLots);

      ResetState();
   }

   //+------------------------------------------------------------------+
   void Init(CSymbolAdapter &adapter, CPositionSizer &sizer,
             double maxRiskPerTradePct, double minRR, int minStopPts, int maxStopPts,
             int maxHoldingMin, int maxPendingMin,
             double dailyLossPct, double weeklyLossPct, double maxDDPct,
             int maxConsecLoss, double minMarginPct, double emergFloor,
             int maxPos, int maxPending, double maxExposure,
             int maxPerStrat, int maxDailyPerStrat)
   {
      m_adapter             = &adapter;
      m_sizer               = &sizer;
      m_maxRiskPerTradePct  = maxRiskPerTradePct;
      m_minRewardRisk       = minRR;
      m_minStopPoints       = minStopPts;
      m_maxStopPoints       = maxStopPts;
      m_maxHoldingMinutes   = maxHoldingMin;
      m_maxPendingMinutes   = maxPendingMin;
      m_dailyLossLimitPct   = dailyLossPct;
      m_weeklyLossLimitPct  = weeklyLossPct;
      m_maxDrawdownPct      = maxDDPct;
      m_maxConsecLosses     = maxConsecLoss;
      m_minMarginLevelPct   = minMarginPct;
      m_emergencyEquityFloor = emergFloor;
      m_maxPositions        = maxPos;
      m_maxPendingOrders    = maxPending;
      m_maxTotalExposureLots = maxExposure;
      m_exposure.Init(maxExposure);
      m_maxPerStrategy      = maxPerStrat;
      m_maxDailyPerStrategy = maxDailyPerStrat;
   }

   //+------------------------------------------------------------------+
   void ResetState()
   {
      m_dailyStartEquity   = 0;
      m_weeklyStartEquity  = 0;
      m_dailyPeriodStart   = 0;
      m_weeklyPeriodStart  = 0;
      m_highWaterMark      = 0;
      m_consecLosses       = 0;
      m_currentDrawdownPct = 0;
      m_dailyLockActive    = false;
      m_weeklyLockActive   = false;
      m_drawdownLockActive = false;
      m_entryKill          = false;
   }

   //+------------------------------------------------------------------+
   //| Initialize daily/weekly tracking values                           |
   //+------------------------------------------------------------------+
   void InitDailyTracking(double currentEquity,
                          double savedDailyStart, datetime savedDailyDate,
                          double savedWeeklyStart, datetime savedWeeklyDate,
                          double savedHWM, bool savedDailyLock,
                          bool savedWeeklyLock, bool savedDrawdownLock,
                          int savedConsecLosses)
   {
      datetime now = TimeCurrent();

      // Set HWM
      if(savedHWM > 0)
         m_highWaterMark = savedHWM;
      else
         m_highWaterMark = currentEquity;

      m_dailyPeriodStart = GetDayStart(now);
      bool sameDay = (savedDailyDate > 0 &&
                      GetDayStart(savedDailyDate) == m_dailyPeriodStart);
      m_dailyStartEquity = (sameDay && savedDailyStart > 0) ?
                           savedDailyStart : currentEquity;
      m_dailyLockActive = sameDay && savedDailyLock;

      m_weeklyPeriodStart = GetWeekStart(now);
      bool sameWeek = (savedWeeklyDate > 0 &&
                       GetWeekStart(savedWeeklyDate) == m_weeklyPeriodStart);
      m_weeklyStartEquity = (sameWeek && savedWeeklyStart > 0) ?
                            savedWeeklyStart : currentEquity;
      m_weeklyLockActive = sameWeek && savedWeeklyLock;
      m_drawdownLockActive = savedDrawdownLock;
      m_consecLosses = MathMax(0, savedConsecLosses);

      QBLogInfo("Risk tracking: dailyStart=" + DoubleToString(m_dailyStartEquity, 2) +
                " weeklyStart=" + DoubleToString(m_weeklyStartEquity, 2) +
                " HWM=" + DoubleToString(m_highWaterMark, 2));
   }

   void UpdateEquityState(double equity, datetime now)
   {
      datetime dayStart = GetDayStart(now);
      if(m_dailyPeriodStart == 0 || dayStart != m_dailyPeriodStart)
      {
         m_dailyPeriodStart = dayStart;
         m_dailyStartEquity = equity;
         m_dailyLockActive = false;
         QBLogInfo("Daily risk period reset at equity " + DoubleToString(equity, 2));
      }

      datetime weekStart = GetWeekStart(now);
      if(m_weeklyPeriodStart == 0 || weekStart != m_weeklyPeriodStart)
      {
         m_weeklyPeriodStart = weekStart;
         m_weeklyStartEquity = equity;
         m_weeklyLockActive = false;
         QBLogInfo("Weekly risk period reset at equity " + DoubleToString(equity, 2));
      }

      if(equity > m_highWaterMark) m_highWaterMark = equity;
      m_currentDrawdownPct = (m_highWaterMark > 0) ?
                             MathMax(0, (m_highWaterMark - equity) / m_highWaterMark * 100.0) : 0;

      if(m_dailyStartEquity > 0 &&
         (m_dailyStartEquity - equity) / m_dailyStartEquity * 100.0 >= m_dailyLossLimitPct)
         ActivateDailyLock();
      if(m_weeklyStartEquity > 0 &&
         (m_weeklyStartEquity - equity) / m_weeklyStartEquity * 100.0 >= m_weeklyLossLimitPct)
         ActivateWeeklyLock();
      if(m_currentDrawdownPct >= m_maxDrawdownPct)
         ActivateDrawdownLock();
   }

   //+------------------------------------------------------------------+
   //| Main pre-trade validation - returns true if trade can proceed     |
   //+------------------------------------------------------------------+
   bool ValidateTrade(const StrategySignal &signal, double equity,
                       double balance, double marginLevel,
                       int currentPositions, int currentPending,
                       double totalExposure, int stratPosCount,
                       int stratTradesToday,
                       string &rejectReason)
   {
      UpdateEquityState(equity, TimeCurrent());

      // --- Kill switch checks ---
      if(m_entryKill)
         { rejectReason = "Entry kill active"; return false; }

      if(m_dailyLockActive)
         { rejectReason = "Daily loss lock active"; return false; }

      if(m_weeklyLockActive)
         { rejectReason = "Weekly loss lock active"; return false; }

      if(m_drawdownLockActive)
         { rejectReason = "Drawdown lock active"; return false; }

      // --- Account-level checks ---
      // Emergency equity floor
      if(equity < m_emergencyEquityFloor)
      {
         rejectReason = "Emergency equity floor breached: " +
                        DoubleToString(equity, 2) + " < " + DoubleToString(m_emergencyEquityFloor, 2);
         return false;
      }

      // Margin level
      if(marginLevel > 0 && marginLevel < m_minMarginLevelPct)
      {
         rejectReason = "Margin level too low: " + DoubleToString(marginLevel, 1) + "%";
         return false;
      }

      // Daily loss
      double dailyPnL = equity - m_dailyStartEquity;
      double dailyLossPct = (m_dailyStartEquity > 0) ? -dailyPnL / m_dailyStartEquity * 100.0 : 0;
      if(dailyLossPct >= m_dailyLossLimitPct)
      {
         rejectReason = "Daily loss limit: " + DoubleToString(dailyLossPct, 1) + "% >= " +
                        DoubleToString(m_dailyLossLimitPct, 1) + "%";
         ActivateDailyLock();
         return false;
      }

      // Weekly loss
      double weeklyPnL = equity - m_weeklyStartEquity;
      double weeklyLossPct = (m_weeklyStartEquity > 0) ? -weeklyPnL / m_weeklyStartEquity * 100.0 : 0;
      if(weeklyLossPct >= m_weeklyLossLimitPct)
      {
         rejectReason = "Weekly loss limit: " + DoubleToString(weeklyLossPct, 1) + "% >= " +
                        DoubleToString(m_weeklyLossLimitPct, 1) + "%";
         ActivateWeeklyLock();
         return false;
      }

      // Drawdown from HWM
      if(m_highWaterMark > 0)
      {
         double ddPct = (m_highWaterMark - equity) / m_highWaterMark * 100.0;
         if(ddPct >= m_maxDrawdownPct)
         {
            rejectReason = "Drawdown limit: " + DoubleToString(ddPct, 1) + "% >= " +
                           DoubleToString(m_maxDrawdownPct, 1) + "%";
            ActivateDrawdownLock();
            return false;
         }
         m_currentDrawdownPct = ddPct;
      }

      // Consecutive losses
      if(m_consecLosses >= m_maxConsecLosses)
      {
         rejectReason = "Max consecutive losses: " + IntegerToString(m_consecLosses);
         return false;
      }

      // Max positions
      if(currentPositions >= m_maxPositions)
      {
         rejectReason = "Max positions: " + IntegerToString(currentPositions) +
                        " >= " + IntegerToString(m_maxPositions);
         return false;
      }

      // Max pending
      if(currentPending >= m_maxPendingOrders)
      {
         rejectReason = "Max pending orders: " + IntegerToString(currentPending);
         return false;
      }

      // Max total exposure (limit policy owned by CExposureManager)
      if(m_exposure.AtCapacity(totalExposure))
      {
         rejectReason = "Max exposure: " + DoubleToString(totalExposure, 2) + " lots";
         return false;
      }

      // --- Strategy-level checks ---
      if(stratPosCount >= m_maxPerStrategy)
      {
         rejectReason = "Max per-strategy positions: " + IntegerToString(stratPosCount);
         return false;
      }

      if(stratTradesToday >= m_maxDailyPerStrategy)
      {
         rejectReason = "Max daily trades for strategy: " + IntegerToString(stratTradesToday);
         return false;
      }

      // --- Trade-level checks ---
      bool validGeometry = (signal.direction == ORDER_TYPE_BUY &&
                            signal.proposed_stop < signal.proposed_entry &&
                            signal.proposed_target > signal.proposed_entry) ||
                           (signal.direction == ORDER_TYPE_SELL &&
                            signal.proposed_stop > signal.proposed_entry &&
                            signal.proposed_target < signal.proposed_entry);
      if(!validGeometry)
      {
         rejectReason = "Invalid entry/stop/target geometry for direction";
         return false;
      }

      double stopDist = MathAbs(signal.proposed_entry - signal.proposed_stop);
      double stopDistPts = stopDist / m_adapter.Point();

      if(stopDistPts < m_minStopPoints)
      {
         rejectReason = "Stop too close: " + DoubleToString(stopDistPts, 1) +
                        " < " + IntegerToString(m_minStopPoints);
         return false;
      }

      if(stopDistPts > m_maxStopPoints)
      {
         rejectReason = "Stop too far: " + DoubleToString(stopDistPts, 1) +
                        " > " + IntegerToString(m_maxStopPoints);
         return false;
      }

      if(signal.expected_reward_r < m_minRewardRisk)
      {
         rejectReason = "Reward:Risk too low: " + DoubleToString(signal.expected_reward_r, 2) +
                        " < " + DoubleToString(m_minRewardRisk, 2);
         return false;
      }

      // Confidence threshold
      if(signal.confidence < 0.3)
      {
         rejectReason = "Signal confidence too low: " + DoubleToString(signal.confidence, 2);
         return false;
      }

      return true;
   }

   bool ValidateSizedTrade(const StrategySignal &signal, double lots,
                           double equity, double totalExposure,
                           string &rejectReason)
   {
      if(lots <= 0 || equity <= 0)
      {
         rejectReason = "Invalid lots or equity";
         return false;
      }

      double actualRisk = m_sizer.EstimateRisk(lots, signal.proposed_entry,
                                                signal.proposed_stop);
      if(actualRisk <= 0)
      {
         rejectReason = "Unable to calculate actual broker risk";
         return false;
      }

      double riskPct = actualRisk / equity * 100.0;
      if(riskPct > m_maxRiskPerTradePct + 0.0001)
      {
         rejectReason = "Actual risk " + DoubleToString(riskPct, 2) +
                        "% exceeds max " + DoubleToString(m_maxRiskPerTradePct, 2) + "%";
         return false;
      }

      if(m_exposure.WouldExceed(totalExposure, lots))
      {
         rejectReason = "Order would exceed total exposure: " +
                        DoubleToString(totalExposure + lots, 2) + " lots";
         return false;
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update after a trade closes                                       |
   //+------------------------------------------------------------------+
   void UpdateAfterClose(double pnl, double currentEquity)
   {
      if(pnl < 0)
         m_consecLosses++;
      else
         m_consecLosses = 0;

      // Update HWM
      if(currentEquity > m_highWaterMark)
         m_highWaterMark = currentEquity;
   }

   //+------------------------------------------------------------------+
   //| Lock/unlock functions                                             |
   //+------------------------------------------------------------------+
   void ActivateDailyLock()
   {
      if(m_dailyLockActive) return;
      m_dailyLockActive = true;
      QBLogWarn("DAILY LOSS LOCK ACTIVATED");
   }

   void ActivateWeeklyLock()
   {
      if(m_weeklyLockActive) return;
      m_weeklyLockActive = true;
      QBLogWarn("WEEKLY LOSS LOCK ACTIVATED");
   }

   void ActivateDrawdownLock()
   {
      if(m_drawdownLockActive) return;
      m_drawdownLockActive = true;
      QBLogWarn("DRAWDOWN LOCK ACTIVATED");
   }

   void SetEntryKill(bool kill) { m_entryKill = kill; }
   bool IsEntryKill()     const { return m_entryKill; }
   bool IsDailyLock()     const { return m_dailyLockActive; }
   bool IsWeeklyLock()    const { return m_weeklyLockActive; }
   bool IsDrawdownLock()  const { return m_drawdownLockActive; }

   double GetDailyStartEquity()  const { return m_dailyStartEquity; }
   double GetWeeklyStartEquity() const { return m_weeklyStartEquity; }
   datetime GetDailyPeriodStart() const { return m_dailyPeriodStart; }
   datetime GetWeeklyPeriodStart() const { return m_weeklyPeriodStart; }
   double GetHighWaterMark()     const { return m_highWaterMark; }
   double GetCurrentDrawdown()   const { return m_currentDrawdownPct; }
   int    GetConsecLosses()      const { return m_consecLosses; }

   // For state persistence
   void SetDailyStartEquity(double eq)  { m_dailyStartEquity = eq; }
   void SetWeeklyStartEquity(double eq) { m_weeklyStartEquity = eq; }
   void SetHighWaterMark(double eq)     { m_highWaterMark = eq; }
};

#endif // QB_RISKENGINE_MQH
