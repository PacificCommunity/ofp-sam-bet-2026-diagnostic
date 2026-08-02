# Native MFCL delta-method output

`bet.var` was generated from the archived `final.par` and matching complete
Hessian with the current MFCL executable using:

```sh
./mfclo64 bet.frq final.par variance.par -switch 2 1 145 4 1 37 2
```

Flag 145 requests native variance output and flag 37 selects the intermediate
dependent-variable set. This retains all-period spawning potential,
recruitment and dynamic depletion, terminal abundance at age, and the recent
management quantities without the much larger full regional/yield derivative
set. MFCL special derivative routines return a non-zero process status after
writing valid output; report generation validates the required rows rather than
interpreting that status as an optimization failure.
