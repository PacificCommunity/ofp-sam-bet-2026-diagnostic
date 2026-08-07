# BET 2026 Diagnostic model report

This directory builds the public report for Diagnostic Job 22974. The report
uses only repository-contained, compact inputs:

- `data/diagnostic-report-data.rds` contains the summarized Hessian, jitter,
  retrospective, self-test, ASPM and likelihood-profile results.
- `../results/reference/model_payload.rds` contains the fitted model output
  needed for the model-fit figures.

No Kflow job output is staged at report-render time. The compact RDS contains
no scheduler paths, access credentials or raw working directories.

## Outputs

The build creates:

- a tabbed public HTML report;
- a self-contained likelihood-profile viewer;
- 400-dpi PNG and vector PDF figures;
- CSV tables and LaTeX `longtable` fragments;
- an A4 PDF that compiles every LaTeX table fragment; and
- captions and a build manifest.

Hessian delta-method intervals are shown only where the required derivatives
are available. Length-composition bands are observation-level predictive
intervals, regional age-length bands describe fitted length-at-age
variability, and CPUE bands use the model's fixed regional log-scale
observation errors. These bands are labelled separately in the report.

## Local build

```sh
MFCLSHINY_REPO=/path/to/mfclshiny \
  REPORT_OUTPUT_DIR=diagnostic-report-output \
  bash diagnostic-report/run.sh
```

The Kflow task installs the pinned package revisions before invoking the report.
For a local build, install those revisions first; `MFCLSHINY_REPO` may point to
the matching source checkout when developing report figures.

## Kflow Local

The checked-in Kflow configuration targets the configured Kflow Local worker, not a remote cluster.

```sh
KFLOW_API_TOKEN=... python3 diagnostic-report/submit.py
```

Use `--dry-run` to inspect the submission payload without contacting Kflow.

## Rebuilding the compact payload

`R/prepare_public_payload.R` recreates the report RDS from the completed check
archives and applies the public-output audit. This preparation step is not
part of the report-render job because the public report is intentionally
independent of raw scheduler artifacts.
