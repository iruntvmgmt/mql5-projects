#ifndef __MSZZ_FAMILY_BREAK_RETEST_CONTINUATION_MQH__
#define __MSZZ_FAMILY_BREAK_RETEST_CONTINUATION_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>

// D031 Family 3 -- Break-Retest Continuation. Canonical definition frozen
// from D030_D035_Six_Family_Claude_Handoff.md "Family 3" section. Fourth
// D031 implementation priority per D030_P4_LOSS_MAP.md (supported by the
// thin-but-real BREAKOUT-phase finding).
//
// Deliberately uses the MEDIUM-speed structural level (the handoff's
// "Recommended canonical level: confirmed medium swing high/low"), not
// fast -- this is a distinct implementation from the existing production
// 1040 Breakout Retest (D027 S2, which uses fast projected-line breaks).
// D032's overlap test must still check for redundancy against 1040.
//
// Hypothesis: when price breaks a meaningful structural level, returns to
// test it, and rejects the return path, the retest may confirm acceptance
// on the new side.
//
// Canonical event (long, short mirrored):
//   1. confirmed close beyond medium structural resistance/support, with a
//      minimum close distance and a body/range filter (rejects marginal
//      one-tick breaks)
//   2. price returns toward the broken level within a frozen retest
//      window (minimum and maximum bars after break)
//   3. retest does not close materially back through the level (frozen
//      maximum penetration)
//   4. bullish/bearish rejection confirms: a later bar closes back through
//      the rejection bar's high/low (the one prospectively frozen
//      confirmation the handoff requires)
//
// Stop: beyond the retest extreme. Target: canonical fixed 2R.
//
// Shadow-only: emits into MSZZResearchCandidate only.

#define MSZZ_BRC_MIN_CLOSE_DISTANCE_ATR 0.10
#define MSZZ_BRC_MIN_BODY_FRACTION      0.40   // body/range filter: reject marginal one-tick breaks
#define MSZZ_BRC_RETEST_MIN_BARS         2
#define MSZZ_BRC_RETEST_MAX_BARS        12
#define MSZZ_BRC_MAX_PENETRATION_ATR    0.30
#define MSZZ_BRC_TARGET_R                2.0
#define MSZZ_BRC_VALIDITY_BARS           3
#define MSZZ_BRC_CANONICAL_VARIANT_ID   "BRC-CANON-1"

enum ENUM_MSZZ_BRC_STATE { MSZZ_BRC_IDLE=0, MSZZ_BRC_BREAK_CONFIRMED=1, MSZZ_BRC_RETEST_ZONE=2, MSZZ_BRC_TRIGGERED=3, MSZZ_BRC_EXPIRED=4, MSZZ_BRC_INVALIDATED=5 };

struct MSZZBreakRetestSetup
{
   bool                 active;
   ENUM_MSZZ_DIRECTION  direction;
   ENUM_MSZZ_BRC_STATE  state;
   datetime             break_time;
   int                  bars_since_break;
   double               break_level;
   double               rejection_bar_high;
   double               rejection_bar_low;
   string               origin_id;
   string               sequence_id;
};

class CMSZZFamilyBreakRetestContinuation
{
private:
   MSZZBreakRetestSetup m_long,m_short;
   int m_period_seconds;

   void Reset(MSZZBreakRetestSetup &s) const { ZeroMemory(s); s.state=MSZZ_BRC_IDLE; s.direction=MSZZ_DIR_NONE; }

   bool ValidBreakBar(const MqlRates &bar) const
   {
      double range=bar.high-bar.low;
      if(range<=0.0) return false;
      return (MathAbs(bar.close-bar.open)/range)>=MSZZ_BRC_MIN_BODY_FRACTION;
   }

   void ArmBreak(MSZZBreakRetestSetup &s,const ENUM_MSZZ_DIRECTION dir,const datetime t,
                 const double level,const string origin_id)
   {
      Reset(s); s.active=true; s.direction=dir; s.state=MSZZ_BRC_BREAK_CONFIRMED;
      s.break_time=t; s.bars_since_break=0; s.break_level=level; s.origin_id=origin_id;
      s.sequence_id="BRC|"+origin_id+"|"+IntegerToString((long)t);
   }

   void Evaluate1Side(MSZZBreakRetestSetup &s,const MqlRates &bar,const double atr,
                       MSZZResearchCandidate &out[],int &count,const string regime_id,
                       const string session_id,const double point_size)
   {
      if(!s.active) return;
      s.bars_since_break++;
      if(s.bars_since_break>MSZZ_BRC_RETEST_MAX_BARS){ s.active=false; s.state=MSZZ_BRC_EXPIRED; return; }

      double penetration=atr*MSZZ_BRC_MAX_PENETRATION_ATR;
      bool invalidated=(s.direction==MSZZ_DIR_LONG ? bar.close<s.break_level-penetration
                                                      : bar.close>s.break_level+penetration);
      if(invalidated){ s.active=false; s.state=MSZZ_BRC_INVALIDATED; return; }

      if(s.bars_since_break<MSZZ_BRC_RETEST_MIN_BARS) return; // ignore same-leg noise immediately after the break

      bool touched=(s.direction==MSZZ_DIR_LONG ? bar.low<=s.break_level : bar.high>=s.break_level);
      if(s.state==MSZZ_BRC_BREAK_CONFIRMED)
      {
         if(!touched) return;
         s.state=MSZZ_BRC_RETEST_ZONE; s.rejection_bar_high=bar.high; s.rejection_bar_low=bar.low;
         return;
      }
      // MSZZ_BRC_RETEST_ZONE: track the most recent bar touching the zone as
      // the rejection-bar reference, then require a LATER bar to close
      // through that specific bar's high/low -- the one frozen confirmation
      // shape, never redefined mid-run.
      if(touched){ s.rejection_bar_high=bar.high; s.rejection_bar_low=bar.low; return; }

      bool trigger=(s.direction==MSZZ_DIR_LONG ? bar.close>s.rejection_bar_high
                                                  : bar.close<s.rejection_bar_low);
      if(!trigger) return;

      double stop=(s.direction==MSZZ_DIR_LONG ? s.rejection_bar_low : s.rejection_bar_high);
      string structural_context=StringFormat("break_level=%.5f;bars_since_break=%d",s.break_level,s.bars_since_break);
      CMSZZResearchCandidateFactory::Emit(out,count,MSZZ_RSRCH_STRAT_BREAK_RETEST_CONTINUATION,
         MSZZ_RSRCH_FAMILY_BREAK_RETEST_CONTINUATION,s.direction,bar.time,
         bar.time+(datetime)(MSZZ_BRC_VALIDITY_BARS*m_period_seconds),bar.close,stop,MSZZ_BRC_TARGET_R,
         7.0,"Break-Retest Continuation",s.origin_id,s.sequence_id+"|FINAL",
         "confirmed medium-structure break, frozen-window retest, close through rejection bar extreme",
         MSZZ_BRC_CANONICAL_VARIANT_ID,regime_id,session_id,"MEDIUM_SWING_HIGH_LOW",structural_context,
         bar.spread,point_size);
      s.active=false; s.state=MSZZ_BRC_TRIGGERED;
   }

public:
   CMSZZFamilyBreakRetestContinuation() { m_period_seconds=300; Reset(m_long); Reset(m_short); }
   void Configure(const int period_seconds) { m_period_seconds=MathMax(1,period_seconds); }

   int Evaluate(const MSZZSpeedSnapshot &m,const MqlRates &bar,const string regime_id,
                const string session_id,const double point_size,MSZZResearchCandidate &out[])
   {
      int count=0; ArrayResize(out,0);
      double atr=m.atr;
      if(atr<=0.0) return 0;

      Evaluate1Side(m_long,bar,atr,out,count,regime_id,session_id,point_size);
      Evaluate1Side(m_short,bar,atr,out,count,regime_id,session_id,point_size);

      double min_dist=atr*MSZZ_BRC_MIN_CLOSE_DISTANCE_ATR;
      if(!m_long.active && m.bullish_break && ValidBreakBar(bar) && m.resistance_now>0.0 &&
         bar.close>=m.resistance_now+min_dist)
         ArmBreak(m_long,MSZZ_DIR_LONG,bar.time,m.resistance_now,m.bullish_event_id);
      if(!m_short.active && m.bearish_break && ValidBreakBar(bar) && m.support_now>0.0 &&
         bar.close<=m.support_now-min_dist)
         ArmBreak(m_short,MSZZ_DIR_SHORT,bar.time,m.support_now,m.bearish_event_id);

      return count;
   }
};

#endif
