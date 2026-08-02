# Frozen model files

This directory is the complete input recipe for the BET 2026 **Diagnostic
model**. Do not run it in place. Use `../doitall`, which copies these files to
a fresh `run/` directory and uses either the pinned Docker image or a local
MFCL executable.

`doitall.sh` starts with `bet.ini -makepar`, runs all eleven estimation phases,
and applies the archived seed-23 checkpoints at Phases 1, 2 and 5 only after
their input hashes match the reference fit. The fitted output is `11.par`; the
root runner also saves it as `final.par`.

Run `../verify` before fitting to validate `MANIFEST.sha256`.

The frequency input explicitly declares that no weight-frequency data are
present (`WFIntervals`, `WFFirst`, and both `WFWidth` fields are zero). The
obsolete trailing WF missing-value field was removed from every fishery
record; all catch and length-frequency values are unchanged.

`doitall.sh` applies the archived seed-23 initialization by default. Set
`SEED23_INITIALIZATION=0` to start from the ordinary `bet.ini -makepar`
initialization without applying the seed-23 checkpoints.
