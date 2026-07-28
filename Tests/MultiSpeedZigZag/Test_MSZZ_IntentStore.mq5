//+------------------------------------------------------------------+
//| Test_MSZZ_IntentStore.mq5                                        |
//| Covers DECISION_LOG.md D007 requirements.                        |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh>

int g_failures=0;

void AssertTrue(const bool condition,const string message)
{
   if(condition) Print("PASS: ",message);
   else { Print("FAIL: ",message); g_failures++; }
}

//--- fixture helpers -------------------------------------------------

MSZZExecutionIntent MakeIntent(const string intent_id,const string cluster_id,const string origin_id,
                               const long magic,const string instance_id)
{
   MSZZExecutionIntent r;
   r.schema_version=MSZZ_INTENT_SCHEMA_VERSION;
   r.intent_id=intent_id;
   r.cluster_id=cluster_id;
   r.origin_id=origin_id;
   r.strategy_id=1003;
   r.symbol="XAUUSD";
   r.timeframe=(int)PERIOD_M5;
   r.magic=magic;
   r.direction=1;
   r.signal_time=D'2026.07.26 10:00';
   r.intent_time=D'2026.07.26 10:00:01';
   r.expiry_time=D'2026.07.26 11:00';
   r.requested_volume=0.01;
   r.requested_entry=4000.00;
   r.requested_stop=3990.00;
   r.requested_target=4015.00;
   r.execution_state=(int)MSZZ_INTENT_CREATED;
   r.submission_attempts=0;
   r.broker_retcode=0;
   r.broker_result_text="";
   r.order_ticket=0;
   r.position_ticket=0;
   r.first_deal_ticket=0;
   r.last_deal_ticket=0;
   r.filled_volume=0.0;
   r.average_fill_price=0.0;
   r.last_reconciliation_time=0;
   r.protection_status=0;
   r.instance_id=instance_id;
   return r;
}

void CleanupFilesFor(const long magic)
{
   string base=StringFormat("MSZZ_Intents_XAUUSD_%d_%d",(int)PERIOD_M5,magic);
   FileDelete(base+".dat");
   FileDelete(base+".bak");
   FileDelete(base+".tmp");
   FileDelete(base+".lock");
}

bool RawReadWholeFile(const string filename,string &content)
{
   int h=FileOpen(filename,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return false;
   content="";
   while(!FileIsEnding(h)) content+=FileReadString(h)+"\r\n";
   FileClose(h);
   return true;
}

bool RawWriteWholeFile(const string filename,const string content)
{
   int h=FileOpen(filename,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return false;
   FileWriteString(h,content);
   FileFlush(h);
   FileClose(h);
   return true;
}

// Independent re-implementation of the store's checksum, used only to hand-craft
// fixture files for tests that need a structurally valid but semantically
// different record (e.g. an unrecognized future schema version).
uint TestFnv1a(const string payload)
{
   uint h=2166136261;
   int n=StringLen(payload);
   for(int i=0;i<n;i++) { h^=(uint)StringGetCharacter(payload,i); h*=16777619; }
   return h;
}
string TestChecksum(const string payload) { return StringFormat("%08X",TestFnv1a(payload)); }
string TestLenPrefix(const string value) { return StringFormat("%d:%s",StringLen(value),value); }

//--- scenarios ---------------------------------------------------------

void TestRoundTripAndMultipleRecords()
{
   long magic=990201;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   AssertTrue(store.Configure("XAUUSD",PERIOD_M5,magic),"round-trip: configure succeeds");
   AssertTrue(store.Load(),"round-trip: load on fresh (nonexistent) files succeeds with empty state");
   AssertTrue(store.Count()==0,"round-trip: fresh store has zero records");

   MSZZExecutionIntent a=MakeIntent("INT-A","CLU-A","ORIG-A",magic,"inst-1");
   MSZZExecutionIntent b=MakeIntent("INT-B","CLU-B","ORIG-B",magic,"inst-1");
   AssertTrue(store.CreateIntent(a),"round-trip: create intent A succeeds");
   AssertTrue(store.CreateIntent(b),"multiple records: create intent B succeeds");
   AssertTrue(store.Count()==2,"multiple records: store holds both records");

   MSZZExecutionIntent back;
   AssertTrue(store.FindById("INT-A",back),"round-trip: find INT-A after save");
   AssertTrue(back.cluster_id=="CLU-A" && back.origin_id=="ORIG-A" && back.requested_entry==4000.00,
              "round-trip: recovered fields match exactly");
   store.Close();
}

void TestDuplicateIntentRejection()
{
   long magic=990202;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();
   MSZZExecutionIntent a=MakeIntent("DUP-1","CLU-1","ORIG-1",magic,"inst-1");
   AssertTrue(store.CreateIntent(a),"duplicate rejection: first create succeeds");
   AssertTrue(!store.CreateIntent(a),"duplicate rejection: second create with same intent_id is rejected");
   AssertTrue(store.Count()==1,"duplicate rejection: store still holds exactly one record");
   store.Close();
}

void TestTempWriteFailureAndRollback()
{
   long magic=990203;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();

   string temp_file=store.TempFilename();
   int blocker=FileOpen(temp_file,FILE_WRITE|FILE_READ|FILE_BIN);
   AssertTrue(blocker!=INVALID_HANDLE,"temp-write failure: test harness holds temp file exclusively");

   MSZZExecutionIntent a=MakeIntent("TMPFAIL-1","CLU-1","ORIG-1",magic,"inst-1");
   bool created=store.CreateIntent(a);
   AssertTrue(!created,"temp-write failure: create fails while temp file is blocked");
   AssertTrue(store.Count()==0,"in-memory rollback: failed save leaves in-memory state unchanged");

   FileClose(blocker);
   AssertTrue(store.CreateIntent(a),"temp-write failure: create succeeds once the block is released");
   AssertTrue(store.Count()==1,"temp-write failure: exactly one record exists after recovery");
   store.Close();
}

void TestPrimaryReplacementFailureAndRollback()
{
   long magic=990204;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();
   MSZZExecutionIntent a=MakeIntent("PRIFAIL-1","CLU-1","ORIG-1",magic,"inst-1");
   AssertTrue(store.CreateIntent(a),"primary-replacement failure: seed record saved");

   string primary_file=store.PrimaryFilename();
   int blocker=FileOpen(primary_file,FILE_WRITE|FILE_READ|FILE_BIN);
   AssertTrue(blocker!=INVALID_HANDLE,"primary-replacement failure: test harness holds primary file exclusively");

   MSZZExecutionIntent b=MakeIntent("PRIFAIL-2","CLU-2","ORIG-2",magic,"inst-1");
   bool created=store.CreateIntent(b);
   AssertTrue(!created,"primary-replacement failure: second create fails while primary is blocked");
   AssertTrue(store.Count()==1,"in-memory rollback: store still reflects only the pre-attempt record");

   FileClose(blocker);
   AssertTrue(store.CreateIntent(b),"primary-replacement failure: create succeeds once the block is released");
   AssertTrue(store.Count()==2,"primary-replacement failure: both records present after recovery");
   store.Close();
}

void TestTruncatedTempFileDoesNotCorruptStore()
{
   // A truncated temp file must be caught by SaveAll()'s own re-open-and-verify
   // step and must never reach the primary. Simulate by writing a truncated file
   // directly to the temp path and confirming a subsequent legitimate save still
   // succeeds cleanly (proving the store does not trust a stale/bad temp file).
   long magic=990205;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();
   MSZZExecutionIntent a=MakeIntent("TRUNCTMP-1","CLU-1","ORIG-1",magic,"inst-1");
   AssertTrue(store.CreateIntent(a),"truncated temp file: seed record saved");

   RawWriteWholeFile(store.TempFilename(),"MSZZI_HEADER|1:1|1:1\r\nMSZZI1|garbage");
   MSZZExecutionIntent b=MakeIntent("TRUNCTMP-2","CLU-2","ORIG-2",magic,"inst-1");
   AssertTrue(store.CreateIntent(b),"truncated temp file: next legitimate save overwrites bad temp content and succeeds");
   AssertTrue(store.Count()==2,"truncated temp file: store state is correct after recovery");
   store.Close();
}

void TestTruncatedPrimaryFileFailsClosed()
{
   long magic=990206;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();
   MSZZExecutionIntent a=MakeIntent("TRUNCPRI-1","CLU-1","ORIG-1",magic,"inst-1");
   store.CreateIntent(a);
   store.Close();

   string content;
   RawReadWholeFile(store.PrimaryFilename(),content);
   string truncated=StringSubstr(content,0,StringLen(content)/2);
   RawWriteWholeFile(store.PrimaryFilename(),truncated);

   CMSZZExecutionIntentStore reloaded;
   reloaded.Configure("XAUUSD",PERIOD_M5,magic);
   bool ok=reloaded.Load();
   AssertTrue(!ok,"truncated primary file: load fails closed with no valid backup available");
   AssertTrue(reloaded.Count()==0,"truncated primary file: no partial/corrupt data is exposed");
   reloaded.Close();
}

void TestCorruptChecksumFailsClosed()
{
   long magic=990207;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();
   MSZZExecutionIntent a=MakeIntent("CKSUM-1","CLU-1","ORIG-1",magic,"CKSUMTEST");
   store.CreateIntent(a);
   store.Close();

   string content;
   RawReadWholeFile(store.PrimaryFilename(),content);
   int pos=StringFind(content,"CKSUMTEST");
   AssertTrue(pos>=0,"corrupt checksum: fixture marker found in raw file");
   string corrupted=StringSubstr(content,0,pos)+"CKSUMTFST"+StringSubstr(content,pos+9);
   RawWriteWholeFile(store.PrimaryFilename(),corrupted);

   CMSZZExecutionIntentStore reloaded;
   reloaded.Configure("XAUUSD",PERIOD_M5,magic);
   bool ok=reloaded.Load();
   AssertTrue(!ok,"corrupt checksum: load fails closed (same-length content mutation breaks checksum, not structure)");
   reloaded.Close();
}

void TestBackupRecoveryScenarios()
{
   long magic=990208;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();
   MSZZExecutionIntent a=MakeIntent("BAK-1","CLU-1","ORIG-1",magic,"inst-1");
   MSZZExecutionIntent b=MakeIntent("BAK-2","CLU-2","ORIG-2",magic,"inst-1");
   store.CreateIntent(a);              // primary now has 1 record, no backup yet
   store.CreateIntent(b);              // primary rotated to backup (1 record); new primary has 2
   string primary_file=store.PrimaryFilename();
   string backup_file=store.BackupFilename();
   store.Close();

   // Valid backup, corrupt primary => recovers to the backup's (older) state.
   string good_primary,good_backup;
   RawReadWholeFile(primary_file,good_primary);
   RawReadWholeFile(backup_file,good_backup);
   RawWriteWholeFile(primary_file,StringSubstr(good_primary,0,10)); // corrupt

   CMSZZExecutionIntentStore recoverA;
   recoverA.Configure("XAUUSD",PERIOD_M5,magic);
   bool okA=recoverA.Load();
   AssertTrue(okA,"valid backup + corrupt primary: load recovers from backup");
   AssertTrue(recoverA.Count()==1,"valid backup + corrupt primary: recovered state matches backup generation (1 record)");
   recoverA.Close();

   // Restore primary, now corrupt backup instead => primary alone is sufficient.
   RawWriteWholeFile(primary_file,good_primary);
   RawWriteWholeFile(backup_file,StringSubstr(good_backup,0,10)); // corrupt

   CMSZZExecutionIntentStore recoverB;
   recoverB.Configure("XAUUSD",PERIOD_M5,magic);
   bool okB=recoverB.Load();
   AssertTrue(okB,"valid primary + corrupt backup: load still succeeds from primary");
   AssertTrue(recoverB.Count()==2,"valid primary + corrupt backup: full primary state (2 records) is used, not the corrupt backup");
   recoverB.Close();
}

void TestSchemaVersionPreservation()
{
   long magic=990209;
   CleanupFilesFor(magic);
   string base=StringFormat("MSZZ_Intents_XAUUSD_%d_%d",(int)PERIOD_M5,magic);
   string primary_file=base+".dat";

   // Hand-craft one structurally valid record with an unrecognized future schema
   // version (99) and a correctly computed checksum for that exact content.
   string payload="MSZZI1"
      +"|"+TestLenPrefix("99")
      +"|"+TestLenPrefix("FUTURE-1")
      +"|"+TestLenPrefix("CLU-FUT")
      +"|"+TestLenPrefix("ORIG-FUT")
      +"|"+TestLenPrefix("1003")
      +"|"+TestLenPrefix("XAUUSD")
      +"|"+TestLenPrefix(IntegerToString((int)PERIOD_M5))
      +"|"+TestLenPrefix(IntegerToString(magic))
      +"|"+TestLenPrefix("1")
      +"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")
      +"|"+TestLenPrefix("0.01000000")+"|"+TestLenPrefix("4000.00000000")
      +"|"+TestLenPrefix("3990.00000000")+"|"+TestLenPrefix("4015.00000000")
      +"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")
      +"|"+TestLenPrefix("future-schema-field-unknown-to-this-build")
      +"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")
      +"|"+TestLenPrefix("0.00000000")+"|"+TestLenPrefix("0.00000000")
      +"|"+TestLenPrefix("0")+"|"+TestLenPrefix("0")+"|"+TestLenPrefix("inst-future");
   string line=payload+"|"+TestLenPrefix(TestChecksum(payload));
   string header="MSZZI_HEADER|"+TestLenPrefix("1")+"|"+TestLenPrefix("1");
   RawWriteWholeFile(primary_file,header+"\r\n"+line+"\r\n");

   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   bool ok=store.Load();
   AssertTrue(ok,"schema-version rejection: a well-formed unknown-schema record still loads successfully");
   AssertTrue(store.Count()==0,"schema-version rejection: unknown-schema record is not exposed as a known intent");
   AssertTrue(store.UnknownRecordCount()==1,"schema-version preservation: unknown-schema record is retained, not dropped");

   MSZZExecutionIntent known=MakeIntent("KNOWN-1","CLU-K","ORIG-K",magic,"inst-1");
   AssertTrue(store.CreateIntent(known),"schema-version preservation: a normal save alongside the unknown record succeeds");

   string after_save;
   RawReadWholeFile(primary_file,after_save);
   AssertTrue(StringFind(after_save,"future-schema-field-unknown-to-this-build")>=0,
              "schema-version preservation: unknown-schema line survives a subsequent save verbatim");
   store.Close();
}

void TestLongIdsAndDelimiterCharacters()
{
   long magic=990210;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();

   string long_id="";
   for(int i=0;i<50;i++) long_id+="0123456789";
   MSZZExecutionIntent longrec=MakeIntent("LONG-1",long_id,long_id,magic,"inst-1");
   AssertTrue(store.CreateIntent(longrec),"long IDs: 500-character cluster/origin ID saves successfully");
   MSZZExecutionIntent backLong;
   AssertTrue(store.FindById("LONG-1",backLong) && StringLen(backLong.cluster_id)==500 && backLong.cluster_id==long_id,
              "long IDs: 500-character cluster ID round-trips exactly");

   string nested="BO|XAUUSD|5|1|S|1784639100|MSZZ|XAUUSD|5|1|-1|1784637600|1784638200";
   MSZZExecutionIntent delimrec=MakeIntent("DELIM-1","MSZZC1|6:XAUUSD|1:5|1:1|1:2|"+IntegerToString(StringLen(nested))+":"+nested,
                                           nested,magic,"inst:with|delims");
   delimrec.broker_result_text="requote|slippage:2.3|retry|comment";
   AssertTrue(store.CreateIntent(delimrec),"delimiter characters: record with '|' and ':' throughout saves successfully");
   MSZZExecutionIntent backDelim;
   AssertTrue(store.FindById("DELIM-1",backDelim) && backDelim.origin_id==nested &&
              backDelim.instance_id=="inst:with|delims" && backDelim.broker_result_text=="requote|slippage:2.3|retry|comment",
              "delimiter characters: every field round-trips exactly despite embedded '|' and ':'");
   store.Close();
}

void TestRestartReload()
{
   long magic=990211;
   CleanupFilesFor(magic);
   {
      CMSZZExecutionIntentStore store1;
      store1.Configure("XAUUSD",PERIOD_M5,magic);
      store1.Load();
      MSZZExecutionIntent a=MakeIntent("RESTART-1","CLU-1","ORIG-1",magic,"inst-1");
      store1.CreateIntent(a);
      store1.Close(); // release exclusivity lock, simulating terminal shutdown
   }
   {
      CMSZZExecutionIntentStore store2;
      bool configured=store2.Configure("XAUUSD",PERIOD_M5,magic);
      AssertTrue(configured,"restart reload: a fresh store instance can acquire the lock after the prior one closed");
      AssertTrue(store2.Load(),"restart reload: load succeeds against the file written by the prior instance");
      AssertTrue(store2.Count()==1,"restart reload: the persisted intent survives the simulated restart");
      MSZZExecutionIntent back;
      AssertTrue(store2.FindById("RESTART-1",back) && back.cluster_id=="CLU-1",
                 "restart reload: recovered record content matches exactly");
      store2.Close();
   }
}

void TestTwoInstanceSeparation()
{
   // (a) Exclusivity: two store instances configured for the SAME filename must
   // not both hold the lock simultaneously.
   long magic=990212;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore first;
   AssertTrue(first.Configure("XAUUSD",PERIOD_M5,magic),"exclusivity: first instance acquires the lock");
   CMSZZExecutionIntentStore second;
   bool second_ok=second.Configure("XAUUSD",PERIOD_M5,magic);
   AssertTrue(!second_ok,"exclusivity: a second instance targeting the same file cannot also acquire it");
   first.Close();
   AssertTrue(second.Configure("XAUUSD",PERIOD_M5,magic),"exclusivity: the second instance can acquire the lock once the first releases it");
   second.Close();

   // (b) Filename separation: two different magic numbers must never collide.
   long magicA=990213, magicB=990214;
   CleanupFilesFor(magicA); CleanupFilesFor(magicB);
   CMSZZExecutionIntentStore storeA, storeB;
   storeA.Configure("XAUUSD",PERIOD_M5,magicA); storeA.Load();
   storeB.Configure("XAUUSD",PERIOD_M5,magicB); storeB.Load();
   storeA.CreateIntent(MakeIntent("SEP-A","CLU-A","ORIG-A",magicA,"inst-A"));
   storeB.CreateIntent(MakeIntent("SEP-B","CLU-B","ORIG-B",magicB,"inst-B"));
   AssertTrue(storeA.Count()==1 && storeB.Count()==1,"filename separation: each differently-configured store holds only its own record");
   MSZZExecutionIntent crossCheck;
   AssertTrue(!storeA.FindById("SEP-B",crossCheck),"filename separation: instance A never sees instance B's record");
   AssertTrue(!storeB.FindById("SEP-A",crossCheck),"filename separation: instance B never sees instance A's record");
   AssertTrue(storeA.PrimaryFilename()!=storeB.PrimaryFilename(),"filename separation: distinct magic numbers produce distinct filenames");
   storeA.Close(); storeB.Close();
}

void TestDeterministicSerialization()
{
   long magic=990215;
   CleanupFilesFor(magic);
   CMSZZExecutionIntentStore store;
   store.Configure("XAUUSD",PERIOD_M5,magic);
   store.Load();
   MSZZExecutionIntent a=MakeIntent("DET-1","CLU-1","ORIG-1",magic,"inst-1");
   store.CreateIntent(a);

   string first_content;
   RawReadWholeFile(store.PrimaryFilename(),first_content);

   // Re-save the exact same field values via UpdateIntent (a legitimate no-op
   // lifecycle update) and confirm the serialized record line is byte-identical.
   AssertTrue(store.UpdateIntent(a),"deterministic serialization: no-op update succeeds");
   string second_content;
   RawReadWholeFile(store.PrimaryFilename(),second_content);
   AssertTrue(first_content==second_content,"deterministic serialization: identical field values encode to byte-identical output");
   store.Close();
}

void OnStart()
{
   TestRoundTripAndMultipleRecords();
   TestDuplicateIntentRejection();
   TestTempWriteFailureAndRollback();
   TestPrimaryReplacementFailureAndRollback();
   TestTruncatedTempFileDoesNotCorruptStore();
   TestTruncatedPrimaryFileFailsClosed();
   TestCorruptChecksumFailsClosed();
   TestBackupRecoveryScenarios();
   TestSchemaVersionPreservation();
   TestLongIdsAndDelimiterCharacters();
   TestRestartReload();
   TestTwoInstanceSeparation();
   TestDeterministicSerialization();

   PrintFormat("MSZZ intent store test complete failures=%d",g_failures);
}
