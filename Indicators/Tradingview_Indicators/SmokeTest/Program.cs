// SmokeTest — End-to-end iCustom + CopyBuffer verification for MT5 converted indicators
// Requires: MT5 terminal running with MtApi5 EA attached on localhost:8222
//           .ex5 files copied to MT5's MQL5/Indicators/<subfolder>
//
// Usage: dotnet run [--host=localhost] [--port=8222] [--symbol=EURUSD]

using MtApi5;

// ── Config ─────────────────────────────────────────────────────────────────
var host     = args.FirstOrDefault(a => a.StartsWith("--host="))?.Split('=')[1] ?? "localhost";
var port     = int.Parse(args.FirstOrDefault(a => a.StartsWith("--port="))?.Split('=')[1] ?? "8222");
var symbol   = args.FirstOrDefault(a => a.StartsWith("--symbol="))?.Split('=')[1] ?? "EURUSD";
var period   = ENUM_TIMEFRAMES.PERIOD_H1;

Console.WriteLine($"=== MTApi5 iCustom Smoke Test ===");
Console.WriteLine($"Host: {host}:{port}  Symbol: {symbol}  Period: {period}");
Console.WriteLine();

var logger = new ConsoleLogger();
var api    = new MtApi5Client(logger);
var results = new List<TestResult>();

// ── Connect ────────────────────────────────────────────────────────────────
Console.WriteLine("[1/7] Connecting to MTApi5 bridge...");
var connected = new TaskCompletionSource<bool>();
api.ConnectionStateChanged += (s, e) =>
{
    logger.Info($"Connection state: {e.Status} — {e.ConnectionMessage}");
    if (e.Status == Mt5ConnectionState.Connected) connected.TrySetResult(true);
    if (e.Status == Mt5ConnectionState.Disconnected || e.Status == Mt5ConnectionState.Failed)
        connected.TrySetResult(false);
};

api.BeginConnect(host, port);
var winner = await Task.WhenAny(connected.Task, Task.Delay(15000));
if (winner != connected.Task || !connected.Task.Result)
{
    Console.WriteLine("  FAIL: Could not connect to MTApi5 bridge.");
    Console.WriteLine("  Ensure MT5 is running with MtApi5 EA attached and listening on port 8222.");
    PrintSummary(results);
    return 1;
}
Console.WriteLine("  PASS: Connected successfully.");
Console.WriteLine();

try
{
    // ── Test 1: No-parameter iCustom ───────────────────────────────────────
    Console.WriteLine("[2/7] No-parameter iCustom → CopyBuffer");
    await TestICustom(api, symbol, period,
        indicatorName: "WAVETREND\\WaveTrend_MAX",
        paramType: "none",
        parameters: Array.Empty<int>(),
        useOverload: "int[]",
        bufferIndex: 0,
        expectedMinBars: 10,
        label: "WaveTrend_MAX (no params)",
        results);

    // ── Test 2: Integer-parameter iCustom ──────────────────────────────────
    Console.WriteLine("[3/7] Integer-parameter iCustom → CopyBuffer");
    await TestICustom(api, symbol, period,
        indicatorName: "HURST_SUITE\\Hurst_Cycle_Oscillator",
        paramType: "int[]",
        parameters: new int[] { /*SCL*/ 10, /*MCL*/ 30, /*SCM*/ 1, /*MCM*/ 3, /*Src*/ (int)ENUM_APPLIED_PRICE.PRICE_CLOSE },
        useOverload: "int[]",
        bufferIndex: 0,
        expectedMinBars: 10,
        label: "Hurst_Oscillator (int params)",
        results);

    // ── Test 3: Double-parameter iCustom ───────────────────────────────────
    Console.WriteLine("[4/7] Double-parameter iCustom → CopyBuffer");
    await TestICustom(api, symbol, period,
        indicatorName: "PATTERNFORGE\\PATTERNFORGE_Pro",
        paramType: "double[]",
        parameters: new double[] { /*tolerance*/ 0.5, /*min pole pct*/ 1.5 },
        useOverload: "double[]",
        bufferIndex: 0,
        expectedMinBars: 5,
        label: "PATTERNFORGE_Pro (double params)",
        results);

    // ── Test 4: Bool-parameter iCustom ─────────────────────────────────────
    Console.WriteLine("[5/7] Bool-parameter iCustom → CopyBuffer");
    await TestICustom(api, symbol, period,
        indicatorName: "Tripple_MA\\Elite_Triple_MA_Suite",
        paramType: "bool[]",
        parameters: new bool[] { true, true, true },  // ShowCloud, ShowSignals, ShowTable
        useOverload: "bool[]",
        bufferIndex: 0,
        expectedMinBars: 10,
        label: "Elite_Triple_MA (bool params)",
        results);

    // ── Test 5: String-parameter iCustom ───────────────────────────────────
    // EliteMA has ENUM_ELITE_MA_TYPE as integer, not string. Skipping string test
    // unless an indicator accepts string inputs.
    Console.WriteLine("[6/7] String-parameter iCustom — skipped (no string-input indicator)");

    // ── Test 6: Multi-buffer CopyBuffer validation ─────────────────────────
    Console.WriteLine("[7/7] Multi-buffer validation (WaveTrend_MAX buffers 0,1,2)");
    await TestMultipleBuffers(api, symbol, period,
        "WAVETREND\\WaveTrend_MAX", new[] { 0, 1, 2 },
        "WT1, WT2, Dynamic Upper", results);

    // ── IndicatorRelease ───────────────────────────────────────────────────
    Console.WriteLine();
    Console.WriteLine("IndicatorRelease cleanup test:");
    var relHandle = api.iCustom(symbol, period, "WAVETREND\\WaveTrend_MAX", Array.Empty<int>());
    if (relHandle > 0)
    {
        bool released = api.IndicatorRelease(relHandle);
        Console.WriteLine($"  Handle {relHandle} released: {(released ? "PASS" : "FAIL")}");
    }
    else
    {
        Console.WriteLine($"  Skipped — handle creation failed ({relHandle})");
    }
}
catch (Exception ex)
{
    Console.WriteLine($"  EXCEPTION: {ex.Message}");
    Console.WriteLine(ex.StackTrace);
}
finally
{
    api.BeginDisconnect();
}

// ── Summary ────────────────────────────────────────────────────────────────
PrintSummary(results);
return results.Any(r => !r.Passed) ? 1 : 0;

// ═══════════════════════════════════════════════════════════════════════════
// Test Helpers
// ═══════════════════════════════════════════════════════════════════════════

async Task TestICustom(
    MtApi5Client api,
    string sym,
    ENUM_TIMEFRAMES tf,
    string indicatorName,
    string paramType,
    object parameters,
    string useOverload,
    int bufferIndex,
    int expectedMinBars,
    string label,
    List<TestResult> results)
{
    var result = new TestResult { Label = label, Indicator = indicatorName };
    
    Console.WriteLine($"  Indicator: {indicatorName}");
    Console.WriteLine($"  Param type: {paramType}");
    
    // Create handle
    int handle;
    try
    {
        handle = useOverload switch
        {
            "int[]"    => api.iCustom(sym, tf, indicatorName, (int[])parameters),
            "double[]" => api.iCustom(sym, tf, indicatorName, (double[])parameters),
            "bool[]"   => api.iCustom(sym, tf, indicatorName, (bool[])parameters),
            "string[]" => api.iCustom(sym, tf, indicatorName, (string[])parameters),
            _          => api.iCustom(sym, tf, indicatorName, (int[])parameters)
        };
    }
    catch (Exception ex)
    {
        result.Error = $"iCustom exception: {ex.Message}";
        result.Passed = false;
        results.Add(result);
        Console.WriteLine($"  FAIL: Exception: {ex.Message}");
        return;
    }
    
    result.Handle = handle;
    Console.WriteLine($"  iCustom handle: {handle}");
    
    if (handle <= 0)
    {
        result.Error = $"Handle invalid ({handle}). Indicator not found, wrong path, or params rejected.";
        result.Passed = false;
        results.Add(result);
        
        // Try to get MT5 last error
        try
        {
            int errCode = api.GetLastError();
            Console.WriteLine($"  MT5 last error code: {errCode}");
            if (errCode != 0)
            {
                result.Error += $" | MT5 error code: {errCode}";
            }
        }
        catch { }
        return;
    }
    
    // Wait for bars to calculate
    Console.WriteLine($"  Waiting for bars to calculate...");
    await Task.Delay(2000);
    
    int barsCalc = api.BarsCalculated(handle);
    result.BarsCalculated = barsCalc;
    Console.WriteLine($"  BarsCalculated: {barsCalc}");
    
    if (barsCalc <= 0)
    {
        result.Error = "BarsCalculated returned 0 — indicator not computing";
        result.Passed = false;
        results.Add(result);
        api.IndicatorRelease(handle);
        return;
    }
    
    // CopyBuffer
    try
    {
        int copied = api.CopyBuffer(handle, bufferIndex, 0, Math.Min(barsCalc, 100), out double[] buffer);
        result.CopiedCount = copied;
        result.BufferSample = buffer.Take(Math.Min(5, buffer.Length)).ToArray();
        
        Console.WriteLine($"  CopyBuffer(buffer={bufferIndex}): copied {copied} values");
        Console.WriteLine($"  Sample (first 5): [{string.Join(", ", buffer.Take(5).Select(v => v.ToString("F6")))}]");
        
        bool hasData = buffer.Any(v => v != 0.0 && v != double.MaxValue && v != double.MinValue && !double.IsNaN(v));
        bool hasEnough = copied >= expectedMinBars;
        
        if (hasEnough && hasData)
        {
            result.Passed = true;
            Console.WriteLine($"  PASS: Got {copied} bars with real data.");
        }
        else
        {
            result.Error = $"Insufficient data: copied={copied}, hasRealData={hasData}, need>={expectedMinBars}";
            result.Passed = false;
            Console.WriteLine($"  FAIL: {result.Error}");
        }
    }
    catch (Exception ex)
    {
        result.Error = $"CopyBuffer exception: {ex.Message}";
        result.Passed = false;
        Console.WriteLine($"  FAIL: {ex.Message}");
    }
    
    // Release
    bool rel = api.IndicatorRelease(handle);
    Console.WriteLine($"  IndicatorRelease: {(rel ? "ok" : "FAIL")}");
    result.Released = rel;
    
    results.Add(result);
    Console.WriteLine();
}

async Task TestMultipleBuffers(
    MtApi5Client api,
    string sym,
    ENUM_TIMEFRAMES tf,
    string indicatorName,
    int[] bufferIndexes,
    string bufferNames,
    List<TestResult> results)
{
    var result = new TestResult { Label = $"Multi-buffer: {indicatorName}", Indicator = indicatorName };
    
    int handle = api.iCustom(sym, tf, indicatorName, Array.Empty<int>());
    result.Handle = handle;
    Console.WriteLine($"  Handle: {handle}");
    
    if (handle <= 0)
    {
        result.Error = $"Handle invalid ({handle})";
        result.Passed = false;
        results.Add(result);
        return;
    }
    
    await Task.Delay(2000);
    int barsCalc = api.BarsCalculated(handle);
    Console.WriteLine($"  BarsCalculated: {barsCalc}");
    
    bool allOk = true;
    for (int bi = 0; bi < bufferIndexes.Length; bi++)
    {
        int bufIdx = bufferIndexes[bi];
        int copied = api.CopyBuffer(handle, bufIdx, 0, Math.Min(barsCalc, 50), out double[] buf);
        bool hasData = buf.Any(v => v != 0.0 && !double.IsNaN(v));
        Console.WriteLine($"  Buffer[{bufIdx}]: copied={copied}, hasData={hasData}");
        if (copied < 5 || !hasData) allOk = false;
    }
    
    result.Passed = allOk;
    result.CopiedCount = barsCalc;
    if (!allOk) result.Error = "One or more buffers returned insufficient data";
    
    api.IndicatorRelease(handle);
    results.Add(result);
    Console.WriteLine($"  {(allOk ? "PASS" : "FAIL")}: {bufferNames}");
    Console.WriteLine();
}

void PrintSummary(List<TestResult> results)
{
    Console.WriteLine();
    Console.WriteLine("═══════════════════════════════════════════════════════════════");
    Console.WriteLine("                     SMOKE TEST SUMMARY");
    Console.WriteLine("═══════════════════════════════════════════════════════════════");
    
    int passed = results.Count(r => r.Passed);
    int failed = results.Count(r => !r.Passed);
    
    foreach (var r in results)
    {
        string status = r.Passed ? "PASS" : "FAIL";
        Console.WriteLine($"  [{status}] {r.Label}");
        Console.WriteLine($"         Handle={r.Handle}  Bars={r.BarsCalculated}  Copied={r.CopiedCount}");
        if (!r.Passed && !string.IsNullOrEmpty(r.Error))
            Console.WriteLine($"         Error: {r.Error}");
        if (r.BufferSample is { Length: > 0 })
            Console.WriteLine($"         Sample: [{string.Join(", ", r.BufferSample.Take(3).Select(v => v.ToString("F4")))}]");
    }
    
    Console.WriteLine("───────────────────────────────────────────────────────────────");
    Console.WriteLine($"  Total: {results.Count}  Passed: {passed}  Failed: {failed}");
    
    if (failed > 0)
    {
        Console.WriteLine();
        Console.WriteLine("  REMEDIATION STEPS:");
        Console.WriteLine("  1. Verify MT5 terminal is running with a chart open for the test symbol.");
        Console.WriteLine("  2. Ensure the MtApi5 EA (.ex5) is attached to the chart.");
        Console.WriteLine("  3. Verify .ex5 files are in MT5's MQL5/Indicators/<subfolder>.");
        Console.WriteLine("  4. Check that enough price history exists for the test symbol/period.");
        Console.WriteLine("  5. The bridge defaults to port 8222 — confirm no firewall blocking.");
        Console.WriteLine("  6. Try loading each indicator manually in MT5 first to verify compilation.");
    }
    
    Console.WriteLine("═══════════════════════════════════════════════════════════════");
}

// ── Types ──────────────────────────────────────────────────────────────────
record TestResult
{
    public string Label { get; set; } = "";
    public string Indicator { get; set; } = "";
    public int Handle { get; set; }
    public int BarsCalculated { get; set; }
    public int CopiedCount { get; set; }
    public double[]? BufferSample { get; set; }
    public bool Passed { get; set; }
    public string? Error { get; set; }
    public bool Released { get; set; }
}

class ConsoleLogger : IMtLogger
{
    public void Debug(object message) { }
    public void Info(object message)  => Console.WriteLine($"  [INFO]  {message}");
    public void Warn(object message)  => Console.WriteLine($"  [WARN]  {message}");
    public void Error(object message) => Console.WriteLine($"  [ERROR] {message}");
    public void Fatal(object message) => Console.WriteLine($"  [FATAL] {message}");
}
