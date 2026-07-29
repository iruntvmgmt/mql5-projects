#property script_show_inputs

// D029 audit remediation, Finding E: one-shot read-only probe comparing the
// OLD generic (stop_distance/tick_size)*tick_value formula against the NEW
// broker-authoritative OrderCalcProfit() loss-per-lot for the account's
// actual live symbol -- confirms whether Finding E's fix changes any
// volume for XAUUSD specifically (a materially different result would
// require a rerun of every percent-equity config; see
// D029_AUDIT_REMEDIATION.md). No trading action -- OrderCalcProfit() is a
// pure calculation call, not an order.

void OnStart()
{
   string sym=_Symbol;
   double tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   MqlTick tick;
   if(!SymbolInfoTick(sym,tick))
   {
      Print("FindingE probe: SymbolInfoTick failed, aborting.");
      return;
   }

   double entry_long=tick.ask;
   double stop_long=entry_long-10.0;
   double entry_short=tick.bid;
   double stop_short=entry_short+10.0;

   double formula_loss_long=(MathAbs(entry_long-stop_long)/tick_size)*tick_value;
   double profit_long=0.0;
   bool ok_long=OrderCalcProfit(ORDER_TYPE_BUY,sym,1.0,entry_long,stop_long,profit_long);
   double broker_loss_long=-profit_long;

   double formula_loss_short=(MathAbs(entry_short-stop_short)/tick_size)*tick_value;
   double profit_short=0.0;
   bool ok_short=OrderCalcProfit(ORDER_TYPE_SELL,sym,1.0,entry_short,stop_short,profit_short);
   double broker_loss_short=-profit_short;

   PrintFormat("FindingE probe symbol=%s tick_size=%.8f tick_value=%.8f",sym,tick_size,tick_value);
   PrintFormat("FindingE probe LONG: entry=%.5f stop=%.5f formula_loss=%.6f OrderCalcProfit_ok=%s broker_loss=%.6f abs_diff=%.8f",
               entry_long,stop_long,formula_loss_long,(ok_long?"true":"false"),broker_loss_long,
               MathAbs(formula_loss_long-broker_loss_long));
   PrintFormat("FindingE probe SHORT: entry=%.5f stop=%.5f formula_loss=%.6f OrderCalcProfit_ok=%s broker_loss=%.6f abs_diff=%.8f",
               entry_short,stop_short,formula_loss_short,(ok_short?"true":"false"),broker_loss_short,
               MathAbs(formula_loss_short-broker_loss_short));
}
