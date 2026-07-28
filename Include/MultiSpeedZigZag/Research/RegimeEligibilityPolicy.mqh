#ifndef __MSZZ_REGIME_ELIGIBILITY_POLICY_MQH__
#define __MSZZ_REGIME_ELIGIBILITY_POLICY_MQH__

// D027 Layer 3: decides whether a strategy is eligible under a regime.
// Pure, stateless, no MT5 API. Two modes -- LABEL_ONLY (default everywhere
// in this branch today: every existing strategy behaves exactly as before,
// every candidate/trade still receives regime labels, nothing is
// filtered) and RESEARCH_FILTER (only the six per-family primary
// hypotheses predeclared in DECISION_LOG.md D027 -- no combinatorial
// search, no gating of A/E, not active for any strategy until a later,
// separate decision authorizes it for that strategy specifically). See
// DECISION_LOG.md D027 for the frozen per-family hypotheses this file
// implements verbatim.

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>

enum ENUM_MSZZ_ELIGIBILITY_MODE
{
   MSZZ_ELIGIBILITY_LABEL_ONLY = 0,
   MSZZ_ELIGIBILITY_RESEARCH_FILTER = 1
};

string MSZZEligibilityModeText(const ENUM_MSZZ_ELIGIBILITY_MODE m)
{
   return (m==MSZZ_ELIGIBILITY_RESEARCH_FILTER) ? "RESEARCH_FILTER" : "LABEL_ONLY";
}

class CMSZZRegimeEligibilityPolicy
{
public:
   static bool IsEligible(const ENUM_MSZZ_ELIGIBILITY_MODE mode,
                           const ENUM_MSZZ_STRATEGY_FAMILY family,
                           const ENUM_MSZZ_STRATEGY_ID strategy_id,
                           const MSZZRegimeState &regime,
                           string &reason)
   {
      reason="";
      if(mode==MSZZ_ELIGIBILITY_LABEL_ONLY)
      {
         reason="LABEL_ONLY mode: every strategy is always eligible, regime is a label only";
         return true;
      }
      if(!regime.valid)
      {
         reason="regime state invalid";
         return false;
      }

      bool aligned=(regime.alignment_state==MSZZ_ALIGN_FULLY_ALIGNED || regime.alignment_state==MSZZ_ALIGN_PARTIALLY_ALIGNED);
      bool vol_ok=(regime.volatility_state==MSZZ_VOL_NORMAL || regime.volatility_state==MSZZ_VOL_EXPANDING);

      switch(family)
      {
         case MSZZ_FAMILY_BREAKOUT:
            if(aligned && vol_ok && (regime.market_phase==MSZZ_PHASE_BREAKOUT || regime.market_phase==MSZZ_PHASE_TREND_CONTINUATION))
            { reason="breakout family: alignment+volatility+phase all satisfied"; return true; }
            reason="breakout family: eligibility hypothesis not met"; return false;

         case MSZZ_FAMILY_PULLBACK:
            if(regime.direction!=MSZZ_REGIME_DIR_NEUTRAL && aligned && regime.market_phase==MSZZ_PHASE_PULLBACK)
            { reason="pullback family: slow direction exists, medium aligned/correcting, phase=PULLBACK"; return true; }
            reason="pullback family: eligibility hypothesis not met"; return false;

         case MSZZ_FAMILY_RETEST:
            if(regime.market_phase==MSZZ_PHASE_TREND_CONTINUATION)
            { reason="retest family: original breakout regime remains directionally valid (TREND_CONTINUATION)"; return true; }
            reason="retest family: eligibility hypothesis not met"; return false;

         case MSZZ_FAMILY_REVERSAL:
            // Two distinct hypotheses share this family (S3 sweep/reclaim,
            // S5 structure transition) -- disambiguated by strategy_id,
            // since their predeclared regime preconditions differ.
            if(strategy_id==MSZZ_STRAT_SWEEP_RECLAIM)
            {
               // Sweep/reclaim's predeclared hypothesis requires
               // MSZZ_PHASE_FAILED_BREAK, which this pass's classifier
               // never emits (see DECISION_LOG.md D027) -- honestly always
               // ineligible under RESEARCH_FILTER until FAILED_BREAK is
               // implemented, not silently redirected to another phase.
               reason="sweep/reclaim family: requires FAILED_BREAK, not implemented by the classifier in this pass";
               return false;
            }
            if(strategy_id==MSZZ_STRAT_STRUCTURE_TRANSITION)
            {
               if(regime.market_phase==MSZZ_PHASE_TRANSITION && regime.alignment_state!=MSZZ_ALIGN_OPPOSED)
               { reason="structure-transition family: phase=TRANSITION and alignment not strongly opposed"; return true; }
               reason="structure-transition family: eligibility hypothesis not met"; return false;
            }
            reason="reversal family: no strategy-specific hypothesis resolved for this strategy_id";
            return false;

         case MSZZ_FAMILY_COMPRESSION:
            if((regime.volatility_state==MSZZ_VOL_CONTRACTING || regime.volatility_state==MSZZ_VOL_NORMAL) &&
               regime.market_phase==MSZZ_PHASE_COMPRESSION)
            { reason="compression family: volatility contracting/normal and phase=COMPRESSION (pre-breakout state)"; return true; }
            reason="compression family: eligibility hypothesis not met"; return false;

         default:
            reason="no RESEARCH_FILTER hypothesis predeclared for this family";
            return false;
      }
   }
};

#endif
