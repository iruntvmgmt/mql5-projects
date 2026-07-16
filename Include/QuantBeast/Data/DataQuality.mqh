//+------------------------------------------------------------------+
//|                                          QuantBeast/DataQuality.mqh|
//|                          XAUUSD Quant Beast EA - Data Validation  |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_DATAQUALITY_MQH
#define QB_DATAQUALITY_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/TimeUtils.mqh"
#include "MarketData.mqh"
#include "BarCache.mqh"

//+------------------------------------------------------------------+
//| Data Quality Checker - validates all market data preconditions    |
//+------------------------------------------------------------------+
class CDataQualityChecker
{
private:
   CSymbolAdapter*  m_adapter;
   CBarCache*       m_barCache;
   bool             m_initialized;
   string           m_errors[20];
   int              m_errorCount;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CDataQualityChecker()
   {
      m_adapter     = NULL;
      m_barCache    = NULL;
      m_initialized = false;
      m_errorCount  = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   bool Init(CSymbolAdapter &adapter, CBarCache &barCache)
   {
      m_adapter  = &adapter;
      m_barCache = &barCache;
      m_initialized = true;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Run all data quality checks                                       |
   //+------------------------------------------------------------------+
   bool RunAllChecks(ENUM_TIMEFRAMES primaryTF, int minBarsRequired,
                     bool checkChronology, bool requireTradingPermissions)
   {
      m_errorCount = 0;

      // 1. Terminal connection
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
         AddError("Terminal not connected to server");

      // 2. Symbol exists
      bool isCustomSymbol = false;
      if(!SymbolExist(m_adapter.Symbol(), isCustomSymbol))
         AddError("Symbol does not exist: " + m_adapter.Symbol());

      // 4. Symbol selected in Market Watch
      if(!SymbolInfoInteger(m_adapter.Symbol(), SYMBOL_SELECT))
         AddError("Symbol not selected in Market Watch: " + m_adapter.Symbol());

      // 5. Symbol visible (quotes arriving)
      if(!SymbolInfoInteger(m_adapter.Symbol(), SYMBOL_VISIBLE))
         QBLogWarn("Symbol not visible (but may still work): " + m_adapter.Symbol());

      // 6. Valid point size
      if(m_adapter.Point() <= 0)
         AddError("Invalid point size: " + DoubleToString(m_adapter.Point()));

      // 7. Valid tick size
      if(m_adapter.TickSize() <= 0)
         AddError("Invalid tick size: " + DoubleToString(m_adapter.TickSize()));

      // 8. Valid min lot
      if(m_adapter.MinLot() <= 0)
         AddError("Invalid minimum lot: " + DoubleToString(m_adapter.MinLot()));

      // 9. Valid max lot
      if(m_adapter.MaxLot() < m_adapter.MinLot())
         AddError("Max lot < Min lot");

      // 10. Valid lot step
      if(m_adapter.LotStep() <= 0)
         AddError("Invalid lot step: " + DoubleToString(m_adapter.LotStep()));

      // 11. Stop level
      if(m_adapter.StopLevel() < 0)
         AddError("Negative stop level");

      // 12. Sufficient bars
      if(minBarsRequired > 0 && m_barCache != NULL)
      {
         if(!m_barCache.HasSufficientBars(primaryTF, minBarsRequired))
            AddError("Insufficient bars on primary TF: " +
                     IntegerToString(m_barCache.GetBarCount(primaryTF)) +
                     " < " + IntegerToString(minBarsRequired));
      }

      // 13. Chronology check
      if(checkChronology && m_barCache != NULL)
      {
         if(!m_barCache.VerifyChronology(primaryTF))
            AddError("Bar chronology violation on primary TF");
      }

      // 14. Bid/ask present
      double bid = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_BID);
      double ask = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_ASK);
      if(bid <= 0) AddError("Bid <= 0");
      if(ask <= 0) AddError("Ask <= 0");
      if(bid > 0 && ask > 0 && ask <= bid)
         AddError("Ask <= Bid");

      // 15. Trade allowed
      if(requireTradingPermissions && !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
         AddError("Account trading not allowed");

      // 16. Expert trading allowed
      if(requireTradingPermissions && !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
         AddError("Expert Advisor trading not allowed");

      // 17. Symbol trade mode
      if(!m_adapter.IsTradeable())
         AddError("Symbol trading not allowed (mode check)");

      // Report results
      if(m_errorCount > 0)
      {
         QBLogError("Data quality check FAILED: " + IntegerToString(m_errorCount) + " errors");
         for(int i = 0; i < m_errorCount; i++)
            QBLogError("  [" + IntegerToString(i+1) + "] " + m_errors[i]);
         return false;
      }

      QBLogInfo("Data quality check PASSED");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Pre-trade validation (called before each trade attempt)           |
   //+------------------------------------------------------------------+
   bool PreTradeValidation(const MarketSnapshot &snap, double maxSpreadPoints,
                           bool requireTradingPermissions)
   {
      m_errorCount = 0;

      // Quick checks that can block a trade

      // 1. Terminal connected
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      {
         AddError("Terminal disconnected");
         return false;
      }

      // 2. Trade allowed
      if(requireTradingPermissions && !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      {
         AddError("Trading not allowed on account");
         return false;
      }

      // 4. EA trade allowed
      if(requireTradingPermissions && !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      {
         AddError("EA trading not allowed");
         return false;
      }

      // 5. Symbol tradeable
      if(!m_adapter.IsTradeable())
      {
         AddError("Symbol not tradeable");
         return false;
      }

      // 6. Quote valid
      if(snap.bid <= 0 || snap.ask <= 0 || snap.ask <= snap.bid)
      {
         AddError("Invalid quote: bid=" + DoubleToString(snap.bid) +
                  " ask=" + DoubleToString(snap.ask));
         return false;
      }

      // 7. Quote fresh
      if(!snap.is_fresh)
      {
         AddError("Stale quote");
         return false;
      }

      // 8. Spread acceptable
      if(snap.spread_points > maxSpreadPoints)
      {
         AddError("Spread too high: " + DoubleToString(snap.spread_points, 1) +
                  " > " + DoubleToString(maxSpreadPoints, 1));
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Validate volume against broker constraints                        |
   //+------------------------------------------------------------------+
   bool ValidateVolume(double volume, string &reason)
   {
      if(volume < m_adapter.MinLot() - QB_EPSILON)
      {
         reason = "Volume below min lot: " + DoubleToString(volume, 2) +
                  " < " + DoubleToString(m_adapter.MinLot(), 2);
         return false;
      }

      if(volume > m_adapter.MaxLot() + QB_EPSILON)
      {
         reason = "Volume above max lot: " + DoubleToString(volume, 2) +
                  " > " + DoubleToString(m_adapter.MaxLot(), 2);
         return false;
      }

      if(!m_adapter.IsVolumeValid(volume))
      {
         reason = "Volume invalid against lot step: " + DoubleToString(volume, 2) +
                  " step=" + DoubleToString(m_adapter.LotStep(), 2);
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Validate stop distance against broker constraints                 |
   //+------------------------------------------------------------------+
   bool ValidateStopDistance(double entry, double stop, string &reason)
   {
      double dist = MathAbs(entry - stop);
      double distPoints = dist / m_adapter.Point();
      double minStopPoints = m_adapter.GetMinStopPoints();

      if(distPoints < minStopPoints)
      {
         reason = "Stop too close: " + DoubleToString(distPoints, 1) +
                  " pts < " + DoubleToString(minStopPoints, 0) + " pts min";
         return false;
      }

      // Check freeze level
      int freezeLevel = m_adapter.FreezeLevel();
      if(freezeLevel > 0 && distPoints < freezeLevel)
      {
         reason = "Stop within freeze level: " + DoubleToString(distPoints, 1) +
                  " pts < " + IntegerToString(freezeLevel) + " pts freeze";
         return false;
      }

      return true;
   }

   bool ValidateTargetDistance(double entry, double target, string &reason)
   {
      double distPoints = MathAbs(entry - target) / m_adapter.Point();
      double minimum = MathMax(m_adapter.GetMinStopPoints(),
                               (double)m_adapter.FreezeLevel());
      if(distPoints < minimum)
      {
         reason = "Target too close: " + DoubleToString(distPoints, 1) +
                  " pts < " + DoubleToString(minimum, 0) + " pts min";
         return false;
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Validate margin availability                                      |
   //+------------------------------------------------------------------+
   bool ValidateMargin(double volume, ENUM_ORDER_TYPE type, double price, string &reason)
   {
      double margin = 0;
      if(!OrderCalcMargin(type, m_adapter.Symbol(), volume, price, margin))
      {
         reason = "Cannot calculate margin";
         return false;
      }

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.95) // Leave 5% buffer
      {
         reason = "Insufficient margin: need=" + DoubleToString(margin, 2) +
                  " have=" + DoubleToString(freeMargin, 2);
         return false;
      }

      return true;
   }

private:
   //+------------------------------------------------------------------+
   //| Add an error to the list                                          |
   //+------------------------------------------------------------------+
   void AddError(string error)
   {
      if(m_errorCount < 20)
      {
         m_errors[m_errorCount] = error;
         m_errorCount++;
      }
   }
};

#endif // QB_DATAQUALITY_MQH
