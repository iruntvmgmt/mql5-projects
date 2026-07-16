//+------------------------------------------------------------------+
//|                                            QuantBeast/TickState.mqh |
//|                          XAUUSD Quant Beast EA - Tick State       |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_TICKSTATE_MQH
#define QB_TICKSTATE_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Tick State - tracks tick-level information for execution decisions|
//+------------------------------------------------------------------+
class CTickState
{
private:
   string      m_symbol;
   datetime    m_lastTickTime;
   datetime    m_lastQuoteTime;
   double      m_lastBid;
   double      m_lastAsk;
   double      m_lastSpread;
   long        m_tickCount;
   long        m_tickVolumeCumulative;

   // Rolling tick frequency tracking
   datetime    m_tickHistory[];
   int         m_tickHistoryIdx;
   int         m_tickHistorySize;

   // Rolling spread tracking
   double      m_spreadHistory[];
   int         m_spreadHistoryIdx;
   int         m_spreadHistorySize;

   // Quote age tracking
   datetime    m_quoteHistory[];
   int         m_quoteHistoryIdx;
   int         m_quoteHistorySize;

   bool        m_initialized;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CTickState()
   {
      m_symbol = "";
      m_lastTickTime = 0;
      m_lastQuoteTime = 0;
      m_lastBid = 0;
      m_lastAsk = 0;
      m_lastSpread = 0;
      m_tickCount = 0;
      m_tickVolumeCumulative = 0;
      m_tickHistoryIdx = 0;
      m_tickHistorySize = 100;
      m_spreadHistoryIdx = 0;
      m_spreadHistorySize = 100;
      m_quoteHistoryIdx = 0;
      m_quoteHistorySize = 50;
      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(string symbol)
   {
      m_symbol = symbol;

      ArrayResize(m_tickHistory, m_tickHistorySize);
      ArrayResize(m_spreadHistory, m_spreadHistorySize);
      ArrayResize(m_quoteHistory, m_quoteHistorySize);

      ArrayInitialize(m_tickHistory, 0);
      ArrayInitialize(m_spreadHistory, 0.0);
      ArrayInitialize(m_quoteHistory, 0);

      m_initialized = true;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update on each tick                                               |
   //+------------------------------------------------------------------+
   void Update(const MarketSnapshot &snap)
   {
      if(!m_initialized) return;

      datetime now = TimeCurrent();

      m_lastTickTime = now;
      m_lastBid  = snap.bid;
      m_lastAsk  = snap.ask;
      m_lastSpread = snap.spread_points;
      m_tickCount++;
      m_tickVolumeCumulative += snap.tick_volume;

      // Track quote time from symbol
      m_lastQuoteTime = (datetime)SymbolInfoInteger(m_symbol, SYMBOL_TIME);

      // Rolling tick history
      m_tickHistory[m_tickHistoryIdx] = now;
      m_tickHistoryIdx = (m_tickHistoryIdx + 1) % m_tickHistorySize;

      // Rolling spread
      m_spreadHistory[m_spreadHistoryIdx] = snap.spread_points;
      m_spreadHistoryIdx = (m_spreadHistoryIdx + 1) % m_spreadHistorySize;

      // Quote age history
      m_quoteHistory[m_quoteHistoryIdx] = now - m_lastQuoteTime;
      m_quoteHistoryIdx = (m_quoteHistoryIdx + 1) % m_quoteHistorySize;
   }

   //+------------------------------------------------------------------+
   //| Get estimated tick frequency (ticks per minute)                   |
   //+------------------------------------------------------------------+
   double GetTickFrequency()
   {
      int validCount = 0;
      datetime oldest = 0;

      // Find how many ticks in our history window
      datetime now = TimeCurrent();
      for(int i = 0; i < m_tickHistorySize; i++)
      {
         if(m_tickHistory[i] > 0 && now - m_tickHistory[i] < 60)
            validCount++;
      }

      if(validCount < 2) return validCount; // Less than 1 minute of data

      return validCount; // ticks per minute (approximate)
   }

   //+------------------------------------------------------------------+
   //| Get rolling average spread                                        |
   //+------------------------------------------------------------------+
   double GetAverageSpread()
   {
      double sum = 0;
      int count = 0;
      for(int i = 0; i < m_spreadHistorySize; i++)
      {
         if(m_spreadHistory[i] > 0)
         {
            sum += m_spreadHistory[i];
            count++;
         }
      }
      if(count == 0) return m_lastSpread;
      return sum / count;
   }

   //+------------------------------------------------------------------+
   //| Get spread percentile (what % of spreads are lower than current)  |
   //+------------------------------------------------------------------+
   double GetSpreadPercentile()
   {
      int below = 0;
      int total = 0;
      for(int i = 0; i < m_spreadHistorySize; i++)
      {
         if(m_spreadHistory[i] > 0)
         {
            if(m_spreadHistory[i] < m_lastSpread) below++;
            total++;
         }
      }
      if(total == 0) return 50.0;
      return (double)below / total * 100.0;
   }

   //+------------------------------------------------------------------+
   //| Get quote age in milliseconds                                     |
   //+------------------------------------------------------------------+
   int GetQuoteAgeMs()
   {
      return (int)((TimeCurrent() - m_lastQuoteTime) * 1000);
   }

   //+------------------------------------------------------------------+
   //| Check if quote is stable (spread not rapidly changing)            |
   //+------------------------------------------------------------------+
   bool IsQuoteStable()
   {
      double avgSpread = GetAverageSpread();
      if(avgSpread < 0.1) return true; // Can't assess

      double spreadRatio = m_lastSpread / avgSpread;
      return (spreadRatio >= 0.5 && spreadRatio <= 2.0);
   }

   //+------------------------------------------------------------------+
   //| Check for abnormal tick (price jump)                              |
   //+------------------------------------------------------------------+
   bool IsAbnormalTick(double &priceChange, double maxPointsJump)
   {
      static double prevMid = 0;
      double currentMid = (m_lastBid + m_lastAsk) / 2.0;

      if(prevMid > 0)
      {
         double change = MathAbs(currentMid - prevMid);
         double points = change / SymbolInfoDouble(m_symbol, SYMBOL_POINT);

         if(points > maxPointsJump)
         {
            priceChange = points;
            prevMid = currentMid;
            return true;
         }
      }

      prevMid = currentMid;
      return false;
   }

   //+------------------------------------------------------------------+
   //| Get relative tick volume (current vs average)                     |
   //+------------------------------------------------------------------+
   double GetRelativeTickVolume()
   {
      // Just return the cumulative tick volume trend
      if(m_tickCount < 100) return 1.0;

      // Simple: use cumulative volume / tick count as proxy for "normal"
      // Real implementation would use rolling window comparison
      return 1.0;
   }

   //+------------------------------------------------------------------+
   //| Accessors                                                         |
   //+------------------------------------------------------------------+
   datetime LastTickTime()  const { return m_lastTickTime; }
   double   LastBid()       const { return m_lastBid; }
   double   LastAsk()       const { return m_lastAsk; }
   double   LastSpread()    const { return m_lastSpread; }
   long     TickCount()     const { return m_tickCount; }
   long     TickVolumeCum() const { return m_tickVolumeCumulative; }
   bool     IsInitialized() const { return m_initialized; }
};

#endif // QB_TICKSTATE_MQH
