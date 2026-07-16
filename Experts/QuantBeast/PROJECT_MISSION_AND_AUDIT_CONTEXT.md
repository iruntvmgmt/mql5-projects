# PROJECT CONTEXT: WHY THE QUANT BEAST EA EXISTS

## Purpose of this document

This document explains the original goal that caused this project to shift away from basic Expert Advisors and toward a much larger quantitative trading architecture.

Read this before auditing, refactoring, simplifying, or removing any part of the system.

The purpose of the audit is not merely to make the EA compile.

The purpose is to verify that the architecture faithfully supports the intended trading mission, that its mechanics are internally correct, and that it can eventually be tested as a serious aggressive account-growth system.

---

# 1. Original objective

The project began with a direct objective:

> Build an automated trading system with the potential to aggressively grow a very small account, initially around $100, toward $500–$1,000 during an exceptional trading week.

This is a highly aggressive objective.

It is fully understood that:

- a 5×–10× weekly return cannot be guaranteed;
- attempting it requires leverage and concentrated risk;
- the probability of losing the entire challenge account may be significant;
- coding a large EA does not prove a trading edge;
- historical profitability does not guarantee live profitability.

The project is not based on the belief that a risk-free money-printing bot exists.

The project is based on the belief that a properly engineered automated system may be able to pursue asymmetric account growth more intelligently, consistently, and safely than a manually operated high-risk strategy.

The EA must therefore be capable of pursuing aggressive growth while still remaining controlled, measurable, auditable, and technically safe.

---

# 2. Why the project moved away from basic EAs

The original direction involved building increasingly complex versions of familiar retail trading tools, including:

- oscillators;
- moving averages;
- Fibonacci systems;
- Smart Money Concepts;
- cycle indicators;
- Kalman filters;
- divergence systems;
- support and resistance tools;
- TradingView-style indicators;
- combinations of multiple confirmation signals.

Those tools may still have research value, but the project deliberately moved away from treating indicator complexity as the main source of profitability.

The shift happened because most basic EAs follow the same limited model:

```text
Indicator condition
→ Buy or sell
→ Fixed stop
→ Fixed target
```

That model usually ignores:

- changing market regimes;
- session conditions;
- volatility state;
- execution quality;
- broker constraints;
- spread expansion;
- order failures;
- strategy conflict;
- portfolio exposure;
- live degradation;
- restart recovery;
- strategy-specific risk;
- the difference between backtest behavior and live execution.

The project was therefore reframed.

Instead of asking:

> Which indicator combination will create the best entry?

The new question became:

> What mechanics would a serious quantitative trading operation require to research, approve, execute, manage, monitor, and retire trading edges?

That question led to the current architecture.

---

# 3. The central design philosophy

The EA is not intended to be one enormous entry strategy.

It is intended to behave like a controlled quantitative trading system.

The core philosophy is:

```text
Different market conditions
require different strategy engines.

Different strategy engines
must share the same risk and execution infrastructure.

No strategy may bypass central control.
```

The platform must separate:

- market interpretation;
- strategy generation;
- signal selection;
- risk approval;
- order execution;
- position management;
- emergency controls;
- analytics.

The correct system flow is:

```text
Market data
→ Data validation
→ Feature calculation
→ Market regime classification
→ Independent strategy engines
→ Signal arbitration
→ Risk approval
→ Order construction
→ Broker execution
→ Position management
→ Journaling and performance analysis
```

Each layer must have a clear responsibility.

---

# 4. Primary market direction

The first deployment target is XAUUSD through MetaTrader 5.

This decision was made because XAUUSD offers:

- strong intraday volatility;
- defined London and New York session behavior;
- frequent expansion and rejection patterns;
- compatibility with the existing MT5 EA environment;
- the possibility of aggressive account growth;
- clear broker-side execution for live testing.

The system should remain architecturally adaptable to BTC or other markets later.

However, the current audit should prioritize correct operation on broker-provided XAUUSD data.

The system must not assume that all XAUUSD brokers behave identically.

The audit must remain aware of differences in:

- symbol names;
- spread;
- digits;
- tick size;
- tick value;
- contract size;
- stop levels;
- freeze levels;
- filling modes;
- commission;
- leverage;
- margin calculation;
- broker-server time.

---

# 5. Trading thesis

The EA is not built around the belief that one universal setup works in every market condition.

It is built around several distinct trading hypotheses.

## 5.1 Volatility expansion

Markets frequently alternate between compression and expansion.

The system should identify:

- reduced volatility;
- narrowing ranges;
- meaningful structural boundaries;
- increasing participation;
- the transition into directional expansion.

The EA should attempt to capture the relatively small number of strong expansion moves that can produce asymmetric returns.

## 5.2 Failed breakouts and liquidity rejection

Price often trades beyond obvious highs, lows, ranges, or session boundaries without gaining acceptance.

The system should distinguish between:

- a genuine breakout;
- a temporary penetration;
- a failed auction;
- a rapid reclaim;
- rejection followed by displacement.

This must be defined objectively.

The EA must not classify every wick beyond a level as a liquidity sweep.

## 5.3 Trend continuation after controlled pullback

Strong directional moves do not always offer clean breakout entries.

The system should identify:

- a persistent trend;
- a non-terminal stage of that trend;
- a controlled retracement;
- structural validity;
- renewed directional momentum.

The pullback engine should avoid entering exhausted trends merely because price remains above or below a moving average.

## 5.4 Mean reversion during balance

Mean reversion can work when price is rotating around a stable area of value.

It should not operate during active breakout expansion.

The system should only enable mean reversion when:

- trend strength is limited;
- structural balance exists;
- volatility is controlled;
- equilibrium is reasonably stable;
- there is sufficient room for price to return toward value after costs.

---

# 6. Why multiple strategies are required

The system contains multiple engines because market behavior changes.

A breakout strategy may perform well during volatility expansion and badly during balance.

A mean-reversion strategy may perform well during balance and fail catastrophically during a genuine breakout.

A trend-pullback system may perform well during directional continuation but enter too late during exhaustion.

A failed-breakout strategy may perform well around meaningful boundaries but generate noise when structural levels are poorly defined.

The regime engine and signal arbitrator therefore exist to ensure that:

- only suitable strategies become eligible;
- conflicting signals are handled centrally;
- multiple strategies do not unknowingly duplicate the same exposure;
- strategy behavior can be measured independently;
- one poorly performing engine can be disabled without destroying the entire EA.

During the audit, do not collapse all strategies into one combined signal expression for convenience.

That would destroy the architecture’s purpose.

---

# 7. The aggressive-growth mandate

The system has two different operational mandates.

## 7.1 Validation mandate

This is the normal research and live-validation path.

It should prioritize:

- correctness;
- controlled risk;
- realistic costs;
- data integrity;
- repeatability;
- stable execution;
- edge validation;
- survival.

Modes supporting this include:

- Diagnostic Mode;
- Shadow Mode;
- Conservative Live Mode.

## 7.2 Challenge mandate

Challenge Mode exists for deliberate high-risk attempts to grow a small, isolated account.

The objective is not smooth institutional compounding.

The objective is to maximize the probability of reaching a defined equity target before the account reaches its failure threshold.

Challenge Mode may use:

- higher risk per trade;
- aggressive compounding;
- stage-based risk;
- milestone locks;
- selective pyramiding into profitable positions;
- reduced risk after reaching protected equity stages.

Challenge Mode must still remain controlled.

It must never use:

- uncontrolled martingale;
- unlimited grid trading;
- automatic averaging into losing positions;
- infinite retries;
- no-stop positions;
- silent leverage escalation;
- bypassed daily or account-level loss limits.

The challenge account should be treated as a bounded-risk experiment.

Its possible loss should be accepted before deployment.

---

# 8. Why the system is larger than a normal EA

The architecture became large because the following are not optional for a serious automated strategy:

## 8.1 Market-state awareness

The bot must know whether the market is:

- trending;
- balanced;
- compressing;
- expanding;
- highly volatile;
- structurally breaking out;
- failing a breakout;
- pulling back;
- illiquid;
- near rollover;
- inside a restricted event window.

## 8.2 Central risk control

Strategies should not determine their own final lot size or decide whether account-level risk permits a trade.

The risk engine must control:

- trade risk;
- strategy risk;
- symbol exposure;
- account drawdown;
- margin;
- daily loss;
- weekly loss;
- challenge-stage loss;
- consecutive-loss lockouts.

## 8.3 Broker-safe execution

A valid signal is not the same thing as a valid order.

The system must handle:

- illegal volume;
- illegal stop distance;
- stale price;
- spread changes;
- insufficient margin;
- unsupported filling mode;
- broker rejection;
- requotes;
- delayed fills;
- duplicate submission;
- disconnects;
- unprotected fills.

## 8.4 Position lifecycle management

Entry is only one part of the trade.

The system must manage:

- initial protection;
- partial exits;
- break-even;
- trailing;
- time exits;
- session exits;
- pre-news handling;
- failed-momentum exits;
- strategy invalidation;
- emergency flattening.

## 8.5 Recovery and persistence

The EA must not forget its risk state because MT5 restarted.

It must recover:

- open positions;
- pending orders;
- challenge stage;
- daily loss status;
- high-water mark;
- partial exits;
- strategy ownership;
- active lockouts.

## 8.6 Explainability

Every important decision must be traceable.

The system should be able to answer:

- Why was this strategy eligible?
- Why was this signal accepted?
- Why was another signal rejected?
- How was the volume calculated?
- What risk limit applied?
- What was the expected execution cost?
- What happened at the broker?
- Why was the position closed?

---

# 9. The architecture is not the edge

A critical principle for the audit:

> The infrastructure does not itself create profitability.

The architecture exists to make it possible to:

- test strategy hypotheses correctly;
- measure real expectancy;
- avoid execution mistakes;
- prevent risk-rule bypasses;
- compare engines fairly;
- identify whether filters help or hurt;
- deploy live with controlled exposure;
- detect strategy degradation.

Do not mistake:

- large code volume;
- modular structure;
- advanced terminology;
- dashboards;
- complex scoring;
- many parameters;

for proof that the EA has an edge.

The audit must independently verify whether each trading mechanic is:

- mathematically meaningful;
- correctly implemented;
- free from future leakage;
- robust enough for testing;
- consistent in tester and live modes.

---

# 10. Audit philosophy

The audit must be adversarial.

Assume the system may contain:

- compile-safe logic errors;
- incorrect array indexing;
- inverted long/short conditions;
- stale values;
- uninitialized structures;
- incorrect time conversions;
- incorrect spread units;
- invalid lot calculations;
- incorrect stop normalization;
- inconsistent risk calculations;
- strategy state leakage;
- duplicated signals;
- tester/live divergence;
- recovery failures;
- hidden future leakage;
- dashboard values that do not match internal state;
- code paths that exist but never execute;
- placeholders that appear complete;
- features that are calculated but never used;
- inputs that do not affect behavior;
- conditions that make strategies permanently ineligible;
- conditions that make strategies excessively permissive.

The audit should not assume correctness because the architecture looks sophisticated.

---

# 11. Most important bug classes to investigate

## 11.1 Data and indexing bugs

Verify:

- whether arrays use series orientation consistently;
- whether index `0` means current bar everywhere;
- whether only closed bars are used where required;
- whether confirmed pivots wait for the correct number of bars;
- whether `CopyRates()` and `CopyBuffer()` return counts are validated;
- whether insufficient-history conditions are handled;
- whether MTF values reference the intended completed bar;
- whether new-bar detection works after restart;
- whether cached data updates correctly.

## 11.2 Time and session bugs

Verify:

- broker time versus UTC versus New York time;
- daylight-saving assumptions;
- sessions crossing midnight;
- Friday-close logic;
- daily counter reset;
- weekly counter reset;
- opening-range initialization;
- previous-day levels;
- rollover lockouts;
- Strategy Tester time behavior.

A session engine that is off by one hour may completely invalidate results.

## 11.3 Price-unit bugs

Verify the distinction among:

- price;
- points;
- ticks;
- pips;
- ATR values;
- spread points;
- stop distance;
- slippage points.

Gold brokers may use different digits and tick sizes.

No calculation should assume that a price movement of `0.01`, one point, one tick, and one pip are always the same.

## 11.4 Position-sizing bugs

Verify:

- risk in account currency;
- stop distance conversion;
- tick value;
- tick size;
- volume step;
- minimum volume;
- maximum volume;
- commissions;
- slippage allowance;
- buy/sell symmetry;
- account currency conversions;
- `OrderCalcProfit()` usage;
- `OrderCalcMargin()` usage.

Lot sizing must be tested across multiple broker symbol specifications.

## 11.5 Signal duplication bugs

Verify:

- multiple ticks producing the same order;
- multiple strategies producing the same economic signal;
- restart causing a prior signal to execute again;
- pending orders not counted as existing exposure;
- partial fills causing repeat submission;
- trade-transaction events producing duplicate state updates.

## 11.6 Order-management bugs

Verify:

- the selected filling mode;
- pending-order expiration;
- retry limits;
- price revalidation before retry;
- stop and target normalization;
- freeze-level behavior;
- rejected modifications;
- partial-close rounding;
- netting versus hedging behavior;
- ticket selection;
- trade ownership;
- handling of asynchronous broker responses.

## 11.7 Protection bugs

Verify:

- every live position receives a protective stop;
- stop placement failures trigger emergency behavior;
- trailing stops never loosen risk unless explicitly allowed;
- break-even calculations include costs;
- partial exits do not accidentally remove protection;
- scale-ins do not increase total risk beyond limits;
- emergency flattening only closes EA-owned positions unless explicitly configured otherwise.

## 11.8 Persistence bugs

Verify:

- daily loss locks survive restart;
- challenge stages survive restart;
- high-water marks do not reset incorrectly;
- strategy cooldowns survive;
- partial-exit flags survive;
- corrupted state fails safely;
- broker state overrides stale local assumptions;
- unknown positions are handled according to configuration.

## 11.9 Strategy eligibility bugs

For every strategy, test whether it can actually become:

- eligible long;
- eligible short;
- ineligible for the correct reason.

Check for contradictory filters such as:

- requiring volatility expansion and compression simultaneously;
- requiring price to be both above and below the same boundary;
- requiring a confirmed breakout before allowing the breakout trigger;
- using thresholds whose scales do not match the calculated feature;
- comparing normalized values with raw price values;
- long logic copied into short logic without reversing comparisons.

## 11.10 Risk-lock bugs

Verify:

- daily limits use equity where intended;
- open losses are included;
- the reset cannot be triggered by restart;
- challenge mode cannot bypass account-level emergency protection;
- disabled strategies cannot place new orders;
- entry kill still allows management of existing positions;
- flatten-all cannot accidentally reopen positions on the next tick;
- manual emergency locks remain active after restart.

---

# 12. Strategy audit expectations

Each strategy must be audited independently.

For every strategy, produce:

- plain-English trading thesis;
- exact eligibility conditions;
- exact long setup;
- exact short setup;
- exact trigger;
- stop logic;
- target logic;
- management logic;
- rejection conditions;
- required features;
- possible repainting or lookahead risk;
- minimum history requirement;
- known regime weaknesses;
- whether the implementation matches the documented thesis.

Do not treat the presence of a class or function as proof that the strategy is complete.

Trace the complete code path from market data to signal output.

---

# 13. Regime-engine audit expectations

The regime engine is one of the most important parts of the system because it determines which strategy is allowed to trade.

Audit:

- feature normalization;
- threshold scales;
- contradictory classifications;
- unstable rapid switching;
- neutral-state handling;
- confidence calculation;
- trend exhaustion logic;
- volatility shock logic;
- balance classification;
- breakout acceptance;
- failed-breakout classification;
- session influence;
- liquidity classification.

Check whether the regime engine creates circular logic.

For example:

- a breakout strategy should not require a regime classification that can occur only after the breakout trade opportunity has already passed;
- mean reversion should not remain eligible after confirmed breakout acceptance;
- trend continuation should not remain eligible during explicit exhaustion.

---

# 14. Signal-arbitration audit expectations

The arbitrator must not create the illusion of intelligence through arbitrary scoring.

Audit:

- how scores are normalized;
- whether strategies produce comparable confidence values;
- how transaction costs affect the score;
- how conflicts are handled;
- how duplicate signals are detected;
- how existing positions affect eligibility;
- whether a stronger score can bypass hard risk rules;
- whether stale signals remain executable;
- whether multiple signals accidentally multiply exposure.

Hard risk rules must always dominate signal score.

---

# 15. Challenge-mode audit expectations

Challenge Mode is especially sensitive.

Audit:

- stage calculations;
- stage transition behavior;
- risk percentage per stage;
- equity versus balance usage;
- stage drawdown;
- daily loss;
- profit-lock behavior;
- maximum attempts;
- leverage limits;
- compounding;
- behavior after partial withdrawal or deposit;
- behavior after restart;
- behavior after reaching the final target;
- behavior after falling below the original balance.

Challenge Mode should pursue aggressive growth, but it must remain deterministic and bounded.

It must never silently increase risk due to:

- losses;
- state corruption;
- incorrect stage detection;
- failed order sizing;
- account deposits;
- floating equity spikes.

---

# 16. What may be simplified during the audit

The audit may simplify code when simplification:

- removes duplication;
- fixes state inconsistency;
- improves testability;
- improves runtime efficiency;
- reduces ambiguous logic;
- centralizes repeated validation;
- removes unused or fake functionality.

However, simplification must not remove core architectural separation.

Do not simplify by:

- merging all strategies into `OnTick()`;
- allowing strategies to place orders directly;
- removing reason codes;
- removing shadow mode;
- removing persistence;
- bypassing the risk engine;
- replacing recovery with local assumptions;
- converting regime logic into one moving-average condition;
- deleting tests because they fail;
- disabling features without reporting them.

---

# 17. What success looks like after the audit

The successful outcome is not:

> The EA compiles and opens trades.

The successful outcome is:

- the code compiles with zero errors and zero warnings;
- all critical code paths are reachable;
- trading calculations use correct broker-specific units;
- strategies behave symmetrically where intended;
- no future leakage exists;
- tester and live logic are aligned;
- risk cannot be bypassed;
- duplicate orders are prevented;
- open positions remain protected;
- restarts do not reset critical risk state;
- every strategy can be tested independently;
- every decision is journaled with a valid reason;
- known limitations are documented honestly;
- the system is ready for structured backtesting and shadow testing.

Profitability remains unproven until sufficient testing is completed.

---

# 18. Required audit output

Produce a detailed audit document with the following sections.

## Executive verdict

Choose:

- PASS
- CONDITIONAL PASS
- FAIL

## Critical defects

List defects that may cause:

- uncontrolled loss;
- duplicate orders;
- incorrect sizing;
- missing stops;
- future leakage;
- invalid backtests;
- recovery failure;
- risk-limit bypass.

## High-priority defects

List defects that materially affect:

- strategy logic;
- execution;
- regime classification;
- challenge mode;
- journaling;
- broker compatibility.

## Medium- and low-priority defects

List maintainability, performance, UI, documentation, and non-critical logic issues.

## Architecture assessment

State whether the actual implementation preserves:

- separation of strategies;
- centralized risk;
- centralized execution;
- position ownership;
- persistence;
- reconciliation;
- shared tester/live logic.

## Strategy-by-strategy verdict

For each strategy, state:

- implemented status;
- reachable status;
- long-side correctness;
- short-side correctness;
- repaint/lookahead status;
- logic defects;
- test readiness.

## Risk assessment

State whether:

- lot sizing is correct;
- account limits work;
- challenge stages work;
- open equity is handled;
- locks survive restart;
- kill switches function.

## Execution assessment

State whether:

- broker properties are dynamic;
- orders are normalized;
- filling modes are handled;
- retries are safe;
- duplicate prevention works;
- stops are guaranteed or emergency exits occur.

## Persistence and recovery assessment

State exactly what happens after:

- terminal restart;
- VPS restart;
- open position recovery;
- pending-order recovery;
- corrupted state;
- unknown position detection.

## Test evidence

Provide:

- tests run;
- scenarios covered;
- failures;
- logs;
- compile output;
- Strategy Tester evidence where available.

## Known limitations

Clearly separate:

- bugs;
- unimplemented features;
- broker limitations;
- Strategy Tester limitations;
- unvalidated strategy assumptions.

## Final readiness classification

Classify the EA as one of:

```text
NOT SAFE TO TEST
READY FOR DIAGNOSTIC MODE
READY FOR SHADOW MODE
READY FOR CONSERVATIVE MICRO-LIVE
READY FOR CHALLENGE-MODE RESEARCH
READY FOR CHALLENGE LIVE
```

Do not classify it as ready for Challenge Live without strong evidence for execution safety, recovery, and risk controls.

---

# 19. Final instruction to the auditing agent

Do not approach this as a normal indicator audit.

This is a high-risk automated trading system designed to eventually operate with real money and potentially aggressive leverage.

Treat every assumption as suspect.

Trace every important value from its source to its final effect.

Confirm behavior through code, logs, and tests rather than comments or filenames.

Do not protect previous work from criticism.

Do not preserve broken complexity merely because significant effort was spent building it.

Fix defects at their architectural source rather than patching symptoms.

The goal is not to defend the codebase.

The goal is to determine whether it can safely serve the original mission:

> A modular, explainable, broker-aware, aggressively capable XAUUSD trading system that can be scientifically tested for the possibility of rapidly growing a small account without relying on martingale, uncontrolled grids, hidden risk, repainting, or execution shortcuts.
