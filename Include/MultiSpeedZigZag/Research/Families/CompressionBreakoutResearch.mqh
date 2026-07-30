#ifndef __MSZZ_FAMILY_COMPRESSION_BREAKOUT_RESEARCH_MQH__
#define __MSZZ_FAMILY_COMPRESSION_BREAKOUT_RESEARCH_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>

// D031 Family 4 -- Compression Breakout (Research). Canonical definition
// frozen from D030_D035_Six_Family_Claude_Handoff.md "Family 4" section.
// Fifth D031 implementation priority per D030_P4_LOSS_MAP.md.
//
// AUDIT NOTE (handoff Family 4: "Audit any existing CompressionBreakout
// code before reuse. Do not assume prior implementation is correct or
// complete"): the existing production strategy 1060 (D027 S4,
// Strategies/D027StrategyFamilies.mqh) arms on three consecutive closed
// bars where the discrete regime classifier already labeled
// market_phase==MSZZ_PHASE_COMPRESSION, then waits up to six bars for a
// close beyond the frozen fast support/resistance boundary. It is
// implemented, correct for its own frozen definition, and default-disabled
// -- there is no defect to fix. This Family 4 research strategy is
// DELIBERATELY a different implementation, not a copy or a wrapper:
//   - it never reads regime.market_phase / MSZZ_PHASE_COMPRESSION at all;
//   - compression is measured directly from regime.normalized_atr (the
//     classifier's own continuous short/long ATR ratio, read before it is
//     bucketed into a VOLATILITY_STATE label) plus a self-tracked rolling
//     N-bar range width, exactly the two raw features the handoff's
//     "Recommended canonical definition" asks for;
//   - it uses its own strategy_id (1201->1203 per Tools/D031/id_allocation.csv)
//     and family_id, disjoint from the production enum entirely (see
//     ResearchCandidateTypes.mqh).
// Distinct type, strategy ID, and implementation identity, as required.
//
// Hypothesis: volatility contraction can precede expansion. When price
// compresses while maintaining structural coherence, a confirmed breakout
// may produce follow-through.
//
// Canonical event (long, short mirrored):
//   1. regime.normalized_atr (short/long ATR ratio) below a frozen
//      threshold
//   2. a rolling N-bar range width, normalized by fast ATR, below a frozen
//      threshold
//   3. both conditions persist for a minimum compression duration (bars)
//   4. medium-structure-aligned confirmed close beyond the compression
//      range boundary, with a minimum breakout distance
//
// Stop: opposite side of the compression range. Target: canonical fixed 2R.
//
// Shadow-only: emits into MSZZResearchCandidate only.

#define MSZZ_CBR_WINDOW_BARS            12
#define MSZZ_CBR_ATR_RATIO_MAX          0.80   // reuses RegimeClassifier's own MSZZ_REGIME_VOL_CONTRACT_MAX threshold -- not re-tuned
#define MSZZ_CBR_RANGE_WIDTH_ATR_MAX    2.50
#define MSZZ_CBR_MIN_DURATION_BARS       3
#define MSZZ_CBR_MAX_ARMED_WAIT_BARS     8
#define MSZZ_CBR_MIN_BREAKOUT_DISTANCE_ATR 0.10
#define MSZZ_CBR_TARGET_R                2.0
#define MSZZ_CBR_VALIDITY_BARS           3
#define MSZZ_CBR_CANONICAL_VARIANT_ID   "CBR-CANON-1"

enum ENUM_MSZZ_CBR_STATE { MSZZ_CBR_IDLE=0, MSZZ_CBR_ARMED=1, MSZZ_CBR_TRIGGERED=2, MSZZ_CBR_INVALIDATED=3 };

class CMSZZFamilyCompressionBreakoutResearch
{
private:
   double m_window_high[],m_window_low[];
   int m_window_count,m_write_idx;
   int m_compression_bars;
   ENUM_MSZZ_CBR_STATE m_state;
   double m_compression_high,m_compression_low;
   datetime m_arm_time,m_expiry_time;
   string m_origin_id,m_sequence_id;
   int m_period_seconds;

   void PushWindow(const double hi,const double lo)
   {
      if(ArraySize(m_window_high)!=MSZZ_CBR_WINDOW_BARS)
      { ArrayResize(m_window_high,MSZZ_CBR_WINDOW_BARS); ArrayResize(m_window_low,MSZZ_CBR_WINDOW_BARS); }
      m_window_high[m_write_idx]=hi; m_window_low[m_write_idx]=lo;
      m_write_idx=(m_write_idx+1)%MSZZ_CBR_WINDOW_BARS;
      if(m_window_count<MSZZ_CBR_WINDOW_BARS) m_window_count++;
   }

   // Window not warmed up yet (fewer than MSZZ_CBR_WINDOW_BARS closed bars
   // seen since start): report an arbitrarily large width so "compressing"
   // is always false until there is enough causal history -- avoids any
   // reliance on a DBL_MAX-style sentinel, which nothing else in this
   // codebase uses.
   double WindowRangeWidth() const
   {
      if(m_window_count<MSZZ_CBR_WINDOW_BARS) return m_window_high[0]-m_window_low[0]+1.0e12;
      double hi=m_window_high[0],lo=m_window_low[0];
      for(int i=1;i<MSZZ_CBR_WINDOW_BARS;i++){ hi=MathMax(hi,m_window_high[i]); lo=MathMin(lo,m_window_low[i]); }
      return hi-lo;
   }

   double WindowHigh() const { double hi=m_window_high[0]; for(int i=1;i<m_window_count;i++) hi=MathMax(hi,m_window_high[i]); return hi; }
   double WindowLow() const  { double lo=m_window_low[0];  for(int i=1;i<m_window_count;i++) lo=MathMin(lo,m_window_low[i]);  return lo; }

public:
   CMSZZFamilyCompressionBreakoutResearch()
   {
      m_window_count=0; m_write_idx=0; m_compression_bars=0; m_state=MSZZ_CBR_IDLE;
      m_compression_high=0.0; m_compression_low=0.0; m_period_seconds=300;
   }
   void Configure(const int period_seconds) { m_period_seconds=MathMax(1,period_seconds); }

   int Evaluate(const MSZZSpeedSnapshot &f,const MSZZSpeedSnapshot &m,const MSZZSpeedSnapshot &s,
                const MSZZRegimeState &regime,const MqlRates &bar,const string regime_id,
                const string session_id,const double point_size,MSZZResearchCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      double atr=f.atr;
      PushWindow(bar.high,bar.low);
      if(atr<=0.0 || !regime.valid) return 0;

      double range_width_atr=WindowRangeWidth()/atr;
      bool compressing=(regime.normalized_atr<=MSZZ_CBR_ATR_RATIO_MAX && range_width_atr<=MSZZ_CBR_RANGE_WIDTH_ATR_MAX);

      if(m_state==MSZZ_CBR_ARMED)
      {
         if(bar.time>m_expiry_time){ m_state=MSZZ_CBR_INVALIDATED; m_compression_bars=0; return 0; }
         double min_dist=atr*MSZZ_CBR_MIN_BREAKOUT_DISTANCE_ATR;
         bool bull_ctx=(m.leg_direction==MSZZ_DIR_LONG || s.leg_direction==MSZZ_DIR_LONG);
         bool bear_ctx=(m.leg_direction==MSZZ_DIR_SHORT || s.leg_direction==MSZZ_DIR_SHORT);
         if(bar.close>=m_compression_high+min_dist && bull_ctx)
         {
            string ctx=StringFormat("compression_high=%.5f|compression_low=%.5f|atr_ratio=%.3f",
                                     m_compression_high,m_compression_low,regime.normalized_atr);
            CMSZZResearchCandidateFactory::Emit(out,count,MSZZ_RSRCH_STRAT_COMPRESSION_BREAKOUT,
               MSZZ_RSRCH_FAMILY_COMPRESSION_BREAKOUT,MSZZ_DIR_LONG,bar.time,
               bar.time+(datetime)(MSZZ_CBR_VALIDITY_BARS*m_period_seconds),bar.close,m_compression_low,
               MSZZ_CBR_TARGET_R,7.0,"Compression Breakout (Research)",m_origin_id,m_sequence_id+"|FINAL",
               "rolling-window compression (raw ATR ratio + range width) resolved by medium/slow-aligned bullish close",
               MSZZ_CBR_CANONICAL_VARIANT_ID,regime_id,session_id,"ROLLING_WINDOW_RANGE",ctx,bar.spread,point_size);
            m_state=MSZZ_CBR_TRIGGERED; m_compression_bars=0; return count;
         }
         if(bar.close<=m_compression_low-min_dist && bear_ctx)
         {
            string ctx=StringFormat("compression_high=%.5f|compression_low=%.5f|atr_ratio=%.3f",
                                     m_compression_high,m_compression_low,regime.normalized_atr);
            CMSZZResearchCandidateFactory::Emit(out,count,MSZZ_RSRCH_STRAT_COMPRESSION_BREAKOUT,
               MSZZ_RSRCH_FAMILY_COMPRESSION_BREAKOUT,MSZZ_DIR_SHORT,bar.time,
               bar.time+(datetime)(MSZZ_CBR_VALIDITY_BARS*m_period_seconds),bar.close,m_compression_high,
               MSZZ_CBR_TARGET_R,7.0,"Compression Breakout (Research)",m_origin_id,m_sequence_id+"|FINAL",
               "rolling-window compression (raw ATR ratio + range width) resolved by medium/slow-aligned bearish close",
               MSZZ_CBR_CANONICAL_VARIANT_ID,regime_id,session_id,"ROLLING_WINDOW_RANGE",ctx,bar.spread,point_size);
            m_state=MSZZ_CBR_TRIGGERED; m_compression_bars=0; return count;
         }
         return 0;
      }

      if(compressing)
      {
         m_compression_bars++;
         if(m_state==MSZZ_CBR_IDLE && m_compression_bars>=MSZZ_CBR_MIN_DURATION_BARS)
         {
            m_state=MSZZ_CBR_ARMED; m_arm_time=bar.time;
            m_expiry_time=bar.time+(datetime)(MSZZ_CBR_MAX_ARMED_WAIT_BARS*m_period_seconds);
            m_compression_high=WindowHigh(); m_compression_low=WindowLow();
            m_origin_id="CBR|"+TimeToString(bar.time,TIME_DATE|TIME_SECONDS);
            m_sequence_id=m_origin_id+"|"+IntegerToString((long)bar.time);
         }
      }
      else { m_compression_bars=0; if(m_state!=MSZZ_CBR_ARMED) m_state=MSZZ_CBR_IDLE; }

      return count;
   }
};

#endif
