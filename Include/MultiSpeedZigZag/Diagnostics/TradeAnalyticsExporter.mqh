#ifndef __MSZZ_TRADE_ANALYTICS_EXPORTER_MQH__
#define __MSZZ_TRADE_ANALYTICS_EXPORTER_MQH__

// See DECISION_LOG.md D016 and D017. Infrastructure for the Edge
// Discovery Sprint (Stage A) -- a separate track from the execution-
// safety phases (D005-D015). D016: computes and exports per-trade
// outcome analytics (R-multiple, MFE/MAE-in-R, exit reason, bars held,
// session) for a closed MSZZ-owned position. D017: accumulates those same
// trades and writes one master run-level summary row at OnDeinit(). See
// both entries for exactly what is and is not covered (deferred:
// spread_at_entry, ATR/structure snapshot columns, commit_sha, raw-
// currency profit/profit-factor -- this stays R-only throughout).

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

// D017: pure, static, array-based aggregation over a completed run's
// trades -- same deterministic-and-unit-testable shape as every other
// policy class in this series.
class CMSZZRunSummaryPolicy
{
public:
   static double Average(const double &values[],const int count)
   {
      if(count<=0) return 0.0;
      double sum=0.0;
      for(int i=0;i<count;i++) sum+=values[i];
      return sum/count;
   }

   // A breakeven trade (r_result exactly 0.0) does not count as a win.
   static double WinRate(const double &r_results[],const int count)
   {
      if(count<=0) return 0.0;
      int wins=0;
      for(int i=0;i<count;i++) if(r_results[i]>0.0) wins++;
      return (double)wins/(double)count;
   }

   // Returns -1.0 (an unambiguous sentinel outside the normal >=0 range)
   // when there are winning trades but zero losing trades -- a true
   // profit factor is undefined there, not "infinite" in any useful sense.
   // Returns 0.0 when there are no winning trades at all (including the
   // fully-empty case), consistent with Average()'s zero-count behavior.
   static double ProfitFactorR(const double &r_results[],const int count)
   {
      double gross_win=0.0, gross_loss=0.0;
      for(int i=0;i<count;i++)
      {
         if(r_results[i]>0.0) gross_win+=r_results[i];
         else if(r_results[i]<0.0) gross_loss+=(-r_results[i]);
      }
      if(gross_win<=0.0) return 0.0;
      if(gross_loss<=0.0) return -1.0;
      return gross_win/gross_loss;
   }

   // Walks the cumulative-R equity curve in trade order, tracking the
   // running peak, and returns the largest peak-to-trough drop as a
   // positive R number (0.0 if the curve never draws down).
   static double MaxDrawdownR(const double &r_results[],const int count)
   {
      double cumulative=0.0, peak=0.0, max_dd=0.0;
      for(int i=0;i<count;i++)
      {
         cumulative+=r_results[i];
         if(cumulative>peak) peak=cumulative;
         double dd=peak-cumulative;
         if(dd>max_dd) max_dd=dd;
      }
      return max_dd;
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
   // D017: fed by every ExportClosedTrade() call this session, so
   // WriteRunSummary() can aggregate at OnDeinit() without a second,
   // independent scan of broker history (see DECISION_LOG.md D017
   // "Rejected alternatives" for why that would risk two numbers silently
   // disagreeing).
   double  m_r_results[];
   int     m_directions[];
   double  m_mfe[];
   double  m_mae[];
   int     m_bars_held[];
   int     m_trade_count;
   datetime m_first_signal_time;
   datetime m_last_close_time;

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
   CMSZZTradeAnalyticsExporter(void)
   {
      m_trade_count=0;
      m_first_signal_time=0;
      m_last_close_time=0;
      ArrayResize(m_r_results,0); ArrayResize(m_directions,0);
      ArrayResize(m_mfe,0); ArrayResize(m_mae,0); ArrayResize(m_bars_held,0);
   }

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

      // D017: feed the same trade into this session's run-summary
      // accumulator -- see WriteRunSummary().
      int n=m_trade_count;
      ArrayResize(m_r_results,n+1); ArrayResize(m_directions,n+1);
      ArrayResize(m_mfe,n+1); ArrayResize(m_mae,n+1); ArrayResize(m_bars_held,n+1);
      m_r_results[n]=r_result; m_directions[n]=(int)direction;
      m_mfe[n]=mfe_r; m_mae[n]=mae_r; m_bars_held[n]=bars_held;
      m_trade_count=n+1;
      if(m_first_signal_time==0 || intent.signal_time<m_first_signal_time) m_first_signal_time=intent.signal_time;
      if(closing_time>m_last_close_time) m_last_close_time=closing_time;

      return true;
   }

   // D017: called once, from OnDeinit(), after every trade this session
   // has already been fed in via ExportClosedTrade() above. Writes one row
   // to a continuously-appended master summary CSV. No-op (writes nothing)
   // if zero trades occurred this session -- matches D016's own behavior
   // of never writing a trade-level row when there is nothing to report.
   bool WriteRunSummary(const string symbol,const long magic,const ENUM_TIMEFRAMES timeframe,
                         const double risk_reward,const string enabled_strategies)
   {
      if(m_trade_count<=0) return true;

      double long_r[]; int long_n=0;
      double short_r[]; int short_n=0;
      ArrayResize(long_r,m_trade_count); ArrayResize(short_r,m_trade_count);
      for(int i=0;i<m_trade_count;i++)
      {
         if(m_directions[i]==(int)MSZZ_DIR_LONG) long_r[long_n++]=m_r_results[i];
         else if(m_directions[i]==(int)MSZZ_DIR_SHORT) short_r[short_n++]=m_r_results[i];
      }
      ArrayResize(long_r,long_n); ArrayResize(short_r,short_n);

      double win_rate=CMSZZRunSummaryPolicy::WinRate(m_r_results,m_trade_count);
      double expectancy_r=CMSZZRunSummaryPolicy::Average(m_r_results,m_trade_count);
      double profit_factor_r=CMSZZRunSummaryPolicy::ProfitFactorR(m_r_results,m_trade_count);
      double max_dd_r=CMSZZRunSummaryPolicy::MaxDrawdownR(m_r_results,m_trade_count);
      double avg_mfe_r=CMSZZRunSummaryPolicy::Average(m_mfe,m_trade_count);
      double avg_mae_r=CMSZZRunSummaryPolicy::Average(m_mae,m_trade_count);

      double bars_held_d[]; ArrayResize(bars_held_d,m_trade_count);
      for(int i=0;i<m_trade_count;i++) bars_held_d[i]=(double)m_bars_held[i];
      double avg_bars_held=CMSZZRunSummaryPolicy::Average(bars_held_d,m_trade_count);

      double long_expectancy_r=CMSZZRunSummaryPolicy::Average(long_r,long_n);
      double short_expectancy_r=CMSZZRunSummaryPolicy::Average(short_r,short_n);

      int h=OpenCsv("MSZZ_RunSummary.csv",
                    "symbol;timeframe;magic;risk_reward;enabled_strategies;first_signal_time;last_close_time;"+
                    "trades;win_rate;expectancy_r;profit_factor_r;max_drawdown_r;avg_mfe_r;avg_mae_r;avg_bars_held;"+
                    "long_expectancy_r;long_trades;short_expectancy_r;short_trades");
      if(h==INVALID_HANDLE) return false;

      FileWrite(h,symbol,EnumToString(timeframe),magic,DoubleToString(risk_reward,2),Sanitize(enabled_strategies),
                TimeToString(m_first_signal_time,TIME_DATE|TIME_SECONDS),
                TimeToString(m_last_close_time,TIME_DATE|TIME_SECONDS),
                m_trade_count,DoubleToString(win_rate,4),DoubleToString(expectancy_r,4),
                DoubleToString(profit_factor_r,4),DoubleToString(max_dd_r,4),
                DoubleToString(avg_mfe_r,4),DoubleToString(avg_mae_r,4),DoubleToString(avg_bars_held,2),
                DoubleToString(long_expectancy_r,4),long_n,DoubleToString(short_expectancy_r,4),short_n);
      FileFlush(h); FileClose(h);
      return true;
   }
};

#endif
