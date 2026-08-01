# BET 2026 Diagnostic model

Public, standalone reconstruction of the BET 2026 diagnostic model. This one
repository contains the frozen inputs, deterministic seed-23 initialization,
fitted `final.par`, compact R payload, completed Hessian and exact Linux MFCL
executable.

## Quick start

On 64-bit Linux, no installation or Docker is needed:

```sh
./run-final
./doitall
```

`run-final` evaluates the included fitted PAR in a few minutes. `doitall`
repeats the complete multi-phase fit and can take several hours.

On Windows or macOS, install
[Docker Desktop](https://www.docker.com/products/docker-desktop/) and run:

```powershell
.\run-final.ps1
.\doitall.ps1
```

The shell runners automatically use Docker on non-Linux systems. Linux users
can force the pinned container with `USE_DOCKER=1 ./doitall`. Results go to
`run/` or `final-run/`; frozen repository files are never modified. Select a
fresh directory with, for example, `RUN_DIR=run-2 ./doitall`.

## Run the complete fit

The bundled `mfclo64` is a statically linked Linux x86-64 executable. The
complete fit starts from the frozen input files and reconstructs the selected
seed-23 initialization path:

```sh
./doitall
```

An alternative compatible executable can still be selected explicitly:

```sh
PROGRAM_PATH=/absolute/path/to/mfclo64 ./doitall
```

## Run the fitted final PAR

To evaluate the included reference fit without refitting:

```sh
./run-final
```

or, in Windows PowerShell:

```powershell
.\run-final.ps1
```

This performs a zero-iteration MFCL evaluation and regenerates the standard
fitted-model outputs, including `evaluated.par`, `ests.rep`,
`plot-evaluated.par.rep`, `catch.rep`, `tag.rep`, CPUE, selectivity,
fishing-mortality and residual files. It then restores the completed full
Hessian and compact R payload into `final-run/`; the Hessian is not recomputed.

To attach the archived Hessian to another copy of this exact reference fit:

```sh
./restore-hessian path/to/fitted-model
```

PowerShell users can use `.\restore-hessian.ps1 path\to\fitted-model`. The
command verifies the `final.par` SHA-256 and refuses a mismatched model, because
a Hessian cannot be transferred safely to different fitted parameters.

## Reference fit

| Item | Reference value |
|---|---:|
| Objective | 89054.3397838085 |
| Maximum gradient | 9.2968286e-05 |
| 2024 depletion | 0.3287955046 |
| Final PAR SHA-256 | `6a7a4489ec40fa8223c9c3aac831a46c4eaa810654a35af0a537cf6b04fb2eed` |
| Hessian | PDH; 1,997/1,997 positive eigenvalues |
| Smallest eigenvalue | 1.62641e-07 |

The fitted files are in [`results/reference/`](results/reference/README.md).

> **Seed 23 note.** Seed 23 was the best-objective converged jitter selected for
> this diagnostic model; it was not the lowest-depletion run. The complete fit
> applies CV=0.1 perturbations only when parameter groups first become active:
> seed 23 at Phase 1, derived seed 2410802 for eight new parameters at Phase 2,
> and derived seed 2413829 for 25 new parameters at Phase 5. Phases 3, 4 and
> 6–11 only carry the preceding PAR forward; they do not jitter it again. The
> archived checkpoints are hash-verified before use.

## Exact runtime

- Docker image: `ghcr.io/pacificcommunity/tuna-flow:v2.5`
- Pinned digest: `sha256:c87f1f6d9d4f62dc447844b58afe35f96af175bf933cb6cffbbbe39a59172360`
- MFCL executable in the image: `/home/mfcl/mfclo64`
- Bundled native executable: `./mfclo64` (Linux x86-64 only)
- MFCL executable SHA-256: `f5bc1e232a86e51f920bce7271d8e0930d0b160e4d18dc46de44078f0fa24cd0`

See [`PROVENANCE.md`](PROVENANCE.md) for the model definition and source
record. Run `./verify` to check all committed inputs and reference results.

## Kflow

The public Kflow task is `ofp-sam-bet-2026-diagnostic`. It uses the same pinned
image and the same `model/doitall.sh`; Kflow does not maintain a second model
recipe.

The earlier experimental MCMC files are preserved on the public `legacy`
branch and are intentionally absent from `main`.
