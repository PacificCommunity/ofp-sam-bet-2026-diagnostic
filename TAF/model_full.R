# Run analysis, write model results

# Before: doitall.sh, mfcl.cfg, bet.age_length, bet.frq, bet.ini,
#         bet.reg_scaling, bet.tag (boot/data), mfclo64 (boot/software)
# After:  11.par, catch.rep, indepvar.rpt, length.fit, plot-11.par.rep,
#         test_plot_output (model)

library(TAF)

mkdir("model")

# Software
cp("boot/software/mfclo64", "model")

# Input files
cp("boot/data/doitall.sh",      "model")
cp("boot/data/mfcl.cfg",        "model")
cp("boot/data/bet.age_length",  "model")
cp("boot/data/bet.frq",         "model")
cp("boot/data/bet.ini",         "model")
cp("boot/data/bet.reg_scaling", "model")
cp("boot/data/bet.tag",         "model")

# Run model
setwd("model")
status <- system2("./doitall.sh")
stopifnot(status == 0L)
setwd("..")
