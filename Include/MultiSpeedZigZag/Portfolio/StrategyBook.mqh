#ifndef __MSZZ_STRATEGY_BOOK_MQH__
#define __MSZZ_STRATEGY_BOOK_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

enum ENUM_MSZZ_BOOK_STATUS
{
   MSZZ_BOOK_DISABLED = 0,
   MSZZ_BOOK_FLAT,
   MSZZ_BOOK_ENTRY_PENDING,
   MSZZ_BOOK_OPEN,
   MSZZ_BOOK_EXIT_PENDING,
   MSZZ_BOOK_RECOVERY_REQUIRED
};

enum ENUM_MSZZ_BOOK_EXIT_POLICY
{
   MSZZ_BOOK_EXIT_LEGACY = 0,
   MSZZ_BOOK_EXIT_FIXED_R = 1,
   MSZZ_BOOK_EXIT_SWEEP_CANONICAL_2R = 2
};

// D028 Stage 5: SweepReclaim exit-management variants. Selected via
// MSZZBookExitConfig.trailing_policy_id, orthogonal to policy_id above
// (policy_id still governs the base fixed-target/opposite-exit shape;
// trailing_policy_id governs what, if anything, additionally manages the
// stop/volume before that fixed target or opposite exit fires). SR0 is the
// default (0) and is an exact no-op versus Stage 4's certified behavior.
// See DECISION_LOG.md D028 Stage 5 for the frozen definition of each.
enum ENUM_MSZZ_SWEEP_EXIT_POLICY
{
   MSZZ_SWEEP_EXIT_SR0_FIXED2R = 0,
   MSZZ_SWEEP_EXIT_SR1_BREAKEVEN = 1,
   MSZZ_SWEEP_EXIT_SR2_STRUCTURAL_TRAIL = 2,
   MSZZ_SWEEP_EXIT_SR3_PARTIAL_FIXED = 3,
   MSZZ_SWEEP_EXIT_SR4_PARTIAL_RUNNER = 4,
   MSZZ_SWEEP_EXIT_SR5_TIME_STOP = 5
};

struct MSZZBookExitConfig
{
   int    policy_id;
   double target_r;
   bool   own_family_opposite_exit;
   int    trailing_policy_id;
   double partial_close_at_r;
   double partial_close_fraction;
   int    time_stop_bars;
};

struct MSZZStrategyBookState
{
   long                      book_id;
   ENUM_MSZZ_STRATEGY_ID     strategy_id;
   ENUM_MSZZ_STRATEGY_FAMILY family_id;
   long                      magic;
   bool                      enabled;
   ENUM_MSZZ_BOOK_STATUS     status;
   ENUM_MSZZ_DIRECTION       direction;
   bool                      position_open;
   ulong                     broker_position_ticket;
   ulong                     broker_order_ticket;
   string                    logical_position_id;
   string                    entry_signal_id;
   string                    origin_id;
   datetime                  entry_time;
   double                    entry_price;
   double                    stop_price;
   double                    target_price;
   double                    initial_risk_price;
   double                    current_r_multiple;
   double                    logical_volume;
   double                    requested_risk_pct;
   double                    allocated_risk_pct;
   MSZZBookExitConfig        exit_config;
   bool                      partial_close_done;
   datetime                  last_update_time;
   bool                      valid;
   string                    status_reason;
   // D028 Stage 5: per-book exit-management bookkeeping (SR1-SR5). Reset on
   // every ResetPositionFields() call, i.e. every new entry, and reseeded
   // safely on restart (effective_stop always initialized from the current
   // broker-side stop, never a remembered value -- see BookExitManager.mqh
   // and DECISION_LOG.md D028 Stage 5 "restart persistence"). Not itself
   // durably persisted -- an explicit, documented research-scope limitation
   // matching this project's established precedent (D026 g_trail_states).
   double                    max_favorable_r;
   bool                      breakeven_activated;
   bool                      structure_activated;
   double                    highest_since_activation;
   double                    lowest_since_activation;
   double                    effective_stop;
   bool                      time_stop_evaluated_done;
};

class CMSZZStrategyBook
{
private:
   MSZZStrategyBookState m_state;

   void ResetPositionFields()
   {
      m_state.direction=MSZZ_DIR_NONE;
      m_state.position_open=false;
      m_state.broker_position_ticket=0;
      m_state.broker_order_ticket=0;
      m_state.logical_position_id="";
      m_state.entry_signal_id="";
      m_state.origin_id="";
      m_state.entry_time=0;
      m_state.entry_price=0.0;
      m_state.stop_price=0.0;
      m_state.target_price=0.0;
      m_state.initial_risk_price=0.0;
      m_state.current_r_multiple=0.0;
      m_state.logical_volume=0.0;
      m_state.requested_risk_pct=0.0;
      m_state.allocated_risk_pct=0.0;
      m_state.partial_close_done=false;
      m_state.max_favorable_r=0.0;
      m_state.breakeven_activated=false;
      m_state.structure_activated=false;
      m_state.highest_since_activation=0.0;
      m_state.lowest_since_activation=0.0;
      m_state.effective_stop=0.0;
      m_state.time_stop_evaluated_done=false;
   }

public:
   CMSZZStrategyBook(void)
   {
      ZeroMemory(m_state);
      m_state.status=MSZZ_BOOK_DISABLED;
   }

   bool Configure(const long book_id,const ENUM_MSZZ_STRATEGY_ID strategy_id,
                  const ENUM_MSZZ_STRATEGY_FAMILY family_id,const long magic,
                  const bool enabled,const MSZZBookExitConfig &exit_config,
                  string &reason)
   {
      reason="";
      ZeroMemory(m_state);
      if(book_id<=0) { reason="book_id must be positive"; return false; }
      if(strategy_id==MSZZ_STRAT_NONE) { reason="strategy_id is required"; return false; }
      if(family_id==MSZZ_FAMILY_NONE) { reason="family_id is required"; return false; }
      if(magic<=0) { reason="book magic must be positive"; return false; }
      if(exit_config.target_r<=0.0) { reason="book target_r must be positive"; return false; }
      if(exit_config.partial_close_fraction<0.0 || exit_config.partial_close_fraction>1.0)
      { reason="partial close fraction outside [0,1]"; return false; }
      m_state.book_id=book_id;
      m_state.strategy_id=strategy_id;
      m_state.family_id=family_id;
      m_state.magic=magic;
      m_state.enabled=enabled;
      m_state.exit_config=exit_config;
      m_state.status=(enabled ? MSZZ_BOOK_FLAT : MSZZ_BOOK_DISABLED);
      m_state.valid=true;
      m_state.status_reason=(enabled ? "configured flat" : "configured disabled");
      return true;
   }

   MSZZStrategyBookState State() const { return m_state; }
   bool OwnsMagic(const long magic) const { return m_state.valid && magic==m_state.magic; }
   bool OwnsTicket(const ulong ticket) const
   {
      return m_state.valid && ticket>0 &&
             (ticket==m_state.broker_position_ticket || ticket==m_state.broker_order_ticket);
   }

   bool MarkEntryPending(const MSZZCandidate &candidate,const double volume,
                         const double requested_risk_pct,string &reason)
   {
      reason="";
      if(!m_state.valid || !m_state.enabled) { reason="book disabled or invalid"; return false; }
      if(m_state.status!=MSZZ_BOOK_FLAT) { reason="book is not flat"; return false; }
      if(!candidate.valid || candidate.strategy_id!=m_state.strategy_id ||
         candidate.family_id!=m_state.family_id)
      { reason="candidate identity does not match book"; return false; }
      if(candidate.direction!=MSZZ_DIR_LONG && candidate.direction!=MSZZ_DIR_SHORT)
      { reason="candidate direction invalid"; return false; }
      if(candidate.event_id=="" || candidate.origin_id=="" ||
         candidate.entry<=0.0 || candidate.stop<=0.0 ||
         MathAbs(candidate.entry-candidate.stop)<=0.0)
      { reason="candidate execution identity invalid"; return false; }
      if(volume<=0.0 || requested_risk_pct<0.0)
      { reason="invalid logical volume or risk"; return false; }
      ResetPositionFields();
      m_state.status=MSZZ_BOOK_ENTRY_PENDING;
      m_state.direction=candidate.direction;
      m_state.entry_signal_id=candidate.event_id;
      m_state.origin_id=candidate.origin_id;
      m_state.logical_position_id=StringFormat("MSZZB1|%I64d|%s",
                                               m_state.book_id,candidate.event_id);
      m_state.stop_price=candidate.stop;
      m_state.target_price=candidate.target;
      m_state.logical_volume=volume;
      m_state.requested_risk_pct=requested_risk_pct;
      m_state.last_update_time=TimeCurrent();
      m_state.status_reason="entry pending";
      return true;
   }

   bool MarkOpen(const string logical_position_id,const ulong position_ticket,
                 const ulong order_ticket,const datetime entry_time,const double entry_price,
                 const double stop_price,const double target_price,
                 const double allocated_risk_pct,string &reason)
   {
      reason="";
      if(m_state.status!=MSZZ_BOOK_ENTRY_PENDING) { reason="entry is not pending"; return false; }
      if(logical_position_id=="" || entry_time<=0 || entry_price<=0.0 ||
         stop_price<=0.0 || allocated_risk_pct<0.0)
      { reason="invalid open-position identity or prices"; return false; }
      double initial_risk_price=MathAbs(entry_price-stop_price);
      if(initial_risk_price<=0.0)
      { reason="entry and stop do not define positive risk"; return false; }
      m_state.logical_position_id=logical_position_id;
      m_state.broker_position_ticket=position_ticket;
      m_state.broker_order_ticket=order_ticket;
      m_state.entry_time=entry_time;
      m_state.entry_price=entry_price;
      m_state.stop_price=stop_price;
      m_state.target_price=target_price;
      m_state.initial_risk_price=initial_risk_price;
      m_state.allocated_risk_pct=allocated_risk_pct;
      m_state.position_open=true;
      m_state.status=MSZZ_BOOK_OPEN;
      m_state.last_update_time=TimeCurrent();
      m_state.status_reason="position open";
      // D028 Stage 5: effective_stop always starts as the just-opened
      // position's real stop -- the same value MarkOpen() itself just
      // validated, so it is never a stale/remembered figure.
      m_state.effective_stop=stop_price;
      return true;
   }

   // D028 Stage 5: applies one exit-management decision computed by
   // CMSZZBookExitManager. The caller (EA) is responsible for actually
   // calling PositionModify/PositionClosePartial against the broker first
   // -- this only updates in-memory bookkeeping once that call is known to
   // have succeeded, so a failed broker call never desyncs book state from
   // broker truth.
   bool UpdateExitManagementState(const double max_favorable_r,
                                  const bool breakeven_activated,
                                  const bool structure_activated,
                                  const double highest_since_activation,
                                  const double lowest_since_activation,
                                  const double effective_stop,
                                  const bool partial_close_done,
                                  const bool time_stop_evaluated_done)
   {
      if(!m_state.valid || m_state.status!=MSZZ_BOOK_OPEN) return false;
      m_state.max_favorable_r=max_favorable_r;
      m_state.breakeven_activated=breakeven_activated;
      m_state.structure_activated=structure_activated;
      m_state.highest_since_activation=highest_since_activation;
      m_state.lowest_since_activation=lowest_since_activation;
      m_state.effective_stop=effective_stop;
      m_state.partial_close_done=partial_close_done;
      m_state.time_stop_evaluated_done=time_stop_evaluated_done;
      m_state.last_update_time=TimeCurrent();
      return true;
   }

   // D028 Stage 5 restart-safety: if in-memory bookkeeping was lost (e.g.
   // EA restart mid-position) but the position is genuinely still open,
   // reseed effective_stop from the CURRENT broker-side stop -- never a
   // remembered value -- so ResolveTightening()'s monotonic-only guard can
   // never regress an already-trailed stop. See DECISION_LOG.md D028
   // Stage 5, mirrors D026's identical restart-safety design.
   bool ReseedEffectiveStopIfMissing(const double current_broker_stop)
   {
      if(!m_state.valid || m_state.status!=MSZZ_BOOK_OPEN) return false;
      if(m_state.effective_stop>0.0) return false; // already seeded, nothing to do
      m_state.effective_stop=current_broker_stop;
      return true;
   }

   bool AssignPendingLogicalPositionId(const string logical_position_id,
                                       string &reason)
   {
      reason="";
      if(m_state.status!=MSZZ_BOOK_ENTRY_PENDING || logical_position_id=="")
      { reason="logical ID assignment requires pending book and nonempty ID"; return false; }
      m_state.logical_position_id=logical_position_id;
      m_state.last_update_time=TimeCurrent();
      return true;
   }

   bool MarkFlat(const string reason)
   {
      if(!m_state.valid) return false;
      ResetPositionFields();
      m_state.status=(m_state.enabled ? MSZZ_BOOK_FLAT : MSZZ_BOOK_DISABLED);
      m_state.last_update_time=TimeCurrent();
      m_state.status_reason=reason;
      return true;
   }
};

#endif
