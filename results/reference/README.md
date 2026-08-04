# Job 21641 reference result

- `final.par`: exact fitted PAR from Kflow Job 21641.
- `fit-summary.csv`: objective, gradient, terminal depletion and provenance.
- `model_payload.rds`: current mfclshiny payload rebuilt from Job 21641 raw
  output after the Job 22020 Hessian attachment.
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

The original compact Kflow attachment did not contain the large native
`bet.hes`; Job 22196 restored it from all 60 verified partitions for report
rendering. This repository does not substitute files from the preceding tau=1
model. Use `../../verify` to validate every committed checksum.
