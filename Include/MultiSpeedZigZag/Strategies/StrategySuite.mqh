#ifndef __MSZZ_STRATEGY_SUITE_MQH__
#define __MSZZ_STRATEGY_SUITE_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

class CMSZZStrategySuite
{
private:
   bool m_fast_breakout,m_medium_breakout,m_slow_breakout,m_fast_medium_confluence;
   bool m_fast_medium_context,m_medium_slow_context,m_nested_pullback,m_weighted_ensemble;
   double m_rr;
   int m_validity_bars;

   void ClearCandidate(MSZZCandidate &c) const { ZeroMemory(c); c.strategy_id=MSZZ_STRAT_NONE; c.family_id=MSZZ_FAMILY_NONE; }

   ENUM_MSZZ_STRATEGY_FAMILY FamilyFor(const ENUM_MSZZ_STRATEGY_ID id) const
   {
      if(id==MSZZ_STRAT_NESTED_PULLBACK || id==MSZZ_STRAT_ALIGNED_FAST_PULLBACK) return MSZZ_FAMILY_PULLBACK;
      if(id==MSZZ_STRAT_BREAKOUT_RETEST) return MSZZ_FAMILY_RETEST;
      if(id==MSZZ_STRAT_SWEEP_RECLAIM || id==MSZZ_STRAT_STRUCTURE_TRANSITION) return MSZZ_FAMILY_REVERSAL;
      if(id==MSZZ_STRAT_COMPRESSION_BREAKOUT) return MSZZ_FAMILY_COMPRESSION;
      if(id==MSZZ_STRAT_WEIGHTED_ENSEMBLE) return MSZZ_FAMILY_ENSEMBLE;
      if(id!=MSZZ_STRAT_NONE) return MSZZ_FAMILY_BREAKOUT;
      return MSZZ_FAMILY_NONE;
   }

   void AddCandidate(MSZZCandidate &out[],int &count,const ENUM_MSZZ_STRATEGY_ID id,
                     const ENUM_MSZZ_DIRECTION dir,const ENUM_MSZZ_ORIGIN_TYPE origin_type,
                     const datetime t,const double entry,const double stop,const double score,
                     const int models,const int evidence_mask,const string name,
                     const string origin_id,const string event_id,const string reason) const
   {
      if(origin_id=="" || event_id=="" || entry<=0.0 || stop<=0.0 || entry==stop) return;
      if(count>=ArraySize(out)) ArrayResize(out,count+16);
      MSZZCandidate c; ClearCandidate(c);
      c.valid=true; c.strategy_id=id; c.family_id=FamilyFor(id); c.direction=dir; c.origin_type=origin_type;
      c.signal_time=t; c.entry=entry; c.stop=stop; c.score=score;
      c.supporting_models=models; c.evidence_mask=evidence_mask;
      c.setup_name=name; c.origin_id=origin_id; c.event_id=event_id; c.reason=reason;
      double risk=MathAbs(entry-stop);
      c.target=(dir==MSZZ_DIR_LONG ? entry+risk*m_rr : entry-risk*m_rr);
      // D015: signal-validity horizon, in bars past signal_time. Was
      // previously never assigned anywhere (always 0) -- see DECISION_LOG.md
      // D015 for why this was a deeper gap than just "unenforced."
      c.expiry_time=t+(datetime)(MathMax(1,m_validity_bars)*PeriodSeconds());
      out[count++]=c;
   }

   bool BullContext(const MSZZSpeedSnapshot &s) const
   {
      return s.leg_direction==MSZZ_DIR_LONG || s.last_low.structure_label==MSZZ_STRUCT_HL || s.last_high.structure_label==MSZZ_STRUCT_HH;
   }
   bool BearContext(const MSZZSpeedSnapshot &s) const
   {
      return s.leg_direction==MSZZ_DIR_SHORT || s.last_high.structure_label==MSZZ_STRUCT_LH || s.last_low.structure_label==MSZZ_STRUCT_LL;
   }
   double LongStop(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m) const
   { if(m.last_low.valid) return m.last_low.price; if(f.last_low.valid) return f.last_low.price; return 0.0; }
   double ShortStop(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m) const
   { if(m.last_high.valid) return m.last_high.price; if(f.last_high.valid) return f.last_high.price; return 0.0; }

public:
   CMSZZStrategySuite(void)
   {
      m_fast_breakout=true; m_medium_breakout=true; m_slow_breakout=true;
      m_fast_medium_confluence=true; m_fast_medium_context=true; m_medium_slow_context=true;
      m_nested_pullback=true; m_weighted_ensemble=true; m_rr=1.5;
      m_validity_bars=3;
   }

   void ConfigureStrategies(const bool fast_breakout,const bool medium_breakout,const bool slow_breakout,
                            const bool fast_medium_confluence,const bool fast_medium_context,
                            const bool medium_slow_context,const bool nested_pullback,const bool weighted_ensemble)
   {
      m_fast_breakout=fast_breakout; m_medium_breakout=medium_breakout; m_slow_breakout=slow_breakout;
      m_fast_medium_confluence=fast_medium_confluence; m_fast_medium_context=fast_medium_context;
      m_medium_slow_context=medium_slow_context; m_nested_pullback=nested_pullback;
      m_weighted_ensemble=weighted_ensemble;
   }

   void SetRiskReward(const double rr) { m_rr=MathMax(0.1,rr); }
   void SetSignalValidityBars(const int bars) { m_validity_bars=MathMax(1,bars); }

   int Evaluate(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m,const MSZZSpeedSnapshot &s,
                const datetime signal_time,const double close_price,MSZZCandidate &out[])
   {
      ArrayResize(out,0);
      int n=0;
      double long_stop=LongStop(f,m),short_stop=ShortStop(f,m);

      if(m_fast_breakout && f.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_FAST_BREAKOUT,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,long_stop,4.0,1,
                      MSZZ_EVIDENCE_TRIGGER,"Fast Breakout",f.bullish_event_id,f.bullish_event_id,"Fast resistance projection broken on close");
      if(m_fast_breakout && f.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_FAST_BREAKOUT,MSZZ_DIR_SHORT,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,short_stop,4.0,1,
                      MSZZ_EVIDENCE_TRIGGER,"Fast Breakout",f.bearish_event_id,f.bearish_event_id,"Fast support projection broken on close");

      if(m_medium_breakout && m.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_BREAKOUT,MSZZ_DIR_LONG,MSZZ_ORIGIN_MEDIUM_BREAK,signal_time,close_price,long_stop,5.5,1,
                      MSZZ_EVIDENCE_TRIGGER,"Medium Breakout",m.bullish_event_id,m.bullish_event_id,"Medium resistance projection broken on close");
      if(m_medium_breakout && m.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_BREAKOUT,MSZZ_DIR_SHORT,MSZZ_ORIGIN_MEDIUM_BREAK,signal_time,close_price,short_stop,5.5,1,
                      MSZZ_EVIDENCE_TRIGGER,"Medium Breakout",m.bearish_event_id,m.bearish_event_id,"Medium support projection broken on close");

      if(m_slow_breakout && s.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_SLOW_BREAKOUT,MSZZ_DIR_LONG,MSZZ_ORIGIN_SLOW_BREAK,signal_time,close_price,long_stop,7.0,1,
                      MSZZ_EVIDENCE_TRIGGER,"Slow Breakout",s.bullish_event_id,s.bullish_event_id,"Slow resistance projection broken on close");
      if(m_slow_breakout && s.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_SLOW_BREAKOUT,MSZZ_DIR_SHORT,MSZZ_ORIGIN_SLOW_BREAK,signal_time,close_price,short_stop,7.0,1,
                      MSZZ_EVIDENCE_TRIGGER,"Slow Breakout",s.bearish_event_id,s.bearish_event_id,"Slow support projection broken on close");

      if(m_fast_medium_confluence && f.bullish_break && (m.bullish_break || BullContext(m)) && BullContext(s))
         AddCandidate(out,n,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,long_stop,8.0,
                      (m.bullish_break?3:2),MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Fast + Medium Confluence / Slow Alignment",
                      f.bullish_event_id,"CFM|"+f.bullish_event_id,"Fast trigger, medium confirmation/context, slow bullish alignment");
      if(m_fast_medium_confluence && f.bearish_break && (m.bearish_break || BearContext(m)) && BearContext(s))
         AddCandidate(out,n,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,MSZZ_DIR_SHORT,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,short_stop,8.0,
                      (m.bearish_break?3:2),MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Fast + Medium Confluence / Slow Alignment",
                      f.bearish_event_id,"CFM|"+f.bearish_event_id,"Fast trigger, medium confirmation/context, slow bearish alignment");

      if(m_fast_medium_context && f.bullish_break && BullContext(m))
         AddCandidate(out,n,MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,long_stop,6.3,2,
                      MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Fast Breakout with Medium Context",f.bullish_event_id,"FMC|"+f.bullish_event_id,"Fast break supported by medium structure");
      if(m_fast_medium_context && f.bearish_break && BearContext(m))
         AddCandidate(out,n,MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT,MSZZ_DIR_SHORT,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,short_stop,6.3,2,
                      MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Fast Breakout with Medium Context",f.bearish_event_id,"FMC|"+f.bearish_event_id,"Fast break supported by medium structure");

      if(m_medium_slow_context && m.bullish_break && BullContext(s))
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_WITH_SLOW_CONTEXT,MSZZ_DIR_LONG,MSZZ_ORIGIN_MEDIUM_BREAK,signal_time,close_price,long_stop,7.2,2,
                      MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Medium Breakout with Slow Context",m.bullish_event_id,"MSC|"+m.bullish_event_id,"Medium break aligned with slow structure");
      if(m_medium_slow_context && m.bearish_break && BearContext(s))
         AddCandidate(out,n,MSZZ_STRAT_MEDIUM_WITH_SLOW_CONTEXT,MSZZ_DIR_SHORT,MSZZ_ORIGIN_MEDIUM_BREAK,signal_time,close_price,short_stop,7.2,2,
                      MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Medium Breakout with Slow Context",m.bearish_event_id,"MSC|"+m.bearish_event_id,"Medium break aligned with slow structure");

      if(m_nested_pullback && BullContext(s) && m.leg_direction==MSZZ_DIR_SHORT && f.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_NESTED_PULLBACK,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,long_stop,8.4,3,
                      MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,"Nested Pullback Continuation",f.bullish_event_id,
                      "NP|"+f.bullish_event_id,"Slow uptrend, medium correction, fast bullish reversal");
      if(m_nested_pullback && BearContext(s) && m.leg_direction==MSZZ_DIR_LONG && f.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_NESTED_PULLBACK,MSZZ_DIR_SHORT,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,short_stop,8.4,3,
                      MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,"Nested Pullback Continuation",f.bearish_event_id,
                      "NP|"+f.bearish_event_id,"Slow downtrend, medium correction, fast bearish reversal");

      int bull_votes=(f.bullish_break?1:0)+(BullContext(m)?1:0)+(BullContext(s)?1:0);
      int bear_votes=(f.bearish_break?1:0)+(BearContext(m)?1:0)+(BearContext(s)?1:0);
      if(m_weighted_ensemble && bull_votes>=2 && f.bullish_break)
         AddCandidate(out,n,MSZZ_STRAT_WEIGHTED_ENSEMBLE,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,long_stop,
                      3.0+1.4*bull_votes,bull_votes,MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Weighted Three-Speed Ensemble",
                      f.bullish_event_id,"WE|"+f.bullish_event_id,StringFormat("Bullish vote score %d/3",bull_votes));
      if(m_weighted_ensemble && bear_votes>=2 && f.bearish_break)
         AddCandidate(out,n,MSZZ_STRAT_WEIGHTED_ENSEMBLE,MSZZ_DIR_SHORT,MSZZ_ORIGIN_FAST_BREAK,signal_time,close_price,short_stop,
                      3.0+1.4*bear_votes,bear_votes,MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT,"Weighted Three-Speed Ensemble",
                      f.bearish_event_id,"WE|"+f.bearish_event_id,StringFormat("Bearish vote score %d/3",bear_votes));
      return n;
   }

   int SelectBestClustered(const MSZZCandidate &in[],const int count,MSZZCandidate &selected) const
   {
      ZeroMemory(selected); selected.strategy_id=MSZZ_STRAT_NONE; selected.family_id=MSZZ_FAMILY_NONE;
      if(count<=0) return -1;
      int best=-1; double best_score=-1.0e100;
      for(int i=0;i<count;i++)
      {
         if(!in[i].valid || in[i].stop<=0.0 || in[i].entry==in[i].stop) continue;
         double composite=in[i].score+0.25*(double)MathMax(0,in[i].supporting_models-1);
         if(composite>best_score) { best_score=composite; best=i; }
      }
      if(best>=0) selected=in[best];
      return best;
   }
};

#endif
