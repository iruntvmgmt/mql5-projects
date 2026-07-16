//+------------------------------------------------------------------+
//|                                           QuantBeast/MarketData.mqh |
//|                          XAUUSD Quant Beast EA - Market Data     |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_MARKETDATA_MQH
#define QB_MARKETDATA_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"
#include "../Core/MathUtils.mqh"

// Normalize an executable price to the broker's tick grid. Display digits
// alone are insufficient on symbols whose tick size is coarser than _Point.
double QBNormalizePriceToTick(double price, double tickSize, int digits)
{
   if(!MathIsValidNumber(price)) return 0.0;
   if(tickSize <= 0.0) return NormalizeDouble(price, digits);

   double ticks = MathRound(price / tickSize);
   return NormalizeDouble(ticks * tickSize, digits);
}

//+------------------------------------------------------------------+
//| Symbol Adapter - dynamic symbol property access                   |
//+------------------------------------------------------------------+
class CSymbolAdapter
{
private:
   string            m_symbol;
   int               m_digits;
   double            m_point;
   double            m_tickSize;
   double            m_tickValue;
   double            m_contractSize;
   double            m_minLot;
   double            m_maxLot;
   double            m_lotStep;
   int               m_stopLevel;
   int               m_freezeLevel;
   double            m_marginInitial;
   double            m_marginMaintenance;
   bool              m_isTradeable;
   ENUM_SYMBOL_TRADE_MODE m_tradeMode;
   int               m_tradeStopsLevel;
   double            m_swapLong;
   double            m_swapShort;
   ENUM_SYMBOL_SWAP_MODE m_swapMode;

public:
   //+------------------------------------------------------------------+
   //| Constructor - reads all symbol props from active chart symbol     |
   //+------------------------------------------------------------------+
   CSymbolAdapter()
   {
      m_symbol = "";
      m_digits = 0;
      m_point  = 0;
      m_tickSize = 0;
      m_tickValue = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize with current chart symbol                              |
   //+------------------------------------------------------------------+
   bool Init(string symbolOverride = "")
   {
      m_symbol = (symbolOverride != "") ? symbolOverride : _Symbol;

      QBLogSection("Symbol Adapter: " + m_symbol);

      m_digits        = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_point         = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_tickSize      = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tickValue     = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_contractSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_minLot        = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_maxLot        = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_lotStep       = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_stopLevel     = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevel   = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      m_marginInitial = SymbolInfoDouble(m_symbol, SYMBOL_MARGIN_INITIAL);
      m_marginMaintenance = SymbolInfoDouble(m_symbol, SYMBOL_MARGIN_MAINTENANCE);
      m_tradeMode     = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
      m_tradeStopsLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

      // Swaps (may fail silently for some brokers)
      m_swapLong  = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_LONG);
      m_swapShort = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_SHORT);
      m_swapMode  = (ENUM_SYMBOL_SWAP_MODE)SymbolInfoInteger(m_symbol, SYMBOL_SWAP_MODE);

      m_isTradeable = (m_tradeMode == SYMBOL_TRADE_MODE_FULL || m_tradeMode == SYMBOL_TRADE_MODE_LONGONLY || m_tradeMode == SYMBOL_TRADE_MODE_SHORTONLY);

      // Validate critical properties
      if(m_point <= 0 || m_tickSize <= 0 || m_minLot <= 0)
      {
         QBLogError("INVALID symbol properties for " + m_symbol);
         QBLogInfoV("  Point", m_point, m_digits);
         QBLogInfoV("  TickSize", m_tickSize, m_digits);
         QBLogInfoV("  MinLot", m_minLot, 2);
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Print symbol diagnostics                                         |
   //+------------------------------------------------------------------+
   void PrintDiagnostics()
   {
      QBLogSection("Symbol Diagnostics: " + m_symbol);
      QBLogInfoV("  Digits", m_digits, 0);
      QBLogInfoV("  Point", m_point, m_digits);
      QBLogInfoV("  Tick Size", m_tickSize, m_digits);
      QBLogInfoV("  Tick Value", m_tickValue, 5);
      QBLogInfoV("  Contract Size", m_contractSize, 0);
      QBLogInfoV("  Min Lot", m_minLot, 2);
      QBLogInfoV("  Max Lot", m_maxLot, 2);
      QBLogInfoV("  Lot Step", m_lotStep, 2);
      QBLogInfoV("  Stop Level (pts)", m_stopLevel, 0);
      QBLogInfoV("  Freeze Level (pts)", m_freezeLevel, 0);
      QBLogInfoV("  Trade Stops Level", m_tradeStopsLevel, 0);
      QBLogInfoS("  Trade Mode", EnumToString(m_tradeMode));
      QBLogInfoS("  Is Tradeable", m_isTradeable ? "Yes" : "No");
      QBLogInfoV("  Swap Long", m_swapLong, 5);
      QBLogInfoV("  Swap Short", m_swapShort, 5);
   }

   //+------------------------------------------------------------------+
   //| Property accessors                                               |
   //+------------------------------------------------------------------+
   string Symbol()       const { return m_symbol; }
   int    Digits()       const { return m_digits; }
   double Point()        const { return m_point; }
   double TickSize()     const { return m_tickSize; }
   double TickValue()    const { return m_tickValue; }
   double ContractSize() const { return m_contractSize; }
   double MinLot()       const { return m_minLot; }
   double MaxLot()       const { return m_maxLot; }
   double LotStep()      const { return m_lotStep; }
   int    StopLevel()    const { return m_stopLevel; }
   int    FreezeLevel()  const { return m_freezeLevel; }
   bool   IsTradeable()  const { return m_isTradeable; }

   //+------------------------------------------------------------------+
   //| Normalize price to the broker's executable tick grid              |
   //+------------------------------------------------------------------+
   double NormalizePrice(double price) const
   {
      return QBNormalizePriceToTick(price, m_tickSize, m_digits);
   }

   //+------------------------------------------------------------------+
   //| Normalize volume to legal lot step                                |
   //+------------------------------------------------------------------+
   double NormalizeVolume(double volume) const
   {
      if(m_lotStep <= 0) return volume;

      double steps = MathRound(volume / m_lotStep);
      double normalized = steps * m_lotStep;

      normalized = Clamp(normalized, m_minLot, m_maxLot);

      int digits = 0;
      double scaledStep = m_lotStep;
      while(digits < 8 && MathAbs(scaledStep - MathRound(scaledStep)) > 1e-10)
      {
         scaledStep *= 10.0;
         digits++;
      }
      return NormalizeDouble(normalized, digits);
   }

   // Normalize down for partial closes and risk-constrained sizing. Never
   // rounds above the requested volume and returns zero below broker minimum.
   double NormalizeVolumeDown(double volume) const
   {
      if(volume < m_minLot - QB_EPSILON) return 0.0;
      if(m_lotStep <= 0) return MathMin(volume, m_maxLot);

      double normalized = MathFloor((volume + QB_EPSILON) / m_lotStep) * m_lotStep;
      normalized = MathMin(normalized, m_maxLot);
      if(normalized < m_minLot - QB_EPSILON) return 0.0;

      int digits = 0;
      double scaledStep = m_lotStep;
      while(digits < 8 && MathAbs(scaledStep - MathRound(scaledStep)) > 1e-10)
      {
         scaledStep *= 10.0;
         digits++;
      }
      return NormalizeDouble(normalized, digits);
   }

   //+------------------------------------------------------------------+
   //| Check if a volume is valid                                        |
   //+------------------------------------------------------------------+
   bool IsVolumeValid(double volume) const
   {
      if(volume < m_minLot - QB_EPSILON) return false;
      if(volume > m_maxLot + QB_EPSILON) return false;

      // Check lot step
      if(m_lotStep > 0)
      {
         double remainder = MathMod(volume - m_minLot, m_lotStep);
         if(remainder > QB_EPSILON && MathAbs(remainder - m_lotStep) > QB_EPSILON)
            return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get minimum stop distance in points (broker stop level)           |
   //+------------------------------------------------------------------+
   int GetMinStopPoints() const
   {
      return m_stopLevel;
   }

   //+------------------------------------------------------------------+
   //| Convert points to price distance                                  |
   //+------------------------------------------------------------------+
   double PointsToPrice(double points) const
   {
      return points * m_point;
   }

   //+------------------------------------------------------------------+
   //| Convert price distance to points                                  |
   //+------------------------------------------------------------------+
   double PriceToPoints(double priceDist) const
   {
      if(m_point <= 0) return 0;
      return priceDist / m_point;
   }

   //+------------------------------------------------------------------+
   //| Get pip value (for gold, 1 pip = 0.01 for most brokers)           |
   //+------------------------------------------------------------------+
   double PipSize() const
   {
      // For XAUUSD, pip is typically 0.01 (10 points when point=0.001)
      // But we compute dynamically
      return m_point * 10.0;
   }

   //+------------------------------------------------------------------+
   //| Calculate tick value for a given lot size                         |
   //+------------------------------------------------------------------+
   double LotTickValue(double lots) const
   {
      return m_tickValue * lots;
   }

   //+------------------------------------------------------------------+
   //| Calculate profit for given distance and volume                    |
   //+------------------------------------------------------------------+
   double CalculateProfit(double volume, double priceEntry, double priceExit, int direction) const
   {
      // direction: 1 for long, -1 for short
      double diff = (priceExit - priceEntry) * direction;
      double profit = diff * m_contractSize * volume;
      return profit;
   }

   //+------------------------------------------------------------------+
   //| Is this a recognized gold symbol?                                 |
   //+------------------------------------------------------------------+
   bool IsGoldSymbol() const
   {
      string symUpper = m_symbol;
      StringToUpper(symUpper);
      return (StringFind(symUpper, "XAU") >= 0 ||
              StringFind(symUpper, "GOLD") >= 0);
   }
};

//+------------------------------------------------------------------+
//| Market Snapshot Factory                                            |
//+------------------------------------------------------------------+
class CMarketSnapshotFactory
{
private:
   CSymbolAdapter* m_adapter;

public:
   CMarketSnapshotFactory(CSymbolAdapter &adapter)
   {
      m_adapter = &adapter;
   }

   //+------------------------------------------------------------------+
   //| Build a market snapshot from current tick                         |
   //+------------------------------------------------------------------+
   MarketSnapshot Capture(int staleQuoteMs = QB_STALE_QUOTE_MS_DEFAULT)
   {
      MarketSnapshot snap;
      ZeroMemory(snap);

      snap.time         = TimeCurrent();
      snap.bid          = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_BID);
      snap.ask          = SymbolInfoDouble(m_adapter.Symbol(), SYMBOL_ASK);
      snap.mid          = (snap.bid + snap.ask) / 2.0;
      snap.spread_points = (snap.ask - snap.bid) / m_adapter.Point();
      snap.spread_price  = (snap.ask - snap.bid);
      snap.tick_volume  = SymbolInfoInteger(m_adapter.Symbol(), SYMBOL_VOLUME);
      snap.real_volume  = 0; // OTC gold typically has no real volume

      // Freshness check
      datetime tickTime = (datetime)SymbolInfoInteger(m_adapter.Symbol(), SYMBOL_TIME);
      int staleSeconds = MathMax(1, (staleQuoteMs + 999) / 1000);
      snap.is_fresh = (TimeCurrent() - tickTime) < staleSeconds;

      // Tradeable check
      snap.is_tradeable = m_adapter.IsTradeable() &&
                          TerminalInfoInteger(TERMINAL_CONNECTED) &&
                          AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
                          AccountInfoInteger(ACCOUNT_TRADE_EXPERT);

      return snap;
   }

   //+------------------------------------------------------------------+
   //| Validate a market snapshot                                        |
   //+------------------------------------------------------------------+
   bool Validate(const MarketSnapshot &snap, double maxSpreadPoints)
   {
      // Bid/ask sanity
      if(snap.bid <= 0 || snap.ask <= 0)
      {
         QBLogWarn("Invalid bid/ask: bid=" + DoubleToString(snap.bid) +
                   " ask=" + DoubleToString(snap.ask));
         return false;
      }

      if(snap.ask <= snap.bid)
      {
         QBLogWarn("Ask <= Bid: " + DoubleToString(snap.bid) +
                   " / " + DoubleToString(snap.ask));
         return false;
      }

      // Spread check
      if(snap.spread_points > maxSpreadPoints)
      {
         QBLogDebug("Spread too high: " + DoubleToString(snap.spread_points, 1) +
                    " > " + DoubleToString(maxSpreadPoints, 1));
         return false;
      }

      // Freshness
      if(!snap.is_fresh)
      {
         QBLogWarn("Stale quote for " + m_adapter.Symbol());
         return false;
      }

      // Tradeable
      if(!snap.is_tradeable)
      {
         QBLogDebug("Symbol not tradeable");
         return false;
      }

      return true;
   }
};

#endif // QB_MARKETDATA_MQH
