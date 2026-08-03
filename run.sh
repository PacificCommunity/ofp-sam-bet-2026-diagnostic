#!/bin/bash
set -euo pipefail
export MODEL_ID=${MODEL_ID:-Diagnostic}
if [[ $MODEL_ID != Diagnostic ]]; then
  echo "MODEL_ID must remain Diagnostic (the Job 21641 model)." >&2
  exit 2
fi
export RUN_DIR=${RUN_DIR:-work/Diagnostic}
export PROGRAM_PATH=${PROGRAM_PATH:-/home/mfcl/mfclo64}
scripts/run-model fit

compact_dir=${COMPACT_OUTPUT_DIR:-outputs/Diagnostic}
if [[ -e $compact_dir ]] && [[ -n $(find "$compact_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]; then
  echo "Compact output directory is not empty: $compact_dir" >&2
  exit 2
fi
mkdir -p "$compact_dir"
for name in \
  model_payload.rds \
  model_payload_manifest.json \
  model_payload_manifest.csv \
  payload-restore-audit.json \
  payload-restore-audit.csv \
  payload-restore-audit.rds \
  README.txt \
  final.par.sha256 \
  model_info.rds \
  mfclkit_diagnostics.rds \
  tag-tau-audit.csv \
  fishery_map.R \
  tag_rep_map.R
do
  [[ ! -s "$RUN_DIR/$name" ]] || cp "$RUN_DIR/$name" "$compact_dir/$name"
done
test -s "$compact_dir/model_payload.rds"
test -s "$compact_dir/model_payload_manifest.json"
test -s "$compact_dir/payload-restore-audit.json"
(
  cd "$compact_dir"
  sha256sum * > compact-output.sha256
)
echo "Compact restorable model output ready: $compact_dir"
