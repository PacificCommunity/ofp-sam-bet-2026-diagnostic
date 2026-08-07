#!/usr/bin/env Rscript

# Generate annual F/FMSY Hessian intervals from the full MFCL dependent-variable
# calculation.  The calculation reuses the fitted parameters and Hessian; it
# does not refit the diagnostic model.

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop(
    "Usage: generate_fishing_mortality_uncertainty.R FULL_GRADIENT_DIR OUTPUT_CSV",
    call. = FALSE
  )
}

gradient_dir <- normalizePath(args[[1L]], mustWork = TRUE)
output_file <- args[[2L]]

expected_sha <- c(
  "final.par" = "21dcaea9db8c89ddc8c29fa3c3a5e514b50bef6e26587c168c00c05f35fbebc3",
  "bet.hes" = "e289a150c45930c2f4f164fb43432d5c034d8caec7bda7ce664caca9e4ad20c5",
  "bet.dep" = "406499fd39a792de4935f104fc69bceb64bc87ccb8f7aa33f7d445be9c5a2817",
  "deplabel.tmp" = "31ea0cff3bc967b95529ce33ba09a33de5c0d94e6c3549b2ab0154ddf79313ed"
)

sha256 <- function(path) {
  result <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  if (!length(result)) stop("Could not calculate SHA-256 for ", path, call. = FALSE)
  strsplit(result[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

source_files <- file.path(gradient_dir, names(expected_sha))
if (any(!file.exists(source_files))) {
  stop("Missing full MFCL dependent-variable source file.", call. = FALSE)
}
observed_sha <- vapply(source_files, sha256, character(1L))
if (!identical(unname(observed_sha), unname(expected_sha))) {
  bad <- names(expected_sha)[observed_sha != expected_sha]
  stop("MFCL source checksum mismatch: ", paste(bad, collapse = ", "), call. = FALSE)
}

read_gradient <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  n_parameter <- readBin(con, integer(), n = 1L, size = 4L, endian = "little")
  n_derived <- readBin(con, integer(), n = 1L, size = 4L, endian = "little")
  values <- readBin(con, numeric(), n = n_parameter * n_derived, size = 8L, endian = "little")
  if (length(values) != n_parameter * n_derived) stop("Incomplete MFCL gradient matrix.", call. = FALSE)
  matrix(values, nrow = n_derived, ncol = n_parameter, byrow = TRUE)
}

read_hessian <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  n_parameter <- readBin(con, integer(), n = 1L, size = 4L, endian = "little")
  values <- readBin(con, numeric(), n = n_parameter * n_parameter, size = 8L, endian = "little")
  if (length(values) != n_parameter * n_parameter) stop("Incomplete MFCL Hessian.", call. = FALSE)
  hessian <- matrix(values, nrow = n_parameter, ncol = n_parameter, byrow = TRUE)
  (hessian + t(hessian)) / 2
}

read_labels <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) %% 2L) stop("Incomplete MFCL label file.", call. = FALSE)
  data.frame(
    value = as.numeric(lines[seq.int(1L, length(lines), by = 2L)]),
    label = lines[seq.int(2L, length(lines), by = 2L)],
    stringsAsFactors = FALSE
  )
}

gradient <- read_gradient(file.path(gradient_dir, "bet.dep"))
hessian <- read_hessian(file.path(gradient_dir, "bet.hes"))
labels <- read_labels(file.path(gradient_dir, "deplabel.tmp"))
if (ncol(gradient) != 1997L || nrow(hessian) != 1997L || nrow(gradient) != nrow(labels)) {
  stop("Unexpected Diagnostic-model Hessian or gradient dimensions.", call. = FALSE)
}

period <- seq_len(292L)
log_rows <- match(paste0("ln_F/Fmsy(", period, ")"), labels$label)
raw_rows <- match(paste0("F/Fmsy(", period, ")"), labels$label)
if (anyNA(log_rows) || anyNA(raw_rows)) stop("Annual F/FMSY dependent variables are incomplete.", call. = FALSE)
log_value <- labels$value[log_rows]
estimate_quarterly <- labels$value[raw_rows]
if (max(abs(exp(log_value) - estimate_quarterly)) > 1e-7) {
  stop("Log and raw F/FMSY dependent-variable values disagree.", call. = FALSE)
}

# For each calendar year, differentiate mean(exp(log(F/FMSY))) so that the
# four quarterly gradients retain their full covariance.
annual_gradient <- matrix(NA_real_, nrow = 73L, ncol = ncol(gradient))
annual_estimate <- numeric(73L)
for (year_index in seq_len(73L)) {
  rows <- 4L * (year_index - 1L) + seq_len(4L)
  values <- estimate_quarterly[rows]
  annual_estimate[[year_index]] <- mean(values)
  weight <- values / sum(values)
  annual_gradient[year_index, ] <- colSums(gradient[log_rows[rows], , drop = FALSE] * weight)
}

chol_hessian <- chol(hessian)
solved <- backsolve(chol_hessian, forwardsolve(t(chol_hessian), t(annual_gradient)))
variance_log <- rowSums(annual_gradient * t(solved))
if (any(!is.finite(variance_log)) || any(variance_log < -1e-10)) {
  stop("Invalid annual F/FMSY delta-method variance.", call. = FALSE)
}
se_log <- sqrt(pmax(variance_log, 0))

result <- data.frame(
  year = 1952:2024,
  quantity = "fishing_mortality",
  estimate = annual_estimate,
  se_log = se_log,
  lower_50 = annual_estimate * exp(-stats::qnorm(0.75) * se_log),
  upper_50 = annual_estimate * exp(stats::qnorm(0.75) * se_log),
  lower_80 = annual_estimate * exp(-stats::qnorm(0.90) * se_log),
  upper_80 = annual_estimate * exp(stats::qnorm(0.90) * se_log),
  lower_95 = annual_estimate * exp(-stats::qnorm(0.975) * se_log),
  upper_95 = annual_estimate * exp(stats::qnorm(0.975) * se_log),
  final_par_sha256 = unname(expected_sha[["final.par"]]),
  hessian_sha256 = unname(expected_sha[["bet.hes"]]),
  gradient_sha256 = unname(expected_sha[["bet.dep"]]),
  method = "MFCL dependent-variable gradients; annual log-scale delta method including FMSY covariance",
  stringsAsFactors = FALSE
)

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(result, output_file, row.names = FALSE)
message("Wrote ", nrow(result), " verified annual F/FMSY estimates to ", output_file)
