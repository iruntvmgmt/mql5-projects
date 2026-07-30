#ifndef __MSZZ_SESSION_SWEEP_REVERSAL_STRATEGY_MQH__
#define __MSZZ_SESSION_SWEEP_REVERSAL_STRATEGY_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

// D033: production execution port of D031's Session Sweep Reversal
// research family (Research/Families/SessionSweepReversal.mqh), the only
// one of six D030-D035 shadow families to pass every D032 mandatory
// screening gate (822 trades, PF 1.079, positive dev/val/holdout
// expectancy, top-3/best-quarter exclusion positive, only 3.9% trade-
// window overlap with the existing SweepReclaim/1050 book -- see
// D032_SIX_FAMILY_SCREENING.md). Per D033's own instruction, the frozen
// canonical definition is preserved EXACTLY -- every constant below is
// copied verbatim from the research file, not re-derived or re-tuned:
// MIN_EXCURSION_ATR=0.15, RECLAIM_BUFFER_ATR=0.05, MAX_FAILURE_ATR=0.50,
// RECLAIM_WINDOW_BARS=6, TARGET_R=2.0, VALIDITY_BARS=3,
// ASIAN_SESSION_END_HOUR=8 (matching TradeAnalyticsExporter.mqh's
// SessionBucket, unchanged).
//
// This is a genuinely separate implementation from the research file --
// it emits the PRODUCTION MSZZCandidate type (Core/Types.mqh) through the
// same Emit()-with-invariants pattern D027StrategyFamilies.mqh already
// uses, not the disjoint MSZZResearchCandidate the shadow layer uses --
// so it can flow through CMSZZCandidateHandoff/StrategyBook/
// PortfolioRiskManager, which only ever accept MSZZCandidate. The
// research file is untouched and keeps running as a pure observer.
//
// Shadow-only trigger LOGIC is identical to the research version; only
// the output type and the strategy/family identity differ (production
// MSZZ_STRAT_SESSION_SWEEP_REVERSAL=1090 / MSZZ_FAMILY_REVERSAL=4, a
// deliberately different ID from the research layer's disjoint
// MSZZ_RSRCH_STRAT_SESSION_SWEEP_REVERSAL=1200/family=8 -- see
// Tools/D033/id_allocation.csv for why 1090, not 1200, was chosen).

#define MSZZ_SSR_PROD_MIN_EXCURSION_ATR    0.15
#define MSZZ_SSR_PROD_RECLAIM_BUFFER_ATR   0.05
#define MSZZ_SSR_PROD_MAX_FAILURE_ATR      0.50
#define MSZZ_SSR_PROD_RECLAIM_WINDOW_BARS  6
#define MSZZ_SSR_PROD_TARGET_R             2.0
#define MSZZ_SSR_PROD_VALIDITY_BARS        3
#define MSZZ_SSR_PROD_ASIAN_SESSION_END_HOUR 8

enum ENUM_MSZZ_SSR_PROD_STATE { MSZZ_SSR_PROD_IDLE=0, MSZZ_SSR_PROD_SWEPT=1, MSZZ_SSR_PROD_TRIGGERED=2, MSZZ_SSR_PROD_EXPIRED=3, MSZZ_SSR_PROD_INVALIDATED=4 };

struct MSZZSessionSweepReversalSetup
{
   bool                 active;
   ENUM_MSZZ_DIRECTION  direction;
   ENUM_MSZZ_SSR_PROD_STATE state;
   datetime             expiry_time;
   double               session_level;
   double               sweep_extreme;
   string               origin_id;
   string               sequence_id;
};

class CMSZZSessionSweepReversalStrategy
{
private:
   MSZZSessionSweepReversalSetup m_long,m_short;
   int m_period_seconds;
   double m_rr;
   int m_validity_bars;
   int m_anchor_day;
   double m_asian_high,m_asian_low;
   bool m_asian_frozen;

   void Reset(MSZZSessionSweepReversalSetup &s) const { ZeroMemory(s); s.state=MSZZ_SSR_PROD_IDLE; s.direction=MSZZ_DIR_NONE; }

   void UpdateAsianLevel(const MqlRates &bar)
   {
      MqlDateTime dt; TimeToStruct(bar.time,dt);
      int day_key=dt.year*10000+dt.mon*100+dt.day;
      if(day_key!=m_anchor_day)
      {
         m_anchor_day=day_key; m_asian_frozen=false;
         m_asian_high=bar.high; m_asian_low=bar.low;
      }
      if(dt.hour<MSZZ_SSR_PROD_ASIAN_SESSION_END_HOUR && !m_asian_frozen)
      {
         m_asian_high=MathMax(m_asian_high,bar.high);
         m_asian_low=MathMin(m_asian_low,bar.low);
      }
      else m_asian_frozen=true;
   }

   void Arm(MSZZSessionSweepReversalSetup &s,const ENUM_MSZZ_DIRECTION dir,const datetime t,
            const double level,const double excursion,const string origin_id)
   {
      Reset(s); s.active=true; s.direction=dir; s.state=MSZZ_SSR_PROD_SWEPT;
      s.expiry_time=t+(datetime)(MSZZ_SSR_PROD_RECLAIM_WINDOW_BARS*m_period_seconds);
      s.session_level=level; s.sweep_extreme=excursion; s.origin_id=origin_id;
      s.sequence_id="SSRP|"+origin_id+"|"+IntegerToString((long)t);
   }

   // Mirrors D027StrategyFamilies.mqh's own Emit() invariants exactly
   // (non-null keys, correct stop side, entry!=stop) -- same one-choke-
   // point discipline, applied to the production MSZZCandidate type.
   void Emit(MSZZCandidate &out[],int &count,const ENUM_MSZZ_DIRECTION direction,
             const datetime t,const double entry,const double stop,const double score,
             const string origin_id,const string event_id,const string reason) const
   {
      if(origin_id=="" || event_id=="" || entry<=0.0 || stop<=0.0 || entry==stop) return;
      if(direction==MSZZ_DIR_LONG && stop>=entry) return;
      if(direction==MSZZ_DIR_SHORT && stop<=entry) return;
      int n=ArraySize(out); ArrayResize(out,n+1);
      MSZZCandidate c; ZeroMemory(c);
      c.valid=true; c.strategy_id=MSZZ_STRAT_SESSION_SWEEP_REVERSAL; c.family_id=MSZZ_FAMILY_REVERSAL;
      c.direction=direction; c.origin_type=MSZZ_ORIGIN_PIVOT_SWEEP; c.signal_time=t;
      c.expiry_time=t+(datetime)(MathMax(1,m_validity_bars)*m_period_seconds);
      c.entry=entry; c.stop=stop; c.score=score; c.supporting_models=1;
      c.evidence_mask=MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_STRUCTURE;
      c.setup_name="Session Sweep Reversal"; c.origin_id=origin_id; c.event_id=event_id; c.reason=reason;
      double risk=MathAbs(entry-stop);
      c.target=(direction==MSZZ_DIR_LONG ? entry+risk*MSZZ_SSR_PROD_TARGET_R : entry-risk*MSZZ_SSR_PROD_TARGET_R);
      out[n]=c; count++;
   }

   void Evaluate1Side(MSZZSessionSweepReversalSetup &s,const MqlRates &bar,const double atr,
                       MSZZCandidate &out[],int &count)
   {
      if(!s.active) return;
      if(bar.time>s.expiry_time){ s.active=false; s.state=MSZZ_SSR_PROD_EXPIRED; return; }

      if(s.direction==MSZZ_DIR_LONG) s.sweep_extreme=MathMin(s.sweep_extreme,bar.low);
      else s.sweep_extreme=MathMax(s.sweep_extreme,bar.high);

      double failure=atr*MSZZ_SSR_PROD_MAX_FAILURE_ATR;
      bool acceptance=(s.direction==MSZZ_DIR_LONG ? bar.close<s.session_level-failure
                                                    : bar.close>s.session_level+failure);
      if(acceptance){ s.active=false; s.state=MSZZ_SSR_PROD_INVALIDATED; return; }

      double reclaim=atr*MSZZ_SSR_PROD_RECLAIM_BUFFER_ATR;
      bool reclaimed=(s.direction==MSZZ_DIR_LONG ? bar.close>s.session_level+reclaim
                                                   : bar.close<s.session_level-reclaim);
      if(!reclaimed) return;

      double stop=(s.direction==MSZZ_DIR_LONG ? s.sweep_extreme-atr*MSZZ_SSR_PROD_RECLAIM_BUFFER_ATR
                                                 : s.sweep_extreme+atr*MSZZ_SSR_PROD_RECLAIM_BUFFER_ATR);
      Emit(out,count,s.direction,bar.time,bar.close,stop,7.0,s.origin_id,s.sequence_id+"|FINAL",
           "Asia session level swept during London/NewYork, closed-bar reclaim within frozen window");
      s.active=false; s.state=MSZZ_SSR_PROD_TRIGGERED;
   }

public:
   CMSZZSessionSweepReversalStrategy()
   {
      m_period_seconds=300; m_rr=MSZZ_SSR_PROD_TARGET_R; m_validity_bars=MSZZ_SSR_PROD_VALIDITY_BARS;
      m_anchor_day=-1; m_asian_high=0.0; m_asian_low=0.0; m_asian_frozen=false;
      Reset(m_long); Reset(m_short);
   }

   void Configure(const int period_seconds,const int validity_bars)
   {
      m_period_seconds=MathMax(1,period_seconds);
      m_validity_bars=MathMax(1,validity_bars);
   }

   int Evaluate(const MSZZSpeedSnapshot &f,const MqlRates &bar,MSZZCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      UpdateAsianLevel(bar);
      double atr=f.atr;
      if(atr<=0.0) return 0;

      MqlDateTime dt; TimeToStruct(bar.time,dt);
      bool eligible_hours=(dt.hour>=MSZZ_SSR_PROD_ASIAN_SESSION_END_HOUR);

      Evaluate1Side(m_long,bar,atr,out,count);
      Evaluate1Side(m_short,bar,atr,out,count);

      if(!eligible_hours || !m_asian_frozen) return count;

      double min_excursion=atr*MSZZ_SSR_PROD_MIN_EXCURSION_ATR;
      if(!m_long.active && bar.low<=m_asian_low-min_excursion)
         Arm(m_long,MSZZ_DIR_LONG,bar.time,m_asian_low,bar.low,"ASIA_LOW|"+IntegerToString(m_anchor_day));
      if(!m_short.active && bar.high>=m_asian_high+min_excursion)
         Arm(m_short,MSZZ_DIR_SHORT,bar.time,m_asian_high,bar.high,"ASIA_HIGH|"+IntegerToString(m_anchor_day));

      return count;
   }
};

#endif
