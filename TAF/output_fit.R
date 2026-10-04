# Extract model fit results, write CSV output tables

# Before: fisheries.csv (data), 11.par, indepvar.rpt, length.fit,
#         plot-11.par.rep, test_plot_output (model)
# After:  cpue.csv, length.comps.csv, likelihoods.csv, params.csv,
#         stats.csv (output)

library(TAF)
suppressMessages(library(FLR4MFCL))
source("utilities.R")  # reading

mkdir("output")

# Read MFCL output files
par <- reading("parameters", read.MFCLPar(finalPar("model")))
rep <- reading("model estimates", read.MFCLRep(finalRep("model")))
like <- reading("likelihoods", read.MFCLLikelihood("model/test_plot_output"))
lenfit <- reading("length fits", read.MFCLLenFit("model/length.fit"))
indepvar <- reading("indep var", readLines("model/indepvar.rpt"))

# Read fisheries description
fisheries <- read.taf("data/fisheries.csv")

# Model stats
npar <- n_pars(par)
objfun <- obj_fun(par)
gradient <- max_grad(par)
stats <- data.frame(npar, objfun, gradient)

# Parameters
indepvar[1] <- paste(indepvar[1], "Note")
params <- read.table(text=indepvar, header=TRUE, fill=TRUE)
names(params)[names(params) == "Var_name"] <- "Parameter"
names(params)[names(params) == "gradient"] <- "Gradient"
params$Note <- sub("\\*+", "*", params$Note)  # use single asterisk

# Likelihoods
likelihoods <- summary(like)
likelihoods <- as.data.frame(as.list(likelihoods$likelihood))
names(likelihoods) <- summary(like)$component
likelihoods$bhsteep <- likelihoods$effort_dev <- NULL
likelihoods$catchability_dev <- likelihoods$weight_comp <- NULL
likelihoods$total <- NULL
likelihoods$penalties <- obj_fun(par) - sum(likelihoods)

# CPUE
obs <- as.data.frame(cpue_obs(rep))
pred <- as.data.frame(cpue_pred(rep))
names(obs)[names(obs) == "data"] <- "obs"
names(pred)[names(pred) == "data"] <- "pred"
cpue <- cbind(obs, pred["pred"])
names(cpue)[names(cpue) == "unit"] <- "fishery"
cpue$area <- NULL
cpue <- merge(cpue, fisheries[c("fishery", "area", "gear_long")])
cpue <- cpue[cpue$gear_long == "Index",]
cpue$obs <- exp(cpue$obs)
cpue$pred <- exp(cpue$pred)
cpue <- cpue[c("year", "season", "fishery", "area", "obs", "pred")]
cpue <- cpue[order(cpue$fishery, cpue$year, cpue$season),]

# Length comps
length.comps <- lenfits(lenfit)
length.comps$season <- (1 + length.comps$month) / 3
names(length.comps)[names(length.comps) == "sample_size"] <- "ess"
length.comps <- length.comps[c("year", "season", "fishery", "ess",
                               "length", "obs", "pred")]

# Write TAF tables
write.taf(cpue, dir="output")
write.taf(length.comps, dir="output")
write.taf(likelihoods, dir="output")
write.taf(params, quote=TRUE, dir="output")
write.taf(stats, dir="output")
