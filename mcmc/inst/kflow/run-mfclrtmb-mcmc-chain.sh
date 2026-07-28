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

mfclrtmb_tarball="${MFCLRTMB_TARBALL:-mcmc/vendor/mfclrtmb_0.3.1.tar.gz}"
mfclrtmb_sha256="${MFCLRTMB_SHA256:-13c1919d1f92291b2cfc88fdbb98d210544cfc2b5a62b6eb23f384211a734a89}"

if [[ ! -f "$mfclrtmb_tarball" ]]; then
  echo "[mfclrtmb-mcmc] Missing bundled mfclrtmb source: $mfclrtmb_tarball" >&2
  exit 1
fi

actual_sha256="$(sha256sum "$mfclrtmb_tarball" | awk '{print $1}')"
if [[ "$actual_sha256" != "$mfclrtmb_sha256" ]]; then
  echo "[mfclrtmb-mcmc] mfclrtmb source checksum mismatch" >&2
  echo "expected=$mfclrtmb_sha256 actual=$actual_sha256" >&2
  exit 1
fi

echo "[mfclrtmb-mcmc] Installing bundled standalone mfclrtmb v0.3.1"
Rscript --vanilla - <<'RS'
repos <- c(
  andrjohns = "https://andrjohns.r-universe.dev",
  stan = "https://stan-dev.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
)
if (!requireNamespace("remotes", quietly = TRUE)) {
  install.packages("remotes", repos = repos[["CRAN"]])
}
missing_binary <- setdiff(c("StanEstimators"), rownames(installed.packages()))
if (length(missing_binary)) {
  install.packages(missing_binary, repos = repos, Ncpus = 2L)
}
if (!requireNamespace("SparseNUTS", quietly = TRUE)) {
  remotes::install_github(
    "noaa-afsc/SparseNUTS",
    dependencies = NA,
    upgrade = "never"
  )
}
RS

R CMD INSTALL \
  --no-multiarch \
  --with-keep.source \
  --library="$library_root" \
  "$mfclrtmb_tarball"

Rscript --vanilla - <<'RS'
stopifnot(
  requireNamespace("StanEstimators", quietly = TRUE),
  requireNamespace("SparseNUTS", quietly = TRUE),
  requireNamespace("mfclrtmb", quietly = TRUE)
)
RS

echo "[mfclrtmb-mcmc] Starting source-job posterior chain"
Rscript --vanilla mcmc/inst/kflow/run-mfclrtmb-mcmc-chain.R
