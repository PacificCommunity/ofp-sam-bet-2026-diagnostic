# Profile and ASPM reruns

[Download native.tar.gz](https://raw.githubusercontent.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/main/reproduce/native.tar.gz). It is included in a normal clone;
[files.json](files.json) lists the archived files and checksums.

The small archive retains 44 original profile final PARs, the constant ASPM
final PAR and the fitted ASPM pre-restart PAR. The scalar-100 anchor, native
inputs, MFCL executable and Diagnostic `doitall` reuse checksum-verified Git files.

On 64-bit x86 Linux, from the repository root:

```sh
make help
make rerun OUT=/tmp/bet-final
make profiles CASE=profiles OUT=/tmp/bet-profile
make aspm CASE=constant OUT=/tmp/bet-aspm-constant
make aspm CASE=fitted OUT=/tmp/bet-aspm-fitted
```

Use `CASE=profile-75` for one profile point. `make rerun` regenerates the five
checksum-locked Diagnostic REP files; `make refit OUT=/tmp/bet-refit` starts
the original full fit. Profile runs use a function-evaluation ceiling of 1,
check the original objective and preserve the source PAR and inputs. Profile
objectives use the original zero-penalty switches. Both ASPM commands require
the complete original REP checksum to match. Detailed outputs stay in the new folder.

The fitted ASPM pre-restart PAR reproduces its original final REP exactly;
the original terminal PAR and restart input remain unavailable. `run-native.py`
therefore continues to refuse that terminal-PAR case.

`make verify` checks saved files and the archive without MFCL. Make and
Python 3 are required; no Python commands need to be edited.
`validation.json` records profile controls; `source-status.json` records source
files and controllers. Original generated profile continuation scripts were not
retained. Published results, figures and HTML remain unchanged.

## Original Hessian

[Download the original Hessian](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/releases/download/bet2026-hessians-20261006/diagnostic.tar.gz)
with its matching final PAR, metadata, eigenvalue counts and calculation logs.
The matrix has 1,997 parameters and the original PDH result.

```sh
make hessian CASE=diagnostic OUT=/absolute/bet-hessian
```

This restores saved files without running MFCL; choose a new folder outside
the repository. [The manifest](hessians.json) pins all eight files by SHA256.
The original compact/full gradient files have not been recovered; the
[published uncertainty results](../results/reference/uncertainty/) remain available.
