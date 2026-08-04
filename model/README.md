# Frozen Job 21641 model files

This directory is the complete input recipe for the BET 2026 **tau=2 fixed-
steepness and selectivity Diagnostic model**. Do not run it in place. Use
`../doitall`, which copies these files to a fresh run directory and starts
from ordinary `bet.ini -makepar` initialization. The main workflow uses the
single explicit `Diagnostic` input matching Job 21641
(steepness 0.90 with the F10 and F33 weak non-decreasing selectivity setting).

The committed `bet.ini` is the effective Job 21641 INI and contains
`sv(29)=0.90`. `model-inputs/Diagnostic.conf` selects the single explicit
33-row `selectivity-models/Diagnostic.csv`: all fisheries remain independent,
with weak non-decreasing penalties 10,000 on F10 and F33.

`doitall.sh` starts from ordinary `bet.ini -makepar`, applies no seed, jitter or
fitted checkpoint, and fixes direct negative-binomial `tau=2`. It audits tau,
steepness, Lorenzen M, DM concentration and Diagnostic selectivity after every
fitted phase. The final fitted file is `11.par`.

The FRQ declares no weight-frequency observations. Removing the obsolete WF
header dimensions and trailing missing-value placeholder did not alter catch,
effort or length-frequency observations.

Run `../verify` before fitting to validate all hashes.
