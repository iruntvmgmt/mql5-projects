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

public:
   CAlerts()
   {
      m_pushEnabled  = false;
      m_emailEnabled = false;
   }

   void Init(bool pushEnabled)
   {
      m_pushEnabled = pushEnabled;
   }

   void SendAlert(string message)
   {
      Alert(message);
      if(m_pushEnabled)
         SendNotification(QB_EA_NAME + ": " + message);
   }

   void SendIfEnabled(bool condition, string message)
   {
      if(condition) SendAlert(message);
   }
};

#endif // QB_ALERTS_MQH
