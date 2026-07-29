#property script_show_inputs

// D029 Phase 0: one-shot read-only probe of the exact symbol volume/tick
// metadata needed for the percentage-equity sizing formula. No trading
// action of any kind -- SymbolInfo* calls only. See
// DECISION_LOG.md D029 Phase 0 and Docs/MultiSpeedZigZag/D029_PERCENT_RISK_PARTIALS.md.

void OnStart()
{
   string sym=_Symbol;
   double vol_min=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double vol_max=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double vol_step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   double contract_size=SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   double point=SymbolInfoDouble(sym,SYMBOL_POINT);
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   string currency_profit=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);
   string currency_base=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
   string account_currency=AccountInfoString(ACCOUNT_CURRENCY);
   double account_balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double account_equity=AccountInfoDouble(ACCOUNT_EQUITY);
   long account_login=AccountInfoInteger(ACCOUNT_LOGIN);
   string account_server=AccountInfoString(ACCOUNT_SERVER);
   long trade_mode=AccountInfoInteger(ACCOUNT_TRADE_MODE);

   int h=FileOpen("D029_SymbolMetadata.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,';');
   if(h==INVALID_HANDLE) h=FileOpen("D029_SymbolMetadata.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(h!=INVALID_HANDLE)
   {
      FileWrite(h,"field","value");
      FileWrite(h,"symbol",sym);
      FileWrite(h,"volume_min",DoubleToString(vol_min,5));
      FileWrite(h,"volume_max",DoubleToString(vol_max,5));
      FileWrite(h,"volume_step",DoubleToString(vol_step,5));
      FileWrite(h,"tick_size",DoubleToString(tick_size,8));
      FileWrite(h,"tick_value",DoubleToString(tick_value,8));
      FileWrite(h,"contract_size",DoubleToString(contract_size,2));
      FileWrite(h,"point",DoubleToString(point,8));
      FileWrite(h,"digits",IntegerToString(digits));
      FileWrite(h,"currency_profit",currency_profit);
      FileWrite(h,"currency_base",currency_base);
      FileWrite(h,"account_currency",account_currency);
      FileWrite(h,"account_balance",DoubleToString(account_balance,2));
      FileWrite(h,"account_equity",DoubleToString(account_equity,2));
      FileWrite(h,"account_login",IntegerToString((int)account_login));
      FileWrite(h,"account_server",account_server);
      FileWrite(h,"account_trade_mode",IntegerToString((int)trade_mode));
      FileClose(h);
   }
   PrintFormat("D029 SymbolMetadataProbe: min=%.5f step=%.5f tick_size=%.8f tick_value=%.8f contract=%.2f digits=%d currency=%s login=%d mode=%d",
               vol_min,vol_step,tick_size,tick_value,contract_size,digits,account_currency,(int)account_login,(int)trade_mode);
}
