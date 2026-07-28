# Reusable mfclrtmb MCMC workflow

This directory contains Kflow orchestration for running
`mfclrtmb`/SparseNUTS against any compatible fitted-model job. It does not
contain a model-specific job number, objective value, parameter count, root
name, or final-PAR checksum.

The exact `mfclrtmb` v0.3.2 source release used by the workers is bundled in
`vendor/` with a checked SHA-256. This makes Kflow execution reproducible and
avoids requiring runtime OAuth access to the private package repository.

`scripts/submit-kflow-pipeline.py` registers all three tasks and submits the
complete dependency graph from one command. A server-side smoke test can be
run first:

```bash
python3 mcmc/scripts/submit-kflow-pipeline.py \
  --source-job SOURCE_JOB \
  --hessian-job FULL_HESSIAN_JOB \
  --model-selector MODEL_LABEL \
  --model-root MODEL_ROOT \
  --stage smoke
```

After the smoke job completes, reuse its compact pack for the full workflow:

```bash
python3 mcmc/scripts/submit-kflow-pipeline.py \
  --source-job SOURCE_JOB \
  --hessian-pack-job COMPACT_PACK_JOB \
  --model-selector MODEL_LABEL \
  --model-root MODEL_ROOT \
  --stage full
```

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
- a direct native `indepvar.rpt` or `xinit.rpt` order manifest;
- a complete semantic-label native-to-mfclrtmb permutation, including
  matrix row/column indices and duplicate-label occurrences.

Each chain runs in its own 16 GB Kflow job because the BET objective uses about
8 GB per process. The merge task combines completed chains, calculates R-hat
and ESS, and saves posterior time series, reference points, depletion outputs,
plots, and an HTML report.

For native preconditioning, `kflow-hessian-pack.yaml` first reduces the large
partition/merge archive to the four files required by every chain: the full
Hessian, its verified diagnostic metadata, the matching final PAR, and the
native parameter-order manifest. The pack task generates the last file with a
zero-iteration native evaluation when it is not already present. This avoids
copying the Hessian parts and repeated logs into every chain job.

`mfclrtmb` remains the standalone estimation engine. It can use `.hes`, its
matching `final.par`, and `indepvar.rpt`/`xinit.rpt` without Kflow or
`hessian_info.rds`; the latter is only an optional cross-check. The native
Hessian itself is an optional pilot preconditioner, not a runtime dependency
of the package.
