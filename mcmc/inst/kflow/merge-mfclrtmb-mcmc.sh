#!/usr/bin/env bash
set -euo pipefail

work_root="${KFLOW_WORK_ROOT:-${PWD}/work}"
output_root="${KFLOW_OUTPUT_ROOT:-${PWD}/outputs}"
library_root="${work_root}/R-library"

mkdir -p "$work_root" "$output_root" "$library_root"
export R_LIBS_USER="$library_root"
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

Rscript --vanilla - <<'RS'
repos <- c(CRAN = "https://cloud.r-project.org")
if (!requireNamespace("posterior", quietly = TRUE)) {
  install.packages("posterior", repos = repos, Ncpus = 2L)
}
stopifnot(requireNamespace("posterior", quietly = TRUE))
RS

echo "[mfclrtmb-mcmc-merge] Combining independent chains"
Rscript --vanilla mcmc/inst/kflow/merge-mfclrtmb-mcmc.R
