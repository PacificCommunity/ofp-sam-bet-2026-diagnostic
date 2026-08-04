# Frozen model files

This directory is the complete input recipe for the BET 2026 **tau=2 fixed-
steepness and selectivity grid**. Do not run it in place. Use `../doitall`,
which copies these files to a fresh run directory and starts from ordinary
`bet.ini -makepar` initialization. `MODEL_ID` selects one of the 27 files in
`model-inputs/`; the default Diagnostic model is `S0.90-F2`, matching Job 21641
(steepness 0.90 with the F10 and F33 weak non-decreasing selectivity setting).

`doitall.sh` starts with `bet.ini -makepar` and runs all eleven estimation
phases without jitter or seed-23 checkpoints. Immediately after makepar it sets
all 33 copies of `fish_pars(4)` to zero. Phase 1 selects the direct negative-
binomial parameterization (`parest 305=1`) and fixes fish flags 43/44 at zero,
so `tau = 1 + exp(0) = 2`. Every phase verifies that these settings persist.
The selected model input also writes fixed `sv(29)` into `bet.model.ini` and
keeps age flag 162 at zero. The fitted output is `11.par`; the root runner also
saves it as `final.par`.

Run `../verify` before fitting to validate `MANIFEST.sha256`.

The frequency input explicitly declares that no weight-frequency data are
present (`WFIntervals`, `WFFirst`, and both `WFWidth` fields are zero). The
obsolete trailing WF missing-value field was removed from every fishery
record; all catch and length-frequency values are unchanged.

No seed or checkpoint file is included in this model directory. The
`results/reference/` directory at repository root contains baseline Diagnostic
artifacts only and is not copied into a fit.
