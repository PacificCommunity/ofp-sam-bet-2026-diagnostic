# BET 2026 Diagnostic model report

The report is built from the Diagnostic model payload with the committed final PAR.
It never falls back to the earlier tau=1 Diagnostic result.

Submit the report from the completed Diagnostic job:

```sh
KFLOW_API_TOKEN=... python3 diagnostic-report/submit.py MODEL_JOB
```

For a local build:

```sh
DIAGNOSTIC_MODEL_DIR=/path/to/model \
MFCLSHINY_REPO=/path/to/mfclshiny \
bash diagnostic-report/run.sh
```

The model directory must contain `model_payload.rds`; the payload must restore
the committed final PAR checksum. The matching native Hessian matrix is
required. Both
`final.par` and `bet.hes` are checksum-verified before rendering.

Outputs include a self-contained paper-ready HTML report, 400-dpi PNG and
vector PDF figures, CSV and LaTeX tables, figure/table indexes and an offline
interactive viewer. Report tables and figures include Word and LaTeX copy
controls.

The Hessian section includes separate annual and quarterly figures for
depletion, spawning potential and recruitment with nested pointwise 50%, 80%
and 95% delta-method intervals.
Quarterly recruitment is
summed, spawning potential is averaged, and depletion is the annual mean of
the quarterly spawning-potential ratios. These transformations use the native
MFCL dependent-variable gradients and retain the full within-year covariance
rather than adding quarterly standard errors or confidence limits.

The verified reference table can be regenerated from the native `bet.dep`,
`bet.dp2`, label files and `bet.hes` with
`diagnostic-report/R/generate_annual_uncertainty.R`. The generator writes both
annual and quarterly reference tables; its checksum locks prevent mixing
gradients or a Hessian from another fit.
