//+------------------------------------------------------------------+
//|                                       QuantBeast/RecoveryEngine.mqh|
//|                          XAUUSD Quant Beast EA - Recovery Engine  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_RECOVERYENGINE_MQH
#define QB_RECOVERYENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Recovery Engine - handles restart, crash recovery, state repair   |
//| Core logic in PositionManager.ReconstructFromBroker() and        |
//| the startup reconciliation in QuantBeastEA.mq5 OnInit().        |
//+------------------------------------------------------------------+
class CRecoveryEngine
{
public:
   CRecoveryEngine() {}
};

#endif // QB_RECOVERYENGINE_MQH
