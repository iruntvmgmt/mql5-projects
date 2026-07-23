//+------------------------------------------------------------------+
//|                                           QuantBeast/StateStore.mqh |
//|                          XAUUSD Quant Beast EA - State Persistence|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_STATESTORE_MQH
#define QB_STATESTORE_MQH

#include "Types.mqh"
#include "Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Global Variable Names                                             |
//+------------------------------------------------------------------+
#define GV_PREFIX              "QB_"
#define GV_DAILY_START_EQUITY  GV_PREFIX "DailyStartEquity"
#define GV_DAILY_DATE          GV_PREFIX "DailyDate"
#define GV_DAILY_PNL           GV_PREFIX "DailyPnL"
#define GV_WEEKLY_START_EQUITY GV_PREFIX "WeeklyStartEquity"
#define GV_WEEKLY_DATE         GV_PREFIX "WeeklyDate"
#define GV_HIGH_WATER_MARK     GV_PREFIX "HighWaterMark"
#define GV_DAILY_LOCK          GV_PREFIX "DailyLock"
#define GV_WEEKLY_LOCK         GV_PREFIX "WeeklyLock"
#define GV_DRAWDOWN_LOCK       GV_PREFIX "DrawdownLock"
#define GV_CONSEC_LOSSES       GV_PREFIX "ConsecLosses"
#define GV_BROKER_FAILURES     GV_PREFIX "BrokerFailures"
#define GV_STRAT_TRADE_DAY     GV_PREFIX "StratTradeDay"
#define GV_STRAT_TRADES_BO     GV_PREFIX "StratTradesBO"
#define GV_STRAT_TRADES_FBO    GV_PREFIX "StratTradesFBO"
#define GV_STRAT_TRADES_TP     GV_PREFIX "StratTradesTP"
#define GV_STRAT_TRADES_MR     GV_PREFIX "StratTradesMR"
#define GV_STRAT_TRADES_TPV2   GV_PREFIX "StratTradesTPV2"
#define GV_ARB_LAST_ACCEPT     GV_PREFIX "ArbLastAccept"
#define GV_ARB_RECENT_COUNT    GV_PREFIX "ArbRecentCount"
#define GV_ARB_RECENT_HASH     GV_PREFIX "ArbRecentHash"
#define GV_ARB_RECENT_TIME     GV_PREFIX "ArbRecentTime"
#define GV_CHALLENGE_STAGE     GV_PREFIX "ChallengeStage"
#define GV_STAGE_START_EQUITY  GV_PREFIX "StageStartEquity"
#define GV_STAGE_PEAK          GV_PREFIX "StagePeak"
#define GV_STAGE_ATTEMPTS      GV_PREFIX "StageAttempts"
#define GV_STAGE_TARGET        GV_PREFIX "StageTarget"
#define GV_STAGE_RISK          GV_PREFIX "StageRisk"
#define GV_STAGE_PROFIT_LOCK   GV_PREFIX "StageProfitLock"
#define GV_STAGE_MAX_EXPOSURE  GV_PREFIX "StageMaxExposure"
#define GV_CHAL_CASHFLOW_MSC   GV_PREFIX "ChalCashflowMsc"
#define GV_CHAL_CASHFLOW_TICKET GV_PREFIX "ChalCashflowTicket"
#define GV_KILL_ENTRIES        GV_PREFIX "KillEntries"
#define GV_KILL_SYMBOL         GV_PREFIX "KillSymbol"
#define GV_KILL_CANCEL         GV_PREFIX "KillCancel"
#define GV_KILL_FLATTEN        GV_PREFIX "KillFlatten"
#define GV_KILL_STRAT_BO       GV_PREFIX "KillBO"
#define GV_KILL_STRAT_FBO      GV_PREFIX "KillFBO"
#define GV_KILL_STRAT_TP       GV_PREFIX "KillTP"
#define GV_KILL_STRAT_MR       GV_PREFIX "KillMR"
#define GV_KILL_STRAT_TPV2     GV_PREFIX "KillTPV2"
#define GV_EMERGENCY           GV_PREFIX "Emergency"
#define GV_STATE_VERSION       GV_PREFIX "StateVer"

#define QB_STATE_VERSION_NUM   4
#define QB_ARB_PERSIST_MAX     20

string g_QBStateScopeSymbol = "";

void SetStateScopeSymbol(const string symbol)
{
   g_QBStateScopeSymbol = symbol;
}

string GetStateScopeSymbol()
{
   return (g_QBStateScopeSymbol == "") ? _Symbol : g_QBStateScopeSymbol;
}

string GV_ScopedName(string name)
{
   return name + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
          GetStateScopeSymbol();
}

string GV_TestScopedName(string name, long login, string symbol)
{
   return name + "_" + IntegerToString(login) + "_" + symbol;
}

//+------------------------------------------------------------------+
//| Write a global variable of type double                            |
//+------------------------------------------------------------------+
void GV_WriteDouble(string name, double value)
{
   GlobalVariableSet(GV_ScopedName(name), value);
}

//+------------------------------------------------------------------+
//| Read a global variable of type double                             |
//+------------------------------------------------------------------+
double GV_ReadDouble(string name, double defaultVal = 0.0)
{
   string key = GV_ScopedName(name);
   if(!GlobalVariableCheck(key))
      return defaultVal;
   return GlobalVariableGet(key);
}

//+------------------------------------------------------------------+
//| Write a global variable of type datetime (stored as double)       |
//+------------------------------------------------------------------+
void GV_WriteDatetime(string name, datetime value)
{
   GlobalVariableSet(GV_ScopedName(name), (double)value);
}

//+------------------------------------------------------------------+
//| Read a global variable as datetime                                |
//+------------------------------------------------------------------+
datetime GV_ReadDatetime(string name, datetime defaultVal = 0)
{
   string key = GV_ScopedName(name);
   if(!GlobalVariableCheck(key))
      return defaultVal;
   return (datetime)GlobalVariableGet(key);
}

//+------------------------------------------------------------------+
//| Save daily risk state                                             |
//+------------------------------------------------------------------+
void SaveDailyRiskState(const DailyRiskState &state)
{
   GV_WriteDatetime(GV_DAILY_DATE, state.date);
   GV_WriteDouble(GV_DAILY_START_EQUITY, state.starting_equity);
   GV_WriteDouble(GV_DAILY_PNL, state.daily_pnl);
   GV_WriteDatetime(GV_WEEKLY_DATE, GetWeekStart(state.date));

   QBLogDebug("Daily risk state saved: date=" + FormatTime(state.date) +
              " startEq=" + DoubleToString(state.starting_equity, 2));
}

//+------------------------------------------------------------------+
//| Load daily risk state                                             |
//+------------------------------------------------------------------+
bool LoadDailyRiskState(DailyRiskState &state)
{
   datetime savedDate = GV_ReadDatetime(GV_DAILY_DATE, 0);
   if(savedDate == 0)
   {
      QBLogDebug("No persisted daily risk state found");
      return false;
   }

   state.date = savedDate;
   state.starting_equity = GV_ReadDouble(GV_DAILY_START_EQUITY, 0);
   state.daily_pnl = GV_ReadDouble(GV_DAILY_PNL, 0);

   datetime today = GetDayStart(TimeCurrent());
   if(!IsSameDay(state.date, today))
   {
      QBLogInfo("Persisted state is from different day - resetting");
      return false;
   }

   QBLogInfo("Daily risk state restored: startEq=" +
             DoubleToString(state.starting_equity, 2) +
             " pnl=" + DoubleToString(state.daily_pnl, 2));
   return true;
}

//+------------------------------------------------------------------+
//| Save high-water mark                                              |
//+------------------------------------------------------------------+
void SaveHighWaterMark(double equity)
{
   double current = GV_ReadDouble(GV_HIGH_WATER_MARK, 0);
   if(equity > current)
   {
      GV_WriteDouble(GV_HIGH_WATER_MARK, equity);
      QBLogDebug("New high-water mark: " + DoubleToString(equity, 2));
   }
}

//+------------------------------------------------------------------+
//| Load high-water mark                                              |
//+------------------------------------------------------------------+
double LoadHighWaterMark()
{
   return GV_ReadDouble(GV_HIGH_WATER_MARK, AccountInfoDouble(ACCOUNT_BALANCE));
}

//+------------------------------------------------------------------+
//| Save challenge state                                              |
//+------------------------------------------------------------------+
void SaveChallengeState(const ChallengeState &state)
{
   GV_WriteDouble(GV_CHALLENGE_STAGE, (double)state.stage);
   GV_WriteDouble(GV_STAGE_START_EQUITY, state.stage_start_equity);
   GV_WriteDouble(GV_STAGE_PEAK, state.stage_peak);
   GV_WriteDouble(GV_STAGE_ATTEMPTS, (double)state.attempts_this_stage);
   GV_WriteDouble(GV_STAGE_TARGET, state.stage_target);
   GV_WriteDouble(GV_STAGE_RISK, state.risk_percent);
   GV_WriteDouble(GV_STAGE_PROFIT_LOCK, state.profit_locked);
   GV_WriteDouble(GV_STAGE_MAX_EXPOSURE, state.max_exposure);
   GV_WriteDouble(GV_CHAL_CASHFLOW_MSC, (double)state.cashflow_time_msc);
   GV_WriteDouble(GV_CHAL_CASHFLOW_TICKET, (double)state.cashflow_ticket);
   QBLogDebug("Challenge state saved: stage=" + IntegerToString(state.stage));
}

//+------------------------------------------------------------------+
//| Load challenge state                                              |
//+------------------------------------------------------------------+
bool LoadChallengeState(ChallengeState &state)
{
   double savedStage = GV_ReadDouble(GV_CHALLENGE_STAGE, -1);
   if(savedStage < 0) return false;

   state.stage = (ENUM_CHALLENGE_STAGE)(int)savedStage;
   state.stage_start_equity = GV_ReadDouble(GV_STAGE_START_EQUITY, 0);
   state.stage_peak = GV_ReadDouble(GV_STAGE_PEAK, 0);
   state.attempts_this_stage = (int)GV_ReadDouble(GV_STAGE_ATTEMPTS, 0);
   state.stage_target = GV_ReadDouble(GV_STAGE_TARGET, 0);
   state.risk_percent = GV_ReadDouble(GV_STAGE_RISK, 0);
   state.profit_locked = GV_ReadDouble(GV_STAGE_PROFIT_LOCK, 0);
   state.max_exposure = GV_ReadDouble(GV_STAGE_MAX_EXPOSURE, 0);
   state.cashflow_time_msc = (long)GV_ReadDouble(GV_CHAL_CASHFLOW_MSC, 0);
   state.cashflow_ticket = (ulong)GV_ReadDouble(GV_CHAL_CASHFLOW_TICKET, 0);
   return true;
}

//+------------------------------------------------------------------+
//| Save kill switch state                                            |
//+------------------------------------------------------------------+
void SaveKillSwitchState(const KillSwitchState &state)
{
   GV_WriteDouble(GV_KILL_ENTRIES, state.entry_kill ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_SYMBOL, state.symbol_kill ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_CANCEL, state.cancel_all ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_FLATTEN, state.flatten_all ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_STRAT_BO, state.strategy_kill[QB_STRAT_IDX_BO] ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_STRAT_FBO, state.strategy_kill[QB_STRAT_IDX_FBO] ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_STRAT_TP, state.strategy_kill[QB_STRAT_IDX_TP] ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_STRAT_MR, state.strategy_kill[QB_STRAT_IDX_MR] ? 1.0 : 0.0);
   GV_WriteDouble(GV_KILL_STRAT_TPV2, state.strategy_kill[QB_STRAT_IDX_TPV2] ? 1.0 : 0.0);
   GV_WriteDouble(GV_EMERGENCY, state.emergency ? 1.0 : 0.0);
}

//+------------------------------------------------------------------+
//| Load kill switch state                                            |
//+------------------------------------------------------------------+
void LoadKillSwitchState(KillSwitchState &state)
{
   ZeroMemory(state);
   state.entry_kill = GV_ReadDouble(GV_KILL_ENTRIES, 0) > 0.5;
   state.symbol_kill = GV_ReadDouble(GV_KILL_SYMBOL, 0) > 0.5;
   state.cancel_all = GV_ReadDouble(GV_KILL_CANCEL, 0) > 0.5;
   state.flatten_all = GV_ReadDouble(GV_KILL_FLATTEN, 0) > 0.5;
   state.strategy_kill[QB_STRAT_IDX_BO]  = GV_ReadDouble(GV_KILL_STRAT_BO, 0) > 0.5;
   state.strategy_kill[QB_STRAT_IDX_FBO] = GV_ReadDouble(GV_KILL_STRAT_FBO, 0) > 0.5;
   state.strategy_kill[QB_STRAT_IDX_TP]  = GV_ReadDouble(GV_KILL_STRAT_TP, 0) > 0.5;
   state.strategy_kill[QB_STRAT_IDX_MR]  = GV_ReadDouble(GV_KILL_STRAT_MR, 0) > 0.5;
   state.strategy_kill[QB_STRAT_IDX_TPV2] = GV_ReadDouble(GV_KILL_STRAT_TPV2, 0) > 0.5;
   state.emergency = GV_ReadDouble(GV_EMERGENCY, 0) > 0.5;
   if(state.emergency) state.emergency_reason = "Restored persisted emergency lock";
}

void SaveStrategyTradeCounters(datetime tradeDay, const int &counts[])
{
   GV_WriteDatetime(GV_STRAT_TRADE_DAY, tradeDay);
   GV_WriteDouble(GV_STRAT_TRADES_BO,  (double)counts[QB_STRAT_IDX_BO]);
   GV_WriteDouble(GV_STRAT_TRADES_FBO, (double)counts[QB_STRAT_IDX_FBO]);
   GV_WriteDouble(GV_STRAT_TRADES_TP,  (double)counts[QB_STRAT_IDX_TP]);
   GV_WriteDouble(GV_STRAT_TRADES_MR,  (double)counts[QB_STRAT_IDX_MR]);
   GV_WriteDouble(GV_STRAT_TRADES_TPV2, (double)counts[QB_STRAT_IDX_TPV2]);
}

bool LoadStrategyTradeCounters(datetime &tradeDay, int &counts[])
{
   tradeDay = GV_ReadDatetime(GV_STRAT_TRADE_DAY, 0);
   if(tradeDay == 0) return false;

   ArrayInitialize(counts, 0);
   counts[QB_STRAT_IDX_BO]  = MathMax(0, (int)GV_ReadDouble(GV_STRAT_TRADES_BO, 0));
   counts[QB_STRAT_IDX_FBO] = MathMax(0, (int)GV_ReadDouble(GV_STRAT_TRADES_FBO, 0));
   counts[QB_STRAT_IDX_TP]  = MathMax(0, (int)GV_ReadDouble(GV_STRAT_TRADES_TP, 0));
   counts[QB_STRAT_IDX_MR]  = MathMax(0, (int)GV_ReadDouble(GV_STRAT_TRADES_MR, 0));
   counts[QB_STRAT_IDX_TPV2] = MathMax(0, (int)GV_ReadDouble(GV_STRAT_TRADES_TPV2, 0));
   return true;
}

bool QBShouldRestoreStrategyCounters(datetime savedDay, datetime currentDay)
{
   return savedDay != 0 && savedDay == currentDay;
}

string GV_ArbHashSlotName(int idx)
{
   return GV_ARB_RECENT_HASH + IntegerToString(idx);
}

string GV_ArbTimeSlotName(int idx)
{
   return GV_ARB_RECENT_TIME + IntegerToString(idx);
}

void SaveArbitrationState(datetime lastAcceptTime, const double &hashes[],
                          const datetime &times[], int count)
{
   int capped = MathMin(MathMin(count, ArraySize(hashes)), ArraySize(times));
   capped = MathMin(capped, QB_ARB_PERSIST_MAX);

   GV_WriteDatetime(GV_ARB_LAST_ACCEPT, lastAcceptTime);
   GV_WriteDouble(GV_ARB_RECENT_COUNT, (double)capped);
   for(int i = 0; i < QB_ARB_PERSIST_MAX; i++)
   {
      if(i < capped)
      {
         GV_WriteDouble(GV_ArbHashSlotName(i), hashes[i]);
         GV_WriteDatetime(GV_ArbTimeSlotName(i), times[i]);
      }
      else
      {
         GV_WriteDouble(GV_ArbHashSlotName(i), 0);
         GV_WriteDatetime(GV_ArbTimeSlotName(i), 0);
      }
   }
}

bool LoadArbitrationState(datetime &lastAcceptTime, double &hashes[],
                          datetime &times[], int &count)
{
   lastAcceptTime = GV_ReadDatetime(GV_ARB_LAST_ACCEPT, 0);
   count = MathMax(0, (int)GV_ReadDouble(GV_ARB_RECENT_COUNT, 0));
   count = MathMin(count, QB_ARB_PERSIST_MAX);

   ArrayResize(hashes, count);
   ArrayResize(times, count);
   for(int i = 0; i < count; i++)
   {
      hashes[i] = GV_ReadDouble(GV_ArbHashSlotName(i), 0);
      times[i] = GV_ReadDatetime(GV_ArbTimeSlotName(i), 0);
   }

   return lastAcceptTime > 0 || count > 0;
}

bool QBShouldRestoreArbitrationTimestamp(datetime savedTime, datetime now,
                                         int windowSeconds)
{
   return savedTime > 0 && savedTime <= now && now - savedTime < windowSeconds;
}

//+------------------------------------------------------------------+
//| Save state version for migration detection                        |
//+------------------------------------------------------------------+
void SaveStateVersion()
{
   GV_WriteDouble(GV_STATE_VERSION, QB_STATE_VERSION_NUM);
}

//+------------------------------------------------------------------+
//| Load state version                                                |
//+------------------------------------------------------------------+
int LoadStateVersion()
{
   return (int)GV_ReadDouble(GV_STATE_VERSION, 0);
}

//+------------------------------------------------------------------+
//| Clear all QB global variables (clean reset)                       |
//+------------------------------------------------------------------+
void ClearAllState()
{
   QBLogInfo("Clearing all persisted state");

   string names[] = {
      GV_DAILY_START_EQUITY, GV_DAILY_DATE, GV_DAILY_PNL,
      GV_WEEKLY_START_EQUITY, GV_WEEKLY_DATE, GV_HIGH_WATER_MARK,
      GV_DAILY_LOCK, GV_WEEKLY_LOCK, GV_DRAWDOWN_LOCK, GV_CONSEC_LOSSES,
      GV_BROKER_FAILURES, GV_STRAT_TRADE_DAY,
      GV_STRAT_TRADES_BO, GV_STRAT_TRADES_FBO,
      GV_STRAT_TRADES_TP, GV_STRAT_TRADES_MR, GV_STRAT_TRADES_TPV2,
      GV_ARB_LAST_ACCEPT, GV_ARB_RECENT_COUNT,
      GV_CHALLENGE_STAGE, GV_STAGE_START_EQUITY, GV_STAGE_PEAK,
      GV_STAGE_ATTEMPTS, GV_STAGE_TARGET, GV_STAGE_RISK,
      GV_STAGE_PROFIT_LOCK, GV_STAGE_MAX_EXPOSURE,
      GV_CHAL_CASHFLOW_MSC, GV_CHAL_CASHFLOW_TICKET,
      GV_KILL_ENTRIES, GV_KILL_SYMBOL, GV_KILL_CANCEL, GV_KILL_FLATTEN,
      GV_KILL_STRAT_BO,
      GV_KILL_STRAT_FBO, GV_KILL_STRAT_TP, GV_KILL_STRAT_MR, GV_KILL_STRAT_TPV2,
      GV_EMERGENCY, GV_STATE_VERSION
   };

   for(int i = 0; i < ArraySize(names); i++)
   {
      string key = GV_ScopedName(names[i]);
      if(GlobalVariableCheck(key))
         GlobalVariableDel(key);
   }

   for(int i = 0; i < QB_ARB_PERSIST_MAX; i++)
   {
      string hashKey = GV_ScopedName(GV_ArbHashSlotName(i));
      string timeKey = GV_ScopedName(GV_ArbTimeSlotName(i));
      if(GlobalVariableCheck(hashKey)) GlobalVariableDel(hashKey);
      if(GlobalVariableCheck(timeKey)) GlobalVariableDel(timeKey);
   }
}

//+------------------------------------------------------------------+
//| Persist state version on first run                                |
//+------------------------------------------------------------------+
bool IsSupportedStateVersion(const int version)
{
   return version == 0 || version == QB_STATE_VERSION_NUM;
}

bool StateStoreInit()
{
   int version = LoadStateVersion();
   if(version == 0)
   {
      QBLogInfo("Initializing persisted state version v" +
                IntegerToString(QB_STATE_VERSION_NUM));
      SaveStateVersion();
      return true;
   }

   if(version != QB_STATE_VERSION_NUM)
   {
      QBLogError("Persisted state version mismatch (found v" +
                 IntegerToString(version) + ", expected v" +
                 IntegerToString(QB_STATE_VERSION_NUM) +
                 "). Entries remain quarantined until state is migrated or cleared.");
      return false;
   }

   return true;
}

bool QBTestStateVersionPolicy(string &detail)
{
   bool emptyAccepted = IsSupportedStateVersion(0);
   bool currentAccepted = IsSupportedStateVersion(QB_STATE_VERSION_NUM);
   bool oldRejected = !IsSupportedStateVersion(QB_STATE_VERSION_NUM - 1);
   bool futureRejected = !IsSupportedStateVersion(QB_STATE_VERSION_NUM + 1);
   detail = "empty=" + (emptyAccepted ? "true" : "false") +
            " current=" + (currentAccepted ? "true" : "false") +
            " old=" + (oldRejected ? "rejected" : "FAILED") +
            " future=" + (futureRejected ? "rejected" : "FAILED");
   return emptyAccepted && currentAccepted && oldRejected && futureRejected;
}

bool QBTestStateScopePolicy(string &detail)
{
   string chartSymbol = "CHART_XAUUSD";
   string effectiveSymbol = "BROKER_XAUUSDm";
   long loginA = 10101;
   long loginB = 20202;

   string chartKey = GV_TestScopedName(GV_STATE_VERSION, loginA, chartSymbol);
   string effectiveKey = GV_TestScopedName(GV_STATE_VERSION, loginA, effectiveSymbol);
   string otherAccountKey = GV_TestScopedName(GV_STATE_VERSION, loginB, effectiveSymbol);

   bool symbolSeparated = (chartKey != effectiveKey);
   bool accountSeparated = (effectiveKey != otherAccountKey);

   string before = GetStateScopeSymbol();
   SetStateScopeSymbol(effectiveSymbol);
   bool overrideApplied = (GetStateScopeSymbol() == effectiveSymbol);
   SetStateScopeSymbol(before);

   detail = "symbol=" + (symbolSeparated ? "scoped" : "FAILED") +
            " account=" + (accountSeparated ? "scoped" : "FAILED") +
            " override=" + (overrideApplied ? "effective" : "FAILED");
   return symbolSeparated && accountSeparated && overrideApplied;
}

bool QBTestStrategyCounterRestorePolicy(string &detail)
{
   datetime today = 1767225600;       // 2026.01.01 00:00:00
   datetime yesterday = today - 86400;
   bool sameDayRestores = QBShouldRestoreStrategyCounters(today, today);
   bool missingRejected = !QBShouldRestoreStrategyCounters(0, today);
   bool oldRejected = !QBShouldRestoreStrategyCounters(yesterday, today);
   bool futureRejected = !QBShouldRestoreStrategyCounters(today + 86400, today);

   detail = "same=" + (sameDayRestores ? "restore" : "FAILED") +
            " missing=" + (missingRejected ? "reject" : "FAILED") +
            " old=" + (oldRejected ? "reject" : "FAILED") +
            " future=" + (futureRejected ? "reject" : "FAILED");
   return sameDayRestores && missingRejected && oldRejected && futureRejected;
}

bool QBTestArbitrationRestorePolicy(string &detail)
{
   datetime now = 1767225900;         // 2026.01.01 00:05:00
   bool freshRestores = QBShouldRestoreArbitrationTimestamp(now - 60, now, 300);
   bool expiredRejected = !QBShouldRestoreArbitrationTimestamp(now - 301, now, 300);
   bool missingRejected = !QBShouldRestoreArbitrationTimestamp(0, now, 300);
   bool futureRejected = !QBShouldRestoreArbitrationTimestamp(now + 60, now, 300);

   detail = "fresh=" + (freshRestores ? "restore" : "FAILED") +
            " expired=" + (expiredRejected ? "reject" : "FAILED") +
            " missing=" + (missingRejected ? "reject" : "FAILED") +
            " future=" + (futureRejected ? "reject" : "FAILED");
   return freshRestores && expiredRejected && missingRejected && futureRejected;
}

#endif // QB_STATESTORE_MQH
