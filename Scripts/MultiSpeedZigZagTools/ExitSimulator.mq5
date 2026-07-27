//+------------------------------------------------------------------+
//| ExitSimulator.mq5                                                 |
//| D021: Exit-Efficiency Study Phase 1. Replays a fixed SIGNAL_LEVEL |
//| entry set (from SignalSetExporter.mq5) against all 14 Phase-1     |
//| exit models, producing both SIGNAL_LEVEL (every signal, no        |
//| occupancy) and PORTFOLIO_LEVEL (one-owned-position, chronological |
//| occupancy per exit model) results. See DECISION_LOG.md D021.     |
//|                                                                    |
//| Design: every (signal, exit_model) pair is resolved exactly once  |
//| in the main loop below and its full result (exit time/price/      |
//| reason/final stop/trail updates/R) is stored. Both the            |
//| SIGNAL_LEVEL trade rows AND the PORTFOLIO_LEVEL occupancy pass     |
//| read from that same stored resolution -- occupancy never changes  |
//| what a trade's own outcome would have been, only whether it       |
//| counts as "taken" given what the account was doing at the time.   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include <MultiSpeedZigZag/Research/ExitSimulatorPolicy.mqh>
#include <MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh>

input string InpSignalSetFile="MSZZ_SignalSet.csv";
input string InpTradeOutputFile="MSZZ_ExitSim_Trades.csv";
input string InpSummaryOutputFile="MSZZ_ExitSim_Summary.csv";
input int    InpForwardWindowDays=3;      // shared MFE/MAE + exit-resolution reference window
input double InpMinMfeThresholdR=0.1;     // below this, percent_mfe_captured is null
input double InpEstimatedCostR=0.02;      // flat round-trip commission+spread estimate, in R -- see D021 caveat
input ENUM_MSZZ_AMBIGUITY_MODE InpAmbiguityMode=MSZZ_AMBIG_PESSIMISTIC; // primary evidence; rerun with OPTIMISTIC for the upper bound

#define MAX_SIGNALS 2000
#define MODEL_COUNT 14

//--- loaded signal set
string   g_sig_time_str[MAX_SIGNALS];
datetime g_sig_time[MAX_SIGNALS];
int      g_sig_direction[MAX_SIGNALS];
double   g_sig_entry[MAX_SIGNALS];
double   g_sig_stop[MAX_SIGNALS];
double   g_sig_target[MAX_SIGNALS];
string   g_sig_strategy_id[MAX_SIGNALS];
string   g_sig_cluster_id[MAX_SIGNALS];
int      g_signal_count=0;
string   g_symbol="XAUUSD";
ENUM_TIMEFRAMES g_period=PERIOD_M5;

//--- per (model,signal) resolved outcome, computed once, reused by both replay modes
bool     g_resolved[MODEL_COUNT][MAX_SIGNALS];
datetime g_entry_time[MAX_SIGNALS];
datetime g_exit_time[MODEL_COUNT][MAX_SIGNALS];
double   g_exit_price[MODEL_COUNT][MAX_SIGNALS];
string   g_exit_reason[MODEL_COUNT][MAX_SIGNALS];
double   g_gross_r[MODEL_COUNT][MAX_SIGNALS];
double   g_net_r[MODEL_COUNT][MAX_SIGNALS];
int      g_bars_held[MODEL_COUNT][MAX_SIGNALS];
double   g_final_stop[MODEL_COUNT][MAX_SIGNALS];
int      g_trail_updates[MODEL_COUNT][MAX_SIGNALS];
double   g_mfe_r[MAX_SIGNALS];
double   g_mae_r[MAX_SIGNALS];
int      g_bars_to_mfe[MAX_SIGNALS];
datetime g_time_to_mfe[MAX_SIGNALS];
string   g_session_text[MAX_SIGNALS];
string   g_weekday_text[MAX_SIGNALS];

//--- per-model accumulators for the summary pass (global, not stack-local,
//    to avoid relying on script stack-size limits for large fixed arrays)
double   g_sig_r_acc[MODEL_COUNT][MAX_SIGNALS];
int      g_sig_r_count[MODEL_COUNT];
double   g_port_r_acc[MODEL_COUNT][MAX_SIGNALS];
int      g_port_r_count[MODEL_COUNT];
int      g_port_skipped[MODEL_COUNT];
int      g_port_qualifying[MODEL_COUNT];

int ParseDirection(const string s) { return (s=="L" || s=="LONG") ? 1 : -1; }

string WeekdayName(const datetime t)
{
   MqlDateTime dt; TimeToStruct(t,dt);
   string names[7]={"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"};
   return names[dt.day_of_week];
}

datetime SessionBoundary(const datetime entry_time)
{
   MqlDateTime dt; TimeToStruct(entry_time,dt);
   int hour=dt.hour;
   int bucket_end_hour=(hour<8)?8:(hour<16?16:24);
   dt.hour=0; dt.min=0; dt.sec=0;
   datetime day_start=StructToTime(dt);
   return day_start+bucket_end_hour*3600;
}

bool LoadSignalSet()
{
   int h=FileOpen(InpSignalSetFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("MSZZ ExitSimulator: failed to open %s error=%d",InpSignalSetFile,GetLastError());
      return false;
   }
   for(int c=0;c<10 && !FileIsEnding(h);c++) FileReadString(h); // header

   g_signal_count=0;
   while(!FileIsEnding(h) && g_signal_count<MAX_SIGNALS)
   {
      string f[10];
      bool complete=true;
      for(int c=0;c<10;c++)
      {
         if(FileIsEnding(h)) { complete=false; break; }
         f[c]=FileReadString(h);
      }
      if(!complete) break;

      int i=g_signal_count;
      g_sig_time_str[i]=f[0];
      g_sig_time[i]=StringToTime(f[0]);
      g_sig_direction[i]=ParseDirection(f[1]);
      g_sig_entry[i]=StringToDouble(f[2]);
      g_sig_stop[i]=StringToDouble(f[3]);
      g_sig_target[i]=StringToDouble(f[4]);
      g_sig_strategy_id[i]=f[5];
      g_sig_cluster_id[i]=f[6];
      if(i==0) g_symbol=f[8];
      g_signal_count++;
   }
   FileClose(h);
   PrintFormat("MSZZ ExitSimulator: loaded %d signals from %s",g_signal_count,InpSignalSetFile);
   return g_signal_count>0;
}

int BuildExitModels(MSZZExitParams &models[],string &model_names[])
{
   ArrayResize(models,MODEL_COUNT); ArrayResize(model_names,MODEL_COUNT);
   int n=0;

   ENUM_MSZZ_EXIT_MODEL fixed_ids[4]={MSZZ_EXIT_FIXED_1R,MSZZ_EXIT_FIXED_1_5R,MSZZ_EXIT_FIXED_2R,MSZZ_EXIT_FIXED_3R};
   double fixed_r[4]={1.0,1.5,2.0,3.0};
   string fixed_names[4]={"FIXED_1R","FIXED_1_5R","FIXED_2R","FIXED_3R"};
   for(int i=0;i<4;i++)
   {
      ZeroMemory(models[n]);
      models[n].model=fixed_ids[i]; models[n].fixed_r_multiple=fixed_r[i];
      model_names[n]=fixed_names[i]; n++;
   }

   ENUM_MSZZ_EXIT_MODEL be_ids[3]={MSZZ_EXIT_BE_0_5R,MSZZ_EXIT_BE_0_75R,MSZZ_EXIT_BE_1R};
   double be_trig[3]={0.5,0.75,1.0};
   string be_names[3]={"BE_0_5R","BE_0_75R","BE_1R"};
   for(int i=0;i<3;i++)
   {
      ZeroMemory(models[n]);
      models[n].model=be_ids[i]; models[n].be_trigger_r=be_trig[i];
      model_names[n]=be_names[i]; n++;
   }

   ZeroMemory(models[n]);
   models[n].model=MSZZ_EXIT_BE_PLUS_COSTS; models[n].be_trigger_r=1.0; // offset set per-trade below
   model_names[n]="BE_PLUS_COSTS"; n++;

   ZeroMemory(models[n]);
   models[n].model=MSZZ_EXIT_TRAIL_0_5R_AFTER_1R; models[n].trail_trigger_r=1.0; models[n].trail_distance_r=0.5;
   model_names[n]="TRAIL_0_5R_AFTER_1R"; n++;

   ENUM_MSZZ_EXIT_MODEL time_ids[4]={MSZZ_EXIT_TIME_4H,MSZZ_EXIT_TIME_8H,MSZZ_EXIT_TIME_12H,MSZZ_EXIT_TIME_24H};
   long time_secs[4]={14400,28800,43200,86400};
   string time_names[4]={"TIME_4H","TIME_8H","TIME_12H","TIME_24H"};
   for(int i=0;i<4;i++)
   {
      ZeroMemory(models[n]);
      models[n].model=time_ids[i]; models[n].time_limit_seconds=time_secs[i];
      model_names[n]=time_names[i]; n++;
   }

   ZeroMemory(models[n]);
   models[n].model=MSZZ_EXIT_SESSION_CLOSE; // session_boundary set per-trade below
   model_names[n]="SESSION_CLOSE"; n++;

   return n;
}

void WriteTradeRow(const int h,const string replay_mode,const int s,const int m,
                    const string model_name,const bool skipped)
{
   if(skipped)
   {
      FileWrite(h,replay_mode,g_sig_strategy_id[s],model_name,g_sig_cluster_id[s],
                (g_sig_direction[s]>0?"L":"S"),TimeToString(g_entry_time[s],TIME_DATE|TIME_SECONDS),
                "","SKIPPED_WHILE_OCCUPIED","","","","","","","","","","","","","","","","","","","","","","true");
      return;
   }
   if(!g_resolved[m][s]) return; // insufficient forward data -- not written as a row at all, not faked

   double risk=MathAbs(g_sig_entry[s]-g_sig_stop[s]);
   int minutes_held=(int)((g_exit_time[m][s]-g_entry_time[s])/60);
   double surrender_r=g_mfe_r[s]-g_net_r[m][s];
   double pct_captured=0.0;
   bool pct_valid=CMSZZExitSimulatorPolicy::PercentMfeCaptured(g_net_r[m][s],g_mfe_r[s],InpMinMfeThresholdR,pct_captured);
   bool r_0_5=(g_mfe_r[s]>=0.5), r_1=(g_mfe_r[s]>=1.0), r_1_5=(g_mfe_r[s]>=1.5), r_2=(g_mfe_r[s]>=2.0), r_3=(g_mfe_r[s]>=3.0);
   bool r_1_then_neg=(g_mfe_r[s]>=1.0 && g_net_r[m][s]<0.0);

   FileWrite(h,replay_mode,g_sig_strategy_id[s],model_name,g_sig_cluster_id[s],
             (g_sig_direction[s]>0?"L":"S"),TimeToString(g_entry_time[s],TIME_DATE|TIME_SECONDS),
             TimeToString(g_exit_time[m][s],TIME_DATE|TIME_SECONDS),g_exit_reason[m][s],
             DoubleToString(g_sig_entry[s],5),DoubleToString(g_sig_stop[s],5),DoubleToString(risk,5),
             DoubleToString(g_gross_r[m][s],4),DoubleToString(g_net_r[m][s],4),
             DoubleToString(g_mfe_r[s],4),DoubleToString(g_mae_r[s],4),
             g_bars_to_mfe[s],(int)((g_time_to_mfe[s]-g_entry_time[s])/60),
             g_bars_held[m][s],minutes_held,DoubleToString(surrender_r,4),
             (pct_valid?DoubleToString(pct_captured,4):"null"),
             (r_0_5?"true":"false"),(r_1?"true":"false"),(r_1_5?"true":"false"),(r_2?"true":"false"),(r_3?"true":"false"),
             (r_1_then_neg?"true":"false"),g_trail_updates[m][s],DoubleToString(g_final_stop[m][s],5),
             EnumToString(InpAmbiguityMode),g_session_text[s],g_weekday_text[s],"false");
}

void OnStart()
{
   if(!LoadSignalSet()) return;

   MSZZExitParams models[]; string model_names[];
   int model_count=BuildExitModels(models,model_names);

   int window_bars=(int)((InpForwardWindowDays*86400)/PeriodSeconds(g_period))+10;
   int unresolved_no_data=0;

   //--- Main loop: resolve every (signal, model) pair exactly once.
   for(int s=0;s<g_signal_count;s++)
   {
      datetime entry_time=g_sig_time[s]+PeriodSeconds(g_period); // fill lags signal by one bar, matching the live EA
      g_entry_time[s]=entry_time;
      double entry=g_sig_entry[s], stop=g_sig_stop[s], target=g_sig_target[s];
      int dir=g_sig_direction[s];
      double risk=MathAbs(entry-stop);
      if(risk<=0.0) { unresolved_no_data++; for(int m=0;m<model_count;m++) g_resolved[m][s]=false; continue; }

      MqlRates rates[];
      // Time-range overload, not (start_time,count): the latter treats
      // start_time as a "most recent as of" reference and copies BACKWARD
      // from it, confirmed empirically (exit_time was landing before
      // entry_time). The range form is unambiguous: everything in
      // [entry_time, entry_time+window] going forward.
      datetime window_end=entry_time+(datetime)(window_bars*PeriodSeconds(g_period));
      int copied=CopyRates(g_symbol,g_period,entry_time,window_end,rates);
      if(copied<=0) { unresolved_no_data++; for(int m=0;m<model_count;m++) g_resolved[m][s]=false; continue; }

      MSZZExitBar bars[]; ArrayResize(bars,copied);
      for(int b=0;b<copied;b++)
      {
         bars[b].time=rates[b].time; bars[b].high=rates[b].high;
         bars[b].low=rates[b].low; bars[b].close=rates[b].close;
      }

      double mfe_r,mae_r; int bars_to_mfe; datetime time_to_mfe;
      CMSZZExitSimulatorPolicy::ComputeMfeMae(entry,risk,dir,bars,copied,mfe_r,mae_r,bars_to_mfe,time_to_mfe);
      g_mfe_r[s]=mfe_r; g_mae_r[s]=mae_r; g_bars_to_mfe[s]=bars_to_mfe; g_time_to_mfe[s]=time_to_mfe;

      int session_hour; { MqlDateTime dtm; TimeToStruct(entry_time,dtm); session_hour=dtm.hour; }
      g_session_text[s]=MSZZSessionText(CMSZZTradeAnalyticsPolicy::SessionBucket(session_hour));
      g_weekday_text[s]=WeekdayName(entry_time);

      for(int m=0;m<model_count;m++)
      {
         MSZZExitParams p=models[m];
         if(p.model==MSZZ_EXIT_BE_PLUS_COSTS) p.be_offset_price=InpEstimatedCostR*risk;
         if(p.model==MSZZ_EXIT_SESSION_CLOSE) p.session_boundary=SessionBoundary(entry_time);

         MSZZExitResult r;
         CMSZZExitSimulatorPolicy::SimulateExit(dir,entry,stop,risk,target,bars,copied,p,InpAmbiguityMode,r);

         g_resolved[m][s]=r.resolved;
         if(!r.resolved) continue;

         g_exit_time[m][s]=r.exit_time;
         g_exit_price[m][s]=r.exit_price;
         g_exit_reason[m][s]=r.exit_reason;
         g_final_stop[m][s]=r.final_stop;
         g_trail_updates[m][s]=r.number_of_trail_updates;
         g_gross_r[m][s]=CMSZZExitSimulatorPolicy::RMultiple(r.exit_price,entry,risk,dir);
         g_net_r[m][s]=g_gross_r[m][s]-InpEstimatedCostR;
         int bars_held=0;
         for(int b=0;b<copied;b++) if(bars[b].time==r.exit_time) { bars_held=b+1; break; }
         g_bars_held[m][s]=bars_held;
      }
   }

   //--- Write per-trade rows: SIGNAL_LEVEL (every resolved signal, no
   //    occupancy) then PORTFOLIO_LEVEL (chronological occupancy per model).
   int trade_h=FileOpen(InpTradeOutputFile,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(trade_h==INVALID_HANDLE) { PrintFormat("MSZZ ExitSimulator: trade output open failed error=%d",GetLastError()); return; }
   FileWrite(trade_h,"replay_mode","strategy_id","exit_model","cluster_id","direction","entry_time","exit_time",
             "exit_reason","entry_price","initial_stop","initial_risk","gross_r","net_r_after_costs","mfe_r","mae_r",
             "bars_to_mfe","minutes_to_mfe","bars_held","minutes_held","surrender_r","percent_mfe_captured",
             "reached_0_5r","reached_1r","reached_1_5r","reached_2r","reached_3r","reached_1r_then_negative",
             "number_of_trail_updates","final_stop","replay_price_mode","session","weekday","skipped_while_occupied");

   // Per-model accumulators for the summary pass (SIGNAL_LEVEL and PORTFOLIO_LEVEL).
   for(int m=0;m<model_count;m++)
   {
      g_sig_r_count[m]=0; g_port_r_count[m]=0; g_port_skipped[m]=0; g_port_qualifying[m]=0;

      for(int s=0;s<g_signal_count;s++)
      {
         if(!g_resolved[m][s]) continue;
         WriteTradeRow(trade_h,"SIGNAL_LEVEL",s,m,model_names[m],false);
         g_sig_r_acc[m][g_sig_r_count[m]]=g_net_r[m][s]; g_sig_r_count[m]++;
      }

      datetime occupied_until=0;
      for(int s=0;s<g_signal_count;s++)
      {
         if(!g_resolved[m][s]) continue;
         g_port_qualifying[m]++;
         if(g_entry_time[s]<occupied_until)
         {
            g_port_skipped[m]++;
            WriteTradeRow(trade_h,"PORTFOLIO_LEVEL",s,m,model_names[m],true);
            continue;
         }
         occupied_until=g_exit_time[m][s];
         WriteTradeRow(trade_h,"PORTFOLIO_LEVEL",s,m,model_names[m],false);
         g_port_r_acc[m][g_port_r_count[m]]=g_net_r[m][s]; g_port_r_count[m]++;
      }
   }
   FileClose(trade_h);

   //--- Aggregate summary: SIGNAL_LEVEL and PORTFOLIO_LEVEL per model,
   //    reusing D017's CMSZZRunSummaryPolicy (WinRate/ProfitFactorR/
   //    MaxDrawdownR/Average) rather than reimplementing them.
   int summary_h=FileOpen(InpSummaryOutputFile,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(summary_h==INVALID_HANDLE) { PrintFormat("MSZZ ExitSimulator: summary output open failed error=%d",GetLastError()); return; }
   FileWrite(summary_h,"replay_mode","exit_model","trades","win_rate","expectancy_r","profit_factor_r",
             "max_drawdown_r","qualifying_signals","skipped_while_occupied","occupancy_pct");

   for(int m=0;m<model_count;m++)
   {
      if(g_sig_r_count[m]>0)
      {
         double vals[]; ArrayResize(vals,g_sig_r_count[m]);
         for(int i=0;i<g_sig_r_count[m];i++) vals[i]=g_sig_r_acc[m][i];
         FileWrite(summary_h,"SIGNAL_LEVEL",model_names[m],g_sig_r_count[m],
                   DoubleToString(CMSZZRunSummaryPolicy::WinRate(vals,g_sig_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::Average(vals,g_sig_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::ProfitFactorR(vals,g_sig_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::MaxDrawdownR(vals,g_sig_r_count[m]),4),
                   g_sig_r_count[m],"","");
      }
      if(g_port_qualifying[m]>0 && g_port_r_count[m]>0)
      {
         double vals[]; ArrayResize(vals,g_port_r_count[m]);
         for(int i=0;i<g_port_r_count[m];i++) vals[i]=g_port_r_acc[m][i];
         double occ_pct=100.0*g_port_skipped[m]/g_port_qualifying[m];
         FileWrite(summary_h,"PORTFOLIO_LEVEL",model_names[m],g_port_r_count[m],
                   DoubleToString(CMSZZRunSummaryPolicy::WinRate(vals,g_port_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::Average(vals,g_port_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::ProfitFactorR(vals,g_port_r_count[m]),4),
                   DoubleToString(CMSZZRunSummaryPolicy::MaxDrawdownR(vals,g_port_r_count[m]),4),
                   g_port_qualifying[m],g_port_skipped[m],DoubleToString(occ_pct,2));
      }
   }
   FileClose(summary_h);

   PrintFormat("MSZZ ExitSimulator complete: signals=%d unresolved_no_data=%d models=%d -> %s / %s",
               g_signal_count,unresolved_no_data,model_count,InpTradeOutputFile,InpSummaryOutputFile);
}
