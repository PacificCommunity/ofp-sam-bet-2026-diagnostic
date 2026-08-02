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
# provide the regional conditional age-at-length report API.
if [ ! -d "${MFCLSHINY_REPO:-}" ]; then
  Rscript --vanilla - <<'RS'
lib <- Sys.getenv("R_LIBS_USER")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(lib, .libPaths())))
required_ref <- Sys.getenv(
  "MFCLSHINY_GITHUB_REF",
  "987bb5d76efa513d82612ad73583ba614c535508"
)
has_api <- requireNamespace("mfclshiny", quietly = TRUE) &&
  "plot_mfcl_age_length_fit" %in% getNamespaceExports("mfclshiny") &&
  any(grepl(
    "region_mean_age",
    deparse(get("plot_mfcl_age_length_fit", envir = asNamespace("mfclshiny"))),
    fixed = TRUE
  ))
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
