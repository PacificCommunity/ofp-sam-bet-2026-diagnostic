# TAF workflow

This is Arni Magnusson’s TAF workflow for the saved Diagnostic fit.
Inputs and native outputs are read from [MFCL](../MFCL/); no download or
model fit is needed for the default workflow.

From the repository root in R:

```r
setwd("TAF")
TAF::taf.boot()
stopifnot(all(TAF::source.all(taf = TRUE)))
```

Install TAF, FLR4MFCL, FLCore and gridExtra first. The versions checked in CI
are recorded in [the workflow](../.github/workflows/check-taf.yml).
Saved [tables](output/) and [figures](report/) can be browsed directly.
Use a separate working copy for regeneration. `model_full.R` runs the original
full fit; [MFCL/README.md](../MFCL/README.md) describes the native commands.
