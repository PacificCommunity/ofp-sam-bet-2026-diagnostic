# Job 21641 Hessian diagnostics

These are the portable diagnostics attached by Kflow Job 22020 to Job 21641.
They describe the included `final.par` and no other model.

| Item | Value |
|---|---:|
| Parameters | 1,997 |
| Completed partitions | 60 / 60 |
| Status | PDH (HIGH reliability) |
| Positive eigenvalues | 1,997 |
| Negative eigenvalues | 0 |
| Zero eigenvalues | 0 |
| Minimum eigenvalue | 2.55194e-07 |
| Maximum eigenvalue | about 1,079 |
| Positive condition number | about 4.23e9 |

The compact attachment records the validated native calculation but does not
archive the large stitched `bet.hes`. `hessian_info.rds` contains all 1,997
parameter labels and marginal standard errors. `check-unit-status.csv` records
all 60 successful partitions.
