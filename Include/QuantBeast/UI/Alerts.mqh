//+------------------------------------------------------------------+
//|                                              QuantBeast/Alerts.mqh|
//|                          XAUUSD Quant Beast EA - Alert System    |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_ALERTS_MQH
#define QB_ALERTS_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Alert System - manages notification channels                      |
//| IMPLEMENTATION: PARTIAL - Terminal alerts only.                  |
//| Push notifications and email are stubbed pending configuration.   |
//+------------------------------------------------------------------+
class CAlerts
{
private:
   bool m_pushEnabled;
   bool m_emailEnabled;
   int  m_sentCount;
   string m_lastMessage;

public:
   CAlerts()
   {
      m_pushEnabled  = false;
      m_emailEnabled = false;
      m_sentCount = 0;
      m_lastMessage = "";
   }

   void Init(bool pushEnabled)
   {
      m_pushEnabled = pushEnabled;
   }

   bool SendAlert(string message)
   {
      m_sentCount++;
      m_lastMessage = message;

      if(MQLInfoInteger(MQL_TESTER))
      {
         QBLogInfo("Alert suppressed in tester: " + message);
         return true;
      }

      Alert(message);
      if(m_pushEnabled)
         SendNotification(QB_EA_NAME + ": " + message);
      return true;
   }

   bool SendIfEnabled(bool condition, string message)
   {
      if(!condition) return false;
      return SendAlert(message);
   }

   int SentCount() const { return m_sentCount; }
   string LastMessage() const { return m_lastMessage; }
};

bool QBTestAlertRouting(string &detail)
{
   CAlerts alerts;
   alerts.Init(false);

   bool disabledSuppressed = !alerts.SendIfEnabled(false, "disabled-alert");
   bool enabledSent = alerts.SendIfEnabled(true, "enabled-alert");
   bool countOK = alerts.SentCount() == 1;
   bool lastOK = alerts.LastMessage() == "enabled-alert";

   detail = "disabled=" + (disabledSuppressed ? "suppressed" : "FAILED") +
            " enabled=" + (enabledSent ? "routed" : "FAILED") +
            " count=" + IntegerToString(alerts.SentCount());
   return disabledSuppressed && enabledSent && countOK && lastOK;
}

#endif // QB_ALERTS_MQH
