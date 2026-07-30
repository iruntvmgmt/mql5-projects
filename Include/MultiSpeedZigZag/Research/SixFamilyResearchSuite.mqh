#ifndef __MSZZ_SIX_FAMILY_RESEARCH_SUITE_MQH__
#define __MSZZ_SIX_FAMILY_RESEARCH_SUITE_MQH__

// D031: six-family shadow candidate architecture, aggregator. See
// Docs/MultiSpeedZigZag/D031_SIX_FAMILY_ARCHITECTURE.md.
//
// SAFETY CONTRACT (verified by Tools/D031's shadow-safety audit and the
// shared architecture tests): this file and everything it includes
//   - never calls OrderSend/OrderCheck/PositionClose or any other trade
//     function,
//   - never mutates a broker position, an ExecutionIntent, a StrategyBook,
//     or the PortfolioRiskManager,
//   - never appends into or otherwise touches the production MSZZCandidate
//     pipeline (StrategySuite / D027StrategyFamilies / CandidateHandoff /
//     ClusterEngine),
//   - only reads inputs the EA already computed this bar (fast/med/slow
//     snapshots, regime state, the closed bar) and writes exactly one
//     journal file.
// Its Include graph is deliberately disjoint from Execution/*: grep
// confirms nothing under Research/Families/ or this file includes
// anything from Include/MultiSpeedZigZag/Execution/ or
// Include/MultiSpeedZigZag/Portfolio/.

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/Families/ResearchCandidateTypes.mqh>
#include <MultiSpeedZigZag/Research/Families/SessionSweepReversal.mqh>
#include <MultiSpeedZigZag/Research/Families/MomentumContinuation.mqh>
#include <MultiSpeedZigZag/Research/Families/BreakRetestContinuation.mqh>
#include <MultiSpeedZigZag/Research/Families/CompressionBreakoutResearch.mqh>
#include <MultiSpeedZigZag/Research/Families/TrendPullback.mqh>
#include <MultiSpeedZigZag/Research/Families/RangeRotation.mqh>

// Reimplements (does not include/call) the exact frozen three-bucket
// session definition already established in
// Diagnostics/TradeAnalyticsExporter.mqh's CMSZZTradeAnalyticsPolicy::
// SessionBucket, so this research layer's include graph never has to pull
// in Execution/ExecutionIntentStore.mqh (that file's own dependency) just
// to label a session. Same three boundaries, same simplification
// disclosed there (not DST-aware).
string MSZZResearchSessionId(const datetime t)
{
   MqlDateTime dt; TimeToStruct(t,dt);
   if(dt.hour<8) return "Asian";
   if(dt.hour<16) return "London";
   return "NewYork";
}

class CMSZZSixFamilyResearchSuite
{
private:
   CMSZZFamilySessionSweepReversal        m_ssr;
   CMSZZFamilyMomentumContinuation        m_mc;
   CMSZZFamilyBreakRetestContinuation     m_brc;
   CMSZZFamilyCompressionBreakoutResearch m_cbr;
   CMSZZFamilyTrendPullback               m_tp;
   CMSZZFamilyRangeRotation               m_rr;
   bool m_write_journal;

   void Journal(const MSZZResearchCandidate &c) const
   {
      if(!m_write_journal) return;
      int h=FileOpen("MSZZ_SixFamilyResearchJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(h==INVALID_HANDLE) return;
      if(FileSize(h)==0)
         FileWrite(h,"strategy_id","family_id","setup_name","signal_time","expiry_time","direction",
                   "entry","stop","target","score","origin_id","event_id","reason",
                   "canonical_variant_id","hypothesis_version","regime_id","session_id",
                   "reference_level_type","structural_context","stop_distance_points","target_r",
                   "spread_to_risk_ratio");
      FileSeek(h,0,SEEK_END);
      FileWrite(h,c.strategy_id,c.family_id,c.setup_name,
                TimeToString(c.signal_time,TIME_DATE|TIME_SECONDS),
                TimeToString(c.expiry_time,TIME_DATE|TIME_SECONDS),MSZZDirectionText(c.direction),
                DoubleToString(c.entry,_Digits),DoubleToString(c.stop,_Digits),DoubleToString(c.target,_Digits),
                DoubleToString(c.score,4),c.origin_id,c.event_id,c.reason,
                c.canonical_variant_id,c.hypothesis_version,c.regime_id,c.session_id,
                c.reference_level_type,c.structural_context,
                DoubleToString(c.stop_distance_points,2),DoubleToString(c.target_r,4),
                DoubleToString(c.spread_to_risk_ratio,6));
      FileFlush(h); FileClose(h);
   }

public:
   CMSZZSixFamilyResearchSuite() { m_write_journal=false; }

   void Configure(const int period_seconds,const bool write_journal)
   {
      m_ssr.Configure(period_seconds); m_mc.Configure(period_seconds); m_brc.Configure(period_seconds);
      m_cbr.Configure(period_seconds); m_tp.Configure(period_seconds); m_rr.Configure(period_seconds);
      m_write_journal=write_journal;
   }

   // Called once per closed bar, read-only w.r.t. everything except its own
   // journal file and each family's own internal state. Returns the total
   // candidate count purely for caller-side logging/diagnostics -- the
   // caller MUST NOT feed the out[] array into the production candidate
   // pipeline (see safety contract above; enforced by convention and by
   // the shared architecture tests, since MSZZResearchCandidate is not
   // MSZZCandidate and CandidateHandoff/ClusterEngine do not accept it).
   int Evaluate(const MSZZSpeedSnapshot &fast,const MSZZSpeedSnapshot &med,const MSZZSpeedSnapshot &slow,
                const MSZZRegimeState &regime,const MqlRates &bar,MSZZResearchCandidate &out[])
   {
      int total=0; ArrayResize(out,0);
      string regime_id=TimeToString(regime.evaluation_time,TIME_DATE|TIME_SECONDS);
      string session_id=MSZZResearchSessionId(bar.time);
      double point_size=_Point;

      MSZZResearchCandidate family_out[];

      int n1=m_ssr.Evaluate(fast,bar,regime_id,session_id,point_size,family_out);
      for(int i=0;i<n1;i++){ int sz=ArraySize(out); ArrayResize(out,sz+1); out[sz]=family_out[i]; Journal(family_out[i]); }
      total+=n1;

      int n2=m_mc.Evaluate(fast,med,slow,regime,bar,regime_id,session_id,point_size,family_out);
      for(int i=0;i<n2;i++){ int sz=ArraySize(out); ArrayResize(out,sz+1); out[sz]=family_out[i]; Journal(family_out[i]); }
      total+=n2;

      int n3=m_brc.Evaluate(med,bar,regime_id,session_id,point_size,family_out);
      for(int i=0;i<n3;i++){ int sz=ArraySize(out); ArrayResize(out,sz+1); out[sz]=family_out[i]; Journal(family_out[i]); }
      total+=n3;

      int n4=m_cbr.Evaluate(fast,med,slow,regime,bar,regime_id,session_id,point_size,family_out);
      for(int i=0;i<n4;i++){ int sz=ArraySize(out); ArrayResize(out,sz+1); out[sz]=family_out[i]; Journal(family_out[i]); }
      total+=n4;

      int n5=m_tp.Evaluate(fast,med,slow,regime,bar,regime_id,session_id,point_size,family_out);
      for(int i=0;i<n5;i++){ int sz=ArraySize(out); ArrayResize(out,sz+1); out[sz]=family_out[i]; Journal(family_out[i]); }
      total+=n5;

      int n6=m_rr.Evaluate(fast,med,slow,regime,bar,regime_id,session_id,point_size,family_out);
      for(int i=0;i<n6;i++){ int sz=ArraySize(out); ArrayResize(out,sz+1); out[sz]=family_out[i]; Journal(family_out[i]); }
      total+=n6;

      return total;
   }
};

#endif
