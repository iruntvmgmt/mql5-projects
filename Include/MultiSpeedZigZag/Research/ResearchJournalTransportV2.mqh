#ifndef __MSZZ_RESEARCH_JOURNAL_TRANSPORT_V2_MQH__
#define __MSZZ_RESEARCH_JOURNAL_TRANSPORT_V2_MQH__

#include <MultiSpeedZigZag/Research/ResearchCandidateCsvV2.mqh>

#define MSZZ_RESEARCH_WRITER_V2 "MSZZ_RESEARCH_CSV_WRITER_V2"
#define MSZZ_RESEARCH_MANIFEST_V2 "MSZZ_RESEARCH_MANIFEST_V2"

struct MSZZResearchJournalManifestV2
{
   string manifest_version;
   string writer_version;
   string schema_version;
   string symbol;
   int    timeframe;
   long   row_count;
   string journal_sha256;
   string source_data_sha256;
};

class CMSZZResearchJournalTransportV2
{
private:
   static bool HexDigit(const ushort value)
   {
      return (value>='0' && value<='9') ||
             (value>='a' && value<='f') ||
             (value>='A' && value<='F');
   }

   static string Quote(const string value)
   {
      string escaped="";
      for(int i=0;i<StringLen(value);i++)
      {
         string character=StringSubstr(value,i,1);
         escaped+=(character=="\"" ? "\"\"" : character);
      }
      return "\""+escaped+"\"";
   }

   static string CanonicalRecord(const string &fields[])
   {
      string result="";
      for(int i=0;i<ArraySize(fields);i++)
      {
         if(i>0) result+=",";
         result+=Quote(fields[i]);
      }
      return result;
   }

   static bool ValidateUtf8(const uchar &data[],string &reason)
   {
      int size=ArraySize(data);
      if(size>=3 && data[0]==0xEF && data[1]==0xBB && data[2]==0xBF)
      {
         reason="UTF8_BOM_FORBIDDEN";
         return false;
      }
      for(int i=0;i<size;)
      {
         int b=(int)data[i];
         if(b<=0x7F) { i++; continue; }
         int need=0;
         uint code=0;
         if(b>=0xC2 && b<=0xDF) { need=1; code=(uint)(b&0x1F); }
         else if(b>=0xE0 && b<=0xEF) { need=2; code=(uint)(b&0x0F); }
         else if(b>=0xF0 && b<=0xF4) { need=3; code=(uint)(b&0x07); }
         else { reason="INVALID_UTF8"; return false; }
         if(i+need>=size) { reason="TRUNCATED_UTF8"; return false; }
         for(int j=1;j<=need;j++)
         {
            int continuation=(int)data[i+j];
            if((continuation&0xC0)!=0x80)
            { reason="INVALID_UTF8_CONTINUATION"; return false; }
            code=(code<<6)|(uint)(continuation&0x3F);
         }
         if((need==2 && code<0x800) || (need==3 && code<0x10000) ||
            (code>=0xD800 && code<=0xDFFF) || code>0x10FFFF)
         { reason="NONCANONICAL_UTF8"; return false; }
         i+=need+1;
      }
      return true;
   }

   static bool ReadBytes(const string file_name,uchar &data[],string &reason)
   {
      ArrayResize(data,0);
      int handle=FileOpen(file_name,FILE_READ|FILE_BIN|FILE_SHARE_READ);
      if(handle==INVALID_HANDLE) { reason="FILE_OPEN_FAILED"; return false; }
      ulong size=FileSize(handle);
      if(size>2147483647)
      {
         FileClose(handle);
         reason="INVALID_FILE_SIZE";
         return false;
      }
      ArrayResize(data,(int)size);
      uint read=(size>0 ? FileReadArray(handle,data,0,(uint)size) : 0);
      FileClose(handle);
      if((ulong)read!=size) { reason="FILE_READ_FAILED"; return false; }
      return true;
   }

   static bool SplitDocument(const string document,string &records[],string &reason)
   {
      ArrayResize(records,0);
      bool quoted=false;
      int start=0;
      int length=StringLen(document);
      for(int i=0;i<length;i++)
      {
         string character=StringSubstr(document,i,1);
         if(character=="\"")
         {
            if(quoted && i+1<length && StringSubstr(document,i+1,1)=="\"") i++;
            else quoted=!quoted;
            continue;
         }
         if(character=="\n" && !quoted)
         { reason="BARE_LF"; return false; }
         if(character=="\r" && !quoted)
         {
            if(i+1>=length || StringSubstr(document,i+1,1)!="\n")
            { reason="BARE_CR"; return false; }
            int count=ArraySize(records);
            ArrayResize(records,count+1);
            records[count]=StringSubstr(document,start,i-start);
            i++;
            start=i+1;
         }
      }
      if(quoted) { reason="UNCLOSED_QUOTE"; return false; }
      if(start<length)
      { reason="MISSING_FINAL_CRLF"; return false; }
      if(start==0 && length==0) { reason="EMPTY_DOCUMENT"; return false; }
      if(ArraySize(records)>0 && records[ArraySize(records)-1]=="")
      { reason="EMPTY_RECORD"; return false; }
      return true;
   }

   static bool Seen(const string value,const string &values[])
   {
      for(int i=0;i<ArraySize(values);i++)
         if(values[i]==value) return true;
      return false;
   }

   static bool IntegerExact(const string value,long &parsed)
   {
      if(value=="") return false;
      parsed=(long)StringToInteger(value);
      return StringFormat("%I64d",parsed)==value;
   }

   static bool DoubleExact(const string value,double &parsed)
   {
      if(value=="") return false;
      parsed=StringToDouble(value);
      return MathIsValidNumber(parsed) && DoubleToString(parsed,16)==value;
   }

   static bool OneOf(const string value,const string options)
   {
      return StringFind("|"+options+"|","|"+value+"|")>=0;
   }

   static bool EmptyRange(const string &fields[],const int first,const int last)
   {
      for(int i=first;i<=last;i++)
         if(fields[i]!="") return false;
      return true;
   }

   static bool ValidateExtensionPartition(const string &fields[],string &reason)
   {
      int family=(int)StringToInteger(fields[2]);
      bool structural=(family==9 || family==10 || family==12);
      if(structural==EmptyRange(fields,34,73))
      { reason="STRUCTURAL_PARTITION_MISMATCH"; return false; }
      int first[6]={74,80,87,94,102,108};
      int last[6] ={79,86,93,101,107,115};
      for(int i=0;i<6;i++)
      {
         bool owner=(family==8+i);
         if(!owner && !EmptyRange(fields,first[i],last[i]))
         { reason="UNEXPECTED_FAMILY_EXTENSION"; return false; }
      }
      return true;
   }

   static bool ValidateCommonFields(const string &fields[],string &reason)
   {
      long strategy=0,family=0,signal=0,expiry=0,arm=0,trigger=0,bars=0,spread=0;
      double entry=0.0,stop=0.0,target=0.0,score=0.0,atr_arm=0.0,atr_trigger=0.0;
      double stop_points=0.0,target_r=0.0,spread_ratio=0.0;
      if(!IntegerExact(fields[1],strategy) || strategy<=0 ||
         !IntegerExact(fields[2],family) || family<8 || family>13)
      { reason="INVALID_ID_ALLOCATION"; return false; }
      if(fields[3]=="" || fields[4]=="")
      { reason="MISSING_HYPOTHESIS_IDENTITY"; return false; }
      if(fields[8]!="BROKER_SERVER_RAW" ||
         fields[9]!=MSZZ_RESEARCH_RAW_BROKER_AUTHORITY_V2)
      { reason="UNSUPPORTED_TIME_AUTHORITY"; return false; }
      if(!IntegerExact(fields[10],signal) || !IntegerExact(fields[11],expiry) ||
         !IntegerExact(fields[20],arm) || !IntegerExact(fields[21],trigger) ||
         signal<=0 || signal!=trigger || arm<=0 || arm>trigger || expiry<=signal)
      { reason="INVALID_LIFECYCLE_TIME"; return false; }
      if(fields[12]!="LONG" && fields[12]!="SHORT")
      { reason="INVALID_DIRECTION"; return false; }
      if(!DoubleExact(fields[13],entry) || !DoubleExact(fields[14],stop) ||
         !DoubleExact(fields[15],target) || !DoubleExact(fields[16],score))
      { reason="INVALID_NUMBER"; return false; }
      if(entry<=0.0 || stop<=0.0 || target<=0.0)
      { reason="INVALID_GEOMETRY"; return false; }
      if((fields[12]=="LONG" && (stop>=entry || target<=entry)) ||
         (fields[12]=="SHORT" && (stop<=entry || target>=entry)))
      { reason="INVALID_DIRECTIONAL_GEOMETRY"; return false; }
      if(!OneOf(fields[17],"NONE|SESSION_RANGE|STRUCTURAL_EVENT|COMPRESSION_WINDOW|VALUE|RANGE"))
      { reason="INVALID_REFERENCE_TYPE"; return false; }
      if(fields[17]!="NONE" && fields[18]=="")
      { reason="INVALID_REFERENCE"; return false; }
      if(!IntegerExact(fields[22],bars) || bars<0 ||
         !OneOf(fields[23],"NONE|EXPIRED|INVALIDATED|EMITTED|SESSION_RESET|DAY_RESET") ||
         !OneOf(fields[24],"NONE|FRESH_CROSS|NEUTRAL|SESSION|DAY|NEW_STRUCTURE|NEW_EPISODE"))
      { reason="INVALID_STATE_FIELD"; return false; }
      if(!DoubleExact(fields[25],atr_arm) || !DoubleExact(fields[26],atr_trigger) ||
         !DoubleExact(fields[27],stop_points) || !DoubleExact(fields[28],target_r) ||
         !IntegerExact(fields[29],spread) || !DoubleExact(fields[30],spread_ratio) ||
         atr_arm<=0.0 || atr_trigger<=0.0 || stop_points<=0.0 ||
         target_r<=0.0 || spread<0 || spread_ratio<0.0)
      { reason="INVALID_DERIVED_FIELD"; return false; }
      if(fields[31]=="" || fields[32]=="")
      { reason="MISSING_CONTEXT_ID"; return false; }
      return true;
   }

   static ENUM_MSZZ_DIRECTION Direction(const string value)
   {
      if(value=="LONG") return MSZZ_DIR_LONG;
      if(value=="SHORT") return MSZZ_DIR_SHORT;
      return MSZZ_DIR_NONE;
   }

   static ENUM_MSZZ_RESEARCH_REFERENCE_V2 Reference(const string value)
   {
      if(value=="SESSION_RANGE") return MSZZ_RESEARCH_REFERENCE_SESSION_RANGE;
      if(value=="STRUCTURAL_EVENT") return MSZZ_RESEARCH_REFERENCE_STRUCTURAL_EVENT;
      if(value=="COMPRESSION_WINDOW") return MSZZ_RESEARCH_REFERENCE_COMPRESSION_WINDOW;
      if(value=="VALUE") return MSZZ_RESEARCH_REFERENCE_VALUE;
      if(value=="RANGE") return MSZZ_RESEARCH_REFERENCE_RANGE;
      return MSZZ_RESEARCH_REFERENCE_NONE;
   }

   static ENUM_MSZZ_RESEARCH_TERMINAL_STATE_V2 Terminal(const string value)
   {
      if(value=="EXPIRED") return MSZZ_RESEARCH_TERMINAL_EXPIRED;
      if(value=="INVALIDATED") return MSZZ_RESEARCH_TERMINAL_INVALIDATED;
      if(value=="EMITTED") return MSZZ_RESEARCH_TERMINAL_EMITTED;
      if(value=="SESSION_RESET") return MSZZ_RESEARCH_TERMINAL_SESSION_RESET;
      if(value=="DAY_RESET") return MSZZ_RESEARCH_TERMINAL_DAY_RESET;
      return MSZZ_RESEARCH_TERMINAL_NONE;
   }

   static ENUM_MSZZ_RESEARCH_RESET_V2 Reset(const string value)
   {
      if(value=="FRESH_CROSS") return MSZZ_RESEARCH_RESET_FRESH_CROSS;
      if(value=="NEUTRAL") return MSZZ_RESEARCH_RESET_NEUTRAL;
      if(value=="SESSION") return MSZZ_RESEARCH_RESET_SESSION;
      if(value=="DAY") return MSZZ_RESEARCH_RESET_DAY;
      if(value=="NEW_STRUCTURE") return MSZZ_RESEARCH_RESET_NEW_STRUCTURE;
      if(value=="NEW_EPISODE") return MSZZ_RESEARCH_RESET_NEW_EPISODE;
      return MSZZ_RESEARCH_RESET_NONE;
   }

   static ENUM_MSZZ_RESEARCH_VALUE_V2 ValueType(const string value)
   {
      if(value=="VWAP_SESSION") return MSZZ_RESEARCH_VALUE_VWAP_SESSION;
      if(value=="ALMA") return MSZZ_RESEARCH_VALUE_ALMA;
      return MSZZ_RESEARCH_VALUE_NONE;
   }

   static bool ReconstructCandidate(const string &f[],MSZZResearchCandidateV2 &c,
                                    string &reason)
   {
      CMSZZResearchCandidateSchemaV2::Initialize(c);
      c.strategy_id=(int)StringToInteger(f[1]); c.family_id=(int)StringToInteger(f[2]);
      c.hypothesis_version=f[3]; c.canonical_variant_id=f[4];
      c.origin_id=f[5]; c.sequence_id=f[6]; c.event_id=f[7];
      c.clock_domain=MSZZ_RESEARCH_CLOCK_BROKER_SERVER_RAW;
      c.time_authority_id=f[9];
      c.signal_time=(datetime)StringToInteger(f[10]);
      c.expiry_time=(datetime)StringToInteger(f[11]);
      c.direction=Direction(f[12]);
      c.entry=StringToDouble(f[13]); c.stop=StringToDouble(f[14]);
      c.target=StringToDouble(f[15]); c.score=StringToDouble(f[16]);
      c.reference_type=Reference(f[17]); c.reference_id=f[18];
      c.reference_price=StringToDouble(f[19]);
      c.arm_time=(datetime)StringToInteger(f[20]);
      c.trigger_time=(datetime)StringToInteger(f[21]);
      c.bars_armed=(int)StringToInteger(f[22]);
      c.terminal_prior_state=Terminal(f[23]); c.reset_classification=Reset(f[24]);
      c.atr_at_arm=StringToDouble(f[25]); c.atr_at_trigger=StringToDouble(f[26]);
      c.stop_distance_points=StringToDouble(f[27]); c.target_r=StringToDouble(f[28]);
      c.spread_points=(int)StringToInteger(f[29]);
      c.spread_to_risk_ratio=StringToDouble(f[30]);
      c.session_id=f[31]; c.regime_id=f[32]; c.diagnostic_json=f[33];

      if(f[34]!="")
      {
         c.structural_binding.bound=true;
         MSZZStructuralEventRecord r;
         CMSZZStructuralEventPolicy::Blank(r);
         r.valid=true; r.validation_reason="OK"; r.event_id=f[34];
         r.speed=(ENUM_MSZZ_SPEED)StringToInteger(f[35]);
         r.direction=Direction(f[36]); r.event_time=(datetime)StringToInteger(f[37]);
         r.previous_bar_time=(datetime)StringToInteger(f[38]);
         r.source_origin_pivot_id=f[39];
         r.source_origin_pivot_speed=(ENUM_MSZZ_SPEED)StringToInteger(f[40]);
         r.source_origin_pivot_kind=(ENUM_MSZZ_PIVOT_KIND)StringToInteger(f[41]);
         r.source_origin_price=StringToDouble(f[42]);
         r.source_origin_pivot_time=(datetime)StringToInteger(f[43]);
         r.source_origin_confirmation_time=(datetime)StringToInteger(f[44]);
         r.broken_pivot_id=f[45];
         r.broken_pivot_speed=(ENUM_MSZZ_SPEED)StringToInteger(f[46]);
         r.broken_pivot_kind=(ENUM_MSZZ_PIVOT_KIND)StringToInteger(f[47]);
         r.broken_pivot_price=StringToDouble(f[48]);
         r.broken_pivot_time=(datetime)StringToInteger(f[49]);
         r.broken_pivot_confirmation_time=(datetime)StringToInteger(f[50]);
         r.projection_anchor_1_id=f[51];
         r.projection_anchor_1_speed=(ENUM_MSZZ_SPEED)StringToInteger(f[52]);
         r.projection_anchor_1_kind=(ENUM_MSZZ_PIVOT_KIND)StringToInteger(f[53]);
         r.projection_anchor_1_price=StringToDouble(f[54]);
         r.projection_anchor_1_time=(datetime)StringToInteger(f[55]);
         r.projection_anchor_1_confirmation_time=(datetime)StringToInteger(f[56]);
         r.projection_anchor_2_id=f[57];
         r.projection_anchor_2_speed=(ENUM_MSZZ_SPEED)StringToInteger(f[58]);
         r.projection_anchor_2_kind=(ENUM_MSZZ_PIVOT_KIND)StringToInteger(f[59]);
         r.projection_anchor_2_price=StringToDouble(f[60]);
         r.projection_anchor_2_time=(datetime)StringToInteger(f[61]);
         r.projection_anchor_2_confirmation_time=(datetime)StringToInteger(f[62]);
         r.projected_level_previous_bar=StringToDouble(f[63]);
         r.projected_level_event_bar=StringToDouble(f[64]);
         r.break_close_previous_bar=StringToDouble(f[65]);
         r.break_close_price=StringToDouble(f[66]);
         r.break_distance=StringToDouble(f[67]);
         r.break_distance_atr=StringToDouble(f[68]);
         r.impulse_origin_price=StringToDouble(f[69]);
         r.impulse_extreme_price=StringToDouble(f[70]);
         r.impulse_distance=StringToDouble(f[71]);
         r.impulse_distance_atr=StringToDouble(f[72]);
         r.atr_at_event=StringToDouble(f[73]);
         c.structural_binding.record=r;
      }

      c.ssr.ssr_clock_rule_id=f[74]; c.ssr.ssr_range_id=f[75];
      c.ssr.ssr_range_high=StringToDouble(f[76]); c.ssr.ssr_range_low=StringToDouble(f[77]);
      c.ssr.ssr_sweep_extreme=StringToDouble(f[78]);
      c.ssr.ssr_reclaim_close=StringToDouble(f[79]);
      c.mc.mc_structural_event_id=f[80];
      c.mc.mc_impulse_origin_price=StringToDouble(f[81]);
      c.mc.mc_impulse_extreme_price=StringToDouble(f[82]);
      c.mc.mc_impulse_distance_atr=StringToDouble(f[83]);
      c.mc.mc_efficiency=StringToDouble(f[84]);
      c.mc.mc_pause_bars=(int)StringToInteger(f[85]);
      c.mc.mc_pullback_fraction=StringToDouble(f[86]);
      c.brc.brc_break_event_id=f[87]; c.brc.brc_broken_level_id=f[88];
      c.brc.brc_broken_level_price=StringToDouble(f[89]);
      c.brc.brc_first_touch_time=(datetime)StringToInteger(f[90]);
      c.brc.brc_rejection_time=(datetime)StringToInteger(f[91]);
      c.brc.brc_penetration_atr=StringToDouble(f[92]);
      c.brc.brc_test_count=(int)StringToInteger(f[93]);
      c.cbr.cbr_window_start=(datetime)StringToInteger(f[94]);
      c.cbr.cbr_window_end=(datetime)StringToInteger(f[95]);
      c.cbr.cbr_window_hash=f[96]; c.cbr.cbr_short_atr=StringToDouble(f[97]);
      c.cbr.cbr_long_atr=StringToDouble(f[98]); c.cbr.cbr_range_atr=StringToDouble(f[99]);
      c.cbr.cbr_extension_atr=StringToDouble(f[100]);
      c.cbr.cbr_obstruction_r=StringToDouble(f[101]);
      c.tp.tp_impulse_event_id=f[102]; c.tp.tp_value_type=ValueType(f[103]);
      c.tp.tp_value_anchor_id=f[104];
      c.tp.tp_distance_start_atr=StringToDouble(f[105]);
      c.tp.tp_distance_min_atr=StringToDouble(f[106]);
      c.tp.tp_distance_trigger_atr=StringToDouble(f[107]);
      c.rr.rr_range_id=f[108]; c.rr.rr_width_cv=StringToDouble(f[109]);
      c.rr.rr_high_touch_ids=f[110]; c.rr.rr_low_touch_ids=f[111];
      c.rr.rr_min_touch_separation_bars=(int)StringToInteger(f[112]);
      c.rr.rr_rotation_away_atr=StringToDouble(f[113]);
      c.rr.rr_medium_contained=(f[114]=="true");
      c.rr.rr_midpoint=StringToDouble(f[115]);

      double risk=MathAbs(c.entry-c.stop);
      double point_size=(c.stop_distance_points>0.0 ?
                         risk/c.stop_distance_points : 0.0);
      if(!CMSZZResearchCandidateSchemaV2::Validate(c,point_size))
      { reason="CANDIDATE_VALIDATION_"+c.validation_reason; return false; }
      string round_trip=CMSZZResearchCandidateCsvV2::Row(c);
      if(round_trip!=CanonicalRecord(f))
      { reason="CANDIDATE_ROUND_TRIP_MISMATCH"; return false; }
      reason="OK";
      return true;
   }

public:
   static string ManifestHeader()
   {
      return "manifest_version,writer_version,schema_version,symbol,timeframe,"
             "row_count,journal_sha256,source_data_sha256";
   }

   static bool ParseRecord(const string record,string &fields[],string &reason,
                           const bool require_all_quoted=true)
   {
      ArrayResize(fields,0);
      int length=StringLen(record);
      int i=0;
      while(i<length)
      {
         string field="";
         if(StringSubstr(record,i,1)=="\"")
         {
            i++;
            bool closed=false;
            while(i<length)
            {
               string character=StringSubstr(record,i,1);
               if(character=="\"")
               {
                  if(i+1<length && StringSubstr(record,i+1,1)=="\"")
                  { field+="\""; i+=2; continue; }
                  closed=true; i++; break;
               }
               field+=character;
               i++;
            }
            if(!closed) { reason="UNCLOSED_QUOTE"; return false; }
            if(i<length && StringSubstr(record,i,1)!=",")
            { reason="TRAILING_AFTER_QUOTE"; return false; }
         }
         else
         {
            if(require_all_quoted) { reason="UNQUOTED_FIELD"; return false; }
            int comma=StringFind(record,",",i);
            int end=(comma<0 ? length : comma);
            field=StringSubstr(record,i,end-i);
            if(StringFind(field,"\"")>=0)
            { reason="QUOTE_IN_UNQUOTED_FIELD"; return false; }
            i=end;
         }
         int count=ArraySize(fields);
         ArrayResize(fields,count+1);
         fields[count]=field;
         if(i==length) break;
         i++;
         if(i==length)
         {
            if(require_all_quoted) { reason="UNQUOTED_FIELD"; return false; }
            ArrayResize(fields,count+2);
            fields[count+1]="";
            break;
         }
      }
      if(length==0) { reason="EMPTY_RECORD"; return false; }
      reason="OK";
      return true;
   }

   static bool IsSha256(const string value)
   {
      if(StringLen(value)!=64) return false;
      for(int i=0;i<64;i++)
         if(!HexDigit(StringGetCharacter(value,i))) return false;
      return true;
   }

   static bool Sha256Bytes(const uchar &data[],string &hex,string &reason)
   {
      uchar key[];
      uchar digest[];
      ArrayResize(key,0);
      ResetLastError();
      int count=CryptEncode(CRYPT_HASH_SHA256,data,key,digest);
      if(count!=32)
      {
         reason="SHA256_FAILED_"+IntegerToString(GetLastError());
         return false;
      }
      hex="";
      for(int i=0;i<count;i++) hex+=StringFormat("%02x",(int)digest[i]);
      reason="OK";
      return true;
   }

   static bool Sha256File(const string file_name,string &hex,string &reason)
   {
      uchar data[];
      if(!ReadBytes(file_name,data,reason)) return false;
      return Sha256Bytes(data,hex,reason);
   }

   static bool ValidateJournalBytes(const uchar &data[],long &row_count,
                                    string &journal_sha256,string &reason)
   {
      row_count=0;
      if(!ValidateUtf8(data,reason)) return false;
      if(!Sha256Bytes(data,journal_sha256,reason)) return false;
      string document=CharArrayToString(data,0,ArraySize(data),CP_UTF8);
      string records[];
      if(!SplitDocument(document,records,reason)) return false;
      if(ArraySize(records)<1) { reason="MISSING_HEADER"; return false; }
      if(records[0]!=CMSZZResearchCandidateCsvV2::Header())
      { reason="HEADER_MISMATCH"; return false; }

      string expected_header_fields[];
      if(!ParseRecord(records[0],expected_header_fields,reason,false)) return false;
      int expected_columns=ArraySize(expected_header_fields);
      string event_ids[];
      string sequence_ids[];
      for(int r=1;r<ArraySize(records);r++)
      {
         string fields[];
         if(!ParseRecord(records[r],fields,reason,true)) return false;
         if(ArraySize(fields)!=expected_columns)
         { reason="COLUMN_COUNT_MISMATCH"; return false; }
         if(CanonicalRecord(fields)!=records[r])
         { reason="NONCANONICAL_RECORD"; return false; }
         if(fields[0]!=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2)
         { reason="UNSUPPORTED_SCHEMA"; return false; }
         if(fields[5]=="" || fields[6]=="" || fields[7]=="")
         { reason="MISSING_IDENTITY"; return false; }
         if(!ValidateCommonFields(fields,reason)) return false;
         if(!ValidateExtensionPartition(fields,reason)) return false;
         MSZZResearchCandidateV2 candidate;
         if(!ReconstructCandidate(fields,candidate,reason)) return false;
         if(Seen(fields[7],event_ids))
         { reason="DUPLICATE_EVENT_ID"; return false; }
         if(Seen(fields[6],sequence_ids))
         { reason="DUPLICATE_SEQUENCE_ID"; return false; }
         int event_count=ArraySize(event_ids);
         ArrayResize(event_ids,event_count+1);
         event_ids[event_count]=fields[7];
         int sequence_count=ArraySize(sequence_ids);
         ArrayResize(sequence_ids,sequence_count+1);
         sequence_ids[sequence_count]=fields[6];
         row_count++;
      }
      reason="OK";
      return true;
   }

   static bool ValidateJournalFile(const string file_name,long &row_count,
                                   string &journal_sha256,string &reason)
   {
      uchar data[];
      if(!ReadBytes(file_name,data,reason)) return false;
      return ValidateJournalBytes(data,row_count,journal_sha256,reason);
   }

   // Additive verified-records accessor (MQL5 analog of the Python
   // reconstruct_verified_rows). Runs the certified ValidateJournalBytes (which
   // already reconstructs + canonical round-trips every row), then returns the
   // exact split records (records[0] is the header). Does not change any
   // accepted/rejected byte, canonical serialization, or manifest rule.
   static bool ReconstructVerifiedRecords(const uchar &data[],string &records[],
                                          long &row_count,string &journal_sha256,
                                          string &reason)
   {
      ArrayResize(records,0);  // fail-closed: never leave stale records on failure
      row_count=0; journal_sha256="";
      if(!ValidateJournalBytes(data,row_count,journal_sha256,reason)) return false;
      string document=CharArrayToString(data,0,ArraySize(data),CP_UTF8);
      return SplitDocument(document,records,reason);
   }

   static string ManifestRow(const MSZZResearchJournalManifestV2 &manifest)
   {
      string fields[8];
      fields[0]=manifest.manifest_version;
      fields[1]=manifest.writer_version;
      fields[2]=manifest.schema_version;
      fields[3]=manifest.symbol;
      fields[4]=IntegerToString(manifest.timeframe);
      fields[5]=IntegerToString(manifest.row_count);
      fields[6]=manifest.journal_sha256;
      fields[7]=manifest.source_data_sha256;
      return CanonicalRecord(fields);
   }

   static bool BuildManifest(const string journal_file,const string symbol,
                             const ENUM_TIMEFRAMES timeframe,
                             const string source_data_sha256,
                             MSZZResearchJournalManifestV2 &manifest,
                             string &reason)
   {
      ZeroMemory(manifest);
      manifest.manifest_version="";
      manifest.writer_version="";
      manifest.schema_version="";
      manifest.symbol="";
      manifest.journal_sha256="";
      manifest.source_data_sha256="";
      if(symbol=="" || !IsSha256(source_data_sha256))
      { reason="INVALID_MANIFEST_INPUT"; return false; }
      long rows=0;
      string journal_hash="";
      if(!ValidateJournalFile(journal_file,rows,journal_hash,reason)) return false;
      manifest.manifest_version=MSZZ_RESEARCH_MANIFEST_V2;
      manifest.writer_version=MSZZ_RESEARCH_WRITER_V2;
      manifest.schema_version=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2;
      manifest.symbol=symbol;
      manifest.timeframe=(int)timeframe;
      manifest.row_count=rows;
      manifest.journal_sha256=journal_hash;
      manifest.source_data_sha256=source_data_sha256;
      reason="OK";
      return true;
   }

   static bool ParseManifestDocument(const string document,
                                     MSZZResearchJournalManifestV2 &manifest,
                                     string &reason)
   {
      string records[];
      if(!SplitDocument(document,records,reason)) return false;
      if(ArraySize(records)!=2 || records[0]!=ManifestHeader())
      { reason="MANIFEST_SHAPE_MISMATCH"; return false; }
      string fields[];
      if(!ParseRecord(records[1],fields,reason,true)) return false;
      if(ArraySize(fields)!=8 || CanonicalRecord(fields)!=records[1])
      { reason="MANIFEST_RECORD_MISMATCH"; return false; }
      long row_count=(long)StringToInteger(fields[5]);
      if(fields[0]!=MSZZ_RESEARCH_MANIFEST_V2 ||
         fields[1]!=MSZZ_RESEARCH_WRITER_V2 ||
         fields[2]!=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2 ||
         fields[3]=="" || IntegerToString((int)StringToInteger(fields[4]))!=fields[4] ||
         (int)StringToInteger(fields[4])<=0 ||
         StringFormat("%I64d",row_count)!=fields[5] || row_count<0 ||
         !IsSha256(fields[6]) || !IsSha256(fields[7]))
      { reason="INVALID_MANIFEST_FIELD"; return false; }
      manifest.manifest_version=fields[0];
      manifest.writer_version=fields[1];
      manifest.schema_version=fields[2];
      manifest.symbol=fields[3];
      manifest.timeframe=(int)StringToInteger(fields[4]);
      manifest.row_count=row_count;
      manifest.journal_sha256=fields[6];
      manifest.source_data_sha256=fields[7];
      reason="OK";
      return true;
   }

   static bool LoadManifestFile(const string file_name,
                                MSZZResearchJournalManifestV2 &manifest,
                                string &reason)
   {
      uchar data[];
      if(!ReadBytes(file_name,data,reason)) return false;
      if(!ValidateUtf8(data,reason)) return false;
      string document=CharArrayToString(data,0,ArraySize(data),CP_UTF8);
      return ParseManifestDocument(document,manifest,reason);
   }

   static bool WriteManifestFile(const string file_name,
                                 const MSZZResearchJournalManifestV2 &manifest,
                                 string &reason)
   {
      string document=ManifestHeader()+"\r\n"+ManifestRow(manifest)+"\r\n";
      uchar data[];
      StringToCharArray(document,data,0,-1,CP_UTF8);
      if(ArraySize(data)>0) ArrayResize(data,ArraySize(data)-1);
      int handle=FileOpen(file_name,FILE_WRITE|FILE_BIN);
      if(handle==INVALID_HANDLE) { reason="MANIFEST_OPEN_FAILED"; return false; }
      uint written=FileWriteArray(handle,data,0,ArraySize(data));
      FileClose(handle);
      if(written!=(uint)ArraySize(data))
      { reason="MANIFEST_WRITE_FAILED"; return false; }
      reason="OK";
      return true;
   }

   static bool VerifyManifest(const MSZZResearchJournalManifestV2 &manifest,
                              const string journal_file,const string symbol,
                              const ENUM_TIMEFRAMES timeframe,
                              const string expected_source_data_sha256,
                              string &reason)
   {
      if(manifest.manifest_version!=MSZZ_RESEARCH_MANIFEST_V2 ||
         manifest.writer_version!=MSZZ_RESEARCH_WRITER_V2 ||
         manifest.schema_version!=MSZZ_RESEARCH_CANDIDATE_SCHEMA_V2)
      { reason="MANIFEST_VERSION_MISMATCH"; return false; }
      if(manifest.symbol!=symbol || manifest.timeframe!=(int)timeframe)
      { reason="MANIFEST_MARKET_MISMATCH"; return false; }
      if(manifest.source_data_sha256!=expected_source_data_sha256)
      { reason="SOURCE_DATA_HASH_MISMATCH"; return false; }
      long rows=0;
      string journal_hash="";
      if(!ValidateJournalFile(journal_file,rows,journal_hash,reason)) return false;
      if(rows!=manifest.row_count) { reason="ROW_COUNT_MISMATCH"; return false; }
      if(journal_hash!=manifest.journal_sha256)
      { reason="JOURNAL_HASH_MISMATCH"; return false; }
      reason="OK";
      return true;
   }
};

#endif
