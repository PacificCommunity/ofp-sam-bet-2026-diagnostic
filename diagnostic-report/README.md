# BET 2026 Diagnostic model report

Submit one completed Diagnostic model job:

```sh
KFLOW_API_TOKEN=... python3 diagnostic-report/submit.py 19835
```

The report uses only that job's staged `model_payload.rds` and raw MFCL
outputs. It does not substitute the repository's committed reference model or
uncertainty files.

Outputs include a self-contained paper-ready HTML report, publication PNG/PDF
figures, CSV/LaTeX tables, figure/table indexes and an offline interactive
viewer. Report tables and figures include direct Word and LaTeX copy controls.

For a local build, set `DIAGNOSTIC_MODEL_DIR` and point `MFCLSHINY_REPO` to a
source checkout if required:

```sh
DIAGNOSTIC_MODEL_DIR=/path/to/model \
MFCLSHINY_REPO=/path/to/mfclshiny \
bash diagnostic-report/run.sh
```
