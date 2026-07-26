#ifndef __MSZZ_OPPORTUNITY_CLUSTER_ENGINE_MQH__
#define __MSZZ_OPPORTUNITY_CLUSTER_ENGINE_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

class CMSZZOpportunityClusterEngine
{
private:
   string ClusterId(const string symbol,const ENUM_TIMEFRAMES timeframe,
                    const ENUM_MSZZ_DIRECTION direction,const ENUM_MSZZ_ORIGIN_TYPE origin_type,
                    const string origin_id) const
   {
      return StringFormat("MSZZC|%s|%d|%d|%d|%s",symbol,(int)timeframe,(int)direction,(int)origin_type,origin_id);
   }

   bool SameCluster(const MSZZCandidate &a,const MSZZCandidate &b) const
   {
      if(!a.valid || !b.valid) return false;
      if(a.direction!=b.direction) return false;
      if(a.origin_id!="" && b.origin_id!="") return a.origin_id==b.origin_id;
      return a.event_id==b.event_id;
   }

   int OwnerPriority(const ENUM_MSZZ_STRATEGY_ID id) const
   {
      switch(id)
      {
         case MSZZ_STRAT_BREAKOUT_RETEST: return 100;
         case MSZZ_STRAT_SWEEP_RECLAIM: return 95;
         case MSZZ_STRAT_NESTED_PULLBACK: return 90;
         case MSZZ_STRAT_SEQUENTIAL_CONFIRMATION: return 85;
         case MSZZ_STRAT_STRUCTURE_TRANSITION: return 80;
         case MSZZ_STRAT_COMPRESSION_BREAKOUT: return 75;
         case MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE: return 70;
         case MSZZ_STRAT_MEDIUM_WITH_SLOW_CONTEXT: return 60;
         case MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT: return 50;
         case MSZZ_STRAT_SLOW_BREAKOUT: return 40;
         case MSZZ_STRAT_MEDIUM_BREAKOUT: return 30;
         case MSZZ_STRAT_FAST_BREAKOUT: return 20;
         case MSZZ_STRAT_WEIGHTED_ENSEMBLE: return 10;
         default: return 0;
      }
   }

   void AppendStrategyId(string &csv,const ENUM_MSZZ_STRATEGY_ID id) const
   {
      string value=IntegerToString((int)id);
      if(csv=="") { csv=value; return; }
      string needle=","+value+",";
      string haystack=","+csv+",";
      if(StringFind(haystack,needle)<0) csv=csv+","+value;
   }

public:
   int Build(const string symbol,const ENUM_TIMEFRAMES timeframe,const MSZZCandidate &candidates[],
             const int candidate_count,MSZZOpportunityCluster &clusters[])
   {
      ArrayResize(clusters,0);
      int cluster_count=0;

      for(int i=0;i<candidate_count;i++)
      {
         if(!candidates[i].valid) continue;
         int target=-1;
         for(int c=0;c<cluster_count;c++)
         {
            int representative=clusters[c].preferred_index;
            if(representative>=0 && representative<candidate_count && SameCluster(candidates[i],candidates[representative]))
            {
               target=c;
               break;
            }
         }

         if(target<0)
         {
            target=cluster_count++;
            ArrayResize(clusters,cluster_count);
            clusters[target].valid=true;
            clusters[target].origin_id=(candidates[i].origin_id!="" ? candidates[i].origin_id : candidates[i].event_id);
            clusters[target].origin_type=candidates[i].origin_type;
            clusters[target].direction=candidates[i].direction;
            clusters[target].state=MSZZ_CLUSTER_OPEN;
            clusters[target].origin_time=candidates[i].signal_time;
            clusters[target].latest_time=candidates[i].signal_time;
            clusters[target].expiry_time=candidates[i].expiry_time;
            clusters[target].canonical_stop=candidates[i].stop;
            clusters[target].combined_score=candidates[i].score;
            clusters[target].stop_disagreement=0.0;
            clusters[target].support_count=1;
            clusters[target].evidence_mask=candidates[i].evidence_mask;
            clusters[target].preferred_index=i;
            clusters[target].owner_strategy_id=candidates[i].strategy_id;
            clusters[target].supporting_strategy_ids=IntegerToString((int)candidates[i].strategy_id);
            clusters[target].cluster_id=ClusterId(symbol,timeframe,candidates[i].direction,
                                                  candidates[i].origin_type,clusters[target].origin_id);
            continue;
         }

         clusters[target].latest_time=MathMax(clusters[target].latest_time,candidates[i].signal_time);
         if(clusters[target].expiry_time==0 || (candidates[i].expiry_time>0 && candidates[i].expiry_time<clusters[target].expiry_time))
            clusters[target].expiry_time=candidates[i].expiry_time;
         clusters[target].stop_disagreement=MathMax(clusters[target].stop_disagreement,MathAbs(candidates[i].stop-clusters[target].canonical_stop));
         clusters[target].support_count++;
         clusters[target].evidence_mask|=candidates[i].evidence_mask;
         AppendStrategyId(clusters[target].supporting_strategy_ids,candidates[i].strategy_id);

         double support_bonus=MathMin(1.5,0.25*(double)(clusters[target].support_count-1));
         clusters[target].combined_score=MathMax(clusters[target].combined_score,candidates[i].score)+support_bonus;
         clusters[target].state=MSZZ_CLUSTER_STRENGTHENED;

         int current_priority=OwnerPriority(clusters[target].owner_strategy_id);
         int candidate_priority=OwnerPriority(candidates[i].strategy_id);
         if(candidate_priority>current_priority ||
            (candidate_priority==current_priority && candidates[i].score>candidates[clusters[target].preferred_index].score))
         {
            clusters[target].preferred_index=i;
            clusters[target].owner_strategy_id=candidates[i].strategy_id;
            clusters[target].canonical_stop=candidates[i].stop;
         }
      }
      return cluster_count;
   }

   int SelectBest(const MSZZOpportunityCluster &clusters[],const int count) const
   {
      int best=-1;
      double best_score=-1.0e100;
      for(int i=0;i<count;i++)
      {
         if(!clusters[i].valid) continue;
         if(clusters[i].combined_score>best_score)
         {
            best_score=clusters[i].combined_score;
            best=i;
         }
      }
      return best;
   }
};

#endif