# Diagnostic, profile and ASPM readers

Use Make and base R; no Python, R packages or downloads are needed for the
native readers. System tar/XZ, stat and SHA-256 tools are required. Native
MFCL execution needs Linux x86-64. Choose a new absolute OUT each time.

From the repository root:

```sh
make verify
make list
make prepare OUT=/tmp/bet-diagnostic-inputs
make rerun OUT=/tmp/bet-diagnostic-final
make profiles CASE=profiles OUT=/tmp/bet-profile
make restore CASE=profile-75 OUT=/tmp/bet-profile-inputs
make aspm CASE=constant OUT=/tmp/bet-aspm-constant
make aspm CASE=fitted OUT=/tmp/bet-aspm-fitted
```

[Download the offline reader ZIP](bet-2026-diagnostic-readers.zip) for the same
R/Make commands without a checkout. `make unpack` exposes ordinary files for
Diagnostic, 45 profile points and two ASPM sources. `FILES.csv` binds every
file's bytes, mode and SHA256; `source-manifest.json` retains the original pins.
Engines are shared in the archive and copied into each working directory.

Each prepared case has its PAR, six native inputs, executable and original
`doitall.sh`. Diagnostic also has its original `run-final`; ASPM retains its
controls and saved PAR/input files under saved names to protect them from outputs.
The original compact [native.tar.gz](native.tar.gz) remains unchanged.

Diagnostic `rerun` checks five complete original REP hashes. Profile runs use
44 archived final PARs plus the scalar-100 Diagnostic anchor, preserving each
original objective recipe and evaluation ceiling of one. Their objective and
active parameter count must match; whole-profile REP equality is not asserted.
Original generated profile continuation scripts were not retained.

Both ASPM replays require the complete original REP checksum. The fitted replay
uses the original **pre-restart PAR**; its terminal PAR and restart input remain
unavailable. Terminal-PAR restoration and rerunning that case are refused.

`make refit OUT=/tmp/bet-diagnostic-refit` starts only the original self-contained
Diagnostic fit. Full-refit equivalence and Hessian regeneration are untested.
Published results, figures and HTML remain unchanged. Saved source identities
do not recover an unknown historical external executable identity.

## Original Hessian

[Original Hessian archive](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/releases/download/bet2026-hessians-20261006/diagnostic.tar.gz)
contains the matching PAR, matrix, metadata, eigenvalue counts and logs.

```sh
make hessian CASE=diagnostic OUT=/absolute/bet-hessian
make hessian-verify CASE=diagnostic ARCHIVE=/absolute/diagnostic.tar.gz
```

Base R checks [all eight file pins](hessians.json) and the original header without
MFCL. Hessian OUT must be outside the checkout; ARCHIVE enables offline use.
Original compact/full gradients remain unavailable; see
[published uncertainty results](../results/reference/uncertainty/).
