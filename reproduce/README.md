# Profile and ASPM reruns

[Download native.tar.gz](https://raw.githubusercontent.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/main/reproduce/native.tar.gz). It is included in a normal clone;
[files.json](files.json) lists the archived files and checksums.

The small archive retains 44 original profile final PARs, the constant ASPM
final PAR and the fitted ASPM pre-restart PAR. The scalar-100 anchor, native
inputs, MFCL executable and Diagnostic `doitall` reuse checksum-verified Git files.

On 64-bit x86 Linux, from the repository root:

```sh
python3 reproduce/run-native.py profiles /tmp/bet-profile
python3 reproduce/replay-aspm.py constant /tmp/bet-aspm-constant
python3 reproduce/replay-aspm.py fitted /tmp/bet-aspm-fitted
```

Choose `profile-75` for one profile point. Runs use one function evaluation,
check the original objective and preserve the source PAR and inputs. Profile
objectives use the original zero-penalty switches. Both ASPM commands require
the complete original REP checksum to match. Detailed outputs stay in the new folder.

The fitted ASPM pre-restart PAR reproduces its original final REP exactly;
the original terminal PAR and restart input remain unavailable. `run-native.py`
therefore continues to refuse that terminal-PAR case.

`python3 reproduce/restore.py --verify` checks the archive without MFCL.
`validation.json` records profile controls; `source-status.json` records source
files and controllers. Original generated profile continuation scripts were not
retained. Published results, figures and HTML remain unchanged.
