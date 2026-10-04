# Profile and ASPM native files

This bundle retains 44 original likelihood-profile final PARs and the constant
ASPM final PAR. The scalar-100 anchor, six MFCL inputs, executable and original
Diagnostic `doitall` reuse checksum-verified public Git files.

On 64-bit x86 Linux, from the Diagnostic repository root:

```sh
python3 reproduce/run-native.py profiles /tmp/bet-profile
python3 reproduce/run-native.py aspm-constant /tmp/bet-aspm
```

Choose `profile-75` for one point, or `available` for all 46 preserved cases.
Each run uses one function evaluation, checks the original reported objective,
and leaves the saved PAR and inputs unchanged. Profile objectives use the
original zero-penalty switches. Generated native outputs stay in the new folder;
Hessian and full REP byte identity are outside this check.

`python3 reproduce/restore.py --verify` checks the small PAR archive.
`validation.json` retains the original profile switches; `source-status.json`
links the original controllers. The generated profile continuation scripts were
not retained. The fitted ASPM terminal PAR and last restart input are missing,
so that case is refused. Keep its original source material until recovered.

Published results, figures and HTML remain unchanged.
