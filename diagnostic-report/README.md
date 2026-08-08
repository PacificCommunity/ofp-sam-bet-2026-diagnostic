# BET 2026 Diagnostic model report

This directory builds the public diagnostic-model report. The report uses only
repository-contained, compact inputs:

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
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "$PWD:/work" \
  --workdir /work \
  --entrypoint /bin/bash \
  ghcr.io/pacificcommunity/tuna-flow-private:v2.7@sha256:4fee4c40cb6439ff920b1dd233a84bf19d5cc0e37278c99ceff3fd79cb9c8852 \
  -lc 'bash diagnostic-report/run.sh'
```

The same pinned TunaFlow v2.7 image is used by the report GitHub Action.

## Standalone likelihood-profile viewer

The [GitHub Pages viewer](https://pacificcommunity.github.io/ofp-sam-bet-2026-diagnostic/bet-2026-likelihood-profile-viewer.html)
is one self-contained HTML file: its data and logos are embedded, so it can be
opened in a browser without adjacent assets. Rebuild it
directly from the public compact payload without running the static-figure
exporter:

```sh
Rscript diagnostic-report/R/build_likelihood_profile_viewer.R . viewer-output
```

The command writes `viewer-output/bet-2026-likelihood-profile-viewer.html`.

## Rebuilding the compact payload

`R/prepare_public_payload.R` recreates the report RDS from completed check
archives and applies the public-output audit. The preparation command requires
a local, git-ignored source map that associates scientific roles with archived
run directories. This keeps internal execution references out of the public
repository while preserving an auditable local rebuild path. Preparation is
not part of the report-render job because the public report is intentionally
independent of raw scheduler artifacts.
