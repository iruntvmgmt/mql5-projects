//+------------------------------------------------------------------+
//| SignalSetExporter.mq5                                             |
//| D021: exports the immutable SIGNAL_LEVEL entry set from an        |
//| already-completed run's MSZZ_SignalJournal.csv -- every signal    |
//| that passed every guard except (possibly) occupancy. The union of |
//| EXECUTED and REJECT_OWNERSHIP journal rows is exactly this set;   |
//| no new EA instrumentation is required. See DECISION_LOG.md D021. |
//|                                                                    |
//| Reads whole LINES (FILE_TXT, not FILE_CSV) and splits each one    |
//| independently on ';', rather than reading a fixed token count     |
//| across the whole file -- confirmed necessary: the journal's       |
//| free-text `reason` column occasionally contains an embedded       |
//| semicolon (e.g. an ORDER_FAILED retcode message), which would     |
//| otherwise desync a fixed-column-count reader for every row after  |
//| the first occurrence. Splitting per-line contains the damage to   |
//| that one row's own trailing (unused) reason text.                 |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input string InpInputJournalFile="MSZZ_SignalJournal.csv";
input string InpOutputFile="MSZZ_SignalSet.csv";

// MSZZ_SignalJournal.csv columns (written by MultiSpeedZigZagEA.mq5's
// JournalCandidate()):
// time;symbol;timeframe;status;cluster_id;strategy_id;setup;direction;score;entry;stop;target;origin_id;event_id;reason
#define COL_TIME 0
#define COL_SYMBOL 1
#define COL_TIMEFRAME 2
#define COL_STATUS 3
#define COL_CLUSTER_ID 4
#define COL_STRATEGY_ID 5
#define COL_SETUP 6
#define COL_DIRECTION 7
#define COL_SCORE 8
#define COL_ENTRY 9
#define COL_STOP 10
#define COL_TARGET 11
#define COL_ORIGIN_ID 12
#define COL_EVENT_ID 13
#define COL_REASON 14
#define JOURNAL_COL_COUNT 15

void OnStart()
{
   int in_handle=FileOpen(InpInputJournalFile,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(in_handle==INVALID_HANDLE)
   {
      PrintFormat("MSZZ SignalSetExporter: failed to open %s error=%d",InpInputJournalFile,GetLastError());
      return;
   }

   int out_handle=FileOpen(InpOutputFile,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(out_handle==INVALID_HANDLE)
   {
      PrintFormat("MSZZ SignalSetExporter: failed to open %s for writing error=%d",InpOutputFile,GetLastError());
      FileClose(in_handle);
      return;
   }
   FileWrite(out_handle,"signal_time","direction","entry","stop","target","strategy_id","cluster_id","score","symbol","timeframe");

   FileReadString(in_handle); // header line, discarded

   int total_rows=0, exported=0, executed_count=0, reject_ownership_count=0, malformed_rows=0;
   while(!FileIsEnding(in_handle))
   {
      string line=FileReadString(in_handle);
      if(StringLen(line)==0 && FileIsEnding(in_handle)) break;

      string field[];
      int n=StringSplit(line,';',field);
      if(n<JOURNAL_COL_COUNT)
      {
         malformed_rows++;
         continue; // fewer columns than expected -- skip rather than misread, and count it
      }
      total_rows++;

      string status=field[COL_STATUS];
      if(status=="EXECUTED") executed_count++;
      else if(status=="REJECT_OWNERSHIP") reject_ownership_count++;
      else continue;

      FileWrite(out_handle,field[COL_TIME],field[COL_DIRECTION],field[COL_ENTRY],field[COL_STOP],
                field[COL_TARGET],field[COL_STRATEGY_ID],field[COL_CLUSTER_ID],field[COL_SCORE],
                field[COL_SYMBOL],field[COL_TIMEFRAME]);
      exported++;
   }

   FileClose(in_handle);
   FileClose(out_handle);

   PrintFormat("MSZZ SignalSetExporter complete: total_rows=%d exported=%d (executed=%d reject_ownership=%d) malformed_skipped=%d -> %s",
               total_rows,exported,executed_count,reject_ownership_count,malformed_rows,InpOutputFile);
}
