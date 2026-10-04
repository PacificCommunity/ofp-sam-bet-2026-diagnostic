# Prepare plots and tables for report

# Before: biology.csv, biomass.csv, catch.csv, f_annual.csv, f_stage.csv,
#         params.csv, summary.csv (output)
# After:  biology.csv, f_adult_juvenile_same_free.png,
#         f_adult_juvenile_same_axes.png, f_last_10_free_axes.png,
#         f_last_10_same_axes.png, params_on_bounds.csv, summary.csv (report)

library(TAF)
library(lattice)
suppressMessages(library(gridExtra))  # grid.arrange

no_ticks_on_top <- function(side, ...)
{
  if(side %in% c("top", "right")) return()
  axis.default(side=side, ...)
}

mkdir("report")

# Read tables
biology <- read.taf("output/biology.csv")
biomass <- read.taf("output/biomass.csv")
catch <- read.taf("output/catch.csv")
f.annual <- read.taf("output/f_annual.csv")
f.stage <- read.taf("output/f_stage.csv")
params <- read.taf("output/params.csv")
summary <- read.taf("output/summary.csv")

# Plot biomass
taf.png("biomass")
sb <- aggregate(sb~year+area, biomass, mean)
sb$sb <- sb$sb / 1000
sb$area <- paste("Region", sb$area)
sb.all <- data.frame(aggregate(sb~year, sb, sum), area="all")
sb.all <- sb.all[c("year", "area", "sb")]
# sb <- rbind(sb, sb.all)
p <- xyplot(sb~year|area, sb, type="l", as.table=TRUE, layout=c(2,3), grid=TRUE,
            lwd=2, xlab="Year", ylab="Spawning potential (1000 t)",
            scales=list(alternating=FALSE))
plot(p)
dev.off()

# Plot adult and juvenile F
taf.png("f_adult_juvenile_same_axes", width=2200, height=1400, res=300)
p1 <- xyplot(f~year|area, groups=stage, f.stage, type="l",
             lwd=2, col=c("darkblue","darkgray"), grid=TRUE, xlab="Year",
             ylab="Fishing mortality", layout=c(2,3), as.table=TRUE,
             axis=no_ticks_on_top, between=list(x=0.6, y=0.6),
             scales=list(y=list(relation="free"), alternating=FALSE, rot=0),
             ylim=lim(f.stage$f, 1.02))
plot(p1)
dev.off()

taf.png("f_adult_juvenile_free_axes", width=2200, height=1400, res=300)
p2 <- xyplot(f~year|area, groups=stage, f.stage, type="l",
             lwd=2, col=c("darkblue","darkgray"), grid=TRUE, xlab="Year",
             ylab="Fishing mortality", layout=c(2,3), as.table=TRUE,
             axis=no_ticks_on_top, between=list(x=0.6, y=0.6),
             scales=list(y=list(relation="free"), alternating=FALSE, rot=0))
plot(p2)
dev.off()

taf.png("f_adult_juvenile_together", width=2400, height=3000, res=300)
grid.arrange(p1, p2)
dev.off()

# Plot F by age for the last ten years
f.last.10 <- f.annual[f.annual$year %in% tail(sort(unique(f.annual$year)), 10),]
f.last.10 <- aggregate(f~age+area, f.last.10, mean)

taf.png("f_last_10_same_axes", width=2200, height=1400, res=300)
p3 <- xyplot(f~age|area, f.last.10, type="l", lwd=2, grid=TRUE,
             xlab="Age class", ylab="Fishing mortality", layout=c(2,3),
             as.table=TRUE, axis=no_ticks_on_top, between=list(x=0.6, y=0.6),
             scales=list(y=list(relation="free"), alternating=FALSE, rot=0),
             ylim=lim(f.last.10$f, 1.02))
plot(p3)
dev.off()

taf.png("f_last_10_free_axes", width=2200, height=1400, res=300)
p4 <- xyplot(f~age|area, f.last.10, type="l", lwd=2, grid=TRUE,
             xlab="Age class", ylab="Fishing mortality", layout=c(2,3),
             as.table=TRUE, axis=no_ticks_on_top, between=list(x=0.6, y=0.6),
             scales=list(y=list(relation="free"), alternating=FALSE, rot=0))
plot(p4)
dev.off()

taf.png("f_last_10_together", width=2400, height=3000, res=300)
grid.arrange(p3, p4)
dev.off()

# Parameters on bounds
params.on.bounds <- params[params$Note == "*",]
params.on.bounds$Gradient <- params.on.bounds$Note <- NULL
params.on.bounds <- rnd(params.on.bounds, "Estimate", 5)
params.on.bounds <- rnd(params.on.bounds, "L_bound", 2)
lo <- (params.on.bounds$Estimate - params.on.bounds$L_bound)^2 == 0
up <- (params.on.bounds$Estimate - params.on.bounds$U_bound)^2 == 0
params.on.bounds$Which <- NA_character_
params.on.bounds$Which[lo] <- "Lower"
params.on.bounds$Which[up] <- "Upper"

# Format tables
biology <- rnd(biology, 2:5, c(1,1,3,3))
summary <- div(summary, 2:6, 10^c(6,3,3,3,3))
summary <- rnd(summary, 2:8, c(0, 0, 0, 0, 0, 2, 2))
biology <- format(biology)  # retain trailing zeros
summary <- format(summary)  # retain trailing zeros

# Write tables
write.taf(biology, dir="report")
write.taf(params.on.bounds, quote=TRUE, dir="report")
write.taf(summary, dir="report")
