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
export RUN_DIR=${RUN_DIR:-outputs/${MODEL_ID}-tau2-fixed}
export PROGRAM_PATH=${PROGRAM_PATH:-/home/mfcl/mfclo64}
exec scripts/run-model fit
