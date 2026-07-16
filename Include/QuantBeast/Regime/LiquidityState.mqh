//+------------------------------------------------------------------+
//|                                      QuantBeast/LiquidityState.mqh|
//|                          XAUUSD Quant Beast EA - Liquidity Classifier|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_LIQUIDITYSTATE_MQH
#define QB_LIQUIDITYSTATE_MQH

#include "../Core/Types.mqh"
#include "../Core/MathUtils.mqh"

//+------------------------------------------------------------------+
//| Liquidity State Classifier                                        |
//+------------------------------------------------------------------+
class CLiquidityState
{
public:
   CLiquidityState() {}

   //+------------------------------------------------------------------+
   //| Classify liquidity from features and session                      |
   //+------------------------------------------------------------------+
   ENUM_LIQUIDITY_REGIME Classify(const FeatureSnapshot &feat,
                                   ENUM_SESSION_TYPE session, double &score)
   {
      double spreadPct  = feat.spread_percentile;
      double quoteAge   = feat.quote_age_ms;
      bool   quoteOk    = feat.quote_stable;
      double tickFreq   = feat.tick_freq;

      score = 0.5;

      // Unsafe: very stale, unstable, or extreme spread
      if(feat.stale_market || quoteAge > 10000 || spreadPct > 95.0)
      {
         score = 0.1;
         return LIQUIDITY_UNSAFE;
      }

      // Thin: spread elevated, low tick frequency, low-liquidity session
      if(spreadPct > 80.0 || tickFreq < 5.0 ||
         session == SESSION_ASIA || session == SESSION_ROLLOVER)
      {
         score = 0.3;
         return LIQUIDITY_THIN;
      }

      // Acceptable: moderate spread, decent tick rate
      if(spreadPct > 50.0 || !quoteOk)
      {
         score = 0.6;
         return LIQUIDITY_ACCEPTABLE;
      }

      // Good: tight spread, high tick rate, stable quotes
      score = 0.85;
      return LIQUIDITY_GOOD;
   }

   //+------------------------------------------------------------------+
   //| Check if liquidity is acceptable for trading                      |
   //+------------------------------------------------------------------+
   bool IsTradeable(ENUM_LIQUIDITY_REGIME liq)
   {
      return (liq == LIQUIDITY_GOOD || liq == LIQUIDITY_ACCEPTABLE);
   }
};

#endif // QB_LIQUIDITYSTATE_MQH
