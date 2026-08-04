# Annual Hessian uncertainty

`annual-hessian-time-series.csv` and `quarterly-hessian-time-series.csv`
contain the verified annual and quarterly point estimates and nested pointwise
50%, 80% and 95% Hessian delta-method intervals used by the Diagnostic model
report. They cover depletion, spawning potential and recruitment for
1952--2024.

The table was calculated from the Job 21641 final fit and the full native MFCL
Hessian restored by Job 22196. Native MFCL dependent-variable gradients were
used for the fitted and zero-fishing trajectories. Quarterly spawning potential
was averaged, quarterly recruitment was summed, and annual depletion was formed
as the annual mean of the quarterly spawning-potential ratios. The corresponding
quarterly gradients were transformed together, retaining their full within-year
covariance.

The source hashes are recorded on every row. Regenerate the table with:

```sh
Rscript diagnostic-report/R/generate_annual_uncertainty.R \
  /path/to/native-gradient-files \
  /path/to/native-timeseries.csv \
  results/reference/uncertainty/annual-hessian-time-series.csv \
  results/reference/uncertainty/quarterly-hessian-time-series.csv
```

The gradient directory must contain `final.par`, `bet.hes`, `bet.dep`,
`bet.dp2`, `deplabel.tmp` and `deplabel_noeff.tmp`. The generator refuses files
whose checksums do not match the verified Diagnostic model.
