# Frozen model files

This directory is the complete input recipe for the BET 2026 **Diagnostic
model: tau fixed at 2** exploration. Do not run it in place. Use `../doitall`,
which copies these files to a fresh `run/` directory and starts from the
ordinary `bet.ini -makepar` initialization.

`doitall.sh` starts with `bet.ini -makepar` and runs all eleven estimation
phases without jitter or seed-23 checkpoints. Immediately after makepar it sets
all 33 copies of `fish_pars(4)` to zero. Phase 1 selects the direct negative-
binomial parameterization (`parest 305=1`) and fixes fish flags 43/44 at zero,
so `tau = 1 + exp(0) = 2`. Every phase verifies that these settings persist.
The fitted output is `11.par`; the root runner also saves it as `final.par`.

Run `../verify` before fitting to validate `MANIFEST.sha256`.

The frequency input explicitly declares that no weight-frequency data are
present (`WFIntervals`, `WFFirst`, and both `WFWidth` fields are zero). The
obsolete trailing WF missing-value field was removed from every fishery
record; all catch and length-frequency values are unchanged.

The archived seed-23 files are retained only as provenance for the main-branch
Diagnostic fit. This exploration does not read or apply them.
