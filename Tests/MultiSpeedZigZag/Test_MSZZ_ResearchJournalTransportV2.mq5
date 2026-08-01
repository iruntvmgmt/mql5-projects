#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ResearchJournalTransportV2.mqh>

int g_failures=0;

void Check(const bool condition,const string name)
{
   if(condition) Print("PASS: ",name);
   else { Print("FAIL: ",name); g_failures++; }
}

void Bytes(const string text,uchar &data[])
{
   StringToCharArray(text,data,0,-1,CP_UTF8);
   if(ArraySize(data)>0) ArrayResize(data,ArraySize(data)-1);
}

MSZZResearchCandidateV2 Candidate(const string sequence_id="SEQUENCE|1",
                                  const string event_id="EVENT|1|FINAL")
{
   MSZZResearchCandidateV2 c;
   CMSZZResearchCandidateSchemaV2::Initialize(c);
   c.strategy_id=1200; c.family_id=8;
   c.hypothesis_version="SSR-V2";
   c.canonical_variant_id="CANONICAL";
   c.origin_id="ASIA_LOW|20260105";
   c.sequence_id=sequence_id;
   c.event_id=event_id;
   c.arm_time=D'2026.01.05 09:55:00';
   c.trigger_time=D'2026.01.05 10:00:00';
   c.signal_time=c.trigger_time;
   c.expiry_time=D'2026.01.05 10:15:00';
   c.direction=MSZZ_DIR_LONG;
   c.entry=100.0; c.stop=99.0; c.target=102.0; c.score=1.0;
   c.reference_type=MSZZ_RESEARCH_REFERENCE_SESSION_RANGE;
   c.reference_id="ASIA|20260105"; c.reference_price=99.5;
   c.bars_armed=1;
   c.terminal_prior_state=MSZZ_RESEARCH_TERMINAL_NONE;
   c.reset_classification=MSZZ_RESEARCH_RESET_FRESH_CROSS;
   c.atr_at_arm=2.0; c.atr_at_trigger=2.1;
   c.spread_points=10;
   c.session_id="SESSION|LONDON"; c.regime_id="REGIME|1";
   c.diagnostic_json="{\"evidence\":\"comma,quote\\\"\"}";
   c.ssr.ssr_clock_rule_id="SESSION_TABLE_V1";
   c.ssr.ssr_range_id="ASIA|20260105";
   c.ssr.ssr_range_high=101.0; c.ssr.ssr_range_low=99.0;
   c.ssr.ssr_sweep_extreme=98.8; c.ssr.ssr_reclaim_close=100.0;
   CMSZZResearchCandidateSchemaV2::PopulateDerived(c,0.01);
   CMSZZResearchCandidateSchemaV2::Validate(c,0.01);
   return c;
}

string Journal(const string row)
{
   return CMSZZResearchCandidateCsvV2::Header()+"\r\n"+row+"\r\n";
}

bool WriteUtf8(const string file_name,const string value)
{
   int h=FileOpen(file_name,FILE_WRITE|FILE_BIN);
   if(h==INVALID_HANDLE) return false;
   uchar data[]; Bytes(value,data);
   uint written=FileWriteArray(h,data,0,ArraySize(data));
   FileClose(h);
   return written==(uint)ArraySize(data);
}

void ParserTests()
{
   MSZZResearchCandidateV2 c=Candidate();
   string row=CMSZZResearchCandidateCsvV2::Row(c);
   uchar data[]; Bytes(Journal(row),data);
   long rows=0; string hash=""; string reason="";
   Check(CMSZZResearchJournalTransportV2::ValidateJournalBytes(data,rows,hash,reason) &&
         rows==1 && StringLen(hash)==64,
         "canonical journal validates");

   string fields[];
   Check(CMSZZResearchJournalTransportV2::ParseRecord(row,fields,reason,true) &&
         ArraySize(fields)>100 && fields[7]=="EVENT|1|FINAL",
         "RFC-4180 quoted row parses exactly");

   Bytes(CMSZZResearchCandidateCsvV2::Header()+"\n"+row+"\n",data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(data,rows,hash,reason) &&
         reason=="BARE_LF","bare LF fails closed");

   Bytes(Journal(row+","+("\"EXTRA\"")),data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(data,rows,hash,reason) &&
         reason=="COLUMN_COUNT_MISMATCH","wrong column count fails closed");

   Bytes(CMSZZResearchCandidateCsvV2::Header()+"\r\n"+row+"\r\n"+row+"\r\n",data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(data,rows,hash,reason) &&
         reason=="DUPLICATE_EVENT_ID","duplicate event ID fails closed");

   MSZZResearchCandidateV2 c2=Candidate("SEQUENCE|1","EVENT|2|FINAL");
   Bytes(CMSZZResearchCandidateCsvV2::Header()+"\r\n"+row+"\r\n"+
         CMSZZResearchCandidateCsvV2::Row(c2)+"\r\n",data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(data,rows,hash,reason) &&
         reason=="DUPLICATE_SEQUENCE_ID","duplicate lifecycle fails closed");

   string noncanonical=row;
   StringReplace(noncanonical,"\"MSZZ_RESEARCH_CANDIDATE_V2\"",
                              "MSZZ_RESEARCH_CANDIDATE_V2");
   Bytes(Journal(noncanonical),data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(data,rows,hash,reason) &&
         reason=="UNQUOTED_FIELD","noncanonical unquoted field fails closed");

   string invalid_direction=row;
   StringReplace(invalid_direction,"\"LONG\"","\"SIDEWAYS\"");
   Bytes(Journal(invalid_direction),data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(
            data,rows,hash,reason) && reason=="INVALID_DIRECTION",
         "invalid enum fails closed");

   string invalid_number=row;
   StringReplace(invalid_number,"\"100.0000000000000000\"","\"100x\"");
   Bytes(Journal(invalid_number),data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(
            data,rows,hash,reason) && reason=="INVALID_NUMBER",
         "invalid number fails closed");

   string invalid_time=row;
   StringReplace(invalid_time,
      "\""+IntegerToString((long)c.expiry_time)+"\"",
      "\""+IntegerToString((long)c.signal_time)+"\"");
   Bytes(Journal(invalid_time),data);
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(
            data,rows,hash,reason) && reason=="INVALID_LIFECYCLE_TIME",
         "invalid lifecycle time fails closed");

   uchar invalid_utf8[2]; invalid_utf8[0]=0xC3; invalid_utf8[1]=0x28;
   Check(!CMSZZResearchJournalTransportV2::ValidateJournalBytes(
            invalid_utf8,rows,hash,reason) &&
         reason=="INVALID_UTF8_CONTINUATION","invalid UTF-8 fails closed");

   uchar abc[]; Bytes("abc",abc);
   Check(CMSZZResearchJournalTransportV2::Sha256Bytes(abc,hash,reason) &&
         hash=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
         "SHA-256 matches canonical abc vector");
}

void ManifestTests()
{
   string journal_file="MSZZ_ResearchJournalTransportV2.csv";
   MSZZResearchCandidateV2 c=Candidate();
   Check(WriteUtf8(journal_file,Journal(CMSZZResearchCandidateCsvV2::Row(c))),
         "fixture journal written");
   string source_hash=
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
   MSZZResearchJournalManifestV2 manifest;
   string reason="";
   Check(CMSZZResearchJournalTransportV2::BuildManifest(
            journal_file,"XAUUSD",PERIOD_M5,source_hash,manifest,reason) &&
         manifest.row_count==1,
         "manifest binds canonical journal");

   string document=CMSZZResearchJournalTransportV2::ManifestHeader()+"\r\n"+
                   CMSZZResearchJournalTransportV2::ManifestRow(manifest)+"\r\n";
   Check(CMSZZResearchJournalTransportV2::WriteManifestFile(
            "MSZZ_ResearchJournalTransportV2_Manifest.csv",manifest,reason),
         "fixture manifest written");
   MSZZResearchJournalManifestV2 parsed;
   Check(CMSZZResearchJournalTransportV2::ParseManifestDocument(
            document,parsed,reason) &&
         parsed.journal_sha256==manifest.journal_sha256,
         "manifest round trip is exact");
   MSZZResearchJournalManifestV2 loaded;
   Check(CMSZZResearchJournalTransportV2::LoadManifestFile(
            "MSZZ_ResearchJournalTransportV2_Manifest.csv",loaded,reason) &&
         loaded.journal_sha256==manifest.journal_sha256,
         "strict manifest file load is exact");
   Check(CMSZZResearchJournalTransportV2::VerifyManifest(
            parsed,journal_file,"XAUUSD",PERIOD_M5,source_hash,reason),
         "manifest verification passes");

   parsed.row_count++;
   Check(!CMSZZResearchJournalTransportV2::VerifyManifest(
            parsed,journal_file,"XAUUSD",PERIOD_M5,source_hash,reason) &&
         reason=="ROW_COUNT_MISMATCH","manifest row mismatch fails closed");
   parsed=manifest;
   Check(!CMSZZResearchJournalTransportV2::VerifyManifest(
            parsed,journal_file,"XAUUSD",PERIOD_M5,
            "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            reason) && reason=="SOURCE_DATA_HASH_MISMATCH",
         "source-data hash mismatch fails closed");
}

void VerifiedRecordsTests()
{
   MSZZResearchCandidateV2 c1=Candidate("SEQUENCE|1","EVENT|1|FINAL");
   MSZZResearchCandidateV2 c2=Candidate("SEQUENCE|2","EVENT|2|FINAL");
   string row1=CMSZZResearchCandidateCsvV2::Row(c1);
   string row2=CMSZZResearchCandidateCsvV2::Row(c2);
   string doc=CMSZZResearchCandidateCsvV2::Header()+"\r\n"+row1+"\r\n"+row2+"\r\n";
   uchar data[]; Bytes(doc,data);

   string records[]; long rows=0; string hash=""; string reason="";
   bool ok=CMSZZResearchJournalTransportV2::ReconstructVerifiedRecords(data,records,rows,hash,reason);
   Check(ok && rows==2,"verified records: valid journal succeeds");
   Check(ArraySize(records)==(int)rows+1,"verified records: count == row_count+1");
   Check(ArraySize(records)>0 && records[0]==CMSZZResearchCandidateCsvV2::Header(),
         "verified records: records[0] is canonical header");
   Check(ArraySize(records)>0 && records[ArraySize(records)-1]!="",
         "verified records: no trailing empty pseudo-record");
   bool allparse=true;
   for(int r=1;r<ArraySize(records);r++)
   { string f[]; if(!CMSZZResearchJournalTransportV2::ParseRecord(records[r],f,reason,true)){ allparse=false; break; } }
   Check(allparse,"verified records: every data record parses");
   string rebuilt=(ArraySize(records)>0 ? records[0] : "");
   for(int r=1;r<ArraySize(records);r++) rebuilt+="\r\n"+records[r];
   rebuilt+="\r\n";
   Check(rebuilt==doc,"verified records: exact record round-trip");
   long rows2=0; string hash2="";
   CMSZZResearchJournalTransportV2::ValidateJournalBytes(data,rows2,hash2,reason);
   Check(hash==hash2 && rows==rows2,"verified records: SHA/count match ValidateJournalBytes");

   // malformed UTF-8 fails + no stale records left in the reused array
   uchar bad[]; ArrayResize(bad,2); bad[0]=0xC3; bad[1]=0x28;
   bool ok2=CMSZZResearchJournalTransportV2::ReconstructVerifiedRecords(bad,records,rows,hash,reason);
   Check(!ok2,"verified records: malformed UTF-8 fails");
   Check(ArraySize(records)==0,"verified records: no stale records after failure");

   uchar lf[]; Bytes(CMSZZResearchCandidateCsvV2::Header()+"\n"+row1+"\n",lf);
   string recs3[]; long r4=0; string h4="";
   Check(!CMSZZResearchJournalTransportV2::ReconstructVerifiedRecords(lf,recs3,r4,h4,reason),
         "verified records: LF-only fails");
   uchar nofinal[]; Bytes(CMSZZResearchCandidateCsvV2::Header()+"\r\n"+row1,nofinal);
   string recs4[]; long r5=0; string h5="";
   Check(!CMSZZResearchJournalTransportV2::ReconstructVerifiedRecords(nofinal,recs4,r5,h5,reason),
         "verified records: missing final CRLF fails");
   string unq=doc; StringReplace(unq,"\"MSZZ_RESEARCH_CANDIDATE_V2\"","MSZZ_RESEARCH_CANDIDATE_V2");
   uchar uq[]; Bytes(unq,uq);
   string recs5[]; long r6=0; string h6="";
   Check(!CMSZZResearchJournalTransportV2::ReconstructVerifiedRecords(uq,recs5,r6,h6,reason),
         "verified records: malformed quoted record fails");
}

void OnStart()
{
   Print("MSZZ ResearchJournalTransportV2 tests begin");
   ParserTests();
   ManifestTests();
   VerifiedRecordsTests();
   int h=FileOpen("MSZZ_ResearchJournalTransportV2_TestSummary.csv",
                  FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(h!=INVALID_HANDLE)
   {
      FileWrite(h,"failures","result");
      FileWrite(h,g_failures,(g_failures==0 ? "PASS" : "FAIL"));
      FileClose(h);
   }
   Print("MSZZ ResearchJournalTransportV2 tests failures=",g_failures);
}
