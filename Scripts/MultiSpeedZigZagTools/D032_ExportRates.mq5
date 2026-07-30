#property strict
#property script_show_inputs

// D032: exports the full-window closed-bar OHLC series used to simulate
// D031's six-family shadow candidates. Read-only (CopyRates only), never
// touches a position or order. Symbol/timeframe/dates match the frozen
// D029/D031 P4 window exactly (2025.03.01-2026.07.24, XAUUSD M5), so the
// candidate outcomes simulated against this series are directly
// comparable to the certified P4 evidence.

input string InpFromDate="2025.03.01";
input string InpToDate="2026.07.25"; // one day past ToDate so the last real bar is included

void OnStart()
{
   datetime from=StringToTime(InpFromDate);
   datetime to=StringToTime(InpToDate);
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,_Period,from,to,rates);
   if(copied<=0)
   {
      PrintFormat("D032_ExportRates failed: copied=%d error=%d",copied,GetLastError());
      return;
   }

   int h=FileOpen("D032_Rates_XAUUSD_M5.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("D032_ExportRates: file open failed error=%d",GetLastError());
      return;
   }
   FileWrite(h,"time","open","high","low","close","spread");
   for(int i=0;i<copied;i++)
      FileWrite(h,TimeToString(rates[i].time,TIME_DATE|TIME_SECONDS),
                DoubleToString(rates[i].open,_Digits),DoubleToString(rates[i].high,_Digits),
                DoubleToString(rates[i].low,_Digits),DoubleToString(rates[i].close,_Digits),
                rates[i].spread);
   FileFlush(h);
   FileClose(h);
   PrintFormat("D032_ExportRates complete bars=%d first=%s last=%s",copied,
               TimeToString(rates[0].time,TIME_DATE|TIME_SECONDS),
               TimeToString(rates[copied-1].time,TIME_DATE|TIME_SECONDS));
}
