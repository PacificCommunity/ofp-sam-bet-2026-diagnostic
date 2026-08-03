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
the exact Job 21641 final PAR checksum. The matching Job 22020 Hessian
attachment is required and is checked before the report is rendered.

Outputs include a self-contained paper-ready HTML report, 400-dpi PNG and
vector PDF figures, CSV and LaTeX tables, figure/table indexes and an offline
interactive viewer. Report tables and figures include Word and LaTeX copy
controls.

The compact Hessian attachment contains PDH/eigen diagnostics and marginal
standard errors for all 1,997 active parameters, but not a matching native
`bet.var`. The report therefore presents real parameter uncertainty and does
not invent confidence ribbons for derived biomass, depletion or recruitment.
