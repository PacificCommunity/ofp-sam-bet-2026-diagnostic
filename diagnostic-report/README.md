# BET 2026 Diagnostic model report

The report is built from Job 21641 or a model payload with the same final PAR.
It never falls back to the earlier tau=1 Diagnostic result.

Submit the report from the completed Diagnostic job:

```sh
KFLOW_API_TOKEN=... python3 diagnostic-report/submit.py 21641
```

For a local build:

```sh
DIAGNOSTIC_MODEL_DIR=/path/to/Job21641/model \
MFCLSHINY_REPO=/path/to/mfclshiny \
bash diagnostic-report/run.sh
```

The model directory must contain `model_payload.rds`; the payload must restore
the exact Job 21641 final PAR checksum. The matching Job 22020 Hessian,
restored with its full native matrix by Job 22196, is required. Both
`final.par` and `bet.hes` are checksum-verified before rendering.

Outputs include a self-contained paper-ready HTML report, 400-dpi PNG and
vector PDF figures, CSV and LaTeX tables, figure/table indexes and an offline
interactive viewer. Report tables and figures include Word and LaTeX copy
controls.

The Hessian figure includes annual depletion, spawning potential and
recruitment with nested pointwise 50%, 80% and 95% delta-method intervals.
Quarterly recruitment is
summed, spawning potential is averaged, and depletion is the annual mean of
the quarterly spawning-potential ratios. These transformations use the native
MFCL dependent-variable gradients and retain the full within-year covariance
rather than adding quarterly standard errors or confidence limits.

The verified reference table can be regenerated from the native `bet.dep`,
`bet.dp2`, label files and `bet.hes` with
`diagnostic-report/R/generate_annual_uncertainty.R`. Its checksum locks prevent
mixing gradients or a Hessian from another fit.
