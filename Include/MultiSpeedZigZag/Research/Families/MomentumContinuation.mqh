#ifndef __MSZZ_FAMILY_MOMENTUM_CONTINUATION_MQH__
#define __MSZZ_FAMILY_MOMENTUM_CONTINUATION_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>

// D031 Family 2 -- Momentum Continuation. Canonical definition frozen from
// D030_D035_Six_Family_Claude_Handoff.md "Family 2" section, hypothesis
// version MSZZ_RSRCH_HYPOTHESIS_VERSION. Highest D031 implementation
// priority per D030_P4_LOSS_MAP.md: targets P4's largest, most stable loss
// cluster (market_phase=TREND_CONTINUATION / alignment_state=FULLY_ALIGNED,
// negative in development, validation, AND holdout).
//
// Hypothesis: a genuine directional displacement followed by controlled
// consolidation or shallow retracement may continue because directional
// acceptance remains intact and countertrend pressure is weak.
//
// Canonical event (long, short mirrored):
//   1. confirmed break of recent fast structure (f.bullish_break)
//   2. impulse range >= frozen ATR multiple (regime.fast_swing_amplitude_r,
//      the classifier's own amplitude/ATR ratio -- not re-derived here)
//   3. directional efficiency above a broad frozen threshold
//   4. fast and medium structure aligned in the same direction
//   5. price pauses/retraces shallowly (bounded fraction of the impulse,
//      1..N bars, no opposite confirmed structure break)
//   6. continuation trigger: a later bar's close exceeds the highest high
//      (long) / lowest low (short) reached during the pause so far
//
// Stop: beyond the pullback structure (the pause extreme, plus a small
// broker-valid ATR buffer). Target: canonical fixed 2R.
//
// Shadow-only: emits into MSZZResearchCandidate only. No order placement,
// no position mutation, no broker calls, no portfolio allocation.

#define MSZZ_MC_IMPULSE_ATR_MIN        1.5    // broad, frozen before any screening -- not tuned on D030 results
#define MSZZ_MC_EFFICIENCY_MIN         0.55
#define MSZZ_MC_PAUSE_MAX_BARS         6
#define MSZZ_MC_PULLBACK_MAX_FRACTION  0.50
#define MSZZ_MC_STOP_BUFFER_ATR        0.05
#define MSZZ_MC_TARGET_R               2.0
#define MSZZ_MC_VALIDITY_BARS          3
#define MSZZ_MC_CANONICAL_VARIANT_ID   "MC-CANON-1"

enum ENUM_MSZZ_MC_STATE { MSZZ_MC_IDLE=0, MSZZ_MC_PAUSE_ARMED=1, MSZZ_MC_TRIGGERED=2, MSZZ_MC_EXPIRED=3, MSZZ_MC_INVALIDATED=4 };

struct MSZZMomentumSetup
{
   bool                 active;
   ENUM_MSZZ_DIRECTION  direction;
   ENUM_MSZZ_MC_STATE   state;
   datetime             origin_time;
   datetime             expiry_time;
   double               impulse_origin_price;  // pre-impulse pivot (long: last_low: short: last_high)
   double               impulse_extreme_price;  // fresh break level (long: last_high; short: last_low)
   double               pause_high;
   double               pause_low;
   int                  pause_bars;
   string               origin_id;
   string               sequence_id;
};

class CMSZZFamilyMomentumContinuation
{
private:
   MSZZMomentumSetup m_long,m_short;
   int m_period_seconds;

   void Reset(MSZZMomentumSetup &s) const { ZeroMemory(s); s.state=MSZZ_MC_IDLE; s.direction=MSZZ_DIR_NONE; }

   void Arm(MSZZMomentumSetup &s,const ENUM_MSZZ_DIRECTION dir,const datetime t,
            const double origin_price,const double extreme_price,const string origin_id)
   {
      Reset(s); s.active=true; s.direction=dir; s.state=MSZZ_MC_PAUSE_ARMED;
      s.origin_time=t; s.expiry_time=t+(datetime)(MSZZ_MC_PAUSE_MAX_BARS*m_period_seconds);
      s.impulse_origin_price=origin_price; s.impulse_extreme_price=extreme_price;
      s.pause_high=extreme_price; s.pause_low=extreme_price; s.pause_bars=0;
      s.origin_id=origin_id; s.sequence_id="MC|"+origin_id+"|"+IntegerToString((long)t);
   }

   double RetracementFraction(const MSZZMomentumSetup &s) const
   {
      double range=MathAbs(s.impulse_extreme_price-s.impulse_origin_price);
      if(range<=0.0) return 1.0;
      if(s.direction==MSZZ_DIR_LONG) return (s.impulse_extreme_price-s.pause_low)/range;
      return (s.pause_high-s.impulse_extreme_price)/range;
   }

   void Evaluate1Side(MSZZMomentumSetup &s,const MqlRates &bar,const double atr,
                       const bool opposite_break,MSZZResearchCandidate &out[],int &count,
                       const string regime_id,const string session_id,const string structural_context,
                       const double point_size)
   {
      if(!s.active) return;
      if(bar.time>s.expiry_time){ s.active=false; s.state=MSZZ_MC_EXPIRED; return; }
      if(opposite_break){ s.active=false; s.state=MSZZ_MC_INVALIDATED; return; }

      double prior_pause_high=s.pause_high, prior_pause_low=s.pause_low;
      s.pause_high=MathMax(s.pause_high,bar.high); s.pause_low=MathMin(s.pause_low,bar.low);
      s.pause_bars++;

      if(RetracementFraction(s)>MSZZ_MC_PULLBACK_MAX_FRACTION){ s.active=false; s.state=MSZZ_MC_INVALIDATED; return; }
      if(s.pause_bars<1) return;

      bool trigger=(s.direction==MSZZ_DIR_LONG ? bar.close>prior_pause_high : bar.close<prior_pause_low);
      if(!trigger) return;

      double stop=(s.direction==MSZZ_DIR_LONG ? s.pause_low-atr*MSZZ_MC_STOP_BUFFER_ATR
                                                : s.pause_high+atr*MSZZ_MC_STOP_BUFFER_ATR);
      CMSZZResearchCandidateFactory::Emit(out,count,MSZZ_RSRCH_STRAT_MOMENTUM_CONTINUATION,
         MSZZ_RSRCH_FAMILY_MOMENTUM_CONTINUATION,s.direction,bar.time,
         bar.time+(datetime)(MSZZ_MC_VALIDITY_BARS*m_period_seconds),bar.close,stop,MSZZ_MC_TARGET_R,
         7.0,"Momentum Continuation",s.origin_id,s.sequence_id+"|FINAL",
         "displacement + shallow pause + close beyond pause extreme, fast/medium aligned, efficiency confirmed",
         MSZZ_MC_CANONICAL_VARIANT_ID,regime_id,session_id,"FAST_STRUCTURE_IMPULSE",structural_context,
         bar.spread,point_size);
      s.active=false; s.state=MSZZ_MC_TRIGGERED;
   }

public:
   CMSZZFamilyMomentumContinuation() { m_period_seconds=300; Reset(m_long); Reset(m_short); }
   void Configure(const int period_seconds) { m_period_seconds=MathMax(1,period_seconds); }

   // Called once per closed bar. fast/med/slow snapshots and regime are the
   // same objects ProcessClosedBar() already computes -- no new engine
   // state, no lookahead (only the current closed bar and already-closed
   // pivots are read).
   int Evaluate(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m,const MSZZSpeedSnapshot &s,
                const MSZZRegimeState &regime,const MqlRates &bar,const string regime_id,
                const string session_id,const double point_size,MSZZResearchCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      double atr=f.atr;
      if(atr<=0.0 || !regime.valid) return 0;
      string structural_context=StringFormat("efficiency=%.3f;fast_amp_r=%.3f",
                                              regime.directional_efficiency,regime.fast_swing_amplitude_r);

      // Process previously armed pauses before arming a new one this bar,
      // so the impulse bar itself can never also be counted as its own
      // pause/trigger (same ordering discipline as D027StrategyFamilies.mqh).
      Evaluate1Side(m_long,bar,atr,f.bearish_break,out,count,regime_id,session_id,structural_context,point_size);
      Evaluate1Side(m_short,bar,atr,f.bullish_break,out,count,regime_id,session_id,structural_context,point_size);

      bool efficiency_ok=regime.directional_efficiency>=MSZZ_MC_EFFICIENCY_MIN;
      bool impulse_ok=regime.fast_swing_amplitude_r>=MSZZ_MC_IMPULSE_ATR_MIN;

      if(!m_long.active && f.bullish_break && efficiency_ok && impulse_ok &&
         f.leg_direction==MSZZ_DIR_LONG && m.leg_direction==MSZZ_DIR_LONG &&
         f.last_low.valid && f.last_high.valid)
         Arm(m_long,MSZZ_DIR_LONG,bar.time,f.last_low.price,f.last_high.price,f.bullish_event_id);

      if(!m_short.active && f.bearish_break && efficiency_ok && impulse_ok &&
         f.leg_direction==MSZZ_DIR_SHORT && m.leg_direction==MSZZ_DIR_SHORT &&
         f.last_low.valid && f.last_high.valid)
         Arm(m_short,MSZZ_DIR_SHORT,bar.time,f.last_high.price,f.last_low.price,f.bearish_event_id);

      return count;
   }
};

#endif
