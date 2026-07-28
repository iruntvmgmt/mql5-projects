#ifndef __MSZZ_REGIME_CLASSIFIER_MQH__
#define __MSZZ_REGIME_CLASSIFIER_MQH__

// D027: Layer 1 regime classifier. Pure, deterministic, no-MT5-API observer
// over the same MSZZSpeedSnapshot data ProcessClosedBar() already computes
// for signal evaluation, plus the same closed-bar rates[] array every
// strategy already relies on. Never places orders, never knows about trade
// profitability, never accesses the forming bar. See DECISION_LOG.md D027
// "Layer 1 -- Regime classifier: exact definitions" for the frozen
// definitions this file implements verbatim -- do not change a boundary or
// formula here without updating that section first (definitions are frozen
// before any strategy or regime-filter result is inspected, per D027's
// anti-overfitting rules).

#include <MultiSpeedZigZag/Core/Types.mqh>

enum ENUM_MSZZ_REGIME_DIRECTION
{
   MSZZ_REGIME_DIR_NEUTRAL = 0,
   MSZZ_REGIME_DIR_BULLISH,
   MSZZ_REGIME_DIR_BEARISH
};

enum ENUM_MSZZ_TREND_STRENGTH
{
   MSZZ_TREND_WEAK = 0,
   MSZZ_TREND_NORMAL,
   MSZZ_TREND_STRONG
};

enum ENUM_MSZZ_VOLATILITY_STATE
{
   MSZZ_VOL_CONTRACTING = 0,
   MSZZ_VOL_NORMAL,
   MSZZ_VOL_EXPANDING
};

enum ENUM_MSZZ_ALIGNMENT_STATE
{
   MSZZ_ALIGN_MIXED = 0,
   MSZZ_ALIGN_PARTIALLY_ALIGNED,
   MSZZ_ALIGN_FULLY_ALIGNED,
   MSZZ_ALIGN_OPPOSED
};

enum ENUM_MSZZ_MARKET_PHASE
{
   MSZZ_PHASE_UNCLASSIFIED = 0,
   MSZZ_PHASE_BREAKOUT,
   MSZZ_PHASE_TREND_CONTINUATION,
   MSZZ_PHASE_PULLBACK,
   MSZZ_PHASE_COMPRESSION,
   MSZZ_PHASE_TRANSITION,
   MSZZ_PHASE_RANGE,
   MSZZ_PHASE_FAILED_BREAK // never emitted in this pass -- see DECISION_LOG.md D027
};

string MSZZRegimeDirectionText(const ENUM_MSZZ_REGIME_DIRECTION d)
{
   switch(d) { case MSZZ_REGIME_DIR_BULLISH: return "BULLISH"; case MSZZ_REGIME_DIR_BEARISH: return "BEARISH"; default: return "NEUTRAL"; }
}
string MSZZTrendStrengthText(const ENUM_MSZZ_TREND_STRENGTH t)
{
   switch(t) { case MSZZ_TREND_WEAK: return "WEAK"; case MSZZ_TREND_STRONG: return "STRONG"; default: return "NORMAL"; }
}
string MSZZVolatilityStateText(const ENUM_MSZZ_VOLATILITY_STATE v)
{
   switch(v) { case MSZZ_VOL_CONTRACTING: return "CONTRACTING"; case MSZZ_VOL_EXPANDING: return "EXPANDING"; default: return "NORMAL"; }
}
string MSZZAlignmentStateText(const ENUM_MSZZ_ALIGNMENT_STATE a)
{
   switch(a)
   {
      case MSZZ_ALIGN_FULLY_ALIGNED: return "FULLY_ALIGNED";
      case MSZZ_ALIGN_PARTIALLY_ALIGNED: return "PARTIALLY_ALIGNED";
      case MSZZ_ALIGN_OPPOSED: return "OPPOSED";
      default: return "MIXED";
   }
}
string MSZZMarketPhaseText(const ENUM_MSZZ_MARKET_PHASE p)
{
   switch(p)
   {
      case MSZZ_PHASE_BREAKOUT: return "BREAKOUT";
      case MSZZ_PHASE_TREND_CONTINUATION: return "TREND_CONTINUATION";
      case MSZZ_PHASE_PULLBACK: return "PULLBACK";
      case MSZZ_PHASE_COMPRESSION: return "COMPRESSION";
      case MSZZ_PHASE_TRANSITION: return "TRANSITION";
      case MSZZ_PHASE_RANGE: return "RANGE";
      case MSZZ_PHASE_FAILED_BREAK: return "FAILED_BREAK";
      default: return "UNCLASSIFIED";
   }
}

struct MSZZRegimeState
{
   datetime                      evaluation_time;

   ENUM_MSZZ_REGIME_DIRECTION    direction;
   ENUM_MSZZ_TREND_STRENGTH      trend_strength;
   ENUM_MSZZ_VOLATILITY_STATE    volatility_state;
   ENUM_MSZZ_ALIGNMENT_STATE     alignment_state;
   ENUM_MSZZ_MARKET_PHASE        market_phase;

   double                        fast_swing_amplitude_r;
   double                        medium_swing_amplitude_r;
   double                        slow_swing_amplitude_r;

   double                        fast_duration_bars;
   double                        medium_duration_bars;
   double                        slow_duration_bars;

   double                        fast_to_medium_amplitude_ratio;
   double                        medium_to_slow_amplitude_ratio;

   double                        normalized_atr;
   double                        directional_efficiency;
   double                        compression_ratio;

   bool                          valid;
   string                        reason;
};

// D027: predeclared, documented, not tuned after seeing any strategy or
// regime-filter result -- see DECISION_LOG.md D027 "Layer 1" for the
// rationale behind each fixed constant below.
#define MSZZ_REGIME_EFFICIENCY_LOOKBACK   20
#define MSZZ_REGIME_ATR_MEDIAN_LOOKBACK   100
#define MSZZ_REGIME_TREND_WEAK_MAX        0.35
#define MSZZ_REGIME_TREND_STRONG_MIN      0.65
#define MSZZ_REGIME_VOL_CONTRACT_MAX      0.80
#define MSZZ_REGIME_VOL_EXPAND_MIN        1.20
#define MSZZ_REGIME_COMPRESSION_RATIO_MAX 0.35

class CMSZZRegimeClassifier
{
private:
   static ENUM_MSZZ_ALIGNMENT_STATE ClassifyAlignment(const ENUM_MSZZ_DIRECTION fast_dir,
                                                        const ENUM_MSZZ_DIRECTION med_dir,
                                                        const ENUM_MSZZ_DIRECTION slow_dir)
   {
      if(fast_dir!=MSZZ_DIR_NONE && fast_dir==med_dir && med_dir==slow_dir)
         return MSZZ_ALIGN_FULLY_ALIGNED;
      if(fast_dir!=MSZZ_DIR_NONE && slow_dir!=MSZZ_DIR_NONE && fast_dir==-slow_dir)
         return MSZZ_ALIGN_OPPOSED;
      bool fm=(fast_dir!=MSZZ_DIR_NONE && fast_dir==med_dir);
      bool ms=(med_dir!=MSZZ_DIR_NONE && med_dir==slow_dir);
      bool fs=(fast_dir!=MSZZ_DIR_NONE && fast_dir==slow_dir);
      if(fm || ms || fs) return MSZZ_ALIGN_PARTIALLY_ALIGNED;
      return MSZZ_ALIGN_MIXED;
   }

   static double SwingAmplitudeR(const MSZZSpeedSnapshot &snap)
   {
      if(!snap.last_high.valid || !snap.last_low.valid || snap.atr<=0.0) return 0.0;
      return MathAbs(snap.last_high.price-snap.last_low.price)/snap.atr;
   }

   static double SwingDurationBars(const MSZZSpeedSnapshot &snap,const int period_seconds)
   {
      if(!snap.last_high.valid || !snap.last_low.valid || period_seconds<=0) return 0.0;
      long diff=(long)MathAbs((double)(snap.last_high.confirmed_time-snap.last_low.confirmed_time));
      return (double)diff/(double)period_seconds;
   }

   // Kaufman-style efficiency ratio over a fixed, predeclared lookback --
   // see DECISION_LOG.md D027. end_index is the index of the last closed
   // bar in a time-ascending rates[] array.
   static double DirectionalEfficiency(const MqlRates &rates[],const int end_index,const int lookback)
   {
      if(lookback<=0 || end_index<lookback) return 0.0;
      int start_index=end_index-lookback;
      double net=MathAbs(rates[end_index].close-rates[start_index].close);
      double path=0.0;
      for(int i=start_index+1;i<=end_index;i++)
         path+=MathAbs(rates[i].close-rates[i-1].close);
      if(path<=0.0) return 0.0;
      return net/path;
   }

   static double SimpleATRSeriesValue(const MqlRates &rates[],const int end_index,const int len)
   {
      if(len<=0 || end_index<len) return 0.0;
      double sum=0.0;
      for(int i=end_index-len+1;i<=end_index;i++)
      {
         double tr1=rates[i].high-rates[i].low;
         double tr2=MathAbs(rates[i].high-rates[i-1].close);
         double tr3=MathAbs(rates[i].low-rates[i-1].close);
         sum+=MathMax(tr1,MathMax(tr2,tr3));
      }
      return sum/len;
   }

   // normalized_atr = ATR(14) / median(ATR(14) over the previous 100 closed
   // bars) -- both computed from the same closed-bar rates[] array, no MT5
   // indicator handle involved, so the classifier stays a pure function of
   // its inputs. Requires at least 14+100 closed bars of history; returns
   // 1.0 (NORMAL) if insufficient, rather than a misleading 0.0.
   static double NormalizedATR(const MqlRates &rates[],const int end_index)
   {
      int atr_len=14;
      if(end_index<atr_len+MSZZ_REGIME_ATR_MEDIAN_LOOKBACK) return 1.0;
      double current=SimpleATRSeriesValue(rates,end_index,atr_len);
      double series[]; ArrayResize(series,MSZZ_REGIME_ATR_MEDIAN_LOOKBACK);
      for(int i=0;i<MSZZ_REGIME_ATR_MEDIAN_LOOKBACK;i++)
         series[i]=SimpleATRSeriesValue(rates,end_index-MSZZ_REGIME_ATR_MEDIAN_LOOKBACK+1+i,atr_len);
      ArraySort(series);
      int n=MSZZ_REGIME_ATR_MEDIAN_LOOKBACK;
      double median=(n%2==1) ? series[n/2] : (series[n/2-1]+series[n/2])/2.0;
      if(median<=0.0) return 1.0;
      return current/median;
   }

   static bool PivotBefore(const MSZZPivot &a,const MSZZPivot &b) { return a.confirmed_time<b.confirmed_time; }

   // Sorts the fast speed's four most recent confirmed pivots (2 highs, 2
   // lows) by confirmed_time ascending and checks for an exact bullish
   // (LL,LH,HL,HH) or bearish (HH,HL,LH,LL) label sequence -- see
   // DECISION_LOG.md D027 "market phase" #5. Requires all four to be valid;
   // returns MSZZ_DIR_NONE if the sequence doesn't match or data is missing.
   static ENUM_MSZZ_DIRECTION DetectTransition(const MSZZSpeedSnapshot &fast)
   {
      if(!fast.last_high.valid || !fast.prior_high.valid || !fast.last_low.valid || !fast.prior_low.valid)
         return MSZZ_DIR_NONE;
      MSZZPivot p[4];
      p[0]=fast.prior_high; p[1]=fast.last_high; p[2]=fast.prior_low; p[3]=fast.last_low;
      // simple insertion sort by confirmed_time -- 4 elements, no need for a library sort
      for(int i=1;i<4;i++)
      {
         MSZZPivot key=p[i]; int j=i-1;
         while(j>=0 && PivotBefore(key,p[j])) { p[j+1]=p[j]; j--; }
         p[j+1]=key;
      }
      ENUM_MSZZ_STRUCTURE_LABEL seq[4];
      for(int i=0;i<4;i++) seq[i]=p[i].structure_label;
      bool bullish=(seq[0]==MSZZ_STRUCT_LL && seq[1]==MSZZ_STRUCT_LH && seq[2]==MSZZ_STRUCT_HL && seq[3]==MSZZ_STRUCT_HH);
      bool bearish=(seq[0]==MSZZ_STRUCT_HH && seq[1]==MSZZ_STRUCT_HL && seq[2]==MSZZ_STRUCT_LH && seq[3]==MSZZ_STRUCT_LL);
      if(bullish) return MSZZ_DIR_LONG;
      if(bearish) return MSZZ_DIR_SHORT;
      return MSZZ_DIR_NONE;
   }

public:
   static bool Evaluate(const MSZZSpeedSnapshot &fast,const MSZZSpeedSnapshot &medium,const MSZZSpeedSnapshot &slow,
                         const MqlRates &rates[],const int closed_count,const int period_seconds,
                         MSZZRegimeState &out_state)
   {
      ZeroMemory(out_state);
      if(closed_count<=0)
      {
         out_state.valid=false; out_state.reason="closed_count<=0";
         return false;
      }
      int end_index=closed_count-1; // last CLOSED bar only -- never the forming bar
      out_state.evaluation_time=rates[end_index].time;

      out_state.direction = (slow.leg_direction==MSZZ_DIR_LONG) ? MSZZ_REGIME_DIR_BULLISH :
                             (slow.leg_direction==MSZZ_DIR_SHORT) ? MSZZ_REGIME_DIR_BEARISH : MSZZ_REGIME_DIR_NEUTRAL;

      out_state.alignment_state=ClassifyAlignment(fast.leg_direction,medium.leg_direction,slow.leg_direction);

      out_state.fast_swing_amplitude_r=SwingAmplitudeR(fast);
      out_state.medium_swing_amplitude_r=SwingAmplitudeR(medium);
      out_state.slow_swing_amplitude_r=SwingAmplitudeR(slow);
      out_state.fast_duration_bars=SwingDurationBars(fast,period_seconds);
      out_state.medium_duration_bars=SwingDurationBars(medium,period_seconds);
      out_state.slow_duration_bars=SwingDurationBars(slow,period_seconds);
      out_state.fast_to_medium_amplitude_ratio=(out_state.medium_swing_amplitude_r>0.0) ?
         out_state.fast_swing_amplitude_r/out_state.medium_swing_amplitude_r : 0.0;
      out_state.medium_to_slow_amplitude_ratio=(out_state.slow_swing_amplitude_r>0.0) ?
         out_state.medium_swing_amplitude_r/out_state.slow_swing_amplitude_r : 0.0;

      out_state.directional_efficiency=DirectionalEfficiency(rates,end_index,MSZZ_REGIME_EFFICIENCY_LOOKBACK);
      out_state.trend_strength = (out_state.directional_efficiency<MSZZ_REGIME_TREND_WEAK_MAX) ? MSZZ_TREND_WEAK :
                                  (out_state.directional_efficiency>MSZZ_REGIME_TREND_STRONG_MIN) ? MSZZ_TREND_STRONG :
                                  MSZZ_TREND_NORMAL;

      out_state.normalized_atr=NormalizedATR(rates,end_index);
      out_state.volatility_state = (out_state.normalized_atr<MSZZ_REGIME_VOL_CONTRACT_MAX) ? MSZZ_VOL_CONTRACTING :
                                    (out_state.normalized_atr>MSZZ_REGIME_VOL_EXPAND_MIN) ? MSZZ_VOL_EXPANDING :
                                    MSZZ_VOL_NORMAL;

      out_state.compression_ratio=out_state.fast_to_medium_amplitude_ratio;

      // market_phase: first match wins, see DECISION_LOG.md D027 for the
      // full documented priority order.
      bool breakout_up = fast.bullish_break && (out_state.alignment_state==MSZZ_ALIGN_FULLY_ALIGNED ||
                          out_state.alignment_state==MSZZ_ALIGN_PARTIALLY_ALIGNED) && slow.leg_direction!=MSZZ_DIR_SHORT;
      bool breakout_down = fast.bearish_break && (out_state.alignment_state==MSZZ_ALIGN_FULLY_ALIGNED ||
                           out_state.alignment_state==MSZZ_ALIGN_PARTIALLY_ALIGNED) && slow.leg_direction!=MSZZ_DIR_LONG;

      bool pullback = (slow.leg_direction!=MSZZ_DIR_NONE) && (medium.leg_direction==slow.leg_direction) &&
                      (fast.leg_direction!=MSZZ_DIR_NONE) && (fast.leg_direction==-slow.leg_direction);

      // Compression additionally requires the fast amplitude to not be
      // expanding versus its own immediately preceding confirmed swing.
      // MSZZSpeedSnapshot only exposes the current (last) and one-back
      // (prior) pivot per side, not a full amplitude history, so this is
      // approximated causally via prior_high/prior_low: the amplitude
      // implied by (prior_high, prior_low) versus (last_high, last_low).
      double prior_amp_r=0.0;
      if(fast.prior_high.valid && fast.prior_low.valid && fast.atr>0.0)
         prior_amp_r=MathAbs(fast.prior_high.price-fast.prior_low.price)/fast.atr;
      bool fast_amp_shrinking=(prior_amp_r<=0.0) ? true : (out_state.fast_swing_amplitude_r<=prior_amp_r);

      bool compression = (out_state.compression_ratio>0.0 && out_state.compression_ratio<MSZZ_REGIME_COMPRESSION_RATIO_MAX) &&
                          (out_state.volatility_state!=MSZZ_VOL_EXPANDING) && fast_amp_shrinking;

      ENUM_MSZZ_DIRECTION transition_dir=DetectTransition(fast);
      bool transition = (transition_dir!=MSZZ_DIR_NONE) && (medium.leg_direction==transition_dir);

      bool range_state = (out_state.alignment_state==MSZZ_ALIGN_MIXED) && (out_state.volatility_state!=MSZZ_VOL_EXPANDING);

      if(breakout_up || breakout_down) out_state.market_phase=MSZZ_PHASE_BREAKOUT;
      else if(out_state.alignment_state==MSZZ_ALIGN_FULLY_ALIGNED &&
              (out_state.volatility_state==MSZZ_VOL_NORMAL || out_state.volatility_state==MSZZ_VOL_EXPANDING))
         out_state.market_phase=MSZZ_PHASE_TREND_CONTINUATION;
      else if(pullback) out_state.market_phase=MSZZ_PHASE_PULLBACK;
      else if(compression) out_state.market_phase=MSZZ_PHASE_COMPRESSION;
      else if(transition) out_state.market_phase=MSZZ_PHASE_TRANSITION;
      else if(range_state) out_state.market_phase=MSZZ_PHASE_RANGE;
      else out_state.market_phase=MSZZ_PHASE_UNCLASSIFIED;

      out_state.valid=true;
      out_state.reason="";
      return true;
   }
};

#endif
