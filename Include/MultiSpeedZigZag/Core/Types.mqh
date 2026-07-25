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
   MSZZ_STRAT_SEQUENTIAL_CONFIRMATION = 1020,
   MSZZ_STRAT_NESTED_PULLBACK = 1030,
   MSZZ_STRAT_BREAKOUT_RETEST = 1040,
   MSZZ_STRAT_SWEEP_RECLAIM = 1050,
   MSZZ_STRAT_COMPRESSION_BREAKOUT = 1060,
   MSZZ_STRAT_STRUCTURE_TRANSITION = 1070,
   MSZZ_STRAT_WEIGHTED_ENSEMBLE = 1080
};

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