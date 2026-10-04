# Prepare data, write CSV data tables

# Before: bet.age_length, bet.frq, bet.reg_scaling, bet.tag,
#         fishery-grouping.csv (boot/data), length.fit (boot/data/model_results)
# After:  cpue.csv, fisheries.csv, length_comps.csv, otoliths.csv,
#         tag_recaptures.csv, tag_releases.csv (data)

library(TAF)
suppressMessages(library(FLR4MFCL))
source("utilities.R")  # reading

mkdir("data")

# Read data
oto <- reading("otolith data",
               read.MFCLALK("boot/data/bet.age_length",
                            "boot/data/model_results/length.fit"))
frq <- reading("catch data", read.MFCLFrq("boot/data/bet.frq"))
fisheries <- reading("fisheries description",
                     read.taf("boot/data/fishery-grouping.csv"))
tag <- reading("tagging data", read.MFCLTag("boot/data/bet.tag"))

# Fisheries description
names(fisheries)[names(fisheries) == "Fishery"] <- "fishery"
names(fisheries)[names(fisheries) == "Name"] <- "code"
names(fisheries)[names(fisheries) == "Region"] <- "area"
names(fisheries)[names(fisheries) == "Data group"] <- "gear_long"
names(fisheries)[names(fisheries) == "Selectivity group"] <- "sel_group"
names(fisheries)[names(fisheries) == "Selectivity form"] <- "sel_form"
names(fisheries)[names(fisheries) == "Number of nodes"] <- "sel_nodes"

# Otolith data
otoliths <- ALK(oto)
otoliths <- otoliths[otoliths$obs > 0,]
otoliths <- otoliths[rep(seq_len(nrow(otoliths)), otoliths$obs),]
otoliths$season <- (1 + otoliths$month) / 3
otoliths$area <- fisheries$area[otoliths$fishery]
otoliths <- otoliths[c("year", "season", "area", "ess", "age", "length")]

# CPUE data
cpue <- realisations(frq)
cpue <- merge(cpue, fisheries[c("fishery", "area", "gear_long")])
cpue <- cpue[cpue$gear_long == "Index",]
cpue$season <- (1 + cpue$month) / 3
cpue$index <- cpue$catch / cpue$effort / 1e6
cpue <- cpue[c("year", "season", "fishery", "area", "index")]

# Length compositions
size <- freq(frq)
size <- size[size$freq != -1,]
length.comps <- size[!is.na(size$length),]
length.comps$season <- (1 + length.comps$month) / 3
length.comps <- length.comps[c("year", "season", "fishery", "length", "freq")]

# Tag releases and recaptures
tag.releases <- releases(tag)
names(tag.releases)[names(tag.releases) == "region"] <- "area"
tag.releases$season <- (1 + tag.releases$month) / 3
tag.releases <- tag.releases[c("rel.group", "area", "year", "season", "program",
                               "length", "lendist")]
tag.recaptures <- recaptures(tag)
names(tag.recaptures)[names(tag.recaptures) == "region"] <- "rel.area"
names(tag.recaptures)[names(tag.recaptures) == "year"] <- "rel.year"
names(tag.recaptures)[names(tag.recaptures) == "month"] <- "rel.month"
names(tag.recaptures) <- sub("recap", "rec", names(tag.recaptures))
tag.recaptures$rel.season <- (1 + tag.recaptures$rel.month) / 3
tag.recaptures$rec.season <- (1 + tag.recaptures$rec.month) / 3
tag.recaptures <- tag.recaptures[
  c("rel.group", "rel.area", "rel.year", "rel.season", "program", "rel.length",
    "rec.fishery", "rec.year", "rec.season", "rec.number")]

# Write TAF tables
write.taf(cpue, dir="data")
write.taf(fisheries, dir="data")
write.taf(length.comps, dir="data")
write.taf(otoliths, dir="data")
write.taf(tag.recaptures, dir="data")
write.taf(tag.releases, dir="data")
