#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
repo_root <- if (length(args) >= 1L) normalizePath(args[[1L]], mustWork = TRUE) else normalizePath(".", mustWork = TRUE)
output_dir <- if (length(args) >= 2L) args[[2L]] else file.path(repo_root, "diagnostic-report-output")
if (!grepl("^/", output_dir)) output_dir <- file.path(repo_root, output_dir)
source_model_dir <- Sys.getenv("DIAGNOSTIC_MODEL_DIR", "")
if (!nzchar(source_model_dir)) stop("DIAGNOSTIC_MODEL_DIR is required.", call. = FALSE)
if (!grepl("^/", source_model_dir)) source_model_dir <- file.path(repo_root, source_model_dir)
source_model_dir <- normalizePath(source_model_dir, mustWork = TRUE)
mfclshiny_repo <- Sys.getenv("MFCLSHINY_REPO", "")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, mustWork = TRUE)
if (nzchar(mfclshiny_repo) && dir.exists(mfclshiny_repo) && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(mfclshiny_repo, quiet = TRUE, export_all = FALSE)
}
if (!requireNamespace("mfclshiny", quietly = TRUE) ||
    !all(c("build_diagnostic_report", "restore_model_payload_files") %in% getNamespaceExports("mfclshiny"))) {
  stop("Current mfclshiny Diagnostic report and payload APIs are required.", call. = FALSE)
}

expected_final_sha <- "21dcaea9db8c89ddc8c29fa3c3a5e514b50bef6e26587c168c00c05f35fbebc3"
payload_file <- file.path(source_model_dir, "model_payload.rds")
if (!file.exists(payload_file)) stop("Missing model_payload.rds: ", payload_file, call. = FALSE)

staging_root <- tempfile("diagnostic-job21641-")
restored_dir <- file.path(staging_root, "Diagnostic")
dir.create(restored_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(staging_root, recursive = TRUE, force = TRUE), add = TRUE)
mfclshiny::restore_model_payload_files(payload_file, output_dir = restored_dir, overwrite = TRUE)
final_par <- file.path(restored_dir, "final.par")
if (!file.exists(final_par)) stop("The payload did not restore final.par.", call. = FALSE)
hash_output <- system2("sha256sum", final_par, stdout = TRUE, stderr = TRUE)
observed_final_sha <- strsplit(hash_output[[1L]], "[[:space:]]+")[[1L]][[1L]]
if (!identical(observed_final_sha, expected_final_sha)) {
  stop(
    "This is not the Job 21641 payload. Expected final.par SHA-256 ",
    expected_final_sha, "; observed ", observed_final_sha, call. = FALSE
  )
}

file.copy(payload_file, file.path(restored_dir, "model_payload.rds"), overwrite = TRUE)
for (name in c("model_payload_manifest.csv", "model_payload_manifest.json")) {
  source <- file.path(source_model_dir, name)
  if (file.exists(source)) file.copy(source, file.path(restored_dir, name), overwrite = TRUE)
}
hessian_source <- file.path(source_model_dir, "hessian")
if (!dir.exists(hessian_source)) stop("Job 21641 Hessian attachment is required.", call. = FALSE)
if (!file.exists(file.path(hessian_source, "bet.hes"))) {
  stop("The full native bet.hes matrix is required; use the verified Job 22196 restoration.", call. = FALSE)
}
if (!file.copy(hessian_source, restored_dir, recursive = TRUE, overwrite = TRUE)) {
  stop("Could not stage the Job 21641 Hessian attachment.", call. = FALSE)
}

Sys.setenv(
  DIAGNOSTIC_MODEL_DIR = restored_dir,
  DIAGNOSTIC_REPORT_OUTPUT_DIR = output_dir,
  DIAGNOSTIC_REPORT_REFERENCE_DIR = file.path(repo_root, "results", "reference", "uncertainty")
)
source(file.path(repo_root, "diagnostic-report", "R", "build_uncertainty.R"), local = new.env(parent = globalenv()))

model_job <- Sys.getenv("MODEL_JOB", Sys.getenv("DIAGNOSTIC_MODEL_JOB", "21641"))
result <- mfclshiny::build_diagnostic_report(
  model_dir = restored_dir,
  output_dir = output_dir,
  title = "BET 2026 Diagnostic model",
  model_job = model_job,
  species_code = "BET",
  species_label = "bigeye tuna",
  assessment_year = "2026",
  formats = c("png", "pdf"),
  dpi = as.integer(Sys.getenv("DIAGNOSTIC_REPORT_DPI", "400")),
  recent_years = 4L,
  max_fisheries = 33L,
  interactive_viewer = TRUE,
  overwrite = TRUE,
  recursive = FALSE
)

fragment_file <- file.path(output_dir, "hessian-report-fragment.html")
if (file.exists(fragment_file) && file.exists(result$html)) {
  html <- paste(readLines(result$html, warn = FALSE), collapse = "\n")
  fragment <- paste(readLines(fragment_file, warn = FALSE), collapse = "\n")
  marker <- if (grepl("</main>", html, fixed = TRUE)) "</main>" else "</body>"
  html <- sub(marker, paste0(fragment, "\n", marker), html, fixed = TRUE)
  writeLines(html, result$html, useBytes = TRUE)
}

provenance <- data.frame(
  item = c(
    "Model", "Source Kflow job", "Final PAR SHA-256", "Steepness",
    "Tag tau", "Selectivity", "Hessian calculation", "Raw Hessian restoration",
    "mfclkit ref", "mfclshiny ref"
  ),
  value = c(
    "Diagnostic", "21641", expected_final_sha, "0.90 fixed", "2 fixed",
    "33 independent groups; F10 and F33 weak non-decreasing penalties 10000",
    "22020", "22196", Sys.getenv("MFCLKIT_GITHUB_REF", ""), Sys.getenv("MFCLSHINY_GITHUB_REF", "")
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(provenance, file.path(output_dir, "report-provenance.csv"), row.names = FALSE)

manifest <- list.files(output_dir, recursive = TRUE, full.names = TRUE)
manifest <- manifest[file.info(manifest)$isdir %in% FALSE]
root <- normalizePath(output_dir, mustWork = TRUE)
manifest_df <- data.frame(
  file = substring(normalizePath(manifest, mustWork = TRUE), nchar(root) + 2L),
  bytes = file.info(manifest)$size,
  stringsAsFactors = FALSE
)
utils::write.csv(manifest_df, file.path(output_dir, "report-manifest.csv"), row.names = FALSE)
message("Wrote verified Job 21641 Diagnostic report to ", result$html)
