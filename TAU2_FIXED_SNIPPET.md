# Portable MFCL fixed-tau=2 snippet

This pattern can be inserted into a shell `doitall` that creates its initial
PAR with `-makepar`. It does not depend on the number of fisheries.

Immediately after the `-makepar` command, write every copy of
`fish_pars(4)` to zero:

```sh
fix_tau2_value()
{
  input_par=$1
  output_par=$2
  awk '
    /^# extra fishery parameters/ { in_extra=1; print; next }
    in_extra && /^#/ { print; next }
    in_extra && NF {
      row++
      if (row == 4) {
        for (i=1; i<=NF; i++) printf "%s%s", 0, (i == NF ? "\n" : " ")
        changed=1
        in_extra=0
        next
      }
    }
    { print }
    END { if (changed != 1) exit 1 }
  ' "$input_par" > "$output_par"
}

$program_path bet.frq bet.ini 00.par -makepar
fix_tau2_value 00.par 00.tau2.par
```

Use `00.tau2.par`, not `00.par`, as the input to the first optimization phase.
Add these switches to that phase's existing switch file or here-document:

```text
  1 111 4
  1 305 1
  1 306 0
  -999 43 0
  -999 44 0
```

Their meanings are:

- parest 111 = 4: negative-binomial tag likelihood;
- parest 305 = 1: direct parameterization, `tau=1+exp(fish_pars(4))`;
- parest 306 = 0: default bounds, inactive because tau is fixed;
- fish flags 43/44 = 0: do not estimate or group `fish_pars(4)`.

Under parest 305 = 1, `fish_pars(4)=0` gives `tau=1+exp(0)=2`. The same
interpretation is not valid under the legacy parest 305 = 0 branch.

This audit can be called after every phase:

```sh
audit_tau2_fixed()
{
  par_file=$1
  awk '
    /^# The parest_flags/ {
      getline
      p111=$111; p305=$305; p306=$306
    }
    /^# fish flags/ { in_flags=1; next }
    in_flags && /^#/ { in_flags=0 }
    in_flags && NF {
      fisheries++
      active43 += $43
      active44 += $44
      next
    }
    /^# extra fishery parameters/ { in_extra=1; next }
    in_extra && /^#/ { next }
    in_extra && NF {
      row++
      if (row == 4) {
        copies=NF
        for (i=1; i<=NF; i++) if ($i < -1e-12 || $i > 1e-12) nonzero++
        in_extra=0
      }
    }
    END {
      ok=(p111 == 4 && p305 == 1 && p306 == 0 && fisheries > 0 &&
          active43 == 0 && active44 == 0 && copies == fisheries && nonzero == 0)
      if (!ok)
        printf "tau audit failed: p111/p305/p306=%s/%s/%s; fisheries=%d; flags43/44=%d/%d; fish_pars4=%d nonzero=%d\n",
          p111, p305, p306, fisheries, active43, active44, copies, nonzero > "/dev/stderr"
      exit(ok ? 0 : 1)
    }
  ' "$par_file"
}
```

For the final phase, also confirm that `indepvar.rpt` contains no active tau
parameter:

```sh
if awk '$2 ~ /^fish_pars[(]4[)]/ { found=1 } END { exit(found ? 0 : 1) }' indepvar.rpt; then
  echo "fish_pars(4) is still estimated" >&2
  exit 1
fi
```
