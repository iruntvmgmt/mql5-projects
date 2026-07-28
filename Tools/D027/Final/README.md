# D027 final decision and robustness artifacts

`analyze_threshold_neighborhoods.py` performs offline adjacent-boundary
sensitivity using each trade's original entry-time continuous regime
measurements. It checks volatility at 0.75/0.80/0.85 and 1.15/1.20/1.25,
directional efficiency at 0.30/0.35/0.40 and 0.60/0.65/0.70, and compression
ratio at 0.30/0.35/0.40.

This is robustness description, not optimization: it does not relabel the
classifier, alter a frozen threshold, change a trigger, simulate different
cluster paths, or select the best neighbor. The formal final strategy and
regime-feature categories are emitted beside the threshold table. The tool
also completes the gated-variant anti-overfitting matrix: top 1/3/5,
best one/two quarters, monthly/quarterly returns, direction contribution,
and strongest entry-time regime contribution with exclusion.

Run:

```bash
python3 Tools/D027/Final/analyze_threshold_neighborhoods.py
```
