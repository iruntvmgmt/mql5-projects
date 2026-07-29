#ifndef __MSZZ_CROSS_FAMILY_POLICY_MQH__
#define __MSZZ_CROSS_FAMILY_POLICY_MQH__

#include <MultiSpeedZigZag/Core/Types.mqh>

enum ENUM_MSZZ_CROSS_FAMILY_POLICY
{
   MSZZ_CROSS_FAMILY_LEGACY_SHARED_REVERSE = 0,
   MSZZ_CROSS_FAMILY_IGNORE = 1,
   MSZZ_CROSS_FAMILY_FLATTEN_ONLY = 2,
   MSZZ_CROSS_FAMILY_REGIME_EXCLUSIVE = 3,
   MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS = 4
};

enum ENUM_MSZZ_CROSS_FAMILY_ACTION
{
   MSZZ_CROSS_ACTION_NONE = 0,
   MSZZ_CROSS_ACTION_IGNORE,
   MSZZ_CROSS_ACTION_FLATTEN,
   MSZZ_CROSS_ACTION_REVERSE,
   MSZZ_CROSS_ACTION_REJECT_REGIME
};

class CMSZZCrossFamilyPolicy
{
public:
   static bool IsKnown(const ENUM_MSZZ_CROSS_FAMILY_POLICY policy)
   {
      return policy>=MSZZ_CROSS_FAMILY_LEGACY_SHARED_REVERSE &&
             policy<=MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS;
   }

   static string Text(const ENUM_MSZZ_CROSS_FAMILY_POLICY policy)
   {
      switch(policy)
      {
         case MSZZ_CROSS_FAMILY_LEGACY_SHARED_REVERSE: return "LEGACY_SHARED_REVERSE";
         case MSZZ_CROSS_FAMILY_IGNORE: return "IGNORE";
         case MSZZ_CROSS_FAMILY_FLATTEN_ONLY: return "FLATTEN_ONLY";
         case MSZZ_CROSS_FAMILY_REGIME_EXCLUSIVE: return "REGIME_EXCLUSIVE";
         case MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS: return "INDEPENDENT_BOOKS";
         default: return "UNKNOWN";
      }
   }

   static ENUM_MSZZ_CROSS_FAMILY_ACTION Resolve(
      const ENUM_MSZZ_CROSS_FAMILY_POLICY policy,
      const ENUM_MSZZ_STRATEGY_FAMILY owner_family,
      const ENUM_MSZZ_STRATEGY_FAMILY signal_family,
      const bool explicit_invalidation,
      const bool regime_eligible)
   {
      if(owner_family==signal_family) return MSZZ_CROSS_ACTION_REVERSE;
      switch(policy)
      {
         case MSZZ_CROSS_FAMILY_LEGACY_SHARED_REVERSE:
            return MSZZ_CROSS_ACTION_REVERSE;
         case MSZZ_CROSS_FAMILY_IGNORE:
         case MSZZ_CROSS_FAMILY_INDEPENDENT_BOOKS:
            return MSZZ_CROSS_ACTION_IGNORE;
         case MSZZ_CROSS_FAMILY_FLATTEN_ONLY:
            return explicit_invalidation ? MSZZ_CROSS_ACTION_FLATTEN : MSZZ_CROSS_ACTION_IGNORE;
         case MSZZ_CROSS_FAMILY_REGIME_EXCLUSIVE:
            return regime_eligible ? MSZZ_CROSS_ACTION_IGNORE : MSZZ_CROSS_ACTION_REJECT_REGIME;
         default:
            return MSZZ_CROSS_ACTION_NONE;
      }
   }
};

#endif
