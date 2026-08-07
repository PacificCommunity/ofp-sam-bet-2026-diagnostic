#!/usr/bin/env Rscript

# Add a verified derived uncertainty table to the compact public payload without
# retaining any raw MFCL files.  This is used when a dependent-variable output
# is added after the original archive extraction.

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop(
    "Usage: augment_public_payload_uncertainty.R INPUT_RDS F_UNCERTAINTY_CSV OUTPUT_RDS",
    call. = FALSE
  )
}

input_file <- normalizePath(args[[1L]], mustWork = TRUE)
f_file <- normalizePath(args[[2L]], mustWork = TRUE)
output_file <- args[[3L]]
payload <- readRDS(input_file)
if (!identical(payload$schema, "bet2026.diagnostic_report.v1")) {
  stop("Unsupported compact report payload schema.", call. = FALSE)
}
if (!is.data.frame(payload$model$annual_uncertainty)) {
  stop("Compact report payload does not contain annual uncertainty.", call. = FALSE)
}

f_uncertainty <- utils::read.csv(f_file, check.names = FALSE, stringsAsFactors = FALSE)
required <- c("year", "quantity", "estimate", "lower_50", "upper_50", "lower_80", "upper_80", "lower_95", "upper_95")
if (!all(required %in% names(f_uncertainty)) ||
    !identical(as.integer(f_uncertainty$year), 1952:2024) ||
    !all(f_uncertainty$quantity == "fishing_mortality")) {
  stop("Annual F/FMSY uncertainty table is incomplete or invalid.", call. = FALSE)
}
if (any(!is.finite(as.matrix(f_uncertainty[required[-c(1L, 2L)], drop = FALSE]))) ||
    any(f_uncertainty$lower_95 < 0) ||
    any(f_uncertainty$lower_95 > f_uncertainty$estimate) ||
    any(f_uncertainty$estimate > f_uncertainty$upper_95)) {
  stop("Annual F/FMSY uncertainty intervals are invalid.", call. = FALSE)
}

base <- payload$model$annual_uncertainty
base <- base[base$quantity != "fishing_mortality", , drop = FALSE]
columns <- union(names(base), names(f_uncertainty))
for (column in setdiff(columns, names(base))) base[[column]] <- NA
for (column in setdiff(columns, names(f_uncertainty))) f_uncertainty[[column]] <- NA
payload$model$annual_uncertainty <- rbind(base[, columns, drop = FALSE], f_uncertainty[, columns, drop = FALSE])
payload$data_vintage <- "2026-08-07"
dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
saveRDS(payload, output_file, compress = "xz")
message("Updated compact public report payload: ", output_file)
