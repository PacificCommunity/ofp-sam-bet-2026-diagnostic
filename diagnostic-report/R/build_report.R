#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
repo_root <- if (length(args) >= 1L) normalizePath(args[[1L]], mustWork = TRUE) else normalizePath(".", mustWork = TRUE)
output_dir <- if (length(args) >= 2L) args[[2L]] else file.path(repo_root, "diagnostic-report-output")
if (!grepl("^/", output_dir)) output_dir <- file.path(repo_root, output_dir)
model_dir <- Sys.getenv("DIAGNOSTIC_MODEL_DIR", "")
if (!nzchar(model_dir)) stop("DIAGNOSTIC_MODEL_DIR is required.", call. = FALSE)
if (!grepl("^/", model_dir)) model_dir <- file.path(repo_root, model_dir)
model_dir <- normalizePath(model_dir, mustWork = TRUE)
mfclshiny_repo <- Sys.getenv("MFCLSHINY_REPO", "")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, mustWork = TRUE)
if (nzchar(mfclshiny_repo) && dir.exists(mfclshiny_repo) && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(mfclshiny_repo, quiet = TRUE, export_all = FALSE)
}
if (!requireNamespace("mfclshiny", quietly = TRUE) ||
    !"build_diagnostic_report" %in% getNamespaceExports("mfclshiny")) {
  stop("mfclshiny::build_diagnostic_report() is required.", call. = FALSE)
}

model_job <- Sys.getenv("MODEL_JOB", Sys.getenv("DIAGNOSTIC_MODEL_JOB", ""))
result <- mfclshiny::build_diagnostic_report(
  model_dir = model_dir,
  output_dir = output_dir,
  title = "BET 2026 Diagnostic model report",
  model_job = model_job,
  species_code = "BET",
  species_label = "bigeye tuna",
  assessment_year = "2026",
  formats = c("png", "pdf"),
  dpi = as.integer(Sys.getenv("DIAGNOSTIC_REPORT_DPI", "300")),
  recent_years = 4L,
  max_fisheries = 33L,
  interactive_viewer = TRUE,
  overwrite = TRUE,
  recursive = FALSE
)

manifest <- list.files(output_dir, recursive = TRUE, full.names = TRUE)
manifest <- manifest[file.info(manifest)$isdir %in% FALSE]
root <- normalizePath(output_dir, mustWork = TRUE)
manifest_df <- data.frame(
  file = substring(normalizePath(manifest, mustWork = TRUE), nchar(root) + 2L),
  bytes = file.info(manifest)$size,
  stringsAsFactors = FALSE
)
utils::write.csv(manifest_df, file.path(output_dir, "report-manifest.csv"), row.names = FALSE)
message("Wrote Diagnostic model report to ", result$html)
