#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
repo_root <- if (length(args) >= 1L) normalizePath(args[[1L]], mustWork = TRUE) else normalizePath(".", mustWork = TRUE)
output_dir <- if (length(args) >= 2L) args[[2L]] else file.path(repo_root, "diagnostic-report-output")
if (!grepl("^/", output_dir)) output_dir <- file.path(repo_root, output_dir)
model_dir <- Sys.getenv("DIAGNOSTIC_MODEL_DIR", file.path(repo_root, "final-run-release-check"))
if (!grepl("^/", model_dir)) model_dir <- file.path(repo_root, model_dir)
model_dir <- normalizePath(model_dir, mustWork = TRUE)
mfclshiny_repo <- Sys.getenv("MFCLSHINY_REPO", "/home/kyuhank/Desktop/SPC/mfclshiny")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, mustWork = TRUE)

if (dir.exists(mfclshiny_repo) && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(mfclshiny_repo, quiet = TRUE, export_all = FALSE)
}
if (!requireNamespace("mfclshiny", quietly = TRUE)) {
  stop("mfclshiny is required to build the Diagnostic report.", call. = FALSE)
}

app_output <- file.path(output_dir, "mfclshiny")
mfclshiny::build_app_report_figures(
  model_dir = model_dir,
  output_dir = app_output,
  title = "BET 2026 Diagnostic model figures",
  formats = c("png", "pdf"),
  dpi = 180,
  interactive_viewer = TRUE,
  species_code = "BET",
  species_label = "bigeye tuna",
  assessment_year = "2026",
  max_fisheries = 33L,
  render_html = TRUE,
  overwrite = TRUE
)

source(file.path(repo_root, "diagnostic-report", "R", "build_uncertainty.R"), local = new.env(parent = globalenv()))

template <- file.path(repo_root, "diagnostic-report", "diagnostic-report.qmd")
css <- file.path(repo_root, "diagnostic-report", "report.css")
invisible(file.copy(template, file.path(output_dir, "diagnostic-report.qmd"), overwrite = TRUE))
invisible(file.copy(css, file.path(output_dir, "report.css"), overwrite = TRUE))

old <- setwd(output_dir)
on.exit(setwd(old), add = TRUE)
status <- system2(
  "quarto",
  c("render", "diagnostic-report.qmd", "--to", "html", "--output", "bet-2026-diagnostic-model-report.html")
)
if (!identical(status, 0L)) stop("Quarto report render failed.", call. = FALSE)

manifest <- list.files(output_dir, recursive = TRUE, full.names = TRUE)
manifest <- manifest[file.info(manifest)$isdir %in% FALSE]
manifest_df <- data.frame(
  file = substring(normalizePath(manifest, mustWork = TRUE), nchar(normalizePath(output_dir, mustWork = TRUE)) + 2L),
  bytes = file.info(manifest)$size,
  stringsAsFactors = FALSE
)
write.csv(manifest_df, file.path(output_dir, "report-manifest.csv"), row.names = FALSE)

message("Wrote BET 2026 Diagnostic model report to ", file.path(output_dir, "bet-2026-diagnostic-model-report.html"))
