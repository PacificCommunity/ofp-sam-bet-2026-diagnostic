# Annual Hessian uncertainty

`annual-hessian-time-series.csv` and `quarterly-hessian-time-series.csv`
contain the verified annual and quarterly point estimates and nested pointwise
50%, 80% and 95% Hessian delta-method intervals used by the Diagnostic model
report. They cover depletion, spawning potential and recruitment for
1952--2024. `annual-fishing-mortality-hessian-time-series.csv` provides the
matching annual F/FMSY intervals.

The table was calculated from the Job 21641 final fit and the full MFCL
Hessian restored by Job 22196. MFCL dependent-variable gradients were
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

The annual F/FMSY table is generated separately because it requires the full
dependent-variable calculation (the compact calculation omits annual F rows):

```sh
Rscript diagnostic-report/R/generate_fishing_mortality_uncertainty.R \
  /path/to/full-dependent-variable-files \
  results/reference/uncertainty/annual-fishing-mortality-hessian-time-series.csv
```

It uses the same fitted parameters and full Hessian, with no model refit.

To propagate the derived table into the compact public report payload without
retaining raw MFCL output, run:

```sh
Rscript diagnostic-report/R/augment_public_payload_uncertainty.R \
  diagnostic-report/data/diagnostic-report-data.rds \
  results/reference/uncertainty/annual-fishing-mortality-hessian-time-series.csv \
  diagnostic-report/data/diagnostic-report-data.rds
```
