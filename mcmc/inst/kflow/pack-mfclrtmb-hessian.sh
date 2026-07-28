#!/usr/bin/env bash
set -euo pipefail

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

mkdir -p "${KFLOW_OUTPUT_ROOT:-${PWD}/outputs}"
echo "[mfclrtmb-hessian-pack] Retaining only the verified full Hessian bundle"
Rscript --vanilla mcmc/inst/kflow/pack-mfclrtmb-hessian.R
