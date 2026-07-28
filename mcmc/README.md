# Reusable mfclrtmb MCMC workflow

This directory contains Kflow orchestration for running
`mfclrtmb`/SparseNUTS against any compatible fitted-model job. It does not
contain a model-specific job number, objective value, parameter count, root
name, or final-PAR checksum.

The exact `mfclrtmb` v0.3.1 source release used by the workers is bundled in
`vendor/` with a checked SHA-256. This makes Kflow execution reproducible and
avoids requiring runtime OAuth access to the private package repository.

At submission time, provide:

- `MCMC_SOURCE_JOB`: the fitted-model Kflow job number;
- `input_jobs`: the source job and, when requested, a matching Hessian-export
  job;
- `MCMC_MODEL_SELECTOR`: only when an input archive contains more than one
  distinct model;
- `MCMC_PRECONDITIONER`: `adaptive` for standalone mfclrtmb sampling or
  `native` to use a verified matching native MFCL Hessian.

The chain runner derives the model root, objective, final-PAR checksum, and
parameter count from the selected source archive. With `native`, it also
requires:

- a full positive-definite Hessian;
- the Hessian's `final.par` to have the same SHA-256 as the selected model;
- a complete native-to-mfclrtmb parameter-order permutation.

Each chain runs in its own 16 GB Kflow job because the BET objective uses about
8 GB per process. The merge task combines completed chains, calculates R-hat
and ESS, and saves posterior time series, reference points, depletion outputs,
plots, and an HTML report.

For native preconditioning, `kflow-hessian-pack.yaml` first reduces the large
partition/merge archive to the three files actually required by every chain:
the full Hessian, its verified diagnostic metadata, and the matching final PAR.
This avoids copying the 70 Hessian parts and repeated logs into ten chain jobs.

`mfclrtmb` remains the standalone estimation engine. The native Hessian is an
optional pilot preconditioner and is not a runtime dependency of the package.
