//+------------------------------------------------------------------+
//|                                             QuantBeast/BarCache.mqh |
//|                          XAUUSD Quant Beast EA - Central Bar Cache|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_BARCACHE_MQH
#define QB_BARCACHE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Supported Timeframes Count                                        |
//+------------------------------------------------------------------+
#define QB_MAX_TF 8

//+------------------------------------------------------------------+
//| Bar Cache - centralized OHLC storage for all required TFs         |
//+------------------------------------------------------------------+
class CBarCache
{
private:
   struct TFData
   {
      ENUM_TIMEFRAMES   tf;
      string            tfName;
      MqlRates          rates[];
      int               totalBars;
      int               lastBarIndex;   // Most recent bar index in rates[]
      datetime          lastBarTime;    // Open time of most recent bar
      int               handle;         // Indicator handle (if used)
      bool              active;
   };

   TFData             m_tfs[QB_MAX_TF];
   int                m_tfCount;
   string             m_symbol;
   bool               m_initialized;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CBarCache()
   {
      m_tfCount = 0;
      m_symbol = "";
      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   //| Initialize with required timeframes                               |
   //+------------------------------------------------------------------+
   bool Init(string symbol, ENUM_TIMEFRAMES &tfs[], int tfCount)
   {
      m_symbol = symbol;
      m_tfCount = 0;

      for(int i = 0; i < tfCount && i < QB_MAX_TF; i++)
      {
         m_tfs[i].tf     = tfs[i];
         m_tfs[i].tfName = EnumToString(tfs[i]);
         m_tfs[i].active = true;
         m_tfs[i].handle = INVALID_HANDLE;
         m_tfs[i].totalBars = 0;
         m_tfs[i].lastBarIndex = -1;
         m_tfs[i].lastBarTime = 0;
         ArrayResize(m_tfs[i].rates, 0);
         m_tfCount++;
      }

      // Load initial data
      bool allOk = true;
      for(int i = 0; i < m_tfCount; i++)
      {
         if(!LoadTF(i))
         {
            QBLogError("Failed to load TF: " + m_tfs[i].tfName);
            allOk = false;
         }
      }

      if(!allOk) return false;

      m_initialized = true;
      QBLogInfo("BarCache initialized: " + IntegerToString(m_tfCount) + " timeframes, symbol=" + m_symbol);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Load bars for a specific TF                                       |
   //+------------------------------------------------------------------+
   bool LoadTF(int idx)
   {
      if(idx < 0 || idx >= m_tfCount) return false;

      // Copy rates from MT5
      int copied = CopyRates(m_symbol, m_tfs[idx].tf, 0, QB_MAX_BARS, m_tfs[idx].rates);

      if(copied <= 0)
      {
         QBLogError("CopyRates failed for " + m_tfs[idx].tfName + " error=" + IntegerToString(GetLastError()));
         return false;
      }

      m_tfs[idx].totalBars = copied;

      // Set as timeseries (index 0 = newest)
      ArraySetAsSeries(m_tfs[idx].rates, true);

      m_tfs[idx].lastBarIndex = 0;
      if(copied > 0)
         m_tfs[idx].lastBarTime = m_tfs[idx].rates[0].time;

      QBLogDebug("Loaded " + IntegerToString(copied) + " bars for " + m_tfs[idx].tfName);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update all caches - call on each tick or new bar                  |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(!m_initialized) return;

      for(int i = 0; i < m_tfCount; i++)
      {
         if(!m_tfs[i].active) continue;

         // Try to copy latest rates
         MqlRates temp[];
         int copied = CopyRates(m_symbol, m_tfs[i].tf, 0, QB_MAX_BARS, temp);

         if(copied <= 0) continue;

         ArraySetAsSeries(temp, true);

         // Check if new bar formed
         if(copied > m_tfs[i].totalBars || temp[0].time != m_tfs[i].lastBarTime)
         {
            // New bar detected - full reload
            ArrayResize(m_tfs[i].rates, copied);
            for(int j = 0; j < copied; j++)
               m_tfs[i].rates[j] = temp[j];

            if(copied > m_tfs[i].totalBars)
            {
               QBLogDebug("New bar on " + m_tfs[i].tfName +
                          " time=" + FormatTime(temp[0].time));
            }

            m_tfs[i].totalBars = copied;
            m_tfs[i].lastBarIndex = 0;
            m_tfs[i].lastBarTime = temp[0].time;
         }
         else
         {
            // Same bar - just update OHLC of current bar
            m_tfs[i].rates[0] = temp[0];
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Get TF index by enum                                              |
   //+------------------------------------------------------------------+
   int GetTFIndex(ENUM_TIMEFRAMES tf) const
   {
      for(int i = 0; i < m_tfCount; i++)
         if(m_tfs[i].tf == tf && m_tfs[i].active)
            return i;
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Get bar count for a TF                                            |
   //+------------------------------------------------------------------+
   int GetBarCount(ENUM_TIMEFRAMES tf) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0) return 0;
      return m_tfs[idx].totalBars;
   }

   //+------------------------------------------------------------------+
   //| Get a specific bar by index (0 = newest)                         |
   //+------------------------------------------------------------------+
   bool GetBar(ENUM_TIMEFRAMES tf, int barIndex, MqlRates &rate) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0) return false;
      if(barIndex < 0 || barIndex >= m_tfs[idx].totalBars) return false;

      rate = m_tfs[idx].rates[barIndex];
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get bar time for a specific index                                 |
   //+------------------------------------------------------------------+
   datetime GetBarTime(ENUM_TIMEFRAMES tf, int barIndex) const
   {
      MqlRates r;
      if(GetBar(tf, barIndex, r))
         return r.time;
      return 0;
   }

   //+------------------------------------------------------------------+
   //| Get close price array (as series, 0 = newest) - writes into provided array |
   //+------------------------------------------------------------------+
   int GetCloseArray(ENUM_TIMEFRAMES tf, double &arr[], int count, int start = 0) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0 || start < 0 || start >= m_tfs[idx].totalBars) return 0;

      int maxCount = MathMin(count, m_tfs[idx].totalBars - start);
      ArrayResize(arr, maxCount);

      for(int i = 0; i < maxCount; i++)
         arr[i] = m_tfs[idx].rates[start + i].close;

      return maxCount;
   }

   //+------------------------------------------------------------------+
   //| Get high array                                                    |
   //+------------------------------------------------------------------+
   int GetHighArray(ENUM_TIMEFRAMES tf, double &arr[], int count, int start = 0) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0 || start < 0 || start >= m_tfs[idx].totalBars) return 0;

      int maxCount = MathMin(count, m_tfs[idx].totalBars - start);
      ArrayResize(arr, maxCount);

      for(int i = 0; i < maxCount; i++)
         arr[i] = m_tfs[idx].rates[start + i].high;

      return maxCount;
   }

   //+------------------------------------------------------------------+
   //| Get low array                                                     |
   //+------------------------------------------------------------------+
   int GetLowArray(ENUM_TIMEFRAMES tf, double &arr[], int count, int start = 0) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0 || start < 0 || start >= m_tfs[idx].totalBars) return 0;

      int maxCount = MathMin(count, m_tfs[idx].totalBars - start);
      ArrayResize(arr, maxCount);

      for(int i = 0; i < maxCount; i++)
         arr[i] = m_tfs[idx].rates[start + i].low;

      return maxCount;
   }

   //+------------------------------------------------------------------+
   //| Get OHLC arrays for a slice                                      |
   //+------------------------------------------------------------------+
   bool GetOHLCArrays(ENUM_TIMEFRAMES tf, double &open[], double &high[],
                       double &low[], double &close[], int count) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0) return false;

      int maxCount = MathMin(count, m_tfs[idx].totalBars);
      ArrayResize(open, maxCount);
      ArrayResize(high, maxCount);
      ArrayResize(low, maxCount);
      ArrayResize(close, maxCount);

      for(int i = 0; i < maxCount; i++)
      {
         open[i]  = m_tfs[idx].rates[i].open;
         high[i]  = m_tfs[idx].rates[i].high;
         low[i]   = m_tfs[idx].rates[i].low;
         close[i] = m_tfs[idx].rates[i].close;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if we have sufficient bars for trading                      |
   //+------------------------------------------------------------------+
   bool HasSufficientBars(ENUM_TIMEFRAMES tf, int minBars) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0) return false;
      return m_tfs[idx].totalBars >= minBars;
   }

   //+------------------------------------------------------------------+
   //| Get the latest bar (index 0) for a TF                             |
   //+------------------------------------------------------------------+
   bool GetLatestBar(ENUM_TIMEFRAMES tf, MqlRates &rate) const
   {
      return GetBar(tf, 0, rate);
   }

   bool GetLatestClosedBar(ENUM_TIMEFRAMES tf, MqlRates &rate) const
   {
      return GetBar(tf, 1, rate);
   }

   //+------------------------------------------------------------------+
   //| Check if new bar has formed since last check                      |
   //+------------------------------------------------------------------+
   bool IsNewBar(ENUM_TIMEFRAMES tf, datetime &prevBarTime) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0) return false;

      datetime currentBarTime = m_tfs[idx].lastBarTime;
      if(currentBarTime != prevBarTime)
      {
         prevBarTime = currentBarTime;
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Verify chronological ordering of bars for a TF                    |
   //+------------------------------------------------------------------+
   bool VerifyChronology(ENUM_TIMEFRAMES tf) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0) return true; // TF not loaded - skip

      for(int i = 1; i < m_tfs[idx].totalBars; i++)
      {
         if(m_tfs[idx].rates[i-1].time <= m_tfs[idx].rates[i].time)
         {
            QBLogError("Chronology violation on " + m_tfs[idx].tfName +
                       " at bar " + IntegerToString(i) +
                       " t[" + IntegerToString(i-1) + "]=" + FormatTime(m_tfs[idx].rates[i-1].time) +
                       " t[" + IntegerToString(i) + "]=" + FormatTime(m_tfs[idx].rates[i].time));
            return false;
         }
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Check for missing data gaps                                       |
   //+------------------------------------------------------------------+
   bool HasDataGaps(ENUM_TIMEFRAMES tf) const
   {
      int idx = GetTFIndex(tf);
      if(idx < 0) return true;

      int tfSeconds = PeriodSeconds(tf);
      if(tfSeconds <= 0) return false;

      for(int i = 1; i < m_tfs[idx].totalBars; i++)
      {
         datetime expected = m_tfs[idx].rates[i].time + tfSeconds;
         datetime actual   = m_tfs[idx].rates[i-1].time;
         if(expected != actual)
         {
            // Allow small gaps for weekend/market close
            if(actual - expected > tfSeconds * 2)
            {
               QBLogWarn("Data gap on " + m_tfs[idx].tfName +
                         ": expected=" + FormatTime(expected) +
                         " actual=" + FormatTime(actual));
               // Don't immediately reject; gaps are common
            }
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Get the number of active timeframes                               |
   //+------------------------------------------------------------------+
   int GetTFCount() const { return m_tfCount; }

   //+------------------------------------------------------------------+
   //| Is the cache initialized                                          |
   //+------------------------------------------------------------------+
   bool IsInitialized() const { return m_initialized; }
};

#endif // QB_BARCACHE_MQH
