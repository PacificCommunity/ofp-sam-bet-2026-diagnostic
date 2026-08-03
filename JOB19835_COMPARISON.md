# Job 19835 versus Job 21641

This audit identifies every intended difference between the previous
Diagnostic Job 19835 and the new Diagnostic Job 21641.

| Component | Job 19835 | Job 21641 Diagnostic | Classification |
|---|---|---|---|
| Steepness | `h=0.80`, fixed | `h=0.90`, fixed | Intended change |
| Selectivity | F10 weak non-decreasing | F10 and F33 weak non-decreasing; all 33 groups independent | Intended change |
| Tag tau | Legacy branch, not estimated | Direct parameterization, `tau=2` fixed | Intended change |
| Initialization | Seed-23 fitted checkpoints at phases 1, 2 and 5 | Ordinary makepar, no seed/checkpoint | Intended change |
| Weight-frequency structure | Declared but unused WF dimensions and trailing placeholder | Unused WF structure removed | Approved cleanup; no observation changed |
| DM | Nmax 25; eight groups; concentration 7 fixed; group effects estimated | Identical | Unchanged |
| Natural mortality | Log-intercept `-2.54930339768360`, Lorenzen slope `-1` | Identical | Unchanged |
| Tag mixing | `K=0.20` | Identical | Unchanged |
| CPUE, biology, movement, growth, recruitment and other likelihood controls | Diagnostic settings | Identical | Unchanged |

Byte-level checks found `bet.tag`, age-length, regional scaling, MFCL config
and mapping files identical. In the FRQ, all 7,449 catch, effort and
length-frequency records are token-identical after excluding only the unused WF
placeholder. The effective Job 21641 INI differs from Job 19835 only at
`sv(29): 0.8 -> 0.90`.

Final fish flags differ only for F33 selectivity (`flag 16: 0 -> 1`,
`flag 56: 0 -> 10000`). Tau uses `parest 305: 0 -> 1`, all
`fish_pars(4)=0`, and fish flags 43/44 remain zero. No unlisted scientific
setting difference was found.
