//+------------------------------------------------------------------+
//|                                      QuantBeast/VolatilityState.mqh|
//|                          XAUUSD Quant Beast EA - Vol Classification|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_VOLATILITYSTATE_MQH
#define QB_VOLATILITYSTATE_MQH

#include "../Core/Types.mqh"
#include "../Core/MathUtils.mqh"

//+------------------------------------------------------------------+
//| Volatility State Classifier                                       |
//+------------------------------------------------------------------+
class CVolatilityState
{
private:
   double   m_compressionPct;
   double   m_shockMultiplier;
   int      m_minExpansionBars;

public:
   CVolatilityState()
   {
      m_compressionPct    = 20.0;
      m_shockMultiplier   = 3.0;
      m_minExpansionBars  = 3;
   }

   void Init(double compressionPct, double shockMultiplier, int minExpBars)
   {
      m_compressionPct    = compressionPct;
      m_shockMultiplier   = shockMultiplier;
      m_minExpansionBars  = minExpBars;
   }

   //+------------------------------------------------------------------+
   //| Classify volatility regime from features                          |
   //+------------------------------------------------------------------+
   ENUM_VOLATILITY_REGIME Classify(const FeatureSnapshot &feat, double &score)
   {
      score = 0.5;

      // Shock: abnormal candle or extreme ATR ratio
      if(feat.abnormal_candle || feat.atr_ratio > m_shockMultiplier)
      {
         score = 0.9;
         return VOL_SHOCK;
      }

      // Extreme: ATR ratio very high but below shock
      if(feat.atr_ratio > 2.0 || feat.range_percentile > 90.0)
      {
         score = 0.8;
         return VOL_EXTREME;
      }

      // Expansion: ATR ratio above 1 and increasing
      if(feat.is_expanding && feat.compression_bars < m_minExpansionBars)
      {
         score = Clamp(feat.atr_ratio / 1.5, 0.6, 0.8);
         return VOL_EXPANSION;
      }

      // Compression: ATR below compression percentile
      if(feat.is_compressing && feat.compression_bars >= m_minExpansionBars)
      {
         score = Clamp(1.0 - feat.atr_ratio, 0.6, 0.8);
         return VOL_COMPRESSION;
      }

      // Normal
      score = Clamp(1.0 - MathAbs(feat.atr_ratio - 1.0), 0.4, 0.6);
      return VOL_NORMAL;
   }

   //+------------------------------------------------------------------+
   //| Check if volatility is safe for trading                           |
   //+------------------------------------------------------------------+
   bool IsSafeForTrading(ENUM_VOLATILITY_REGIME vol)
   {
      return (vol == VOL_NORMAL || vol == VOL_COMPRESSION);
   }

   //+------------------------------------------------------------------+
   //| Check if volatility is dangerous                                  |
   //+------------------------------------------------------------------+
   bool IsDangerous(ENUM_VOLATILITY_REGIME vol)
   {
      return (vol == VOL_SHOCK || vol == VOL_EXTREME);
   }
};

#endif // QB_VOLATILITYSTATE_MQH
