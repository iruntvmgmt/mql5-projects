# Research Journal and Outcome-Label Schema

## Purpose

The journal must preserve enough information to determine which structural facts and strategy hypotheses are predictive without rerunning old builds or relying only on MT5 summary statistics.

## Record layers

### 1. Bar-state record

One row per evaluated closed bar:

```text
run_id,bar_index,time,symbol,timeframe,open,high,low,close,spread_points,tick_volume,
atr_fast,atr_medium,atr_slow,fast_leg,medium_leg,slow_leg,
fast_last_high_label,fast_last_low_label,medium_last_high_label,medium_last_low_label,
slow_last_high_label,slow_last_low_label,fast_support,fast_resistance,
medium_support,medium_resistance,slow_support,slow_resistance
```

### 2. Raw candidate record

One row per strategy interpretation:

```text
run_id,time,strategy_id,strategy_version,direction,origin_id,event_id,
entry_reference,structural_stop,target_reference,raw_score,
feature_break_distance_atr,feature_body_atr,feature_volume_ratio,
feature_line_age,feature_confluence_count,feature_compression_score,
passes_filters,rejection_reason
```

### 3. Opportunity-cluster record

```text
run_id,time,cluster_id,direction,origin_id,state,owner_strategy_id,
supporting_strategy_ids,evidence_mask,combined_score,canonical_stop,
selected,rejection_reason
```

### 4. Execution record

```text
run_id,cluster_id,order_id,position_id,decision_time,request_time,fill_time,
requested_price,fill_price,slippage_points,spread_points,volume,
stop,target,execution_status,retcode
```

### 5. Outcome labels

Outcomes must be computed for every selected shadow cluster, not only executed trades.

Fixed-horizon labels:

```text
return_1_bar,return_3_bars,return_5_bars,return_10_bars,return_20_bars
```

Excursion labels:

```text
mfe_points_5,mfe_points_10,mfe_points_20,
mae_points_5,mae_points_10,mae_points_20,
mfe_r_5,mfe_r_10,mfe_r_20,
mae_r_5,mae_r_10,mae_r_20
```

Barrier labels:

```text
stop_hit_first,target_hit_first,both_same_bar,neither_by_expiry,
bars_to_stop,bars_to_target
```

Structural labels:

```text
medium_confirmed_later,slow_confirmed_later,
opposite_fast_break_within_5,opposite_medium_break_within_10,
new_supporting_pivot_before_failure
```

## Same-bar ambiguity

When both stop and target occur inside one OHLC bar and tick order is unavailable:

- mark `both_same_bar=true`
- do not assume the favorable outcome
- either exclude from strict outcome analysis or use an explicitly conservative ordering

## Run identity

Every journal row includes a `run_id` derived from:

- commit SHA
- parameter manifest hash
- symbol/timeframe
- data interval
- execution model

Different parameter or code versions must never silently append into the same analytical run.

## Anti-leakage rule

Features are frozen at decision time. Outcome calculations may read future bars, but future values must only populate outcome columns and never overwrite feature columns.

## Required analyses

Per strategy and cluster owner:

- sample count
- expectancy in R
- median and distribution of MFE/MAE
- hit rate by fixed horizon
- performance by spread bucket
- performance by session
- performance by volatility regime
- long/short asymmetry
- parameter stability
- overlap with other strategies

No edge claim is allowed from combined-suite profitability alone.