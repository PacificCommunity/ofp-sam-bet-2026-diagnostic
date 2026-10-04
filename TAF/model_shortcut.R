# Run analysis, write model results

# Before: model_results (boot/data)
# After:  11.par, catch.rep, indepvar.rpt, length.fit, plot-11.par.rep,
#         test_plot_output (model)

library(TAF)

mkdir("model")

# Model results
cp("boot/data/model_results/11.par",           "model")
cp("boot/data/model_results/catch.rep",        "model")
cp("boot/data/model_results/indepvar.rpt",     "model")
cp("boot/data/model_results/length.fit",       "model")
cp("boot/data/model_results/plot-11.par.rep",  "model")
cp("boot/data/model_results/test_plot_output", "model")
