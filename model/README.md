# Frozen Job 21641 model files

This directory is the complete BET 2026 Diagnostic Job 21641 recipe. Do not run
it in place; use `../doitall`, which copies it to a fresh directory.

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
