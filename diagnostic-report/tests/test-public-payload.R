options(stringsAsFactors = FALSE)

payload_file <- file.path("diagnostic-report", "data", "diagnostic-report-data.rds")
if (!file.exists(payload_file)) stop("Missing compact diagnostic report payload.", call. = FALSE)
payload <- readRDS(payload_file)

if (any(c("final_diagnostic_job", "jobs") %in% names(payload$source))) {
  stop("The public payload must not retain scheduler job identifiers.", call. = FALSE)
}
if (!identical(sort(payload$source$archive_roles), sort(c(
  "model_payload", "retrospective", "jitter", "likelihood_profile", "self_test", "aspm"
)))) {
  stop("The public payload must retain only stable archive roles.", call. = FALSE)
}

public_files <- c(
  "diagnostic-report/kflow.yaml",
  "diagnostic-report/README.md",
  "diagnostic-report/submit.py",
  "diagnostic-report/R/prepare_public_payload.R",
  "diagnostic-report/R/build_report.R"
)
for (path in public_files) {
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  if (grepl("22974|22020|22196|21641", text, fixed = FALSE)) {
    stop("Public source contains an execution identifier: ", path, call. = FALSE)
  }
}

cat("Validated public payload provenance and source files.\n")
