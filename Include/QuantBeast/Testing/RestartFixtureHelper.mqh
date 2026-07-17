//+------------------------------------------------------------------+
//|                                          RestartFixtureHelper.mqh |
//|  Included by QuantBeastEA.mq5 for restart-recovery testing        |
//|  Provides script-equivalent functions callable from the EA.       |
//+------------------------------------------------------------------+
#property copyright "QuantBeast Restart Fixture"
#property version   "1.00"

#ifndef _RESTART_FIXTURE_HELPER_MQH_
#define _RESTART_FIXTURE_HELPER_MQH_

#include <Trade/Trade.mqh>

// --- Commands ---
enum ENUM_FIXTURE_CMD
{
   FIXT_CMD_NONE = -1,
   FIXT_CMD_REPORT = 0,
   FIXT_CMD_PLACE_OWNED = 1,
   FIXT_CMD_PLACE_PENDING = 2,
   FIXT_CMD_PLACE_UNKNOWN = 3,
   FIXT_CMD_WRITE_CORRUPT = 4,
   FIXT_CMD_CLEANUP_ALL = 5,
   FIXT_CMD_DELETE_CORRUPT = 6
};

// --- Magic numbers ---
#define FIXTURE_MAGIC_OWNED    20260701
#define FIXTURE_MAGIC_PENDING  20260801
#define FIXTURE_MAGIC_UNKNOWN  99999999
#define FIXTURE_GLOBAL_PREFIX  "QB_FIX_"

//+------------------------------------------------------------------+
//| Report current account state                                      |
//+------------------------------------------------------------------+
void FixtureReport()
{
   Print("=== QB FIXTURE REPORT ===");
   Print("Account: ", AccountInfoInteger(ACCOUNT_LOGIN),
         "  Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
         "  Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
         "  Margin: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2));

   int posTotal = PositionsTotal();
   Print("Positions: ", posTotal);
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      Print("  POS ticket=", ticket,
            " symbol=", PositionGetString(POSITION_SYMBOL),
            " type=", EnumToString((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)),
            " volume=", DoubleToString(PositionGetDouble(POSITION_VOLUME), 2),
            " open=", DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 2),
            " sl=", DoubleToString(PositionGetDouble(POSITION_SL), 2),
            " tp=", DoubleToString(PositionGetDouble(POSITION_TP), 2),
            " magic=", PositionGetInteger(POSITION_MAGIC),
            " comment=", PositionGetString(POSITION_COMMENT));
   }

   int ordTotal = OrdersTotal();
   Print("Orders: ", ordTotal);
   for(int i = 0; i < ordTotal; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      Print("  ORD ticket=", ticket,
            " symbol=", OrderGetString(ORDER_SYMBOL),
            " type=", EnumToString((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)),
            " volume=", DoubleToString(OrderGetDouble(ORDER_VOLUME_INITIAL), 2),
            " price=", DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), 2),
            " magic=", OrderGetInteger(ORDER_MAGIC));
   }

   Print("=== QB FIXTURE REPORT END ===");
}

//+------------------------------------------------------------------+
//| Place a market order                                              |
//+------------------------------------------------------------------+
void FixturePlaceMarket(ulong magic, string comment)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = "XAUUSD";
   req.volume    = 0.01;
   req.type      = ORDER_TYPE_BUY;
   req.price     = SymbolInfoDouble("XAUUSD", SYMBOL_ASK);
   req.sl        = 3000.00;
   req.tp        = 5000.00;
   req.deviation = 100;
   req.magic     = (int)magic;
   req.comment   = comment;

   Print("FIXTURE: Sending market BUY 0.01 XAUUSD magic=", magic, " comment=", comment,
         " ask=", DoubleToString(req.price, 2));

   if(!OrderSend(req, res))
   {
      Print("FIXTURE ERROR: OrderSend failed: ", GetLastError());
      return;
   }

   Print("FIXTURE: OrderSend retcode=", res.retcode,
         " order=", res.order, " deal=", res.deal,
         " price=", DoubleToString(res.price, 2));
}

//+------------------------------------------------------------------+
//| Place a pending order                                             |
//+------------------------------------------------------------------+
void FixturePlacePending(ulong magic, string comment)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   double currentPrice = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
   double limitPrice   = NormalizeDouble(currentPrice - 50.00, 2);

   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = "XAUUSD";
   req.volume    = 0.01;
   req.type      = ORDER_TYPE_BUY_LIMIT;
   req.price     = limitPrice;
   req.sl        = 3000.00;
   req.tp        = 5000.00;
   req.magic     = (int)magic;
   req.comment   = comment;

   Print("FIXTURE: Sending BUY LIMIT 0.01 XAUUSD @ ", DoubleToString(limitPrice, 2),
         " magic=", magic);

   if(!OrderSend(req, res))
   {
      Print("FIXTURE ERROR: OrderSend failed: ", GetLastError());
      return;
   }

   Print("FIXTURE: OrderSend retcode=", res.retcode, " order=", res.order);
}

//+------------------------------------------------------------------+
//| Write incompatible state version                                  |
//+------------------------------------------------------------------+
void FixtureWriteCorrupt()
{
   GlobalVariableSet(FIXTURE_GLOBAL_PREFIX + "SCHEMA", 999);
   GlobalVariableSet(FIXTURE_GLOBAL_PREFIX + "MARKER", 1);
   GlobalVariablesFlush();
   Print("FIXTURE: Wrote corrupt state schema=999");
}

//+------------------------------------------------------------------+
//| Clean up all positions, orders, fixture globals                   |
//+------------------------------------------------------------------+
void FixtureCleanupAll()
{
   Print("=== FIXTURE CLEANUP START ===");

   // Close all XAUUSD positions
   int posTotal = PositionsTotal();
   for(int i = posTotal - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != "XAUUSD") continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = "XAUUSD";
      req.volume    = PositionGetDouble(POSITION_VOLUME);
      req.type      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                      ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.position  = ticket;
      req.price     = (req.type == ORDER_TYPE_SELL)
                      ? SymbolInfoDouble("XAUUSD", SYMBOL_BID)
                      : SymbolInfoDouble("XAUUSD", SYMBOL_ASK);
      req.deviation = 100;
      req.comment   = "QB fixture cleanup";

      Print("FIXTURE: Closing position ", ticket);
      if(!OrderSend(req, res))
         Print("FIXTURE ERROR: close failed: ", GetLastError());
      else
         Print("FIXTURE: close retcode=", res.retcode, " deal=", res.deal);
   }

   // Cancel all XAUUSD pending orders
   int ordTotal = OrdersTotal();
   for(int i = ordTotal - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != "XAUUSD") continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action  = TRADE_ACTION_REMOVE;
      req.order   = ticket;
      req.comment = "QB fixture cleanup";

      Print("FIXTURE: Cancelling order ", ticket);
      if(!OrderSend(req, res))
         Print("FIXTURE ERROR: cancel failed: ", GetLastError());
      else
         Print("FIXTURE: cancel retcode=", res.retcode);
   }

   // Delete fixture globals
   for(int v = GlobalVariablesTotal() - 1; v >= 0; v--)
   {
      string name = GlobalVariableName(v);
      if(StringFind(name, FIXTURE_GLOBAL_PREFIX) == 0)
      {
         Print("FIXTURE: Deleting global ", name);
         GlobalVariableDel(name);
      }
   }
   GlobalVariablesFlush();

   Print("=== FIXTURE CLEANUP END ===");
}

//+------------------------------------------------------------------+
//| Delete only corrupt globals                                       |
//+------------------------------------------------------------------+
void FixtureDeleteCorrupt()
{
   for(int v = GlobalVariablesTotal() - 1; v >= 0; v--)
   {
      string name = GlobalVariableName(v);
      if(StringFind(name, FIXTURE_GLOBAL_PREFIX) == 0)
      {
         GlobalVariableDel(name);
      }
   }
   GlobalVariablesFlush();
   Print("FIXTURE: Deleted corrupt globals");
}

#endif // _RESTART_FIXTURE_HELPER_MQH_
