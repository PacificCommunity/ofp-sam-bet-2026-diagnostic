# Paste-at-top MFCL fixed-tau=2 header

Copy all of [`TAU2_FIXED_HEADER.sh`](TAU2_FIXED_HEADER.sh) immediately below the
target `doitall` shebang. It assumes `mfclo64` is in the same folder and the
phases use the standard `-file -` here-document form. The rest of the `doitall`
does not need to be edited.

The small wrapper appends these controls to every phase:

```text
1 111 4
1 305 1
1 306 0
-999 43 0
-999 44 0
```

It also writes all copies of `fish_pars(4)` to zero after `-makepar` and every
later phase. Under the direct parameterization this fixes
`tau = 1 + exp(fish_pars(4)) = 2` and keeps tau out of estimation.
