import os

OUT = r"C:\Program Files\MetaTrader 5\MQL5\Profiles\Tester\MS-ZZ-BO-V2"
SYM = "XAUUSD"
PER = "M5"
DEP = 10000

TR_FROM = "2024.07.01"
TR_TO   = "2025.06.30"
HO_FROM = "2025.07.01"
HO_TO   = "2026.06.30"

def header(label, frm, to):
    return f""";MS-ZZ-BO-V2_EA | {SYM} {PER} | {label}
[Tester]
Expert=MS-ZZ-BO-V2\\MS-ZZ-BO-V2_EA.ex5
Symbol={SYM}
Period={PER}
Optimization=0
Model=4
FromDate={frm}
ToDate={to}
ForwardMode=0
Deposit={DEP}
Currency=USD
ProfitInPips=0
Leverage=500
ExecutionMode=0
OptimizationCriterion=0
Visual=0
[TesterInputs]
"""

def defaults():
    return [
        "; 1. Safety",
        "InpEnableTrading=true||false||0||true||N",
        "InpMagicNumber=260715||260715||1||2607150||N",
        "InpTradeSymbol=XAUUSD",
        "InpSignalTF=5||0||0||49153||N",
        "; 2. Indicator",
        "InpIndicatorPath=Tradingview_Indicators\\MULTI_SPEED_ZIGZAG\\MS-ZZ-BO-V2",
        "InpSignalMode=0||0||0||2||N",
        "InpMinBarsBetweenTrades=3||3||1||30||N",
        "; 3. Session & Spread",
        "InpUseSessionFilter=true||false||0||true||N",
        "InpSessionStart=07:00",
        "InpSessionEnd=17:00",
        "InpUseSpreadFilter=true||false||0||true||N",
        "InpMaxSpreadPoints=80.0||80.0||8.000000||800.000000||N",
        "; 4. Risk",
        "InpATRPeriod=14||14||1||140||N",
        "InpATRMultSL=2.0||2.0||0.200000||20.000000||N",
        "InpTargetR=2.0||2.0||0.200000||20.000000||N",
        "InpUseBreakeven=true||false||0||true||N",
        "InpBEActivationR=1.0||1.0||0.100000||10.000000||N",
        "InpUseTrailingStop=true||false||0||true||N",
        "InpTrailActivationR=1.25||1.25||0.125000||12.500000||N",
        "InpTrailDistanceATR=1.0||1.0||0.100000||10.000000||N",
        "InpRiskPct=1.0||1.0||0.100000||10.000000||N",
        "InpMaxLots=1.0||1.0||0.100000||10.000000||N",
        "InpMinLots=0.01||0.01||0.001000||0.100000||N",
        "; 5. Misc",
        "InpVerboseLogging=false||false||0||true||N",
    ]

def write_ini(fname, label, frm, to, overrides):
    lines = [header(label, frm, to)]
    d = list(defaults())
    for k, v in overrides.items():
        for i, line in enumerate(d):
            if line.startswith(k + "=") or line.startswith(k + "||"):
                d[i] = v
                break
    lines.extend(d)
    path = os.path.join(OUT, fname)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    return path

count = 0

# --- 00_Baseline ---
write_ini("00_Baseline.train.ini",   f"BASELINE TRAIN {TR_FROM}-{TR_TO}", TR_FROM, TR_TO, {})
write_ini("00_Baseline.holdout.ini", f"BASELINE HOLDOUT {HO_FROM}-{HO_TO}", HO_FROM, HO_TO, {})
count += 2

# --- 01_SignalMode ---
for mode_name, mode_val in [("MED_ONLY","0||0||0||2||N"), ("FAST_ONLY","1||0||0||2||N"), ("ANY","2||0||0||2||N")]:
    write_ini(f"01_SignalMode_{mode_name}.train.ini", f"SIGNALMODE={mode_name} TRAIN", TR_FROM, TR_TO,
              {"InpSignalMode": mode_val})
    write_ini(f"01_SignalMode_{mode_name}.holdout.ini", f"SIGNALMODE={mode_name} HOLDOUT", HO_FROM, HO_TO,
              {"InpSignalMode": mode_val})
count += 6

# --- 02_SignalTF ---
for tf_name, tf_val in [("M1","1||0||0||49153||N"), ("M5","5||0||0||49153||N"), ("M15","15||0||0||49153||N"), ("CURRENT","0||0||0||49153||N")]:
    write_ini(f"02_SignalTF_{tf_name}.train.ini", f"SIGNALTF={tf_name} TRAIN", TR_FROM, TR_TO,
              {"InpSignalTF": tf_val})
    write_ini(f"02_SignalTF_{tf_name}.holdout.ini", f"SIGNALTF={tf_name} HOLDOUT", HO_FROM, HO_TO,
              {"InpSignalTF": tf_val})
count += 8

# --- 03_MinBarsBetweenTrades ---
for b in [0,1,2,3,5,8]:
    val = f"{b}||{b}||1||30||N"
    write_ini(f"03_MinBars_{b}.train.ini", f"MINBARS={b} TRAIN", TR_FROM, TR_TO,
              {"InpMinBarsBetweenTrades": val})
    write_ini(f"03_MinBars_{b}.holdout.ini", f"MINBARS={b} HOLDOUT", HO_FROM, HO_TO,
              {"InpMinBarsBetweenTrades": val})
count += 12

# --- 04_SessionFilter ---
for sf_name, sf_val in [("On","true||false||0||true||N"), ("Off","false||false||0||true||N")]:
    write_ini(f"04_SessionFilter_{sf_name}.train.ini", f"SESSFILT={sf_name} TRAIN", TR_FROM, TR_TO,
              {"InpUseSessionFilter": sf_val})
    write_ini(f"04_SessionFilter_{sf_name}.holdout.ini", f"SESSFILT={sf_name} HOLDOUT", HO_FROM, HO_TO,
              {"InpUseSessionFilter": sf_val})
count += 4

# --- 05_SessionTimes ---
for s_name, s_start, s_end in [("00-23","00:00","23:59"), ("07-17","07:00","17:00"), ("08-20","08:00","20:00"), ("22-05","22:00","05:00")]:
    write_ini(f"05_Session_{s_name}.train.ini", f"SESS={s_name} TRAIN", TR_FROM, TR_TO,
              {"InpSessionStart": s_start, "InpSessionEnd": s_end})
    write_ini(f"05_Session_{s_name}.holdout.ini", f"SESS={s_name} HOLDOUT", HO_FROM, HO_TO,
              {"InpSessionStart": s_start, "InpSessionEnd": s_end})
count += 8

# --- 06_SpreadFilter ---
for sf_name, sf_val in [("On","true||false||0||true||N"), ("Off","false||false||0||true||N")]:
    write_ini(f"06_SpreadFilter_{sf_name}.train.ini", f"SPREADFILT={sf_name} TRAIN", TR_FROM, TR_TO,
              {"InpUseSpreadFilter": sf_val})
    write_ini(f"06_SpreadFilter_{sf_name}.holdout.ini", f"SPREADFILT={sf_name} HOLDOUT", HO_FROM, HO_TO,
              {"InpUseSpreadFilter": sf_val})
count += 4

# --- 07_MaxSpreadPoints ---
for sp in [30,40,60,80,120]:
    val = f"{sp}.0||{sp}.0||8.000000||800.000000||N"
    write_ini(f"07_MaxSpread_{sp}.train.ini", f"MAXSPREAD={sp} TRAIN", TR_FROM, TR_TO,
              {"InpMaxSpreadPoints": val})
    write_ini(f"07_MaxSpread_{sp}.holdout.ini", f"MAXSPREAD={sp} HOLDOUT", HO_FROM, HO_TO,
              {"InpMaxSpreadPoints": val})
count += 10

# --- 08_ATRPeriod ---
for ap in [10,14,20,28]:
    val = f"{ap}||{ap}||1||140||N"
    write_ini(f"08_ATRPeriod_{ap}.train.ini", f"ATRPER={ap} TRAIN", TR_FROM, TR_TO,
              {"InpATRPeriod": val})
    write_ini(f"08_ATRPeriod_{ap}.holdout.ini", f"ATRPER={ap} HOLDOUT", HO_FROM, HO_TO,
              {"InpATRPeriod": val})
count += 8

# --- 09_ATRMultSL ---
for v in ["1.0","1.5","2.0","2.5","3.0"]:
    val = f"{v}||{v}||0.200000||20.000000||N"
    tag = v.replace(".","p")
    write_ini(f"09_ATRMultSL_{tag}.train.ini", f"ATRMULT={v} TRAIN", TR_FROM, TR_TO,
              {"InpATRMultSL": val})
    write_ini(f"09_ATRMultSL_{tag}.holdout.ini", f"ATRMULT={v} HOLDOUT", HO_FROM, HO_TO,
              {"InpATRMultSL": val})
count += 10

# --- 10_TargetR ---
for v in ["1.5","2.0","2.5","3.0","4.0"]:
    val = f"{v}||{v}||0.200000||20.000000||N"
    tag = v.replace(".","p")
    write_ini(f"10_TargetR_{tag}.train.ini", f"TARGETR={v} TRAIN", TR_FROM, TR_TO,
              {"InpTargetR": val})
    write_ini(f"10_TargetR_{tag}.holdout.ini", f"TARGETR={v} HOLDOUT", HO_FROM, HO_TO,
              {"InpTargetR": val})
count += 10

# --- 11_Breakeven ---
for be_name, be_val in [("On","true||false||0||true||N"), ("Off","false||false||0||true||N")]:
    write_ini(f"11_Breakeven_{be_name}.train.ini", f"BE={be_name} TRAIN", TR_FROM, TR_TO,
              {"InpUseBreakeven": be_val})
    write_ini(f"11_Breakeven_{be_name}.holdout.ini", f"BE={be_name} HOLDOUT", HO_FROM, HO_TO,
              {"InpUseBreakeven": be_val})
count += 4

# --- 12_BEActivationR ---
for v in ["0.5","0.75","1.0","1.25"]:
    val = f"{v}||{v}||0.100000||10.000000||N"
    tag = v.replace(".","p")
    write_ini(f"12_BEActivationR_{tag}.train.ini", f"BEACT={v} TRAIN", TR_FROM, TR_TO,
              {"InpBEActivationR": val})
    write_ini(f"12_BEActivationR_{tag}.holdout.ini", f"BEACT={v} HOLDOUT", HO_FROM, HO_TO,
              {"InpBEActivationR": val})
count += 8

# --- 13_TrailingStop ---
for ts_name, ts_val in [("On","true||false||0||true||N"), ("Off","false||false||0||true||N")]:
    write_ini(f"13_TrailingStop_{ts_name}.train.ini", f"TRAIL={ts_name} TRAIN", TR_FROM, TR_TO,
              {"InpUseTrailingStop": ts_val})
    write_ini(f"13_TrailingStop_{ts_name}.holdout.ini", f"TRAIL={ts_name} HOLDOUT", HO_FROM, HO_TO,
              {"InpUseTrailingStop": ts_val})
count += 4

# --- 14_TrailActivationR ---
for v in ["1.0","1.25","1.5","2.0"]:
    val = f"{v}||{v}||0.125000||12.500000||N"
    tag = v.replace(".","p")
    write_ini(f"14_TrailActivationR_{tag}.train.ini", f"TRAILACT={v} TRAIN", TR_FROM, TR_TO,
              {"InpTrailActivationR": val})
    write_ini(f"14_TrailActivationR_{tag}.holdout.ini", f"TRAILACT={v} HOLDOUT", HO_FROM, HO_TO,
              {"InpTrailActivationR": val})
count += 8

# --- 15_TrailDistanceATR ---
for v in ["0.75","1.0","1.25","1.5"]:
    val = f"{v}||{v}||0.100000||10.000000||N"
    tag = v.replace(".","p")
    write_ini(f"15_TrailDistanceATR_{tag}.train.ini", f"TRAILDIST={v} TRAIN", TR_FROM, TR_TO,
              {"InpTrailDistanceATR": val})
    write_ini(f"15_TrailDistanceATR_{tag}.holdout.ini", f"TRAILDIST={v} HOLDOUT", HO_FROM, HO_TO,
              {"InpTrailDistanceATR": val})
count += 8

# --- 16_RiskPct ---
for v in ["0.5","1.0","1.5","2.0","3.0","5.0"]:
    val = f"{v}||{v}||0.100000||10.000000||N"
    tag = v.replace(".","p")
    write_ini(f"16_RiskPct_{tag}.train.ini", f"RISK={v}% TRAIN", TR_FROM, TR_TO,
              {"InpRiskPct": val})
    write_ini(f"16_RiskPct_{tag}.holdout.ini", f"RISK={v}% HOLDOUT", HO_FROM, HO_TO,
              {"InpRiskPct": val})
count += 12

print(f"Generated {count} .ini files in {OUT}")
