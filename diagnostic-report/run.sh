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

if [[ ! -d "${MFCLSHINY_REPO:-}" ]]; then
  runtime_root=$(mktemp -d)

  install_repo() {
    local package=$1
    local repo=$2
    local ref=$3
    local source_dir=$runtime_root/$package
    echo "[diagnostic-report] installing $package at $ref"
    GIT_TERMINAL_PROMPT=0 git clone --quiet --filter=blob:none "https://github.com/$repo.git" "$source_dir"
    GIT_TERMINAL_PROMPT=0 git -C "$source_dir" checkout --quiet "$ref"
    R CMD INSTALL -l "$report_lib" "$source_dir"
  }

  install_repo FLR4MFCL PacificCommunity/ofp-sam-flr4mfcl "${FLR4MFCL_GITHUB_REF:-ff8367fcec19baff98333170c0f1bca3f9903029}"
  install_repo mfclkit PacificCommunity/ofp-sam-mfclkit "${MFCLKIT_GITHUB_REF:-cf786007b5261f84faac8f3d24f7084bd323119d}"
  install_repo mfclshiny PacificCommunity/mfclshiny "${MFCLSHINY_GITHUB_REF:-a8dffd78de61c99af8cf5b1f6995e861157dc96c}"
fi

exec Rscript "$report_root/diagnostic-report/R/build_report.R" "$report_root" "$output_dir"
