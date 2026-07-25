#ifndef __MSZZ_STRATEGY_SUITE_MQH__
#define __MSZZ_STRATEGY_SUITE_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

class CMSZZStrategySuite
{
private:
   bool m_enabled[13];
   int  m_sequence_window_bars;
   double m_rr;

   void ClearCandidate(MSZZCandidate &c) const { ZeroMemory(c); c.strategy_id=MSZZ_STRAT_NONE; }

   void AddCandidate(MSZZCandidate &out[],int &count,const ENUM_MSZZ_STRATEGY_ID id,
                     const ENUM_MSZZ_DIRECTION dir,const datetime t,const double entry,
                     const double stop,const double score,const int models,const string name,
                     const string event_id,const string reason) const
   {
      if(count>=ArraySize(out)) ArrayResize(out,count+16);
      MSZZCandidate c; ClearCandidate(c);
      c.valid=true; c.strategy_id=id; c.direction=dir; c.signal_time=t;
      c.entry=entry; c.stop=stop; c.score=score; c.supporting_models=models;
      c.setup_name=name; c.event_id=event_id; c.reason=reason;
      double risk=MathAbs(entry-stop);
      if(risk>0.0) c.target=(dir==MSZZ_DIR_LONG ? entry+risk*m_rr : entry-risk*m_rr);
      out[count++]=c;
   }

   bool BullContext(const MSZZSpeedSnapshot &s) const
   {
      return s.leg_direction==MSZZ_DIR_LONG || s.last_low.structure_label==MSZZ_STRUCT_HL ||
             s.last_high.structure_label==MSZZ_STRUCT_HH;
   }

   bool BearContext(const MSZZSpeedSnapshot &s) const
   {
      return s.leg_direction==MSZZ_DIR_SHORT || s.last_high.structure_label==MSZZ_STRUCT_LH ||
             s.last_low.structure_label==MSZZ_STRUCT_LL;
   }

   double LongStop(const MSZZSpeedSnapshot &fast,const MSZZSpeedSnapshot &med) const
   {
      if(med.last_low.valid) return med.last_low.price;
      if(fast.last_low.valid) return fast.last_low.price;
      return 0.0;
   }

   double ShortStop(const MSZZSpeedSnapshot &fast,const MSZZSpeedSnapshot &med) const
   {
      if(med.last_high.valid) return med.last_high.price;
      if(fast.last_high.valid) return fast.last_high.price;
      return 0.0;
   }

public:
   CMSZZStrategySuite(void)
   {
      for(int i=0;i<13;i++) m_enabled[i]=true;
      m_sequence_window_bars=5;
      m_rr=1.5;
   }

   void SetRiskReward(const double rr) { m_rr=MathMax(0.1,rr); }

   int Evaluate(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m,const MSZZSpeedSnapshot &s,
                const datetime signal_time,const double close_price,MSZZCandidate &out[])
   {
      ArrayResize(out,0);
      int n=0;
      double long_stop=LongStop(f,m), short_stop=ShortStop(f,m);

      if(f.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_FAST_BREAKOUT,MSZZ_DIR_LONG,signal_time,close_price,long_stop,4.0,1,
                      "Fast Breakout",f.bullish_event_id,"Fast resistance projection broken on close");
      if(f.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_FAST_BREAKOUT,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,4.0,1,
                      "Fast Breakout",f.bearish_event_id,"Fast support projection broken on close");

      if(m.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_BREAKOUT,MSZZ_DIR_LONG,signal_time,close_price,long_stop,5.5,1,
                      "Medium Breakout",m.bullish_event_id,"Medium resistance projection broken on close");
      if(m.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_BREAKOUT,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,5.5,1,
                      "Medium Breakout",m.bearish_event_id,"Medium support projection broken on close");

      if(s.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_SLOW_BREAKOUT,MSZZ_DIR_LONG,signal_time,close_price,long_stop,7.0,1,
                      "Slow Breakout",s.bullish_event_id,"Slow resistance projection broken on close");
      if(s.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_SLOW_BREAKOUT,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,7.0,1,
                      "Slow Breakout",s.bearish_event_id,"Slow support projection broken on close");

      if(f.bullish_break && (m.bullish_break || BullContext(m)) && BullContext(s))
         AddCandidate(out,n,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_DIR_LONG,signal_time,close_price,long_stop,8.0,
                      (m.bullish_break?3:2),"Fast + Medium Confluence / Slow Alignment",
                      "CLUSTER|"+f.bullish_event_id,"Fast trigger, medium confirmation/context, slow bullish alignment");
      if(f.bearish_break && (m.bearish_break || BearContext(m)) && BearContext(s))
         AddCandidate(out,n,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,8.0,
                      (m.bearish_break?3:2),"Fast + Medium Confluence / Slow Alignment",
                      "CLUSTER|"+f.bearish_event_id,"Fast trigger, medium confirmation/context, slow bearish alignment");

      if(f.bullish_break && BullContext(m))
         AddCandidate(out,n,MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT,MSZZ_DIR_LONG,signal_time,close_price,long_stop,6.3,2,
                      "Fast Breakout with Medium Context","CLUSTER|"+f.bullish_event_id,"Fast break supported by medium structure");
      if(f.bearish_break && BearContext(m))
         AddCandidate(out,n,MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,6.3,2,
                      "Fast Breakout with Medium Context","CLUSTER|"+f.bearish_event_id,"Fast break supported by medium structure");

      if(m.bullish_break && BullContext(s))
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_WITH_SLOW_CONTEXT,MSZZ_DIR_LONG,signal_time,close_price,long_stop,7.2,2,
                      "Medium Breakout with Slow Context","CLUSTER|"+m.bullish_event_id,"Medium break aligned with slow structure");
      if(m.bearish_break && BearContext(s))
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_WITH_SLOW_CONTEXT,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,7.2,2,
                      "Medium Breakout with Slow Context","CLUSTER|"+m.bearish_event_id,"Medium break aligned with slow structure");

      if(BullContext(s) && m.leg_direction==MSZZ_DIR_SHORT && f.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_NESTED_PULLBACK,MSZZ_DIR_LONG,signal_time,close_price,long_stop,8.4,3,
                      "Nested Pullback Continuation","CLUSTER|"+f.bullish_event_id,"Slow uptrend, medium correction, fast bullish reversal");
      if(BearContext(s) && m.leg_direction==MSZZ_DIR_LONG && f.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_NESTED_PULLBACK,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,8.4,3,
                      "Nested Pullback Continuation","CLUSTER|"+f.bearish_event_id,"Slow downtrend, medium correction, fast bearish reversal");

      int bull_votes=(f.bullish_break?1:0)+(BullContext(m)?1:0)+(BullContext(s)?1:0);
      int bear_votes=(f.bearish_break?1:0)+(BearContext(m)?1:0)+(BearContext(s)?1:0);
      if(bull_votes>=2 && f.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_WEIGHTED_ENSEMBLE,MSZZ_DIR_LONG,signal_time,close_price,long_stop,
                      3.0+1.4*bull_votes,bull_votes,"Weighted Three-Speed Ensemble","CLUSTER|"+f.bullish_event_id,
                      StringFormat("Bullish vote score %d/3",bull_votes));
      if(bear_votes>=2 && f.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_WEIGHTED_ENSEMBLE,MSZZ_DIR_SHORT,signal_time,close_price,short_stop,
                      3.0+1.4*bear_votes,bear_votes,"Weighted Three-Speed Ensemble","CLUSTER|"+f.bearish_event_id,
                      StringFormat("Bearish vote score %d/3",bear_votes));
      return n;
   }

   int SelectBestClustered(const MSZZCandidate &in[],const int count,MSZZCandidate &selected) const
   {
      ZeroMemory(selected);
      if(count<=0) return -1;
      int best=-1;
      double best_score=-DBL_MAX;
      for(int i=0;i<count;i++)
      {
         if(!in[i].valid || in[i].stop<=0.0 || in[i].entry==in[i].stop) continue;
         double composite=in[i].score+0.25*(double)MathMax(0,in[i].supporting_models-1);
         if(composite>best_score)
         {
            best_score=composite; best=i;
         }
      }
      if(best>=0) selected=in[best];
      return best;
   }
};

#endif