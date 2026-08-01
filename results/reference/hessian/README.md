# Completed native Hessian

This directory contains the full MFCL Hessian and compact diagnostics for the
included `final.par`. It is a frozen result, not a recipe for another model.

| Item | Value |
|---|---:|
| Parameters | 1,997 |
| Completed partitions | 70 / 70 |
| Status | PDH (HIGH reliability) |
| Positive eigenvalues | 1,997 |
| Negative eigenvalues | 0 |
| Zero eigenvalues | 0 |
| Minimum eigenvalue | 1.62641e-07 |
| Maximum eigenvalue | about 398 |
| Positive condition number | about 2.45e9 |

`bet.hes` is already stitched. Use the repository-root `restore-hessian`
command to copy it only to a fitted model with the matching `final.par` hash.
