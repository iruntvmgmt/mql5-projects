//+------------------------------------------------------------------+
//|                                         QuantBeast/FeatureEngine.mqh|
//|                          XAUUSD Quant Beast EA - Feature Factory  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_FEATUREENGINE_MQH
#define QB_FEATUREENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/MathUtils.mqh"
#include "../Core/Diagnostics.mqh"
#include "BarCache.mqh"
#include "MarketData.mqh"
#include "SessionEngine.mqh"
#include "TickState.mqh"

//+------------------------------------------------------------------+
//| Feature Engine - calculates all market features                   |
//+------------------------------------------------------------------+
class CFeatureEngine
{
private:
   CSymbolAdapter*  m_adapter;
   CBarCache*       m_barCache;
   CSessionEngine*  m_session;
   CTickState*      m_tickState;

   // ATR indicator handles
   int   m_atrHandlePrimary;
   int   m_atrHandleHTF;

   // Cached feature values
   FeatureSnapshot  m_current;
   datetime         m_lastCalcTime;
   bool             m_initialized;

   // Configuration
   int   m_atrPeriod;
   int   m_trendLookback;
   double m_trendSlopeThreshold;
   int   m_compressionLookback;
   double m_compressionPct;
   double m_shockVolMultiplier;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CFeatureEngine()
   {
      m_adapter     = NULL;
      m_barCache    = NULL;
      m_session     = NULL;
      m_tickState   = NULL;
      m_atrHandlePrimary = INVALID_HANDLE;
      m_atrHandleHTF     = INVALID_HANDLE;
      m_lastCalcTime = 0;
      m_initialized  = false;
      ZeroMemory(m_current);
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CFeatureEngine()
   {
      ReleaseHandles();
   }

   //+------------------------------------------------------------------+
   //| Release indicator handles                                         |
   //+------------------------------------------------------------------+
   void ReleaseHandles()
   {
      if(m_atrHandlePrimary != INVALID_HANDLE)
         IndicatorRelease(m_atrHandlePrimary);
      if(m_atrHandleHTF != INVALID_HANDLE)
         IndicatorRelease(m_atrHandleHTF);
      m_atrHandlePrimary = INVALID_HANDLE;
      m_atrHandleHTF = INVALID_HANDLE;
   }

   //+------------------------------------------------------------------+
   //| Initialize with dependencies and config                            |
   //+------------------------------------------------------------------+
   bool Init(CSymbolAdapter &adapter, CBarCache &barCache, CSessionEngine &session,
             CTickState &tickState, ENUM_TIMEFRAMES primaryTF, ENUM_TIMEFRAMES htfTF,
             int atrPeriod, int trendLookback, double trendSlopeThreshold,
             int compressionLookback, double compressionPct, double shockVolMultiplier)
   {
      m_adapter  = &adapter;
      m_barCache = &barCache;
      m_session  = &session;
      m_tickState = &tickState;

      m_atrPeriod            = atrPeriod;
      m_trendLookback        = trendLookback;
      m_trendSlopeThreshold  = trendSlopeThreshold;
      m_compressionLookback  = compressionLookback;
      m_compressionPct       = compressionPct;
      m_shockVolMultiplier   = shockVolMultiplier;

      string sym = adapter.Symbol();

      // Create ATR handles (cached, not recreated per tick)
      m_atrHandlePrimary = iATR(sym, primaryTF, atrPeriod);
      m_atrHandleHTF     = iATR(sym, htfTF, atrPeriod);

      if(m_atrHandlePrimary == INVALID_HANDLE || m_atrHandleHTF == INVALID_HANDLE)
      {
         QBLogError("Failed to create ATR handles");
         return false;
      }

      m_initialized = true;
      QBLogInfo("FeatureEngine initialized (ATR period=" + IntegerToString(atrPeriod) + ")");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Calculate all features (call on new bar or as needed)             |
   //+------------------------------------------------------------------+
   FeatureSnapshot Calculate(ENUM_TIMEFRAMES primaryTF, ENUM_TIMEFRAMES htfTF,
                              ENUM_TIMEFRAMES dailyTF, const MarketSnapshot &snap)
   {
      ZeroMemory(m_current);
      m_current.calc_time = TimeCurrent();

      // --- Volatility Features ---
      CalcVolatilityFeatures(primaryTF);

      // --- Trend Features ---
      CalcTrendFeatures(primaryTF, htfTF);

      // --- Structural Features ---
      CalcStructuralFeatures(primaryTF, dailyTF);

      // --- Auction/Equilibrium Features ---
      CalcEquilibriumFeatures(primaryTF, snap);

      // --- Liquidity Features ---
      CalcLiquidityFeatures(snap);

      m_lastCalcTime = TimeCurrent();
      return m_current;
   }

   //+------------------------------------------------------------------+
   //| Get the latest feature snapshot                                   |
   //+------------------------------------------------------------------+
   FeatureSnapshot GetCurrent() const { return m_current; }

private:
   //+------------------------------------------------------------------+
   //| ATR helper - get ATR value from handle at bar index              |
   //+------------------------------------------------------------------+
   double GetATR(int handle, int barIndex)
   {
      double buf[1];
      if(CopyBuffer(handle, 0, barIndex, 1, buf) != 1)
         return 0;
      return buf[0];
   }

   //+------------------------------------------------------------------+
   //| Volatility Features                                               |
   //+------------------------------------------------------------------+
   void CalcVolatilityFeatures(ENUM_TIMEFRAMES primaryTF)
   {
      int barCount = m_barCache.GetBarCount(primaryTF);
      if(barCount < m_atrPeriod + 5) return;

      // ATR from indicator handle
      m_current.atr = GetATR(m_atrHandlePrimary, 1);
      m_current.atr_points = m_current.atr / m_adapter.Point();

      // Short-term ATR (e.g., 5-period)
      double atrShort = 0;
      {
         int shortPer = MathMax(3, m_atrPeriod / 3);
         double high[], low[], close[];
         m_barCache.GetHighArray(primaryTF, high, shortPer + 1, 1);
         m_barCache.GetLowArray(primaryTF, low, shortPer + 1, 1);
         m_barCache.GetCloseArray(primaryTF, close, shortPer + 2, 1);

         for(int i = 0; i < shortPer; i++)
         {
            double tr = TrueRange(high[i], low[i], close[i+1]);
            if(i == 0) atrShort = tr;
            else atrShort = (atrShort * (shortPer - 1) + tr) / shortPer;
         }
      }
      m_current.short_atr = atrShort;
      m_current.long_atr  = m_current.atr;
      m_current.atr_ratio = (m_current.atr > 0) ? atrShort / m_current.atr : 1.0;

      // Realized volatility (std dev of returns)
      {
         double close[];
         int count = m_barCache.GetCloseArray(primaryTF, close, 21, 1);
         if(count >= 5)
         {
            double returns[];
            ArrayResize(returns, count - 1);
            for(int i = 0; i < count - 1; i++)
               returns[i] = (close[i] - close[i+1]) / close[i+1];

            double mean, stddev;
            ArrayMeanStdDev(returns, count - 1, mean, stddev);
            m_current.realized_vol = stddev * MathSqrt(252 * 24 * 60 / PeriodSeconds(primaryTF)); // Annualized approx
         }
      }

      // Compression/expansion detection
      double atrValues[];
      ArrayResize(atrValues, m_compressionLookback);
      for(int i = 0; i < m_compressionLookback && i < barCount; i++)
      {
         double atrVal = GetATR(m_atrHandlePrimary, i + 1);
         atrValues[i] = atrVal;
      }

      if(m_compressionLookback > 5)
      {
         int atrCount = MathMin(m_compressionLookback, barCount);
         double atrPercentile = ArrayPercentileUnsorted(atrValues, atrCount, m_compressionPct);
         int belowOrEqual = 0;
         for(int i = 0; i < atrCount; i++)
         {
            if(atrValues[i] <= m_current.atr)
               belowOrEqual++;
         }
         m_current.atr_percentile_rank = (atrCount > 0 ? 100.0 * belowOrEqual / atrCount : 100.0);
         m_current.is_compressing = (m_current.atr <= atrPercentile);

         // Compression bars count
         if(m_current.is_compressing)
         {
            int compBars = 0;
            for(int i = 0; i < MathMin(20, barCount); i++)
            {
               double atr_i = GetATR(m_atrHandlePrimary, i + 2);
               if(atr_i <= atrPercentile) compBars++;
               else break;
            }
            m_current.compression_bars = compBars;
         }
      }

      // Expansion detection
      m_current.is_expanding = (m_current.atr_ratio > 1.3);

      // Bollinger bandwidth
      {
         double close[];
         m_barCache.GetCloseArray(primaryTF, close, 21, 1);
         int cnt = MathMin(20, ArraySize(close));
         if(cnt >= 5)
         {
            double sma = SMA_Slice(close, 0, cnt);
            double sumSq = 0;
            for(int i = 0; i < cnt; i++)
            {
               double diff = close[i] - sma;
               sumSq += diff * diff;
            }
            double stdDev = MathSqrt(sumSq / cnt);
            m_current.bb_bandwidth = (sma > 0) ? (4 * stdDev) / sma : 0;
         }
      }

      // Range percentile
      {
         double close[];
         int cnt = m_barCache.GetCloseArray(primaryTF, close, 21, 1);
         if(cnt >= 20)
         {
            double highRange = ArrayMaxSlice(close, 0, cnt);
            double lowRange  = ArrayMinSlice(close, 0, cnt);
            double range = highRange - lowRange;
            if(range > 0)
               m_current.range_percentile = (close[0] - lowRange) / range * 100.0;
         }
      }

      // Vol of vol
      if(m_compressionLookback > 10)
      {
         double atrChanges[];
         ArrayResize(atrChanges, MathMin(m_compressionLookback, barCount) - 1);
         for(int i = 0; i < MathMin(m_compressionLookback, barCount) - 1; i++)
            atrChanges[i] = MathAbs(atrValues[i] - atrValues[i+1]) / MathMax(atrValues[i+1], 0.0001);
         double mean, stddev;
         ArrayMeanStdDev(atrChanges, ArraySize(atrChanges), mean, stddev);
         m_current.vol_of_vol = stddev;
      }

      // Abnormal candle
      {
         MqlRates r;
         if(m_barCache.GetLatestClosedBar(primaryTF, r))
         {
            double body = MathAbs(r.close - r.open);
            double atrVal = m_current.atr;
            if(atrVal > 0 && body / atrVal > 2.5)
               m_current.abnormal_candle = true;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Trend Features                                                    |
   //+------------------------------------------------------------------+
   void CalcTrendFeatures(ENUM_TIMEFRAMES primaryTF, ENUM_TIMEFRAMES htfTF)
   {
      double close[];
      int cnt = m_barCache.GetCloseArray(primaryTF, close, m_trendLookback + 50, 1);
      if(cnt < m_trendLookback) return;

      // Regression slope
      m_current.trend_slope = RegressionSlopeSeries(close, 0, m_trendLookback);

      // Normalized slope
      double atrVal = m_current.atr;
      if(atrVal > 0)
         m_current.slope_norm = m_current.trend_slope * m_trendLookback / atrVal;

      // Directional efficiency
      m_current.dir_efficiency = DirectionalEfficiency(close, 0, m_trendLookback);

      // Fast vs slow MA
      int fastPer = MathMax(5, m_trendLookback / 4);
      int slowPer = m_trendLookback;
      m_current.fast_ma = SMA_Slice(close, 0, MathMin(fastPer, cnt));
      m_current.slow_ma = SMA_Slice(close, 0, MathMin(slowPer, cnt));
      m_current.fast_slow_aligned = (m_current.fast_ma > m_current.slow_ma && m_current.trend_slope > 0) ||
                                     (m_current.fast_ma < m_current.slow_ma && m_current.trend_slope < 0);

      // HTF alignment (simple: same slope direction)
      double htfClose[];
      int htfCnt = m_barCache.GetCloseArray(htfTF, htfClose, m_trendLookback + 1, 1);
      if(htfCnt >= m_trendLookback)
      {
         double htfSlope = RegressionSlopeSeries(htfClose, 0, m_trendLookback);
         m_current.htf_slope = htfSlope;
         m_current.htf_aligned = (m_current.trend_slope > 0 && htfSlope > 0) ||
                                  (m_current.trend_slope < 0 && htfSlope < 0);
      }

      // Trend persistence (bars since slope changed sign)
      if(m_current.trend_slope != 0)
      {
         int persist = 1;
         double prevSlopeSign = (m_current.trend_slope > 0) ? 1.0 : -1.0;
         for(int i = 1; i < MathMin(cnt, 50) && i + m_trendLookback <= cnt; i++)
         {
            double segSlope = RegressionSlopeSeries(close, i, m_trendLookback);
            double segSign = (segSlope > 0) ? 1.0 : -1.0;
            if(segSign != prevSlopeSign) break;
            persist++;
         }
         m_current.trend_persistence = persist;
      }

      // Trend acceleration
      double close5[];
      m_barCache.GetCloseArray(primaryTF, close5, 6, 1);
      if(ArraySize(close5) >= 6)
      {
         double slopeRecent = RegressionSlopeSeries(close5, 0, 5);
         double slopePrior  = RegressionSlopeSeries(close5, 1, 5);
         m_current.trend_accel = slopeRecent - slopePrior;
      }

      // Distance from equilibrium (SMA distance normalized by ATR)
      double sma20[];
      m_barCache.GetCloseArray(primaryTF, sma20, 21, 1);
      int smaCnt = MathMin(20, ArraySize(sma20));
      if(smaCnt >= 5 && atrVal > 0)
      {
         double sma = SMA_Slice(sma20, 0, smaCnt);
         m_current.dist_from_equil = (close[0] - sma) / atrVal;
      }

      // Trend maturity
      m_current.trend_maturity = (double)m_current.trend_persistence / (double)m_trendLookback;
   }

   //+------------------------------------------------------------------+
   //| Structural Features                                               |
   //+------------------------------------------------------------------+
   void CalcStructuralFeatures(ENUM_TIMEFRAMES primaryTF, ENUM_TIMEFRAMES dailyTF)
   {
      double high[], low[], close[];
      int cnt = m_barCache.GetBarCount(primaryTF);
      int lookback = MathMin(50, cnt);

      m_barCache.GetHighArray(primaryTF, high, lookback, 1);
      m_barCache.GetLowArray(primaryTF, low, lookback, 1);
      m_barCache.GetCloseArray(primaryTF, close, lookback, 1);

      if(ArraySize(high) < 5 || ArraySize(low) < 5) return;

      // Simple swing detection (fractal-like: pivot if 2 bars on each side are lower/higher)
      int swingHighIdx = -1, swingLowIdx = -1;
      for(int i = 2; i < lookback - 2; i++)
      {
         if(high[i] > high[i-1] && high[i] > high[i-2] &&
            high[i] > high[i+1] && high[i] > high[i+2])
         {
            swingHighIdx = i;
            break;
         }
      }
      for(int i = 2; i < lookback - 2; i++)
      {
         if(low[i] < low[i-1] && low[i] < low[i-2] &&
            low[i] < low[i+1] && low[i] < low[i+2])
         {
            swingLowIdx = i;
            break;
         }
      }

      if(swingHighIdx >= 0)
      {
         m_current.swing_high = high[swingHighIdx];
         m_current.swing_high_bars = swingHighIdx;
      }
      if(swingLowIdx >= 0)
      {
         m_current.swing_low = low[swingLowIdx];
         m_current.swing_low_bars = swingLowIdx;
      }

      // Compare the two newest confirmed pivots (series index grows older).
      int priorHighIdx = -1, priorLowIdx = -1;
      for(int i = swingHighIdx + 1; swingHighIdx >= 0 && i < lookback - 2; i++)
      {
         if(high[i] > high[i-1] && high[i] > high[i-2] &&
            high[i] > high[i+1] && high[i] > high[i+2])
         { priorHighIdx = i; break; }
      }
      for(int i = swingLowIdx + 1; swingLowIdx >= 0 && i < lookback - 2; i++)
      {
         if(low[i] < low[i-1] && low[i] < low[i-2] &&
            low[i] < low[i+1] && low[i] < low[i+2])
         { priorLowIdx = i; break; }
      }
      if(priorHighIdx >= 0)
      {
         m_current.higher_high = high[swingHighIdx] > high[priorHighIdx];
         m_current.lower_high = high[swingHighIdx] < high[priorHighIdx];
      }
      if(priorLowIdx >= 0)
      {
         m_current.higher_low = low[swingLowIdx] > low[priorLowIdx];
         m_current.lower_low = low[swingLowIdx] < low[priorLowIdx];
      }

      MqlRates closedBar;
      if(m_barCache.GetLatestClosedBar(primaryTF, closedBar))
      {
         m_current.closed_open = closedBar.open;
         m_current.closed_high = closedBar.high;
         m_current.closed_low = closedBar.low;
         m_current.closed_close = closedBar.close;
         if(m_current.atr > 0)
            m_current.displacement = MathAbs(closedBar.close - closedBar.open) / m_current.atr;
      }

      // Prior range excludes the just-closed trigger bar.
      int rangeBars = MathMin(20, lookback);
      double rangeHigh[], rangeLow[];
      int rangeCount = m_barCache.GetHighArray(primaryTF, rangeHigh, rangeBars, 2);
      m_barCache.GetLowArray(primaryTF, rangeLow, rangeBars, 2);
      if(rangeCount > 0)
      {
         m_current.current_range_high = ArrayMaxSlice(rangeHigh, 0, rangeCount);
         m_current.current_range_low  = ArrayMinSlice(rangeLow, 0, rangeCount);
      }

      // Previous day levels
      double dailyHigh[], dailyLow[];
      int dailyCnt = m_barCache.GetHighArray(dailyTF, dailyHigh, 2, 1);
      m_barCache.GetLowArray(dailyTF, dailyLow, 2, 1);
      if(dailyCnt >= 1)
      {
         m_current.prev_day_high = dailyHigh[0];
         m_current.prev_day_low  = dailyLow[0];
      }

      // Current session range before the trigger bar.
      MqlRates signalBar;
      if(m_barCache.GetBar(primaryTF, 1, signalBar))
      {
         ENUM_SESSION_TYPE signalSession = m_session.Classify(signalBar.time);
         double sessHigh = 0, sessLow = DBL_MAX;
         double sessionHighs[100], sessionLows[100];
         int sessionCount = 0;
         for(int i = 2; i < MathMin(102, cnt) && sessionCount < 100; i++)
         {
            MqlRates bar;
            if(!m_barCache.GetBar(primaryTF, i, bar) ||
               m_session.Classify(bar.time) != signalSession)
               break;
            sessionHighs[sessionCount] = bar.high;
            sessionLows[sessionCount] = bar.low;
            sessHigh = MathMax(sessHigh, bar.high);
            sessLow = MathMin(sessLow, bar.low);
            sessionCount++;
         }
         if(sessionCount > 0)
         {
            m_current.session_high = sessHigh;
            m_current.session_low = sessLow;
            int orBars = MathMin(4, sessionCount);
            m_current.or_high = 0;
            m_current.or_low = DBL_MAX;
            for(int i = sessionCount - orBars; i < sessionCount; i++)
            {
               m_current.or_high = MathMax(m_current.or_high, sessionHighs[i]);
               m_current.or_low = MathMin(m_current.or_low, sessionLows[i]);
            }
         }
      }

      // Rejection wick measurement
      MqlRates r;
      if(m_barCache.GetLatestClosedBar(primaryTF, r))
      {
         double bodyHigh = MathMax(r.open, r.close);
         double bodyLow  = MathMin(r.open, r.close);
         m_current.rejection_wick_upper = r.high - bodyHigh;
         m_current.rejection_wick_lower = bodyLow - r.low;
         m_current.rejection_wick = MathMax(m_current.rejection_wick_upper,
                                            m_current.rejection_wick_lower);
         if(m_current.atr > 0)
         {
            m_current.rejection_wick /= m_current.atr; // Normalize by ATR
            m_current.rejection_wick_upper /= m_current.atr;
            m_current.rejection_wick_lower /= m_current.atr;
         }
      }

      // Accepted breaks and same-bar failed auctions relative to levels
      // that existed before the trigger bar.
      if(m_current.closed_close > m_current.current_range_high)
      {
         m_current.breakout_dist = m_current.closed_close - m_current.current_range_high;
         m_current.bars_beyond_level = 1;
      }
      else if(m_current.closed_close < m_current.current_range_low)
      {
         m_current.breakout_dist = m_current.current_range_low - m_current.closed_close;
         m_current.bars_beyond_level = 1;
      }

      double upperLevel = m_current.prev_day_high;
      if(m_current.session_high > 0 && (upperLevel <= 0 || m_current.session_high < upperLevel))
         upperLevel = m_current.session_high;
      double lowerLevel = m_current.prev_day_low;
      if(m_current.session_low > 0 && (lowerLevel <= 0 || m_current.session_low > lowerLevel))
         lowerLevel = m_current.session_low;

      if(upperLevel > 0 && m_current.closed_high > upperLevel &&
         m_current.closed_close < upperLevel)
      {
         m_current.failed_breakout = true;
         m_current.reclaim_detected = true;
         m_current.failed_breakout_up = true;
         m_current.reclaim_level = upperLevel;
         m_current.sweep_extreme = m_current.closed_high;
         m_current.breakout_dist = m_current.closed_high - upperLevel;
         m_current.bars_beyond_level = 1;
      }
      if(lowerLevel > 0 && m_current.closed_low < lowerLevel &&
         m_current.closed_close > lowerLevel)
      {
         m_current.failed_breakout = true;
         m_current.reclaim_detected = true;
         m_current.failed_breakout_down = true;
         m_current.reclaim_level = lowerLevel;
         m_current.sweep_extreme = m_current.closed_low;
         m_current.breakout_dist = lowerLevel - m_current.closed_low;
         m_current.bars_beyond_level = 1;
      }
   }

   //+------------------------------------------------------------------+
   //| Auction/Equilibrium Features                                      |
   //+------------------------------------------------------------------+
   void CalcEquilibriumFeatures(ENUM_TIMEFRAMES primaryTF, const MarketSnapshot &snap)
   {
      // VWAP approximation using tick volume weighted price
      double close[], high[], low[];
      int cnt = m_barCache.GetBarCount(primaryTF);
      int vwapBars = MathMin(50, cnt);

      m_barCache.GetCloseArray(primaryTF, close, vwapBars, 1);
      m_barCache.GetHighArray(primaryTF, high, vwapBars, 1);
      m_barCache.GetLowArray(primaryTF, low, vwapBars, 1);

      if(ArraySize(close) < 2) return;

      // Simple VWAP (equal weighted since tick vol may be unreliable for OTC gold)
      // Still use tick volume for weighting but note limitations
      MqlRates rates[];
      int copied = CopyRates(m_adapter.Symbol(), primaryTF, 1, vwapBars, rates);
      if(copied > 0)
      {
         ArraySetAsSeries(rates, true);
         double totalPV = 0, totalP2V = 0, totalVol = 0;
         for(int i = 0; i < MathMin(copied, vwapBars); i++)
         {
            double typical = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
            double vol = (double)MathMax(rates[i].tick_volume, (long)1); // Minimum 1 to avoid zero weight
            totalPV += typical * vol;
            totalP2V += typical * typical * vol;
            totalVol += vol;
         }
         if(totalVol > 0)
         {
            m_current.vwap = totalPV / totalVol;
            m_current.rolling_vwap = m_current.vwap;
            double variance = MathMax(0.0, totalP2V / totalVol -
                                           m_current.vwap * m_current.vwap);
            m_current.vwap_sd = MathSqrt(variance);
         }
      }

      // Range midpoint
      m_current.range_midpoint = (m_current.current_range_high + m_current.current_range_low) / 2.0;

      // Normalized distance from VWAP
      if(m_current.vwap > 0 && m_current.atr > 0)
         m_current.norm_dist_vwap = (m_current.closed_close - m_current.vwap) / m_current.atr;

      // True weighted standard-deviation distance from VWAP.
      if(m_current.vwap_sd > QB_EPSILON)
         m_current.sd_dist = (m_current.closed_close - m_current.vwap) /
                             m_current.vwap_sd;

      // Return to value detection
      if(MathAbs(m_current.norm_dist_vwap) < 0.3)
         m_current.returning_to_value = true;
   }

   //+------------------------------------------------------------------+
   //| Liquidity/Execution Features                                      |
   //+------------------------------------------------------------------+
   void CalcLiquidityFeatures(const MarketSnapshot &snap)
   {
      m_current.current_spread = snap.spread_points;

      if(m_tickState != NULL && m_tickState.IsInitialized())
      {
         m_current.avg_spread       = m_tickState.GetAverageSpread();
         m_current.spread_percentile = m_tickState.GetSpreadPercentile();
         m_current.tick_freq        = m_tickState.GetTickFrequency();
         m_current.quote_age_ms     = m_tickState.GetQuoteAgeMs();
         m_current.quote_stable     = m_tickState.IsQuoteStable();
      }

      // Expected execution cost (spread + estimated slippage)
      m_current.exp_exec_cost = snap.spread_points + 5.0; // 5 pts estimated slippage

      // Max acceptable entry displacement
      m_current.max_entry_displacement = MathMax(m_current.exp_exec_cost * 2, 20.0);

      // Stale market detection
      m_current.stale_market = (m_current.quote_age_ms > 5000);
   }
};

#endif // QB_FEATUREENGINE_MQH
