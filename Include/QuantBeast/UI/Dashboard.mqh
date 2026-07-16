//+------------------------------------------------------------------+
//|                                            QuantBeast/Dashboard.mqh|
//|                          XAUUSD Quant Beast EA - On-Chart Dashboard|
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_DASHBOARD_MQH
#define QB_DASHBOARD_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Diagnostics.mqh"

//+------------------------------------------------------------------+
//| Dashboard - efficient on-chart status display                     |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   bool     m_enabled;
   int      m_x, m_y;
   int      m_fontSize;
   color    m_color;
   string   m_objPrefix;
   int      m_lineCount;
   datetime m_lastUpdate;
   int      m_updateIntervalSec;
   bool     m_initialized;

   // Object names for each line
   string   m_objNames[30];

public:
   //+------------------------------------------------------------------+
   CDashboard()
   {
      m_enabled = false;
      m_x = 10; m_y = 20;
      m_fontSize = 8;
      m_color = clrWhite;
      m_objPrefix = "QB_Dash_";
      m_lineCount = 0;
      m_lastUpdate = 0;
      m_updateIntervalSec = 1; // Update every second
      m_initialized = false;
   }

   //+------------------------------------------------------------------+
   ~CDashboard()
   {
      Clear();
   }

   //+------------------------------------------------------------------+
   void Init(bool enabled, int x, int y, int fontSize, color clr)
   {
      m_enabled  = enabled;
      m_x        = x;
      m_y        = y;
      m_fontSize = fontSize;
      m_color    = clr;

      if(!m_enabled) return;

      m_initialized = true;
   }

   //+------------------------------------------------------------------+
   void Clear()
   {
      for(int i = 0; i < m_lineCount; i++)
      {
         ObjectDelete(0, m_objNames[i]);
      }
      m_lineCount = 0;

      // Also delete any leftover objects with prefix
      ObjectsDeleteAll(0, m_objPrefix);
   }

   //+------------------------------------------------------------------+
   //| Create a text label on chart                                      |
   //+------------------------------------------------------------------+
   void CreateLabel(int index, string text, color clr = clrWhite)
   {
      string name = m_objPrefix + IntegerToString(index);
      m_objNames[index] = name;

      int yPos = m_y + index * (m_fontSize + 2);

      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_fontSize);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }

      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
   }

   //+------------------------------------------------------------------+
   //| Update dashboard with current system state                        |
   //+------------------------------------------------------------------+
   void Update(string symbolName, ENUM_QB_MODE mode, ENUM_SESSION_TYPE session,
               ENUM_TREND_REGIME trend, ENUM_VOLATILITY_REGIME vol,
               ENUM_LIQUIDITY_REGIME liq, ENUM_STRUCTURE_REGIME structure,
               double spread, int posCount, int pendCount,
               double dailyPnL, double drawdown, double dailyLossRemain,
               string killStatus, string challengeInfo, string lastSignal,
               string lastRejection)
   {
      if(!m_enabled || !m_initialized) return;

      // Throttle updates
      if(TimeCurrent() - m_lastUpdate < m_updateIntervalSec) return;
      m_lastUpdate = TimeCurrent();

      int line = 0;

      CreateLabel(line++, QB_EA_NAME + " v" + QB_VERSION + " | " + symbolName, clrGold);

      string modeStr = "";
      switch(mode)
      {
         case QB_MODE_DIAGNOSTIC:        modeStr = "DIAGNOSTIC"; break;
         case QB_MODE_SHADOW:            modeStr = "SHADOW";      break;
         case QB_MODE_CONSERVATIVE_LIVE: modeStr = "LIVE (CONS)"; break;
         case QB_MODE_CHALLENGE_LIVE:    modeStr = "LIVE (CHAL)"; break;
      }
      CreateLabel(line++, "Mode: " + modeStr);

      CreateLabel(line++, "Sess: " + EnumToString(session) +
                  " | Spread: " + DoubleToString(spread, 1));

      CreateLabel(line++, "T:" + EnumToString(trend) +
                  " V:" + EnumToString(vol) +
                  " L:" + EnumToString(liq));

      CreateLabel(line++, "S:" + EnumToString(structure) +
                  " | Pos:" + IntegerToString(posCount) +
                  " Pend:" + IntegerToString(pendCount));

      CreateLabel(line++, "Day PnL: $" + DoubleToString(dailyPnL, 2) +
                  " | DD: " + DoubleToString(drawdown, 1) + "%");

      if(dailyLossRemain > 0)
         CreateLabel(line++, "Day Loss Remain: $" + DoubleToString(dailyLossRemain, 2),
                     dailyLossRemain < 10 ? clrRed : clrWhite);

      if(killStatus != "OK")
         CreateLabel(line++, "KILL: " + killStatus, clrRed);

      if(challengeInfo != "")
         CreateLabel(line++, challengeInfo, clrGold);

      if(lastSignal != "")
         CreateLabel(line++, "Last Signal: " + lastSignal);

      if(lastRejection != "")
         CreateLabel(line++, "Reject: " + lastRejection, clrOrange);

      m_lineCount = line;

      // Clean up old lines
      for(int i = line; i < 30; i++)
      {
         if(ObjectFind(0, m_objPrefix + IntegerToString(i)) >= 0)
            ObjectDelete(0, m_objPrefix + IntegerToString(i));
      }
   }

   //+------------------------------------------------------------------+
   //| Update for diagnostic mode (extended info)                        |
   //+------------------------------------------------------------------+
   void UpdateDiagnostic(CSymbolAdapter &adapter, bool connected,
                          bool tradeAllowed, bool eaAllowed,
                          int selfTestPassed, int selfTestFailed)
   {
      if(!m_enabled) return;

      if(TimeCurrent() - m_lastUpdate < m_updateIntervalSec) return;
      m_lastUpdate = TimeCurrent();

      int line = 20; // Offset for diag info below main dashboard

      CreateLabel(line++, "══════ DIAGNOSTIC ══════", clrCyan);
      CreateLabel(line++, "Connected: " + (connected ? "YES" : "NO"),
                  connected ? clrGreen : clrRed);
      CreateLabel(line++, "Trade Allowed: " + (tradeAllowed ? "YES" : "NO"),
                  tradeAllowed ? clrGreen : clrRed);
      CreateLabel(line++, "EA Allowed: " + (eaAllowed ? "YES" : "NO"),
                  eaAllowed ? clrGreen : clrRed);
      CreateLabel(line++, "Point: " + DoubleToString(adapter.Point(), adapter.Digits()) +
                  " | TickSz: " + DoubleToString(adapter.TickSize(), adapter.Digits()));
      CreateLabel(line++, "MinLot: " + DoubleToString(adapter.MinLot(), 2) +
                  " | MaxLot: " + DoubleToString(adapter.MaxLot(), 2));
      CreateLabel(line++, "Tests: " + IntegerToString(selfTestPassed) + "P/" +
                  IntegerToString(selfTestFailed) + "F",
                  selfTestFailed == 0 ? clrGreen : clrRed);

      m_lineCount = line;
   }
};

#endif // QB_DASHBOARD_MQH
