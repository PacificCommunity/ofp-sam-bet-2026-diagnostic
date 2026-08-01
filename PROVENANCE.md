# Provenance

## Model identity

- Public name: **Diagnostic model**
- Kflow source: Job 19835
- Scientific parent: Job 19325, best-objective converged jitter seed 23
- Source repository: `PacificCommunity/ofp-sam-bet-2026-stepwise`
- Source commit: `2973795d47b255e015fee680608401f20160e80a`
- Source model key: `K020-tau-not-estimated-sel20c-f10-ndpen-weak-seed23-base`

## Model definition

- K = 0.20; tag tau not estimated
- F10: five-node cubic spline
- F10 non-decreasing controls: flag 16 = 1 and flag 56 = 10000
- Fixed Lorenzen natural-mortality intercept: -2.54930339768360
- Dirichlet-multinomial composition likelihood: eight groups, Nmax = 25
- Frozen frequency, tag, age-length and regional-scaling inputs

## Seed-23 initialization

Job 19835 reproduced Job 19325 seed 23 from `bet.ini -makepar`. Parameters are
perturbed only when first represented, not once per optimization phase.

| Phase | Parameter family | Applied seed | Parameters | CV |
|---:|---|---:|---:|---:|
| 1 | Final-active variables represented after Phase 1 | 23 | 1964 | 0.1 |
| 2 | `fish_pars(23)` | 2410802 | 8 | 0.1 |
| 5 | Regional-index selectivity coefficients | 2413829 | 25 | 0.1 |

The original dynamic mapping used mfclkit 0.0.0.9040 at commit
`34c56de25afecdd13e9f8e94f2e421e37d9c2f9b` and FLR4MFCL 1.7.2. Because
mfclkit is private, this public repository uses the exact Job 19835 checkpoint
PARs instead. Committed checkpoint PARs must match their archived MD5 before
use. A generated pre-checkpoint PAR is also compared with Job 19835; a
cross-platform floating-point difference is reported but does not block the
verified checkpoint from being applied.

## Runtime record

Job 19835 completed in the pinned tuna-flow v2.5 image recorded in the root
README. Its output archive supplied the committed final PAR, compact model
payload, summaries and seed checkpoints. The raw MFCL executable is not copied
into Git; it remains available inside the public pinned container image.
