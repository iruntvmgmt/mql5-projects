#ifndef __MSZZ_PARITY_EXPORTER_MQH__
#define __MSZZ_PARITY_EXPORTER_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

class CMSZZParityExporter
{
private:
   string m_prefix;
   string m_emitted_pivots[];
   string m_emitted_candidates[];
   string m_emitted_clusters[];

   bool Seen(const string &items[],const string key) const
   {
      for(int i=0;i<ArraySize(items);i++) if(items[i]==key) return true;
      return false;
   }

   void Remember(string &items[],const string key)
   {
      int n=ArraySize(items);
      ArrayResize(items,n+1);
      items[n]=key;
   }

   int OpenCsv(const string suffix,const string header)
   {
      string filename=m_prefix+"_"+suffix+".csv";
      int h=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
      if(h==INVALID_HANDLE)
      {
         PrintFormat("MSZZ parity export open failed file=%s error=%d",filename,GetLastError());
         return INVALID_HANDLE;
      }
      if(FileSize(h)==0 && header!="") FileWriteString(h,header+"\r\n");
      FileSeek(h,0,SEEK_END);
      return h;
   }

public:
   CMSZZParityExporter(void) { m_prefix="MSZZ_PARITY"; }

   void Configure(const string run_id)
   {
      string safe=run_id;
      StringReplace(safe,"/","_"); StringReplace(safe,"\\","_");
      StringReplace(safe,":","_"); StringReplace(safe,"|","_");
      m_prefix="MSZZ_PARITY_"+safe;
      ArrayResize(m_emitted_pivots,0);
      ArrayResize(m_emitted_candidates,0);
      ArrayResize(m_emitted_clusters,0);
   }

   bool WriteManifest(const string engine_version,const string commit_sha,const string symbol,
                      const ENUM_TIMEFRAMES timeframe,const datetime start_time,const datetime end_time,
                      const int fast_len,const double fast_mult,const int med_len,const double med_mult,
                      const int slow_len,const double slow_mult,const int min_spacing,
                      const string reversal_source,const string breakout_source,const string geometry_mode)
   {
      int h=OpenCsv("manifest","key;value"); if(h==INVALID_HANDLE) return false;
      FileWrite(h,"engine_version",engine_version); FileWrite(h,"commit_sha",commit_sha);
      FileWrite(h,"symbol",symbol); FileWrite(h,"timeframe",EnumToString(timeframe));
      FileWrite(h,"start_time",TimeToString(start_time,TIME_DATE|TIME_SECONDS));
      FileWrite(h,"end_time",TimeToString(end_time,TIME_DATE|TIME_SECONDS));
      FileWrite(h,"fast_atr_len",fast_len); FileWrite(h,"fast_atr_mult",DoubleToString(fast_mult,8));
      FileWrite(h,"medium_atr_len",med_len); FileWrite(h,"medium_atr_mult",DoubleToString(med_mult,8));
      FileWrite(h,"slow_atr_len",slow_len); FileWrite(h,"slow_atr_mult",DoubleToString(slow_mult,8));
      FileWrite(h,"min_pivot_spacing",min_spacing); FileWrite(h,"reversal_source",reversal_source);
      FileWrite(h,"breakout_source",breakout_source); FileWrite(h,"geometry_mode",geometry_mode);
      FileFlush(h); FileClose(h); return true;
   }

   bool WriteBar(const int bar_index,const MqlRates &bar,const double atr_fast,const double atr_med,const double atr_slow)
   {
      int h=OpenCsv("bars","bar_index;time;open;high;low;close;tick_volume;atr_fast;atr_medium;atr_slow");
      if(h==INVALID_HANDLE) return false;
      FileWrite(h,bar_index,(long)bar.time,DoubleToString(bar.open,_Digits),DoubleToString(bar.high,_Digits),
                DoubleToString(bar.low,_Digits),DoubleToString(bar.close,_Digits),(long)bar.tick_volume,
                DoubleToString(atr_fast,10),DoubleToString(atr_med,10),DoubleToString(atr_slow,10));
      FileClose(h); return true;
   }

   bool WritePivot(const string engine,const MSZZPivot &pivot)
   {
      if(!pivot.valid || pivot.id=="") return true;
      string key=engine+"|"+pivot.id;
      if(Seen(m_emitted_pivots,key)) return true;
      int h=OpenCsv("pivots","engine;speed;pivot_kind;pivot_shift;pivot_time;confirmed_time;price;structure_label;pivot_id");
      if(h==INVALID_HANDLE) return false;
      FileWrite(h,engine,(int)pivot.speed,(int)pivot.kind,pivot.pivot_shift,(long)pivot.pivot_time,
                (long)pivot.confirmed_time,DoubleToString(pivot.price,_Digits),MSZZStructureText(pivot.structure_label),pivot.id);
      FileClose(h); Remember(m_emitted_pivots,key); return true;
   }

   bool WriteSnapshot(const int bar_index,const datetime time,const MSZZSpeedSnapshot &s)
   {
      int h=OpenCsv("snapshots","bar_index;time;speed;leg_direction;atr;threshold;resistance;support;bullish_break;bearish_break;bullish_event_id;bearish_event_id");
      if(h==INVALID_HANDLE) return false;
      FileWrite(h,bar_index,(long)time,(int)s.speed,(int)s.leg_direction,DoubleToString(s.atr,10),
                DoubleToString(s.reversal_threshold,10),DoubleToString(s.resistance_now,_Digits),
                DoubleToString(s.support_now,_Digits),(int)s.bullish_break,(int)s.bearish_break,
                s.bullish_event_id,s.bearish_event_id);
      FileClose(h); return true;
   }

   bool WriteCandidate(const int bar_index,const MSZZCandidate &c)
   {
      if(!c.valid) return true;
      string key=IntegerToString(bar_index)+"|"+IntegerToString((int)c.strategy_id)+"|"+c.event_id;
      if(Seen(m_emitted_candidates,key)) return true;
      int h=OpenCsv("candidates","bar_index;time;strategy_id;direction;origin_type;origin_id;event_id;entry;stop;target;raw_score;evidence_mask;reason");
      if(h==INVALID_HANDLE) return false;
      FileWrite(h,bar_index,(long)c.signal_time,(int)c.strategy_id,(int)c.direction,(int)c.origin_type,c.origin_id,
                c.event_id,DoubleToString(c.entry,_Digits),DoubleToString(c.stop,_Digits),
                DoubleToString(c.target,_Digits),DoubleToString(c.score,4),c.evidence_mask,c.reason);
      FileClose(h); Remember(m_emitted_candidates,key); return true;
   }

   bool WriteCluster(const int bar_index,const datetime time,const MSZZOpportunityCluster &cluster)
   {
      if(!cluster.valid) return true;
      string key=IntegerToString(bar_index)+"|"+cluster.cluster_id;
      if(Seen(m_emitted_clusters,key)) return true;
      int h=OpenCsv("clusters","bar_index;time;cluster_id;direction;origin_type;origin_id;state;owner_strategy_id;supporting_strategy_ids;evidence_mask;combined_score;canonical_stop;expiry_time");
      if(h==INVALID_HANDLE) return false;
      FileWrite(h,bar_index,(long)time,cluster.cluster_id,(int)cluster.direction,(int)cluster.origin_type,
                cluster.origin_id,(int)cluster.state,(int)cluster.owner_strategy_id,cluster.supporting_strategy_ids,
                cluster.evidence_mask,DoubleToString(cluster.combined_score,4),
                DoubleToString(cluster.canonical_stop,_Digits),(long)cluster.expiry_time);
      FileClose(h); Remember(m_emitted_clusters,key); return true;
   }
};

#endif