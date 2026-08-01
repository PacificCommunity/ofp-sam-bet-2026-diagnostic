# BET 2026 Diagnostic model

Public, standalone reconstruction of the BET 2026 diagnostic model fitted in
Kflow Job 19835. The repository contains the frozen MFCL inputs, deterministic
seed-23 initialization, fitted `final.par`, and compact R payload.

## Run the complete fit

Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) on
Windows or macOS, or Docker Engine on Linux. Then clone the repository and run:

```sh
./doitall
```

Windows PowerShell users can run:

```powershell
.\doitall.ps1
```

The pinned Job 19835 Docker image supplies the exact MFCL executable. Results
are written to `run/`; frozen files in `model/` are never modified. A complete
fit can take several hours.

Linux users who already have the MFCL executable may run without Docker:

```sh
PROGRAM_PATH=/absolute/path/to/mfclo64 ./doitall
```

## Run the fitted final PAR

To evaluate the included Job 19835 fit without refitting:

```sh
./run-final
```

or, in Windows PowerShell:

```powershell
.\run-final.ps1
```

This copies `results/reference/final.par` into `final-run/` and performs a
zero-iteration MFCL evaluation to regenerate reports. It does not estimate the
model again.

## Reference fit

| Item | Job 19835 value |
|---|---:|
| Objective | 89054.3397838085 |
| Maximum gradient | 9.2968286e-05 |
| 2024 depletion | 0.3287955046 |
| Final PAR SHA-256 | `6a7a4489ec40fa8223c9c3aac831a46c4eaa810654a35af0a537cf6b04fb2eed` |

The fitted files are in [`results/reference/`](results/reference/README.md).

> **Seed 23 note.** Seed 23 was the best-objective converged jitter from Job
> 19325; it was not the lowest-depletion run. The complete fit applies its
> CV=0.1 perturbation once when parameters first become available: seed 23 at
> Phase 1, derived seed 2410802 at Phase 2, and derived seed 2413829 at Phase 5.
> The archived checkpoints are hash-verified before use.

## Exact runtime

- Docker image: `ghcr.io/pacificcommunity/tuna-flow:v2.5`
- Pinned digest: `sha256:c87f1f6d9d4f62dc447844b58afe35f96af175bf933cb6cffbbbe39a59172360`
- MFCL executable in the image: `/home/mfcl/mfclo64`
- MFCL executable SHA-256: `f5bc1e232a86e51f920bce7271d8e0930d0b160e4d18dc46de44078f0fa24cd0`

See [`PROVENANCE.md`](PROVENANCE.md) for the model definition and source
record. Run `./verify` to check all committed inputs and reference results.

## Kflow

The public Kflow task is `ofp-sam-bet-2026-diagnostic`. It uses the same pinned
image and the same `model/doitall.sh`; Kflow does not maintain a second model
recipe.

The earlier experimental MCMC files are preserved on the public `legacy`
branch and are intentionally absent from `main`.
