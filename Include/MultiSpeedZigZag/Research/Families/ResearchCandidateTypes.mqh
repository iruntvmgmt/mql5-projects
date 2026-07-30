#ifndef __MSZZ_RESEARCH_CANDIDATE_TYPES_MQH__
#define __MSZZ_RESEARCH_CANDIDATE_TYPES_MQH__

// Only for ENUM_MSZZ_DIRECTION (MSZZ_DIR_LONG/SHORT/NONE) -- this file is
// otherwise deliberately independent of Core/Types.mqh, see below.
#include <MultiSpeedZigZag/Core/Types.mqh>

// D031: six-family shadow research architecture. See
// Docs/MultiSpeedZigZag/D031_SIX_FAMILY_ARCHITECTURE.md and
// Docs/MultiSpeedZigZag/D030_D035_Six_Family_Claude_Handoff.md.
//
// Deliberately NOT built on ENUM_MSZZ_STRATEGY_ID / ENUM_MSZZ_STRATEGY_FAMILY
// / MSZZCandidate (Core/Types.mqh). Those types are load-bearing for the
// LIVE execution path (StrategySuite -> CandidateHandoff -> ClusterEngine ->
// ExecuteCluster -> StrategyBook -> broker). Reusing them here would create
// a compile-time and conceptual coupling between shadow research candidates
// and the execution pipeline that this program's isolation requirements
// ("no execution intents", "no order placement", "shadow mode cannot reach
// execution") are specifically designed to prevent. This file's IDs and
// struct are a deliberately separate, disjoint namespace: plain int fields,
// not the production enums, so nothing here can ever be silently accepted
// by code that expects an ENUM_MSZZ_STRATEGY_ID/ENUM_MSZZ_STRATEGY_FAMILY.
//
// ID allocation (verified non-colliding against Core/Types.mqh's existing
// 1001-1080 strategy-ID range and 0-7 family-ID range as of D031 -- see
// Tools/D031/id_allocation.csv for the inspection this was derived from):

#define MSZZ_RSRCH_STRAT_SESSION_SWEEP_REVERSAL     1200
#define MSZZ_RSRCH_STRAT_MOMENTUM_CONTINUATION      1201
#define MSZZ_RSRCH_STRAT_BREAK_RETEST_CONTINUATION  1202
#define MSZZ_RSRCH_STRAT_COMPRESSION_BREAKOUT       1203
#define MSZZ_RSRCH_STRAT_TREND_PULLBACK             1204
#define MSZZ_RSRCH_STRAT_RANGE_ROTATION             1205

#define MSZZ_RSRCH_FAMILY_SESSION_SWEEP_REVERSAL     8
#define MSZZ_RSRCH_FAMILY_MOMENTUM_CONTINUATION      9
#define MSZZ_RSRCH_FAMILY_BREAK_RETEST_CONTINUATION  10
#define MSZZ_RSRCH_FAMILY_COMPRESSION_BREAKOUT       11
#define MSZZ_RSRCH_FAMILY_TREND_PULLBACK             12
#define MSZZ_RSRCH_FAMILY_RANGE_ROTATION             13

// D031 anti-overfitting freeze: one hypothesis_version string per family,
// bumped only if a family's canonical definition is deliberately redefined
// in a future phase (never silently). Frozen before any D032 screening.
#define MSZZ_RSRCH_HYPOTHESIS_VERSION "D031v1"

string MSZZResearchStrategyName(const int strategy_id)
{
   switch(strategy_id)
   {
      case MSZZ_RSRCH_STRAT_SESSION_SWEEP_REVERSAL:    return "Session Sweep Reversal";
      case MSZZ_RSRCH_STRAT_MOMENTUM_CONTINUATION:     return "Momentum Continuation";
      case MSZZ_RSRCH_STRAT_BREAK_RETEST_CONTINUATION: return "Break-Retest Continuation";
      case MSZZ_RSRCH_STRAT_COMPRESSION_BREAKOUT:      return "Compression Breakout (Research)";
      case MSZZ_RSRCH_STRAT_TREND_PULLBACK:            return "Trend Pullback";
      case MSZZ_RSRCH_STRAT_RANGE_ROTATION:             return "Range Rotation";
      default: return "UNKNOWN_RESEARCH_STRATEGY";
   }
}

// Every field the D030_D035 handoff's "shared candidate interface" +
// "research metadata" sections require, in one struct, shared by all six
// families and the aggregator/journal. Emission-only: nothing in this
// research layer ever mutates a candidate after CMSZZResearchJournal writes
// it (enforced by convention -- callers must treat the struct as write-once
// after Emit()).
struct MSZZResearchCandidate
{
   bool                 valid;
   int                  strategy_id;
   int                  family_id;
   string               setup_name;
   datetime             signal_time;
   datetime             expiry_time;
   ENUM_MSZZ_DIRECTION  direction;
   double               entry;
   double               stop;
   double               target;
   double               score;
   string               origin_id;
   string               event_id;
   string               reason;
   // Research metadata (D030_D035 handoff, "Shared candidate interface"):
   string               canonical_variant_id;
   string               hypothesis_version;
   string               regime_id;
   string               session_id;
   string               reference_level_type;
   string               structural_context;
   double               stop_distance_points;
   double               target_r;
   double               spread_to_risk_ratio;
};

// Shared, deterministic emit helper: every family calls this instead of
// constructing MSZZResearchCandidate by hand, so the invariants below are
// enforced identically everywhere (no order placement, no null keys, no
// non-finite geometry) -- mirrors D027StrategyFamilies.mqh's Emit() pattern
// one layer up, for the disjoint research struct instead of MSZZCandidate.
class CMSZZResearchCandidateFactory
{
public:
   static bool Emit(MSZZResearchCandidate &out[],int &count,
                     const int strategy_id,const int family_id,
                     const ENUM_MSZZ_DIRECTION direction,const datetime signal_time,
                     const datetime expiry_time,const double entry,const double stop,
                     const double target_r_multiple,const double score,
                     const string setup_name,const string origin_id,const string event_id,
                     const string reason,const string canonical_variant_id,
                     const string regime_id,const string session_id,
                     const string reference_level_type,const string structural_context,
                     const int bar_spread_points,const double point_size)
   {
      if(origin_id=="" || event_id=="" || setup_name=="") return false;
      if(entry<=0.0 || stop<=0.0 || entry==stop) return false;
      if(direction==MSZZ_DIR_LONG && stop>=entry) return false;
      if(direction==MSZZ_DIR_SHORT && stop<=entry) return false;
      if(direction==MSZZ_DIR_NONE) return false;
      double risk=MathAbs(entry-stop);
      if(risk<=0.0) return false;

      MSZZResearchCandidate c; ZeroMemory(c);
      c.valid=true; c.strategy_id=strategy_id; c.family_id=family_id; c.direction=direction;
      c.signal_time=signal_time; c.expiry_time=expiry_time;
      c.entry=entry; c.stop=stop;
      c.target=(direction==MSZZ_DIR_LONG ? entry+risk*target_r_multiple : entry-risk*target_r_multiple);
      c.score=score; c.setup_name=setup_name; c.origin_id=origin_id; c.event_id=event_id; c.reason=reason;
      c.canonical_variant_id=canonical_variant_id;
      c.hypothesis_version=MSZZ_RSRCH_HYPOTHESIS_VERSION;
      c.regime_id=regime_id; c.session_id=session_id;
      c.reference_level_type=reference_level_type; c.structural_context=structural_context;
      c.stop_distance_points=(point_size>0.0 ? risk/point_size : 0.0);
      c.target_r=target_r_multiple;
      c.spread_to_risk_ratio=(risk>0.0 ? (bar_spread_points*point_size)/risk : 0.0);

      int n=ArraySize(out); ArrayResize(out,n+1);
      out[n]=c; count++;
      return true;
   }

   // Range Rotation's canonical target is the range midpoint, not a fixed
   // R-multiple -- every other family uses Emit() above. target_r here is
   // derived (realized R the geometric target implies), for journaling
   // parity with the other families' target_r field, never used to define
   // the target itself.
   static bool EmitWithExplicitTarget(MSZZResearchCandidate &out[],int &count,
                     const int strategy_id,const int family_id,
                     const ENUM_MSZZ_DIRECTION direction,const datetime signal_time,
                     const datetime expiry_time,const double entry,const double stop,
                     const double target,const double score,
                     const string setup_name,const string origin_id,const string event_id,
                     const string reason,const string canonical_variant_id,
                     const string regime_id,const string session_id,
                     const string reference_level_type,const string structural_context,
                     const int bar_spread_points,const double point_size)
   {
      if(origin_id=="" || event_id=="" || setup_name=="") return false;
      if(entry<=0.0 || stop<=0.0 || target<=0.0 || entry==stop) return false;
      if(direction==MSZZ_DIR_LONG && (stop>=entry || target<=entry)) return false;
      if(direction==MSZZ_DIR_SHORT && (stop<=entry || target>=entry)) return false;
      double risk=MathAbs(entry-stop);
      if(risk<=0.0) return false;

      MSZZResearchCandidate c; ZeroMemory(c);
      c.valid=true; c.strategy_id=strategy_id; c.family_id=family_id; c.direction=direction;
      c.signal_time=signal_time; c.expiry_time=expiry_time;
      c.entry=entry; c.stop=stop; c.target=target;
      c.score=score; c.setup_name=setup_name; c.origin_id=origin_id; c.event_id=event_id; c.reason=reason;
      c.canonical_variant_id=canonical_variant_id;
      c.hypothesis_version=MSZZ_RSRCH_HYPOTHESIS_VERSION;
      c.regime_id=regime_id; c.session_id=session_id;
      c.reference_level_type=reference_level_type; c.structural_context=structural_context;
      c.stop_distance_points=(point_size>0.0 ? risk/point_size : 0.0);
      c.target_r=MathAbs(target-entry)/risk;
      c.spread_to_risk_ratio=(risk>0.0 ? (bar_spread_points*point_size)/risk : 0.0);

      int n=ArraySize(out); ArrayResize(out,n+1);
      out[n]=c; count++;
      return true;
   }
};

#endif
