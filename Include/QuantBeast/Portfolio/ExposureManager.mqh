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
#include "../Core/Constants.mqh"

//+------------------------------------------------------------------+
//| Exposure Manager                                                  |
//|                                                                   |
//| Owns the aggregate-exposure LIMIT POLICY for the account: the     |
//| total-lots cap and the two decisions the risk gate makes against  |
//| it -- the pre-sizing "already at capacity" gate and the           |
//| post-sizing "this order would breach the cap" projection.         |
//|                                                                   |
//| The authoritative *current* aggregate remains the broker/Shadow   |
//| query (the single source of truth in a broker-backed system);     |
//| callers pass it in. CRiskEngine consults this module for both     |
//| exposure comparisons instead of hard-coding them, so the cap      |
//| policy lives in exactly one place. The per-strategy / per-        |
//| direction helpers below let callers project the effect of a       |
//| prospective order without duplicating the arithmetic.             |
//+------------------------------------------------------------------+
class CExposureManager
{
private:
   double m_maxTotalLots;   // Aggregate cap (lots) == InpMaxTotalExposureLots

public:
   CExposureManager() { m_maxTotalLots = 2.0; }

   void   Init(double maxTotalLots) { m_maxTotalLots = maxTotalLots; }
   double MaxTotalLots() const      { return m_maxTotalLots; }

   //+------------------------------------------------------------------+
   //| Pre-sizing gate: the account is already at (or over) the cap, so |
   //| no further entry may be sized. Mirrors the original             |
   //| RiskEngine.ValidateTrade check `totalExposure >= max`.          |
   //+------------------------------------------------------------------+
   bool AtCapacity(double currentLots) const
   {
      return (currentLots >= m_maxTotalLots);
   }

   //+------------------------------------------------------------------+
   //| Post-sizing projection: placing `addLots` on top of the current |
   //| aggregate would breach the cap. Mirrors the original            |
   //| RiskEngine.ValidateSizedTrade check                             |
   //| `totalExposure + lots > max + QB_EPSILON`.                      |
   //+------------------------------------------------------------------+
   bool WouldExceed(double currentLots, double addLots) const
   {
      return (currentLots + addLots > m_maxTotalLots + QB_EPSILON);
   }

   //+------------------------------------------------------------------+
   //| Lots still available under the cap given the current aggregate,  |
   //| floored at zero. Useful for sizing headroom / diagnostics.       |
   //+------------------------------------------------------------------+
   double Remaining(double currentLots) const
   {
      double r = m_maxTotalLots - currentLots;
      return (r > 0.0) ? r : 0.0;
   }
};

#endif // QB_EXPOSUREMANAGER_MQH
