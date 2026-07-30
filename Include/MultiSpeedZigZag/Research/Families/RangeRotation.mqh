#ifndef __MSZZ_FAMILY_RANGE_ROTATION_MQH__
#define __MSZZ_FAMILY_RANGE_ROTATION_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>

// D031 Family 6 -- Range Rotation. Canonical definition frozen from
// D030_D035_Six_Family_Claude_Handoff.md "Family 6" section. Lowest D031
// implementation priority per D030_P4_LOSS_MAP.md: MSZZ_PHASE_RANGE never
// fired once across 98,943 D030 census bars, so this family CANNOT depend
// on it and must define its own range.
//
// Independent range detector (self-contained to this file; does NOT read
// regime.market_phase and does NOT alter RegimeClassifier.mqh or any
// global regime state):
//   - a rolling W-bar window of closed-bar highs/lows (causal, no lookahead)
//   - range_high/range_low = window max/min
//   - range_width_atr = (range_high-range_low)/fast ATR, must stay inside
//     a frozen stable band bar-over-bar (too narrow: not tradeable /
//     spread-dominated; too wide: not a genuine range)
//   - range "age" = consecutive bars the width has stayed inside that band
//     (minimum range age gate)
//   - upper/lower touch counts = bars within the window whose high/low
//     came within a frozen ATR tolerance of range_high/range_low
//     (minimum touch count on BOTH sides gate)
//   - low directional efficiency = regime.directional_efficiency (the
//     classifier's own pre-existing continuous feature, read but not
//     altered) below a frozen threshold
//   - lack of an accepted medium-structure breakout = no confirmed medium
//     break on the current bar (a live per-bar gate, not a full-window
//     history scan -- documented simplification, see
//     Docs/MultiSpeedZigZag/D031_SIX_FAMILY_ARCHITECTURE.md limitations)
//
// Hypothesis: in a genuinely balanced market, failed movement near a
// mature range boundary may rotate toward equilibrium.
//
// Canonical event: short after a test/slight excess above range high
// followed by failed acceptance and bearish rejection (long mirrored at
// range low), only while every range-quality gate above holds.
//
// Stop: outside the range boundary and rejection extreme.
// Target: canonical range midpoint (not a fixed R-multiple -- see
// CMSZZResearchCandidateFactory::EmitWithExplicitTarget).
//
// Shadow-only: emits into MSZZResearchCandidate only.

#define MSZZ_RR_WINDOW_BARS              48     // 4 hours on M5 -- round, frozen, not tuned
#define MSZZ_RR_MIN_WIDTH_ATR             1.0
#define MSZZ_RR_MAX_WIDTH_ATR             6.0
#define MSZZ_RR_MIN_AGE_BARS              12
#define MSZZ_RR_TOUCH_TOLERANCE_ATR       0.15
#define MSZZ_RR_MIN_TOUCHES_PER_SIDE       2
#define MSZZ_RR_EFFICIENCY_MAX            0.40
#define MSZZ_RR_MAX_EXCESS_ATR            0.30   // beyond this it's a breakout, not a rotation-qualifying excess
#define MSZZ_RR_RECLAIM_WINDOW_BARS        6
#define MSZZ_RR_STOP_BUFFER_ATR           0.05
#define MSZZ_RR_MIN_TARGET_R              0.5    // reject if midpoint reward-to-risk is inadequate
#define MSZZ_RR_VALIDITY_BARS              3
#define MSZZ_RR_CANONICAL_VARIANT_ID     "RR-CANON-1"

enum ENUM_MSZZ_RR_STATE { MSZZ_RR_IDLE=0, MSZZ_RR_SWEPT=1, MSZZ_RR_TRIGGERED=2, MSZZ_RR_EXPIRED=3, MSZZ_RR_INVALIDATED=4 };

struct MSZZRangeRotationSetup
{
   bool                 active;
   ENUM_MSZZ_DIRECTION  direction;
   ENUM_MSZZ_RR_STATE   state;
   datetime             expiry_time;
   double               range_high_at_arm,range_low_at_arm;
   double               excursion_extreme;
   string               origin_id;
   string               sequence_id;
};

class CMSZZFamilyRangeRotation
{
private:
   double m_window_high[],m_window_low[];
   int m_window_count,m_write_idx;
   int m_stable_bars;
   MSZZRangeRotationSetup m_long,m_short;
   int m_period_seconds;

   void Reset(MSZZRangeRotationSetup &s) const { ZeroMemory(s); s.state=MSZZ_RR_IDLE; s.direction=MSZZ_DIR_NONE; }

   void PushWindow(const double hi,const double lo)
   {
      if(ArraySize(m_window_high)!=MSZZ_RR_WINDOW_BARS)
      { ArrayResize(m_window_high,MSZZ_RR_WINDOW_BARS); ArrayResize(m_window_low,MSZZ_RR_WINDOW_BARS); }
      m_window_high[m_write_idx]=hi; m_window_low[m_write_idx]=lo;
      m_write_idx=(m_write_idx+1)%MSZZ_RR_WINDOW_BARS;
      if(m_window_count<MSZZ_RR_WINDOW_BARS) m_window_count++;
   }

   bool WindowStats(double &range_high,double &range_low,int &upper_touches,int &lower_touches,const double atr) const
   {
      if(m_window_count<MSZZ_RR_WINDOW_BARS) return false; // not enough causal history yet
      range_high=m_window_high[0]; range_low=m_window_low[0];
      for(int i=1;i<MSZZ_RR_WINDOW_BARS;i++){ range_high=MathMax(range_high,m_window_high[i]); range_low=MathMin(range_low,m_window_low[i]); }
      double tol=atr*MSZZ_RR_TOUCH_TOLERANCE_ATR;
      upper_touches=0; lower_touches=0;
      for(int i=0;i<MSZZ_RR_WINDOW_BARS;i++)
      {
         if(m_window_high[i]>=range_high-tol) upper_touches++;
         if(m_window_low[i]<=range_low+tol) lower_touches++;
      }
      return true;
   }

   void Arm(MSZZRangeRotationSetup &s,const ENUM_MSZZ_DIRECTION dir,const datetime t,
            const double range_high,const double range_low,const double excursion,const string origin_id)
   {
      Reset(s); s.active=true; s.direction=dir; s.state=MSZZ_RR_SWEPT;
      s.expiry_time=t+(datetime)(MSZZ_RR_RECLAIM_WINDOW_BARS*m_period_seconds);
      s.range_high_at_arm=range_high; s.range_low_at_arm=range_low; s.excursion_extreme=excursion;
      s.origin_id=origin_id; s.sequence_id="RR|"+origin_id+"|"+IntegerToString((long)t);
   }

   void Evaluate1Side(MSZZRangeRotationSetup &s,const MqlRates &bar,const double atr,
                       MSZZResearchCandidate &out[],int &count,const string regime_id,
                       const string session_id,const double point_size)
   {
      if(!s.active) return;
      if(bar.time>s.expiry_time){ s.active=false; s.state=MSZZ_RR_EXPIRED; return; }

      if(s.direction==MSZZ_DIR_SHORT) s.excursion_extreme=MathMax(s.excursion_extreme,bar.high);
      else s.excursion_extreme=MathMin(s.excursion_extreme,bar.low);

      double boundary=(s.direction==MSZZ_DIR_SHORT ? s.range_high_at_arm : s.range_low_at_arm);
      double acceptance=atr*MSZZ_RR_MAX_EXCESS_ATR*2.0; // wider than the arm-time excess cap -> genuine acceptance, not just a slow reclaim
      bool accepted=(s.direction==MSZZ_DIR_SHORT ? bar.close>boundary+acceptance : bar.close<boundary-acceptance);
      if(accepted){ s.active=false; s.state=MSZZ_RR_INVALIDATED; return; }

      bool reclaimed=(s.direction==MSZZ_DIR_SHORT ? bar.close<boundary : bar.close>boundary);
      if(!reclaimed) return;

      double midpoint=(s.range_high_at_arm+s.range_low_at_arm)/2.0;
      double stop=(s.direction==MSZZ_DIR_SHORT ? s.excursion_extreme+atr*MSZZ_RR_STOP_BUFFER_ATR
                                                  : s.excursion_extreme-atr*MSZZ_RR_STOP_BUFFER_ATR);
      double risk=MathAbs(bar.close-stop);
      if(risk<=0.0) return;
      double target_r=MathAbs(midpoint-bar.close)/risk;
      if(target_r<MSZZ_RR_MIN_TARGET_R) { s.active=false; s.state=MSZZ_RR_INVALIDATED; return; } // "midpoint reward-to-risk is inadequate"

      string ctx=StringFormat("range_high=%.5f;range_low=%.5f;midpoint=%.5f",
                               s.range_high_at_arm,s.range_low_at_arm,midpoint);
      CMSZZResearchCandidateFactory::EmitWithExplicitTarget(out,count,MSZZ_RSRCH_STRAT_RANGE_ROTATION,
         MSZZ_RSRCH_FAMILY_RANGE_ROTATION,s.direction,bar.time,
         bar.time+(datetime)(MSZZ_RR_VALIDITY_BARS*m_period_seconds),bar.close,stop,midpoint,7.0,
         "Range Rotation",s.origin_id,s.sequence_id+"|FINAL",
         "mature two-sided range, failed excess beyond boundary, closed-bar rejection back toward midpoint",
         MSZZ_RR_CANONICAL_VARIANT_ID,regime_id,session_id,"SELF_DETECTED_ROLLING_RANGE",ctx,
         bar.spread,point_size);
      s.active=false; s.state=MSZZ_RR_TRIGGERED;
   }

public:
   CMSZZFamilyRangeRotation() { m_window_count=0; m_write_idx=0; m_stable_bars=0; m_period_seconds=300; Reset(m_long); Reset(m_short); }
   void Configure(const int period_seconds) { m_period_seconds=MathMax(1,period_seconds); }

   int Evaluate(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m,const MSZZSpeedSnapshot &s,
                const MSZZRegimeState &regime,const MqlRates &bar,const string regime_id,
                const string session_id,const double point_size,MSZZResearchCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      double atr=f.atr;
      if(atr<=0.0 || !regime.valid) return 0;

      Evaluate1Side(m_long,bar,atr,out,count,regime_id,session_id,point_size);
      Evaluate1Side(m_short,bar,atr,out,count,regime_id,session_id,point_size);

      // Range stats are computed from the window as accumulated THROUGH THE
      // PRIOR bar, deliberately -- PushWindow() for the current bar happens
      // at the very end of this function. If the current bar's own
      // high/low were already inside range_high/range_low, a genuine
      // breakout bar would trivially satisfy "bar.high>range_high" as
      // false (its own high defines the new range_high), making the
      // rotation entry below unreachable. Excluding the current bar keeps
      // "did THIS bar excurse beyond the ALREADY-ESTABLISHED range" a
      // meaningful, causal question.
      double range_high,range_low; int upper_touches,lower_touches;
      bool have_range=WindowStats(range_high,range_low,upper_touches,lower_touches,atr);
      PushWindow(bar.high,bar.low);
      if(!have_range) return count;

      double width_atr=(range_high-range_low)/atr;
      bool width_stable=(width_atr>=MSZZ_RR_MIN_WIDTH_ATR && width_atr<=MSZZ_RR_MAX_WIDTH_ATR);
      m_stable_bars=(width_stable ? m_stable_bars+1 : 0);

      bool no_accepted_break=(!m.bullish_break && !m.bearish_break);
      bool range_mature=(m_stable_bars>=MSZZ_RR_MIN_AGE_BARS &&
                          upper_touches>=MSZZ_RR_MIN_TOUCHES_PER_SIDE &&
                          lower_touches>=MSZZ_RR_MIN_TOUCHES_PER_SIDE &&
                          regime.directional_efficiency<=MSZZ_RR_EFFICIENCY_MAX &&
                          no_accepted_break);
      if(!range_mature) return count;

      double excess=atr*MSZZ_RR_MAX_EXCESS_ATR;
      if(!m_short.active && bar.high>range_high && bar.high<=range_high+excess)
         Arm(m_short,MSZZ_DIR_SHORT,bar.time,range_high,range_low,bar.high,
             "RR_HIGH|"+TimeToString(bar.time,TIME_DATE|TIME_SECONDS));
      if(!m_long.active && bar.low<range_low && bar.low>=range_low-excess)
         Arm(m_long,MSZZ_DIR_LONG,bar.time,range_high,range_low,bar.low,
             "RR_LOW|"+TimeToString(bar.time,TIME_DATE|TIME_SECONDS));

      return count;
   }
};

#endif
