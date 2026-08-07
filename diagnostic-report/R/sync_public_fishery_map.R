#!/usr/bin/env Rscript

# Synchronise the public, compact report payload with the version-controlled
# diagnostic fishery map.  The payload deliberately contains only display and
# grouping metadata; this keeps public reports free of raw model files while
# ensuring labels follow the fitted diagnostic configuration.

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) {
  stop(
    "Usage: sync_public_fishery_map.R REPO_ROOT INPUT_RDS OUTPUT_RDS",
    call. = FALSE
  )
}

repo_root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
input_file <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output_file <- args[[3L]]
payload <- readRDS(input_file)
if (!identical(payload$schema, "bet2026.diagnostic_report.v1")) {
  stop("Unsupported compact report payload schema.", call. = FALSE)
}

map_env <- new.env(parent = baseenv())
sys.source(file.path(repo_root, "model", "fishery_map.R"), envir = map_env)
fishery_map <- map_env$fishery_map
required <- c(
  "fishery", "fishery_name", "region", "group", "source_recipe",
  "tag_recapture_group", "tag_recapture_name", "selectivity_group",
  "selectivity_name", "selectivity_form", "selectivity_constraint"
)
if (!is.data.frame(fishery_map) || nrow(fishery_map) != 33L ||
    !all(required %in% names(fishery_map)) ||
    !identical(as.integer(fishery_map$fishery), seq_len(33L))) {
  stop("The diagnostic fishery map is incomplete or not ordered by fishery.", call. = FALSE)
}
if (!identical(as.integer(fishery_map$region[c(26L, 28L)]), c(4L, 4L)) ||
    !identical(as.character(fishery_map$fishery_name[c(26L, 28L)]),
               c("26.PS.ASS.EAST.4", "28.PS.UNA.EAST.4"))) {
  stop("Region-4 east fishery labels do not match the diagnostic map.", call. = FALSE)
}

payload$mappings$fisheries <- fishery_map[, required, drop = FALSE]
payload$data_vintage <- "2026-08-08"
dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
saveRDS(payload, output_file, compress = "xz")
message("Updated compact public fishery map: ", output_file)
