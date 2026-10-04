local({
  args <- commandArgs(trailingOnly = TRUE)
  stopifnot(length(args) == 1L)
  root <- normalizePath(args[1L], mustWork = TRUE)
  pins <- list(
    TAF = c("4.4.0", "e7960d0d8092072ed4910a7d8d7da4ef6eb38832"),
    FLCore = c("2.6.33", "0642117cb7b66d398abc084f814c7c8b4a12dc8d"),
    FLR4MFCL = c("1.8.1", "56d9e6e079b0cfa6023ebfdbdc8ca8cfb102cb0b")
  )
  for (name in names(pins)) {
    stopifnot(requireNamespace(name, quietly = TRUE))
    description <- packageDescription(name)
    stopifnot(identical(description$Version, pins[[name]][1L]),
              identical(description$RemoteSha, pins[[name]][2L]))
    cat(name, description$Version, description$RemoteSha, "\n")
  }
  stopifnot(requireNamespace("gridExtra", quietly = TRUE))
  cat("gridExtra", as.character(packageVersion("gridExtra")), "\n")
  cat(R.version.string, "\n")

  setwd(file.path(root, "TAF"))
  TAF::taf.boot()
  results <- TAF::source.all(taf = TRUE)
  stopifnot(length(results) == 5L, all(results),
            identical(names(results), c("utilities.R", "data.R", "model.R",
                                       "output.R", "report.R")))
  stats <- read.csv("output/stats.csv")
  stopifnot(nrow(stats) == 1L, stats$npar == 1997L,
            is.finite(stats$objfun), abs(stats$objfun - 90814.8573966594) < 1e-6,
            nrow(read.csv("data/otoliths.csv")) == 2005L,
            "ess" %in% names(read.csv("data/otoliths.csv")),
            nrow(read.csv("data/fisheries.csv")) == 33L)
  images <- list.files("report", pattern = "[.]png$", full.names = TRUE)
  stopifnot(length(images) == 7L, all(file.info(images)$size > 0L))
  cat("TAF boot and all five saved-result stages passed; no model fit.\n")
})
