#ifndef __MSZZ_CANDIDATE_HANDOFF_MQH__
#define __MSZZ_CANDIDATE_HANDOFF_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

// D028 Stage 0B: candidate arrays crossing subsystem boundaries are compact
// logical collections. No caller may infer a logical index from spare array
// capacity, and no malformed/uninitialized slot may reach clustering.
class CMSZZCandidateHandoff
{
private:
   static bool KnownStrategy(const ENUM_MSZZ_STRATEGY_ID id)
   {
      switch(id)
      {
         case MSZZ_STRAT_FAST_BREAKOUT:
         case MSZZ_STRAT_MEDIUM_BREAKOUT:
         case MSZZ_STRAT_SLOW_BREAKOUT:
         case MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE:
         case MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT:
         case MSZZ_STRAT_MEDIUM_WITH_SLOW_CONTEXT:
         case MSZZ_STRAT_SEQUENTIAL_CONFIRMATION:
         case MSZZ_STRAT_NESTED_PULLBACK:
         case MSZZ_STRAT_ALIGNED_FAST_PULLBACK:
         case MSZZ_STRAT_BREAKOUT_RETEST:
         case MSZZ_STRAT_SWEEP_RECLAIM:
         case MSZZ_STRAT_COMPRESSION_BREAKOUT:
         case MSZZ_STRAT_STRUCTURE_TRANSITION:
         case MSZZ_STRAT_WEIGHTED_ENSEMBLE:
            return true;
         default:
            return false;
      }
   }

   static bool KnownFamily(const ENUM_MSZZ_STRATEGY_FAMILY id)
   {
      return id>=MSZZ_FAMILY_BREAKOUT && id<=MSZZ_FAMILY_ENSEMBLE;
   }

public:
   static bool Validate(const MSZZCandidate &candidate,string &diagnostic)
   {
      diagnostic="";
      if(!candidate.valid) { diagnostic="candidate_not_explicitly_initialized"; return false; }
      if(!KnownStrategy(candidate.strategy_id)) { diagnostic="invalid_strategy_id"; return false; }
      if(!KnownFamily(candidate.family_id)) { diagnostic="invalid_family_id"; return false; }
      if(candidate.direction!=MSZZ_DIR_LONG && candidate.direction!=MSZZ_DIR_SHORT)
      { diagnostic="invalid_direction"; return false; }
      if(candidate.event_id=="") { diagnostic="missing_event_id"; return false; }
      if(candidate.origin_id=="") { diagnostic="missing_origin_id"; return false; }
      if(!MathIsValidNumber(candidate.score)) { diagnostic="invalid_score"; return false; }
      if(!MathIsValidNumber(candidate.entry) || candidate.entry<=0.0)
      { diagnostic="invalid_entry"; return false; }
      if(!MathIsValidNumber(candidate.stop) || candidate.stop<=0.0 || candidate.stop==candidate.entry)
      { diagnostic="invalid_stop"; return false; }
      if(!MathIsValidNumber(candidate.target) || candidate.target<=0.0)
      { diagnostic="invalid_target"; return false; }
      return true;
   }

   static bool ValidateCollection(const MSZZCandidate &candidates[],const int logical_count,
                                  string &diagnostic)
   {
      diagnostic="";
      int physical_size=ArraySize(candidates);
      if(logical_count<0) { diagnostic="negative_candidate_count"; return false; }
      if(logical_count>physical_size)
      {
         diagnostic=StringFormat("candidate_count_exceeds_array_size count=%d size=%d",
                                 logical_count,physical_size);
         return false;
      }
      if(logical_count!=physical_size)
      {
         diagnostic=StringFormat("sparse_candidate_collection count=%d size=%d",
                                 logical_count,physical_size);
         return false;
      }
      for(int i=0;i<logical_count;i++)
      {
         string reason;
         if(!Validate(candidates[i],reason))
         {
            diagnostic=StringFormat("invalid_candidate index=%d reason=%s",i,reason);
            return false;
         }
      }
      return true;
   }

   static bool Append(MSZZCandidate &candidates[],int &logical_count,
                      const MSZZCandidate &candidate,int &appended_index,string &diagnostic)
   {
      appended_index=-1;
      diagnostic="";
      int physical_size=ArraySize(candidates);
      if(logical_count<0 || logical_count>physical_size)
      {
         diagnostic=StringFormat("append_count_out_of_bounds count=%d size=%d",
                                 logical_count,physical_size);
         return false;
      }
      // A handoff collection must be compact before append. This rejects the
      // exact D027 defect: logical count 1 with physical size 16.
      if(logical_count!=physical_size)
      {
         diagnostic=StringFormat("append_to_sparse_collection count=%d size=%d",
                                 logical_count,physical_size);
         return false;
      }
      string reason;
      if(!Validate(candidate,reason))
      {
         diagnostic="append_invalid_candidate reason="+reason;
         return false;
      }
      appended_index=logical_count;
      if(ArrayResize(candidates,logical_count+1)!=logical_count+1)
      {
         appended_index=-1;
         diagnostic="append_resize_failed";
         return false;
      }
      candidates[appended_index]=candidate;
      logical_count++;
      return true;
   }
};

#endif
