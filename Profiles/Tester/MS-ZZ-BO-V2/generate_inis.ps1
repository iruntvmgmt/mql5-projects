# MS-ZZ-BO-V2 EA — Config generator
# Stage A: Coarse sweep of every parameter family
# Stage B: Refinement of top regions (manual)

$outDir = "C:\Program Files\MetaTrader 5\MQL5\Profiles\Tester\MS-ZZ-BO-V2"

# --- BASE TEMPLATE ---
function New-IniHeader($symbol, $period, $from, $to, $deposit) {
@"
;MS-ZZ-BO-V2_EA | $symbol | $period | $from - $to
[Tester]
Expert=MS-ZZ-BO-V2\MS-ZZ-BO-V2_EA.ex5
Symbol=$symbol
Period=$period
Optimization=0
Model=4
FromDate=$from
ToDate=$to
ForwardMode=0
Deposit=$deposit
Currency=USD
ProfitInPips=0
Leverage=500
ExecutionMode=0
OptimizationCriterion=0
Visual=0
[TesterInputs]
; 1. Safety
InpEnableTrading=true||false||0||true||N
InpMagicNumber=260715||260715||1||2607150||N
InpTradeSymbol=$symbol
"@
}

# --- DEFAULTS ---
$DefaultSignalMode   = "0||0||0||2||N"        # MED_ONLY
$DefaultSignalTF     = "5||0||0||49153||N"      # PERIOD_M5
$DefaultMinBars      = "3||3||1||30||N"
$DefaultSessionFilter= "true||false||0||true||N"
$DefaultSessionStart = "07:00"
$DefaultSessionEnd   = "17:00"
$DefaultSpreadFilter = "true||false||0||true||N"
$DefaultMaxSpread    = "80.0||80.0||8.000000||800.000000||N"
$DefaultATRPeriod    = "14||14||1||140||N"
$DefaultATRMultSL    = "2.0||2.0||0.200000||20.000000||N"
$DefaultTargetR      = "2.0||2.0||0.200000||20.000000||N"
$DefaultBreakeven    = "true||false||0||true||N"
$DefaultBEActivation = "1.0||1.0||0.100000||10.000000||N"
$DefaultTrailing     = "true||false||0||true||N"
$DefaultTrailAct     = "1.25||1.25||0.125000||12.500000||N"
$DefaultTrailDist    = "1.0||1.0||0.100000||10.000000||N"
$DefaultRiskPct      = "1.0||1.0||0.100000||10.000000||N"
$DefaultMaxLots      = "1.0||1.0||0.100000||10.000000||N"
$DefaultMinLots      = "0.01||0.01||0.001000||0.100000||N"
$DefaultVerbose      = "false||false||0||true||N"

function New-Body() {
@"
InpSignalTF=$DefaultSignalTF
; 2. Indicator
InpIndicatorPath=Tradingview_Indicators\MULTI_SPEED_ZIGZAG\MS-ZZ-BO-V2
InpSignalMode=$DefaultSignalMode
InpMinBarsBetweenTrades=$DefaultMinBars
; 3. Session & Spread
InpUseSessionFilter=$DefaultSessionFilter
InpSessionStart=$DefaultSessionStart
InpSessionEnd=$DefaultSessionEnd
InpUseSpreadFilter=$DefaultSpreadFilter
InpMaxSpreadPoints=$DefaultMaxSpread
; 4. Risk
InpATRPeriod=$DefaultATRPeriod
InpATRMultSL=$DefaultATRMultSL
InpTargetR=$DefaultTargetR
InpUseBreakeven=$DefaultBreakeven
InpBEActivationR=$DefaultBEActivation
InpUseTrailingStop=$DefaultTrailing
InpTrailActivationR=$DefaultTrailAct
InpTrailDistanceATR=$DefaultTrailDist
InpRiskPct=$DefaultRiskPct
InpMaxLots=$DefaultMaxLots
InpMinLots=$DefaultMinLots
; 5. Misc
InpVerboseLogging=$DefaultVerbose
"@
}

# --- WINDOWS ---
$trainFrom = "2024.07.01"
$trainTo   = "2025.06.30"
$holdFrom  = "2025.07.01"
$holdTo    = "2026.06.30"
$deposit   = 10000
$symbol    = "XAUUSD"
$period    = "M5"

# ========================
# 00_BASELINE
# ========================
$body = New-Body
$trainPath = Join-Path $outDir "00_Baseline.train.ini"
$holdPath  = Join-Path $outDir "00_Baseline.holdout.ini"
(New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 $trainPath
(New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 $holdPath
Write-Host "00_Baseline done"

# ========================
# 01_SignalMode sweep
# ========================
$modes = @(
    @{n="MED_ONLY";  v="0||0||0||2||N"},
    @{n="FAST_ONLY"; v="1||0||0||2||N"},
    @{n="ANY";       v="2||0||0||2||N"}
)
foreach ($m in $modes) {
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpSignalMode=$DefaultSignalMode"), "InpSignalMode=$($m.v)"
    $tn = "01_SignalMode_$($m.n).train.ini"
    $hn = "01_SignalMode_$($m.n).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "01_SignalMode done"

# ========================
# 02_SignalTF sweep
# ========================
$tfs = @(
    @{n="M1";  v="1||0||0||49153||N"},
    @{n="M5";  v="5||0||0||49153||N"},
    @{n="M15"; v="15||0||0||49153||N"},
    @{n="CURRENT"; v="0||0||0||49153||N"}
)
foreach ($tf in $tfs) {
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpSignalTF=$DefaultSignalTF"), "InpSignalTF=$($tf.v)"
    $tn = "02_SignalTF_$($tf.n).train.ini"
    $hn = "02_SignalTF_$($tf.n).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "02_SignalTF done"

# ========================
# 03_MinBarsBetweenTrades sweep
# ========================
$bars = @(0,1,2,3,5,8)
foreach ($b in $bars) {
    $v = "$b||$b||1||30||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpMinBarsBetweenTrades=$DefaultMinBars"), "InpMinBarsBetweenTrades=$v"
    $tn = "03_MinBars_$($b).train.ini"
    $hn = "03_MinBars_$($b).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "03_MinBars done"

# ========================
# 04_SessionFilter
# ========================
$sfs = @("true||false||0||true||N", "false||false||0||true||N")
$sfn = @("On","Off")
for ($i=0; $i -lt 2; $i++) {
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpUseSessionFilter=$DefaultSessionFilter"), "InpUseSessionFilter=$($sfs[$i])"
    $tn = "04_SessionFilter_$($sfn[$i]).train.ini"
    $hn = "04_SessionFilter_$($sfn[$i]).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "04_SessionFilter done"

# ========================
# 05_SessionTimes
# ========================
$sessions = @(
    @{n="00-23";  s="00:00"; e="23:59"},
    @{n="07-17";  s="07:00"; e="17:00"},
    @{n="08-20";  s="08:00"; e="20:00"},
    @{n="22-05";  s="22:00"; e="05:00"}
)
foreach ($s in $sessions) {
    $body = New-Body
    $body = $body -replace "InpSessionStart=$DefaultSessionStart", "InpSessionStart=$($s.s)"
    $body = $body -replace "InpSessionEnd=$DefaultSessionEnd", "InpSessionEnd=$($s.e)"
    $tn = "05_Session_$($s.n).train.ini"
    $hn = "05_Session_$($s.n).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "05_SessionTimes done"

# ========================
# 06_SpreadFilter
# ========================
for ($i=0; $i -lt 2; $i++) {
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpUseSpreadFilter=$DefaultSpreadFilter"), "InpUseSpreadFilter=$($sfs[$i])"
    $tn = "06_SpreadFilter_$($sfn[$i]).train.ini"
    $hn = "06_SpreadFilter_$($sfn[$i]).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "06_SpreadFilter done"

# ========================
# 07_MaxSpreadPoints sweep
# ========================
$sprVals = @(30,40,60,80,120)
foreach ($v in $sprVals) {
    $sv = "$v.0||$v.0||8.000000||800.000000||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpMaxSpreadPoints=$DefaultMaxSpread"), "InpMaxSpreadPoints=$sv"
    $tn = "07_MaxSpread_$($v).train.ini"
    $hn = "07_MaxSpread_$($v).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "07_MaxSpread done"

# ========================
# 08_ATRPeriod sweep
# ========================
$atrP = @(10,14,20,28)
foreach ($v in $atrP) {
    $sv = "$v||$v||1||140||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpATRPeriod=$DefaultATRPeriod"), "InpATRPeriod=$sv"
    $tn = "08_ATRPeriod_$($v).train.ini"
    $hn = "08_ATRPeriod_$($v).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "08_ATRPeriod done"

# ========================
# 09_ATRMultSL sweep
# ========================
$multVals = @("1.0","1.5","2.0","2.5","3.0")
foreach ($v in $multVals) {
    $sv = "$v||$v||0.200000||20.000000||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpATRMultSL=$DefaultATRMultSL"), "InpATRMultSL=$sv"
    $tn = "09_ATRMultSL_$($v.Replace('.','p')).train.ini"
    $hn = "09_ATRMultSL_$($v.Replace('.','p')).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "09_ATRMultSL done"

# ========================
# 10_TargetR sweep
# ========================
$rVals = @("1.5","2.0","2.5","3.0","4.0")
foreach ($v in $rVals) {
    $sv = "$v||$v||0.200000||20.000000||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpTargetR=$DefaultTargetR"), "InpTargetR=$sv"
    $tn = "10_TargetR_$($v.Replace('.','p')).train.ini"
    $hn = "10_TargetR_$($v.Replace('.','p')).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "10_TargetR done"

# ========================
# 11_Breakeven toggle
# ========================
for ($i=0; $i -lt 2; $i++) {
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpUseBreakeven=$DefaultBreakeven"), "InpUseBreakeven=$($sfs[$i])"
    $tn = "11_Breakeven_$($sfn[$i]).train.ini"
    $hn = "11_Breakeven_$($sfn[$i]).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "11_Breakeven done"

# ========================
# 12_BEActivationR sweep
# ========================
$beaVals = @("0.5","0.75","1.0","1.25")
foreach ($v in $beaVals) {
    $sv = "$v||$v||0.100000||10.000000||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpBEActivationR=$DefaultBEActivation"), "InpBEActivationR=$sv"
    $tn = "12_BEActivationR_$($v.Replace('.','p')).train.ini"
    $hn = "12_BEActivationR_$($v.Replace('.','p')).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "12_BEActivationR done"

# ========================
# 13_TrailingStop toggle
# ========================
for ($i=0; $i -lt 2; $i++) {
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpUseTrailingStop=$DefaultTrailing"), "InpUseTrailingStop=$($sfs[$i])"
    $tn = "13_TrailingStop_$($sfn[$i]).train.ini"
    $hn = "13_TrailingStop_$($sfn[$i]).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "13_TrailingStop done"

# ========================
# 14_TrailActivationR sweep
# ========================
$traVals = @("1.0","1.25","1.5","2.0")
foreach ($v in $traVals) {
    $sv = "$v||$v||0.125000||12.500000||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpTrailActivationR=$DefaultTrailAct"), "InpTrailActivationR=$sv"
    $tn = "14_TrailActivationR_$($v.Replace('.','p')).train.ini"
    $hn = "14_TrailActivationR_$($v.Replace('.','p')).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "14_TrailActivationR done"

# ========================
# 15_TrailDistanceATR sweep
# ========================
$tdaVals = @("0.75","1.0","1.25","1.5")
foreach ($v in $tdaVals) {
    $sv = "$v||$v||0.100000||10.000000||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpTrailDistanceATR=$DefaultTrailDist"), "InpTrailDistanceATR=$sv"
    $tn = "15_TrailDistanceATR_$($v.Replace('.','p')).train.ini"
    $hn = "15_TrailDistanceATR_$($v.Replace('.','p')).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "15_TrailDistanceATR done"

# ========================
# 16_RiskPct sweep
# ========================
$riskVals = @("0.5","1.0","1.5","2.0","3.0","5.0")
foreach ($v in $riskVals) {
    $sv = "$v||$v||0.100000||10.000000||N"
    $body = New-Body
    $body = $body -replace [regex]::Escape("InpRiskPct=$DefaultRiskPct"), "InpRiskPct=$sv"
    $tn = "16_RiskPct_$($v.Replace('.','p')).train.ini"
    $hn = "16_RiskPct_$($v.Replace('.','p')).holdout.ini"
    (New-IniHeader $symbol $period $trainFrom $trainTo $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $tn)
    (New-IniHeader $symbol $period $holdFrom  $holdTo  $deposit) + $body | Out-File -Encoding utf8 (Join-Path $outDir $hn)
}
Write-Host "16_RiskPct done"

Write-Host "=== ALL INI FILES GENERATED ==="
Write-Host "Train: $trainFrom - $trainTo"
Write-Host "Holdout: $holdFrom - $holdTo"
