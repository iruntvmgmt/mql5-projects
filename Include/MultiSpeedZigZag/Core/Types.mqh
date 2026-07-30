#ifndef __MSZZ_TYPES_MQH__
#define __MSZZ_TYPES_MQH__

enum ENUM_MSZZ_SPEED
{
   MSZZ_SPEED_FAST = 0,
   MSZZ_SPEED_MEDIUM = 1,
   MSZZ_SPEED_SLOW = 2
};

enum ENUM_MSZZ_DIRECTION
{
   MSZZ_DIR_NONE = 0,
   MSZZ_DIR_LONG = 1,
   MSZZ_DIR_SHORT = -1
};

enum ENUM_MSZZ_PIVOT_KIND
{
   MSZZ_PIVOT_NONE = 0,
   MSZZ_PIVOT_HIGH = 1,
   MSZZ_PIVOT_LOW = -1
};

enum ENUM_MSZZ_STRUCTURE_LABEL
{
   MSZZ_STRUCT_UNKNOWN = 0,
   MSZZ_STRUCT_HH,
   MSZZ_STRUCT_HL,
   MSZZ_STRUCT_LH,
   MSZZ_STRUCT_LL
};

enum ENUM_MSZZ_STRATEGY_ID
{
   MSZZ_STRAT_NONE = 0,
   MSZZ_STRAT_FAST_BREAKOUT = 1001,
   MSZZ_STRAT_MEDIUM_BREAKOUT = 1002,
   MSZZ_STRAT_SLOW_BREAKOUT = 1003,
   MSZZ_STRAT_FAST_MEDIUM_CONFLUENCE = 1010,
   MSZZ_STRAT_FAST_WITH_MEDIUM_CONTEXT = 1011,
   MSZZ_STRAT_MEDIUM_WITH_SLOW_CONTEXT = 1012,
   MSZZ_STRAT_SEQUENTIAL_CONFIRMATION = 1020, // reserved since original architecture; a distinct future hypothesis ("fast break followed by medium within a window"), NOT D027's S1 -- see DECISION_LOG.md D027
   MSZZ_STRAT_NESTED_PULLBACK = 1030,
   MSZZ_STRAT_ALIGNED_FAST_PULLBACK = 1031, // D027 S1 -- new ID, does not collide with the reserved 1020 slot above
   MSZZ_STRAT_BREAKOUT_RETEST = 1040,       // D027 S2 -- reserved since original architecture, matches STRATEGY_CATALOG.md exactly
   MSZZ_STRAT_SWEEP_RECLAIM = 1050,         // D027 S3
   MSZZ_STRAT_COMPRESSION_BREAKOUT = 1060,  // D027 S4
   MSZZ_STRAT_STRUCTURE_TRANSITION = 1070,  // D027 S5
   MSZZ_STRAT_WEIGHTED_ENSEMBLE = 1080,
   // D033: production execution port of the D031/D032 Session Sweep
   // Reversal shadow family -- the only one of six to pass every D032
   // mandatory gate. 1090 was the D030 handoff's original *suggested* ID
   // for a different, never-implemented hypothesis ("Compression
   // Breakout" Family 4); D031 explicitly declined it for that purpose
   // (see STRATEGY_CATALOG.md's D031 addendum) and it remains otherwise
   // unassigned, so it is reused here for SSR instead -- see
   // Tools/D033/id_allocation.csv. Deliberately NOT 1200: that ID belongs
   // to the disjoint, non-executing research namespace
   // (Research/Families/ResearchCandidateTypes.mqh) and must never be
   // confused with this production strategy.
   MSZZ_STRAT_SESSION_SWEEP_REVERSAL = 1090
};

// D027 Layer 2: explicit strategy-family identity, separate from
// strategy_id and never inferred later from a setup name. See
// DECISION_LOG.md D027 and Docs/MultiSpeedZigZag/STRATEGY_CATALOG.md for
// the full existing-eight and new-five family assignments.
enum ENUM_MSZZ_STRATEGY_FAMILY
{
   MSZZ_FAMILY_NONE = 0,
   MSZZ_FAMILY_BREAKOUT = 1,
   MSZZ_FAMILY_PULLBACK = 2,
   MSZZ_FAMILY_RETEST = 3,
   MSZZ_FAMILY_REVERSAL = 4,
   MSZZ_FAMILY_COMPRESSION = 5,
   MSZZ_FAMILY_RANGE = 6,
   MSZZ_FAMILY_ENSEMBLE = 7
};

string MSZZFamilyText(const ENUM_MSZZ_STRATEGY_FAMILY f)
{
   switch(f)
   {
      case MSZZ_FAMILY_BREAKOUT:   return "BREAKOUT";
      case MSZZ_FAMILY_PULLBACK:   return "PULLBACK";
      case MSZZ_FAMILY_RETEST:     return "RETEST";
      case MSZZ_FAMILY_REVERSAL:   return "REVERSAL";
      case MSZZ_FAMILY_COMPRESSION:return "COMPRESSION";
      case MSZZ_FAMILY_RANGE:      return "RANGE";
      case MSZZ_FAMILY_ENSEMBLE:   return "ENSEMBLE";
      default:                     return "NONE";
   }
}

enum ENUM_MSZZ_ORIGIN_TYPE
{
   MSZZ_ORIGIN_UNKNOWN = 0,
   MSZZ_ORIGIN_FAST_BREAK,
   MSZZ_ORIGIN_MEDIUM_BREAK,
   MSZZ_ORIGIN_SLOW_BREAK,
   MSZZ_ORIGIN_PIVOT_SWEEP,
   MSZZ_ORIGIN_STRUCTURE_TRANSITION,
   MSZZ_ORIGIN_COMPRESSION_RELEASE
};

enum ENUM_MSZZ_CLUSTER_STATE
{
   MSZZ_CLUSTER_OPEN = 0,
   MSZZ_CLUSTER_STRENGTHENED,
   MSZZ_CLUSTER_SELECTED,
   MSZZ_CLUSTER_EXECUTED,
   MSZZ_CLUSTER_MANAGED,
   MSZZ_CLUSTER_CLOSED,
   MSZZ_CLUSTER_EXPIRED,
   MSZZ_CLUSTER_INVALIDATED,
   MSZZ_CLUSTER_CANCELLED_CONFLICT
};

// D029: position-sizing mode. Default MSZZ_SIZE_FIXED_LOT keeps every
// existing certified run's behavior byte-identical -- percentage-equity
// sizing only activates when a config explicitly sets InpSizingMode=1.
// See DECISION_LOG.md D029 Phase 1.
enum ENUM_MSZZ_POSITION_SIZING_MODE
{
   MSZZ_SIZE_FIXED_LOT      = 0,
   MSZZ_SIZE_PERCENT_EQUITY = 1
};

enum ENUM_MSZZ_EVIDENCE_MASK
{
   MSZZ_EVIDENCE_NONE       = 0,
   MSZZ_EVIDENCE_TRIGGER    = 1,
   MSZZ_EVIDENCE_CONTEXT    = 2,
   MSZZ_EVIDENCE_STRUCTURE  = 4,
   MSZZ_EVIDENCE_QUALITY    = 8,
   MSZZ_EVIDENCE_RETEST     = 16
};

struct MSZZPivot
{
   bool                      valid;
   ENUM_MSZZ_SPEED           speed;
   ENUM_MSZZ_PIVOT_KIND      kind;
   ENUM_MSZZ_STRUCTURE_LABEL structure_label;
   datetime                  pivot_time;
   datetime                  confirmed_time;
   int                       pivot_shift;
   double                    price;
   string                    id;
};

struct MSZZSpeedSnapshot
{
   ENUM_MSZZ_SPEED      speed;
   ENUM_MSZZ_DIRECTION leg_direction;
   double               atr;
   double               reversal_threshold;
   double               current_extreme;
   datetime             current_extreme_time;
   MSZZPivot            last_high;
   MSZZPivot            prior_high;
   MSZZPivot            last_low;
   MSZZPivot            prior_low;
   bool                 new_pivot;
   bool                 bullish_break;
   bool                 bearish_break;
   double               resistance_now;
   double               support_now;
   string               bullish_event_id;
   string               bearish_event_id;
};

struct MSZZCandidate
{
   bool                    valid;
   ENUM_MSZZ_STRATEGY_ID   strategy_id;
   ENUM_MSZZ_STRATEGY_FAMILY family_id;
   ENUM_MSZZ_DIRECTION     direction;
   ENUM_MSZZ_ORIGIN_TYPE   origin_type;
   datetime                signal_time;
   datetime                expiry_time;
   double                  entry;
   double                  stop;
   double                  target;
   double                  score;
   int                     supporting_models;
   int                     evidence_mask;
   string                  setup_name;
   string                  origin_id;
   string                  event_id;
   string                  reason;
};

struct MSZZOpportunityCluster
{
   bool                    valid;
   string                  cluster_id;
   string                  origin_id;
   ENUM_MSZZ_ORIGIN_TYPE   origin_type;
   ENUM_MSZZ_DIRECTION     direction;
   ENUM_MSZZ_CLUSTER_STATE state;
   datetime                origin_time;
   datetime                latest_time;
   datetime                expiry_time;
   double                  canonical_stop;
   double                  combined_score;
   double                  stop_disagreement;
   int                     support_count;
   int                     evidence_mask;
   int                     preferred_index;
   ENUM_MSZZ_STRATEGY_ID   owner_strategy_id;
   string                  supporting_strategy_ids;
   string                  supporting_family_ids;
};

string MSZZDirectionText(const ENUM_MSZZ_DIRECTION dir)
{
   if(dir == MSZZ_DIR_LONG) return "LONG";
   if(dir == MSZZ_DIR_SHORT) return "SHORT";
   return "NONE";
}

string MSZZStructureText(const ENUM_MSZZ_STRUCTURE_LABEL label)
{
   switch(label)
   {
      case MSZZ_STRUCT_HH: return "HH";
      case MSZZ_STRUCT_HL: return "HL";
      case MSZZ_STRUCT_LH: return "LH";
      case MSZZ_STRUCT_LL: return "LL";
      default: return "UNKNOWN";
   }
}

#endif
