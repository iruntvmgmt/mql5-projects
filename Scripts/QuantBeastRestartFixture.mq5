//+------------------------------------------------------------------+
//|                                       QuantBeastRestartFixture.mq5 |
//|  Single-purpose script for restart-recovery scenario construction |
//|  and cleanup on Coinexx-Demo. Never use on a live account.        |
//+------------------------------------------------------------------+
#property copyright "QuantBeast Restart Fixture"
#property version   "1.10"
#property script_show_inputs

// --- Commands ---
enum ENUM_FIXTURE_CMD
{
   CMD_REPORT,          // 0: dump positions, orders, globals
   CMD_PLACE_OWNED,     // 1: scenario 1 — owned position (magic 20260701)
   CMD_PLACE_PENDING,   // 2: scenario 2 — pending order (magic 20260801)
   CMD_PLACE_UNKNOWN,   // 3: scenario 3 — unknown position (magic 99999999)
   CMD_WRITE_CORRUPT,   // 4: scenario 4 — write incompatible state version
   CMD_CLEANUP_ALL,     // 5: close all positions, cancel all orders, delete fixture globals
   CMD_DELETE_CORRUPT,  // 6: delete only the corrupt-state globals
   CMD_CLEAR_KILL_STATE // 7: delete persisted QuantBeast kill-switch globals
};

input ENUM_FIXTURE_CMD InpCommand = CMD_REPORT;

// --- Magic numbers ---
#define FIXTURE_MAGIC_OWNED    20260701   // Inside QB range (BO strategy)
#define FIXTURE_MAGIC_PENDING  20260801   // Inside QB range (FBO strategy)
#define FIXTURE_MAGIC_UNKNOWN  99999999   // Far outside QB range
#define FIXTURE_GLOBAL_PREFIX  "QB_FIX_"

//+------------------------------------------------------------------+
//| Report current state                                              |
//+------------------------------------------------------------------+
void DoReport()
{
   Print("=== FIXTURE REPORT ===");
   Print("Account: ", AccountInfoInteger(ACCOUNT_LOGIN),
         "  Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
         "  Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
         "  Margin: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2));

   // Positions
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

   // Orders
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
            " sl=", DoubleToString(OrderGetDouble(ORDER_SL), 2),
            " tp=", DoubleToString(OrderGetDouble(ORDER_TP), 2),
            " magic=", OrderGetInteger(ORDER_MAGIC),
            " comment=", OrderGetString(ORDER_COMMENT));
   }

   // Fixture globals
   Print("Fixture globals:");
   for(int v = 0; v < GlobalVariablesTotal(); v++)
   {
      string name = GlobalVariableName(v);
      if(StringFind(name, FIXTURE_GLOBAL_PREFIX) == 0 ||
         StringFind(name, "QB_STATE_") == 0 ||
         StringFind(name, "QB_RISK_") == 0 ||
         StringFind(name, "QB_KILL_") == 0 ||
         StringFind(name, "QB_CHALLENGE_") == 0 ||
         StringFind(name, "QB_STRAT_") == 0 ||
         StringFind(name, "QB_ARB_") == 0)
      {
         Print("  ", name, " = ", DoubleToString(GlobalVariableGet(name), 0));
      }
   }

   Print("=== FIXTURE REPORT END ===");
}

//+------------------------------------------------------------------+
//| Place a market order                                              |
//+------------------------------------------------------------------+
void DoPlaceMarket(ulong magic, string comment)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   string sym = _Symbol;
   double askPrice = SymbolInfoDouble(sym, SYMBOL_ASK);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double stopDist = 50.0 * point * 100;
   double tgtDist  = 100.0 * point * 100;

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = sym;
   req.volume    = 0.01;
   req.type      = ORDER_TYPE_BUY;
   req.price     = askPrice;
   req.sl        = NormalizeDouble(askPrice - stopDist, digits);
   req.tp        = NormalizeDouble(askPrice + tgtDist, digits);
   req.deviation = 500;
   req.magic     = (int)magic;
   req.comment   = comment;

   Print("Sending market BUY 0.01 ", sym, "  magic=", magic, "  comment=", comment,
         "  ask=", DoubleToString(askPrice, digits),
         "  sl=", DoubleToString(req.sl, digits),
         "  tp=", DoubleToString(req.tp, digits));

   if(!OrderSend(req, res))
   {
      Print("ERROR: OrderSend failed: ", GetLastError(),
            "  retcode=", res.retcode);
      return;
   }

   Print("OrderSend result: retcode=", res.retcode,
         "  order=", res.order,
         "  deal=", res.deal,
         "  volume=", DoubleToString(res.volume, 2),
         "  price=", DoubleToString(res.price, 2));

   if(res.retcode == 10009 || res.retcode == 10008)
      Print("SUCCESS: position opened  ticket=", res.order);
   else
      Print("WARNING: unexpected retcode ", res.retcode, " — check MT5 terminal");
}

//+------------------------------------------------------------------+
//| Place a pending order                                             |
//+------------------------------------------------------------------+
void DoPlacePending(ulong magic, string comment)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   string sym = _Symbol;
   double currentPrice = SymbolInfoDouble(sym, SYMBOL_BID);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double limitPrice = NormalizeDouble(currentPrice - 50.0 * point * 100, digits);

   req.action    = TRADE_ACTION_PENDING;
   req.symbol    = sym;
   req.volume    = 0.01;
   req.type      = ORDER_TYPE_BUY_LIMIT;
   req.price     = limitPrice;
   req.sl        = NormalizeDouble(limitPrice - 50.0 * point * 100, digits);
   req.tp        = NormalizeDouble(limitPrice + 100.0 * point * 100, digits);
   req.magic     = (int)magic;
   req.comment   = comment;

   Print("Sending BUY LIMIT 0.01 ", sym, " @ ", DoubleToString(limitPrice, digits),
         "  magic=", magic, "  comment=", comment);

   if(!OrderSend(req, res))
   {
      Print("ERROR: OrderSend failed: ", GetLastError());
      return;
   }

   Print("OrderSend result: retcode=", res.retcode,
         "  order=", res.order,
         "  volume=", DoubleToString(res.volume, 2),
         "  price=", DoubleToString(res.price, 2));

   if(res.retcode == 10009)
      Print("SUCCESS: pending order placed  ticket=", res.order);
   else
      Print("WARNING: unexpected retcode ", res.retcode, " — check MT5 terminal");
}

//+------------------------------------------------------------------+
//| Write incompatible state version to terminal globals              |
//+------------------------------------------------------------------+
void DoWriteCorrupt()
{
   GlobalVariableSet(FIXTURE_GLOBAL_PREFIX + "SCHEMA", 999);
   GlobalVariableSet(FIXTURE_GLOBAL_PREFIX + "MARKER", 1);
   GlobalVariablesFlush();

   Print("Wrote corrupt state: schema=999 (incompatible with current v4)");
   Print("Fixture globals set: ", FIXTURE_GLOBAL_PREFIX, "SCHEMA=999  MARKER=1");
}

//+------------------------------------------------------------------+
//| Close a position by ticket                                        |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("ERROR: cannot select position ", ticket, " for close");
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = PositionGetString(POSITION_SYMBOL);
   req.volume    = PositionGetDouble(POSITION_VOLUME);
   req.type      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                   ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.position  = ticket;
   req.price     = (req.type == ORDER_TYPE_SELL)
                   ? SymbolInfoDouble(req.symbol, SYMBOL_BID)
                   : SymbolInfoDouble(req.symbol, SYMBOL_ASK);
   req.deviation = 500;
   req.comment   = "QB fixture cleanup";

   Print("Closing position ", ticket, "  type=", EnumToString((ENUM_ORDER_TYPE)req.type));

   if(!OrderSend(req, res))
   {
      Print("ERROR: OrderSend close failed: ", GetLastError());
      return false;
   }

   Print("Close result: retcode=", res.retcode, "  deal=", res.deal);
   return (res.retcode == 10009 || res.retcode == 10008);
}

//+------------------------------------------------------------------+
//| Cancel an order by ticket                                         |
//+------------------------------------------------------------------+
bool CancelOrder(ulong ticket)
{
   if(!OrderSelect(ticket))
   {
      Print("ERROR: cannot select order ", ticket, " for cancel");
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_REMOVE;
   req.order    = ticket;
   req.comment  = "QB fixture cleanup";

   Print("Cancelling order ", ticket);

   if(!OrderSend(req, res))
   {
      Print("ERROR: OrderSend cancel failed: ", GetLastError());
      return false;
   }

   Print("Cancel result: retcode=", res.retcode);
   return (res.retcode == 10009);
}

//+------------------------------------------------------------------+
//| Clean up all positions, orders, and fixture globals               |
//+------------------------------------------------------------------+
void DoCleanupAll()
{
   Print("=== FIXTURE CLEANUP START ===");

   string sym = _Symbol;
   int posTotal = PositionsTotal();
   ulong posTickets[];
   ArrayResize(posTickets, posTotal);
   int posCount = 0;
   for(int i = 0; i < posTotal; i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      posTickets[posCount++] = t;
   }
   for(int i = 0; i < posCount; i++)
   {
      Print("Cleanup: closing position ", posTickets[i]);
      ClosePosition(posTickets[i]);
   }

   int ordTotal = OrdersTotal();
   ulong ordTickets[];
   ArrayResize(ordTickets, ordTotal);
   int ordCount = 0;
   for(int i = 0; i < ordTotal; i++)
   {
      ulong t = OrderGetTicket(i);
      if(!OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL) != sym) continue;
      ordTickets[ordCount++] = t;
   }
   for(int i = 0; i < ordCount; i++)
   {
      Print("Cleanup: cancelling order ", ordTickets[i]);
      CancelOrder(ordTickets[i]);
   }

   for(int v = GlobalVariablesTotal() - 1; v >= 0; v--)
   {
      string name = GlobalVariableName(v);
      if(StringFind(name, FIXTURE_GLOBAL_PREFIX) == 0)
      {
         Print("Cleanup: deleting global ", name);
         GlobalVariableDel(name);
      }
   }
   GlobalVariablesFlush();

   Print("=== FIXTURE CLEANUP END ===");
}

//+------------------------------------------------------------------+
//| Delete only corrupt globals                                       |
//+------------------------------------------------------------------+
void DoDeleteCorrupt()
{
   Print("=== DELETE CORRUPT GLOBALS ===");
   for(int v = GlobalVariablesTotal() - 1; v >= 0; v--)
   {
      string name = GlobalVariableName(v);
      if(StringFind(name, FIXTURE_GLOBAL_PREFIX) == 0)
      {
         Print("Deleting global ", name);
         GlobalVariableDel(name);
      }
   }
   GlobalVariablesFlush();
   Print("=== DELETE CORRUPT END ===");
}

//+------------------------------------------------------------------+
//| Clear persisted QuantBeast kill-switch state                       |
//+------------------------------------------------------------------+
void DoClearKillState()
{
   Print("=== CLEAR KILL STATE ===");
   Print("WARNING: manually clearing persisted kill-switch state");

   string killGlobals[] = {
      "QB_KillEntries", "QB_KillSymbol", "QB_KillCancel", "QB_KillFlatten",
      "QB_KillBO", "QB_KillFBO", "QB_KillTP", "QB_KillMR", "QB_Emergency"
   };

   for(int i = 0; i < ArraySize(killGlobals); i++)
   {
      if(GlobalVariableCheck(killGlobals[i]))
      {
         double val = GlobalVariableGet(killGlobals[i]);
         Print("WARNING: deleting kill global: ", killGlobals[i], " = ", DoubleToString(val, 0));
         GlobalVariableDel(killGlobals[i]);
      }
      else
      {
         Print("Kill global not present: ", killGlobals[i]);
      }
   }
   GlobalVariablesFlush();
   Print("=== CLEAR KILL STATE END ===");
}

//+------------------------------------------------------------------+
//| Script entry point                                                |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("QuantBeastRestartFixture  v1.10  cmd=", EnumToString(InpCommand),
         "  symbol=", _Symbol);

   switch(InpCommand)
   {
      case CMD_REPORT:
         DoReport();
         break;

      case CMD_PLACE_OWNED:
         DoPlaceMarket(FIXTURE_MAGIC_OWNED, "QB_FBO_fixture");
         DoReport();
         break;

      case CMD_PLACE_PENDING:
         DoPlacePending(FIXTURE_MAGIC_PENDING, "QB_FBO_fixture_pending");
         DoReport();
         break;

      case CMD_PLACE_UNKNOWN:
         DoPlaceMarket(FIXTURE_MAGIC_UNKNOWN, "FIXTURE_UNKNOWN");
         DoReport();
         break;

      case CMD_WRITE_CORRUPT:
         DoWriteCorrupt();
         DoReport();
         break;

      case CMD_CLEANUP_ALL:
         DoCleanupAll();
         DoReport();
         break;

      case CMD_DELETE_CORRUPT:
         DoDeleteCorrupt();
         DoReport();
         break;

      case CMD_CLEAR_KILL_STATE:
         DoClearKillState();
         DoReport();
         break;

      default:
         Print("ERROR: unknown command");
         break;
   }
}
//+------------------------------------------------------------------+