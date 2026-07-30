#ifndef __MSZZ_TRIPLE_ZIGZAG_ENGINE_MQH__
#define __MSZZ_TRIPLE_ZIGZAG_ENGINE_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Core/StructuralEventRecord.mqh>

class CMSZZTripleZigZagEngine
{
private:
   int      m_atr_len[3];
   double   m_atr_mult[3];
   int      m_min_bars_between;
   MSZZSpeedSnapshot m_snapshot[3];

   double TrueRange(const MqlRates &rates[], const int i) const
   {
      if(i <= 0) return rates[i].high - rates[i].low;
      return MathMax(rates[i].high-rates[i].low,
                     MathMax(MathAbs(rates[i].high-rates[i-1].close),
                             MathAbs(rates[i].low-rates[i-1].close)));
   }

   double ATRAt(const MqlRates &rates[], const int i, const int len) const
   {
      if(i < len) return 0.0;
      double sum = 0.0;
      for(int j=i-len+1; j<=i; j++) sum += TrueRange(rates,j);
      return sum/(double)len;
   }

   string PivotId(const string symbol,const ENUM_TIMEFRAMES tf,const ENUM_MSZZ_SPEED speed,
                  const ENUM_MSZZ_PIVOT_KIND kind,const datetime pivot_time,const datetime confirmed_time) const
   {
      return CMSZZStructuralEventPolicy::PivotId(symbol,tf,speed,kind,
                                                 pivot_time,confirmed_time);
   }

   ENUM_MSZZ_STRUCTURE_LABEL ClassifyHigh(const double price,const MSZZPivot &previous) const
   {
      if(!previous.valid) return MSZZ_STRUCT_UNKNOWN;
      return (price > previous.price ? MSZZ_STRUCT_HH : MSZZ_STRUCT_LH);
   }

   ENUM_MSZZ_STRUCTURE_LABEL ClassifyLow(const double price,const MSZZPivot &previous) const
   {
      if(!previous.valid) return MSZZ_STRUCT_UNKNOWN;
      return (price > previous.price ? MSZZ_STRUCT_HL : MSZZ_STRUCT_LL);
   }

   void BlankPivot(MSZZPivot &p) const
   {
      p.valid=false; p.speed=MSZZ_SPEED_FAST; p.kind=MSZZ_PIVOT_NONE;
      p.structure_label=MSZZ_STRUCT_UNKNOWN; p.pivot_time=0; p.confirmed_time=0;
      p.pivot_shift=0; p.price=0.0; p.id="";
   }

   void ResetSnapshot(const ENUM_MSZZ_SPEED speed)
   {
      int s=(int)speed;
      m_snapshot[s].speed=speed;
      m_snapshot[s].leg_direction=MSZZ_DIR_NONE;
      m_snapshot[s].atr=0.0;
      m_snapshot[s].reversal_threshold=0.0;
      m_snapshot[s].current_extreme=0.0;
      m_snapshot[s].current_extreme_time=0;
      BlankPivot(m_snapshot[s].last_high);
      BlankPivot(m_snapshot[s].prior_high);
      BlankPivot(m_snapshot[s].last_low);
      BlankPivot(m_snapshot[s].prior_low);
      m_snapshot[s].new_pivot=false;
      m_snapshot[s].bullish_break=false;
      m_snapshot[s].bearish_break=false;
      m_snapshot[s].resistance_now=0.0;
      m_snapshot[s].support_now=0.0;
      m_snapshot[s].bullish_event_id="";
      m_snapshot[s].bearish_event_id="";
      CMSZZStructuralEventPolicy::Blank(m_snapshot[s].bullish_structural_event);
      CMSZZStructuralEventPolicy::Blank(m_snapshot[s].bearish_structural_event);
   }

   void ConfirmHigh(const string symbol,const ENUM_TIMEFRAMES tf,const ENUM_MSZZ_SPEED speed,
                    const int shift,const datetime pivot_time,const datetime confirm_time,const double price)
   {
      int s=(int)speed;
      MSZZPivot p;
      p.valid=true; p.speed=speed; p.kind=MSZZ_PIVOT_HIGH;
      p.structure_label=ClassifyHigh(price,m_snapshot[s].last_high);
      p.pivot_time=pivot_time; p.confirmed_time=confirm_time; p.pivot_shift=shift; p.price=price;
      p.id=PivotId(symbol,tf,speed,MSZZ_PIVOT_HIGH,pivot_time,confirm_time);
      m_snapshot[s].prior_high=m_snapshot[s].last_high;
      m_snapshot[s].last_high=p;
      m_snapshot[s].new_pivot=true;
   }

   void ConfirmLow(const string symbol,const ENUM_TIMEFRAMES tf,const ENUM_MSZZ_SPEED speed,
                   const int shift,const datetime pivot_time,const datetime confirm_time,const double price)
   {
      int s=(int)speed;
      MSZZPivot p;
      p.valid=true; p.speed=speed; p.kind=MSZZ_PIVOT_LOW;
      p.structure_label=ClassifyLow(price,m_snapshot[s].last_low);
      p.pivot_time=pivot_time; p.confirmed_time=confirm_time; p.pivot_shift=shift; p.price=price;
      p.id=PivotId(symbol,tf,speed,MSZZ_PIVOT_LOW,pivot_time,confirm_time);
      m_snapshot[s].prior_low=m_snapshot[s].last_low;
      m_snapshot[s].last_low=p;
      m_snapshot[s].new_pivot=true;
   }

   double ProjectLine(const MSZZPivot &a,const MSZZPivot &b,const datetime now) const
   {
      return CMSZZStructuralEventPolicy::ProjectLevel(a,b,now);
   }

   bool BuildSpeed(const string symbol,const ENUM_TIMEFRAMES tf,const MqlRates &rates[],
                   const int count,const ENUM_MSZZ_SPEED speed)
   {
      ResetSnapshot(speed);
      int s=(int)speed;
      if(count < m_atr_len[s]+10) return false;

      int direction=0;
      double extreme=0.0;
      int extreme_i=-1;
      int last_pivot_i=-1000000;
      MSZZPivot origin_for_last_high,origin_for_last_low;
      BlankPivot(origin_for_last_high);
      BlankPivot(origin_for_last_low);

      for(int i=m_atr_len[s]; i<count; i++)
      {
         double atr=ATRAt(rates,i,m_atr_len[s]);
         if(atr<=0.0) continue;
         double threshold=atr*m_atr_mult[s];

         if(direction==0)
         {
            direction=(rates[i].close>=rates[i-1].close ? 1 : -1);
            extreme=(direction>0 ? rates[i].high : rates[i].low);
            extreme_i=i;
            continue;
         }

         if(direction>0)
         {
            if(rates[i].high>=extreme) { extreme=rates[i].high; extreme_i=i; }
            if(extreme-rates[i].low>=threshold && extreme_i-last_pivot_i>=m_min_bars_between)
            {
               ConfirmHigh(symbol,tf,speed,extreme_i,rates[extreme_i].time,rates[i].time,extreme);
               MSZZPivot confirmed_high=m_snapshot[s].last_high;
               if(m_snapshot[s].last_low.valid &&
                  m_snapshot[s].last_low.pivot_time<confirmed_high.pivot_time &&
                  m_snapshot[s].last_low.confirmed_time<confirmed_high.confirmed_time)
                  origin_for_last_high=m_snapshot[s].last_low;
               else
                  BlankPivot(origin_for_last_high);
               last_pivot_i=extreme_i;
               direction=-1; extreme=rates[i].low; extreme_i=i;
            }
         }
         else
         {
            if(rates[i].low<=extreme) { extreme=rates[i].low; extreme_i=i; }
            if(rates[i].high-extreme>=threshold && extreme_i-last_pivot_i>=m_min_bars_between)
            {
               ConfirmLow(symbol,tf,speed,extreme_i,rates[extreme_i].time,rates[i].time,extreme);
               MSZZPivot confirmed_low=m_snapshot[s].last_low;
               if(m_snapshot[s].last_high.valid &&
                  m_snapshot[s].last_high.pivot_time<confirmed_low.pivot_time &&
                  m_snapshot[s].last_high.confirmed_time<confirmed_low.confirmed_time)
                  origin_for_last_low=m_snapshot[s].last_high;
               else
                  BlankPivot(origin_for_last_low);
               last_pivot_i=extreme_i;
               direction=1; extreme=rates[i].high; extreme_i=i;
            }
         }

         if(i==count-1)
         {
            m_snapshot[s].atr=atr;
            m_snapshot[s].reversal_threshold=threshold;
         }
      }

      m_snapshot[s].leg_direction=(direction>0 ? MSZZ_DIR_LONG : MSZZ_DIR_SHORT);
      m_snapshot[s].current_extreme=extreme;
      if(extreme_i>=0) m_snapshot[s].current_extreme_time=rates[extreme_i].time;

      datetime now=rates[count-1].time;
      m_snapshot[s].resistance_now=ProjectLine(m_snapshot[s].prior_high,m_snapshot[s].last_high,now);
      m_snapshot[s].support_now=ProjectLine(m_snapshot[s].prior_low,m_snapshot[s].last_low,now);

      if(count>=2)
      {
         double prev_close=rates[count-2].close;
         double close_now=rates[count-1].close;
         double prev_res=ProjectLine(m_snapshot[s].prior_high,m_snapshot[s].last_high,rates[count-2].time);
         double prev_sup=ProjectLine(m_snapshot[s].prior_low,m_snapshot[s].last_low,rates[count-2].time);

         m_snapshot[s].bullish_break=(m_snapshot[s].resistance_now>0.0 && prev_res>0.0 &&
                                      prev_close<=prev_res && close_now>m_snapshot[s].resistance_now);
         m_snapshot[s].bearish_break=(m_snapshot[s].support_now>0.0 && prev_sup>0.0 &&
                                      prev_close>=prev_sup && close_now<m_snapshot[s].support_now);

         if(m_snapshot[s].bullish_break)
         {
            m_snapshot[s].bullish_event_id=StringFormat("BO|%s|%d|%d|L|%I64d|%s",symbol,(int)tf,s,(long)now,m_snapshot[s].last_high.id);
            double point_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
            CMSZZStructuralEventPolicy::Build(
               symbol,tf,speed,MSZZ_DIR_LONG,rates[count-2].time,now,
               prev_close,close_now,rates[count-1].high,rates[count-1].low,
               m_snapshot[s].atr,m_snapshot[s].prior_high,
               m_snapshot[s].last_high,origin_for_last_high,point_size,
               m_snapshot[s].bullish_structural_event);
         }
         if(m_snapshot[s].bearish_break)
         {
            m_snapshot[s].bearish_event_id=StringFormat("BO|%s|%d|%d|S|%I64d|%s",symbol,(int)tf,s,(long)now,m_snapshot[s].last_low.id);
            double point_size=SymbolInfoDouble(symbol,SYMBOL_POINT);
            CMSZZStructuralEventPolicy::Build(
               symbol,tf,speed,MSZZ_DIR_SHORT,rates[count-2].time,now,
               prev_close,close_now,rates[count-1].high,rates[count-1].low,
               m_snapshot[s].atr,m_snapshot[s].prior_low,
               m_snapshot[s].last_low,origin_for_last_low,point_size,
               m_snapshot[s].bearish_structural_event);
         }
      }
      return true;
   }

public:
   CMSZZTripleZigZagEngine(void)
   {
      m_atr_len[0]=14; m_atr_len[1]=14; m_atr_len[2]=14;
      m_atr_mult[0]=1.0; m_atr_mult[1]=2.0; m_atr_mult[2]=3.5;
      m_min_bars_between=3;
      for(int i=0;i<3;i++) ResetSnapshot((ENUM_MSZZ_SPEED)i);
   }

   void Configure(const int fast_len,const double fast_mult,const int med_len,const double med_mult,
                  const int slow_len,const double slow_mult,const int min_bars_between)
   {
      m_atr_len[0]=fast_len; m_atr_mult[0]=fast_mult;
      m_atr_len[1]=med_len; m_atr_mult[1]=med_mult;
      m_atr_len[2]=slow_len; m_atr_mult[2]=slow_mult;
      m_min_bars_between=MathMax(1,min_bars_between);
   }

   bool Rebuild(const string symbol,const ENUM_TIMEFRAMES tf,const MqlRates &rates[],const int count)
   {
      bool ok=true;
      for(int s=0;s<3;s++) if(!BuildSpeed(symbol,tf,rates,count,(ENUM_MSZZ_SPEED)s)) ok=false;
      return ok;
   }

   MSZZSpeedSnapshot Snapshot(const ENUM_MSZZ_SPEED speed) const { return m_snapshot[(int)speed]; }
};

#endif
