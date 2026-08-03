# Paste immediately below #!/bin/sh or #!/bin/bash.
# Assumes mfclo64 is in the same folder and phases use the usual `-file -`.

tau2_dir=$(pwd)
cat > "$tau2_dir/.mfclo64-tau2" <<'TAU2_WRAPPER'
#!/bin/sh
real_mfcl="$(dirname "$0")/mfclo64"
controls=

if [ "${4:-}" = "-file" ] && [ "${5:-}" = "-" ]; then
  controls=$(mktemp)
  cat > "$controls"
  printf '%s\n' \
    '1 111 4' \
    '1 305 1' \
    '1 306 0' \
    '-999 43 0' \
    '-999 44 0' >> "$controls"
  if "$real_mfcl" "$@" < "$controls"; then status=0; else status=$?; fi
  rm -f "$controls"
else
  if "$real_mfcl" "$@"; then status=0; else status=$?; fi
fi

out_par=${3:-}
if [ -s "$out_par" ] && grep -q '^# extra fishery parameters' "$out_par"; then
  awk '
    /^# extra fishery parameters/ { extra=1; print; next }
    extra && /^#/ { print; next }
    extra && NF {
      row++
      if (row == 4) {
        for (i=1; i<=NF; i++) $i=0
        fixed=1
        extra=0
      }
    }
    { print }
    END { if (fixed != 1) exit 1 }
  ' "$out_par" > "$out_par.tau2" || exit 91
  mv "$out_par.tau2" "$out_par"
fi

exit "$status"
TAU2_WRAPPER

chmod +x "$tau2_dir/.mfclo64-tau2"
PROGRAM_PATH="$tau2_dir/.mfclo64-tau2"
MFCL_EXECUTABLE=$PROGRAM_PATH
program_path=$PROGRAM_PATH
program=$PROGRAM_PATH
export PROGRAM_PATH MFCL_EXECUTABLE
