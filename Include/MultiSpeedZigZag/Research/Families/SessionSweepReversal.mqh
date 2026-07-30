#ifndef __MSZZ_FAMILY_SESSION_SWEEP_REVERSAL_MQH__
#define __MSZZ_FAMILY_SESSION_SWEEP_REVERSAL_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>

// D031 Family 1 -- Session Sweep Reversal. Canonical definition frozen from
// D030_D035_Six_Family_Claude_Handoff.md "Family 1" section. Third D031
// implementation priority per D030_P4_LOSS_MAP.md, independently supported
// by the finding that the Asian session is persistently the weakest of
// P4's three sessions across development/validation/holdout.
//
// Reference-level hierarchy: canonical start only, per the handoff's own
// "Recommended canonical start" -- Asia session high/low swept during
// London or New York. Not combining multiple level types.
//
// Session windows: reuses the EXACT frozen boundaries already established
// in Include/MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh
// CMSZZTradeAnalyticsPolicy::SessionBucket and Tools/D030's own
// session_bucket() -- broker server time, Asian <08:00, London <16:00,
// NewYork else. Not redefined here. Explicitly a simplification, not a
// DST-aware trading-session calendar (same disclosed limitation as that
// policy).
//
// Canonical event (short mirrors a swept Asia high, long mirrors a swept
// Asia low):
//   1. Asia session high/low frozen at the Asian/London boundary (08:00
//      broker time) each calendar day
//   2. during London or New York hours, price trades beyond that frozen
//      level by at least a minimum structural distance
//   3. a later closed bar (within a frozen window) closes back inside the
//      frozen level
//   4. entry only after the reclaiming bar closes -- no intrabar lookahead
//
// Stop: beyond the sweep extreme plus a fixed broker-valid buffer.
// Target: canonical fixed 2R.
//
// Shadow-only: emits into MSZZResearchCandidate only.

#define MSZZ_SSR_MIN_EXCURSION_ATR   0.15
#define MSZZ_SSR_RECLAIM_BUFFER_ATR  0.05
#define MSZZ_SSR_MAX_FAILURE_ATR     0.50   // excursion beyond this suggests acceptance, not a failed sweep -- invalidate
#define MSZZ_SSR_RECLAIM_WINDOW_BARS 6
#define MSZZ_SSR_TARGET_R            2.0
#define MSZZ_SSR_VALIDITY_BARS       3
#define MSZZ_SSR_CANONICAL_VARIANT_ID "SSR-CANON-1"
#define MSZZ_SSR_ASIAN_SESSION_END_HOUR 8   // matches TradeAnalyticsExporter.mqh SessionBucket

enum ENUM_MSZZ_SSR_STATE { MSZZ_SSR_IDLE=0, MSZZ_SSR_SWEPT=1, MSZZ_SSR_TRIGGERED=2, MSZZ_SSR_EXPIRED=3, MSZZ_SSR_INVALIDATED=4 };

struct MSZZSessionSweepSetup
{
   bool                 active;
   ENUM_MSZZ_DIRECTION  direction;
   ENUM_MSZZ_SSR_STATE  state;
   datetime             origin_time;
   datetime             expiry_time;
   double               session_level;      // frozen Asia high/low being swept
   double               sweep_extreme;
   string               origin_id;
   string               sequence_id;
};

class CMSZZFamilySessionSweepReversal
{
private:
   MSZZSessionSweepSetup m_long,m_short;
   int m_period_seconds;
   int m_anchor_day;
   double m_asian_high,m_asian_low;
   bool m_asian_frozen;

   void Reset(MSZZSessionSweepSetup &s) const { ZeroMemory(s); s.state=MSZZ_SSR_IDLE; s.direction=MSZZ_DIR_NONE; }

   // Rolls the Asian-session accumulator forward on every bar; freezes
   // asian_high/asian_low the instant the bar's hour first reaches the
   // London boundary each calendar day (i.e. the level used for the rest
   // of the day is exactly what the Asian session actually printed, never
   // re-widened by later bars).
   void UpdateAsianLevel(const MqlRates &bar)
   {
      MqlDateTime dt; TimeToStruct(bar.time,dt);
      int day_key=dt.year*10000+dt.mon*100+dt.day;
      if(day_key!=m_anchor_day)
      {
         m_anchor_day=day_key; m_asian_frozen=false;
         m_asian_high=bar.high; m_asian_low=bar.low;
      }
      if(dt.hour<MSZZ_SSR_ASIAN_SESSION_END_HOUR && !m_asian_frozen)
      {
         m_asian_high=MathMax(m_asian_high,bar.high);
         m_asian_low=MathMin(m_asian_low,bar.low);
      }
      else m_asian_frozen=true;
   }

   void Arm(MSZZSessionSweepSetup &s,const ENUM_MSZZ_DIRECTION dir,const datetime t,
            const double level,const double excursion,const string origin_id)
   {
      Reset(s); s.active=true; s.direction=dir; s.state=MSZZ_SSR_SWEPT;
      s.origin_time=t; s.expiry_time=t+(datetime)(MSZZ_SSR_RECLAIM_WINDOW_BARS*m_period_seconds);
      s.session_level=level; s.sweep_extreme=excursion; s.origin_id=origin_id;
      s.sequence_id="SSR|"+origin_id+"|"+IntegerToString((long)t);
   }

   void Evaluate1Side(MSZZSessionSweepSetup &s,const MqlRates &bar,const double atr,
                       MSZZResearchCandidate &out[],int &count,const string regime_id,
                       const string session_id,const double point_size)
   {
      if(!s.active) return;
      if(bar.time>s.expiry_time){ s.active=false; s.state=MSZZ_SSR_EXPIRED; return; }

      if(s.direction==MSZZ_DIR_LONG) s.sweep_extreme=MathMin(s.sweep_extreme,bar.low);
      else s.sweep_extreme=MathMax(s.sweep_extreme,bar.high);

      double failure=atr*MSZZ_SSR_MAX_FAILURE_ATR;
      bool acceptance=(s.direction==MSZZ_DIR_LONG ? bar.close<s.session_level-failure
                                                    : bar.close>s.session_level+failure);
      if(acceptance){ s.active=false; s.state=MSZZ_SSR_INVALIDATED; return; }

      double reclaim=atr*MSZZ_SSR_RECLAIM_BUFFER_ATR;
      bool reclaimed=(s.direction==MSZZ_DIR_LONG ? bar.close>s.session_level+reclaim
                                                   : bar.close<s.session_level-reclaim);
      if(!reclaimed) return;

      double stop=(s.direction==MSZZ_DIR_LONG ? s.sweep_extreme-atr*MSZZ_SSR_RECLAIM_BUFFER_ATR
                                                 : s.sweep_extreme+atr*MSZZ_SSR_RECLAIM_BUFFER_ATR);
      string structural_context=StringFormat("asian_high=%.5f;asian_low=%.5f;sweep_extreme=%.5f",
                                              m_asian_high,m_asian_low,s.sweep_extreme);
      CMSZZResearchCandidateFactory::Emit(out,count,MSZZ_RSRCH_STRAT_SESSION_SWEEP_REVERSAL,
         MSZZ_RSRCH_FAMILY_SESSION_SWEEP_REVERSAL,s.direction,bar.time,
         bar.time+(datetime)(MSZZ_SSR_VALIDITY_BARS*m_period_seconds),bar.close,stop,MSZZ_SSR_TARGET_R,
         7.0,"Session Sweep Reversal",s.origin_id,s.sequence_id+"|FINAL",
         "Asia session level swept during London/NewYork, closed-bar reclaim within frozen window",
         MSZZ_SSR_CANONICAL_VARIANT_ID,regime_id,session_id,"ASIA_SESSION_HIGH_LOW",structural_context,
         bar.spread,point_size);
      s.active=false; s.state=MSZZ_SSR_TRIGGERED;
   }

public:
   CMSZZFamilySessionSweepReversal() { m_period_seconds=300; m_anchor_day=-1; m_asian_high=0.0; m_asian_low=0.0; m_asian_frozen=false; Reset(m_long); Reset(m_short); }
   void Configure(const int period_seconds) { m_period_seconds=MathMax(1,period_seconds); }

   int Evaluate(const MSZZSpeedSnapshot &f,const MqlRates &bar,const string regime_id,
                const string session_id,const double point_size,MSZZResearchCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      UpdateAsianLevel(bar);
      double atr=f.atr;
      if(atr<=0.0) return 0;

      MqlDateTime dt; TimeToStruct(bar.time,dt);
      bool eligible_hours=(dt.hour>=MSZZ_SSR_ASIAN_SESSION_END_HOUR); // London/NewYork only -- not the still-forming Asian session itself

      Evaluate1Side(m_long,bar,atr,out,count,regime_id,session_id,point_size);
      Evaluate1Side(m_short,bar,atr,out,count,regime_id,session_id,point_size);

      if(!eligible_hours || !m_asian_frozen) return count;

      double min_excursion=atr*MSZZ_SSR_MIN_EXCURSION_ATR;
      if(!m_long.active && bar.low<=m_asian_low-min_excursion)
         Arm(m_long,MSZZ_DIR_LONG,bar.time,m_asian_low,bar.low,"ASIA_LOW|"+IntegerToString(m_anchor_day));
      if(!m_short.active && bar.high>=m_asian_high+min_excursion)
         Arm(m_short,MSZZ_DIR_SHORT,bar.time,m_asian_high,bar.high,"ASIA_HIGH|"+IntegerToString(m_anchor_day));

      return count;
   }
};

#endif
