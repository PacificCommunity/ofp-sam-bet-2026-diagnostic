# BET 2026 fixed-tau selectivity models

Each selectivity definition below is crossed with fixed steepness `0.80`,
`0.85` and `0.90`, giving 24 models. Every model uses the same Diagnostic
inputs, estimation phases, fixed `tau=2`, mixing period, biological settings
and data weighting. Within a steepness level, only the selectivity controls in
this table change.

| Model | Sharing | Node setting | F10 | F33 | Other change |
|---|---|---|---|---|---|
| F1 | All 33 independent | Diagnostic defaults | 5-node spline; weak non-decreasing penalty 10,000 | 5-node spline | None |
| F2 | All 33 independent | Diagnostic defaults | 5-node spline; weak non-decreasing penalty 10,000 | 5-node spline; weak non-decreasing penalty 10,000 | None |
| F3 | All 33 independent | Diagnostic defaults | Logistic | 5-node spline | F3 logistic |
| F4 | All 33 independent | Diagnostic defaults | 5-node unpenalized spline | Logistic | None |
| P1 | F2/F3 and F7/F9 shared | F1, F2, F3, F5 and F29 use four nodes | 5-node unpenalized spline | Logistic | Reproduces the parsimonious selectivity structure |
| P2 | F2/F3 and F7/F9 shared | The P1 four-node curves return to five nodes | 5-node unpenalized spline | Logistic | Isolates the four-versus-five-node choice |
| P3 | F2/F3 and F7/F9 shared | As P2 | Logistic | Logistic | Isolates F10 form within the P2 structure |
| P4 | F2/F3 and F7/F9 shared | As P2 | 5-node spline; weak non-decreasing penalty 10,000 | 5-node spline; weak non-decreasing penalty 10,000 | Combines parsimonious sharing with the two weak penalties |

The five selectivity input columns are MFCL fish flags 16, 24, 56, 57 and 61.
Their complete 33-fishery values are directly available here:

| Definition | Explicit input |
|---|---|
| F1 | [F1.csv](model/selectivity-models/F1.csv) |
| F2 | [F2.csv](model/selectivity-models/F2.csv) |
| F3 | [F3.csv](model/selectivity-models/F3.csv) |
| F4 | [F4.csv](model/selectivity-models/F4.csv) |
| P1 | [P1.csv](model/selectivity-models/P1.csv) |
| P2 | [P2.csv](model/selectivity-models/P2.csv) |
| P3 | [P3.csv](model/selectivity-models/P3.csv) |
| P4 | [P4.csv](model/selectivity-models/P4.csv) |

F25 and F26 retain their existing seven-node specifications in every model.
All other fisheries retain the Diagnostic node settings unless explicitly
listed above.

The sharing sensitivity is limited to two catch-weighted longline extraction
pairs with compatible fishery definitions and similar independently fitted
curves: F2/F3 in Region 1 and F7/F9 in Region 3-West. Regional index fisheries
remain independent. The four-node settings in P1 are retained from the earlier
parsimonious screening; P2 provides the direct five-node comparison without
changing the sharing structure.

## Complete 24-model grid

Each link is the exact model input used by `doitall.sh`.

| Fixed steepness | F1 | F2 | F3 | F4 | P1 | P2 | P3 | P4 |
|---:|---|---|---|---|---|---|---|---|
| 0.80 | [S0.80-F1](model/model-inputs/S0.80-F1.conf) | [S0.80-F2](model/model-inputs/S0.80-F2.conf) | [S0.80-F3](model/model-inputs/S0.80-F3.conf) | [S0.80-F4](model/model-inputs/S0.80-F4.conf) | [S0.80-P1](model/model-inputs/S0.80-P1.conf) | [S0.80-P2](model/model-inputs/S0.80-P2.conf) | [S0.80-P3](model/model-inputs/S0.80-P3.conf) | [S0.80-P4](model/model-inputs/S0.80-P4.conf) |
| 0.85 | [S0.85-F1](model/model-inputs/S0.85-F1.conf) | [S0.85-F2](model/model-inputs/S0.85-F2.conf) | [S0.85-F3](model/model-inputs/S0.85-F3.conf) | [S0.85-F4](model/model-inputs/S0.85-F4.conf) | [S0.85-P1](model/model-inputs/S0.85-P1.conf) | [S0.85-P2](model/model-inputs/S0.85-P2.conf) | [S0.85-P3](model/model-inputs/S0.85-P3.conf) | [S0.85-P4](model/model-inputs/S0.85-P4.conf) |
| 0.90 | [S0.90-F1](model/model-inputs/S0.90-F1.conf) | [S0.90-F2](model/model-inputs/S0.90-F2.conf) | [S0.90-F3](model/model-inputs/S0.90-F3.conf) | [S0.90-F4](model/model-inputs/S0.90-F4.conf) | [S0.90-P1](model/model-inputs/S0.90-P1.conf) | [S0.90-P2](model/model-inputs/S0.90-P2.conf) | [S0.90-P3](model/model-inputs/S0.90-P3.conf) | [S0.90-P4](model/model-inputs/S0.90-P4.conf) |

Run one model with, for example:

```sh
MODEL_ID=S0.85-P3 RUN_DIR=run-S0.85-P3 ./doitall
```

The run writes `model-input-audit.csv` and `selectivity-audit.csv`, and stops if
the final fixed steepness or fishery flags do not match the selected model.
