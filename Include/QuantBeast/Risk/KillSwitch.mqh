//+------------------------------------------------------------------+
//|                                            QuantBeast/KillSwitch.mqh|
//|                          XAUUSD Quant Beast EA - Kill Switch System|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_KILLSWITCH_MQH
#define QB_KILLSWITCH_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

bool QBModeAllowsBrokerActions(ENUM_QB_MODE mode)
{
   return mode == QB_MODE_CONSERVATIVE_LIVE ||
          mode == QB_MODE_CHALLENGE_LIVE;
}

bool QBBrokerActionAttemptDue(ulong nowMsc, ulong minIntervalMsc,
                              ulong &lastAttemptMsc)
{
   if(lastAttemptMsc != 0 && nowMsc >= lastAttemptMsc &&
      nowMsc - lastAttemptMsc < minIntervalMsc)
      return false;
   lastAttemptMsc = nowMsc;
   return true;
}

//+------------------------------------------------------------------+
//| Kill Switch Manager - emergency protection system                 |
//+------------------------------------------------------------------+
class CKillSwitch
{
private:
   KillSwitchState m_state;
   string          m_alertPrefix;
   bool            m_transientEntryBlock;
   string          m_transientReason;

public:
   //+------------------------------------------------------------------+
   CKillSwitch()
   {
      ZeroMemory(m_state);
      m_alertPrefix = QB_EA_NAME + " KILL: ";
      m_transientEntryBlock = false;
      m_transientReason = "";
   }

   //+------------------------------------------------------------------+
   //| Kill a specific strategy                                          |
   //+------------------------------------------------------------------+
   void KillStrategy(int stratIdx, string reason)
   {
      if(stratIdx >= 0 && stratIdx < QB_STRAT_COUNT)
      {
         m_state.strategy_kill[stratIdx] = true;
         QBLogWarn(m_alertPrefix + "Strategy " + IntegerToString(stratIdx) +
                   " killed: " + reason);
      }
   }

   //+------------------------------------------------------------------+
   //| Kill all new entries                                              |
   //+------------------------------------------------------------------+
   void KillEntries(string reason)
   {
      if(m_state.entry_kill) return;
      m_state.entry_kill = true;
      QBLogWarn(m_alertPrefix + "Entry kill activated: " + reason);
   }

   //+------------------------------------------------------------------+
   //| Kill symbol trading                                               |
   //+------------------------------------------------------------------+
   void KillSymbol(string reason)
   {
      m_state.symbol_kill = true;
      QBLogWarn(m_alertPrefix + "Symbol kill activated: " + reason);
   }

   //+------------------------------------------------------------------+
   //| Cancel all pending orders request                                 |
   //+------------------------------------------------------------------+
   void CancelAll(string reason)
   {
      m_state.cancel_all = true;
      QBLogWarn(m_alertPrefix + "Cancel-all activated: " + reason);
   }

   //+------------------------------------------------------------------+
   //| Flatten all positions request                                     |
   //+------------------------------------------------------------------+
   void FlattenAll(string reason)
   {
      m_state.flatten_all = true;
      m_state.cancel_all = true;
      m_state.entry_kill = true;
      QBLogWarn(m_alertPrefix + "Flatten-all activated: " + reason);
   }

   //+------------------------------------------------------------------+
   //| Emergency mode (full lockout)                                     |
   //+------------------------------------------------------------------+
   void Emergency(string reason)
   {
      m_state.emergency = true;
      m_state.entry_kill = true;
      m_state.cancel_all = true;
      m_state.flatten_all = true;
      m_state.emergency_reason = reason;
      QBLogError(m_alertPrefix + "EMERGENCY: " + reason);
   }

   //+------------------------------------------------------------------+
   //| Check conditions and auto-trigger                                 |
   //+------------------------------------------------------------------+
   void CheckConditions(bool quoteStale, bool repeatedRejection,
                         bool stopPlacementFailure, bool equityFloorBreached,
                         bool dailyDDHit, bool weeklyDDHit,
                         bool terminalDisconnected, bool abnormalSpread)
   {
      // Quote freshness, connectivity, and spread are transient pre-trade
      // gates. They must clear automatically when market conditions recover;
      // persisted/manual kills remain latched until an explicit reset.
      m_transientEntryBlock = false;
      m_transientReason = "";

      // Persistent hard-risk conditions must latch even while disconnected.
      // A transient connectivity return must never suppress an equity floor,
      // account lock, stop failure, or repeated-rejection decision.
      if(equityFloorBreached)
      {
         Emergency("Equity floor breached");
         return;
      }

      if(dailyDDHit)
      {
         KillEntries("Daily drawdown limit hit");
      }

      if(weeklyDDHit)
      {
         KillEntries("Weekly drawdown limit hit");
      }

      if(stopPlacementFailure && m_state.emergency)
      {
         // Already in emergency, no need to re-trigger.
      }
      else if(stopPlacementFailure)
      {
         KillEntries("Repeated stop placement failure");
      }

      if(repeatedRejection)
      {
         KillEntries("Repeated broker rejection");
      }

      if(terminalDisconnected)
      {
         m_transientEntryBlock = true;
         m_transientReason = "Terminal disconnected";
         return;
      }

      if(abnormalSpread)
      {
         m_transientEntryBlock = true;
         m_transientReason = "Abnormal spread detected";
      }

      if(quoteStale)
      {
         m_transientEntryBlock = true;
         if(m_transientReason == "") m_transientReason = "Stale quotes detected";
      }
   }

   //+------------------------------------------------------------------+
   //| Reset all kills (e.g., new day)                                   |
   //+------------------------------------------------------------------+
   void ResetNonEmergency()
   {
      if(m_state.emergency) return; // Don't reset emergency

      for(int i = 0; i < QB_STRAT_COUNT; i++)
         m_state.strategy_kill[i] = false;
      m_state.entry_kill   = false;
      m_state.symbol_kill  = false;
      m_state.cancel_all   = false;
      m_state.flatten_all  = false;
      m_transientEntryBlock = false;
      m_transientReason = "";
   }

   //+------------------------------------------------------------------+
   //| Reset everything (including emergency)                            |
   //+------------------------------------------------------------------+
   void ResetAll()
   {
      ZeroMemory(m_state);
      m_transientEntryBlock = false;
      m_transientReason = "";
      QBLogInfo("All kill switches reset");
   }

   void ClearCancelRequest() { m_state.cancel_all = false; }
   void ClearFlattenRequest()
   {
      m_state.flatten_all = false;
      m_state.cancel_all = false;
   }

   //+------------------------------------------------------------------+
   //| Query state                                                       |
   //+------------------------------------------------------------------+
   bool IsStrategyKilled(int stratIdx) const
   {
      if(stratIdx < 0 || stratIdx >= QB_STRAT_COUNT) return true;
      return m_state.strategy_kill[stratIdx] || m_state.emergency;
   }

   bool IsEntryKill()    const { return m_state.entry_kill || m_state.emergency || m_transientEntryBlock; }
   bool IsSymbolKill()   const { return m_state.symbol_kill || m_state.emergency; }
   bool IsCancelAll()    const { return m_state.cancel_all || m_state.emergency; }
   bool IsFlattenAll()   const { return m_state.flatten_all || m_state.emergency; }
   bool IsEmergency()    const { return m_state.emergency; }

   KillSwitchState GetState() const { return m_state; }

   void RestoreState(const KillSwitchState &saved)
   {
      m_state = saved;
      m_transientEntryBlock = false;
      m_transientReason = "";
   }

   //+------------------------------------------------------------------+
   //| Get status string for dashboard                                   |
   //+------------------------------------------------------------------+
   string GetStatusString()
   {
      if(m_state.emergency) return "EMERGENCY: " + m_state.emergency_reason;
      if(m_state.flatten_all) return "FLATTEN ALL";
      if(m_state.cancel_all) return "CANCEL ALL";
      if(m_state.entry_kill) return "ENTRIES BLOCKED";
      if(m_state.symbol_kill) return "SYMBOL KILLED";
      if(m_transientEntryBlock) return "ENTRY GATE: " + m_transientReason;

      string stratKills = "";
      for(int i = 0; i < QB_STRAT_COUNT; i++)
      {
         if(m_state.strategy_kill[i])
         {
            if(stratKills != "") stratKills += ",";
            stratKills += IntegerToString(i);
         }
      }
      if(stratKills != "") return "STRAT KILL: " + stratKills;

      return "OK";
   }
};

#endif // QB_KILLSWITCH_MQH
