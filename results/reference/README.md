# Reference fitted result

- `final.par`: fitted MFCL parameter file; use `./run-final` from the repository root.
- `fit-summary.csv`: objective, gradient, terminal depletion and provenance.
- `model_payload.rds`: compact model object used by the BET diagnostic viewer.
- `model_payload_manifest.csv` and `.json`: payload contents and fit statistics.
- `run-summary.csv`: final-stage and final-PAR checksum.
- `seed23-initialization-summary.csv`: Phase 1, 2 and 5 seed audit.
- `tag-tau-audit.csv`: retained tag, DM and natural-mortality controls.

These files came directly from the completed reference fit. Use `../../verify`
to validate their committed SHA-256 checksums.
