//+------------------------------------------------------------------+
//|                                         QuantBeast/Diagnostics.mqh |
//|                          XAUUSD Quant Beast EA - Logging & Diag   |
//| Project: QuantBeast                                               |
//+------------------------------------------------------------------+
#property copyright "QuantBeast"
#property version   "1.00"
#property strict

#ifndef QB_DIAGNOSTICS_MQH
#define QB_DIAGNOSTICS_MQH

#include "Constants.mqh"
#include "TimeUtils.mqh"

//+------------------------------------------------------------------+
//| Global debug flag (set from Configuration)                        |
//+------------------------------------------------------------------+
bool QB_DebugEnabled = false;

//+------------------------------------------------------------------+
//| Initialize diagnostics                                             |
//+------------------------------------------------------------------+
void DiagInit(bool debugEnabled)
{
   QB_DebugEnabled = debugEnabled;
}

//+------------------------------------------------------------------+
//| Log levels                                                        |
//+------------------------------------------------------------------+
#define QB_LOG_INFO    0
#define QB_LOG_WARN    1
#define QB_LOG_ERROR   2
#define QB_LOG_DEBUG   3

string LogLevelStr(int level)
{
   switch(level)
   {
      case QB_LOG_INFO:  return "INFO";
      case QB_LOG_WARN:  return "WARN";
      case QB_LOG_ERROR: return "ERROR";
      case QB_LOG_DEBUG: return "DEBUG";
   }
   return "???";
}

//+------------------------------------------------------------------+
//| Core logging function                                             |
//+------------------------------------------------------------------+
void QBLog(int level, string message)
{
   if(level == QB_LOG_DEBUG && !QB_DebugEnabled) return;

   string prefix = QB_EA_NAME + "[" + LogLevelStr(level) + "] ";
   string fullMsg = prefix + message;

   if(level == QB_LOG_ERROR)
      Print("!!! " + fullMsg);
   else if(level == QB_LOG_WARN)
      Print("⚠ " + fullMsg);
   else if(level == QB_LOG_DEBUG)
      Print("[DBG] " + fullMsg);
   else
      Print(fullMsg);
}

//+------------------------------------------------------------------+
//| Convenience macros                                                |
//+------------------------------------------------------------------+
void QBLogInfo(string msg)  { QBLog(QB_LOG_INFO, msg); }
void QBLogWarn(string msg)  { QBLog(QB_LOG_WARN, msg); }
void QBLogError(string msg) { QBLog(QB_LOG_ERROR, msg); }
void QBLogDebug(string msg) { QBLog(QB_LOG_DEBUG, msg); }

//+------------------------------------------------------------------+
//| Log with value                                                    |
//+------------------------------------------------------------------+
void QBLogInfoV(string label, double value, int digits=2)
{
   QBLogInfo(label + " = " + DoubleToString(value, digits));
}

void QBLogInfoS(string label, string value)
{
   QBLogInfo(label + " = " + value);
}

//+------------------------------------------------------------------+
//| Separator for log readability                                     |
//+------------------------------------------------------------------+
void QBLogSeparator()
{
   QBLogInfo("══════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Section header                                                    |
//+------------------------------------------------------------------+
void QBLogSection(string section)
{
   QBLogInfo("── " + section + " ──");
}

//+------------------------------------------------------------------+
//| Write a CSV line to a file handle                                  |
//+------------------------------------------------------------------+
void WriteCSVLine(int handle, string line)
{
   if(handle == INVALID_HANDLE) return;
   FileWriteString(handle, line + "\r\n");
}

//+------------------------------------------------------------------+
//| Open a CSV journal file in common folder                          |
//+------------------------------------------------------------------+
int OpenJournalFile(string filename, string headers)
{
   string path = QB_LOG_DIR + filename;

   // Check if file exists to decide whether to write headers
   bool exists = FileIsExist(path, FILE_COMMON);

   int handle = FileOpen(path, FILE_COMMON|FILE_WRITE|FILE_READ|FILE_TXT|FILE_SHARE_READ, '\t');
   if(handle == INVALID_HANDLE)
   {
      QBLogError("Cannot open journal file: " + path + " error=" + IntegerToString(GetLastError()));
      return INVALID_HANDLE;
   }

   // Write headers if new file or empty
   if(!exists || FileSize(handle) == 0)
   {
      FileSeek(handle, 0, SEEK_END);
      WriteCSVLine(handle, headers);
      FileFlush(handle);
   }

   return handle;
}

//+------------------------------------------------------------------+
//| Safe CSV field (escape commas and quotes)                         |
//+------------------------------------------------------------------+
string CSVEscape(string field)
{
   if(StringFind(field, ",") >= 0 || StringFind(field, "\"") >= 0)
   {
      StringReplace(field, "\"", "\"\"");
      return "\"" + field + "\"";
   }
   return field;
}

//+------------------------------------------------------------------+
//| Format a CSV row from string array                                |
//+------------------------------------------------------------------+
string MakeCSVRow(string &fields[], int count)
{
   string row = "";
   for(int i = 0; i < count; i++)
   {
      if(i > 0) row += ",";
      row += CSVEscape(fields[i]);
   }
   return row;
}

//+------------------------------------------------------------------+
//| Get current timestamp string for logging                          |
//+------------------------------------------------------------------+
string NowStr()
{
   return FormatTime(TimeCurrent());
}

//+------------------------------------------------------------------+
//| Log a value change for monitoring                                 |
//+------------------------------------------------------------------+
void QBLogChange(string name, double oldVal, double newVal, int digits=5)
{
   if(MathAbs(newVal - oldVal) > QB_EPSILON)
   {
      QBLogDebug(name + ": " + DoubleToString(oldVal, digits) +
                 " → " + DoubleToString(newVal, digits));
   }
}

//+------------------------------------------------------------------+
//| Assert a condition and log failure                                |
//+------------------------------------------------------------------+
bool QBAssert(bool condition, string testName, string detail)
{
   if(!condition)
   {
      QBLogError("ASSERT FAILED: " + testName + " - " + detail);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Output broker/server diagnostic info                              |
//+------------------------------------------------------------------+
void DiagPrintBrokerInfo()
{
   QBLogSection("Broker / Server Info");
   QBLogInfoS("Account Server",   AccountInfoString(ACCOUNT_SERVER));
   QBLogInfoS("Account Company",  AccountInfoString(ACCOUNT_COMPANY));
   QBLogInfoS("Account Name",     AccountInfoString(ACCOUNT_NAME));
   QBLogInfoV("Account Number",   (double)AccountInfoInteger(ACCOUNT_LOGIN), 0);
   QBLogInfoS("Account Currency", AccountInfoString(ACCOUNT_CURRENCY));
   QBLogInfoV("Account Leverage", (double)AccountInfoInteger(ACCOUNT_LEVERAGE), 0);

   string accType = "Hedging";
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      accType = "Netting";
   QBLogInfoS("Account Type", accType);

   QBLogInfoV("Account Balance",  AccountInfoDouble(ACCOUNT_BALANCE), 2);
   QBLogInfoV("Account Equity",   AccountInfoDouble(ACCOUNT_EQUITY), 2);
   QBLogInfoV("Account Margin",   AccountInfoDouble(ACCOUNT_MARGIN), 2);
   QBLogInfoV("Free Margin",      AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2);
   QBLogInfoV("Margin Level (%)", AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2);

   QBLogInfoV("Trade Mode",       (double)AccountInfoInteger(ACCOUNT_TRADE_MODE), 0);
   QBLogInfoV("Trade Allowed",    (double)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED), 0);
   QBLogInfoV("Expert Allowed",   (double)AccountInfoInteger(ACCOUNT_TRADE_EXPERT), 0);
}

#endif // QB_DIAGNOSTICS_MQH
