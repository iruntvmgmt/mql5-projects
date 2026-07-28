//+------------------------------------------------------------------+
//| Test_MSZZ_Clusters.mq5                                           |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>

void InitCandidate(MSZZCandidate &c,const ENUM_MSZZ_STRATEGY_ID strategy,const double score,
                   const string origin,const string event_id,const double stop,const int evidence)
{
   ZeroMemory(c);
   c.valid=true;
   c.strategy_id=strategy;
   c.family_id=(strategy==MSZZ_STRAT_NESTED_PULLBACK ? MSZZ_FAMILY_PULLBACK :
                strategy==MSZZ_STRAT_WEIGHTED_ENSEMBLE ? MSZZ_FAMILY_ENSEMBLE :
                MSZZ_FAMILY_BREAKOUT);
   c.direction=MSZZ_DIR_LONG;
   c.origin_type=MSZZ_ORIGIN_FAST_BREAK;
   c.signal_time=D'2026.01.01 10:00';
   c.expiry_time=0;
   c.entry=100.0;
   c.stop=stop;
   c.target=110.0;
   c.score=score;
   c.supporting_models=1;
   c.evidence_mask=evidence;
   c.setup_name="";
   c.origin_id=origin;
   c.event_id=event_id;
   c.reason="";
}

void AssertTrue(const bool condition,const string message,int &failures)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); failures++; }
}

void TestClusterIdEncoding(int &failures)
{
   CMSZZOpportunityClusterEngine engine;

   // origin ID containing "|"
   {
      string symbol,origin_id; int tf,dir,ot;
      string encoded=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_SHORT,MSZZ_ORIGIN_MEDIUM_BREAK,"A|B|C");
      bool ok=engine.DecodeClusterId(encoded,symbol,tf,dir,ot,origin_id);
      AssertTrue(ok && origin_id=="A|B|C","origin ID containing '|' round-trips exactly",failures);
      AssertTrue(ok && symbol=="XAUUSD" && tf==(int)PERIOD_M5 && dir==(int)MSZZ_DIR_SHORT && ot==(int)MSZZ_ORIGIN_MEDIUM_BREAK,
                 "origin ID containing '|' preserves symbol/timeframe/direction/origin_type",failures);
   }

   // origin ID containing ":"
   {
      string symbol,origin_id; int tf,dir,ot;
      string encoded=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,"12:34:56");
      bool ok=engine.DecodeClusterId(encoded,symbol,tf,dir,ot,origin_id);
      AssertTrue(ok && origin_id=="12:34:56","origin ID containing ':' round-trips exactly",failures);
   }

   // origin ID with both, mirroring a real nested breakout/pivot ID (the exact defect class this fix addresses)
   {
      string symbol,origin_id; int tf,dir,ot;
      string nested="BO|XAUUSD|5|1|S|1784639100|MSZZ|XAUUSD|5|1|-1|1784637600|1784638200";
      string encoded=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_SHORT,MSZZ_ORIGIN_MEDIUM_BREAK,nested);
      bool ok=engine.DecodeClusterId(encoded,symbol,tf,dir,ot,origin_id);
      AssertTrue(ok && origin_id==nested,"real-world nested pipe-delimited origin ID round-trips exactly",failures);
      int pipe_count=0;
      for(int i=0;i<StringLen(encoded);i++) if(StringGetCharacter(encoded,i)=='|') pipe_count++;
      int naive_token_count=pipe_count+1;
      // The origin ID alone contributes 11 "|" characters, so a naive split-on-"|" parser
      // would see far more than the 6 tokens the old five-field format implied -- proving
      // exactly the ambiguity this format fixes. Correct decoding never splits blindly on
      // "|"; it only ever consumes the length declared by each field's prefix.
      AssertTrue(naive_token_count>6,"naive split-on-'|' would be ambiguous, confirming length-prefix decoding is required",failures);
   }

   // empty origin ID
   {
      string symbol,origin_id; int tf,dir,ot;
      string encoded=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,"");
      bool ok=engine.DecodeClusterId(encoded,symbol,tf,dir,ot,origin_id);
      AssertTrue(ok && origin_id=="","empty origin ID round-trips to an empty string",failures);
   }

   // invalid / malformed encoded strings must fail to decode, not silently parse
   {
      string symbol,origin_id; int tf,dir,ot;
      AssertTrue(!engine.DecodeClusterId("",symbol,tf,dir,ot,origin_id),"empty string is not a valid cluster ID",failures);
      AssertTrue(!engine.DecodeClusterId("MSZZC|XAUUSD|5|-1|2|BO|XAUUSD|5|1|S|1|MSZZ|XAUUSD|5|1|-1|2|3",
                 symbol,tf,dir,ot,origin_id),"legacy unversioned format is rejected, not silently accepted as new format",failures);
      AssertTrue(!engine.DecodeClusterId("MSZZC1|6:XAUUSD|1:5|2:-1|1:2|999:short",
                 symbol,tf,dir,ot,origin_id),"declared length exceeding available data is rejected",failures);
      AssertTrue(!engine.DecodeClusterId("MSZZC1|X:XAUUSD|1:5|2:-1|1:2|3:abc",
                 symbol,tf,dir,ot,origin_id),"non-digit length prefix is rejected",failures);
      AssertTrue(!engine.DecodeClusterId("MSZZC1|6:XAUUSD|1:5|2:-1|1:2|3:abcXX",
                 symbol,tf,dir,ot,origin_id),"trailing garbage after the declared final-field length is rejected",failures);
   }

   // long origin ID
   {
      string long_origin="";
      for(int i=0;i<50;i++) long_origin+="0123456789";
      string symbol,origin_id; int tf,dir,ot;
      string encoded=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,long_origin);
      bool ok=engine.DecodeClusterId(encoded,symbol,tf,dir,ot,origin_id);
      AssertTrue(ok && origin_id==long_origin && StringLen(origin_id)==500,"500-character origin ID round-trips exactly",failures);
   }

   // deterministic output
   {
      string a=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,"SAME|ORIGIN:X");
      string b=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,"SAME|ORIGIN:X");
      AssertTrue(a==b,"identical inputs encode to identical output every time",failures);
   }

   // distinct origins producing distinct cluster IDs
   {
      string a=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,"ORIGIN_A");
      string b=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_LONG,MSZZ_ORIGIN_FAST_BREAK,"ORIGIN_B");
      string c=engine.EncodeClusterId("XAUUSD",PERIOD_M5,MSZZ_DIR_SHORT,MSZZ_ORIGIN_FAST_BREAK,"ORIGIN_A");
      AssertTrue(a!=b,"distinct origin IDs produce distinct cluster IDs",failures);
      AssertTrue(a!=c,"distinct directions with the same origin ID produce distinct cluster IDs",failures);
   }
}

void OnStart()
{
   int failures=0;
   TestClusterIdEncoding(failures);

   MSZZCandidate candidates[];
   ArrayResize(candidates,4);

   InitCandidate(candidates[0],MSZZ_STRAT_FAST_BREAKOUT,4.0,"FAST_ORIGIN_1","E1",95.0,MSZZ_EVIDENCE_TRIGGER);
   InitCandidate(candidates[1],MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT,6.3,"FAST_ORIGIN_1","E2",95.0,
                 MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT);
   InitCandidate(candidates[2],MSZZ_STRAT_NESTED_PULLBACK,8.4,"FAST_ORIGIN_1","E3",94.5,
                 MSZZ_EVIDENCE_TRIGGER|MSZZ_EVIDENCE_CONTEXT|MSZZ_EVIDENCE_STRUCTURE);
   InitCandidate(candidates[3],MSZZ_STRAT_MEDIUM_BREAKOUT,5.5,"MED_ORIGIN_2","E4",96.0,MSZZ_EVIDENCE_TRIGGER);

   CMSZZOpportunityClusterEngine engine;
   MSZZOpportunityCluster clusters[];
   int count=engine.Build("XAUUSD",PERIOD_M5,candidates,ArraySize(candidates),clusters);

   AssertTrue(count==2,"three related candidates become one cluster and independent origin stays separate",failures);
   AssertTrue(clusters[0].support_count==3,"support count preserved",failures);
   AssertTrue(clusters[0].owner_strategy_id==MSZZ_STRAT_NESTED_PULLBACK,"specific nested pullback owns cluster",failures);
   AssertTrue((clusters[0].evidence_mask & MSZZ_EVIDENCE_STRUCTURE)!=0,"evidence mask merges structure evidence",failures);
   AssertTrue(clusters[0].stop_disagreement>0.0,"stop disagreement measured",failures);
   AssertTrue(clusters[0].cluster_id!="","stable cluster ID created",failures);

   int best=engine.SelectBest(clusters,count);
   AssertTrue(best>=0,"best cluster selected",failures);
   if(best>=0) AssertTrue(clusters[best].origin_id=="FAST_ORIGIN_1","stronger related cluster selected",failures);

   PrintFormat("MSZZ cluster test complete failures=%d",failures);
}
