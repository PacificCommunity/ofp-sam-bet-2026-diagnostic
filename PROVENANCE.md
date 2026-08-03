# Provenance

## Model identity

- Public name: **BET 2026 fixed-tau steepness-selectivity grid**
- Initialization: ordinary `bet.ini -makepar`; no jitter or seed checkpoint
- Source repository: `PacificCommunity/ofp-sam-bet-2026-stepwise`
- Source commit: `2973795d47b255e015fee680608401f20160e80a`
- Source configuration: BET 2026 Diagnostic model

## Model definition

- K = 0.20; tag tau fixed at 2 using the direct negative-binomial formulation
- Fixed steepness grid: 0.80, 0.85 and 0.90 (`sv(29)`, age flag 162 = 0)
- Selectivity grid: F1-F4 and P1-P4, defined in `SELECTIVITY_MODELS.md`
- Job 19835 input/control audit: `JOB19835_COMPARISON.md`
- Parest flags 111/305/306 = 4/1/0
- All fish flags 43/44 = 0 and all `fish_pars(4) = 0`
- F10: five-node cubic spline
- F10 non-decreasing controls: flag 16 = 1 and flag 56 = 10000
- Fixed Lorenzen natural-mortality intercept: -2.54930339768360
- Dirichlet-multinomial composition likelihood: eight groups, Nmax = 25
- Frozen frequency, tag, age-length and regional-scaling inputs
- No weight-frequency observations: the FRQ header uses zero WF dimensions
  and fishery records contain no trailing WF missing-value field

The Diagnostic FRQ originally declared 200 weight intervals even though no weight-frequency
observations existed. That unused structure and its trailing per-record `-1`
field were removed. The 7,449 catch and length-frequency records were otherwise
preserved token-for-token.

## Initialization and tau treatment

The complete exploration starts from the unperturbed makepar output. Before
Phase 1, every fishery copy of `fish_pars(4)` is written as zero. The phase
switches select parest flag 305 = 1 and keep fish flags 43/44 at zero. The
ongoing-development likelihood therefore uses `tau=1+exp(0)=2` while excluding
the parameter from the independent-variable vector. An audit after each phase
prevents the fixed value or flags from being silently changed.

## Runtime record

The tau=2 exploration uses the pinned tuna-flow v2.5 image and bundled Linux
x86-64 MFCL executable recorded in the root README. The committed
`results/reference/` files are retained baseline Diagnostic artifacts and must
not be interpreted as tau=2 results.

## Hessian record

The retained baseline native Hessian was evaluated in 70 complete partitions and stitched with
MFCL into the committed full 1,997 by 1,997 `bet.hes`. The binary header and
size were validated after reconstruction. The completed eigen analysis found
1,997 positive, zero negative and zero zero eigenvalues: status PDH,
reliability HIGH, minimum eigenvalue 1.62641e-07. These values describe the
baseline Diagnostic fit, not the tau=2 exploration. Public RDS files retain the
scientific contents but use portable relative paths instead of scheduler work
directories.
