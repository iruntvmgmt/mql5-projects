@echo off
setlocal enabledelayedexpansion
set OUT=C:\Program Files\MetaTrader 5\MQL5\Profiles\Tester\MS-ZZ-BO-V2
set TR_FROM=2024.07.01
set TR_TO=2025.06.30
set HO_FROM=2025.07.01
set HO_TO=2026.06.30

:: helper to write an ini
:: %1=filename %2=from %3=to %4=window_label %5..N=custom_replacement
goto :gen_all

:write_ini
set FN=%OUT%\%1
set FROM=%2
set TO=%3
set LABEL=%4
(
echo ;MS-ZZ-BO-V2_EA ^| XAUUSD M5 ^| %LABEL%
echo [Tester]
echo Expert=MS-ZZ-BO-V2\MS-ZZ-BO-V2_EA.ex5
echo Symbol=XAUUSD
echo Period=M5
echo Optimization=0
echo Model=4
echo FromDate=%FROM%
echo ToDate=%TO%
echo ForwardMode=0
echo Deposit=10000
echo Currency=USD
echo ProfitInPips=0
echo Leverage=500
echo ExecutionMode=0
echo OptimizationCriterion=0
echo Visual=0
echo [TesterInputs]
echo ; 1. Safety
echo InpEnableTrading=true^^|^^|false^^|^^|0^^|^^|true^^|^^|N
echo InpMagicNumber=260715^^|^^|260715^^|^^|1^^|^^|2607150^^|^^|N
echo InpTradeSymbol=XAUUSD
) > "%FN%"
shift
shift
shift
shift
:: remaining args are key=value lines to append
:append_loop
if "%1"=="" goto :eof
echo %1 >> "%FN%"
shift
goto :append_loop

:gen_all
echo Generating ini files...

:: 00_Baseline
call :write_ini 00_Baseline.train.ini %TR_FROM% %TR_TO% "TRAIN %TR_FROM%-%TR_TO%" ^
 "InpSignalTF=5||0||0||49153||N" ^
 "; 2. Indicator" ^
 "InpIndicatorPath=Tradingview_Indicators\MULTI_SPEED_ZIGZAG\MS-ZZ-BO-V2" ^
 "InpSignalMode=0||0||0||2||N" ^
 "InpMinBarsBetweenTrades=3||3||1||30||N" ^
 "; 3. Session & Spread" ^
 "InpUseSessionFilter=true||false||0||true||N" ^
 "InpSessionStart=07:00" ^
 "InpSessionEnd=17:00" ^
 "InpUseSpreadFilter=true||false||0||true||N" ^
 "InpMaxSpreadPoints=80.0||80.0||8.000000||800.000000||N" ^
 "; 4. Risk" ^
 "InpATRPeriod=14||14||1||140||N" ^
 "InpATRMultSL=2.0||2.0||0.200000||20.000000||N" ^
 "InpTargetR=2.0||2.0||0.200000||20.000000||N" ^
 "InpUseBreakeven=true||false||0||true||N" ^
 "InpBEActivationR=1.0||1.0||0.100000||10.000000||N" ^
 "InpUseTrailingStop=true||false||0||true||N" ^
 "InpTrailActivationR=1.25||1.25||0.125000||12.500000||N" ^
 "InpTrailDistanceATR=1.0||1.0||0.100000||10.000000||N" ^
 "InpRiskPct=1.0||1.0||0.100000||10.000000||N" ^
 "InpMaxLots=1.0||1.0||0.100000||10.000000||N" ^
 "InpMinLots=0.01||0.01||0.001000||0.100000||N" ^
 "; 5. Misc" ^
 "InpVerboseLogging=false||false||0||true||N"

call :write_ini 00_Baseline.holdout.ini %HO_FROM% %HO_TO% "HOLDOUT %HO_FROM%-%HO_TO%" ^
 "InpSignalTF=5||0||0||49153||N" ^
 "; 2. Indicator" ^
 "InpIndicatorPath=Tradingview_Indicators\MULTI_SPEED_ZIGZAG\MS-ZZ-BO-V2" ^
 "InpSignalMode=0||0||0||2||N" ^
 "InpMinBarsBetweenTrades=3||3||1||30||N" ^
 "; 3. Session & Spread" ^
 "InpUseSessionFilter=true||false||0||true||N" ^
 "InpSessionStart=07:00" ^
 "InpSessionEnd=17:00" ^
 "InpUseSpreadFilter=true||false||0||true||N" ^
 "InpMaxSpreadPoints=80.0||80.0||8.000000||800.000000||N" ^
 "; 4. Risk" ^
 "InpATRPeriod=14||14||1||140||N" ^
 "InpATRMultSL=2.0||2.0||0.200000||20.000000||N" ^
 "InpTargetR=2.0||2.0||0.200000||20.000000||N" ^
 "InpUseBreakeven=true||false||0||true||N" ^
 "InpBEActivationR=1.0||1.0||0.100000||10.000000||N" ^
 "InpUseTrailingStop=true||false||0||true||N" ^
 "InpTrailActivationR=1.25||1.25||0.125000||12.500000||N" ^
 "InpTrailDistanceATR=1.0||1.0||0.100000||10.000000||N" ^
 "InpRiskPct=1.0||1.0||0.100000||10.000000||N" ^
 "InpMaxLots=1.0||1.0||0.100000||10.000000||N" ^
 "InpMinLots=0.01||0.01||0.001000||0.100000||N" ^
 "; 5. Misc" ^
 "InpVerboseLogging=false||false||0||true||N"

echo Done base.
echo ALL DONE
