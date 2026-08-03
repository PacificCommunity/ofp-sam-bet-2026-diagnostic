#!/bin/bash
set -euo pipefail
export MODEL_ID=${MODEL_ID:-S0.80-F1}
case "$MODEL_ID" in
  S0.80-F1|S0.80-F2|S0.80-F3|S0.80-F4|S0.80-F5|S0.80-P1|S0.80-P2|S0.80-P3|S0.80-P4|\
  S0.85-F1|S0.85-F2|S0.85-F3|S0.85-F4|S0.85-F5|S0.85-P1|S0.85-P2|S0.85-P3|S0.85-P4|\
  S0.90-F1|S0.90-F2|S0.90-F3|S0.90-F4|S0.90-F5|S0.90-P1|S0.90-P2|S0.90-P3|S0.90-P4) ;;
  *)
    echo "MODEL_ID must be S0.80, S0.85 or S0.90 followed by F1-F5 or P1-P4." >&2
    exit 2
    ;;
esac
export RUN_DIR=${RUN_DIR:-work/${MODEL_ID}-tau2-fixed}
export PROGRAM_PATH=${PROGRAM_PATH:-/home/mfcl/mfclo64}
scripts/run-model fit

compact_dir=${COMPACT_OUTPUT_DIR:-outputs/${MODEL_ID}-tau2-fixed}
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
