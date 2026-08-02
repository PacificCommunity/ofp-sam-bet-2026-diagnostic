BET 2026 DIAGNOSTIC MODEL - STANDALONE LINUX PACKAGE
====================================================

Everything needed to run the model is in this one directory. Use a Linux
x86-64 computer, or a Linux x86-64 environment such as WSL2.

First, open a terminal in this directory and run:

  chmod +x mfclo64 run-final doitall doitall-seed23 doitall-core

QUICK: EVALUATE THE PROVIDED FINAL PAR

  ./run-final

This uses final.par and writes evaluated.par, ests.rep,
plot-evaluated.par.rep, catch.rep, tag.rep, and the other MFCL reports into
this directory. It does not refit the model.

COMPLETE FIT: STANDARD MAKEPAR INITIALIZATION

  ./doitall

This follows the same model phases but does not apply the seed-23 initialization
checkpoints. It starts from the ordinary bet.ini -makepar values. The fitted PAR
is 11.par. This is also a long model fit.

COMPLETE FIT: REPRODUCE THE DIAGNOSTIC MODEL INITIALIZATION

  ./doitall-seed23

This starts at bet.ini -makepar and applies the archived seed-23 initialization
checkpoints at the documented phases. The fitted PAR is 11.par. This is a long
model fit.

The supplied mfclo64 is a statically linked Linux x86-64 executable. To use a
different compatible MFCL executable, set PROGRAM_PATH, for example:

  PROGRAM_PATH=/path/to/mfclo64 ./run-final

For a clean complete fit, use a newly extracted copy of this directory.
