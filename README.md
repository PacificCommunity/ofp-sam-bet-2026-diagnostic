# BET 2026 Diagnostic model — tau=2 exploration

This branch fits 27 controlled BET 2026 models: three fixed steepness values
(`0.80`, `0.85`, `0.90`) crossed with nine selectivity settings (`F1`-`F5`,
`P1`-`P4`). Tag negative-binomial overdispersion is fixed at `tau=2` in every
model.

All models share two fitting differences from the original Diagnostic run:

- direct tau parameterization with `tau=2` fixed;
- ordinary `bet.ini -makepar` initialization, with no jitter or seed-23
  checkpoint.

The only differences among the 27 models are fixed steepness and the documented
selectivity flags. All other inputs, phases and controls are common. See
[SELECTIVITY_MODELS.md](SELECTIVITY_MODELS.md) for the exact definitions and
[JOB19835_COMPARISON.md](JOB19835_COMPARISON.md) for the archived-input and
control audit.

## Run

On 64-bit Linux:

```sh
chmod +x mfclo64 doitall verify scripts/* model/doitall.sh
./doitall
```

`./doitall` runs the Diagnostic model `S0.90-F2`, matching Job 21641. Select another model and a fresh output directory
with:

```sh
MODEL_ID=S0.85-P2 RUN_DIR=run-S0.85-P2 ./doitall
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
the source and manual audit. A portable implementation for other `doitall`
scripts is in [TAU2_FIXED_SNIPPET.md](TAU2_FIXED_SNIPPET.md).

## Kflow

The branch includes one Kflow task using the same `model/doitall.sh` recipe as
the standalone run. `MODEL_ID` selects one of the 27 explicit model inputs; the
default is `S0.90-F2` (the Job 21641 Diagnostic model). Jobs use the pinned `tuna-flow:v2.5` image and install
the latest-at-submission `mfclkit` (`cf786007`) and `mfclshiny` (`542ac93b`)
revisions before fitting. The original 24 definitions remain unchanged; the
three `F5` jobs add the independent F10+F33-logistic comparison.

## Baseline reference files

The committed `results/reference/`, completed Hessian, `final.par` and
`run-final` belong to the main-branch Diagnostic fit. They are retained for
comparison and are **not** tau=2 exploration results. The fitted tau=2 result
must come from `./doitall` or the Kflow task above.
