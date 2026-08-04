# BET 2026 Diagnostic model

This repository reproduces Kflow Job 21641, the BET 2026 Diagnostic model used
as the basis of the tau=2 structural ensemble. The earlier Diagnostic `main`
is preserved without modification on branch
[`tau=1`](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/tree/tau%3D1).

## Fixed model definition

| Component | Diagnostic setting |
|---|---|
| Steepness | `h=0.90`, fixed; committed `model/bet.ini` has `sv(29)=0.90` and age flag 162 remains zero |
| Selectivity | 33 independent groups; F10 and F33 are five-node splines with weak non-decreasing penalty 10,000 |
| Tag likelihood | Direct negative binomial; `tau=2` fixed (`parest 111/305/306 = 4/1/0`, all `fish_pars(4)=0`, fish flags 43/44 = 0) |
| Initialization | Ordinary `bet.ini -makepar`; no seed, jitter or fitted checkpoint |
| Natural mortality | Lorenzen log-intercept `-2.54930339768360`, slope `-1`, fixed |
| Composition likelihood | Dirichlet-multinomial, Nmax 25, eight groups, concentration 7 fixed and group effects estimated |
| Tag mixing | `K=0.20` |

The fitting script audits steepness, tau, natural mortality, DM concentration
and every Diagnostic selectivity flag after each fitted phase. A mismatch stops
the run before the next phase.

## Run

On 64-bit Linux:

```sh
./verify
./doitall
```

`./doitall` runs the Diagnostic model `S0.90-F2`, matching Job 21641. Select another model and a fresh output directory
with:

```sh
./run-final
```

## Reference result

| Item | Job 21641 value |
|---|---:|
| Objective | 90,814.8573966593 |
| Maximum gradient | 9.6794115e-05 |
| Final PAR SHA-256 | `21dcaea9db8c89ddc8c29fa3c3a5e514b50bef6e26587c168c00c05f35fbebc3` |
| Hessian | PDH; 60/60 partitions completed |
| Eigenvalues | 1,997 positive; 0 non-positive |
| Smallest eigenvalue | 2.55194e-07 |

[`results/reference/`](results/reference/README.md) contains the exact final
PAR, Hessian diagnostics and Hessian-enriched MFCL Shiny payload. The payload
restores the matching final PAR and core MFCL report files and can be opened
directly in MFCL Shiny.

## Diagnostic report

The branch includes one Kflow task using the same `model/doitall.sh` recipe as
the standalone run. `MODEL_ID` selects one of the 27 explicit model inputs; the
default is `S0.90-F2` (the Job 21641 Diagnostic model). Jobs use the pinned `tuna-flow:v2.5` image and install
the latest-at-submission `mfclkit` (`cf786007`) and `mfclshiny` (`542ac93b`)
revisions before fitting. The original 24 definitions remain unchanged; the
three `F5` jobs add the independent F10+F33-logistic comparison.

```sh
DIAGNOSTIC_MODEL_DIR=/path/to/Job21641/model bash diagnostic-report/run.sh
```

The report refuses a mismatched final PAR. It produces publication-resolution
PNG/PDF figures, CSV/LaTeX tables, Hessian uncertainty summaries, a
self-contained HTML report and an offline viewer. See
[`diagnostic-report/`](diagnostic-report/README.md).

## Provenance

- Source Kflow model: Job 21641
- Source repository commit: `3abf0c64fb9b0c2d70b9c672dc7d9a655d3060d6`
- Runtime: Tuna Flow 2.5, pinned by image digest in `kflow.yaml`
- MFCL executable SHA-256: `8995f72019869863c1d1c0b4f44fc6a6268d1f79031f5bc79dc354ee10f0a63e`

See [`PROVENANCE.md`](PROVENANCE.md) and
[`JOB19835_COMPARISON.md`](JOB19835_COMPARISON.md) for the input/control audit.
