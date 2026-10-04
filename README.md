[![Preservation checks](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/actions/workflows/verify-preserved-results.yml/badge.svg?branch=main)](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/actions/workflows/verify-preserved-results.yml?query=branch%3Amain) [![TAF checks](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/actions/workflows/check-taf.yml/badge.svg?branch=main)](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/actions/workflows/check-taf.yml?query=branch%3Amain)

# BET 2026 Diagnostic model

<a id="fixed-model-definition"></a>
<a id="run"></a>
<a id="standalone-release"></a>
<a id="reference-result"></a>
<a id="diagnostic-report"></a>
<a id="provenance"></a>

[Report](https://pacificcommunity.github.io/ofp-sam-bet-2026-diagnostic/bet-2026-diagnostic-report.html)
· [Viewer](https://pacificcommunity.github.io/ofp-sam-bet-2026-diagnostic/bet-2026-likelihood-profile-viewer.html)
· [Standalone bundle](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/releases/download/diagnostic-standalone-2026.08.11/bet-2026-diagnostic-standalone.zip).

The Diagnostic model uses fixed steepness 0.90, direct tag overdispersion τ=2,
and 33 independent selectivity groups. The earlier τ=1 configuration remains
on the `tau=1` branch.

The repository includes the native MFCL executable, complete inputs,
`doitall.sh` and exact fitted PAR. On 64-bit Linux, run from the repository root:

```sh
make help
make verify
make rerun OUT=/tmp/bet-final
```

`make rerun` uses the saved fit and a function-evaluation ceiling of 1 to
regenerate five checksum-locked REP files in a new directory. Source inputs
and published results stay in place.

Use `./restore-payload` to restore saved core outputs without MFCL, or
`make refit OUT=/tmp/bet-refit` for a complete fit from the committed inputs.

The profile and constant ASPM final PARs are retained in `reproduce/`;
see [native reruns and remaining gaps](reproduce/README.md).

See [model and reproduction details](docs/reproduction.md),
[reference results](results/reference/README.md),
[report instructions](diagnostic-report/README.md),
[provenance](PROVENANCE.md) and [input comparison](JOB19835_COMPARISON.md).
