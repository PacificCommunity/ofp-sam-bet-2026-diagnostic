BET 2026 DIAGNOSTIC MODEL — JOB 21641
====================================

This bundle uses fixed steepness h=0.90, Diagnostic F10/F33 weak selectivity
penalties, direct negative-binomial tau=2 fixed, and ordinary makepar with no
seed or checkpoint.

To evaluate the provided Job 21641 final.par:

  chmod +x mfclo64 run-final doitall.sh
  ./run-final

To refit the same model from the committed h=0.90 bet.ini:

  ./doitall.sh
