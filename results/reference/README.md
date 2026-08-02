# Reference fitted result

- `final.par`: fitted MFCL parameter file; use `./run-final` from the repository root.
- `fit-summary.csv`: objective, gradient, terminal depletion and provenance.
- `model_payload.rds`: compact Hessian-enriched model object used by the BET diagnostic viewer.
- `model_payload_manifest.csv` and `.json`: payload contents and fit statistics.
- `run-summary.csv`: final-stage and final-PAR checksum.
- `seed23-initialization-summary.csv`: Phase 1, 2 and 5 seed audit.
- `tag-tau-audit.csv`: retained tag, DM and natural-mortality controls.
- `hessian/bet.hes`: complete 1,997 by 1,997 native MFCL Hessian.
- `hessian/hessian_info.rds`: portable parameter-level Hessian diagnostics.
- `hessian/check-summary.csv`: partition completion and eigenvalue summary.
- `hessian/neigenvalues`: MFCL negative/total eigenvalue counts.
- `hessian/mfcl_*_log.txt`: retained stitch and eigen logs.
- `uncertainty/bet.var`: native all-period delta-method estimates and standard
  errors used by the Diagnostic report.

Run `../../run-final` to regenerate standard MFCL outputs and restore these
Hessian files without repeating the long calculation. Use `../../verify` to
validate all committed SHA-256 checksums.
