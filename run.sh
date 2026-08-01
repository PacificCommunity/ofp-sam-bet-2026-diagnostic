#!/bin/bash
set -euo pipefail
export RUN_DIR=${RUN_DIR:-outputs/Diagnostic-model}
export PROGRAM_PATH=${PROGRAM_PATH:-/home/mfcl/mfclo64}
exec scripts/run-model fit
