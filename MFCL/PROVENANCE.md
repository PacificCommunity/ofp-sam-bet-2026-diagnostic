# Provenance

## Model identity

- Public name: **BET 2026 Diagnostic model**
- Kflow source: Job 21641
- Source repository commit: `3abf0c64fb9b0c2d70b9c672dc7d9a655d3060d6`
- Source run: completed on Suva with exit code 0
- Initialization: ordinary `bet.ini -makepar`; no seed, jitter or checkpoint

## Scientific definition

- Steepness `h=0.90` fixed in the committed INI (`sv(29)=0.90`; age flag 162 = 0)
- 33 independent selectivity groups
- F10 and F33 five-node splines with weak non-decreasing penalties 10,000
- Direct negative-binomial tag likelihood with `tau=2` fixed
- Parest flags 111/305/306 = 4/1/0
- Fish flags 43/44 = 0 and all `fish_pars(4)=0`
- Tag mixing `K=0.20`
- Fixed Lorenzen M log-intercept `-2.54930339768360` and slope `-1`
- Dirichlet-multinomial likelihood: Nmax 25, eight groups,
  `fish_pars(22)=7` fixed and `fish_pars(23)` estimated
- Frozen tag, age-length, regional-scaling, CPUE and biological inputs
- No weight-frequency observations; the obsolete unused WF structure is removed

The effective Job 21641 INI was compared with the committed `model/bet.ini`.
They are byte-identical. The archived Job 21641 final PAR is likewise identical
to the final PAR restored from the committed Hessian-enriched payload.

## Runtime safeguards

The original Job 21641 Phase-0 sequence is retained: the effective public INI
is copied byte-for-byte to `bet.model.ini`, MFCL writes `00.par` with
`-makepar`, and the fixed tau and DM initial values are materialized in
`00.fixed.par` before Phase 1. These are run-local generated files, not inputs
loaded from another directory. MFCL's INI format cannot store
`fish_pars(22)=7`, so removing this explicit Phase-0 step would change the
model.
All 198 Phase 1/5 selectivity controls are embedded as literal MFCL control
lines in `doitall.sh`; no model `.conf` or selectivity `.csv` is read at run time. The
checksum-locked CSV is retained as an independent repository audit, and the
validator proves all embedded controls match its 33 rows. After every fitted
phase the script verifies the tau parameterization and value, steepness, fixed
M, DM settings and the complete 33-fishery selectivity table. The controls are
numerically identical to those used by Job 21641; the additional checks do not
change the fit.

## Reference outputs

- Final PAR: Job 21641, SHA-256
  `21dcaea9db8c89ddc8c29fa3c3a5e514b50bef6e26587c168c00c05f35fbebc3`
- Compact payload: Job 22020, rebuilt from Job 21641 after Hessian attachment
- Hessian: 60/60 partitions completed, PDH, reliability HIGH
- Eigenvalues: 1,997 positive, zero non-positive; minimum 2.55194e-07

The public `tau=1` branch preserves the preceding Diagnostic main and all of
its fitted results without rewriting history.
