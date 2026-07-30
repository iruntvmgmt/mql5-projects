#ifndef __MSZZ_FAMILY_TREND_PULLBACK_MQH__
#define __MSZZ_FAMILY_TREND_PULLBACK_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>

// D031 Family 5 -- Trend Pullback. Canonical definition frozen from
// D030_D035_Six_Family_Claude_Handoff.md "Family 5" section. Second D031
// implementation priority per D030_P4_LOSS_MAP.md: targets the same
// TREND_CONTINUATION/FULLY_ALIGNED gap as Momentum Continuation, but from a
// slower, value-location-driven angle rather than a fresh-impulse-and-pause
// trigger -- deliberately NOT gated on f.bullish_break/f.bearish_break, so
// it is structurally distinct from Momentum Continuation (D031's own
// overlap test in D032 must still confirm this empirically).
//
// Hypothesis: in an established trend, a controlled retracement into
// structural value may offer better reward-to-risk than chasing the
// impulse.
//
// Value reference: session/day-anchored VWAP (tick_volume-weighted, reset
// at each broker calendar-day boundary). The handoff requires choosing
// exactly one of ALMA or VWAP before testing; VWAP is chosen here as the
// simpler, unambiguous, non-parametric choice (no window-length or
// weighting-curve parameter to freeze/tune) -- not stacked with ALMA/VWMA/
// Kalman/oscillators.
//
// Canonical event (long, short mirrored):
//   1. fast and medium swing alignment in the trend direction
//   2. directional efficiency above a broad frozen threshold
//   3. price on the correct side of VWAP
//   4. a confirmed countertrend micro-pivot (fast HL in an uptrend / LH in
//      a downtrend) marks the pullback low/high, i.e. medium structure has
//      not broken
//   5. pullback remains within a broad frozen fraction of the pre-pullback
//      distance from value
//   6. resumption: a later bar's close breaks back through the pullback's
//      own developing micro-structure (chosen over "fast structure turns
//      back with trend" per the handoff's "choose one")
//
// Stop: beyond the pullback extreme. Target: canonical fixed 2R.
//
// Shadow-only: emits into MSZZResearchCandidate only.

#define MSZZ_TP_EFFICIENCY_MIN         0.50
#define MSZZ_TP_PULLBACK_MAX_FRACTION  0.50
#define MSZZ_TP_MAX_PAUSE_BARS         10
#define MSZZ_TP_STOP_BUFFER_ATR        0.05
#define MSZZ_TP_TARGET_R               2.0
#define MSZZ_TP_VALIDITY_BARS          3
#define MSZZ_TP_CANONICAL_VARIANT_ID   "TP-CANON-1"

enum ENUM_MSZZ_TP_STATE { MSZZ_TP_IDLE=0, MSZZ_TP_PULLBACK_ARMED=1, MSZZ_TP_TRIGGERED=2, MSZZ_TP_EXPIRED=3, MSZZ_TP_INVALIDATED=4 };

struct MSZZTrendPullbackSetup
{
   bool                 active;
   ENUM_MSZZ_DIRECTION  direction;
   ENUM_MSZZ_TP_STATE   state;
   datetime             origin_time;
   datetime             expiry_time;
   double               value_at_arm;       // VWAP snapshot when armed
   double               pre_pullback_extreme; // the trend leg's extreme before this pullback
   double               pause_high;
   double               pause_low;
   int                  pause_bars;
   string               origin_id;
   string               sequence_id;
};

class CMSZZFamilyTrendPullback
{
private:
   MSZZTrendPullbackSetup m_long,m_short;
   int m_period_seconds;
   double m_cum_pv,m_cum_v,m_vwap;
   int m_anchor_day;

   void Reset(MSZZTrendPullbackSetup &s) const { ZeroMemory(s); s.state=MSZZ_TP_IDLE; s.direction=MSZZ_DIR_NONE; }

   void UpdateVWAP(const MqlRates &bar)
   {
      MqlDateTime dt; TimeToStruct(bar.time,dt);
      int day_key=dt.year*10000+dt.mon*100+dt.day;
      if(day_key!=m_anchor_day) { m_cum_pv=0.0; m_cum_v=0.0; m_anchor_day=day_key; }
      double typical=(bar.high+bar.low+bar.close)/3.0;
      double vol=(bar.tick_volume>0 ? (double)bar.tick_volume : 1.0);
      m_cum_pv+=typical*vol; m_cum_v+=vol;
      m_vwap=(m_cum_v>0.0 ? m_cum_pv/m_cum_v : typical);
   }

   void Arm(MSZZTrendPullbackSetup &s,const ENUM_MSZZ_DIRECTION dir,const datetime t,
            const double extreme_price,const string origin_id)
   {
      Reset(s); s.active=true; s.direction=dir; s.state=MSZZ_TP_PULLBACK_ARMED;
      s.origin_time=t; s.expiry_time=t+(datetime)(MSZZ_TP_MAX_PAUSE_BARS*m_period_seconds);
      s.value_at_arm=m_vwap; s.pre_pullback_extreme=extreme_price;
      s.pause_high=extreme_price; s.pause_low=extreme_price; s.pause_bars=0;
      s.origin_id=origin_id; s.sequence_id="TP|"+origin_id+"|"+IntegerToString((long)t);
   }

   double PullbackDepthFraction(const MSZZTrendPullbackSetup &s) const
   {
      double range=MathAbs(s.pre_pullback_extreme-s.value_at_arm);
      if(range<=0.0) return 1.0;
      if(s.direction==MSZZ_DIR_LONG) return (s.pre_pullback_extreme-s.pause_low)/range;
      return (s.pause_high-s.pre_pullback_extreme)/range;
   }

   void Evaluate1Side(MSZZTrendPullbackSetup &s,const MqlRates &bar,const double atr,
                       const bool opposite_medium_break,MSZZResearchCandidate &out[],int &count,
                       const string regime_id,const string session_id,const double point_size)
   {
      if(!s.active) return;
      if(bar.time>s.expiry_time){ s.active=false; s.state=MSZZ_TP_EXPIRED; return; }
      if(opposite_medium_break){ s.active=false; s.state=MSZZ_TP_INVALIDATED; return; }

      double prior_pause_high=s.pause_high, prior_pause_low=s.pause_low;
      s.pause_high=MathMax(s.pause_high,bar.high); s.pause_low=MathMin(s.pause_low,bar.low);
      s.pause_bars++;

      if(PullbackDepthFraction(s)>MSZZ_TP_PULLBACK_MAX_FRACTION){ s.active=false; s.state=MSZZ_TP_INVALIDATED; return; }
      if(s.pause_bars<1) return;

      bool trigger=(s.direction==MSZZ_DIR_LONG ? bar.close>prior_pause_high : bar.close<prior_pause_low);
      if(!trigger) return;

      double stop=(s.direction==MSZZ_DIR_LONG ? s.pause_low-atr*MSZZ_TP_STOP_BUFFER_ATR
                                                : s.pause_high+atr*MSZZ_TP_STOP_BUFFER_ATR);
      string structural_context=StringFormat("value_at_arm=%.5f;pullback_depth_frac=%.3f",
                                              s.value_at_arm,PullbackDepthFraction(s));
      CMSZZResearchCandidateFactory::Emit(out,count,MSZZ_RSRCH_STRAT_TREND_PULLBACK,
         MSZZ_RSRCH_FAMILY_TREND_PULLBACK,s.direction,bar.time,
         bar.time+(datetime)(MSZZ_TP_VALIDITY_BARS*m_period_seconds),bar.close,stop,MSZZ_TP_TARGET_R,
         7.0,"Trend Pullback",s.origin_id,s.sequence_id+"|FINAL",
         "established trend, correct side of VWAP, bounded pullback, close through pullback micro-structure",
         MSZZ_TP_CANONICAL_VARIANT_ID,regime_id,session_id,"SESSION_VWAP",structural_context,
         bar.spread,point_size);
      s.active=false; s.state=MSZZ_TP_TRIGGERED;
   }

public:
   CMSZZFamilyTrendPullback() { m_period_seconds=300; m_cum_pv=0.0; m_cum_v=0.0; m_vwap=0.0; m_anchor_day=-1; Reset(m_long); Reset(m_short); }
   void Configure(const int period_seconds) { m_period_seconds=MathMax(1,period_seconds); }
   double CurrentVWAP() const { return m_vwap; }

   int Evaluate(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m,const MSZZSpeedSnapshot &s,
                const MSZZRegimeState &regime,const MqlRates &bar,const string regime_id,
                const string session_id,const double point_size,MSZZResearchCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      UpdateVWAP(bar);
      double atr=f.atr;
      if(atr<=0.0 || !regime.valid) return 0;

      Evaluate1Side(m_long,bar,atr,m.bearish_break,out,count,regime_id,session_id,point_size);
      Evaluate1Side(m_short,bar,atr,m.bullish_break,out,count,regime_id,session_id,point_size);

      bool efficiency_ok=regime.directional_efficiency>=MSZZ_TP_EFFICIENCY_MIN;

      bool trend_long=(f.leg_direction==MSZZ_DIR_LONG && m.leg_direction==MSZZ_DIR_LONG && efficiency_ok);
      bool value_long=(bar.close>m_vwap);
      if(!m_long.active && trend_long && value_long && f.last_low.valid &&
         f.last_low.structure_label==MSZZ_STRUCT_HL && f.last_high.valid)
         Arm(m_long,MSZZ_DIR_LONG,bar.time,f.last_high.price,f.last_low.id);

      bool trend_short=(f.leg_direction==MSZZ_DIR_SHORT && m.leg_direction==MSZZ_DIR_SHORT && efficiency_ok);
      bool value_short=(bar.close<m_vwap);
      if(!m_short.active && trend_short && value_short && f.last_high.valid &&
         f.last_high.structure_label==MSZZ_STRUCT_LH && f.last_low.valid)
         Arm(m_short,MSZZ_DIR_SHORT,bar.time,f.last_low.price,f.last_high.id);

      return count;
   }
};

#endif
