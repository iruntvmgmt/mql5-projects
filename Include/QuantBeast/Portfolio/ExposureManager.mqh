//+------------------------------------------------------------------+
//|                                     QuantBeast/ExposureManager.mqh|
//|                          XAUUSD Quant Beast EA - Exposure Manager|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_EXPOSUREMANAGER_MQH
#define QB_EXPOSUREMANAGER_MQH

#include "../Core/Types.mqh"

//+------------------------------------------------------------------+
//| Exposure Manager - tracks and limits aggregate exposure           |
//| Currently implemented via RiskEngine. This stub exists for       |
//| future expansion (multi-symbol, multi-account).                   |
//+------------------------------------------------------------------+
class CExposureManager
{
public:
   CExposureManager() {}
};

#endif // QB_EXPOSUREMANAGER_MQH
