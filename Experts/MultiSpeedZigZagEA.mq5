//+------------------------------------------------------------------+
//| MultiSpeedZigZagEA.mq5                                           |
//+------------------------------------------------------------------+
#property strict
#property version   "0.410"
#property description "Standalone Multi-Speed ZigZag strategy suite"

#include <Trade/Trade.mqh>
#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>
#include <MultiSpeedZigZag/Arbitration/OpportunityClusterEngine.mqh>
#include <MultiSpeedZigZag/Execution/EventStore.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionGuard.mqh>
#include <MultiSpeedZigZag/Execution/PositionOwnership.mqh>
#include <MultiSpeedZigZag/Execution/PositionOwnershipPolicy.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionIntentStore.mqh>
#include <MultiSpeedZigZag/Execution/ExecutionReconciler.mqh>
#include <MultiSpeedZigZag/Execution/IntentStateMachine.mqh>
#include <MultiSpeedZigZag/Execution/ProtectionGuard.mqh>
#include <MultiSpeedZigZag/Execution/MarginGuard.mqh>
#include <MultiSpeedZigZag/Execution/AccountSafeguard.mqh>
#include <MultiSpeedZigZag/Diagnostics/TradeAnalyticsExporter.mqh>
#include <MultiSpeedZigZag/Research/ResearchEligibilityPolicy.mqh>

// D019: hardcoded, not user-suppliable -- see DECISION_LOG.md D019 for why
// the authorized login is a compile-time constant rather than an input.
#define MSZZ_RESEARCH_AUTHORIZED_DEMO_LOGIN 870012

input group "═══ Operating Mode ═══"
input bool   InpShadowOnly=true;
input bool   InpAllowLiveExecution=false;
input bool   InpAcknowledgeRisk=false;
input long   InpMagic=26072501;
input int    InpHistoryBars=1500;

input group "═══ Fast Speed ═══"
input int    InpFastATRLen=14;
input double InpFastATRMult=1.0;
input group "═══ Medium Speed ═══"
input int    InpMedATRLen=14;
input double InpMedATRMult=2.0;
input group "═══ Slow Speed ═══"
input int    InpSlowATRLen=14;
input double InpSlowATRMult=3.5;

input group "═══ Strategy Enablement ═══"
input bool InpEnableFastBreakout=true;
input bool InpEnableMediumBreakout=true;
input bool InpEnableSlowBreakout=true;
input bool InpEnableFastMedConfluence=true;
input bool InpEnableFastMedContext=true;
input bool InpEnableMedSlowContext=true;
input bool InpEnableNestedPullback=true;
input bool InpEnableWeightedEnsemble=true;

input group "═══ Structure & Signal ═══"
input int    InpMinBarsBetween=3;
input double InpMinScore=5.0;
input double InpResearchMinScoreOverride=0.0;
input bool   InpAcknowledgeResearchOverride=false;
input double InpRiskReward=1.5;
input bool   InpOneOwnedPositionPerSymbol=true;
input int    InpSignalValidityBars=3;

input group "═══ Standalone Execution ═══"
input double InpFixedLots=0.01;
input double InpMaxSpreadPoints=80.0;
input int    InpDeviationPoints=30;
input bool   InpExitOwnedOpposite=true;
// D025: research-only mechanism-decomposition inputs, all default to a
// no-op so canonical behavior is unchanged unless explicitly opted in.
// See DECISION_LOG.md D025.
input bool   InpSuppressReversalEntry=false;  // close on opposite signal, but do not let that same signal reverse into a new position
input bool   InpDisableFixedTarget=false;     // structural stop only, no take-profit -- exits via SL or opposite-signal reversal only
input double InpPartialCloseAtR=0.0;          // 0=disabled; else close InpPartialCloseFraction of volume once floating R reaches this on a closed bar
input double InpPartialCloseFraction=0.5;
input int    InpMaxPersistentEvents=2000;
input double InpMarginBufferRatio=1.0;

input group "═══ Account Safeguards ═══"
input bool   InpKillSwitchEngaged=false;
input int    InpMaxTradesPerDay=20;
input double InpMaxDailyLossAmount=0.0;

input group "═══ Diagnostics ═══"
input bool InpWriteCSV=true;
input bool InpVerboseLog=true;

CMSZZTripleZigZagEngine       g_engine;
CMSZZStrategySuite            g_suite;
CMSZZOpportunityClusterEngine g_cluster_engine;
CMSZZEventStore                g_event_store;
CMSZZExecutionGuard            g_execution_guard;
CMSZZPositionOwnership         g_ownership;
CMSZZExecutionIntentStore      g_intent_store;
CMSZZExecutionReconciler       g_reconciler;
CMSZZProtectionGuard           g_protection;
CMSZZMarginGuard               g_margin;
CMSZZAccountSafeguardGuard      g_safeguard;
CMSZZTradeAnalyticsExporter     g_trade_analytics;
CTrade                         g_trade;
datetime                       g_last_bar=0;
string                         g_instance_id="";
bool                           g_recovery_required=false;
// D019: computed once in OnInit() after the fail-closed authorization
// check passes; both existing InpMinScore comparison sites read this
// instead, so the two gates can never disagree about which threshold
// is in effect.
double                         g_effective_min_score=0.0;
bool                           g_research_mode_active=false;
// D025 variants G/H: research-only, in-memory (non-persistent across
// restarts) record of tickets already partially closed by
// ProcessPartialCloses(). Not integrated with ExecutionIntentStore --
// explicitly out of scope for a bounded mechanism-decomposition study.
// See DECISION_LOG.md D025.
ulong                          g_partial_closed_tickets[];

bool LiveExecutionAuthorized(){ return (!InpShadowOnly && InpAllowLiveExecution && InpAcknowledgeRisk); }
bool EventConsumed(const string id){ return g_event_store.Contains(id); }
bool ConsumeEvent(const string id){ return g_event_store.Add(id); }

void JournalCandidate(const MSZZCandidate &c,const string status,const string cluster_id="")
{
   if(InpVerboseLog)
      PrintFormat("MSZZ %s %s cluster=%s score=%.2f entry=%.*f stop=%.*f target=%.*f origin=%s event=%s reason=%s",
                  status,c.setup_name,cluster_id,c.score,_Digits,c.entry,_Digits,c.stop,_Digits,c.target,c.origin_id,c.event_id,c.reason);
   if(!InpWriteCSV) return;
   int h=FileOpen("MSZZ_SignalJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE){ PrintFormat("MSZZ journal open failed error=%d",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","timeframe","status","cluster_id","strategy_id","setup","direction","score","entry","stop","target","origin_id","event_id","reason");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(c.signal_time,TIME_DATE|TIME_SECONDS),_Symbol,EnumToString(_Period),status,cluster_id,
             (int)c.strategy_id,c.setup_name,MSZZDirectionText(c.direction),DoubleToString(c.score,2),
             DoubleToString(c.entry,_Digits),DoubleToString(c.stop,_Digits),DoubleToString(c.target,_Digits),
             c.origin_id,c.event_id,c.reason);
   FileFlush(h); FileClose(h);
}

void JournalCluster(const MSZZOpportunityCluster &cluster,const string status)
{
   if(InpVerboseLog)
      PrintFormat("MSZZ CLUSTER %s id=%s owner=%d score=%.2f support=%d evidence=%d stop_disagreement=%.*f",
                  status,cluster.cluster_id,(int)cluster.owner_strategy_id,cluster.combined_score,
                  cluster.support_count,cluster.evidence_mask,_Digits,cluster.stop_disagreement);
}

void JournalOwnership(const MSZZOwnershipSnapshot &snapshot,const string status)
{
   if(!InpVerboseLog) return;
   PrintFormat("MSZZ OWNERSHIP %s mode=%s symbol_total=%d owned=%d long=%d short=%d manual=%d foreign=%d err=%s",
               status,CMSZZPositionOwnership::AccountModeText(snapshot.account_mode),snapshot.total_symbol_positions,
               snapshot.owned_positions,snapshot.owned_longs,snapshot.owned_shorts,
               snapshot.manual_positions,snapshot.foreign_positions,snapshot.error_reason);
}

bool RefreshOwnership(string &reason)
{
   reason="";
   if(!g_ownership.Refresh())
   {
      MSZZOwnershipSnapshot failed=g_ownership.Snapshot();
      JournalOwnership(failed,"REFRESH_FAILED");
      reason=(failed.error_reason!="" ? failed.error_reason : "ownership refresh failed");
      return false;
   }
   JournalOwnership(g_ownership.Snapshot(),"REFRESHED");
   return true;
}

// D025: closed_opposite reports whether THIS call actually closed an owned
// opposite position (i.e. the candidate's own arrival triggered the close),
// distinct from simply "InpExitOwnedOpposite is enabled" -- consumed by
// InpSuppressReversalEntry in ExecuteCluster(). See DECISION_LOG.md D025.
bool ApplyOwnershipPreflight(const ENUM_MSZZ_DIRECTION desired,string &reason,bool &closed_opposite)
{
   reason=""; closed_opposite=false;
   if(!RefreshOwnership(reason)) return false;

   MSZZOwnershipSnapshot before=g_ownership.Snapshot();
   if(!g_ownership.ExecutionAllowedForAccountMode(reason)) return false;

   if(!g_ownership.CloseOwnedOpposite(g_trade,desired,InpExitOwnedOpposite,reason)) return false;

   if(InpExitOwnedOpposite && ((desired==MSZZ_DIR_LONG && before.owned_shorts>0) ||
                               (desired==MSZZ_DIR_SHORT && before.owned_longs>0)))
   {
      closed_opposite=true;
      if(!RefreshOwnership(reason)) return false;
   }

   MSZZOwnershipSnapshot after=g_ownership.Snapshot();
   if(!CMSZZPositionOwnershipPolicy::CanOpen(after,InpOneOwnedPositionPerSymbol,reason)) return false;
   return true;
}

bool PrepareMarketCandidate(const MSZZCandidate &source,MSZZCandidate &prepared,string &reason)
{
   prepared=source;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)){ reason="no current tick"; return false; }
   prepared.entry=(source.direction==MSZZ_DIR_LONG ? tick.ask : tick.bid);
   double risk=MathAbs(prepared.entry-source.stop);
   if(risk<=0.0){ reason="market entry equals structural stop"; return false; }
   // D025 variant F: no fixed take-profit at all -- exits via SL or
   // opposite-signal reversal only. See DECISION_LOG.md D025.
   prepared.target=InpDisableFixedTarget ? 0.0 :
      (source.direction==MSZZ_DIR_LONG ? prepared.entry+risk*InpRiskReward : prepared.entry-risk*InpRiskReward);
   return g_execution_guard.ValidateStops(prepared,prepared.stop,prepared.target,reason,InpDisableFixedTarget);
}

bool ExecuteCluster(const MSZZOpportunityCluster &cluster,const MSZZCandidate &owner)
{
   string persistence_id=cluster.cluster_id;
   if(!LiveExecutionAuthorized())
   {
      JournalCluster(cluster,"SHADOW");
      JournalCandidate(owner,"SHADOW",cluster.cluster_id);
      return true;
   }

   // D015: reject a stale signal before any other consideration, including
   // whether it would have scored well enough to execute. Checked against
   // cluster.expiry_time (the cluster-level aggregated value the cluster
   // engine already computes as the earliest constituent candidate's
   // expiry), not owner.expiry_time. See DECISION_LOG.md D015 -- this is
   // not currently expected to ever fire, since candidates are generated
   // and acted upon synchronously in the same OnTick() call, but exists as
   // defense-in-depth for the day any retry/queueing logic is added.
   if(CMSZZExecutionGuard::IsExpired(TimeCurrent(),cluster.expiry_time))
   {
      MSZZCandidate rejected=owner;
      rejected.reason=StringFormat("signal expired at %s",TimeToString(cluster.expiry_time,TIME_DATE|TIME_SECONDS));
      JournalCandidate(rejected,"REJECT_EXPIRED",cluster.cluster_id);
      return false;
   }

   if(cluster.combined_score<g_effective_min_score){ JournalCandidate(owner,"REJECT_SCORE",cluster.cluster_id); return false; }
   if(EventConsumed(persistence_id)){ JournalCandidate(owner,"REJECT_DUPLICATE_CLUSTER",cluster.cluster_id); return false; }

   // D009/D011: a RECOVERY_REQUIRED (unresolved broker state) or
   // PROTECTION_FAILED (an open position whose SL/TP could not be repaired)
   // intent blocks all new live execution for this symbol/magic until an
   // operator clears it out-of-band. See DECISION_LOG.md D009 failure policy
   // and D011 for why PROTECTION_FAILED shares this same gate.
   if(g_recovery_required)
   {
      MSZZCandidate rejected=owner;
      rejected.reason="one or more execution intents require manual recovery (see MSZZ RECONCILE/PROTECTION log)";
      JournalCandidate(rejected,"REJECT_RECOVERY_REQUIRED",cluster.cluster_id);
      return false;
   }

   // D013: kill switch, daily trade-count limit, and daily realized-loss
   // limit -- checked first among the per-attempt guards, as cheaply as
   // possible, since a breached account safeguard should short-circuit
   // everything else. See DECISION_LOG.md D013 for scope and defaults.
   string safeguard_reason;
   if(!g_safeguard.CheckSafeguards(_Symbol,InpMagic,InpMaxTradesPerDay,InpMaxDailyLossAmount,
                                    InpKillSwitchEngaged,safeguard_reason))
   {
      MSZZCandidate rejected=owner; rejected.reason=safeguard_reason;
      JournalCandidate(rejected,"REJECT_ACCOUNT_SAFEGUARD",cluster.cluster_id);
      return false;
   }

   string reason;
   if(!g_execution_guard.TradingAllowed(reason))
   {
      MSZZCandidate rejected=owner; rejected.reason=reason;
      JournalCandidate(rejected,"REJECT_TRADING_DISABLED",cluster.cluster_id); return false;
   }
   double spread_points=0.0;
   if(!g_execution_guard.SpreadAllowed(InpMaxSpreadPoints,spread_points))
   {
      MSZZCandidate rejected=owner;
      rejected.reason=StringFormat("spread %.1f exceeds maximum %.1f points",spread_points,InpMaxSpreadPoints);
      JournalCandidate(rejected,"REJECT_SPREAD",cluster.cluster_id); return false;
   }

   MSZZCandidate prepared;
   if(!PrepareMarketCandidate(owner,prepared,reason))
   {
      MSZZCandidate rejected=owner; rejected.reason=reason;
      JournalCandidate(rejected,"REJECT_STOPS",cluster.cluster_id); return false;
   }
   double volume=g_execution_guard.NormalizeVolume(InpFixedLots);
   if(volume<=0.0){ prepared.reason="volume normalization failed"; JournalCandidate(prepared,"REJECT_VOLUME",cluster.cluster_id); return false; }

   // D012: fail closed before any state-mutating call if the account cannot
   // comfortably afford this order. See DECISION_LOG.md D012 for why
   // OrderCalcMargin() (broker-authoritative) is used instead of a manual
   // formula, and why InpMarginBufferRatio defaults to requiring double the
   // bare minimum required margin.
   ENUM_ORDER_TYPE order_type=(prepared.direction==MSZZ_DIR_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double required_margin,free_margin;
   string margin_reason;
   if(!g_margin.CheckMargin(_Symbol,order_type,volume,prepared.entry,InpMarginBufferRatio,required_margin,free_margin,margin_reason))
   {
      prepared.reason=margin_reason;
      JournalCandidate(prepared,"REJECT_MARGIN",cluster.cluster_id);
      return false;
   }

   bool closed_opposite=false;
   if(!ApplyOwnershipPreflight(prepared.direction,reason,closed_opposite))
   {
      prepared.reason=reason;
      JournalCandidate(prepared,"REJECT_OWNERSHIP",cluster.cluster_id);
      return false;
   }

   // D025 variant C: the close-on-opposite-signal behavior is retained
   // (it already happened, above), but the same triggering signal is not
   // allowed to reverse into a new position -- a later, independent
   // cluster may still enter normally. The cluster is still marked
   // consumed so this same signal is not retried. See DECISION_LOG.md D025.
   if(InpSuppressReversalEntry && closed_opposite)
   {
      if(!ConsumeEvent(persistence_id))
      {
         prepared.reason="execution intent persistence failed after suppressed reversal, order not attempted";
         JournalCandidate(prepared,"REJECT_INTENT_PERSISTENCE",cluster.cluster_id);
         return false;
      }
      prepared.reason="reversal entry suppressed by InpSuppressReversalEntry after closing owned opposite position";
      JournalCandidate(prepared,"SUPPRESSED_REVERSAL_ENTRY",cluster.cluster_id);
      return true;
   }

   // D006 idempotent execution-intent persistence: durably mark this cluster
   // consumed BEFORE attempting to submit the order, and fail closed if that
   // write does not succeed. This makes execution idempotent with respect to
   // persistence-layer failures -- a live order attempt and its durable
   // consumed-event record can never be split by an I/O failure, because the
   // record is written first and gates the attempt. The trade-off (accepted,
   // see DECISION_LOG.md D006): if the order itself is then rejected by the
   // broker, this cluster will not be retried even though no position opened.
   if(!ConsumeEvent(persistence_id))
   {
      prepared.reason="execution intent persistence failed, order not attempted";
      JournalCandidate(prepared,"REJECT_INTENT_PERSISTENCE",cluster.cluster_id);
      return false;
   }

   // D008: a second, independent, equally fail-closed gate using the richer
   // ExecutionIntentStore (D007), run after D006's proven EventStore gate.
   // Neither gate replaces the other in this pass. See DECISION_LOG.md D008.
   MSZZExecutionIntent intent;
   intent.schema_version=MSZZ_INTENT_SCHEMA_VERSION;
   intent.intent_id=persistence_id;
   intent.cluster_id=cluster.cluster_id;
   intent.origin_id=owner.origin_id;
   intent.strategy_id=(int)prepared.strategy_id;
   intent.symbol=_Symbol;
   intent.timeframe=(int)_Period;
   intent.magic=InpMagic;
   intent.direction=(int)prepared.direction;
   intent.signal_time=owner.signal_time;
   intent.intent_time=TimeCurrent();
   intent.expiry_time=owner.expiry_time;
   intent.requested_volume=volume;
   intent.requested_entry=prepared.entry;
   intent.requested_stop=prepared.stop;
   intent.requested_target=prepared.target;
   intent.execution_state=(int)MSZZ_INTENT_PERSISTED;
   intent.submission_attempts=0;
   intent.broker_retcode=0;
   intent.broker_result_text="";
   intent.order_ticket=0; intent.position_ticket=0;
   intent.first_deal_ticket=0; intent.last_deal_ticket=0;
   intent.filled_volume=0.0; intent.average_fill_price=0.0;
   intent.last_reconciliation_time=0;
   intent.protection_status=0;
   intent.instance_id=g_instance_id;

   if(!g_intent_store.CreateIntent(intent))
   {
      prepared.reason="execution intent store persistence failed: "+g_intent_store.LastError();
      JournalCandidate(prepared,"REJECT_INTENT_STORE",cluster.cluster_id);
      return false;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   bool ok=false;
   // D009: "MI"+8-hex correlation token, not the old bare strategy id -- lets
   // the reconciler match this order back to its intent even if the local
   // ticket fields were never recorded (e.g. a crash right after submission).
   string comment="MI"+MSZZCorrelationToken(persistence_id);
   if(prepared.direction==MSZZ_DIR_LONG) ok=g_trade.Buy(volume,_Symbol,0.0,prepared.stop,prepared.target,comment);
   else if(prepared.direction==MSZZ_DIR_SHORT) ok=g_trade.Sell(volume,_Symbol,0.0,prepared.stop,prepared.target,comment);

   intent.submission_attempts=1;
   intent.broker_retcode=g_trade.ResultRetcode();
   intent.broker_result_text=g_trade.ResultRetcodeDescription();
   // D010: routed through the state machine's TryTransition() instead of a
   // direct field write. This transition is always legal given how intents
   // are constructed above (always starts PERSISTED), but the gate means a
   // future refactor that changes construction order gets caught here
   // instead of silently corrupting the record. On rejection, TryTransition
   // leaves intent.execution_state untouched (still PERSISTED) -- the D009
   // reconciler already fails a stuck PERSISTED intent closed to
   // RECOVERY_REQUIRED on the next restart, so this is not a new gap.
   string transition_reason;
   if(ok)
   {
      if(!CMSZZIntentStateMachine::TryTransition(intent,MSZZ_INTENT_BROKER_ACCEPTED,transition_reason))
         Print("MSZZ WARNING: post-accept state transition rejected: ",transition_reason);
      intent.order_ticket=g_trade.ResultOrder();
      intent.first_deal_ticket=g_trade.ResultDeal();
      // D018: these were declared and persisted since Phase 1 but never
      // actually assigned anywhere -- always 0.0, silently corrupting every
      // R-multiple the D016/D017 analytics exporter has ever computed.
      intent.average_fill_price=g_trade.ResultPrice();
      intent.filled_volume=g_trade.ResultVolume();

      // D011: on a hedging account (the only mode this EA has ever run
      // against), a brand-new position's ticket equals the opening order's
      // ticket -- see DECISION_LOG.md D011 for why this is documented as a
      // limitation, not generalized to netting. If the position resolves,
      // mark it active immediately (previously this only happened at the
      // next restart's reconciliation, D010) and verify/repair protection
      // in the same tick rather than waiting for a future restart.
      intent.position_ticket=intent.order_ticket;
      if(PositionSelectByTicket(intent.position_ticket))
      {
         if(!CMSZZIntentStateMachine::TryTransition(intent,MSZZ_INTENT_POSITION_ACTIVE,transition_reason))
            Print("MSZZ WARNING: post-fill state transition rejected: ",transition_reason);

         string protection_reason;
         ENUM_MSZZ_PROTECTION_VERDICT verdict=g_protection.VerifyAndRepair(
            g_trade,intent.position_ticket,prepared.stop,prepared.target,protection_reason);
         PrintFormat("MSZZ PROTECTION verdict=%s ticket=%I64u reason=%s",
                     MSZZProtectionVerdictText(verdict),intent.position_ticket,protection_reason);
         if(verdict==MSZZ_PROTECTION_REPAIR_FAILED || verdict==MSZZ_PROTECTION_POSITION_NOT_FOUND)
         {
            if(!CMSZZIntentStateMachine::TryTransition(intent,MSZZ_INTENT_PROTECTION_FAILED,transition_reason))
               Print("MSZZ WARNING: post-protection-failure state transition rejected: ",transition_reason);
            g_recovery_required=true;
         }
      }
      else
      {
         // Ticket did not resolve to a live position -- do not force an
         // unproven POSITION_ACTIVE. Leave at BROKER_ACCEPTED; D009's
         // reconciler will pick up this stuck intent at the next restart
         // exactly as it already does for any other unresolved case, and
         // clear position_ticket back to unset rather than keep a ticket
         // that never actually resolved.
         intent.position_ticket=0;
      }
   }
   else
   {
      if(!CMSZZIntentStateMachine::TryTransition(intent,MSZZ_INTENT_BROKER_REJECTED,transition_reason))
         Print("MSZZ WARNING: post-reject state transition rejected: ",transition_reason);
   }
   // Warn-only, not fail-closed: EventStore already durably marked this cluster
   // consumed above, so the anti-duplicate guarantee does not depend on this
   // update succeeding. A failure here leaves the intent record's fill/ticket
   // details incomplete -- exactly what Phase 2's reconciler exists to detect
   // and repair against broker truth, not a new gap this decision introduces.
   if(!g_intent_store.UpdateIntent(intent))
      Print("MSZZ WARNING: intent store post-submission update failed: ",g_intent_store.LastError());

   if(ok)
   {
      JournalCluster(cluster,"EXECUTED"); JournalCandidate(prepared,"EXECUTED",cluster.cluster_id);
   }
   else
   {
      prepared.reason=StringFormat("retcode=%u %s (cluster already marked consumed; not retried)",
                                   g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      JournalCandidate(prepared,"ORDER_FAILED",cluster.cluster_id);
   }
   return ok;
}

// D016: detect an MSZZ-owned position closing every bar, not only at EA
// restart. The D009 reconciler is deliberately not reused here -- it
// solves identity ambiguity (comment-token matching, netting conflicts)
// for the restart case where a ticket might be unknown; here the ticket
// is already known and trustworthy (D011 sets it in the same tick as the
// fill). A direct PositionSelectByTicket check is sufficient and safer
// than threading this through the reconciler for a problem it doesn't
// have. See DECISION_LOG.md D016.
void DetectClosedPositions()
{
   int count=g_intent_store.Count();
   for(int i=0;i<count;i++)
   {
      MSZZExecutionIntent intent;
      if(!g_intent_store.IntentAt(i,intent)) continue;
      if(intent.execution_state!=(int)MSZZ_INTENT_POSITION_ACTIVE) continue;
      if(intent.position_ticket==0) continue;
      if(PositionSelectByTicket(intent.position_ticket)) continue; // still open

      if(!HistorySelect(intent.intent_time-3600,TimeCurrent()))
      {
         PrintFormat("MSZZ WARNING: closed-position detection HistorySelect failed intent=%s",intent.intent_id);
         continue;
      }

      ulong closing_deal=0; datetime closing_time=0; double closing_price=0.0;
      datetime fill_time=intent.intent_time; // fallback if the opening deal isn't found below
      // D025: a position may have been PARTIALLY closed earlier (variants
      // G/H's InpPartialCloseAtR) before this final exit deal. R-multiple
      // is linear in price for a fixed entry/risk, so the volume-weighted
      // average price across EVERY exit deal for this position (not just
      // the last one) gives the exact blended R-multiple across a
      // partial-then-remainder close sequence -- found and fixed during
      // D025 verification; the prior single-last-deal-price logic silently
      // discarded any profit already banked at an earlier partial close.
      // See DECISION_LOG.md D025.
      double exit_volume_sum=0.0, exit_price_volume_sum=0.0;
      int deal_total=HistoryDealsTotal();
      for(int d=0;d<deal_total;d++)
      {
         ulong ticket=HistoryDealGetTicket(d);
         if(ticket==0) continue;
         if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=intent.position_ticket) continue;

         long entry_type=HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry_type==DEAL_ENTRY_IN)
         {
            fill_time=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
         }
         else if(entry_type==DEAL_ENTRY_OUT || entry_type==DEAL_ENTRY_OUT_BY)
         {
            datetime t=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
            double deal_price=HistoryDealGetDouble(ticket,DEAL_PRICE);
            double deal_volume=HistoryDealGetDouble(ticket,DEAL_VOLUME);
            exit_volume_sum+=deal_volume;
            exit_price_volume_sum+=deal_price*deal_volume;
            if(t>=closing_time) { closing_time=t; closing_deal=ticket; }
         }
      }
      if(exit_volume_sum>0.0) closing_price=exit_price_volume_sum/exit_volume_sum;

      string transition_reason;
      if(!CMSZZIntentStateMachine::TryTransition(intent,MSZZ_INTENT_POSITION_CLOSED,transition_reason))
      {
         PrintFormat("MSZZ WARNING: closed-position detection state transition rejected intent=%s reason=%s",
                     intent.intent_id,transition_reason);
         continue;
      }

      if(closing_deal==0)
      {
         PrintFormat("MSZZ WARNING: closed-position detection found no closing deal intent=%s ticket=%I64u; state transitioned, trade analytics not exported",
                     intent.intent_id,intent.position_ticket);
      }
      else if(InpWriteCSV)
      {
         g_trade_analytics.ExportClosedTrade(intent,fill_time,closing_price,closing_time);
      }

      if(!g_intent_store.UpdateIntent(intent))
         PrintFormat("MSZZ WARNING: closed-position detection intent update failed intent=%s error=%s",
                     intent.intent_id,g_intent_store.LastError());
   }
}

bool TicketAlreadyPartialClosed(const ulong ticket)
{
   for(int i=0;i<ArraySize(g_partial_closed_tickets);i++)
      if(g_partial_closed_tickets[i]==ticket) return true;
   return false;
}

void MarkTicketPartialClosed(const ulong ticket)
{
   int n=ArraySize(g_partial_closed_tickets);
   ArrayResize(g_partial_closed_tickets,n+1);
   g_partial_closed_tickets[n]=ticket;
}

// D025 variants G/H: checked once per closed bar, using that bar's own
// favorable extreme -- matches this EA's existing bar-based (not
// tick-based) decision cadence everywhere else. The exact partial-close
// fill price may therefore differ slightly from the theoretical
// R-threshold price; an accepted, documented simplification for this
// mechanism-decomposition study, not a live-trading-grade feature. See
// DECISION_LOG.md D025.
void ProcessPartialCloses(const MqlRates &bar)
{
   if(InpPartialCloseAtR<=0.0) return;
   string reason;
   if(!RefreshOwnership(reason)) return; // best-effort for this research-only feature; skip this bar's check rather than fail loudly
   int count=g_ownership.RecordCount();
   for(int i=0;i<count;i++)
   {
      MSZZPositionRecord record;
      if(!g_ownership.RecordAt(i,record)) continue;
      if(!record.valid || record.owner!=MSZZ_OWNER_OWNED) continue;
      if(record.volume<=0.0 || record.stop_loss<=0.0) continue;
      if(TicketAlreadyPartialClosed(record.ticket)) continue;

      double risk=MathAbs(record.price_open-record.stop_loss);
      if(risk<=0.0) continue;
      double favorable=(record.direction==MSZZ_DIR_LONG ? bar.high : bar.low);
      double fav_r=(record.direction==MSZZ_DIR_LONG ? (favorable-record.price_open) : (record.price_open-favorable))/risk;
      if(fav_r<InpPartialCloseAtR) continue;

      double close_volume=g_execution_guard.NormalizeVolume(record.volume*InpPartialCloseFraction);
      if(close_volume<=0.0 || close_volume>=record.volume) continue;
      if(g_trade.PositionClosePartial(record.ticket,close_volume))
         MarkTicketPartialClosed(record.ticket);
      else
         PrintFormat("MSZZ WARNING: partial close failed ticket=%I64u retcode=%u %s",
                     record.ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
   }
}

void ProcessClosedBar()
{
   DetectClosedPositions();

   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,_Period,0,MathMax(300,InpHistoryBars),rates);
   if(copied<100){ PrintFormat("MSZZ insufficient bars copied=%d error=%d",copied,GetLastError()); return; }
   int closed_count=copied-1; if(closed_count<100) return;

   ProcessPartialCloses(rates[closed_count-1]);

   g_engine.Configure(InpFastATRLen,InpFastATRMult,InpMedATRLen,InpMedATRMult,InpSlowATRLen,InpSlowATRMult,InpMinBarsBetween);
   if(!g_engine.Rebuild(_Symbol,_Period,rates,closed_count)) return;
   MSZZSpeedSnapshot fast=g_engine.Snapshot(MSZZ_SPEED_FAST);
   MSZZSpeedSnapshot med=g_engine.Snapshot(MSZZ_SPEED_MEDIUM);
   MSZZSpeedSnapshot slow=g_engine.Snapshot(MSZZ_SPEED_SLOW);

   g_suite.SetRiskReward(InpRiskReward);
   g_suite.SetSignalValidityBars(InpSignalValidityBars);
   g_suite.ConfigureStrategies(InpEnableFastBreakout,InpEnableMediumBreakout,InpEnableSlowBreakout,
                               InpEnableFastMedConfluence,InpEnableFastMedContext,InpEnableMedSlowContext,
                               InpEnableNestedPullback,InpEnableWeightedEnsemble);
   MSZZCandidate candidates[];
   int candidate_count=g_suite.Evaluate(fast,med,slow,rates[closed_count-1].time,rates[closed_count-1].close,candidates);
   if(candidate_count<=0) return;
   for(int i=0;i<candidate_count;i++) if(candidates[i].valid) JournalCandidate(candidates[i],"RAW_CANDIDATE");

   MSZZOpportunityCluster clusters[];
   int cluster_count=g_cluster_engine.Build(_Symbol,_Period,candidates,candidate_count,clusters);
   if(cluster_count<=0) return;
   int best_cluster=g_cluster_engine.SelectBest(clusters,cluster_count);
   if(best_cluster<0 || !clusters[best_cluster].valid) return;

   MSZZOpportunityCluster selected_cluster=clusters[best_cluster];
   int owner_index=selected_cluster.preferred_index;
   if(owner_index<0 || owner_index>=candidate_count || !candidates[owner_index].valid) return;
   MSZZCandidate owner=candidates[owner_index];

   JournalCluster(selected_cluster,"SELECTED");
   if(selected_cluster.combined_score<g_effective_min_score){ JournalCandidate(owner,"REJECT_SCORE",selected_cluster.cluster_id); return; }
   if(EventConsumed(selected_cluster.cluster_id)){ JournalCandidate(owner,"REJECT_DUPLICATE_CLUSTER",selected_cluster.cluster_id); return; }

   ExecuteCluster(selected_cluster,owner);
   if(!LiveExecutionAuthorized() && !ConsumeEvent(selected_cluster.cluster_id))
      Print("MSZZ WARNING: shadow cluster persistence failed.");
}

int OnInit()
{
   if(InpMagic<=0 || InpFastATRLen<1 || InpMedATRLen<1 || InpSlowATRLen<1 || InpFastATRMult<=0.0 ||
      InpMedATRMult<=0.0 || InpSlowATRMult<=0.0 || InpRiskReward<=0.0 || InpHistoryBars<300)
      return INIT_PARAMETERS_INCORRECT;

   // D019: fail-closed research-eligibility authorization. All-or-nothing --
   // if InpResearchMinScoreOverride>0.0 is set but any required condition
   // is not met, refuse to start entirely rather than silently falling
   // back to normal scoring. See DECISION_LOG.md D019.
   g_effective_min_score=InpMinScore;
   g_research_mode_active=false;
   if(InpResearchMinScoreOverride>0.0)
   {
      bool is_tester=(bool)MQLInfoInteger(MQL_TESTER);
      long trade_mode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
      long login=AccountInfoInteger(ACCOUNT_LOGIN);
      bool authorized=CMSZZResearchEligibilityPolicy::IsAuthorized(
         InpResearchMinScoreOverride,InpAcknowledgeResearchOverride,is_tester,
         trade_mode,login,MSZZ_RESEARCH_AUTHORIZED_DEMO_LOGIN,(long)ACCOUNT_TRADE_MODE_DEMO);
      if(!authorized)
      {
         PrintFormat("MSZZ RESEARCH ELIGIBILITY REJECTED: override=%.2f acknowledge=%s is_tester=%s trade_mode=%d login=%I64d -- refusing to start. See DECISION_LOG.md D019.",
                     InpResearchMinScoreOverride,(InpAcknowledgeResearchOverride?"true":"false"),(is_tester?"true":"false"),(int)trade_mode,login);
         return INIT_FAILED;
      }
      g_effective_min_score=InpResearchMinScoreOverride;
      g_research_mode_active=true;
      PrintFormat("MSZZ WARNING: RESEARCH ELIGIBILITY MODE ACTIVE -- effective min score overridden from %.2f to %.2f",
                  InpMinScore,g_effective_min_score);
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   if(!g_execution_guard.Load(_Symbol)) return INIT_FAILED;

   g_ownership.Configure(_Symbol,InpMagic);
   string ownership_reason;
   if(!RefreshOwnership(ownership_reason))
   {
      PrintFormat("MSZZ ownership initialization failed: %s",ownership_reason);
      return INIT_FAILED;
   }

   g_event_store.Configure(_Symbol,_Period,InpMagic,InpMaxPersistentEvents);
   if(!g_event_store.Load()) return INIT_FAILED;

   g_instance_id=StringFormat("%d-%d-%d",(int)AccountInfoInteger(ACCOUNT_LOGIN),(int)TimeLocal(),MathRand());
   if(!g_intent_store.Configure(_Symbol,_Period,InpMagic,g_instance_id))
   {
      PrintFormat("MSZZ intent store initialization failed: %s",g_intent_store.LastError());
      return INIT_FAILED;
   }
   if(!g_intent_store.Load())
   {
      PrintFormat("MSZZ intent store load failed: %s",g_intent_store.LastError());
      return INIT_FAILED;
   }

   // D009: reconcile every loaded intent against broker truth once at startup,
   // before the EA does anything else. See DECISION_LOG.md D009 "Restart
   // behavior". This also fulfils D008's deferred TODO of deriving
   // position_ticket from broker records rather than leaving it unset.
   g_reconciler.Configure(_Symbol,InpMagic);
   int intent_count=g_intent_store.Count();
   MSZZExecutionIntent all_intents[];
   ArrayResize(all_intents,intent_count);
   for(int i=0;i<intent_count;i++) g_intent_store.IntentAt(i,all_intents[i]);

   bool is_netting=(g_ownership.AccountMode()==MSZZ_ACCOUNT_NETTING || g_ownership.AccountMode()==MSZZ_ACCOUNT_EXCHANGE);
   MSZZReconcileResult recon_results[];
   g_reconciler.Reconcile(all_intents,intent_count,is_netting,recon_results);

   g_recovery_required=false;
   for(int i=0;i<intent_count;i++)
   {
      bool terminal=(all_intents[i].execution_state==(int)MSZZ_INTENT_POSITION_CLOSED ||
                     all_intents[i].execution_state==(int)MSZZ_INTENT_ABANDONED);
      if(terminal) continue;

      PrintFormat("MSZZ RECONCILE intent=%s verdict=%s ticket=%I64u reason=%s",
                  recon_results[i].intent_id,MSZZReconcileVerdictText(recon_results[i].verdict),
                  recon_results[i].matched_ticket,recon_results[i].reason);

      MSZZExecutionIntent updated=all_intents[i];
      updated.last_reconciliation_time=TimeCurrent();
      // D010: verdict-to-state transitions now go through the state machine
      // instead of direct field writes. MATCHED_ACTIVE_POSITION/
      // MATCHED_CLOSED_POSITION/CONSISTENT_REJECTION completing to
      // POSITION_ACTIVE/POSITION_CLOSED/ABANDONED are new as of D010 -- D009
      // deliberately left these transitions undone (see DECISION_LOG.md D009
      // and D010). A rejected transition is journaled and the intent's
      // execution_state is left exactly as loaded -- never forced.
      string transition_reason;
      if(recon_results[i].verdict==MSZZ_RECONCILE_RECOVERY_REQUIRED)
      {
         if(!CMSZZIntentStateMachine::TryTransition(updated,MSZZ_INTENT_RECOVERY_REQUIRED,transition_reason))
            PrintFormat("MSZZ WARNING: reconciliation state transition rejected intent=%s reason=%s",updated.intent_id,transition_reason);
         g_recovery_required=true;
      }
      else if(recon_results[i].verdict==MSZZ_RECONCILE_MATCHED_ACTIVE_POSITION)
      {
         if(updated.position_ticket==0) updated.position_ticket=recon_results[i].matched_ticket;
         if(!CMSZZIntentStateMachine::TryTransition(updated,MSZZ_INTENT_POSITION_ACTIVE,transition_reason))
            PrintFormat("MSZZ WARNING: reconciliation state transition rejected intent=%s reason=%s",updated.intent_id,transition_reason);

         // D011: a position that survived a restart gets the same protection
         // check as one opened in the current session -- see DECISION_LOG.md
         // D011. This extends the same VerifyAndRepair call used immediately
         // post-fill in ExecuteCluster() to the restart/reconciliation path.
         string protection_reason;
         ENUM_MSZZ_PROTECTION_VERDICT verdict=g_protection.VerifyAndRepair(
            g_trade,updated.position_ticket,updated.requested_stop,updated.requested_target,protection_reason);
         PrintFormat("MSZZ PROTECTION verdict=%s ticket=%I64u reason=%s",
                     MSZZProtectionVerdictText(verdict),updated.position_ticket,protection_reason);
         if(verdict==MSZZ_PROTECTION_REPAIR_FAILED || verdict==MSZZ_PROTECTION_POSITION_NOT_FOUND)
         {
            if(!CMSZZIntentStateMachine::TryTransition(updated,MSZZ_INTENT_PROTECTION_FAILED,transition_reason))
               PrintFormat("MSZZ WARNING: reconciliation state transition rejected intent=%s reason=%s",updated.intent_id,transition_reason);
            g_recovery_required=true;
         }
      }
      else if(recon_results[i].verdict==MSZZ_RECONCILE_MATCHED_CLOSED_POSITION)
      {
         if(updated.position_ticket==0) updated.position_ticket=recon_results[i].matched_ticket;
         if(!CMSZZIntentStateMachine::TryTransition(updated,MSZZ_INTENT_POSITION_CLOSED,transition_reason))
            PrintFormat("MSZZ WARNING: reconciliation state transition rejected intent=%s reason=%s",updated.intent_id,transition_reason);
      }
      else if(recon_results[i].verdict==MSZZ_RECONCILE_CONSISTENT_REJECTION)
      {
         if(!CMSZZIntentStateMachine::TryTransition(updated,MSZZ_INTENT_ABANDONED,transition_reason))
            PrintFormat("MSZZ WARNING: reconciliation state transition rejected intent=%s reason=%s",updated.intent_id,transition_reason);
      }
      if(!g_intent_store.UpdateIntent(updated))
         PrintFormat("MSZZ WARNING: reconciliation update failed for intent=%s error=%s",
                     updated.intent_id,g_intent_store.LastError());
   }
   if(g_recovery_required)
      Print("MSZZ WARNING: one or more intents require manual recovery. New live execution is blocked for this symbol/magic until cleared.");

   Print(!LiveExecutionAuthorized() ?
         "MSZZ initialized in SHADOW posture. Three live gates are required." :
         "MSZZ WARNING: LIVE EXECUTION AUTHORIZED by all three gates.");
   PrintFormat("MSZZ account mode=%s event store loaded count=%d file=%s",
               CMSZZPositionOwnership::AccountModeText(g_ownership.AccountMode()),
               g_event_store.Count(),g_event_store.Filename());
   PrintFormat("MSZZ intent store loaded count=%d unknown=%d file=%s instance=%s",
               g_intent_store.Count(),g_intent_store.UnknownRecordCount(),
               g_intent_store.PrimaryFilename(),g_instance_id);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime bar=iTime(_Symbol,_Period,0);
   if(bar==0 || bar==g_last_bar) return;
   g_last_bar=bar; ProcessClosedBar();
}

// D017: a comma-separated list of the strategies enabled for this run,
// for the run-summary CSV's metadata column.
string EnabledStrategiesSummary()
{
   string out="";
   if(InpEnableFastBreakout)       out+=(out=="" ? "" : ",")+"FastBreakout";
   if(InpEnableMediumBreakout)     out+=(out=="" ? "" : ",")+"MediumBreakout";
   if(InpEnableSlowBreakout)       out+=(out=="" ? "" : ",")+"SlowBreakout";
   if(InpEnableFastMedConfluence)  out+=(out=="" ? "" : ",")+"FastMedConfluence";
   if(InpEnableFastMedContext)     out+=(out=="" ? "" : ",")+"FastMedContext";
   if(InpEnableMedSlowContext)     out+=(out=="" ? "" : ",")+"MedSlowContext";
   if(InpEnableNestedPullback)     out+=(out=="" ? "" : ",")+"NestedPullback";
   if(InpEnableWeightedEnsemble)   out+=(out=="" ? "" : ",")+"WeightedEnsemble";
   return (out=="" ? "NONE" : out);
}

// D019: written only when research eligibility mode was active this run --
// a normal Stage A/shadow/live run never creates this file at all, so its
// mere presence in a Tester Agent sandbox is itself a signal. commit_sha
// and ex5_hash are not obtainable from MQL5 at runtime (same limitation as
// D016/D017's commit_sha) -- left empty, filled in externally via
// `git rev-parse`/`shasum` when the research batch is logged.
void WriteResearchManifest()
{
   int h=FileOpen("MSZZ_ResearchManifest.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE)
   {
      PrintFormat("MSZZ research manifest open failed error=%d",GetLastError());
      return;
   }
   if(FileSize(h)==0)
      FileWriteString(h,"configured_min_score;effective_min_score;research_eligibility_enabled;tester_or_demo;account_login;account_server;commit_sha_placeholder;ex5_hash\r\n");
   FileSeek(h,0,SEEK_END);
   bool is_tester=(bool)MQLInfoInteger(MQL_TESTER);
   FileWriteString(h,StringFormat("%.2f;%.2f;true;%s;%I64d;%s;;\r\n",
                   InpMinScore,g_effective_min_score,(is_tester?"TESTER":"DEMO"),
                   AccountInfoInteger(ACCOUNT_LOGIN),AccountInfoString(ACCOUNT_SERVER)));
   FileClose(h);
}

void OnDeinit(const int reason)
{
   g_trade_analytics.WriteRunSummary(_Symbol,InpMagic,_Period,InpRiskReward,EnabledStrategiesSummary());
   if(g_research_mode_active) WriteResearchManifest();
   PrintFormat("MSZZ deinitialized reason=%d",reason);
}
