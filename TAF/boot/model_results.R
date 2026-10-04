library(TAF)

# Copy the published native files from this checkout.
source_dir <- "../../../../MFCL"
key <- c("11.par", "final.par", "bet.age_length", "bet.frq", "bet.ini",
         "bet.reg_scaling", "bet.tag", "BUILD-INFO.txt", "catch.rep",
         "doitall.sh", "indepvar.rpt", "length.fit", "mfcl.cfg", "mfclo64",
         "plot-11.par.rep", "PROVENANCE.md", "README.txt", "run-final",
         "standalone-final-evaluation.log", "test_plot_output")
stopifnot(all(file.exists(file.path(source_dir, key))))
cp(file.path(source_dir, key), ".")
cp(key, "..")
