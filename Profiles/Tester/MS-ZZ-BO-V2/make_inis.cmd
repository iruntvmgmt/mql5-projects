@echo off
setlocal EnableDelayedExpansion
set O=C:\Program Files\MetaTrader 5\MQL5\Profiles\Tester\MS-ZZ-BO-V2
set TRF=2024.07.01
set TRT=2025.06.30
set HOF=2025.07.01
set HOT=2026.06.30

if not exist "%O%" mkdir "%O%"

:: Write function using a temp approach: write lines with echo
:: We use a helper approach - each call writes a complete ini

:: --- 00_Baseline ---
call :make 00_Baseline.train %TRF% %TRT% "BASELINE TRAIN" ^
  "InpSignalTF=5||0||0||49153||N" ^
  "InpIndicatorPath=Tradingview_Indicators\\MULTI_SPEED_ZIGZAG\\MS-ZZ-BO-V2" ^
  "InpSignalMode=0||0||0||2||N" ^
  "InpMinBarsBetweenTrades=3||3||1||30||N" ^
  "InpUseSessionFilter=true||false||0||true||N" ^
  "InpSessionStart=07:00" "InpSessionEnd=17:00" ^
  "InpUseSpreadFilter=true||false||0||true||N" ^
  "InpMaxSpreadPoints=80.0||80.0||8.000000||800.000000||N" ^
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
  "InpVerboseLogging=false||false||0||true||N"

call :make 00_Baseline.holdout %HOF% %HOT% "BASELINE HOLDOUT" ^
  "InpSignalTF=5||0||0||49153||N" ^
  "InpIndicatorPath=Tradingview_Indicators\\MULTI_SPEED_ZIGZAG\\MS-ZZ-BO-V2" ^
  "InpSignalMode=0||0||0||2||N" ^
  "InpMinBarsBetweenTrades=3||3||1||30||N" ^
  "InpUseSessionFilter=true||false||0||true||N" ^
  "InpSessionStart=07:00" "InpSessionEnd=17:00" ^
  "InpUseSpreadFilter=true||false||0||true||N" ^
  "InpMaxSpreadPoints=80.0||80.0||8.000000||800.000000||N" ^
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
  "InpVerboseLogging=false||false||0||true||N"

echo Done baseline
goto :eof

:make
:: %1=name %2=from %3=to %4=label %5+=InputLines
set FN=%O%\%1.ini
set FR=%2
set TO=%3
set LB=%4
shift
shift
shift
shift

> "%FN%" echo ;MS-ZZ-BO-V2_EA ^| XAUUSD M5 ^| %LB%
>>"%FN%" echo [Tester]
>>"%FN%" echo Expert=MS-ZZ-BO-V2\MS-ZZ-BO-V2_EA.ex5
>>"%FN%" echo Symbol=XAUUSD
>>"%FN%" echo Period=M5
>>"%FN%" echo Optimization=0
>>"%FN%" echo Model=4
>>"%FN%" echo FromDate=%FR%
>>"%FN%" echo ToDate=%TO%
>>"%FN%" echo ForwardMode=0
>>"%FN%" echo Deposit=10000
>>"%FN%" echo Currency=USD
>>"%FN%" echo ProfitInPips=0
>>"%FN%" echo Leverage=500
>>"%FN%" echo ExecutionMode=0
>>"%FN%" echo OptimizationCriterion=0
>>"%FN%" echo Visual=0
>>"%FN%" echo [TesterInputs]
>>"%FN%" echo ; 1. Safety
>>"%FN%" echo InpEnableTrading=true^|^|false^|^|0^|^|true^|^|N
>>"%FN%" echo InpMagicNumber=260715^|^|260715^|^|1^|^|2607150^|^|N
>>"%FN%" echo InpTradeSymbol=XAUUSD

:make_loop
if "%~1"=="" goto :eof
>>"%FN%" echo %~1
shift
goto :make_loop
