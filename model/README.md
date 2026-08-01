# Frozen model files

This directory is the complete input recipe for the BET 2026 **Diagnostic
model**. Do not run it in place. Use `../doitall`, which copies these files to
a fresh `run/` directory and uses either the pinned Docker image or a local
MFCL executable.

`doitall.sh` starts with `bet.ini -makepar`, runs all eleven estimation phases,
and applies the archived seed-23 checkpoints at Phases 1, 2 and 5 only after
their input hashes match Job 19835. The fitted output is `11.par`; the root
runner also saves it as `final.par`.

Run `../verify` before fitting to validate `MANIFEST.sha256`.
