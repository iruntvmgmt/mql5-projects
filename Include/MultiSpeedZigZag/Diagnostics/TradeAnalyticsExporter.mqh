#ifndef __MSZZ_TRADE_ANALYTICS_EXPORTER_MQH__
#define __MSZZ_TRADE_ANALYTICS_EXPORTER_MQH__

// See DECISION_LOG.md D016. First infrastructure piece of the Edge
// Discovery Sprint (Stage A) -- a separate track from the execution-
// safety phases (D005-D015). Computes and exports per-trade outcome
// analytics (R-multiple, MFE/MAE-in-R, exit reason, bars held, session)
// for a closed MSZZ-owned position. See D016 for exactly what is and is
// not covered (deferred: spread_at_entry, ATR/structure snapshot columns,
// commit_sha, the master run-level summary CSV).

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh>

enum ENUM_MSZZ_EXIT_REASON
{
   MSZZ_EXIT_SL = 0,
   MSZZ_EXIT_TP,
   MSZZ_EXIT_OTHER
};

string MSZZExitReasonText(const ENUM_MSZZ_EXIT_REASON r)
{
   switch(r)
   {
      case MSZZ_EXIT_SL:    return "SL";
      case MSZZ_EXIT_TP:    return "TP";
      case MSZZ_EXIT_OTHER: return "OTHER";
      default:              return "UNKNOWN";
   }
}

enum ENUM_MSZZ_SESSION
{
   MSZZ_SESSION_ASIAN = 0,
   MSZZ_SESSION_LONDON,
   MSZZ_SESSION_NEWYORK
};

string MSZZSessionText(const ENUM_MSZZ_SESSION s)
{
   switch(s)
   {
      case MSZZ_SESSION_ASIAN:   return "Asian";
      case MSZZ_SESSION_LONDON:  return "London";
      case MSZZ_SESSION_NEWYORK: return "NewYork";
      default:                   return "UNKNOWN";
   }
}

// Pure, deterministic, no-MT5-API class -- same "pure policy" shape as
// every other component in this series (D005/D009/D010/D011/D012/D013).
class CMSZZTradeAnalyticsPolicy
{
public:
   // Signed R-multiple: positive = favorable, negative = adverse, for
   // either direction. Guards zero/invalid risk by returning 0.0 rather
   // than risking nan/inf reaching a CSV (defensive -- upstream already
   // rejects entry==stop at signal time).
   static double RMultiple(const double entry,const double stop,const double close,
                            const ENUM_MSZZ_DIRECTION direction)
   {
      double risk=MathAbs(entry-stop);
      if(risk<=0.0) return 0.0;
      double raw=(direction==MSZZ_DIR_LONG ? (close-entry) : (entry-close));
      return raw/risk;
   }

   // Same shape as RMultiple, used for both MFE (pass the window's best
   // price for this direction) and MAE (pass the window's worst price).
   // Reported as a signed excursion in R -- the caller (ExportClosedTrade)
   // takes the max/min across both extremes rather than this function
   // guessing which one is "favorable".
   static double ExcursionInR(const double extreme_price,const double entry,const double stop,
                               const ENUM_MSZZ_DIRECTION direction)
   {
      return RMultiple(entry,stop,extreme_price,direction);
   }

   // Reuses D011's ProtectionGuard.mqh half-point tolerance convention
   // rather than inventing a new one.
   static ENUM_MSZZ_EXIT_REASON ClassifyExitReason(const double close,const double stop,const double target,
                                                    const double point)
   {
      double tolerance=(point>0.0 ? point/2.0 : 0.0000001);
      if(MathAbs(close-stop)<=tolerance) return MSZZ_EXIT_SL;
      if(MathAbs(close-target)<=tolerance) return MSZZ_EXIT_TP;
      return MSZZ_EXIT_OTHER;
   }

   // Three fixed, non-overlapping 8-hour buckets on broker server time.
   // Explicitly a simplification, not a DST-aware trading-session
   // calendar -- see DECISION_LOG.md D016.
   static ENUM_MSZZ_SESSION SessionBucket(const int hour_of_day)
   {
      int h=hour_of_day % 24; if(h<0) h+=24;
      if(h<8) return MSZZ_SESSION_ASIAN;
      if(h<16) return MSZZ_SESSION_LONDON;
      return MSZZ_SESSION_NEWYORK;
   }
};

// Live wrapper: given a closed intent and its closing deal's price/time,
// derives realized figures from broker history and CopyRates, and writes
// one CSV row via the same header-once/reopen-per-write pattern as
// Diagnostics/ParityExporter.mqh's OpenCsv() -- mirrored, not shared code,
// since that component is a signal-shape-validation concern and this is a
// trade-outcome concern (same separation this series keeps everywhere).
class CMSZZTradeAnalyticsExporter
{
private:
   string Sanitize(const string s) const
   {
      string out=s;
      StringReplace(out,";","_");
      StringReplace(out,"\n","_");
      StringReplace(out,"\r","_");
      return out;
   }

   int OpenCsv(const string filename,const string header)
   {
      int h=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(h==INVALID_HANDLE)
      {
         PrintFormat("MSZZ trade analytics export open failed file=%s error=%d",filename,GetLastError());
         return INVALID_HANDLE;
      }
      if(FileSize(h)==0) FileWriteString(h,header+"\r\n");
      FileSeek(h,0,SEEK_END);
      return h;
   }

public:
   bool ExportClosedTrade(const MSZZExecutionIntent &intent,
                           const datetime fill_time,
                           const double closing_price,
                           const datetime closing_time)
   {
      ENUM_MSZZ_DIRECTION direction=(ENUM_MSZZ_DIRECTION)intent.direction;
      double entry=intent.average_fill_price;
      double stop=intent.requested_stop;
      double target=intent.requested_target;

      double r_result=CMSZZTradeAnalyticsPolicy::RMultiple(entry,stop,closing_price,direction);

      double point=SymbolInfoDouble(intent.symbol,SYMBOL_POINT);
      ENUM_MSZZ_EXIT_REASON exit_reason=CMSZZTradeAnalyticsPolicy::ClassifyExitReason(closing_price,stop,target,point);

      // D016: MFE/MAE window is a bar-range scan (CopyRates), not tick
      // level -- precision-matched to this series' existing Model=2
      // (open-price-only) Tester regressions, not a downgrade from them.
      double mfe_r=r_result, mae_r=r_result;
      MqlRates rates[];
      int copied=CopyRates(intent.symbol,(ENUM_TIMEFRAMES)intent.timeframe,fill_time,closing_time,rates);
      if(copied>0)
      {
         double best=rates[0].high, worst=rates[0].low;
         for(int i=1;i<copied;i++)
         {
            if(rates[i].high>best) best=rates[i].high;
            if(rates[i].low<worst) worst=rates[i].low;
         }
         double excursion_a=CMSZZTradeAnalyticsPolicy::ExcursionInR(best,entry,stop,direction);
         double excursion_b=CMSZZTradeAnalyticsPolicy::ExcursionInR(worst,entry,stop,direction);
         mfe_r=MathMax(excursion_a,excursion_b);
         mae_r=MathMin(excursion_a,excursion_b);
      }
      else
      {
         PrintFormat("MSZZ WARNING: trade analytics CopyRates returned no bars for %s fill=%s close=%s, falling back to realized R for MFE/MAE",
                     intent.symbol,TimeToString(fill_time,TIME_DATE|TIME_SECONDS),TimeToString(closing_time,TIME_DATE|TIME_SECONDS));
      }

      int period_seconds=PeriodSeconds((ENUM_TIMEFRAMES)intent.timeframe);
      int bars_held=(period_seconds>0 ? (int)((closing_time-fill_time)/period_seconds) : 0);

      MqlDateTime dt;
      TimeToStruct(fill_time,dt);
      ENUM_MSZZ_SESSION session=CMSZZTradeAnalyticsPolicy::SessionBucket(dt.hour);

      int h=OpenCsv("MSZZ_TradeAnalytics.csv",
                    "cluster_id;strategy_id;symbol;timeframe;direction;signal_time;fill_time;close_time;"+
                    "entry;stop;target;exit;exit_reason;r_result;mfe_r;mae_r;bars_held;session");
      if(h==INVALID_HANDLE) return false;

      FileWrite(h,Sanitize(intent.cluster_id),intent.strategy_id,intent.symbol,
                EnumToString((ENUM_TIMEFRAMES)intent.timeframe),
                MSZZDirectionText(direction),
                TimeToString(intent.signal_time,TIME_DATE|TIME_SECONDS),
                TimeToString(fill_time,TIME_DATE|TIME_SECONDS),
                TimeToString(closing_time,TIME_DATE|TIME_SECONDS),
                DoubleToString(entry,8),DoubleToString(stop,8),DoubleToString(target,8),DoubleToString(closing_price,8),
                MSZZExitReasonText(exit_reason),
                DoubleToString(r_result,4),DoubleToString(mfe_r,4),DoubleToString(mae_r,4),
                bars_held,MSZZSessionText(session));
      FileFlush(h); FileClose(h);
      return true;
   }
};

#endif
