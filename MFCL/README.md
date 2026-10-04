# MFCL files

The Diagnostic inputs, final PAR, executable, `doitall.sh` and key outputs are
available here as individual files. They are unchanged copies from the
[original standalone release](https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/releases/tag/diagnostic-standalone-2026.08.11).
The [ZIP](bet-2026-diagnostic-standalone.zip) contains all 67 original files.
[11.par](11.par) is the saved evaluation output; [final.par](final.par) is the
fitted input. [TAF](../TAF/) provides tables and figures from these results.

Read an input directly in R:

```r
otoliths <- FLR4MFCL::read.MFCLALK("https://raw.githubusercontent.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/main/MFCL/bet.age_length")
```

Check the files with `python3 ci/verify-mfcl-files.py` from the repository root.
To regenerate outputs on 64-bit Linux, extract the ZIP into a separate working
directory and run `./run-final`. Use another fresh copy and `./doitall.sh` for a
full fit. Both commands write files; keep the published copies unchanged.
The [original instructions](README.txt) describe the fitting sequence.

[fishery-grouping.csv](fishery-grouping.csv) is an unchanged copy of the
published fishery mapping used by TAF.
