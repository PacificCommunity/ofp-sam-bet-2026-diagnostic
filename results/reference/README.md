# Diagnostic model reference result

- `final.par`: exact fitted PAR for the Diagnostic model.
- `fit-summary.csv`: objective, gradient, terminal depletion and provenance.
- `model_payload.rds`: compact MFCL Shiny payload for the Diagnostic model.
- `model_payload_manifest.csv` and `.json`: payload contents, fit statistics
  and Hessian status.
- `payload-restore-audit.csv`: checksum proof for the PAR restored from the
  payload.
- `run-summary.csv`: final-stage and source checksums.
- `tag-tau-audit.csv`: fixed tau, DM and natural-mortality controls.
- `hessian/hessian_info.rds`: portable parameter-level Hessian diagnostics.
- `hessian/check-summary.csv`: 60-partition completion and eigenvalue summary.
- `hessian/check-unit-status.csv`: status of every partition.
- `hessian/neigenvalues` and `hessian/mfcl_*_log.txt`: native eigen and stitch
  records.
- `uncertainty/annual-hessian-time-series.csv`: annual native-MFCL estimates
  with nested 50%, 80% and 95% Hessian delta-method intervals.
- `uncertainty/quarterly-hessian-time-series.csv`: matching quarterly estimates
  and intervals before annual aggregation.

The native `bet.hes` and all 60 verified Hessian partitions are retained for
report rendering. This repository does not substitute files from the preceding
tau=1 model. Use `../../verify` to validate every committed checksum.
