#ifndef __MSZZ_EXECUTION_INTENT_STORE_MQH__
#define __MSZZ_EXECUTION_INTENT_STORE_MQH__

// See DECISION_LOG.md D007. This is a persistence component only; it is not
// wired into MultiSpeedZigZagEA.mq5's execution path yet (that is a separate,
// later decision -- Phase 2/3 of the execution-safety engineering plan).

#define MSZZ_INTENT_SCHEMA_VERSION 1

enum ENUM_MSZZ_INTENT_STATE
{
   MSZZ_INTENT_CREATED = 0,
   MSZZ_INTENT_PERSISTED,
   MSZZ_INTENT_PREFLIGHT_PASSED,
   MSZZ_INTENT_SUBMISSION_STARTED,
   MSZZ_INTENT_BROKER_ACCEPTED,
   MSZZ_INTENT_BROKER_REJECTED,
   MSZZ_INTENT_RESULT_UNKNOWN,
   MSZZ_INTENT_PARTIALLY_FILLED,
   MSZZ_INTENT_FILLED,
   MSZZ_INTENT_POSITION_ACTIVE,
   MSZZ_INTENT_POSITION_CLOSED,
   MSZZ_INTENT_PROTECTION_FAILED,
   MSZZ_INTENT_RECOVERY_REQUIRED,
   MSZZ_INTENT_ABANDONED
};

string MSZZIntentStateText(const ENUM_MSZZ_INTENT_STATE s)
{
   switch(s)
   {
      case MSZZ_INTENT_CREATED:            return "INTENT_CREATED";
      case MSZZ_INTENT_PERSISTED:          return "INTENT_PERSISTED";
      case MSZZ_INTENT_PREFLIGHT_PASSED:   return "PREFLIGHT_PASSED";
      case MSZZ_INTENT_SUBMISSION_STARTED: return "SUBMISSION_STARTED";
      case MSZZ_INTENT_BROKER_ACCEPTED:    return "BROKER_ACCEPTED";
      case MSZZ_INTENT_BROKER_REJECTED:    return "BROKER_REJECTED";
      case MSZZ_INTENT_RESULT_UNKNOWN:     return "RESULT_UNKNOWN";
      case MSZZ_INTENT_PARTIALLY_FILLED:   return "PARTIALLY_FILLED";
      case MSZZ_INTENT_FILLED:             return "FILLED";
      case MSZZ_INTENT_POSITION_ACTIVE:    return "POSITION_ACTIVE";
      case MSZZ_INTENT_POSITION_CLOSED:    return "POSITION_CLOSED";
      case MSZZ_INTENT_PROTECTION_FAILED:  return "PROTECTION_FAILED";
      case MSZZ_INTENT_RECOVERY_REQUIRED:  return "RECOVERY_REQUIRED";
      case MSZZ_INTENT_ABANDONED:          return "ABANDONED";
      default:                             return "UNKNOWN";
   }
}

// D009: a short, deterministic correlation token for the broker trade comment.
// A full intent/cluster ID (which can exceed 70 characters, see D004) does not
// fit MT5's comment length limit, so this is a fallback correlation signal for
// reconciliation, not a primary key -- order_ticket/position_ticket, recorded
// locally at submission time, are always tried first. Same FNV-1a algorithm as
// the store's own corruption checksum, exposed here as a free function since
// both the EA (to set the comment) and the reconciler (to match it back) need it.
string MSZZCorrelationToken(const string intent_id)
{
   uint h=2166136261;
   int n=StringLen(intent_id);
   for(int i=0;i<n;i++) { h^=(uint)StringGetCharacter(intent_id,i); h*=16777619; }
   return StringFormat("%08X",h);
}

struct MSZZExecutionIntent
{
   int      schema_version;
   string   intent_id;
   string   cluster_id;
   string   origin_id;
   int      strategy_id;
   string   symbol;
   int      timeframe;
   long     magic;
   int      direction;
   datetime signal_time;
   datetime intent_time;
   datetime expiry_time;
   double   requested_volume;
   double   requested_entry;
   double   requested_stop;
   double   requested_target;
   int      execution_state;
   int      submission_attempts;
   uint     broker_retcode;
   string   broker_result_text;
   ulong    order_ticket;
   ulong    position_ticket;
   ulong    first_deal_ticket;
   ulong    last_deal_ticket;
   double   filled_volume;
   double   average_fill_price;
   datetime last_reconciliation_time;
   int      protection_status;
   string   instance_id;
};

class CMSZZExecutionIntentStore
{
private:
   MSZZExecutionIntent m_intents[];
   string              m_unknown_lines[];
   string              m_primary_file;
   string              m_backup_file;
   string              m_temp_file;
   string              m_lock_file;
   string              m_instance_id;
   int                 m_lock_handle;
   string              m_last_error;

   //--- length-prefix primitives (same proven pattern as DECISION_LOG.md D004) ---

   string LenPrefix(const string value) const { return StringFormat("%d:%s",StringLen(value),value); }

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

   bool DecodeField(const string line,int &pos,const bool is_last,string &value) const
   {
      int colon=StringFind(line,":",pos);
      if(colon<0) return false;
      string len_str=StringSubstr(line,pos,colon-pos);
      if(!IsAllDigits(len_str)) return false;
      int len=(int)StringToInteger(len_str);
      int value_start=colon+1;
      if(len<0 || value_start+len>StringLen(line)) return false;
      value=StringSubstr(line,value_start,len);
      pos=value_start+len;
      if(is_last)
      {
         if(pos!=StringLen(line)) return false;
      }
      else
      {
         if(pos>=StringLen(line) || StringSubstr(line,pos,1)!="|") return false;
         pos=pos+1;
      }
      return true;
   }

   //--- FNV-1a 32-bit corruption-detection checksum (explicitly non-cryptographic) ---

   uint Fnv1a(const string payload) const
   {
      uint h=2166136261;
      int n=StringLen(payload);
      for(int i=0;i<n;i++)
      {
         h^=(uint)StringGetCharacter(payload,i);
         h*=16777619;
      }
      return h;
   }

   string ChecksumOf(const string payload) const { return StringFormat("%08X",Fnv1a(payload)); }

   //--- typed-field string conversion helpers ---

   string I(const long v) const { return IntegerToString(v); }
   string U(const ulong v) const { return StringFormat("%I64u",v); }
   string Dbl(const double v) const { return DoubleToString(v,8); }
   string T(const datetime v) const { return IntegerToString((long)v); }

   //--- record encode/decode ---

   string EncodeRecord(const MSZZExecutionIntent &r) const
   {
      string payload="MSZZI1"
         +"|"+LenPrefix(I(r.schema_version))
         +"|"+LenPrefix(r.intent_id)
         +"|"+LenPrefix(r.cluster_id)
         +"|"+LenPrefix(r.origin_id)
         +"|"+LenPrefix(I(r.strategy_id))
         +"|"+LenPrefix(r.symbol)
         +"|"+LenPrefix(I(r.timeframe))
         +"|"+LenPrefix(I(r.magic))
         +"|"+LenPrefix(I(r.direction))
         +"|"+LenPrefix(T(r.signal_time))
         +"|"+LenPrefix(T(r.intent_time))
         +"|"+LenPrefix(T(r.expiry_time))
         +"|"+LenPrefix(Dbl(r.requested_volume))
         +"|"+LenPrefix(Dbl(r.requested_entry))
         +"|"+LenPrefix(Dbl(r.requested_stop))
         +"|"+LenPrefix(Dbl(r.requested_target))
         +"|"+LenPrefix(I(r.execution_state))
         +"|"+LenPrefix(I(r.submission_attempts))
         +"|"+LenPrefix(I((long)r.broker_retcode))
         +"|"+LenPrefix(r.broker_result_text)
         +"|"+LenPrefix(U(r.order_ticket))
         +"|"+LenPrefix(U(r.position_ticket))
         +"|"+LenPrefix(U(r.first_deal_ticket))
         +"|"+LenPrefix(U(r.last_deal_ticket))
         +"|"+LenPrefix(Dbl(r.filled_volume))
         +"|"+LenPrefix(Dbl(r.average_fill_price))
         +"|"+LenPrefix(T(r.last_reconciliation_time))
         +"|"+LenPrefix(I(r.protection_status))
         +"|"+LenPrefix(r.instance_id);
      return payload+"|"+LenPrefix(ChecksumOf(payload));
   }

   bool DecodeRecord(const string line,MSZZExecutionIntent &out,int &schema_out) const
   {
      string prefix="MSZZI1|";
      int prefix_len=StringLen(prefix);
      if(StringLen(line)<prefix_len || StringSubstr(line,0,prefix_len)!=prefix) return false;

      int pos=prefix_len;
      string f_schema,f_intent_id,f_cluster_id,f_origin_id,f_strategy_id,f_symbol,f_timeframe,f_magic,
             f_direction,f_signal_time,f_intent_time,f_expiry_time,f_req_vol,f_req_entry,f_req_stop,
             f_req_target,f_exec_state,f_attempts,f_retcode,f_result_text,f_order_ticket,f_position_ticket,
             f_first_deal,f_last_deal,f_filled_vol,f_avg_price,f_last_recon,f_protection,f_instance;

      if(!DecodeField(line,pos,false,f_schema)) return false;
      if(!DecodeField(line,pos,false,f_intent_id)) return false;
      if(!DecodeField(line,pos,false,f_cluster_id)) return false;
      if(!DecodeField(line,pos,false,f_origin_id)) return false;
      if(!DecodeField(line,pos,false,f_strategy_id)) return false;
      if(!DecodeField(line,pos,false,f_symbol)) return false;
      if(!DecodeField(line,pos,false,f_timeframe)) return false;
      if(!DecodeField(line,pos,false,f_magic)) return false;
      if(!DecodeField(line,pos,false,f_direction)) return false;
      if(!DecodeField(line,pos,false,f_signal_time)) return false;
      if(!DecodeField(line,pos,false,f_intent_time)) return false;
      if(!DecodeField(line,pos,false,f_expiry_time)) return false;
      if(!DecodeField(line,pos,false,f_req_vol)) return false;
      if(!DecodeField(line,pos,false,f_req_entry)) return false;
      if(!DecodeField(line,pos,false,f_req_stop)) return false;
      if(!DecodeField(line,pos,false,f_req_target)) return false;
      if(!DecodeField(line,pos,false,f_exec_state)) return false;
      if(!DecodeField(line,pos,false,f_attempts)) return false;
      if(!DecodeField(line,pos,false,f_retcode)) return false;
      if(!DecodeField(line,pos,false,f_result_text)) return false;
      if(!DecodeField(line,pos,false,f_order_ticket)) return false;
      if(!DecodeField(line,pos,false,f_position_ticket)) return false;
      if(!DecodeField(line,pos,false,f_first_deal)) return false;
      if(!DecodeField(line,pos,false,f_last_deal)) return false;
      if(!DecodeField(line,pos,false,f_filled_vol)) return false;
      if(!DecodeField(line,pos,false,f_avg_price)) return false;
      if(!DecodeField(line,pos,false,f_last_recon)) return false;
      if(!DecodeField(line,pos,false,f_protection)) return false;
      if(!DecodeField(line,pos,false,f_instance)) return false;

      int payload_end=pos-1;
      if(payload_end<0 || StringSubstr(line,payload_end,1)!="|") return false;
      string payload=StringSubstr(line,0,payload_end);

      string f_checksum;
      if(!DecodeField(line,pos,true,f_checksum)) return false;
      if(f_checksum!=ChecksumOf(payload)) return false;

      schema_out=(int)StringToInteger(f_schema);
      if(schema_out!=MSZZ_INTENT_SCHEMA_VERSION) return true; // caller preserves as unknown-schema line

      out.schema_version=schema_out;
      out.intent_id=f_intent_id;
      out.cluster_id=f_cluster_id;
      out.origin_id=f_origin_id;
      out.strategy_id=(int)StringToInteger(f_strategy_id);
      out.symbol=f_symbol;
      out.timeframe=(int)StringToInteger(f_timeframe);
      out.magic=StringToInteger(f_magic);
      out.direction=(int)StringToInteger(f_direction);
      out.signal_time=(datetime)StringToInteger(f_signal_time);
      out.intent_time=(datetime)StringToInteger(f_intent_time);
      out.expiry_time=(datetime)StringToInteger(f_expiry_time);
      out.requested_volume=StringToDouble(f_req_vol);
      out.requested_entry=StringToDouble(f_req_entry);
      out.requested_stop=StringToDouble(f_req_stop);
      out.requested_target=StringToDouble(f_req_target);
      out.execution_state=(int)StringToInteger(f_exec_state);
      out.submission_attempts=(int)StringToInteger(f_attempts);
      out.broker_retcode=(uint)StringToInteger(f_retcode);
      out.broker_result_text=f_result_text;
      out.order_ticket=(ulong)StringToInteger(f_order_ticket);
      out.position_ticket=(ulong)StringToInteger(f_position_ticket);
      out.first_deal_ticket=(ulong)StringToInteger(f_first_deal);
      out.last_deal_ticket=(ulong)StringToInteger(f_last_deal);
      out.filled_volume=StringToDouble(f_filled_vol);
      out.average_fill_price=StringToDouble(f_avg_price);
      out.last_reconciliation_time=(datetime)StringToInteger(f_last_recon);
      out.protection_status=(int)StringToInteger(f_protection);
      out.instance_id=f_instance;
      return true;
   }

   //--- file-level load/save ---

   bool LoadFile(const string filename,MSZZExecutionIntent &out_intents[],string &out_unknown[]) const
   {
      ArrayResize(out_intents,0);
      ArrayResize(out_unknown,0);
      int h=FileOpen(filename,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return false;

      string header=FileReadString(h);
      StringTrimLeft(header); StringTrimRight(header);
      string prefix="MSZZI_HEADER|";
      if(StringLen(header)<StringLen(prefix) || StringSubstr(header,0,StringLen(prefix))!=prefix)
      { FileClose(h); return false; }

      int pos=StringLen(prefix);
      string f_schema,f_count;
      if(!DecodeField(header,pos,false,f_schema)) { FileClose(h); return false; }
      if(!DecodeField(header,pos,true,f_count)) { FileClose(h); return false; }
      if(!IsAllDigits(f_count)) { FileClose(h); return false; }
      int declared_count=(int)StringToInteger(f_count);
      if(declared_count<0) { FileClose(h); return false; }

      int loaded=0;
      string seen_ids[];
      while(!FileIsEnding(h) && loaded<declared_count)
      {
         string line=FileReadString(h);
         StringTrimLeft(line); StringTrimRight(line);
         if(line=="") { FileClose(h); return false; }

         MSZZExecutionIntent rec;
         int schema=0;
         if(!DecodeRecord(line,rec,schema)) { FileClose(h); return false; }

         if(schema!=MSZZ_INTENT_SCHEMA_VERSION)
         {
            int un=ArraySize(out_unknown);
            ArrayResize(out_unknown,un+1);
            out_unknown[un]=line;
            loaded++;
            continue;
         }

         for(int i=0;i<ArraySize(seen_ids);i++)
            if(seen_ids[i]==rec.intent_id) { FileClose(h); return false; }
         int sn=ArraySize(seen_ids);
         ArrayResize(seen_ids,sn+1);
         seen_ids[sn]=rec.intent_id;

         int n=ArraySize(out_intents);
         ArrayResize(out_intents,n+1);
         out_intents[n]=rec;
         loaded++;
      }
      FileClose(h);
      if(loaded!=declared_count) return false;
      return true;
   }

   bool WriteFile(const string filename,const MSZZExecutionIntent &intents[],const string &unknown[]) const
   {
      int h=FileOpen(filename,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(h==INVALID_HANDLE) return false;
      int total=ArraySize(intents)+ArraySize(unknown);
      FileWriteString(h,"MSZZI_HEADER|"+LenPrefix(I(MSZZ_INTENT_SCHEMA_VERSION))+"|"+LenPrefix(I(total))+"\r\n");
      for(int i=0;i<ArraySize(intents);i++)
         FileWriteString(h,EncodeRecord(intents[i])+"\r\n");
      for(int i=0;i<ArraySize(unknown);i++)
         FileWriteString(h,unknown[i]+"\r\n");
      FileFlush(h);
      FileClose(h);
      return true;
   }

   bool RecordsMatch(const MSZZExecutionIntent &a,const MSZZExecutionIntent &b) const
   {
      return EncodeRecord(a)==EncodeRecord(b);
   }

   //--- the persistence protocol itself (see D007 for the exact guarantee) ---

   bool SaveAll()
   {
      m_last_error="";
      if(!WriteFile(m_temp_file,m_intents,m_unknown_lines))
      { m_last_error="temp write failed file="+m_temp_file+" error="+IntegerToString(GetLastError()); return false; }

      MSZZExecutionIntent verify_intents[]; string verify_unknown[];
      if(!LoadFile(m_temp_file,verify_intents,verify_unknown))
      { m_last_error="temp verify failed"; return false; }
      if(ArraySize(verify_intents)!=ArraySize(m_intents) || ArraySize(verify_unknown)!=ArraySize(m_unknown_lines))
      { m_last_error="temp verify count mismatch"; return false; }
      for(int i=0;i<ArraySize(m_intents);i++)
         if(!RecordsMatch(verify_intents[i],m_intents[i]))
         { m_last_error="temp verify content mismatch"; return false; }

      if(FileIsExist(m_primary_file))
      {
         if(!FileMove(m_primary_file,0,m_backup_file,FILE_REWRITE))
         { m_last_error="backup rotation failed error="+IntegerToString(GetLastError()); return false; }
      }

      if(!FileMove(m_temp_file,0,m_primary_file,FILE_REWRITE))
      { m_last_error="primary replace failed error="+IntegerToString(GetLastError()); return false; }

      MSZZExecutionIntent final_intents[]; string final_unknown[];
      if(!LoadFile(m_primary_file,final_intents,final_unknown))
      { m_last_error="post-replace verify failed"; return false; }
      if(ArraySize(final_intents)!=ArraySize(m_intents) || ArraySize(final_unknown)!=ArraySize(m_unknown_lines))
      { m_last_error="post-replace verify count mismatch"; return false; }
      for(int i=0;i<ArraySize(m_intents);i++)
         if(!RecordsMatch(final_intents[i],m_intents[i]))
         { m_last_error="post-replace verify content mismatch"; return false; }

      return true;
   }

   int FindIndexById(const string intent_id) const
   {
      for(int i=0;i<ArraySize(m_intents);i++)
         if(m_intents[i].intent_id==intent_id) return i;
      return -1;
   }

   // MQL5's generic ArrayCopy()/whole-array "=" do not support struct arrays
   // containing string members (compiler error 368: "structures or classes
   // containing objects are not allowed"), even though single-struct
   // assignment with strings works fine. Copy element-by-element instead.
   void CopyIntents(MSZZExecutionIntent &dst[],const MSZZExecutionIntent &src[]) const
   {
      int n=ArraySize(src);
      ArrayResize(dst,n);
      for(int i=0;i<n;i++) dst[i]=src[i];
   }

   void CopyStrings(string &dst[],const string &src[]) const
   {
      int n=ArraySize(src);
      ArrayResize(dst,n);
      for(int i=0;i<n;i++) dst[i]=src[i];
   }

public:
   CMSZZExecutionIntentStore(void)
   {
      m_primary_file=""; m_backup_file=""; m_temp_file=""; m_lock_file="";
      m_instance_id=""; m_lock_handle=INVALID_HANDLE; m_last_error="";
      ArrayResize(m_intents,0); ArrayResize(m_unknown_lines,0);
   }

   ~CMSZZExecutionIntentStore(void) { Close(); }

   void Close()
   {
      if(m_lock_handle!=INVALID_HANDLE) { FileClose(m_lock_handle); m_lock_handle=INVALID_HANDLE; }
   }

   bool Configure(const string symbol,const ENUM_TIMEFRAMES timeframe,const long magic,const string instance_id="")
   {
      Close();
      string safe_symbol=symbol;
      StringReplace(safe_symbol,"/","_");
      StringReplace(safe_symbol,"\\","_");
      StringReplace(safe_symbol,":","_");
      string base=StringFormat("MSZZ_Intents_%s_%d_%I64d",safe_symbol,(int)timeframe,magic);
      m_primary_file=base+".dat";
      m_backup_file=base+".bak";
      m_temp_file=base+".tmp";
      m_lock_file=base+".lock";
      m_instance_id=(instance_id!="" ? instance_id : StringFormat("%d-%d",(int)TimeLocal(),MathRand()));

      // Exclusivity: no share flags => this handle is the only one allowed on this
      // file anywhere, including a second store instance in the same process.
      m_lock_handle=FileOpen(m_lock_file,FILE_WRITE|FILE_READ|FILE_BIN);
      if(m_lock_handle==INVALID_HANDLE)
      {
         m_last_error=StringFormat("exclusivity lock failed file=%s error=%d",m_lock_file,GetLastError());
         return false;
      }
      FileWriteString(m_lock_handle,m_instance_id);
      FileFlush(m_lock_handle);
      ArrayResize(m_intents,0);
      ArrayResize(m_unknown_lines,0);
      return true;
   }

   bool Load()
   {
      m_last_error="";
      MSZZExecutionIntent intents[]; string unknown[];
      if(LoadFile(m_primary_file,intents,unknown))
      {
         CopyIntents(m_intents,intents); CopyStrings(m_unknown_lines,unknown);
         return true;
      }
      string primary_error="primary load failed";
      if(LoadFile(m_backup_file,intents,unknown))
      {
         CopyIntents(m_intents,intents); CopyStrings(m_unknown_lines,unknown);
         m_last_error="primary invalid, recovered from backup";
         return true;
      }
      if(!FileIsExist(m_primary_file) && !FileIsExist(m_backup_file))
      {
         ArrayResize(m_intents,0); ArrayResize(m_unknown_lines,0);
         return true; // first run: nothing to load is not an error
      }
      m_last_error="primary and backup both invalid";
      ArrayResize(m_intents,0); ArrayResize(m_unknown_lines,0);
      return false;
   }

   bool CreateIntent(const MSZZExecutionIntent &intent)
   {
      m_last_error="";
      if(FindIndexById(intent.intent_id)>=0)
      { m_last_error="duplicate intent_id "+intent.intent_id; return false; }

      MSZZExecutionIntent snapshot[];
      CopyIntents(snapshot,m_intents);
      int n=ArraySize(m_intents);
      ArrayResize(m_intents,n+1);
      m_intents[n]=intent;
      m_intents[n].schema_version=MSZZ_INTENT_SCHEMA_VERSION;

      if(!SaveAll())
      {
         CopyIntents(m_intents,snapshot); // rollback
         return false;
      }
      return true;
   }

   bool UpdateIntent(const MSZZExecutionIntent &intent)
   {
      m_last_error="";
      int idx=FindIndexById(intent.intent_id);
      if(idx<0) { m_last_error="unknown intent_id "+intent.intent_id; return false; }

      MSZZExecutionIntent snapshot[];
      CopyIntents(snapshot,m_intents);
      m_intents[idx]=intent;
      m_intents[idx].schema_version=MSZZ_INTENT_SCHEMA_VERSION;

      if(!SaveAll())
      {
         CopyIntents(m_intents,snapshot); // rollback
         return false;
      }
      return true;
   }

   bool FindById(const string intent_id,MSZZExecutionIntent &out) const
   {
      int idx=FindIndexById(intent_id);
      if(idx<0) return false;
      out=m_intents[idx];
      return true;
   }

   bool FindByClusterId(const string cluster_id,MSZZExecutionIntent &out) const
   {
      for(int i=0;i<ArraySize(m_intents);i++)
         if(m_intents[i].cluster_id==cluster_id) { out=m_intents[i]; return true; }
      return false;
   }

   int Count() const { return ArraySize(m_intents); }
   int UnknownRecordCount() const { return ArraySize(m_unknown_lines); }

   bool IntentAt(const int index,MSZZExecutionIntent &out) const
   {
      if(index<0 || index>=ArraySize(m_intents)) return false;
      out=m_intents[index];
      return true;
   }

   string LastError() const { return m_last_error; }
   string PrimaryFilename() const { return m_primary_file; }
   string BackupFilename() const { return m_backup_file; }
   string TempFilename() const { return m_temp_file; }
   string InstanceId() const { return m_instance_id; }
};

#endif
