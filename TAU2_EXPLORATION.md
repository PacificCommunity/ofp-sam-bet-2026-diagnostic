# Fixed tau=2 exploration

This branch retains the BET 2026 Diagnostic model settings and changes the tag
negative-binomial treatment to a fixed `tau=2`. It starts from the ordinary
`bet.ini -makepar` parameter values; no jitter or seed-23 checkpoint is used.

## MFCL settings

| Control | Value | Purpose |
|---|---:|---|
| parest flag 111 | 4 | Negative-binomial tag likelihood |
| parest flag 305 | 1 | Direct tau parameterization |
| parest flag 306 | 0 | Default bounds; inactive while tau is fixed |
| fish flags 43/44 | 0/0 | Do not estimate or group `fish_pars(4)` |
| `fish_pars(4)` | 0 for all 33 fisheries | `log(tau-1)=log(1)=0` |

The ongoing-development source implements

```
tau = 1 + exp(fish_pars(4))
a   = mu / (tau - 1)
```

where `mu` is the expected number of recaptures and `a` is the negative-
binomial size parameter. Therefore `fish_pars(4)=0` gives `tau=2`, `a=mu`, and
conditional variance `mu + mu^2/a = 2*mu`.

Fish flag 43 is deliberately zero. A value of one would place `fish_pars(4)`
in the independent-variable vector and estimate tau. Fish flag 44 only controls
grouping when that parameter is estimated. Parest flag 306 supplies estimation
bounds and does not determine a fixed value.

## Safeguards

The run script writes `fish_pars(4)=0` directly into the Phase-0 PAR before any
optimization. After every phase it verifies the parameterization, both fish
flags and every fishery copy of `fish_pars(4)`. The final audit also verifies
that no `fish_pars(4)` occurs in `indepvar.rpt` and writes
`tag-tau-audit.csv`.

Source audit performed against:

- MFCL `ongoing-dev`: `aad7241ca72634ef7509038e1bcb5fcfb957df04`
- MFCL manual `master`: `b58818e0ae0929da16b1029caf47743444747d7a`

The current manual documents the direct formula and fish flags 43/44. The
executable source additionally confirms that parest flag 305 selects between
the legacy and direct likelihood parameterizations.
