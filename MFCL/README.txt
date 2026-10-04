BET 2026 DIAGNOSTIC MODEL — JOB 21641
====================================

This one-directory bundle uses fixed steepness h=0.90, Diagnostic F10/F33
weak selectivity penalties, direct negative-binomial tau=2 fixed, and the
exact Job 21641 fitting sequence with no seed or checkpoint.

The ten files needed to refit and evaluate the final PAR are all in this
directory:

  bet.age_length  bet.frq  bet.ini  bet.reg_scaling  bet.tag  mfcl.cfg
  mfclo64  doitall.sh  final.par  run-final

No model .conf, selectivity CSV, downloaded checkpoint or file from another
directory is required at run time.

The distributed directory already contains every file produced by one native
evaluation of the provided Job 21641 final.par, not just the five REP files.
This includes 10.par, 11.par, fishmort, fishmort2, gradient and independent-
variable reports, CPUE files, selectivity and recruitment outputs, diagnostic
logs, and all other native files written by that evaluation. SHA256SUMS is the
complete archive inventory.

To repeat the evaluation and reproduce the complete output set:

  chmod +x mfclo64 run-final doitall.sh
  ./run-final

This preserves final.par, stages a checksum-verified byte copy as 10.par, and
writes 11.par plus the complete native output set. The 10.par name reproduces
the original Phase-11 report headers; it does not change a parameter. The five
canonical REP files and fishmort2 are checksum-identical to the original Kflow
Job 21641 outputs. Runtime logs contain paths, timings and memory addresses, so
their checksums can change on a repeat run even when scientific outputs agree.

To refit the same model from the committed h=0.90 bet.ini:

  ./doitall.sh

This is the original Job 21641 process: bet.ini is copied byte-for-byte to the
run-local bet.model.ini, MFCL creates 00.par with -makepar, the fixed tau and
DM initial values are materialized in 00.fixed.par, and the unchanged Phase
1--11 controls are run. These are normal files generated in this directory;
no external input replacement occurs.

To prove that final.par itself is accepted directly by MFCL, it can also be
used as the native input name:

  printf '%s\n' '1 1 1' '1 50 -4' '1 121 0' '1 246 1' | \
    ./mfclo64 bet.frq final.par evaluated.par -file -

Use ./run-final when the original Job 21641 REP filenames and byte-identical
report files are required.
