#!/usr/bin/env bash
set -euo pipefail

report_root=$(cd "$(dirname "$0")/.." && pwd)
input_dir=${INPUT_DIR:-${KFLOW_INPUT_DIR:-$report_root/inputs}}
output_dir=${REPORT_OUTPUT_DIR:-$report_root/diagnostic-report-output}
report_lib=${R_LIBS_USER:-$report_root/diagnostic-report/.R-library}

case "$input_dir" in /*) ;; *) input_dir=$report_root/$input_dir ;; esac
case "$output_dir" in /*) ;; *) output_dir=$report_root/$output_dir ;; esac
mkdir -p "$input_dir" "$output_dir" "$report_lib"
export R_LIBS_USER=$report_lib

if [[ -n "${DIAGNOSTIC_MODEL_DIR:-}" ]]; then
  model_dir=$DIAGNOSTIC_MODEL_DIR
  case "$model_dir" in /*) ;; *) model_dir=$report_root/$model_dir ;; esac
else
  mapfile -t payloads < <(find "$input_dir" -type f -name model_payload.rds -print | sort)
  if [[ ${#payloads[@]} -ne 1 ]]; then
    echo "Expected exactly one staged Diagnostic model payload; found ${#payloads[@]} under $input_dir" >&2
    exit 2
  fi
  model_dir=$(dirname "${payloads[0]}")
fi
if [[ ! -s "$model_dir/model_payload.rds" ]]; then
  echo "Missing Diagnostic model payload: $model_dir/model_payload.rds" >&2
  exit 2
fi
export DIAGNOSTIC_MODEL_DIR=$model_dir

if [[ ! -d "${MFCLSHINY_REPO:-}" ]]; then
  runtime_root=$(mktemp -d)
  askpass_file=""
  cleanup_runtime() {
    [[ -z "$askpass_file" ]] || rm -f "$askpass_file"
    rm -rf "$runtime_root"
  }
  trap cleanup_runtime EXIT

  runtime_token=""
  for token_name in GITHUB_PAT GH_TOKEN GITHUB_TOKEN KFLOW_GITHUB_TOKEN KFLOW_PERSONAL_TOKEN; do
    if [[ -n "${!token_name:-}" ]]; then runtime_token=${!token_name}; break; fi
  done
  if [[ -n "$runtime_token" ]]; then
    askpass_file=$(mktemp)
    printf '%s\n' '#!/bin/sh' 'case "$1" in *Username*) printf "%s\n" x-access-token ;; *) printf "%s\n" "$KFLOW_REPORT_GIT_TOKEN" ;; esac' > "$askpass_file"
    chmod 700 "$askpass_file"
  fi

  install_repo() {
    local package=$1
    local repo=$2
    local ref=$3
    local source_dir=$runtime_root/$package
    echo "[diagnostic-report] installing $package at $ref"
    if [[ -n "$runtime_token" ]]; then
      GIT_ASKPASS=$askpass_file GIT_TERMINAL_PROMPT=0 KFLOW_REPORT_GIT_TOKEN=$runtime_token \
        git clone --quiet --filter=blob:none "https://github.com/$repo.git" "$source_dir"
      GIT_ASKPASS=$askpass_file GIT_TERMINAL_PROMPT=0 KFLOW_REPORT_GIT_TOKEN=$runtime_token \
        git -C "$source_dir" checkout --quiet "$ref"
    else
      GIT_TERMINAL_PROMPT=0 git clone --quiet --filter=blob:none "https://github.com/$repo.git" "$source_dir"
      GIT_TERMINAL_PROMPT=0 git -C "$source_dir" checkout --quiet "$ref"
    fi
    R CMD INSTALL -l "$report_lib" "$source_dir"
  }

  install_repo FLR4MFCL PacificCommunity/ofp-sam-flr4mfcl "${FLR4MFCL_GITHUB_REF:-ff8367fcec19baff98333170c0f1bca3f9903029}"
  install_repo mfclkit PacificCommunity/ofp-sam-mfclkit "${MFCLKIT_GITHUB_REF:-cf786007b5261f84faac8f3d24f7084bd323119d}"
  install_repo mfclshiny PacificCommunity/mfclshiny "${MFCLSHINY_GITHUB_REF:?MFCLSHINY_GITHUB_REF is required}"
fi

exec Rscript "$report_root/diagnostic-report/R/build_report.R" "$report_root" "$output_dir"
