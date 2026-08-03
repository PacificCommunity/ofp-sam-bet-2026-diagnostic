# Job 19835 comparison

This grid retains the BET 2026 Diagnostic data and non-selectivity controls
used by Kflow Job 19835. The 27 fits form a complete 3 by 9 cross: fixed
steepness `0.80`, `0.85` or `0.90`, and selectivity definition `F1`-`F5` or
`P1`-`P4`.

## Controlled changes

| Setting | Archived Job 19835 | This 27-model grid |
|---|---|---|
| Steepness | `sv(29)=0.80`, fixed (`age flag 162=0`) | `sv(29)=0.80`, `0.85` or `0.90`, fixed in every fit (`age flag 162=0`) |
| Selectivity | F1/Diagnostic definition | One explicit F1-F5 or P1-P4 definition; only fish flags 16, 24, 56, 57 and 61 vary |
| Tag tau | Tau not estimated under the archived legacy branch (`parest 305=0`) | Exactly `tau=2`, fixed under the direct branch (`parest 305=1`, all `fish_pars(4)=0`, fish flags 43/44=0) |
| Initialization | Seed-23 fitted checkpoints were applied during the staged fit | Ordinary `bet.ini -makepar`; no seed, jitter or checkpoint |
| DM composition treatment | Eight groups; `fish_pars(22)=7` fixed; `fish_pars(23)` estimated; `Nmax=25`; staged CEST | Unchanged; the run adds phase-by-phase audits but does not alter these controls |
| Biology, mixing, weighting and phases | Diagnostic settings, including K=0.20 | Unchanged |
| Weight-frequency structure | Declared 200 unused WF intervals and a trailing placeholder despite no WF observations | Approved cleanup: zero WF dimensions and no unused trailing placeholder; catch and LF data are unchanged |

The only differences **among the 27 new fits** are the first two grid axes:
fixed steepness and the five selectivity flags. Fixed tau=2, ordinary makepar
initialization and the WF cleanup are common to all 27 fits.

## Frozen input audit

The Job 19835 archive was compared with the committed run inputs. All files in
this table are byte-identical.

| Input | SHA-256 in Job 19835 and this grid |
|---|---|
| `bet.age_length` | `426859b825bd815aa69c8d97c9dd93097027ed1eb6b9e444d88b69562097a00c` |
| `bet.ini` | `5292938d4743c1dfdd2f1a095c1aa87482c9c17f78b8d879671fe6851d58646f` |
| `bet.reg_scaling` | `5f047ddb4053d1f6df9ace18e85e440b11553de246d024ce8138b427f5f9f7e3` |
| `bet.tag` | `b140e66eb52f2b7e022ef2c562134f8bc9baf3dede18ce95283a001acd2b013f` |
| `cpue_mle_sigma_audit.csv` | `cd2d9a9b61f6efda432318be34c856029b355f0ea35f33681dc1dc37820cbc86` |
| `fishery_map.R` | `0e989f4692c4a2a54abf22f12a1c53c7bd29cb7f0f3bd7c4457cdd3d6e1a125c` |
| `mfcl.cfg` | `2ec8a291fae62c6f37541aec1de37444626d42b3290b371bb42b63d510034eae` |
| `tag_rep_map.R` | `e1bddfe316a8b3e39333d0792f58db8f070d3f6f370770507e2f500f9d88786c` |

`bet.frq` has different hashes solely because of the approved unused-WF
cleanup: Job 19835 is
`9b8f4630b5b8bec8b8292e8207cc789b00542d29338faf6187f3c9af55504aa3`,
and the cleaned input is
`d0d84f0a498e6a62681f2a58ffc1ba53dab9e3d6af856b4ad1fd907196250004`.
The 7,449 catch and length-frequency records were otherwise preserved
token-for-token.
