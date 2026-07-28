#ifndef __MSZZ_OPPORTUNITY_CLUSTER_ENGINE_MQH__
#define __MSZZ_OPPORTUNITY_CLUSTER_ENGINE_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>
#include <MultiSpeedZigZag/Core/CandidateHandoff.mqh>

class CMSZZOpportunityClusterEngine
{
private:
   string m_last_diagnostic;

   string LenPrefix(const string value) const
   {
      return StringFormat("%d:%s",StringLen(value),value);
   }

   bool IsAllDigits(const string s) const
   {
      int n=StringLen(s);
      if(n<=0) return false;
      for(int i=0;i<n;i++)
      {
         ushort c=StringGetCharacter(s,i);
         if(c<'0' || c>'9') return false;
      }
      return true;
   }

   bool DecodeField(const string id,int &pos,const bool is_last,string &value) const
   {
      int colon=StringFind(id,":",pos);
      if(colon<0) return false;
      string len_str=StringSubstr(id,pos,colon-pos);
      if(!IsAllDigits(len_str)) return false;
      int len=(int)StringToInteger(len_str);
      int value_start=colon+1;
      if(len<0 || value_start+len>StringLen(id)) return false;
      value=StringSubstr(id,value_start,len);
      pos=value_start+len;
      if(is_last)
      {
         if(pos!=StringLen(id)) return false;
      }
      else
      {
         if(pos>=StringLen(id) || StringSubstr(id,pos,1)!="|") return false;
         pos=pos+1;
      }
      return true;
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
         case MSZZ_STRAT_ALIGNED_FAST_PULLBACK: return 92;
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

   void AppendFamilyId(string &csv,const ENUM_MSZZ_STRATEGY_FAMILY id) const
   {
      string value=IntegerToString((int)id);
      if(csv=="") { csv=value; return; }
      string needle=","+value+",";
      string haystack=","+csv+",";
      if(StringFind(haystack,needle)<0) csv=csv+","+value;
   }

public:
   string LastDiagnostic() const { return m_last_diagnostic; }

   // Format (see DECISION_LOG.md D004): MSZZC1|<len>:<symbol>|<len>:<timeframe>|<len>:<direction>|<len>:<origin_type>|<len>:<origin_id>
   // Every field is length-prefixed so a "|" or ":" inside origin_id can never be
   // mistaken for a field delimiter. Do not construct or parse cluster IDs by ad hoc
   // string manipulation anywhere else -- always go through these two methods.
   string EncodeClusterId(const string symbol,const ENUM_TIMEFRAMES timeframe,
                          const ENUM_MSZZ_DIRECTION direction,const ENUM_MSZZ_ORIGIN_TYPE origin_type,
                          const string origin_id) const
   {
      return "MSZZC1|"+LenPrefix(symbol)+"|"+LenPrefix(IntegerToString((int)timeframe))+"|"+
             LenPrefix(IntegerToString((int)direction))+"|"+LenPrefix(IntegerToString((int)origin_type))+"|"+
             LenPrefix(origin_id);
   }

   bool DecodeClusterId(const string id,string &symbol,int &timeframe,int &direction,int &origin_type,string &origin_id) const
   {
      string prefix="MSZZC1|";
      int prefix_len=StringLen(prefix);
      if(StringLen(id)<prefix_len || StringSubstr(id,0,prefix_len)!=prefix) return false;

      int pos=prefix_len;
      string tf_str,dir_str,ot_str;
      if(!DecodeField(id,pos,false,symbol)) return false;
      if(!DecodeField(id,pos,false,tf_str)) return false;
      if(!DecodeField(id,pos,false,dir_str)) return false;
      if(!DecodeField(id,pos,false,ot_str)) return false;
      if(!DecodeField(id,pos,true,origin_id)) return false;

      timeframe=(int)StringToInteger(tf_str);
      direction=(int)StringToInteger(dir_str);
      origin_type=(int)StringToInteger(ot_str);
      return true;
   }

   int Build(const string symbol,const ENUM_TIMEFRAMES timeframe,const MSZZCandidate &candidates[],
             const int candidate_count,MSZZOpportunityCluster &clusters[])
   {
      ArrayResize(clusters,0);
      m_last_diagnostic="";
      if(!CMSZZCandidateHandoff::ValidateCollection(candidates,candidate_count,m_last_diagnostic))
         return -1;
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
            ZeroMemory(clusters[target]);
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
            clusters[target].supporting_family_ids=IntegerToString((int)candidates[i].family_id);
            clusters[target].cluster_id=EncodeClusterId(symbol,timeframe,candidates[i].direction,
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
         AppendFamilyId(clusters[target].supporting_family_ids,candidates[i].family_id);

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
