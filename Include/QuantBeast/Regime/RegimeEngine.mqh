//+------------------------------------------------------------------+
//|                                          QuantBeast/RegimeEngine.mqh|
//|                          XAUUSD Quant Beast EA - Combined Regime  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_REGIMEENGINE_MQH
#define QB_REGIMEENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/MathUtils.mqh"
#include "../Core/Diagnostics.mqh"
#include "TrendState.mqh"
#include "VolatilityState.mqh"
#include "LiquidityState.mqh"
#include "StructuralState.mqh"

//+------------------------------------------------------------------+
//| Regime Engine - combines all regime classifiers                   |
//+------------------------------------------------------------------+
class CRegimeEngine
{
private:
   CTrendState         m_trendClassifier;
   CVolatilityState    m_volClassifier;
   CLiquidityState     m_liqClassifier;
   CStructuralState    m_structClassifier;

   RegimeState         m_current;
   bool                m_enabled;
   bool                m_initialized;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CRegimeEngine()
   {
      m_enabled = false;
      m_initialized = false;
      ZeroMemory(m_current);
   }

   //+------------------------------------------------------------------+
   //| Initialize classifiers                                            |
   //+------------------------------------------------------------------+
   bool Init(bool enabled, double trendSlopeThreshold, double compressionPct,
             double shockMultiplier, int minExpBars)
   {
      m_enabled = enabled;
      m_trendClassifier.Init(trendSlopeThreshold);
      m_volClassifier.Init(compressionPct, shockMultiplier, minExpBars);
      m_initialized = true;

      QBLogInfo("RegimeEngine initialized (enabled=" + (enabled ? "Yes" : "No") + ")");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Classify current regime from features and context                 |
   //+------------------------------------------------------------------+
   RegimeState Classify(const FeatureSnapshot &feat,
                         ENUM_SESSION_TYPE session,
                         ENUM_EVENT_STATE event)
   {
      ZeroMemory(m_current);

      if(!m_enabled)
      {
         m_current.trend      = TREND_NEUTRAL;
         m_current.volatility  = VOL_NORMAL;
         m_current.liquidity   = LIQUIDITY_GOOD;
         m_current.structure   = STRUCTURE_BALANCED;
         m_current.session     = session;
         m_current.event_state = event;
         m_current.confidence  = 0.5;
         return m_current;
      }

      // Classify each dimension
      m_current.trend      = m_trendClassifier.Classify(feat, m_current.trend_score);
      m_current.volatility  = m_volClassifier.Classify(feat, m_current.volatility_score);
      m_current.liquidity   = m_liqClassifier.Classify(feat, session, m_current.liquidity_score);
      m_current.structure   = m_structClassifier.Classify(feat, m_current.structure_score);
      m_current.session     = session;
      m_current.event_state = event;

      // Overall confidence (average of sub-scores)
      m_current.confidence = (m_current.trend_score + m_current.volatility_score +
                               m_current.liquidity_score + m_current.structure_score) / 4.0;

      return m_current;
   }

   //+------------------------------------------------------------------+
   //| Get current regime state                                          |
   //+------------------------------------------------------------------+
   RegimeState GetCurrent() const { return m_current; }

   //+------------------------------------------------------------------+
   //| Check if regime is safe for any trading                           |
   //+------------------------------------------------------------------+
   bool IsSafeForTrading()
   {
      if(!m_enabled) return true;

      // Must have good/acceptable liquidity
      if(!m_liqClassifier.IsTradeable(m_current.liquidity))
         return false;

      // Must not be in shock volatility
      if(m_volClassifier.IsDangerous(m_current.volatility))
         return false;

      // Must not be in news lockout
      if(m_current.event_state != EVENT_NORMAL)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get regime summary string                                         |
   //+------------------------------------------------------------------+
   string GetSummary()
   {
      return "T:" + EnumToString(m_current.trend) +
             " V:" + EnumToString(m_current.volatility) +
             " L:" + EnumToString(m_current.liquidity) +
             " S:" + EnumToString(m_current.structure) +
             " Sn:" + EnumToString(m_current.session) +
             " E:" + EnumToString(m_current.event_state);
   }

   //+------------------------------------------------------------------+
   //| Print regime diagnostics                                          |
   //+------------------------------------------------------------------+
   void PrintDiagnostics()
   {
      QBLogSection("Regime Diagnostics");
      QBLogInfoS("  Trend",        EnumToString(m_current.trend) + " (" + DoubleToString(m_current.trend_score, 2) + ")");
      QBLogInfoS("  Volatility",   EnumToString(m_current.volatility) + " (" + DoubleToString(m_current.volatility_score, 2) + ")");
      QBLogInfoS("  Liquidity",    EnumToString(m_current.liquidity) + " (" + DoubleToString(m_current.liquidity_score, 2) + ")");
      QBLogInfoS("  Structure",    EnumToString(m_current.structure) + " (" + DoubleToString(m_current.structure_score, 2) + ")");
      QBLogInfoS("  Session",      EnumToString(m_current.session));
      QBLogInfoS("  Event",        EnumToString(m_current.event_state));
      QBLogInfoV("  Confidence",   m_current.confidence, 2);
      QBLogInfoS("  Safe to Trade", IsSafeForTrading() ? "Yes" : "No");
   }

   bool IsInitialized() const { return m_initialized; }
};

#endif // QB_REGIMEENGINE_MQH
