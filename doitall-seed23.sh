#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$root"
SEED23_INITIALIZATION=1 exec ./doitall "$@"
