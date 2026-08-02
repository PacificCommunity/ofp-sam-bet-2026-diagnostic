#!/bin/bash
set -euo pipefail

report_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir=${REPORT_OUTPUT_DIR:-$report_root/diagnostic-report-output}
report_lib=${R_LIBS_USER:-$report_root/diagnostic-report/.R-library}

mkdir -p "$report_lib"
export R_LIBS_USER=$report_lib

(
  cd "$report_root/results/reference/uncertainty"
  sha256sum -c SHA256SUMS
)

# Local development uses the source checkout directly. Kflow installs the
# exact public mfclshiny revision only when the container does not already
# provide the regional age-length growth and uncertainty report API.
if [ ! -d "${MFCLSHINY_REPO:-}" ]; then
  Rscript --vanilla - <<'RS'
lib <- Sys.getenv("R_LIBS_USER")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(lib, .libPaths())))
required_ref <- Sys.getenv(
  "MFCLSHINY_GITHUB_REF",
  "c861bce8c1d8c769d12d897e035765765880bafd"
)
has_api <- requireNamespace("mfclshiny", quietly = TRUE) &&
  all(c("plot_mfcl_age_length_fit", "plot_mfcl_age_length_growth") %in%
    getNamespaceExports("mfclshiny"))
if (!has_api) {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes", lib = lib, repos = "https://cloud.r-project.org")
  }
  remotes::install_github(
    paste0("PacificCommunity/mfclshiny@", required_ref),
    lib = lib,
    auth_token = Sys.getenv("GITHUB_PAT", Sys.getenv("GITHUB_TOKEN", "")),
    upgrade = "never",
    dependencies = NA,
    quiet = TRUE
  )
}
RS
fi

exec Rscript "$report_root/diagnostic-report/R/build_report.R" "$report_root" "$output_dir"
