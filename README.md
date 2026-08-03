# BET 2026 Diagnostic model — tau=2 exploration

This branch fits the BET 2026 Diagnostic configuration with tag
negative-binomial overdispersion fixed at `tau=2`.

Only two aspects differ from the Diagnostic fitting recipe:

- direct tau parameterization with `tau=2` fixed;
- ordinary `bet.ini -makepar` initialization, with no jitter or seed-23
  checkpoint.

All other model inputs, phases and controls are retained.

## Run

On 64-bit Linux:

```sh
chmod +x mfclo64 doitall verify scripts/* model/doitall.sh
./doitall
```

The run is written to `run/`; the final fitted parameter file is
`run/final.par`. Select another empty output directory with, for example,
`RUN_DIR=run-2 ./doitall`.

On Windows or macOS, install Docker Desktop and run `./doitall` from a Linux
shell, or use `doitall.ps1`. The pinned runtime is
`ghcr.io/pacificcommunity/tuna-flow:v2.5`.

## Fixed-tau implementation

The run uses:

| Control | Value |
|---|---:|
| parest flag 111 | 4 |
| parest flag 305 | 1 |
| parest flag 306 | 0 |
| fish flags 43/44 | 0/0 |
| `fish_pars(4)` | 0 for all fisheries |

Under the direct parameterization,
`tau = 1 + exp(fish_pars(4))`; therefore `fish_pars(4)=0` fixes `tau=2`.
The script writes this value into the makepar-generated PAR before Phase 1 and
checks it after every phase. See [TAU2_EXPLORATION.md](TAU2_EXPLORATION.md) for
the source and manual audit.

## Kflow

The branch includes a Kflow task named
`ofp-sam-bet-2026-diagnostic-tau2-exploration`. It uses the same
`model/doitall.sh` recipe as the standalone run.

## Baseline reference files

The committed `results/reference/`, completed Hessian, `final.par` and
`run-final` belong to the main-branch Diagnostic fit. They are retained for
comparison and are **not** tau=2 exploration results. The fitted tau=2 result
must come from `./doitall` or the Kflow task above.
