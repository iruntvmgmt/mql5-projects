//+------------------------------------------------------------------+
//| MultiSpeedZigZagEA.mq5                                           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.420"
#property description "Standalone Multi-Speed ZigZag strategy suite"

#include <Trade/Trade.mqh>
#include <MultiSpeedZigZag/Core/TripleZigZagEngine.mqh>
#include <MultiSpeedZigZag/Strategies/StrategySuite.mqh>
#include <MultiSpeedZigZag/Core/CandidateHandoff.mqh>
#include <MultiSpeedZigZag/Strategies/D027StrategyFamilies.mqh>
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
#include <MultiSpeedZigZag/Research/ResearchTrailPolicy.mqh>
#include <MultiSpeedZigZag/Research/RegimeClassifier.mqh>
#include <MultiSpeedZigZag/Research/RegimeEligibilityPolicy.mqh>
#include <MultiSpeedZigZag/Research/SixFamilyResearchSuite.mqh>
#include <MultiSpeedZigZag/Portfolio/CrossFamilyPolicy.mqh>
#include <MultiSpeedZigZag/Portfolio/StrategyBook.mqh>
#include <MultiSpeedZigZag/Portfolio/PortfolioRiskManager.mqh>
#include <MultiSpeedZigZag/Portfolio/ExecutionCoordinator.mqh>
#include <MultiSpeedZigZag/Portfolio/VirtualNettingLedger.mqh>
#include <MultiSpeedZigZag/Portfolio/PortfolioJournals.mqh>
#include <MultiSpeedZigZag/Portfolio/PositionSizing.mqh>
#include <MultiSpeedZigZag/Portfolio/PortfolioBookRouting.mqh>
#include <MultiSpeedZigZag/Portfolio/BookExitManager.mqh>

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
// D027 Stage 3 research families. All default disabled: canonical A/E and
// every existing-eight configuration remain behaviorally unchanged.
input bool InpEnableAlignedFastPullback=false;
input bool InpEnableBreakoutRetest=false;
input bool InpEnableSweepReclaim=false;
input bool InpEnableCompressionBreakout=false;
input bool InpEnableStructureTransition=false;
// D031 six-family shadow research (see Research/SixFamilyResearchSuite.mqh).
// Default disabled, same convention as the D027 research families above:
// every existing configuration's candidate stream and behavior remain
// unchanged unless this is explicitly turned on. Even when enabled, this
// suite can never reach execution -- it only ever writes its own journal.
input bool InpEnableSixFamilyResearch=false;

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
// D029: MSZZ_SIZE_FIXED_LOT (default) uses InpFixedLots exactly as before,
// byte-identical to every certified pre-D029 run. MSZZ_SIZE_PERCENT_EQUITY
// sizes from InpPortfolioRiskPerBookPct/ACCOUNT_EQUITY instead -- those two
// existing inputs are reused rather than duplicated with new ones, since
// they already mean exactly "requested per-book risk percent" and "max
// total portfolio risk percent." See DECISION_LOG.md D029 Phase 1.
input ENUM_MSZZ_POSITION_SIZING_MODE InpSizingMode=MSZZ_SIZE_FIXED_LOT;
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
// D026: research-only trailing-stop inputs, all default to a no-op so
// canonical (and D025 variant) behavior is byte-identical unless explicitly
// opted in. See DECISION_LOG.md D026.
input group "═══ D026 Research Trailing Stop ═══"
input bool   InpEnableResearchTrail=false;
input double InpTrailRung1TriggerR=0.0;  input double InpTrailRung1FloorR=0.0;
input double InpTrailRung2TriggerR=0.0;  input double InpTrailRung2FloorR=0.0;
input double InpTrailRung3TriggerR=0.0;  input double InpTrailRung3FloorR=0.0;
input double InpTrailRung4TriggerR=0.0;  input double InpTrailRung4FloorR=0.0;
input double InpTrailRung5TriggerR=0.0;  input double InpTrailRung5FloorR=0.0;
input double InpTrailCostEstimateR=0.02;
input int    InpTrailStructureMode=0; // 0=NONE,1=FAST_SWING,2=MEDIUM_SWING,3=CHANDELIER
input double InpTrailStructureActivationR=0.0;
input int    InpTrailChandelierATRLen=14;
input double InpTrailChandelierATRMult=3.0;

// D027: Layer 1/3 regime architecture. InpRegimeEligibilityMode defaults to
// LABEL_ONLY -- every existing strategy behaves exactly as before, every
// candidate/trade still receives regime labels, nothing is filtered.
// RESEARCH_FILTER applies only to explicitly enabled D027 research
// candidates; existing A/E and existing-eight candidates are never gated.
input group "═══ D027 Regime Architecture ═══"
input int    InpRegimeEligibilityMode=0; // 0=LABEL_ONLY, 1=RESEARCH_FILTER

// D028 Stage 1: architecture-only scaffold. Default false is an exact legacy
// no-op. Activation deliberately fails closed until Stage 2 deterministic
// integration tests and Stage 3 single-book equivalence authorize dispatch.
input group "═══ D028 Multi-Book Portfolio (Architecture Only) ═══"
input bool   InpEnableMultiBookPortfolio=false;
input int    InpCrossFamilyPolicy=0; // 0=legacy control; 4=independent books
input long   InpPortfolioBaseMagic=26074000;
input double InpFastMedBookTargetR=2.0;
input double InpSweepBookTargetR=2.0;
input double InpPortfolioRiskPerBookPct=0.25;
input double InpPortfolioMaxTotalRiskPct=0.50;
input double InpPortfolioMaxFamilyRiskPct=0.50;
input int    InpPortfolioMaxBooks=2;
input int    InpPortfolioMaxPhysicalPositions=2;
input bool   InpPortfolioAllowOpposingBooks=false;
input bool   InpPortfolioAllowSameDirectionStacking=false;

// D028 Stage 5: bounded SweepReclaim exit-management study. Default 0
// (SR0) is an exact no-op versus the certified Stage 4 P1-P4 behavior --
// no breakeven, no trail, no partial close, no time stop. Only the Sweep
// book's exit policy varies in Stage 5; FastMedConfluence's book is never
// touched (0/SR0 always). See DECISION_LOG.md D028 Stage 5.
input group "═══ D028 Stage 5 SweepReclaim Exit Policy ═══"
input int    InpSweepExitPolicy=0; // 0=SR0 fixed2R,1=SR1 breakeven,2=SR2 structural trail,3=SR3 partial fixed,4=SR4 partial runner,5=SR5 time stop

input group "═══ Account Safeguards ═══"
input bool   InpKillSwitchEngaged=false;
input int    InpMaxTradesPerDay=20;
input double InpMaxDailyLossAmount=0.0;

input group "═══ Diagnostics ═══"
input bool InpWriteCSV=true;
input bool InpVerboseLog=true;

CMSZZTripleZigZagEngine       g_engine;
CMSZZStrategySuite            g_suite;
CMSZZD027StrategyFamilies     g_d027_suite;
// D031: six-family shadow research suite (pure observer -- see
// Research/SixFamilyResearchSuite.mqh's safety contract). Evaluated
// alongside CMSZZRegimeClassifier in ProcessClosedBar(), its own
// candidates are never appended to the candidates[]/d027_candidates[]
// arrays g_suite/g_d027_suite feed into ExecuteCluster().
CMSZZSixFamilyResearchSuite   g_six_family_suite;
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
// D028 Stage 5 bug fix: tracks which broker position tickets have already
// received a MSZZ_PortfolioTradeAnalytics.csv row, so a position closed via
// ProcessOneBookExit's SR5 force-close path (which journals immediately,
// see ExportClosedPortfolioBookFromTrade) is never journaled a second time
// when DetectClosedPositions() later notices the same ticket is gone. An
// earlier attempt gated the DetectClosedPositions() write on
// ActivePortfolioBookState() still matching the closed ticket instead --
// wrong, because the far more common own-family-opposite-close path
// (ApplyOwnershipPreflight -> PortfolioMarkFlat("own-book opposite close"))
// flattens/reassigns the book to a new position mid-bar, before
// DetectClosedPositions() ever runs for the old intent, so that guard
// silently dropped every opposite-close trade's portfolio journal row
// instead of just the intended SR5 duplicate. See DECISION_LOG.md D028
// Stage 5.
ulong                          g_portfolio_journaled_tickets[];
// D026: research-only, in-memory (non-persistent across restarts, see
// DECISION_LOG.md D026 "restart persistence") per-ticket trailing-stop
// state. g_trail_config is built once in OnInit() from the Inp* rung/
// structure inputs.
MSZZTrailState                 g_trail_states[];
MSZZTrailConfig                g_trail_config;
// D027: the current closed bar's regime label, recomputed once per bar in
// ProcessClosedBar() before any candidate is evaluated, and referenced by
// every JournalCandidate() call for that same bar. g_last_regime_id is a
// stable, human-readable snapshot reference (the bar's own timestamp) --
// deliberately not a duplicated serialization of the full struct into
// every journal row. See DECISION_LOG.md D027.
MSZZRegimeState                g_last_regime;
string                         g_last_regime_id="";
// D028 Stage 1 architecture objects. No ProcessClosedBar()/ExecuteCluster()
// caller reaches these while InpEnableMultiBookPortfolio is false.
CMSZZStrategyBook              g_fastmed_book;
CMSZZStrategyBook              g_sweep_book;
CMSZZPortfolioRiskManager      g_portfolio_risk;
CMSZZExecutionCoordinator      g_execution_coordinator;
CMSZZVirtualNettingLedger      g_virtual_ledger;
CMSZZPortfolioJournals         g_portfolio_journals;
bool                           g_portfolio_single_book_active=false;
bool                           g_portfolio_multi_book_active=false;
ENUM_MSZZ_STRATEGY_ID          g_portfolio_strategy_id=MSZZ_STRAT_NONE;

bool LiveExecutionAuthorized(){ return (!InpShadowOnly && InpAllowLiveExecution && InpAcknowledgeRisk); }
bool EventConsumed(const string id){ return g_event_store.Contains(id); }
bool ConsumeEvent(const string id){ return g_event_store.Add(id); }

string PortfolioConsumedKey(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                            const string cluster_id)
{
   return CMSZZPortfolioBookRouting::ConsumedKey(strategy_id,cluster_id);
}

bool PortfolioEventConsumed(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                            const string cluster_id)
{
   return EventConsumed(PortfolioConsumedKey(strategy_id,cluster_id));
}

bool ConsumePortfolioEvent(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                           const string cluster_id)
{
   if(PortfolioEventConsumed(strategy_id,cluster_id)) return true;
   return ConsumeEvent(PortfolioConsumedKey(strategy_id,cluster_id));
}

int EnabledStrategyCount()
{
   int count=0;
   if(InpEnableFastBreakout) count++;
   if(InpEnableMediumBreakout) count++;
   if(InpEnableSlowBreakout) count++;
   if(InpEnableFastMedConfluence) count++;
   if(InpEnableFastMedContext) count++;
   if(InpEnableMedSlowContext) count++;
   if(InpEnableNestedPullback) count++;
   if(InpEnableWeightedEnsemble) count++;
   if(InpEnableAlignedFastPullback) count++;
   if(InpEnableBreakoutRetest) count++;
   if(InpEnableSweepReclaim) count++;
   if(InpEnableCompressionBreakout) count++;
   if(InpEnableStructureTransition) count++;
   return count;
}

MSZZStrategyBookState ActivePortfolioBookState()
{
   if(g_portfolio_strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
      return g_fastmed_book.State();
   return g_sweep_book.State();
}

bool PortfolioMarkFlat(const string reason)
{
   if(!g_portfolio_single_book_active) return true;
   if(g_portfolio_strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
      return g_fastmed_book.MarkFlat(reason);
   if(g_portfolio_strategy_id==MSZZ_STRAT_SWEEP_RECLAIM)
      return g_sweep_book.MarkFlat(reason);
   return false;
}

bool PortfolioMarkEntryPending(const MSZZCandidate &candidate,const double volume,
                               const double requested_risk_pct,string &reason)
{
   if(!g_portfolio_single_book_active) return true;
   if(candidate.strategy_id!=g_portfolio_strategy_id)
   {
      reason="candidate does not belong to active single book";
      return false;
   }
   if(g_portfolio_strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
      return g_fastmed_book.MarkEntryPending(candidate,volume,requested_risk_pct,reason);
   return g_sweep_book.MarkEntryPending(candidate,volume,requested_risk_pct,reason);
}

bool PortfolioMarkOpen(const string logical_position_id,const ulong position_ticket,
                       const ulong order_ticket,const datetime entry_time,
                       const double entry_price,const double stop_price,
                       const double target_price,const double allocated_risk_pct,
                       string &reason)
{
   if(!g_portfolio_single_book_active) return true;
   if(g_portfolio_strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
      return g_fastmed_book.MarkOpen(logical_position_id,position_ticket,order_ticket,
                                     entry_time,entry_price,stop_price,target_price,
                                     allocated_risk_pct,reason);
   return g_sweep_book.MarkOpen(logical_position_id,position_ticket,order_ticket,
                                entry_time,entry_price,stop_price,target_price,
                                allocated_risk_pct,reason);
}

bool PortfolioAssignPendingLogicalPositionId(const string logical_position_id,
                                             string &reason)
{
   if(!g_portfolio_single_book_active) return true;
   if(g_portfolio_strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
      return g_fastmed_book.AssignPendingLogicalPositionId(logical_position_id,reason);
   return g_sweep_book.AssignPendingLogicalPositionId(logical_position_id,reason);
}

double PortfolioTargetR(const ENUM_MSZZ_STRATEGY_ID strategy_id)
{
   if(!g_portfolio_single_book_active && !g_portfolio_multi_book_active)
      return InpRiskReward;
   if(strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE) return InpFastMedBookTargetR;
   if(strategy_id==MSZZ_STRAT_SWEEP_RECLAIM) return InpSweepBookTargetR;
   return 0.0;
}

bool ConfigurePortfolioArchitecture(string &reason)
{
   reason="";
   ENUM_MSZZ_CROSS_FAMILY_POLICY policy=
      (ENUM_MSZZ_CROSS_FAMILY_POLICY)InpCrossFamilyPolicy;
   if(!CMSZZCrossFamilyPolicy::IsKnown(policy))
   {
      reason="unknown D028 cross-family policy";
      return false;
   }
   if(policy!=MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS)
   {
      reason="Stage 3 single-book mode requires INDEPENDENT_BOOKS policy";
      return false;
   }
   int enabled_count=EnabledStrategyCount();
   bool supported_pair=(enabled_count==2 && InpEnableFastMedConfluence &&
                        InpEnableSweepReclaim);
   if(!CMSZZPortfolioBookRouting::IsSupportedSelection(
         enabled_count,InpEnableFastMedConfluence,InpEnableSweepReclaim))
   {
      reason="portfolio strategy selection is unsupported";
      return false;
   }
   if(enabled_count==1 && InpEnableFastMedConfluence)
      g_portfolio_strategy_id=MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE;
   else if(enabled_count==1 && InpEnableSweepReclaim)
      g_portfolio_strategy_id=MSZZ_STRAT_SWEEP_RECLAIM;
   else if(supported_pair)
      g_portfolio_strategy_id=MSZZ_STRAT_NONE;
   else
   {
      reason="portfolio mode requires one supported book or the exact FastMed+Sweep pair";
      return false;
   }
   if(!g_execution_coordinator.Configure(_Symbol,InpPortfolioBaseMagic,policy,reason))
      return false;

   MSZZBookExitConfig fastmed_exit; ZeroMemory(fastmed_exit);
   fastmed_exit.policy_id=MSZZ_BOOK_EXIT_FIXED_R;
   fastmed_exit.target_r=InpFastMedBookTargetR;
   fastmed_exit.own_family_opposite_exit=true;
   MSZZBookExitConfig sweep_exit; ZeroMemory(sweep_exit);
   sweep_exit.policy_id=MSZZ_BOOK_EXIT_SWEEP_CANONICAL_2R;
   sweep_exit.target_r=InpSweepBookTargetR;
   sweep_exit.own_family_opposite_exit=true;
   // D028 Stage 5: only the Sweep book's exit management varies; validated
   // as one of the six frozen enum values, fail-closed otherwise.
   if(InpSweepExitPolicy<0 || InpSweepExitPolicy>5)
   { reason="InpSweepExitPolicy must be 0-5 (SR0-SR5)"; return false; }
   sweep_exit.trailing_policy_id=InpSweepExitPolicy;

   // Stage 3 deliberately reuses the certified run's InpMagic for its one
   // physical book, keeping all legacy ownership/intent/analytics machinery
   // identical. Stage 4 will assign distinct per-book magics.
   if(supported_pair)
   {
      long fastmed_magic=g_execution_coordinator.BookMagic(
         MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,1);
      long sweep_magic=g_execution_coordinator.BookMagic(MSZZ_STRAT_SWEEP_RECLAIM,2);
      if(fastmed_magic<=0 || sweep_magic<=0 || fastmed_magic==sweep_magic)
      { reason="multi-book magic derivation failed"; return false; }
      if(!g_fastmed_book.Configure(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                                   MSZZ_FAMILY_BREAKOUT,fastmed_magic,true,
                                   fastmed_exit,reason)) return false;
      if(!g_sweep_book.Configure(2,MSZZ_STRAT_SWEEP_RECLAIM,
                                 MSZZ_FAMILY_REVERSAL,sweep_magic,true,
                                 sweep_exit,reason)) return false;
   }
   else if(g_portfolio_strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
   {
      if(!g_fastmed_book.Configure(1,MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                                   MSZZ_FAMILY_BREAKOUT,InpMagic,true,
                                   fastmed_exit,reason)) return false;
   }
   else
   {
      if(!g_sweep_book.Configure(2,MSZZ_STRAT_SWEEP_RECLAIM,
                                 MSZZ_FAMILY_REVERSAL,InpMagic,true,
                                 sweep_exit,reason)) return false;
   }

   MSZZPortfolioRiskConfig risk; ZeroMemory(risk);
   risk.max_total_initial_risk_pct=InpPortfolioMaxTotalRiskPct;
   risk.max_risk_per_book_pct=InpPortfolioRiskPerBookPct;
   risk.max_risk_per_family_pct=InpPortfolioMaxFamilyRiskPct;
   risk.max_same_direction_risk_pct=InpPortfolioMaxTotalRiskPct;
   risk.max_opposing_direction_risk_pct=InpPortfolioMaxTotalRiskPct;
   risk.max_logical_books=InpPortfolioMaxBooks;
   risk.max_books_per_strategy=1;
   risk.max_physical_positions=InpPortfolioMaxPhysicalPositions;
   risk.daily_loss_cap_pct=0.0;
   risk.drawdown_cap_pct=0.0;
   // D029 Phase 2 bug fix: this cap was always derived from InpFixedLots,
   // an assumption that only holds in MSZZ_SIZE_FIXED_LOT mode. In
   // MSZZ_SIZE_PERCENT_EQUITY mode, normalized volume is computed from risk
   // percent and varies per trade (often far above InpFixedLots*2) -- found
   // empirically when Phase 2's first real D29-A run rejected 432/717
   // candidates with "symbol exposure cap exceeded" despite every sizing
   // decision itself being correct and within the 0.25%/0.50% risk caps.
   // Disabling this lot-count cap in percent-equity mode is correct, not a
   // safety regression: portfolio risk is already bounded by the
   // mode-aware max_total_initial_risk_pct/max_risk_per_book_pct checks
   // above, which use ACTUAL computed risk regardless of lot size. See
   // DECISION_LOG.md D029 Phase 2.
   risk.symbol_exposure_cap_lots=(InpSizingMode==MSZZ_SIZE_PERCENT_EQUITY) ?
      0.0 : InpFixedLots*InpPortfolioMaxBooks;
   risk.allow_opposing_books=InpPortfolioAllowOpposingBooks;
   risk.allow_same_direction_stacking=InpPortfolioAllowSameDirectionStacking;
   if(!g_portfolio_risk.Configure(risk,reason)) return false;

   string ledger_file=StringFormat("MSZZ_D028_VirtualLedger_%s_%d_%I64d.csv",
                                   _Symbol,(int)_Period,InpPortfolioBaseMagic);
   if(!g_virtual_ledger.Configure(_Symbol,ledger_file))
   {
      reason=g_virtual_ledger.LastError();
      return false;
   }
   g_portfolio_journals.Configure(InpWriteCSV);
   if(!g_portfolio_journals.EnsureTradeAnalyticsHeader())
   {
      reason="D028 portfolio journal initialization failed";
      return false;
   }
   g_portfolio_multi_book_active=supported_pair;
   g_portfolio_single_book_active=!supported_pair;
   return true;
}

// D027: one row per closed bar, every bar -- independent of whether any
// candidate fired that bar. Required for Stage 2's regime-distribution and
// per-strategy regime-attribution work, which needs the full population,
// not just signal-time snapshots. See DECISION_LOG.md D027 Stage 1.
void JournalRegime(const MSZZRegimeState &r)
{
   if(!InpWriteCSV) return;
   int h=FileOpen("MSZZ_RegimeJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE){ PrintFormat("MSZZ regime journal open failed error=%d",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWriteString(h,"time;symbol;timeframe;direction;trend_strength;volatility_state;alignment_state;market_phase;"+
                       "normalized_atr;directional_efficiency;compression_ratio;fast_swing_amplitude;medium_swing_amplitude;"+
                       "slow_swing_amplitude;fast_duration;medium_duration;slow_duration;valid;reason\r\n");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(r.evaluation_time,TIME_DATE|TIME_SECONDS),_Symbol,EnumToString(_Period),
             MSZZRegimeDirectionText(r.direction),MSZZTrendStrengthText(r.trend_strength),
             MSZZVolatilityStateText(r.volatility_state),MSZZAlignmentStateText(r.alignment_state),
             MSZZMarketPhaseText(r.market_phase),DoubleToString(r.normalized_atr,4),
             DoubleToString(r.directional_efficiency,4),DoubleToString(r.compression_ratio,4),
             DoubleToString(r.fast_swing_amplitude_r,4),DoubleToString(r.medium_swing_amplitude_r,4),
             DoubleToString(r.slow_swing_amplitude_r,4),DoubleToString(r.fast_duration_bars,2),
             DoubleToString(r.medium_duration_bars,2),DoubleToString(r.slow_duration_bars,2),
             (r.valid?"true":"false"),r.reason);
   FileFlush(h); FileClose(h);
}

string g_journal_cluster_owner="";
string g_journal_cluster_strategies="";
string g_journal_cluster_families="";

void JournalCandidate(const MSZZCandidate &c,const string status,const string cluster_id="")
{
   if(InpVerboseLog)
      PrintFormat("MSZZ %s %s cluster=%s score=%.2f entry=%.*f stop=%.*f target=%.*f origin=%s event=%s reason=%s",
                  status,c.setup_name,cluster_id,c.score,_Digits,c.entry,_Digits,c.stop,_Digits,c.target,c.origin_id,c.event_id,c.reason);
   if(!InpWriteCSV) return;
   ENUM_MSZZ_ELIGIBILITY_MODE elig_mode=(ENUM_MSZZ_ELIGIBILITY_MODE)InpRegimeEligibilityMode;
   string elig_reason;
   bool elig_result=CMSZZRegimeEligibilityPolicy::IsEligible(elig_mode,c.family_id,c.strategy_id,g_last_regime,elig_reason);
   int h=FileOpen("MSZZ_SignalJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE){ PrintFormat("MSZZ journal open failed error=%d",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","timeframe","status","cluster_id","strategy_id","setup","direction","score","entry","stop","target","origin_id","event_id","reason",
                "strategy_family","regime_snapshot_id","regime_direction","regime_strength","regime_volatility","regime_alignment","regime_phase",
                "eligibility_mode","eligibility_result","eligibility_reason","cluster_owner_strategy_id",
                "overlap_strategy_ids","overlap_family_ids","execution_status","rejection_reason");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(c.signal_time,TIME_DATE|TIME_SECONDS),_Symbol,EnumToString(_Period),status,cluster_id,
             (int)c.strategy_id,c.setup_name,MSZZDirectionText(c.direction),DoubleToString(c.score,2),
             DoubleToString(c.entry,_Digits),DoubleToString(c.stop,_Digits),DoubleToString(c.target,_Digits),
             c.origin_id,c.event_id,c.reason,MSZZFamilyText(c.family_id),
             g_last_regime_id,MSZZRegimeDirectionText(g_last_regime.direction),MSZZTrendStrengthText(g_last_regime.trend_strength),
             MSZZVolatilityStateText(g_last_regime.volatility_state),MSZZAlignmentStateText(g_last_regime.alignment_state),
             MSZZMarketPhaseText(g_last_regime.market_phase),MSZZEligibilityModeText(elig_mode),(elig_result?"true":"false"),elig_reason,
             (cluster_id=="" ? "" : g_journal_cluster_owner),
             (cluster_id=="" ? "" : g_journal_cluster_strategies),
             (cluster_id=="" ? "" : g_journal_cluster_families),status,
             (StringFind(status,"REJECT")==0 || status=="ORDER_FAILED" ? c.reason : ""));
   FileFlush(h); FileClose(h);
}

void JournalCluster(const MSZZOpportunityCluster &cluster,const string status)
{
   g_journal_cluster_owner=IntegerToString((int)cluster.owner_strategy_id);
   g_journal_cluster_strategies=cluster.supporting_strategy_ids;
   g_journal_cluster_families=cluster.supporting_family_ids;
   if(InpVerboseLog)
      PrintFormat("MSZZ CLUSTER %s id=%s owner=%d strategies=%s families=%s score=%.2f support=%d evidence=%d stop_disagreement=%.*f",
                  status,cluster.cluster_id,(int)cluster.owner_strategy_id,
                  cluster.supporting_strategy_ids,cluster.supporting_family_ids,cluster.combined_score,
                  cluster.support_count,cluster.evidence_mask,_Digits,cluster.stop_disagreement);
}

bool IsD027Strategy(const ENUM_MSZZ_STRATEGY_ID id)
{
   return id==MSZZ_STRAT_ALIGNED_FAST_PULLBACK || id==MSZZ_STRAT_BREAKOUT_RETEST ||
          id==MSZZ_STRAT_SWEEP_RECLAIM || id==MSZZ_STRAT_COMPRESSION_BREAKOUT ||
          id==MSZZ_STRAT_STRUCTURE_TRANSITION;
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
   double target_r=PortfolioTargetR(source.strategy_id);
   if(target_r<=0.0){ reason="book target R is invalid"; return false; }
   // D025 variant F: no fixed take-profit at all -- exits via SL or
   // opposite-signal reversal only. See DECISION_LOG.md D025.
   prepared.target=InpDisableFixedTarget ? 0.0 :
      (source.direction==MSZZ_DIR_LONG ? prepared.entry+risk*target_r : prepared.entry-risk*target_r);
   return g_execution_guard.ValidateStops(prepared,prepared.stop,prepared.target,reason,InpDisableFixedTarget);
}

// D029 Phase 1: single sizing entry point shared by both the single-book
// (ExecuteCluster) and multi-book (ExecutePortfolioBookCandidate) execution
// paths. In MSZZ_SIZE_FIXED_LOT (default) mode this is exactly the
// pre-D029 InpFixedLots/NormalizeVolume() call, byte-identical output --
// risk_pct_for_book returns InpPortfolioRiskPerBookPct unchanged, matching
// every certified run's existing (assumed, not computed) bookkeeping value.
// In MSZZ_SIZE_PERCENT_EQUITY mode, computes and journals the full sizing
// decision (accepted or rejected) via CMSZZPositionSizing::Calculate(), and
// returns the ACTUAL normalized risk percent for risk-cap approval and book
// bookkeeping -- never the flat requested percent -- per the D029 handoff's
// explicit "portfolio approval must use actual normalized initial risk"
// requirement. See DECISION_LOG.md D029 Phase 1.
// D029 audit remediation, Finding E: broker-authoritative loss-per-lot via
// OrderCalcProfit(), replacing PositionSizing.mqh's former internal
// (stop_distance/tick_size)*tick_value linear formula -- wrong for any
// instrument whose P&L is not a strict linear function of price distance
// (FX crosses needing account-currency conversion, tiered tick values,
// etc). OrderCalcProfit() naturally handles long/short via ORDER_TYPE_BUY/
// ORDER_TYPE_SELL and account-currency conversion internally. Fails closed
// (false, loss_per_lot=0.0, reason populated) on an OrderCalcProfit()
// failure or a nonpositive resulting loss -- never silently falls back to
// the old formula. See DECISION_LOG.md D029 audit remediation.
bool CalculateBrokerLossPerLot(const string symbol,const ENUM_MSZZ_DIRECTION direction,
                               const double entry,const double stop,
                               double &loss_per_lot,string &reason)
{
   loss_per_lot=0.0; reason="";
   if(direction!=MSZZ_DIR_LONG && direction!=MSZZ_DIR_SHORT)
   { reason="invalid direction for loss-per-lot calculation"; return false; }
   if(entry<=0.0 || stop<=0.0 || MathAbs(entry-stop)<=0.0)
   { reason="invalid entry/stop for loss-per-lot calculation"; return false; }
   ENUM_ORDER_TYPE order_type=(direction==MSZZ_DIR_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double profit=0.0;
   if(!OrderCalcProfit(order_type,symbol,1.0,entry,stop,profit))
   { reason=StringFormat("OrderCalcProfit failed error=%d",GetLastError()); return false; }
   double loss=-profit;
   if(loss<=0.0)
   { reason=StringFormat("OrderCalcProfit returned a nonpositive loss (%.4f) for a stop-out move -- refusing to size",loss); return false; }
   loss_per_lot=loss;
   return true;
}

bool ComputeSizedVolume(const MSZZCandidate &prepared,const long book_id,
                        const ENUM_MSZZ_STRATEGY_ID strategy_id,const long magic,
                        const string logical_position_id,
                        double &volume,double &risk_pct_for_book,
                        bool &partial_capable,string &reject_reason)
{
   reject_reason="";
   double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(InpSizingMode==MSZZ_SIZE_FIXED_LOT)
   {
      volume=g_execution_guard.NormalizeVolume(InpFixedLots);
      risk_pct_for_book=InpPortfolioRiskPerBookPct;
      // D029 audit remediation, Finding D: partial_capable now checks the
      // broker's actual minimum tradable size, not just 2x the step --
      // fixed-lot mode's InpFixedLots=0.01 at this account's 0.01 min/0.01
      // step is still never partial-capable (0.005 rounds down to 0.00),
      // but the check itself no longer silently assumes min==step.
      {
         double vmin_fixed=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
         double dp,dr; string dreason;
         partial_capable=CMSZZPositionSizing::ComputePartialSplit(volume,0.5,vmin_fixed,vstep,dp,dr,dreason);
      }
      if(volume<=0.0){ reject_reason="volume normalization failed"; return false; }
      return true;
   }

   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double tsize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tvalue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   // D029 audit remediation, Finding E: broker-authoritative loss-per-lot
   // computed first and fed into the pure sizing module -- see
   // CalculateBrokerLossPerLot()'s header comment. Fails closed exactly
   // like every other sizing-rejection path in this function.
   double loss_per_lot=0.0; string loss_reason;
   if(!CalculateBrokerLossPerLot(_Symbol,prepared.direction,prepared.entry,prepared.stop,
                                 loss_per_lot,loss_reason))
   {
      volume=0.0; risk_pct_for_book=0.0; partial_capable=false;
      reject_reason=loss_reason;
      return false;
   }

   MSZZSizingResult sizing;
   bool ok=CMSZZPositionSizing::Calculate(equity,InpPortfolioRiskPerBookPct,
                                          prepared.entry,prepared.stop,loss_per_lot,
                                          tsize,tvalue,vmin,vstep,vmax,sizing);
   if(InpWriteCSV)
      g_portfolio_journals.JournalSizing(TimeCurrent(),logical_position_id,strategy_id,
                                         book_id,magic,sizing,0.0,0.0,0.0);
   partial_capable=sizing.partial_capable;
   if(!ok)
   {
      volume=0.0; risk_pct_for_book=0.0;
      reject_reason=sizing.reject_reason;
      return false;
   }
   volume=sizing.normalized_volume;
   risk_pct_for_book=sizing.actual_risk_pct;
   return true;
}

// D029 Phase 3: SweepReclaim's exit policy is only meaningfully SR3-PCT/
// SR4-PCT if the entry itself can support a genuine 50% partial close.
// Rather than silently letting the trade open and then skipping the
// partial later (D028 Stage 5A's behavior, which is exactly how SR3/SR4
// were found to be invalidly tested at 0.01 fixed lots), this rejects the
// ENTRY itself up front -- "Do not silently... fall back to canonical
// fixed exit." Only applies to SweepReclaim under an active partial
// policy; every other strategy/policy combination is unaffected. See
// DECISION_LOG.md D029 Phase 3 / Docs/MultiSpeedZigZag/D029_PERCENT_RISK_PARTIALS.md.
bool RequiresPartialEligibility(const ENUM_MSZZ_STRATEGY_ID strategy_id)
{
   return (strategy_id==MSZZ_STRAT_SWEEP_RECLAIM &&
          (InpSweepExitPolicy==(int)MSZZ_SWEEP_EXIT_SR3_PARTIAL_FIXED ||
           InpSweepExitPolicy==(int)MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER));
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
   MSZZStrategyBookState sizing_book_ctx=ActivePortfolioBookState();
   double volume,portfolio_requested_risk_computed;
   bool sizing_partial_capable;
   string sizing_reject;
   if(!ComputeSizedVolume(prepared,sizing_book_ctx.book_id,prepared.strategy_id,
                          (sizing_book_ctx.magic!=0 ? sizing_book_ctx.magic : InpMagic),
                          cluster.cluster_id,volume,portfolio_requested_risk_computed,
                          sizing_partial_capable,sizing_reject))
   {
      prepared.reason=sizing_reject;
      JournalCandidate(prepared,(InpSizingMode==MSZZ_SIZE_PERCENT_EQUITY ? "REJECT_SIZING" : "REJECT_VOLUME"),
                       cluster.cluster_id);
      return false;
   }
   if(RequiresPartialEligibility(prepared.strategy_id) && !sizing_partial_capable)
   {
      prepared.reason="partial-policy volume ineligible for a valid 50% split -- opening volume below 2x broker step";
      JournalCandidate(prepared,"REJECT_PARTIAL_VOLUME_INELIGIBLE",cluster.cluster_id);
      return false;
   }

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

   bool portfolio_pending=false;
   double portfolio_requested_risk=portfolio_requested_risk_computed;
   if(g_portfolio_single_book_active)
   {
      if(closed_opposite && !PortfolioMarkFlat("own-book opposite close"))
      {
         prepared.reason="active book could not reconcile opposite close";
         JournalCandidate(prepared,"REJECT_PORTFOLIO_BOOK",cluster.cluster_id);
         return false;
      }

      MSZZStrategyBookState books[];
      ArrayResize(books,1);
      books[0]=ActivePortfolioBookState();
      MSZZPortfolioRiskSnapshot risk_snapshot;
      MSZZOwnershipSnapshot ownership_snapshot=g_ownership.Snapshot();
      if(!g_portfolio_risk.BuildSnapshot(books,1,ownership_snapshot.owned_positions,
                                         0.0,0.0,risk_snapshot))
      {
         prepared.reason="portfolio risk snapshot failed: "+risk_snapshot.reason;
         JournalCandidate(prepared,"REJECT_PORTFOLIO_RISK",cluster.cluster_id);
         return false;
      }
      if(!g_portfolio_risk.ApproveOpen(risk_snapshot,books,1,prepared.strategy_id,
                                       prepared.family_id,prepared.direction,
                                       portfolio_requested_risk,volume,reason))
      {
         prepared.reason=reason;
         JournalCandidate(prepared,"REJECT_PORTFOLIO_RISK",cluster.cluster_id);
         return false;
      }
      if(!PortfolioMarkEntryPending(owner,volume,portfolio_requested_risk,reason))
      {
         prepared.reason=reason;
         JournalCandidate(prepared,"REJECT_PORTFOLIO_BOOK",cluster.cluster_id);
         return false;
      }
      if(!PortfolioAssignPendingLogicalPositionId(persistence_id,reason))
      {
         PortfolioMarkFlat("logical position identity rejected");
         prepared.reason=reason;
         JournalCandidate(prepared,"REJECT_PORTFOLIO_BOOK",cluster.cluster_id);
         return false;
      }
      MSZZExecutionPlan plan;
      if(!g_execution_coordinator.BuildOpenPlan(ActivePortfolioBookState(),0.0,plan,reason) ||
         plan.action!=MSZZ_COORDINATOR_OPEN_PHYSICAL)
      {
         PortfolioMarkFlat("execution plan rejected");
         prepared.reason=(reason!="" ? reason : "single-book hedging plan not physical");
         JournalCandidate(prepared,"REJECT_PORTFOLIO_EXECUTION",cluster.cluster_id);
         return false;
      }
      g_portfolio_journals.JournalRisk(TimeCurrent(),plan.book_id,"OPEN",true,
                                       "approved",risk_snapshot,portfolio_requested_risk);
      g_portfolio_journals.JournalBook(TimeCurrent(),ActivePortfolioBookState(),
                                      "ENTRY_PENDING","",
                                      g_execution_coordinator.AccountMode(),
                                      g_last_regime_id);
      portfolio_pending=true;
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
      if(portfolio_pending) PortfolioMarkFlat("event persistence failed");
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
      if(portfolio_pending) PortfolioMarkFlat("intent persistence failed");
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

      if(portfolio_pending)
      {
         MSZZStrategyBookState pending_book=ActivePortfolioBookState();
         string book_reason;
         datetime book_entry_time=TimeCurrent();
         double book_entry_price=(intent.average_fill_price>0.0 ?
                                  intent.average_fill_price : prepared.entry);
         if(!PortfolioMarkOpen(pending_book.logical_position_id,intent.position_ticket,
                               intent.order_ticket,book_entry_time,book_entry_price,
                               prepared.stop,prepared.target,portfolio_requested_risk,
                               book_reason))
         {
            Print("MSZZ D028 BOOK OPEN RECONCILIATION FAILED: ",book_reason);
            g_recovery_required=true;
         }
         else
         {
            g_portfolio_journals.JournalBook(TimeCurrent(),ActivePortfolioBookState(),
                                            "OPEN","",
                                            g_execution_coordinator.AccountMode(),
                                            g_last_regime_id);
         }
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
      if(portfolio_pending) PortfolioMarkFlat("broker order failed");
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
         // D029 audit remediation, Finding B: journal every deal for this
         // intent's position while it is already being read for fill_time/
         // exit_price/closing_time below -- read-only, no new broker query.
         if(InpWriteCSV)
            g_portfolio_journals.JournalDeal(
               (datetime)HistoryDealGetInteger(ticket,DEAL_TIME),0,(ENUM_MSZZ_STRATEGY_ID)intent.strategy_id,
               intent.position_ticket,ticket,
               (entry_type==DEAL_ENTRY_IN ? "IN" : (entry_type==DEAL_ENTRY_OUT ? "OUT" : "OUT_BY")),
               HistoryDealGetDouble(ticket,DEAL_VOLUME),HistoryDealGetDouble(ticket,DEAL_PRICE),
               HistoryDealGetDouble(ticket,DEAL_COMMISSION),HistoryDealGetDouble(ticket,DEAL_SWAP),
               HistoryDealGetDouble(ticket,DEAL_PROFIT));
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

      // D028 Stage 5 bug fix: guard on a ticket-already-journaled set, not
      // on whether ActivePortfolioBookState() still matches this ticket.
      // The book is legitimately reassigned to a NEW position mid-bar by
      // the own-family-opposite-close path (ApplyOwnershipPreflight ->
      // PortfolioMarkFlat("own-book opposite close"), well before
      // DetectClosedPositions() ever sees the old intent) -- an earlier
      // attempt at this fix gated on active-book-matches-ticket and, as a
      // result, silently dropped the portfolio journal row for every
      // opposite-close trade (the common case), not just the intended
      // target (SR5's force-close path, which journals immediately via
      // ExportClosedPortfolioBookFromTrade and must not be double-journaled
      // here). See DECISION_LOG.md D028 Stage 5.
      if(g_portfolio_single_book_active &&
         intent.strategy_id==(int)g_portfolio_strategy_id &&
         !TicketAlreadyPortfolioJournaled(intent.position_ticket))
      {
         MSZZStrategyBookState active_book=ActivePortfolioBookState();
         MSZZStrategyBookState journal_book; ZeroMemory(journal_book);
         journal_book.valid=true;
         journal_book.enabled=true;
         journal_book.book_id=active_book.book_id;
         journal_book.strategy_id=(ENUM_MSZZ_STRATEGY_ID)intent.strategy_id;
         journal_book.family_id=active_book.family_id;
         journal_book.magic=intent.magic;
         journal_book.direction=(ENUM_MSZZ_DIRECTION)intent.direction;
         journal_book.logical_position_id=intent.intent_id;
         journal_book.broker_position_ticket=intent.position_ticket;
         journal_book.entry_time=fill_time;
         journal_book.entry_price=intent.average_fill_price;
         journal_book.stop_price=intent.requested_stop;
         journal_book.target_price=intent.requested_target;
         journal_book.initial_risk_price=MathAbs(intent.average_fill_price-
                                                intent.requested_stop);
         journal_book.logical_volume=intent.filled_volume;
         journal_book.exit_config=active_book.exit_config;
         double realized_r=0.0;
         if(journal_book.initial_risk_price>0.0)
            realized_r=(intent.direction==(int)MSZZ_DIR_LONG ?
                        closing_price-intent.average_fill_price :
                        intent.average_fill_price-closing_price)/
                       journal_book.initial_risk_price;
         if(InpWriteCSV)
            g_portfolio_journals.JournalTrade(journal_book,closing_time,
                                              closing_price,0.0,realized_r,
                                              "broker position closed",
                                              g_last_regime_id);
         MarkTicketPortfolioJournaled(intent.position_ticket);
         if(active_book.position_open &&
            active_book.broker_position_ticket==intent.position_ticket)
         {
            PortfolioMarkFlat("broker position closed");
         }
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

bool TicketAlreadyPortfolioJournaled(const ulong ticket)
{
   for(int i=0;i<ArraySize(g_portfolio_journaled_tickets);i++)
      if(g_portfolio_journaled_tickets[i]==ticket) return true;
   return false;
}

void MarkTicketPortfolioJournaled(const ulong ticket)
{
   int n=ArraySize(g_portfolio_journaled_tickets);
   ArrayResize(g_portfolio_journaled_tickets,n+1);
   g_portfolio_journaled_tickets[n]=ticket;
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

// D026: builds the immutable trail configuration once from Inp* inputs.
// Fails closed (false) if rungs are not supplied in strictly ascending
// trigger_r order -- a config-authoring guard, not a runtime concern (see
// DECISION_LOG.md D026). TriggerR<=0.0 means "this rung slot is unused",
// matching this project's established non-positive-disables convention
// (D012/D013/D015).
bool BuildTrailConfig(MSZZTrailConfig &config,string &reason)
{
   reason="";
   config.enabled=InpEnableResearchTrail;
   config.cost_r_estimate=InpTrailCostEstimateR;
   config.structure_mode=(ENUM_MSZZ_TRAIL_STRUCTURE)InpTrailStructureMode;
   config.structure_activation_r=InpTrailStructureActivationR;
   config.chandelier_atr_len=InpTrailChandelierATRLen;
   config.chandelier_atr_mult=InpTrailChandelierATRMult;

   double triggers[MSZZ_TRAIL_MAX_RUNGS]={InpTrailRung1TriggerR,InpTrailRung2TriggerR,InpTrailRung3TriggerR,
                                           InpTrailRung4TriggerR,InpTrailRung5TriggerR};
   double floors[MSZZ_TRAIL_MAX_RUNGS]={InpTrailRung1FloorR,InpTrailRung2FloorR,InpTrailRung3FloorR,
                                         InpTrailRung4FloorR,InpTrailRung5FloorR};
   config.rung_count=0;
   double last_trigger=-DBL_MAX;
   for(int i=0;i<MSZZ_TRAIL_MAX_RUNGS;i++)
   {
      if(triggers[i]<=0.0) continue;
      if(triggers[i]<=last_trigger)
      {
         reason=StringFormat("trail rung %d trigger_r=%.4f is not strictly ascending",i+1,triggers[i]);
         return false;
      }
      last_trigger=triggers[i];
      int n=config.rung_count;
      config.rungs[n].trigger_r=triggers[i];
      config.rungs[n].floor_r=floors[i];
      config.rung_count=n+1;
   }
   if(!config.enabled) return true;
   if(config.rung_count==0 && config.structure_mode==MSZZ_TRAIL_STRUCT_NONE)
   {
      reason="InpEnableResearchTrail=true but no rungs and no structure mode configured";
      return false;
   }
   if(config.structure_mode!=MSZZ_TRAIL_STRUCT_NONE && config.structure_activation_r<=0.0)
   {
      reason="structure trail mode configured but InpTrailStructureActivationR<=0.0";
      return false;
   }
   if(config.structure_mode==MSZZ_TRAIL_STRUCT_CHANDELIER &&
      (config.chandelier_atr_len<1 || config.chandelier_atr_mult<=0.0))
   {
      reason="Chandelier structure mode requires InpTrailChandelierATRLen>=1 and InpTrailChandelierATRMult>0.0";
      return false;
   }
   return true;
}

// D026: iterates the durable intent store for the ACTIVE intent whose
// position_ticket matches -- same iteration pattern DetectClosedPositions()
// already uses. Entry/original_stop are read from here (never from the
// live position's current SL/TP, which trailing itself mutates), so the R
// basis survives an EA restart even though in-memory trail bookkeeping
// does not. See DECISION_LOG.md D026 "restart persistence" note.
bool FindIntentByTicket(const ulong ticket,MSZZExecutionIntent &out)
{
   int count=g_intent_store.Count();
   for(int i=0;i<count;i++)
   {
      MSZZExecutionIntent intent;
      if(!g_intent_store.IntentAt(i,intent)) continue;
      if(intent.position_ticket==ticket && intent.execution_state==(int)MSZZ_INTENT_POSITION_ACTIVE)
      { out=intent; return true; }
   }
   return false;
}

int FindOrCreateTrailState(const ulong ticket,const ENUM_MSZZ_DIRECTION direction,
                            const double entry,const double original_stop,const double current_broker_stop)
{
   for(int i=0;i<ArraySize(g_trail_states);i++)
      if(g_trail_states[i].active && g_trail_states[i].ticket==ticket) return i;
   int n=ArraySize(g_trail_states);
   ArrayResize(g_trail_states,n+1);
   CMSZZResearchTrailPolicy::InitState(g_trail_states[n],ticket,direction,entry,original_stop,current_broker_stop);
   return n;
}

void JournalTrailUpdate(const ulong ticket,const double old_stop,const double new_stop,
                         const double fav_r,const string reason,const bool ok)
{
   if(!InpWriteCSV) return;
   int h=FileOpen("MSZZ_TrailJournal.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE){ PrintFormat("MSZZ trail journal open failed error=%d",GetLastError()); return; }
   if(FileSize(h)==0) FileWriteString(h,"ticket;time;old_stop;new_stop;fav_r;reason;modify_ok\r\n");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,ticket,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
             DoubleToString(old_stop,8),DoubleToString(new_stop,8),DoubleToString(fav_r,4),reason,(ok?"true":"false"));
   FileFlush(h); FileClose(h);
}

// D026: checked once per closed bar, after the engine rebuild (needs
// fast/med for the structure trail) and before g_suite.Evaluate()/
// ExecuteCluster() -- see DECISION_LOG.md D026 "same-bar ordering" for why
// this position in ProcessClosedBar() satisfies the required
// detect-closure -> trail-update -> evaluate-opposite-signal -> reverse
// sequence.
void ProcessResearchTrail(const MqlRates &rates[],const int closed_count,
                           const MSZZSpeedSnapshot &fast,const MSZZSpeedSnapshot &med)
{
   if(!g_trail_config.enabled) return;
   string reason;
   if(!RefreshOwnership(reason)) return; // best-effort for this research-only feature, matches ProcessPartialCloses
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double min_distance=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                        SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;

   const MqlRates last_bar=rates[closed_count-1];
   double atr=0.0;
   if(g_trail_config.structure_mode==MSZZ_TRAIL_STRUCT_CHANDELIER)
   {
      double high[],low[],close[];
      ArrayResize(high,closed_count); ArrayResize(low,closed_count); ArrayResize(close,closed_count);
      for(int i=0;i<closed_count;i++){ high[i]=rates[i].high; low[i]=rates[i].low; close[i]=rates[i].close; }
      atr=CMSZZResearchTrailPolicy::SimpleATR(high,low,close,closed_count-1,g_trail_config.chandelier_atr_len);
   }

   int count=g_ownership.RecordCount();
   for(int i=0;i<count;i++)
   {
      MSZZPositionRecord record;
      if(!g_ownership.RecordAt(i,record)) continue;
      if(!record.valid || record.owner!=MSZZ_OWNER_OWNED) continue;
      if(record.stop_loss<=0.0) continue;

      MSZZExecutionIntent intent;
      if(!FindIntentByTicket(record.ticket,intent)) continue;
      double entry=intent.average_fill_price;
      double original_stop=intent.requested_stop;
      if(entry<=0.0 || original_stop<=0.0) continue;

      int idx=FindOrCreateTrailState(record.ticket,record.direction,entry,original_stop,record.stop_loss);
      double risk=MathAbs(entry-original_stop);
      if(risk<=0.0) continue;
      double fav_r=CMSZZResearchTrailPolicy::FavorableR(record.direction,entry,risk,last_bar.high,last_bar.low);
      if(fav_r>g_trail_states[idx].max_favorable_r) g_trail_states[idx].max_favorable_r=fav_r;

      double market_price=(record.direction==MSZZ_DIR_LONG ? tick.bid : tick.ask);
      double effective_stop=g_trail_states[idx].effective_stop;
      double best_candidate=effective_stop;
      bool have_candidate=false;

      double floor_candidate;
      if(CMSZZResearchTrailPolicy::EvaluateFloorRung(g_trail_config,g_trail_states[idx],fav_r,floor_candidate))
      {
         double tightened;
         if(CMSZZResearchTrailPolicy::ResolveTightening(record.direction,effective_stop,floor_candidate,
                                                          market_price,min_distance,tightened))
         {
            best_candidate=tightened; have_candidate=true;
         }
      }

      if(g_trail_config.structure_mode!=MSZZ_TRAIL_STRUCT_NONE && fav_r>=g_trail_config.structure_activation_r)
      {
         if(!g_trail_states[idx].structure_activated)
         {
            g_trail_states[idx].structure_activated=true;
            g_trail_states[idx].highest_since_activation=last_bar.high;
            g_trail_states[idx].lowest_since_activation=last_bar.low;
         }
         else
         {
            if(last_bar.high>g_trail_states[idx].highest_since_activation) g_trail_states[idx].highest_since_activation=last_bar.high;
            if(last_bar.low<g_trail_states[idx].lowest_since_activation) g_trail_states[idx].lowest_since_activation=last_bar.low;
         }

         double structure_candidate=0.0; bool structure_valid=false;
         if(g_trail_config.structure_mode==MSZZ_TRAIL_STRUCT_FAST_SWING)
            structure_valid=CMSZZResearchTrailPolicy::SwingTrailCandidate(record.direction,last_bar.close,
                              (record.direction==MSZZ_DIR_LONG ? fast.last_low.valid : fast.last_high.valid),
                              (record.direction==MSZZ_DIR_LONG ? fast.last_low.price : fast.last_high.price),
                              structure_candidate);
         else if(g_trail_config.structure_mode==MSZZ_TRAIL_STRUCT_MEDIUM_SWING)
            structure_valid=CMSZZResearchTrailPolicy::SwingTrailCandidate(record.direction,last_bar.close,
                              (record.direction==MSZZ_DIR_LONG ? med.last_low.valid : med.last_high.valid),
                              (record.direction==MSZZ_DIR_LONG ? med.last_low.price : med.last_high.price),
                              structure_candidate);
         else if(g_trail_config.structure_mode==MSZZ_TRAIL_STRUCT_CHANDELIER && atr>0.0)
         {
            double extreme=(record.direction==MSZZ_DIR_LONG ? g_trail_states[idx].highest_since_activation
                                                              : g_trail_states[idx].lowest_since_activation);
            structure_candidate=CMSZZResearchTrailPolicy::ChandelierCandidate(record.direction,extreme,atr,
                                                                                g_trail_config.chandelier_atr_mult);
            structure_valid=true;
         }

         if(structure_valid)
         {
            double tightened;
            if(CMSZZResearchTrailPolicy::ResolveTightening(record.direction,effective_stop,structure_candidate,
                                                             market_price,min_distance,tightened))
            {
               bool structure_is_tighter=(!have_candidate) ||
                  (record.direction==MSZZ_DIR_LONG ? tightened>best_candidate : tightened<best_candidate);
               if(structure_is_tighter){ best_candidate=tightened; have_candidate=true; }
            }
         }
      }

      if(!have_candidate) continue;
      double normalized=NormalizeDouble(best_candidate,_Digits);
      if(MathAbs(normalized-effective_stop)<_Point/2.0) continue; // duplicate-modification suppression

      bool ok=g_trade.PositionModify(record.ticket,normalized,record.take_profit);
      string mod_reason=(ok ? "trail applied" : StringFormat("retcode=%u %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()));
      JournalTrailUpdate(record.ticket,effective_stop,normalized,fav_r,mod_reason,ok);
      g_trail_states[idx].last_modification_time=TimeCurrent();
      g_trail_states[idx].last_modification_ok=ok;
      g_trail_states[idx].last_modification_reason=mod_reason;
      if(ok) g_trail_states[idx].effective_stop=normalized;
      else PrintFormat("MSZZ WARNING: trail stop modification failed ticket=%I64u %s",record.ticket,mod_reason);
   }
}

MSZZStrategyBookState PortfolioBookStateFor(const ENUM_MSZZ_STRATEGY_ID strategy_id)
{
   if(strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE) return g_fastmed_book.State();
   return g_sweep_book.State();
}

bool PortfolioBookMarkFlatFor(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                              const string reason)
{
   if(strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
      return g_fastmed_book.MarkFlat(reason);
   if(strategy_id==MSZZ_STRAT_SWEEP_RECLAIM)
      return g_sweep_book.MarkFlat(reason);
   return false;
}

bool PortfolioBookMarkPendingFor(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                                 const MSZZCandidate &candidate,
                                 const double volume,const double risk_pct,
                                 const string logical_id,string &reason)
{
   bool ok=false;
   if(strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
   {
      ok=g_fastmed_book.MarkEntryPending(candidate,volume,risk_pct,reason);
      if(ok) ok=g_fastmed_book.AssignPendingLogicalPositionId(logical_id,reason);
   }
   else if(strategy_id==MSZZ_STRAT_SWEEP_RECLAIM)
   {
      ok=g_sweep_book.MarkEntryPending(candidate,volume,risk_pct,reason);
      if(ok) ok=g_sweep_book.AssignPendingLogicalPositionId(logical_id,reason);
   }
   else reason="unsupported portfolio strategy";
   return ok;
}

bool PortfolioBookMarkOpenFor(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                              const string logical_id,const ulong position_ticket,
                              const ulong order_ticket,const datetime entry_time,
                              const double entry_price,const double stop_price,
                              const double target_price,const double risk_pct,
                              string &reason)
{
   if(strategy_id==MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE)
      return g_fastmed_book.MarkOpen(logical_id,position_ticket,order_ticket,
                                     entry_time,entry_price,stop_price,target_price,
                                     risk_pct,reason);
   if(strategy_id==MSZZ_STRAT_SWEEP_RECLAIM)
      return g_sweep_book.MarkOpen(logical_id,position_ticket,order_ticket,
                                   entry_time,entry_price,stop_price,target_price,
                                   risk_pct,reason);
   reason="unsupported portfolio strategy";
   return false;
}

bool ExportAndFlattenPortfolioBook(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                                   const string exit_reason)
{
   MSZZStrategyBookState book=PortfolioBookStateFor(strategy_id);
   if(!book.position_open || book.broker_position_ticket==0) return true;
   if(PositionSelectByTicket(book.broker_position_ticket)) return false;
   if(!HistorySelect(book.entry_time-3600,TimeCurrent())) return false;

   double exit_volume=0.0,exit_price_volume=0.0;
   datetime exit_time=0;
   int deals=HistoryDealsTotal();
   for(int i=0;i<deals;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 ||
         (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=book.broker_position_ticket)
         continue;
      long entry_type=HistoryDealGetInteger(deal,DEAL_ENTRY);
      // D029 audit remediation, Finding B: journal every deal for this
      // position (entry and every exit) while it is already being read for
      // the exit_price/realized_r computation below -- read-only, no new
      // broker query, no change to the computation itself.
      if(InpWriteCSV)
         g_portfolio_journals.JournalDeal(
            (datetime)HistoryDealGetInteger(deal,DEAL_TIME),book.book_id,strategy_id,
            book.broker_position_ticket,deal,
            (entry_type==DEAL_ENTRY_IN ? "IN" : (entry_type==DEAL_ENTRY_OUT ? "OUT" : "OUT_BY")),
            HistoryDealGetDouble(deal,DEAL_VOLUME),HistoryDealGetDouble(deal,DEAL_PRICE),
            HistoryDealGetDouble(deal,DEAL_COMMISSION),HistoryDealGetDouble(deal,DEAL_SWAP),
            HistoryDealGetDouble(deal,DEAL_PROFIT));
      if(entry_type!=DEAL_ENTRY_OUT && entry_type!=DEAL_ENTRY_OUT_BY) continue;
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
      exit_volume+=volume;
      exit_price_volume+=HistoryDealGetDouble(deal,DEAL_PRICE)*volume;
      datetime deal_time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      if(deal_time>exit_time) exit_time=deal_time;
   }
   if(exit_volume<=0.0 || exit_time<=0) return false;
   double exit_price=exit_price_volume/exit_volume;
   double realized_r=(book.direction==MSZZ_DIR_LONG ?
                      exit_price-book.entry_price :
                      book.entry_price-exit_price)/book.initial_risk_price;
   if(InpWriteCSV)
      g_portfolio_journals.JournalTrade(book,exit_time,exit_price,0.0,
                                        realized_r,exit_reason,g_last_regime_id);
   g_portfolio_journals.JournalBook(exit_time,book,"CLOSED",exit_reason,
                                   g_execution_coordinator.AccountMode(),
                                   g_last_regime_id);
   return PortfolioBookMarkFlatFor(strategy_id,exit_reason);
}

// D028 Stage 5: called directly by ProcessOneBookExit()'s SR5 force-close
// branch, immediately after PositionClose() succeeds -- unlike the two
// broker-detection paths above (DetectClosedPositions() for single-book,
// DetectClosedPortfolioBooks()/ExportAndFlattenPortfolioBook() for multi-
// book), which only discover a closure on a LATER bar once the ticket is
// already gone. Marks the ticket journaled so DetectClosedPositions()'s
// own later detection of this same now-closed ticket does not write a
// second MSZZ_PortfolioTradeAnalytics.csv row for it. See
// DECISION_LOG.md D028 Stage 5.
bool ExportClosedPortfolioBookFromTrade(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                                        const string exit_reason,
                                        const double exit_price,
                                        const datetime exit_time)
{
   MSZZStrategyBookState book=PortfolioBookStateFor(strategy_id);
   if(!book.position_open || book.broker_position_ticket==0 ||
      exit_price<=0.0 || exit_time<=0)
      return false;

   // D029 audit remediation, Finding B: independent deal-level
   // reconciliation of the reruns caught a real, pre-existing defect here
   // (not introduced by this audit's patches -- present in the original
   // D029 evidence too). This function's caller-supplied exit_price is
   // only the price of the FINAL closing deal. For a position that was
   // already partially closed earlier (SR3/SR4's own partial-close
   // policies), that silently ignores the profit/loss already realized on
   // the partial leg, understating or overstating realized_r versus the
   // true volume-weighted result across every exit deal -- confirmed via
   // reconcile_deals_and_r.py against real broker deal history (see
   // DECISION_LOG.md D029 audit remediation). Fixed by computing the same
   // volume-weighted exit price ExportAndFlattenPortfolioBook() already
   // uses, from the exact deal scan below, and using THAT for realized_r
   // and the journaled exit_price -- exit_price/exit_time parameters are
   // now only a fallback if the deal scan finds nothing (defensive; should
   // not happen given a position that just closed has at least one exit
   // deal in history by construction).
   double weighted_exit_price=exit_price;
   datetime last_exit_time=exit_time;
   bool have_deal_data=false;
   if(HistorySelect(book.entry_time-3600,TimeCurrent()))
   {
      double exit_volume=0.0,exit_price_volume=0.0;
      datetime scanned_last_time=0;
      int deal_total=HistoryDealsTotal();
      for(int i=0;i<deal_total;i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=book.broker_position_ticket)
            continue;
         long entry_type=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(InpWriteCSV)
            g_portfolio_journals.JournalDeal(
               (datetime)HistoryDealGetInteger(deal,DEAL_TIME),book.book_id,strategy_id,
               book.broker_position_ticket,deal,
               (entry_type==DEAL_ENTRY_IN ? "IN" : (entry_type==DEAL_ENTRY_OUT ? "OUT" : "OUT_BY")),
               HistoryDealGetDouble(deal,DEAL_VOLUME),HistoryDealGetDouble(deal,DEAL_PRICE),
               HistoryDealGetDouble(deal,DEAL_COMMISSION),HistoryDealGetDouble(deal,DEAL_SWAP),
               HistoryDealGetDouble(deal,DEAL_PROFIT));
         if(entry_type!=DEAL_ENTRY_OUT && entry_type!=DEAL_ENTRY_OUT_BY) continue;
         double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
         exit_volume+=volume;
         exit_price_volume+=HistoryDealGetDouble(deal,DEAL_PRICE)*volume;
         datetime deal_time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         if(deal_time>scanned_last_time) scanned_last_time=deal_time;
      }
      if(exit_volume>0.0)
      {
         weighted_exit_price=exit_price_volume/exit_volume;
         last_exit_time=scanned_last_time;
         have_deal_data=true;
      }
   }
   if(!have_deal_data)
      PrintFormat("MSZZ WARNING: ExportClosedPortfolioBookFromTrade found no exit deals in history for ticket=%I64u; falling back to caller-supplied exit_price=%.5f (realized_r may not reflect an earlier partial close)",
                  book.broker_position_ticket,exit_price);

   double realized_r=(book.direction==MSZZ_DIR_LONG ?
                      weighted_exit_price-book.entry_price :
                      book.entry_price-weighted_exit_price)/book.initial_risk_price;
   if(InpWriteCSV)
      g_portfolio_journals.JournalTrade(book,last_exit_time,weighted_exit_price,0.0,
                                        realized_r,exit_reason,g_last_regime_id);
   MarkTicketPortfolioJournaled(book.broker_position_ticket);
   g_portfolio_journals.JournalBook(exit_time,book,"CLOSED",exit_reason,
                                   g_execution_coordinator.AccountMode(),
                                   g_last_regime_id);
   return PortfolioBookMarkFlatFor(strategy_id,exit_reason);
}

void DetectClosedPortfolioBooks()
{
   if(!g_portfolio_multi_book_active) return;
   MSZZStrategyBookState fastmed=g_fastmed_book.State();
   if(fastmed.position_open && !PositionSelectByTicket(fastmed.broker_position_ticket))
      ExportAndFlattenPortfolioBook(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                                    "BROKER_SL_TP_OR_TEST_END");
   MSZZStrategyBookState sweep=g_sweep_book.State();
   if(sweep.position_open && !PositionSelectByTicket(sweep.broker_position_ticket))
      ExportAndFlattenPortfolioBook(MSZZ_STRAT_SWEEP_RECLAIM,
                                    "BROKER_SL_TP_OR_TEST_END");
}

bool ExecutePortfolioBookCandidate(const MSZZOpportunityCluster &cluster,
                                   const MSZZCandidate &owner)
{
   ENUM_MSZZ_STRATEGY_ID strategy_id=owner.strategy_id;
   MSZZStrategyBookState book=PortfolioBookStateFor(strategy_id);
   if(!book.valid || book.strategy_id!=strategy_id) return false;
   // D029 audit remediation, Finding C: the multi-book path never checked
   // g_recovery_required at all (only ExecuteCluster()'s single-book path
   // did) -- found while wiring the protection-failure emergency-close
   // path, which sets this flag. Without this guard, a book with an
   // emergency-close failure (protection permanently unresolved) could
   // still open brand-new entries in the SAME multi-book portfolio. See
   // DECISION_LOG.md D009 (original mechanism) and D029 audit remediation.
   if(g_recovery_required)
   {
      MSZZCandidate rejected=owner;
      rejected.reason="one or more execution intents require manual recovery (see MSZZ RECONCILE/PROTECTION log)";
      JournalCandidate(rejected,"REJECT_RECOVERY_REQUIRED",cluster.cluster_id);
      return false;
   }
   if(cluster.combined_score<g_effective_min_score)
   {
      JournalCandidate(owner,"REJECT_SCORE",cluster.cluster_id);
      return false;
   }
   if(PortfolioEventConsumed(strategy_id,cluster.cluster_id))
   {
      JournalCandidate(owner,"REJECT_DUPLICATE_CLUSTER",cluster.cluster_id);
      return false;
   }
   if(!LiveExecutionAuthorized())
   {
      JournalCandidate(owner,"SHADOW",cluster.cluster_id);
      return true;
   }

   string reason;
   if(!g_execution_guard.TradingAllowed(reason))
   {
      MSZZCandidate rejected=owner; rejected.reason=reason;
      JournalCandidate(rejected,"REJECT_TRADING_DISABLED",cluster.cluster_id);
      return false;
   }
   double spread_points=0.0;
   if(!g_execution_guard.SpreadAllowed(InpMaxSpreadPoints,spread_points))
   {
      MSZZCandidate rejected=owner;
      rejected.reason=StringFormat("spread %.1f exceeds maximum %.1f points",
                                   spread_points,InpMaxSpreadPoints);
      JournalCandidate(rejected,"REJECT_SPREAD",cluster.cluster_id);
      return false;
   }
   string safeguard_reason;
   MSZZStrategyBookState safeguard_book=PortfolioBookStateFor(strategy_id);
   if(!g_safeguard.CheckSafeguards(_Symbol,safeguard_book.magic,
                                    InpMaxTradesPerDay,InpMaxDailyLossAmount,
                                    InpKillSwitchEngaged,safeguard_reason))
   {
      MSZZCandidate rejected=owner; rejected.reason=safeguard_reason;
      JournalCandidate(rejected,"REJECT_ACCOUNT_SAFEGUARD",cluster.cluster_id);
      return false;
   }
   MSZZCandidate prepared;
   if(!PrepareMarketCandidate(owner,prepared,reason))
   {
      prepared=owner; prepared.reason=reason;
      JournalCandidate(prepared,"REJECT_STOPS",cluster.cluster_id);
      return false;
   }
   double volume,book_requested_risk;
   bool sizing_partial_capable;
   string sizing_reject;
   if(!ComputeSizedVolume(prepared,book.book_id,strategy_id,book.magic,
                          cluster.cluster_id,volume,book_requested_risk,
                          sizing_partial_capable,sizing_reject))
   {
      prepared.reason=sizing_reject;
      JournalCandidate(prepared,(InpSizingMode==MSZZ_SIZE_PERCENT_EQUITY ? "REJECT_SIZING" : "REJECT_VOLUME"),
                       cluster.cluster_id);
      return false;
   }
   if(RequiresPartialEligibility(strategy_id) && !sizing_partial_capable)
   {
      prepared.reason="partial-policy volume ineligible for a valid 50% split -- opening volume below 2x broker step";
      JournalCandidate(prepared,"REJECT_PARTIAL_VOLUME_INELIGIBLE",cluster.cluster_id);
      return false;
   }

   book=PortfolioBookStateFor(strategy_id);
   if(book.position_open)
   {
      if(book.direction==prepared.direction)
      {
         JournalCandidate(prepared,"REJECT_OWN_BOOK_OPEN",cluster.cluster_id);
         return false;
      }
      g_trade.SetExpertMagicNumber(book.magic);
      g_trade.SetDeviationInPoints(InpDeviationPoints);
      if(!g_trade.PositionClose(book.broker_position_ticket))
      {
         prepared.reason="own-book opposite close failed";
         JournalCandidate(prepared,"REJECT_OWN_BOOK_CLOSE",cluster.cluster_id);
         return false;
      }
      const double close_price=g_trade.ResultPrice();
      const datetime close_time=TimeCurrent();
      if(!ExportClosedPortfolioBookFromTrade(
            strategy_id,
            CMSZZPortfolioBookRouting::CloseReason(true),
            close_price,close_time))
      {
         prepared.reason="own-book close attribution failed";
         JournalCandidate(prepared,"REJECT_OWN_BOOK_RECONCILIATION",cluster.cluster_id);
         return false;
      }
   }

   MSZZStrategyBookState books[];
   ArrayResize(books,2);
   books[0]=g_fastmed_book.State();
   books[1]=g_sweep_book.State();
   MSZZPortfolioRiskSnapshot snapshot;
   int physical_positions=(books[0].position_open?1:0)+(books[1].position_open?1:0);
   if(!g_portfolio_risk.BuildSnapshot(books,2,physical_positions,0.0,0.0,snapshot) ||
      !g_portfolio_risk.ApproveOpen(snapshot,books,2,strategy_id,owner.family_id,
                                    prepared.direction,book_requested_risk,
                                    volume,reason))
   {
      prepared.reason=(reason!="" ? reason : snapshot.reason);
      JournalCandidate(prepared,"REJECT_PORTFOLIO_RISK",cluster.cluster_id);
      g_portfolio_journals.JournalRisk(TimeCurrent(),book.book_id,"OPEN",false,
                                       prepared.reason,snapshot,
                                       book_requested_risk);
      return false;
   }

   if(!PortfolioBookMarkPendingFor(strategy_id,owner,volume,
                                   book_requested_risk,
                                   cluster.cluster_id,reason))
   {
      prepared.reason=reason;
      JournalCandidate(prepared,"REJECT_PORTFOLIO_BOOK",cluster.cluster_id);
      return false;
   }
   book=PortfolioBookStateFor(strategy_id);
   MSZZExecutionPlan plan;
   if(!g_execution_coordinator.BuildOpenPlan(book,0.0,plan,reason) ||
      plan.action!=MSZZ_COORDINATOR_OPEN_PHYSICAL)
   {
      PortfolioBookMarkFlatFor(strategy_id,"physical plan rejected");
      return false;
   }

   ENUM_ORDER_TYPE order_type=(prepared.direction==MSZZ_DIR_LONG ?
                               ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double required_margin,free_margin;
   if(!g_margin.CheckMargin(_Symbol,order_type,volume,prepared.entry,
                            InpMarginBufferRatio,required_margin,free_margin,reason))
   {
      PortfolioBookMarkFlatFor(strategy_id,"margin rejected");
      return false;
   }
   g_trade.SetExpertMagicNumber(book.magic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   string comment="PB"+MSZZCorrelationToken(cluster.cluster_id);
   if(!ConsumePortfolioEvent(strategy_id,cluster.cluster_id))
   {
      PortfolioBookMarkFlatFor(strategy_id,"event persistence failed");
      prepared.reason="portfolio event persistence failed";
      JournalCandidate(prepared,"REJECT_INTENT_PERSISTENCE",cluster.cluster_id);
      return false;
   }
   bool ok=(prepared.direction==MSZZ_DIR_LONG ?
            g_trade.Buy(volume,_Symbol,0.0,prepared.stop,prepared.target,comment) :
            g_trade.Sell(volume,_Symbol,0.0,prepared.stop,prepared.target,comment));
   if(!ok)
   {
      PortfolioBookMarkFlatFor(strategy_id,"broker order failed");
      prepared.reason=g_trade.ResultRetcodeDescription();
      JournalCandidate(prepared,"ORDER_FAILED",cluster.cluster_id);
      return false;
   }

   ulong order_ticket=g_trade.ResultOrder();
   ulong position_ticket=order_ticket;
   double entry_price=g_trade.ResultPrice();
   if(entry_price<=0.0) entry_price=prepared.entry;
   if(!PortfolioBookMarkOpenFor(strategy_id,cluster.cluster_id,position_ticket,
                                order_ticket,TimeCurrent(),entry_price,
                                prepared.stop,prepared.target,
                                book_requested_risk,reason))
   {
      Print("MSZZ D028 MULTI BOOK OPEN RECONCILIATION FAILED: ",reason);
      return false;
   }
   book=PortfolioBookStateFor(strategy_id);
   g_portfolio_journals.JournalRisk(TimeCurrent(),book.book_id,"OPEN",true,
                                    "approved",snapshot,book_requested_risk);
   g_portfolio_journals.JournalBook(TimeCurrent(),book,"OPEN","",
                                    g_execution_coordinator.AccountMode(),
                                    g_last_regime_id);
   plan.owned_ticket=position_ticket;
   plan.logical_position_id=cluster.cluster_id;
   g_portfolio_journals.JournalAllocation(TimeCurrent(),plan,g_trade.ResultDeal(),
                                          "OPEN","NONE",0.0,0.0);
   JournalCluster(cluster,"EXECUTED");
   JournalCandidate(prepared,"EXECUTED",cluster.cluster_id);
   return true;
}

void ProcessPortfolioStrategyCandidates(const ENUM_MSZZ_STRATEGY_ID strategy_id,
                                        const MSZZCandidate &candidates[],
                                        const int candidate_count)
{
   MSZZCandidate subset[];
   int count=0;
   for(int i=0;i<candidate_count;i++)
   {
      if(candidates[i].strategy_id!=strategy_id) continue;
      ArrayResize(subset,count+1);
      subset[count++]=candidates[i];
   }
   if(count<=0) return;
   MSZZOpportunityCluster clusters[];
   int cluster_count=g_cluster_engine.Build(_Symbol,_Period,subset,count,clusters);
   if(cluster_count<=0) return;
   int best=g_cluster_engine.SelectBest(clusters,cluster_count);
   if(best<0 || !clusters[best].valid) return;
   int owner_index=clusters[best].preferred_index;
   if(owner_index<0 || owner_index>=count) return;
   ExecutePortfolioBookCandidate(clusters[best],subset[owner_index]);
}

void ProcessMultiBookCandidates(const MSZZCandidate &candidates[],
                                const int candidate_count)
{
   // Frozen deterministic arbitration for Stage 4: core book first, then
   // SweepReclaim. Portfolio policy—not cross-family mutation—decides whether
   // the second book may coexist.
   ProcessPortfolioStrategyCandidates(MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE,
                                      candidates,candidate_count);
   ProcessPortfolioStrategyCandidates(MSZZ_STRAT_SWEEP_RECLAIM,
                                      candidates,candidate_count);
}

// D028 Stage 5: applies one book's exit-management decision this closed
// bar, if its exit_config.trailing_policy_id is non-zero (SR0 is always a
// no-op, matching Stage 4's certified behavior exactly). Order within
// ProcessClosedBar() matches this project's established same-bar
// discipline (D026): detect prior-bar closure -> confirmed exit-management
// update -> evaluate new signal/opposite exit. See DECISION_LOG.md D028
// Stage 5.
// D029 audit remediation, Finding C: frozen before any rerun result was
// inspected -- 3 retry attempts (in addition to the initial same-bar
// attempt), then emergency-close the unprotected remainder.
#define MSZZ_PROTECTION_MAX_RETRIES 3

// D029 audit remediation, Finding C: while a book's remainder is in
// MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING, no new exit-management decision
// is evaluated for it at all (CMSZZBookExitManager::Evaluate() is not
// called) -- this single retry path is the ONLY thing that runs, which by
// construction blocks SR4's runner-trail progression (reached only via a
// normal Evaluate() call) until protection is confirmed, without needing
// to change BookExitManager.mqh's pure SR4 logic at all. Retries a plain
// PositionModify() with the same frozen target stop/target every closed
// bar; after MSZZ_PROTECTION_MAX_RETRIES failures, emergency-closes the
// remainder; if that ALSO fails, sets g_recovery_required (existing D009
// mechanism) and blocks new entries. Every attempt is journaled. See
// DECISION_LOG.md D029 audit remediation.
void ProcessPendingProtection(CMSZZStrategyBook &book_obj,const MSZZStrategyBookState &book)
{
   g_trade.SetExpertMagicNumber(book.magic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   double new_target=(book.protection_remove_target ? 0.0 : book.target_price);
   bool ok=g_trade.PositionModify(book.broker_position_ticket,book.protection_target_stop,new_target);
   int attempt_num=book.protection_retry_count+1;
   g_portfolio_journals.JournalExitManagement(TimeCurrent(),book.book_id,
      book.exit_config.trailing_policy_id,"PROTECTION_RETRY",0.0,book.effective_stop,
      book.protection_target_stop,0.0,ok,
      StringFormat("protection retry attempt %d of %d",attempt_num,MSZZ_PROTECTION_MAX_RETRIES));

   if(ok)
   {
      book_obj.UpdatePartialProtectionState(MSZZ_PARTIAL_PROTECTED,attempt_num,
         book.protection_target_stop,book.protection_remove_target);
      book_obj.UpdateExitManagementState(book.max_favorable_r,book.breakeven_activated,
         book.structure_activated,book.highest_since_activation,book.lowest_since_activation,
         book.protection_target_stop,book.partial_close_done,book.time_stop_evaluated_done);
      return;
   }

   if(attempt_num<MSZZ_PROTECTION_MAX_RETRIES)
   {
      book_obj.UpdatePartialProtectionState(MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING,attempt_num,
         book.protection_target_stop,book.protection_remove_target);
      return;
   }

   // Retries exhausted: emergency-close the unprotected remainder rather
   // than let it keep running without the intended protection.
   bool closed=g_trade.PositionClose(book.broker_position_ticket);
   g_portfolio_journals.JournalExitManagement(TimeCurrent(),book.book_id,
      book.exit_config.trailing_policy_id,"PROTECTION_EMERGENCY_CLOSE",0.0,
      book.effective_stop,book.effective_stop,0.0,closed,
      "protection retries exhausted -- emergency-closing unprotected remainder");
   if(closed)
   {
      double close_price=g_trade.ResultPrice();
      datetime close_time=TimeCurrent();
      ExportClosedPortfolioBookFromTrade(book.strategy_id,"PROTECTION_EMERGENCY_CLOSE",
                                         close_price,close_time);
      // ExportClosedPortfolioBookFromTrade already marks the book flat,
      // which resets protection_state to MSZZ_PARTIAL_NOT_STARTED for the
      // next entry -- nothing further to persist here.
   }
   else
   {
      g_recovery_required=true;
      book_obj.UpdatePartialProtectionState(MSZZ_PARTIAL_PROTECTION_FAILED,attempt_num,
         book.protection_target_stop,book.protection_remove_target);
      PrintFormat("MSZZ CRITICAL: D029 audit protection emergency close FAILED book=%d ticket=%I64u retcode=%u %s -- recovery required, new entries blocked",
                  book.book_id,book.broker_position_ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
   }
}

void ProcessOneBookExit(CMSZZStrategyBook &book_obj,const MSZZSpeedSnapshot &fast,
                        const MqlRates &bar)
{
   MSZZStrategyBookState book=book_obj.State();
   if(!book.valid || book.status!=MSZZ_BOOK_OPEN || !book.position_open) return;
   ENUM_MSZZ_SWEEP_EXIT_POLICY policy=(ENUM_MSZZ_SWEEP_EXIT_POLICY)book.exit_config.trailing_policy_id;
   if(policy==MSZZ_SWEEP_EXIT_SR0_FIXED2R) return;
   if(book.initial_risk_price<=0.0) return;

   // Restart-safety: if bookkeeping was lost but the position is genuinely
   // still open, reseed effective_stop from the current broker-side stop
   // before evaluating anything -- never from a remembered value.
   if(book.effective_stop<=0.0)
   {
      if(PositionSelectByTicket(book.broker_position_ticket))
      {
         double broker_stop=PositionGetDouble(POSITION_SL);
         if(broker_stop>0.0) book_obj.ReseedEffectiveStopIfMissing(broker_stop);
      }
      book=book_obj.State();
      if(book.effective_stop<=0.0) return; // still unknown this bar; try again next bar
   }

   // D029 audit remediation, Finding C: while protection is unresolved
   // from a prior bar's partial close, this is the ONLY thing that runs
   // for this book this bar -- no new CMSZZBookExitManager::Evaluate()
   // call, which is what blocks SR4's runner-trail progression (and any
   // other exit-management decision) until protection is confirmed. See
   // ProcessPendingProtection()'s own header comment.
   if(book.protection_state==MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING)
   {
      ProcessPendingProtection(book_obj,book);
      return;
   }

   double fav_r=CMSZZBookExitManager::FavorableR(book.direction,book.entry_price,
                                                  book.initial_risk_price,bar.high,bar.low);
   double max_fav_r=MathMax(book.max_favorable_r,fav_r);

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double market_price=(book.direction==MSZZ_DIR_LONG ? tick.bid : tick.ask);
   double min_distance=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                        SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   int bars_since_entry=(PeriodSeconds()>0) ? (int)((bar.time-book.entry_time)/PeriodSeconds()) : 0;

   MSZZBookExitDecision decision;
   bool have_decision=CMSZZBookExitManager::Evaluate(policy,book,bar,fast,market_price,min_distance,
                                                      bars_since_entry,max_fav_r,decision);

   bool breakeven_activated=book.breakeven_activated || (policy==MSZZ_SWEEP_EXIT_SR1_BREAKEVEN && have_decision);
   bool structure_activated=book.structure_activated ||
      ((policy==MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL || policy==MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER) &&
       max_fav_r>=MSZZ_SR_STRUCTURE_ACTIVATION_R);
   bool partial_done=book.partial_close_done;
   double effective_stop=book.effective_stop;

   if(!have_decision)
   {
      book_obj.UpdateExitManagementState(max_fav_r,breakeven_activated,structure_activated,
                                         book.highest_since_activation,book.lowest_since_activation,
                                         effective_stop,partial_done,book.time_stop_evaluated_done);
      return;
   }

   g_trade.SetExpertMagicNumber(book.magic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);

   if(decision.force_close)
   {
      bool ok=g_trade.PositionClose(book.broker_position_ticket);
      g_portfolio_journals.JournalExitManagement(TimeCurrent(),book.book_id,(int)policy,
         "TIME_STOP",max_fav_r,book.stop_price,book.stop_price,0.0,ok,decision.reason);
      if(ok)
      {
         double close_price=g_trade.ResultPrice();
         datetime close_time=TimeCurrent();
         ExportClosedPortfolioBookFromTrade(book.strategy_id,"TIME_STOP",close_price,close_time);
      }
      return;
   }

   int protection_state=book.protection_state;
   int protection_retry_count=book.protection_retry_count;
   double protection_target_stop=book.protection_target_stop;
   bool protection_remove_target=book.protection_remove_target;

   if(decision.partial_close)
   {
      double requested_partial_volume=book.logical_volume*decision.partial_fraction;
      double vstep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      double close_volume,remaining_volume; string split_reject_reason;
      // D029 Phase 3 / audit Finding D: uses the same tested split helper
      // the EA's entry-time eligibility gate is built on
      // (CMSZZPositionSizing::ComputePartialSplit), now checking the
      // broker's actual minimum volume (not just 2x the step) for both
      // legs independently -- guarantees "no full-close masquerading as
      // partial" by construction (returns false rather than a clamped-to-
      // full volume).
      bool splittable=CMSZZPositionSizing::ComputePartialSplit(book.logical_volume,
                          decision.partial_fraction,vmin,vstep,close_volume,remaining_volume,
                          split_reject_reason);
      if(splittable)
      {
         bool ok=g_trade.PositionClosePartial(book.broker_position_ticket,close_volume);
         double partial_price=(ok ? g_trade.ResultPrice() : 0.0);
         ulong partial_deal=(ok ? g_trade.ResultDeal() : 0);
         g_portfolio_journals.JournalExitManagement(TimeCurrent(),book.book_id,(int)policy,
            "PARTIAL_CLOSE",max_fav_r,book.stop_price,decision.new_stop,close_volume,ok,decision.reason);
         // D029 Phase 3: full parent/child accounting for exact
         // reconciliation -- see JournalPartialClose()'s own header comment.
         g_portfolio_journals.JournalPartialClose(TimeCurrent(),book.book_id,(int)policy,
            book.logical_volume,decision.partial_fraction,requested_partial_volume,
            close_volume,(ok ? close_volume : 0.0),
            (ok ? remaining_volume : book.logical_volume),
            partial_deal,partial_price,ok,decision.reason);
         if(ok)
         {
            partial_done=true;
            // D029 audit remediation, Finding C: the partial succeeding and
            // its required protection succeeding are two separate broker
            // calls -- attempt protection immediately (same bar), but never
            // conflate the two outcomes. Only a CONFIRMED successful modify
            // reaches MSZZ_PARTIAL_PROTECTED; any failure enters the pending
            // retry state instead of being silently treated as done.
            double new_target=(decision.remove_target ? 0.0 : book.target_price);
            bool protect_ok=g_trade.PositionModify(book.broker_position_ticket,decision.new_stop,new_target);
            string protect_action=((policy==MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL ||
                                    policy==MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER) ? "STRUCTURAL_TRAIL" : "STOP_MODIFY");
            g_portfolio_journals.JournalExitManagement(TimeCurrent(),book.book_id,(int)policy,protect_action,
               max_fav_r,book.stop_price,decision.new_stop,0.0,protect_ok,decision.reason);
            if(protect_ok)
            {
               effective_stop=decision.new_stop;
               protection_state=MSZZ_PARTIAL_PROTECTED;
               protection_retry_count=0;
               protection_target_stop=decision.new_stop;
               protection_remove_target=decision.remove_target;
            }
            else
            {
               protection_state=MSZZ_PARTIAL_EXECUTED_PROTECTION_PENDING;
               protection_retry_count=1;
               protection_target_stop=decision.new_stop;
               protection_remove_target=decision.remove_target;
               PrintFormat("MSZZ WARNING: D029 audit partial protection modify failed book=%d ticket=%I64u retcode=%u %s -- entering retry state",
                           book.book_id,book.broker_position_ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
            }
         }
         else PrintFormat("MSZZ WARNING: D028 Stage5 partial close failed book=%d ticket=%I64u retcode=%u %s",
                          book.book_id,book.broker_position_ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      }
      else
      {
         // D029 audit remediation, Finding D: journals the actual reason
         // ComputePartialSplit() rejected the split (e.g. a leg below
         // volume_min), not a hardcoded generic message -- this branch
         // should be structurally unreachable now that entry-time
         // eligibility already checked partial_capable with the same
         // corrected logic, but is retained as defense-in-depth.
         g_portfolio_journals.JournalExitManagement(TimeCurrent(),book.book_id,(int)policy,
            "PARTIAL_CLOSE_SKIPPED_VOLUME",max_fav_r,book.stop_price,book.stop_price,0.0,false,
            split_reject_reason);
      }
   }

   // D029 audit remediation, Finding C: SR3/SR4's own protection modify is
   // now handled entirely inline above, atomically sequenced with its
   // partial close -- this generic block only ever applies to policies
   // that set modify_stop WITHOUT a partial_close in the same decision
   // (SR1 breakeven, SR2 structural trail), unchanged from before.
   if(decision.modify_stop && !decision.partial_close)
   {
      double new_target=(decision.remove_target ? 0.0 : book.target_price);
      bool ok=g_trade.PositionModify(book.broker_position_ticket,decision.new_stop,new_target);
      string action=(policy==MSZZ_SWEEP_EXIT_SR1_BREAKEVEN ? "BREAKEVEN" :
                     (policy==MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL || policy==MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER) ?
                     "STRUCTURAL_TRAIL" : "STOP_MODIFY");
      g_portfolio_journals.JournalExitManagement(TimeCurrent(),book.book_id,(int)policy,action,
         max_fav_r,book.stop_price,decision.new_stop,0.0,ok,decision.reason);
      if(ok) effective_stop=decision.new_stop;
      else PrintFormat("MSZZ WARNING: D028 Stage5 stop modification failed book=%d ticket=%I64u retcode=%u %s",
                       book.book_id,book.broker_position_ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
   }

   book_obj.UpdatePartialProtectionState(protection_state,protection_retry_count,
                                         protection_target_stop,protection_remove_target);
   book_obj.UpdateExitManagementState(max_fav_r,breakeven_activated,structure_activated,
                                      book.highest_since_activation,book.lowest_since_activation,
                                      effective_stop,partial_done,book.time_stop_evaluated_done);
}

void ProcessBookExitManagement(const MSZZSpeedSnapshot &fast,const MqlRates &bar)
{
   // D028 Stage 5 bug fix: the original gate only checked
   // g_portfolio_multi_book_active, so single-strategy runs (e.g. Stage 5's
   // SweepReclaim-only configs, which set g_portfolio_single_book_active
   // instead -- see ConfigurePortfolioArchitecture()) never reached
   // ProcessOneBookExit() at all, regardless of InpSweepExitPolicy. Matches
   // the existing !single && !multi convention used at PortfolioTargetR().
   if(!g_portfolio_multi_book_active && !g_portfolio_single_book_active) return;
   ProcessOneBookExit(g_fastmed_book,fast,bar);
   ProcessOneBookExit(g_sweep_book,fast,bar);
}

void ProcessClosedBar()
{
   DetectClosedPositions();
   DetectClosedPortfolioBooks();

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

   // D027: regime classification happens once per bar, immediately after
   // the engine rebuild (it needs fast/med/slow) and before any candidate
   // is evaluated -- every JournalCandidate() call this bar reads
   // g_last_regime/g_last_regime_id. LABEL_ONLY mode (the default and only
   // mode active anywhere in this branch today) never filters anything;
   // this is purely an observer. See DECISION_LOG.md D027.
   CMSZZRegimeClassifier::Evaluate(fast,med,slow,rates,closed_count,PeriodSeconds(),g_last_regime);
   g_last_regime_id=TimeToString(g_last_regime.evaluation_time,TIME_DATE|TIME_SECONDS);
   JournalRegime(g_last_regime);

   // D031: six-family shadow research, evaluated immediately after regime
   // classification (same dependency as every strategy below) but BEFORE
   // g_suite/g_d027_suite -- and its output is a disjoint MSZZResearchCandidate
   // array that is never passed to CMSZZCandidateHandoff, g_cluster_engine,
   // or ExecuteCluster. Pure observer, same shape as JournalRegime() above:
   // reads this bar's fast/med/slow/regime, writes only its own journal.
   if(InpEnableSixFamilyResearch)
   {
      MSZZResearchCandidate six_family_candidates[];
      g_six_family_suite.Evaluate(fast,med,slow,g_last_regime,rates[closed_count-1],six_family_candidates);
   }

   ProcessResearchTrail(rates,closed_count,fast,med);
   ProcessBookExitManagement(fast,rates[closed_count-1]);

   g_suite.SetRiskReward(InpRiskReward);
   g_suite.SetSignalValidityBars(InpSignalValidityBars);
   g_suite.ConfigureStrategies(InpEnableFastBreakout,InpEnableMediumBreakout,InpEnableSlowBreakout,
                               InpEnableFastMedConfluence,InpEnableFastMedContext,InpEnableMedSlowContext,
                               InpEnableNestedPullback,InpEnableWeightedEnsemble);
   MSZZCandidate candidates[];
   int candidate_count=g_suite.Evaluate(fast,med,slow,rates[closed_count-1].time,rates[closed_count-1].close,candidates);
   MSZZCandidate d027_candidates[];
   int d027_count=g_d027_suite.Evaluate(fast,med,slow,g_last_regime,rates[closed_count-1],d027_candidates);
   string handoff_diagnostic;
   if(!CMSZZCandidateHandoff::ValidateCollection(candidates,candidate_count,handoff_diagnostic))
   {
      Print("MSZZ CANDIDATE HANDOFF REJECTED stage=legacy reason=",handoff_diagnostic);
      return;
   }
   if(!CMSZZCandidateHandoff::ValidateCollection(d027_candidates,d027_count,handoff_diagnostic))
   {
      Print("MSZZ CANDIDATE HANDOFF REJECTED stage=d027 reason=",handoff_diagnostic);
      return;
   }
   for(int i=0;i<d027_count;i++)
   {
      int appended_index=-1;
      if(!CMSZZCandidateHandoff::Append(candidates,candidate_count,d027_candidates[i],
                                       appended_index,handoff_diagnostic))
      {
         PrintFormat("MSZZ CANDIDATE HANDOFF REJECTED stage=append source_index=%d reason=%s",
                     i,handoff_diagnostic);
         return;
      }
      if(appended_index<0 || appended_index>=candidate_count)
      {
         PrintFormat("MSZZ CANDIDATE HANDOFF REJECTED stage=append_index index=%d count=%d",
                     appended_index,candidate_count);
         return;
      }
   }
   if(candidate_count<=0) return;
   MSZZCandidate eligible_candidates[]; int eligible_count=0;
   for(int i=0;i<candidate_count;i++)
   {
      if(!candidates[i].valid) continue;
      JournalCandidate(candidates[i],"RAW_CANDIDATE");
      bool eligible=true;
      if(IsD027Strategy(candidates[i].strategy_id) &&
         (ENUM_MSZZ_ELIGIBILITY_MODE)InpRegimeEligibilityMode==MSZZ_ELIGIBILITY_RESEARCH_FILTER)
      {
         string eligibility_reason;
         eligible=CMSZZRegimeEligibilityPolicy::IsEligible(MSZZ_ELIGIBILITY_RESEARCH_FILTER,
                    candidates[i].family_id,candidates[i].strategy_id,g_last_regime,eligibility_reason);
         if(!eligible){ MSZZCandidate rejected=candidates[i]; rejected.reason=eligibility_reason; JournalCandidate(rejected,"REJECT_REGIME"); }
      }
      if(eligible)
      {
         ArrayResize(eligible_candidates,eligible_count+1);
         eligible_candidates[eligible_count++]=candidates[i];
      }
   }
   ArrayResize(candidates,eligible_count);
   for(int i=0;i<eligible_count;i++) candidates[i]=eligible_candidates[i];
   candidate_count=eligible_count;
   if(candidate_count<=0) return;
   if(!CMSZZCandidateHandoff::ValidateCollection(candidates,candidate_count,handoff_diagnostic))
   {
      Print("MSZZ CANDIDATE HANDOFF REJECTED stage=eligible reason=",handoff_diagnostic);
      return;
   }
   if(g_portfolio_multi_book_active)
   {
      ProcessMultiBookCandidates(candidates,candidate_count);
      return;
   }

   MSZZOpportunityCluster clusters[];
   int cluster_count=g_cluster_engine.Build(_Symbol,_Period,candidates,candidate_count,clusters);
   if(cluster_count<0)
   {
      Print("MSZZ CANDIDATE HANDOFF REJECTED stage=cluster reason=",g_cluster_engine.LastDiagnostic());
      return;
   }
   if(cluster_count==0) return;
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

   if(InpEnableMultiBookPortfolio)
   {
      string portfolio_reason;
      if(!ConfigurePortfolioArchitecture(portfolio_reason))
      {
         Print("MSZZ D028 PORTFOLIO CONFIG REJECTED: ",portfolio_reason);
         return INIT_FAILED;
      }
      PrintFormat("MSZZ D028 PORTFOLIO ARCHITECTURE READY mode=%s policy=%s "
                  "physical_ticket_isolation=%s virtual_ledger_required=%s",
                  CMSZZPositionOwnership::AccountModeText(g_execution_coordinator.AccountMode()),
                  CMSZZCrossFamilyPolicy::Text(
                     (ENUM_MSZZ_CROSS_FAMILY_POLICY)InpCrossFamilyPolicy),
                  (g_execution_coordinator.PhysicalTicketIsolationSupported()?"true":"false"),
                  (g_execution_coordinator.VirtualLedgerRequired()?"true":"false"));
      if(!g_execution_coordinator.PhysicalTicketIsolationSupported())
      {
         Print("MSZZ D028 STAGE 3 REJECTED: single-book equivalence is restricted "
               "to the isolated HEDGING account.");
         return INIT_FAILED;
      }
      if(g_portfolio_multi_book_active)
         PrintFormat("MSZZ D028 STAGE 4 MULTI BOOK ACTIVE fastmed_magic=%I64d "
                     "sweep_magic=%I64d opposing=%s same_direction=%s",
                     g_fastmed_book.State().magic,g_sweep_book.State().magic,
                     (InpPortfolioAllowOpposingBooks?"true":"false"),
                     (InpPortfolioAllowSameDirectionStacking?"true":"false"));
      else
         PrintFormat("MSZZ D028 STAGE 3 SINGLE BOOK ACTIVE strategy_id=%d magic=%I64d target_r=%.2f",
                     (int)g_portfolio_strategy_id,InpMagic,
                     PortfolioTargetR(g_portfolio_strategy_id));
   }

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

   // D026: fail closed on a malformed trail configuration rather than
   // silently ignoring it or guessing an intended order. See
   // DECISION_LOG.md D026.
   string trail_reason;
   if(!BuildTrailConfig(g_trail_config,trail_reason))
   {
      PrintFormat("MSZZ RESEARCH TRAIL CONFIG REJECTED: %s -- refusing to start. See DECISION_LOG.md D026.",trail_reason);
      return INIT_FAILED;
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

   string d027_state_file=StringFormat("MSZZ_D027_State_%s_%d_%I64d.csv",_Symbol,(int)_Period,InpMagic);
   g_d027_suite.Configure(InpEnableAlignedFastPullback,InpEnableBreakoutRetest,InpEnableSweepReclaim,
                          InpEnableCompressionBreakout,InpEnableStructureTransition,InpRiskReward,
                          InpSignalValidityBars,PeriodSeconds(),InpWriteCSV,d027_state_file);
   if(g_d027_suite.AnyEnabled() && !g_d027_suite.LoadState())
   {
      Print("MSZZ D027 sequence-state load failed; refusing to start enabled multi-step research.");
      return INIT_FAILED;
   }

   g_six_family_suite.Configure(PeriodSeconds(),InpWriteCSV);

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
   if(InpEnableAlignedFastPullback) out+=(out=="" ? "" : ",")+"AlignedFastPullback";
   if(InpEnableBreakoutRetest)      out+=(out=="" ? "" : ",")+"BreakoutRetest";
   if(InpEnableSweepReclaim)        out+=(out=="" ? "" : ",")+"SweepReclaim";
   if(InpEnableCompressionBreakout) out+=(out=="" ? "" : ",")+"CompressionBreakout";
   if(InpEnableStructureTransition) out+=(out=="" ? "" : ",")+"StructureTransition";
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
   if(g_d027_suite.AnyEnabled() && !g_d027_suite.SaveState())
      Print("MSZZ WARNING: D027 sequence-state save failed during deinitialization.");
   // D026: the Strategy Tester force-closes any still-open position at the
   // literal end of the test window to finalize equity -- a real closing
   // deal the MT5 native report counts, but one that happens after the
   // EA's last new-bar OnTick() has already run, so ProcessClosedBar()'s
   // own DetectClosedPositions() call never sees it. A second call here,
   // before WriteRunSummary(), is a no-op for the live/non-Tester case
   // (DetectClosedPositions() already skips any ticket that still resolves
   // via PositionSelectByTicket(), which it always will for an EA removed
   // mid-trade on a live/demo chart) and only does new work in the
   // Tester-forced-liquidation case. See DECISION_LOG.md D026.
   DetectClosedPositions();
   DetectClosedPortfolioBooks();
   g_trade_analytics.WriteRunSummary(_Symbol,InpMagic,_Period,InpRiskReward,EnabledStrategiesSummary());
   if(g_research_mode_active) WriteResearchManifest();
   PrintFormat("MSZZ deinitialized reason=%d",reason);
}
