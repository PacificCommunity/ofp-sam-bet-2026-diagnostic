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

The compact Kflow attachment does not contain the large native `bet.hes` or a
derived `bet.var`; this repository does not substitute the preceding tau=1
files. `../../restore-hessian` restores the matching diagnostic metadata and
payload only. Use `../../verify` to validate every committed checksum.
