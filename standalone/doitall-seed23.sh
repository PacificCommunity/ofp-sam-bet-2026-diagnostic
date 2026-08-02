#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$here"
SEED23_INITIALIZATION=1 exec sh ./.doitall-core "$@"
