#!/usr/bin/env bash
set -euo pipefail

report_root=$(cd "$(dirname "$0")/.." && pwd)
output_dir=${REPORT_OUTPUT_DIR:-$report_root/diagnostic-report-output}
report_lib=${R_LIBS_USER:-$report_root/diagnostic-report/.R-library}

case "$output_dir" in /*) ;; *) output_dir=$report_root/$output_dir ;; esac
mkdir -p "$output_dir" "$report_lib"
export R_LIBS_USER=$report_lib
if [[ ! -s "$report_root/results/reference/model_payload.rds" ]]; then
  echo "Missing repository model payload: results/reference/model_payload.rds" >&2
  exit 2
fi
if [[ ! -s "$report_root/diagnostic-report/data/diagnostic-report-data.rds" ]]; then
  echo "Missing compact diagnostic report payload." >&2
  exit 2
fi
export DIAGNOSTIC_REPORT_DPI=${DIAGNOSTIC_REPORT_DPI:-400}

Rscript -e '
  required <- c("FLR4MFCL", "mfclkit", "mfclshiny")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop(
      "Missing Kflow runtime package(s): ", paste(missing, collapse = ", "),
      ". Install the pinned revisions before running the report.",
      call. = FALSE
    )
  }
'

exec Rscript "$report_root/diagnostic-report/R/build_report.R" "$report_root" "$output_dir"
