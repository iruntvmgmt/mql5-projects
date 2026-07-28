#ifndef __MSZZ_D027_STRATEGY_FAMILIES_MQH__
#define __MSZZ_D027_STRATEGY_FAMILIES_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>

// D027 Stage 3 canonical research definitions. These values are frozen before
// the Stage 4 screen and are intentionally not user-optimizable in D027.
#define MSZZ_D027_RETEST_WINDOW_BARS       12
#define MSZZ_D027_RETEST_TOLERANCE_ATR     0.15
#define MSZZ_D027_RETEST_INVALIDATION_ATR  0.30
#define MSZZ_D027_SWEEP_WINDOW_BARS         6
#define MSZZ_D027_SWEEP_MIN_ATR             0.10
#define MSZZ_D027_SWEEP_RECLAIM_ATR         0.05
#define MSZZ_D027_SWEEP_FAILURE_ATR         0.50
#define MSZZ_D027_COMPRESSION_MIN_BARS      3
#define MSZZ_D027_COMPRESSION_WAIT_BARS     6

enum ENUM_MSZZ_D027_SETUP_STATE
{
   MSZZ_D027_IDLE=0,
   MSZZ_D027_ARMED=1,
   MSZZ_D027_TOUCHED=2,
   MSZZ_D027_SWEPT=3,
   MSZZ_D027_TRIGGERED=4,
   MSZZ_D027_EXPIRED=5,
   MSZZ_D027_INVALIDATED=6
};

struct MSZZD027Setup
{
   bool                    active;
   ENUM_MSZZ_STRATEGY_ID   strategy_id;
   ENUM_MSZZ_STRATEGY_FAMILY family_id;
   ENUM_MSZZ_DIRECTION     direction;
   ENUM_MSZZ_D027_SETUP_STATE state;
   datetime                origin_time;
   datetime                expiry_time;
   double                  origin_level;
   double                  invalidation_level;
   double                  structural_stop;
   double                  deepest_excursion;
   string                  origin_id;
   string                  sequence_id;
};

class CMSZZD027StrategyFamilies
{
private:
   bool m_s1,m_s2,m_s3,m_s4,m_s5,m_write_journal;
   double m_rr;
   int m_validity_bars,m_period_seconds,m_compression_count;
   string m_state_file;
   MSZZD027Setup m_retest_long,m_retest_short,m_sweep_long,m_sweep_short,m_compression;

   void Reset(MSZZD027Setup &s) const
   {
      ZeroMemory(s); s.state=MSZZ_D027_IDLE;
      s.strategy_id=MSZZ_STRAT_NONE; s.family_id=MSZZ_FAMILY_NONE; s.direction=MSZZ_DIR_NONE;
   }

   string StateText(const ENUM_MSZZ_D027_SETUP_STATE state) const
   {
      switch(state)
      {
         case MSZZ_D027_ARMED: return "ARMED";
         case MSZZ_D027_TOUCHED: return "RETEST_ZONE";
         case MSZZ_D027_SWEPT: return "SWEPT";
         case MSZZ_D027_TRIGGERED: return "TRIGGERED";
         case MSZZ_D027_EXPIRED: return "EXPIRED";
         case MSZZ_D027_INVALIDATED: return "INVALIDATED";
         default: return "IDLE";
      }
   }

   void Journal(const MSZZD027Setup &s,const datetime t,const string reason) const
   {
      if(!m_write_journal) return;
      int h=FileOpen("MSZZ_SequenceJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(h==INVALID_HANDLE) return;
      if(FileSize(h)==0)
         FileWrite(h,"sequence_id","strategy_id","family_id","state","direction","origin_time",
                   "origin_level","confirmation_time","expiry_time","invalidation_time","final_event_id","reason");
      FileSeek(h,0,SEEK_END);
      FileWrite(h,s.sequence_id,(int)s.strategy_id,(int)s.family_id,StateText(s.state),MSZZDirectionText(s.direction),
                TimeToString(s.origin_time,TIME_DATE|TIME_SECONDS),DoubleToString(s.origin_level,_Digits),
                (s.state==MSZZ_D027_TRIGGERED ? TimeToString(t,TIME_DATE|TIME_SECONDS) : ""),
                TimeToString(s.expiry_time,TIME_DATE|TIME_SECONDS),
                (s.state==MSZZ_D027_INVALIDATED ? TimeToString(t,TIME_DATE|TIME_SECONDS) : ""),
                (s.state==MSZZ_D027_TRIGGERED ? s.sequence_id+"|FINAL" : ""),reason);
      FileFlush(h); FileClose(h);
   }

   void Transition(MSZZD027Setup &s,const ENUM_MSZZ_D027_SETUP_STATE state,
                   const datetime t,const string reason)
   {
      s.state=state;
      Journal(s,t,reason);
      if(state==MSZZ_D027_TRIGGERED || state==MSZZ_D027_EXPIRED || state==MSZZ_D027_INVALIDATED)
         s.active=false;
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

   void Emit(MSZZCandidate &out[],int &count,const ENUM_MSZZ_STRATEGY_ID id,
             const ENUM_MSZZ_STRATEGY_FAMILY family,const ENUM_MSZZ_DIRECTION direction,
             const ENUM_MSZZ_ORIGIN_TYPE origin_type,const datetime t,const double entry,
             const double stop,const double score,const int evidence,const string name,
             const string origin_id,const string event_id,const string reason) const
   {
      if(origin_id=="" || event_id=="" || entry<=0.0 || stop<=0.0 || entry==stop) return;
      if(direction==MSZZ_DIR_LONG && stop>=entry) return;
      if(direction==MSZZ_DIR_SHORT && stop<=entry) return;
      int n=ArraySize(out); ArrayResize(out,n+1);
      MSZZCandidate c; ZeroMemory(c);
      c.valid=true; c.strategy_id=id; c.family_id=family; c.direction=direction;
      c.origin_type=origin_type; c.signal_time=t;
      c.expiry_time=t+(datetime)(MathMax(1,m_validity_bars)*m_period_seconds);
      c.entry=entry; c.stop=stop; c.score=score; c.supporting_models=2;
      c.evidence_mask=evidence; c.setup_name=name; c.origin_id=origin_id;
      c.event_id=event_id; c.reason=reason;
      double risk=MathAbs(entry-stop);
      c.target=(direction==MSZZ_DIR_LONG ? entry+risk*m_rr : entry-risk*m_rr);
      out[n]=c; count++;
   }

   void ArmRetest(MSZZD027Setup &setup,const ENUM_MSZZ_DIRECTION direction,
                  const datetime t,const double level,const double atr,const double stop,
                  const string origin_id)
   {
      Reset(setup); setup.active=true; setup.strategy_id=MSZZ_STRAT_BREAKOUT_RETEST;
      setup.family_id=MSZZ_FAMILY_RETEST; setup.direction=direction; setup.state=MSZZ_D027_ARMED;
      setup.origin_time=t; setup.expiry_time=t+(datetime)(MSZZ_D027_RETEST_WINDOW_BARS*m_period_seconds);
      setup.origin_level=level; setup.structural_stop=stop; setup.origin_id=origin_id;
      setup.invalidation_level=(direction==MSZZ_DIR_LONG ? level-atr*MSZZ_D027_RETEST_INVALIDATION_ATR :
                                                         level+atr*MSZZ_D027_RETEST_INVALIDATION_ATR);
      setup.sequence_id="RT|"+origin_id;
      Journal(setup,t,"compatible breakout armed; projected breakout level frozen");
   }

   void EvaluateRetestSide(MSZZD027Setup &setup,const MqlRates &bar,const double atr,
                           const bool opposite_break,MSZZCandidate &out[],int &count)
   {
      if(!setup.active) return;
      if(bar.time>setup.expiry_time){ Transition(setup,MSZZ_D027_EXPIRED,bar.time,"fixed 12-bar retest window elapsed"); return; }
      if(opposite_break){ Transition(setup,MSZZ_D027_INVALIDATED,bar.time,"opposite fast breakout"); return; }
      double tolerance=atr*MSZZ_D027_RETEST_TOLERANCE_ATR;
      bool invalid=(setup.direction==MSZZ_DIR_LONG ? bar.close<setup.invalidation_level :
                                                    bar.close>setup.invalidation_level);
      if(invalid){ Transition(setup,MSZZ_D027_INVALIDATED,bar.time,"close beyond frozen invalidation tolerance"); return; }
      bool touched=(setup.direction==MSZZ_DIR_LONG ? bar.low<=setup.origin_level+tolerance :
                                                    bar.high>=setup.origin_level-tolerance);
      if(touched && setup.state==MSZZ_D027_ARMED)
      {
         setup.state=MSZZ_D027_TOUCHED;
         setup.deepest_excursion=(setup.direction==MSZZ_DIR_LONG ? bar.low : bar.high);
         Journal(setup,bar.time,"price entered frozen retest zone");
      }
      if(setup.state!=MSZZ_D027_TOUCHED) return;
      if(setup.direction==MSZZ_DIR_LONG) setup.deepest_excursion=MathMin(setup.deepest_excursion,bar.low);
      else setup.deepest_excursion=MathMax(setup.deepest_excursion,bar.high);
      bool reclaimed=(setup.direction==MSZZ_DIR_LONG ? bar.close>setup.origin_level+tolerance :
                                                      bar.close<setup.origin_level-tolerance);
      if(!reclaimed) return;
      double stop=(setup.direction==MSZZ_DIR_LONG ? MathMin(setup.deepest_excursion,setup.invalidation_level) :
                                                   MathMax(setup.deepest_excursion,setup.invalidation_level));
      Emit(out,count,MSZZ_STRAT_BREAKOUT_RETEST,MSZZ_FAMILY_RETEST,setup.direction,MSZZ_ORIGIN_FAST_BREAK,
           bar.time,bar.close,stop,7.5,MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_RETEST|MSZZ_EVIDENCE_CONTEXT,
           "Breakout Retest Continuation",setup.origin_id,setup.sequence_id+"|FINAL",
           "FastMed-compatible break survived frozen-level retest and closed-bar reclaim");
      Transition(setup,MSZZ_D027_TRIGGERED,bar.time,"closed bar reclaimed frozen breakout level");
   }

   void ArmSweep(MSZZD027Setup &setup,const ENUM_MSZZ_DIRECTION direction,const datetime t,
                 const double level,const double excursion,const double atr,const string origin_id)
   {
      Reset(setup); setup.active=true; setup.strategy_id=MSZZ_STRAT_SWEEP_RECLAIM;
      setup.family_id=MSZZ_FAMILY_REVERSAL; setup.direction=direction; setup.state=MSZZ_D027_SWEPT;
      setup.origin_time=t; setup.expiry_time=t+(datetime)(MSZZ_D027_SWEEP_WINDOW_BARS*m_period_seconds);
      setup.origin_level=level; setup.deepest_excursion=excursion; setup.origin_id=origin_id;
      setup.invalidation_level=(direction==MSZZ_DIR_LONG ? level-atr*MSZZ_D027_SWEEP_FAILURE_ATR :
                                                         level+atr*MSZZ_D027_SWEEP_FAILURE_ATR);
      setup.sequence_id="SR|"+origin_id+"|"+IntegerToString((long)t);
      Journal(setup,t,"minimum excursion beyond confirmed pivot shelf");
   }

   void EvaluateSweepSide(MSZZD027Setup &setup,const MqlRates &bar,const double atr,
                          const bool structure_confirms,const bool context_forbidden,
                          MSZZCandidate &out[],int &count)
   {
      if(!setup.active) return;
      if(bar.time>setup.expiry_time){ Transition(setup,MSZZ_D027_EXPIRED,bar.time,"fixed 6-bar reclaim window elapsed"); return; }
      if(context_forbidden){ Transition(setup,MSZZ_D027_INVALIDATED,bar.time,"medium and slow strongly oppose reclaim"); return; }
      if(setup.direction==MSZZ_DIR_LONG) setup.deepest_excursion=MathMin(setup.deepest_excursion,bar.low);
      else setup.deepest_excursion=MathMax(setup.deepest_excursion,bar.high);
      bool failed=(setup.direction==MSZZ_DIR_LONG ? bar.close<setup.invalidation_level :
                                                   bar.close>setup.invalidation_level);
      if(failed){ Transition(setup,MSZZ_D027_INVALIDATED,bar.time,"close exceeded maximum failure distance"); return; }
      double reclaim=atr*MSZZ_D027_SWEEP_RECLAIM_ATR;
      bool reclaimed=(setup.direction==MSZZ_DIR_LONG ? bar.close>setup.origin_level+reclaim :
                                                      bar.close<setup.origin_level-reclaim);
      if(!reclaimed || !structure_confirms) return;
      double stop=setup.deepest_excursion;
      Emit(out,count,MSZZ_STRAT_SWEEP_RECLAIM,MSZZ_FAMILY_REVERSAL,setup.direction,MSZZ_ORIGIN_PIVOT_SWEEP,
           bar.time,bar.close,stop,7.0,MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_STRUCTURE,
           "Sweep and Reclaim",setup.origin_id,setup.sequence_id+"|FINAL",
           "confirmed pivot shelf swept, closed-bar reclaim and fast upward/downward confirmation");
      Transition(setup,MSZZ_D027_TRIGGERED,bar.time,"closed-bar reclaim with fast structure confirmation");
   }

   void SaveOne(const int h,const string key,const MSZZD027Setup &s) const
   {
      FileWrite(h,key,(s.active?1:0),(int)s.strategy_id,(int)s.family_id,(int)s.direction,(int)s.state,
                (long)s.origin_time,(long)s.expiry_time,DoubleToString(s.origin_level,10),
                DoubleToString(s.invalidation_level,10),DoubleToString(s.structural_stop,10),
                DoubleToString(s.deepest_excursion,10),s.origin_id,s.sequence_id);
   }

   void LoadOne(MSZZD027Setup &s,const string &values[])
   {
      Reset(s); if(ArraySize(values)<13) return;
      s.active=((int)StringToInteger(values[1])==1);
      s.strategy_id=(ENUM_MSZZ_STRATEGY_ID)StringToInteger(values[2]);
      s.family_id=(ENUM_MSZZ_STRATEGY_FAMILY)StringToInteger(values[3]);
      s.direction=(ENUM_MSZZ_DIRECTION)StringToInteger(values[4]);
      s.state=(ENUM_MSZZ_D027_SETUP_STATE)StringToInteger(values[5]);
      s.origin_time=(datetime)StringToInteger(values[6]); s.expiry_time=(datetime)StringToInteger(values[7]);
      s.origin_level=StringToDouble(values[8]); s.invalidation_level=StringToDouble(values[9]);
      s.structural_stop=StringToDouble(values[10]); s.deepest_excursion=StringToDouble(values[11]);
      s.origin_id=values[12]; if(ArraySize(values)>13) s.sequence_id=values[13];
   }

   bool ReadOne(const int h,const string expected,MSZZD027Setup &s)
   {
      string values[]; ArrayResize(values,14);
      for(int i=0;i<14;i++)
      {
         if(FileIsEnding(h)) return false;
         values[i]=FileReadString(h);
      }
      if(values[0]!=expected) return false;
      LoadOne(s,values); return true;
   }

public:
   CMSZZD027StrategyFamilies()
   {
      m_s1=false; m_s2=false; m_s3=false; m_s4=false; m_s5=false;
      m_write_journal=false; m_rr=2.0; m_validity_bars=3; m_period_seconds=300;
      m_compression_count=0; m_state_file="";
      Reset(m_retest_long); Reset(m_retest_short); Reset(m_sweep_long);
      Reset(m_sweep_short); Reset(m_compression);
   }

   void Configure(const bool s1,const bool s2,const bool s3,const bool s4,const bool s5,
                  const double rr,const int validity_bars,const int period_seconds,
                  const bool write_journal,const string state_file)
   {
      m_s1=s1; m_s2=s2; m_s3=s3; m_s4=s4; m_s5=s5; m_rr=MathMax(0.1,rr);
      m_validity_bars=MathMax(1,validity_bars); m_period_seconds=MathMax(1,period_seconds);
      m_write_journal=write_journal; m_state_file=state_file;
   }

   bool AnyEnabled() const { return m_s1 || m_s2 || m_s3 || m_s4 || m_s5; }

   bool SaveState() const
   {
      if(m_state_file=="") return false;
      int h=FileOpen(m_state_file,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
      if(h==INVALID_HANDLE) return false;
      FileWrite(h,m_compression_count);
      SaveOne(h,"RETEST_LONG",m_retest_long); SaveOne(h,"RETEST_SHORT",m_retest_short);
      SaveOne(h,"SWEEP_LONG",m_sweep_long); SaveOne(h,"SWEEP_SHORT",m_sweep_short);
      SaveOne(h,"COMPRESSION",m_compression);
      FileFlush(h); FileClose(h); return true;
   }

   bool LoadState()
   {
      if(m_state_file=="" || !FileIsExist(m_state_file)) return true;
      int h=FileOpen(m_state_file,FILE_READ|FILE_CSV|FILE_ANSI,';');
      if(h==INVALID_HANDLE) return false;
      m_compression_count=(int)FileReadNumber(h);
      bool ok=ReadOne(h,"RETEST_LONG",m_retest_long) &&
              ReadOne(h,"RETEST_SHORT",m_retest_short) &&
              ReadOne(h,"SWEEP_LONG",m_sweep_long) &&
              ReadOne(h,"SWEEP_SHORT",m_sweep_short) &&
              ReadOne(h,"COMPRESSION",m_compression);
      FileClose(h); return ok;
   }

   int Evaluate(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m,const MSZZSpeedSnapshot &s,
                const MSZZRegimeState &regime,const MqlRates &bar,MSZZCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      double atr=(f.atr>0.0 ? f.atr : 0.0);
      if(atr<=0.0) return 0;

      // S1: the confirmed HL/LH is the completed pullback pivot; the fast
      // close-confirmed break is the reversal trigger. Medium may align or
      // be the countertrend correction, while slow defines primary direction.
      if(m_s1 && s.leg_direction==MSZZ_DIR_LONG && m.leg_direction!=MSZZ_DIR_NONE &&
         f.last_low.valid && f.last_low.structure_label==MSZZ_STRUCT_HL && f.bullish_break)
         Emit(out,count,MSZZ_STRAT_ALIGNED_FAST_PULLBACK,MSZZ_FAMILY_PULLBACK,MSZZ_DIR_LONG,
              MSZZ_ORIGIN_FAST_BREAK,bar.time,bar.close,f.last_low.price,7.0,
              MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,
              "Aligned Fast Pullback Continuation",f.last_low.id,
              "AFP|"+f.last_low.id+"|"+f.bullish_event_id,
              "slow bullish, confirmed fast HL after correction, closed-bar reversal break");
      if(m_s1 && s.leg_direction==MSZZ_DIR_SHORT && m.leg_direction!=MSZZ_DIR_NONE &&
         f.last_high.valid && f.last_high.structure_label==MSZZ_STRUCT_LH && f.bearish_break)
         Emit(out,count,MSZZ_STRAT_ALIGNED_FAST_PULLBACK,MSZZ_FAMILY_PULLBACK,MSZZ_DIR_SHORT,
              MSZZ_ORIGIN_FAST_BREAK,bar.time,bar.close,f.last_high.price,7.0,
              MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,
              "Aligned Fast Pullback Continuation",f.last_high.id,
              "AFP|"+f.last_high.id+"|"+f.bearish_event_id,
              "slow bearish, confirmed fast LH after correction, closed-bar reversal break");

      // S2: process previously armed sequences before arming this bar, so an
      // initial displacement can never also count as its own retest.
      if(m_s2)
      {
         EvaluateRetestSide(m_retest_long,bar,atr,f.bearish_break,out,count);
         EvaluateRetestSide(m_retest_short,bar,atr,f.bullish_break,out,count);
         if(f.bullish_break && BullContext(m) && BullContext(s) && f.resistance_now>0.0)
            ArmRetest(m_retest_long,MSZZ_DIR_LONG,bar.time,f.resistance_now,atr,
                      (f.last_low.valid?f.last_low.price:0.0),f.bullish_event_id);
         if(f.bearish_break && BearContext(m) && BearContext(s) && f.support_now>0.0)
            ArmRetest(m_retest_short,MSZZ_DIR_SHORT,bar.time,f.support_now,atr,
                      (f.last_high.valid?f.last_high.price:0.0),f.bearish_event_id);
      }

      // S3: confirmed fast pivot shelves only. A sweep may reclaim on the same
      // closed bar, but the wick alone never emits a candidate.
      if(m_s3)
      {
         if(!m_sweep_long.active && f.last_low.valid &&
            bar.low<=f.last_low.price-atr*MSZZ_D027_SWEEP_MIN_ATR)
            ArmSweep(m_sweep_long,MSZZ_DIR_LONG,bar.time,f.last_low.price,bar.low,atr,f.last_low.id);
         if(!m_sweep_short.active && f.last_high.valid &&
            bar.high>=f.last_high.price+atr*MSZZ_D027_SWEEP_MIN_ATR)
            ArmSweep(m_sweep_short,MSZZ_DIR_SHORT,bar.time,f.last_high.price,bar.high,atr,f.last_high.id);
         bool bull_confirm=f.bullish_break ||
                           (f.leg_direction==MSZZ_DIR_LONG && f.last_low.structure_label==MSZZ_STRUCT_HL);
         bool bear_confirm=f.bearish_break ||
                           (f.leg_direction==MSZZ_DIR_SHORT && f.last_high.structure_label==MSZZ_STRUCT_LH);
         EvaluateSweepSide(m_sweep_long,bar,atr,bull_confirm,
                           m.leg_direction==MSZZ_DIR_SHORT && s.leg_direction==MSZZ_DIR_SHORT,out,count);
         EvaluateSweepSide(m_sweep_short,bar,atr,bear_confirm,
                           m.leg_direction==MSZZ_DIR_LONG && s.leg_direction==MSZZ_DIR_LONG,out,count);
      }

      // S4: persist three consecutive causal COMPRESSION labels, then freeze
      // confirmed fast boundaries for a six-bar close-confirmed release.
      if(m_s4)
      {
         if(!m_compression.active && regime.market_phase==MSZZ_PHASE_COMPRESSION &&
            f.last_high.valid && f.last_low.valid)
         {
            m_compression_count++;
            if(m_compression_count>=MSZZ_D027_COMPRESSION_MIN_BARS)
            {
               Reset(m_compression); m_compression.active=true;
               m_compression.strategy_id=MSZZ_STRAT_COMPRESSION_BREAKOUT;
               m_compression.family_id=MSZZ_FAMILY_COMPRESSION;
               m_compression.state=MSZZ_D027_ARMED; m_compression.origin_time=bar.time;
               m_compression.expiry_time=bar.time+(datetime)(MSZZ_D027_COMPRESSION_WAIT_BARS*m_period_seconds);
               m_compression.origin_level=f.last_high.price;
               m_compression.invalidation_level=f.last_low.price;
               m_compression.origin_id="COMP|"+f.last_low.id+"|"+f.last_high.id;
               m_compression.sequence_id=m_compression.origin_id+"|"+IntegerToString((long)bar.time);
               Journal(m_compression,bar.time,"three consecutive causal compression bars; boundaries frozen");
            }
         }
         else if(!m_compression.active) m_compression_count=0;

         if(m_compression.active)
         {
            if(bar.time>m_compression.expiry_time)
            {
               Transition(m_compression,MSZZ_D027_EXPIRED,bar.time,"fixed six-bar compression release window elapsed");
               m_compression_count=0;
            }
            else if(bar.close>m_compression.origin_level && (BullContext(m) || BullContext(s)))
            {
               Emit(out,count,MSZZ_STRAT_COMPRESSION_BREAKOUT,MSZZ_FAMILY_COMPRESSION,MSZZ_DIR_LONG,
                    MSZZ_ORIGIN_COMPRESSION_RELEASE,bar.time,bar.close,m_compression.invalidation_level,7.0,
                    MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,
                    "Compression Breakout",m_compression.origin_id,m_compression.sequence_id+"|FINAL",
                    "three-bar compression followed by close above frozen boundary with context");
               Transition(m_compression,MSZZ_D027_TRIGGERED,bar.time,"bullish close outside compression boundary");
               m_compression_count=0;
            }
            else if(bar.close<m_compression.invalidation_level && (BearContext(m) || BearContext(s)))
            {
               Emit(out,count,MSZZ_STRAT_COMPRESSION_BREAKOUT,MSZZ_FAMILY_COMPRESSION,MSZZ_DIR_SHORT,
                    MSZZ_ORIGIN_COMPRESSION_RELEASE,bar.time,bar.close,m_compression.origin_level,7.0,
                    MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,
                    "Compression Breakout",m_compression.origin_id,m_compression.sequence_id+"|FINAL",
                    "three-bar compression followed by close below frozen boundary with context");
               Transition(m_compression,MSZZ_D027_TRIGGERED,bar.time,"bearish close outside compression boundary");
               m_compression_count=0;
            }
         }
      }

      // S5: RegimeClassifier's TRANSITION contract already requires the exact
      // four-pivot LL,LH,HL,HH / HH,HL,LH,LL sequence and medium validation.
      if(m_s5 && regime.market_phase==MSZZ_PHASE_TRANSITION)
      {
         if(m.leg_direction==MSZZ_DIR_LONG && f.last_low.valid && f.last_high.valid)
            Emit(out,count,MSZZ_STRAT_STRUCTURE_TRANSITION,MSZZ_FAMILY_REVERSAL,MSZZ_DIR_LONG,
                 MSZZ_ORIGIN_STRUCTURE_TRANSITION,bar.time,bar.close,f.last_low.price,7.2,
                 MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,
                 "Confirmed Structure Transition",f.last_low.id,
                 "ST|B|"+f.last_low.id+"|"+f.last_high.id,
                 "confirmed LL/LH to HL/HH sequence with medium bullish validation");
         if(m.leg_direction==MSZZ_DIR_SHORT && f.last_low.valid && f.last_high.valid)
            Emit(out,count,MSZZ_STRAT_STRUCTURE_TRANSITION,MSZZ_FAMILY_REVERSAL,MSZZ_DIR_SHORT,
                 MSZZ_ORIGIN_STRUCTURE_TRANSITION,bar.time,bar.close,f.last_high.price,7.2,
                 MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE,
                 "Confirmed Structure Transition",f.last_high.id,
                 "ST|S|"+f.last_high.id+"|"+f.last_low.id,
                 "confirmed HH/HL to LH/LL sequence with medium bearish validation");
      }

      if(AnyEnabled()) SaveState();
      return count;
   }
};

#endif
