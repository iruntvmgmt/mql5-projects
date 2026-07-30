#property strict
//+------------------------------------------------------------------+
//| StructuralReplay.mqh                                              |
//| D024: research-only causal ZigZag bar-history extraction for      |
//| Phase 2 structural exit replay.                                   |
//|                                                                    |
//| CMSZZTripleZigZagEngine::Rebuild() (Core/TripleZigZagEngine.mqh)   |
//| is already a single forward O(n) pass that only ever uses         |
//| rates[0..i] to confirm anything at step i -- it is fully causal    |
//| and non-repainting by construction. Its public API only exposes   |
//| the FINAL snapshot after a full Rebuild(), not the bar-by-bar      |
//| timeline of confirmed pivots and structure breaks that Phase 2's   |
//| structural exits need. Rather than modify that live-critical,      |
//| already-tested class, this file duplicates its scanning loop       |
//| verbatim into a research-only function that emits a snapshot PER   |
//| BAR instead of only at the end. See DECISION_LOG.md D024. The live |
//| engine is never touched by this file; Test_MSZZ_StructuralReplay   |
//| asserts this duplicate's final-bar state matches the real engine's |
//| Snapshot() exactly, as a safeguard against algorithmic drift.      |
//+------------------------------------------------------------------+

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Core/StructuralEventRecord.mqh>

// Per-bar structural state for one speed, as it would have been known
// causally at the CLOSE of bars[i] (i.e. safe to use starting bars[i+1]).
struct MSZZSpeedBarState
{
   MSZZPivot last_high;
   MSZZPivot prior_high;
   MSZZPivot last_low;
   MSZZPivot prior_low;
   ENUM_MSZZ_DIRECTION leg_direction;
   bool      bullish_break;   // fired exactly on this bar
   bool      bearish_break;   // fired exactly on this bar
   bool      new_high_pivot;  // a high pivot was confirmed exactly on this bar
   bool      new_low_pivot;   // a low pivot was confirmed exactly on this bar
   bool      warmed_up;       // false while ATR history is still insufficient
   MSZZStructuralEventRecord bullish_structural_event;
   MSZZStructuralEventRecord bearish_structural_event;
};

class CMSZZStructuralReplay
{
private:
   static double TrueRange(const MqlRates &rates[],const int i)
   {
      if(i<=0) return rates[i].high-rates[i].low;
      return MathMax(rates[i].high-rates[i].low,
                     MathMax(MathAbs(rates[i].high-rates[i-1].close),
                             MathAbs(rates[i].low-rates[i-1].close)));
   }

   static double ATRAt(const MqlRates &rates[],const int i,const int len)
   {
      if(i<len) return 0.0;
      double sum=0.0;
      for(int j=i-len+1;j<=i;j++) sum+=TrueRange(rates,j);
      return sum/(double)len;
   }

   static ENUM_MSZZ_STRUCTURE_LABEL ClassifyHigh(const double price,const MSZZPivot &previous)
   {
      if(!previous.valid) return MSZZ_STRUCT_UNKNOWN;
      return (price>previous.price ? MSZZ_STRUCT_HH : MSZZ_STRUCT_LH);
   }

   static ENUM_MSZZ_STRUCTURE_LABEL ClassifyLow(const double price,const MSZZPivot &previous)
   {
      if(!previous.valid) return MSZZ_STRUCT_UNKNOWN;
      return (price>previous.price ? MSZZ_STRUCT_HL : MSZZ_STRUCT_LL);
   }

   static void BlankPivot(MSZZPivot &p)
   {
      p.valid=false; p.speed=MSZZ_SPEED_FAST; p.kind=MSZZ_PIVOT_NONE;
      p.structure_label=MSZZ_STRUCT_UNKNOWN; p.pivot_time=0; p.confirmed_time=0;
      p.pivot_shift=0; p.price=0.0; p.id="";
   }

   static double ProjectLine(const MSZZPivot &a,const MSZZPivot &b,const datetime now)
   {
      return CMSZZStructuralEventPolicy::ProjectLevel(a,b,now);
   }

public:
   // Fills out[0..count-1]. out[i] reflects structural state as causally
   // knowable at the CLOSE of bars[i] -- mirrors what
   // CMSZZTripleZigZagEngine::Rebuild(rates[0..i+1]) would conclude,
   // repeated at every bar in one O(count) pass instead of O(count^2)
   // separate Rebuild calls.
   static bool BuildBarHistory(const string symbol,const ENUM_TIMEFRAMES tf,
                                const MqlRates &rates[],const int count,
                                const int atr_len,const double atr_mult,
                                const int min_bars_between,
                                const ENUM_MSZZ_SPEED speed,
                                MSZZSpeedBarState &out[])
   {
      ArrayResize(out,count);
      MSZZSpeedBarState blank;
      blank.leg_direction=MSZZ_DIR_NONE; blank.bullish_break=false; blank.bearish_break=false;
      blank.new_high_pivot=false; blank.new_low_pivot=false; blank.warmed_up=false;
      BlankPivot(blank.last_high); BlankPivot(blank.prior_high);
      BlankPivot(blank.last_low); BlankPivot(blank.prior_low);
      CMSZZStructuralEventPolicy::Blank(blank.bullish_structural_event);
      CMSZZStructuralEventPolicy::Blank(blank.bearish_structural_event);
      for(int i=0;i<count;i++) out[i]=blank;

      if(count<atr_len+10) return false;

      int direction=0;
      double extreme=0.0;
      int extreme_i=-1;
      int last_pivot_i=-1000000;
      MSZZPivot last_high, prior_high, last_low, prior_low;
      BlankPivot(last_high); BlankPivot(prior_high); BlankPivot(last_low); BlankPivot(prior_low);
      MSZZPivot origin_for_last_high,origin_for_last_low;
      BlankPivot(origin_for_last_high); BlankPivot(origin_for_last_low);
      double point_size=SymbolInfoDouble(symbol,SYMBOL_POINT);

      for(int i=atr_len;i<count;i++)
      {
         double atr=ATRAt(rates,i,atr_len);
         bool new_high_pivot=false, new_low_pivot=false;
         if(atr>0.0)
         {
            double threshold=atr*atr_mult;

            if(direction==0)
            {
               direction=(rates[i].close>=rates[i-1].close ? 1 : -1);
               extreme=(direction>0 ? rates[i].high : rates[i].low);
               extreme_i=i;
            }
            else if(direction>0)
            {
               if(rates[i].high>=extreme) { extreme=rates[i].high; extreme_i=i; }
               if(extreme-rates[i].low>=threshold && extreme_i-last_pivot_i>=min_bars_between)
               {
                  MSZZPivot p; p.valid=true; p.speed=speed; p.kind=MSZZ_PIVOT_HIGH;
                  p.structure_label=ClassifyHigh(extreme,last_high);
                  p.pivot_time=rates[extreme_i].time; p.confirmed_time=rates[i].time;
                  p.pivot_shift=extreme_i; p.price=extreme;
                  p.id=CMSZZStructuralEventPolicy::PivotId(symbol,tf,speed,
                     MSZZ_PIVOT_HIGH,p.pivot_time,p.confirmed_time);
                  prior_high=last_high; last_high=p; new_high_pivot=true;
                  if(last_low.valid && last_low.pivot_time<p.pivot_time &&
                     last_low.confirmed_time<p.confirmed_time)
                     origin_for_last_high=last_low;
                  else
                     BlankPivot(origin_for_last_high);
                  last_pivot_i=extreme_i;
                  direction=-1; extreme=rates[i].low; extreme_i=i;
               }
            }
            else
            {
               if(rates[i].low<=extreme) { extreme=rates[i].low; extreme_i=i; }
               if(rates[i].high-extreme>=threshold && extreme_i-last_pivot_i>=min_bars_between)
               {
                  MSZZPivot p; p.valid=true; p.speed=speed; p.kind=MSZZ_PIVOT_LOW;
                  p.structure_label=ClassifyLow(extreme,last_low);
                  p.pivot_time=rates[extreme_i].time; p.confirmed_time=rates[i].time;
                  p.pivot_shift=extreme_i; p.price=extreme;
                  p.id=CMSZZStructuralEventPolicy::PivotId(symbol,tf,speed,
                     MSZZ_PIVOT_LOW,p.pivot_time,p.confirmed_time);
                  prior_low=last_low; last_low=p; new_low_pivot=true;
                  if(last_high.valid && last_high.pivot_time<p.pivot_time &&
                     last_high.confirmed_time<p.confirmed_time)
                     origin_for_last_low=last_high;
                  else
                     BlankPivot(origin_for_last_low);
                  last_pivot_i=extreme_i;
                  direction=1; extreme=rates[i].high; extreme_i=i;
               }
            }
         }

         bool bullish_break=false, bearish_break=false;
         MSZZStructuralEventRecord bullish_event,bearish_event;
         CMSZZStructuralEventPolicy::Blank(bullish_event);
         CMSZZStructuralEventPolicy::Blank(bearish_event);
         if(i>=1)
         {
            double prev_close=rates[i-1].close;
            double close_now=rates[i].close;
            double res_now=ProjectLine(prior_high,last_high,rates[i].time);
            double sup_now=ProjectLine(prior_low,last_low,rates[i].time);
            double prev_res=ProjectLine(prior_high,last_high,rates[i-1].time);
            double prev_sup=ProjectLine(prior_low,last_low,rates[i-1].time);
            bullish_break=(res_now>0.0 && prev_res>0.0 && prev_close<=prev_res && close_now>res_now);
            bearish_break=(sup_now>0.0 && prev_sup>0.0 && prev_close>=prev_sup && close_now<sup_now);
            if(bullish_break)
               CMSZZStructuralEventPolicy::Build(symbol,tf,speed,MSZZ_DIR_LONG,
                  rates[i-1].time,rates[i].time,prev_close,close_now,
                  rates[i].high,rates[i].low,atr,prior_high,last_high,
                  origin_for_last_high,point_size,bullish_event);
            if(bearish_break)
               CMSZZStructuralEventPolicy::Build(symbol,tf,speed,MSZZ_DIR_SHORT,
                  rates[i-1].time,rates[i].time,prev_close,close_now,
                  rates[i].high,rates[i].low,atr,prior_low,last_low,
                  origin_for_last_low,point_size,bearish_event);
         }

         out[i].last_high=last_high; out[i].prior_high=prior_high;
         out[i].last_low=last_low; out[i].prior_low=prior_low;
         out[i].leg_direction=(direction>0 ? MSZZ_DIR_LONG : (direction<0 ? MSZZ_DIR_SHORT : MSZZ_DIR_NONE));
         out[i].bullish_break=bullish_break; out[i].bearish_break=bearish_break;
         out[i].new_high_pivot=new_high_pivot; out[i].new_low_pivot=new_low_pivot;
         out[i].warmed_up=true;
         out[i].bullish_structural_event=bullish_event;
         out[i].bearish_structural_event=bearish_event;
      }
      return true;
   }
};
