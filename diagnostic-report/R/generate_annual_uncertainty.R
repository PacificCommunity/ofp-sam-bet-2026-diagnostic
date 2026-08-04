#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) {
  stop(
    paste(
      "Usage: generate_annual_uncertainty.R NATIVE_GRADIENT_DIR",
      "NATIVE_TIMESERIES_CSV ANNUAL_OUTPUT_CSV QUARTERLY_OUTPUT_CSV"
    ),
    call. = FALSE
  )
}

gradient_dir <- normalizePath(args[[1L]], mustWork = TRUE)
time_series_file <- normalizePath(args[[2L]], mustWork = TRUE)
output_file <- args[[3L]]
quarterly_output_file <- args[[4L]]

expected_sha <- c(
  "final.par" = "21dcaea9db8c89ddc8c29fa3c3a5e514b50bef6e26587c168c00c05f35fbebc3",
  "bet.hes" = "e289a150c45930c2f4f164fb43432d5c034d8caec7bda7ce664caca9e4ad20c5",
  "bet.dep" = "2a1d8aca95b935951cb371014dc53250bca5ead96b6750c991b6e3b51a154b04",
  "bet.dp2" = "278bee47cd45eccaf00a839b10f2e01146092ada4f32ea3a0afa4a9b2b55b53f",
  "deplabel.tmp" = "94fb712e265a3403f4c4916e82370cc3693e1435f67577ffdadd425aaf38c4cc",
  "deplabel_noeff.tmp" = "b6e4ed38c442094cb5e079513d498b88dcd148c2c829f311e2ca4e2cb9b7e47c"
)

sha256 <- function(path) {
  output <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  if (!length(output)) stop("Could not calculate SHA-256 for ", path, call. = FALSE)
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

source_files <- file.path(gradient_dir, names(expected_sha))
missing <- source_files[!file.exists(source_files)]
if (length(missing)) stop("Missing native MFCL source file: ", missing[[1L]], call. = FALSE)
observed_sha <- vapply(source_files, sha256, character(1L))
if (!identical(unname(observed_sha), unname(expected_sha))) {
  mismatch <- names(expected_sha)[observed_sha != expected_sha]
  stop("Native MFCL source checksum mismatch: ", paste(mismatch, collapse = ", "), call. = FALSE)
}

read_native_matrix <- function(path) {
  connection <- file(path, "rb")
  on.exit(close(connection), add = TRUE)
  n_parameter <- readBin(connection, integer(), n = 1L, size = 4L, endian = "little")
  n_derived <- readBin(connection, integer(), n = 1L, size = 4L, endian = "little")
  values <- readBin(
    connection, numeric(), n = n_parameter * n_derived,
    size = 8L, endian = "little"
  )
  if (length(values) != n_parameter * n_derived) {
    stop("Incomplete native MFCL gradient matrix: ", path, call. = FALSE)
  }
  matrix(values, nrow = n_derived, ncol = n_parameter, byrow = TRUE)
}

read_native_hessian <- function(path) {
  connection <- file(path, "rb")
  on.exit(close(connection), add = TRUE)
  n_parameter <- readBin(connection, integer(), n = 1L, size = 4L, endian = "little")
  values <- readBin(
    connection, numeric(), n = n_parameter * n_parameter,
    size = 8L, endian = "little"
  )
  if (length(values) != n_parameter * n_parameter) {
    stop("Incomplete native MFCL Hessian: ", path, call. = FALSE)
  }
  value <- matrix(values, nrow = n_parameter, ncol = n_parameter, byrow = TRUE)
  (value + t(value)) / 2
}

read_labels <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) %% 2L != 0L) stop("Incomplete native MFCL label file: ", path, call. = FALSE)
  data.frame(
    value = as.numeric(lines[seq.int(1L, length(lines), by = 2L)]),
    label = lines[seq.int(2L, length(lines), by = 2L)],
    stringsAsFactors = FALSE
  )
}

indexed_rows <- function(labels, prefix, count) {
  wanted <- paste0(prefix, "(", seq_len(count), ")")
  rows <- match(wanted, labels$label)
  if (anyNA(rows)) stop("Missing native MFCL dependent variable: ", wanted[is.na(rows)][[1L]], call. = FALSE)
  rows
}

annual_log_gradient <- function(log_value, gradient) {
  if (length(log_value) != 292L || nrow(gradient) != 292L) {
    stop("Expected 292 quarterly values for 1952--2024.", call. = FALSE)
  }
  result <- matrix(NA_real_, nrow = 73L, ncol = ncol(gradient))
  for (year_index in seq_len(73L)) {
    rows <- 4L * (year_index - 1L) + seq_len(4L)
    shifted <- log_value[rows] - max(log_value[rows])
    weight <- exp(shifted) / sum(exp(shifted))
    result[year_index, ] <- colSums(gradient[rows, , drop = FALSE] * weight)
  }
  result
}

gradient <- read_native_matrix(file.path(gradient_dir, "bet.dep"))
gradient_noeff <- read_native_matrix(file.path(gradient_dir, "bet.dp2"))
hessian <- read_native_hessian(file.path(gradient_dir, "bet.hes"))
if (ncol(gradient) != 1997L || ncol(gradient_noeff) != 1997L || nrow(hessian) != 1997L) {
  stop("Native MFCL Hessian and gradient dimensions do not match 1,997 parameters.", call. = FALSE)
}

labels <- read_labels(file.path(gradient_dir, "deplabel.tmp"))
labels_noeff <- read_labels(file.path(gradient_dir, "deplabel_noeff.tmp"))
if (nrow(labels) != nrow(gradient) || nrow(labels_noeff) != nrow(gradient_noeff)) {
  stop("Native MFCL labels do not match the gradient matrices.", call. = FALSE)
}

adult_rows <- indexed_rows(labels, "adult_rbio", 292L)
recruitment_rows <- indexed_rows(labels, "ln_abs_recr", 292L)
adult_noeff_rows <- indexed_rows(labels_noeff, "adult_rbio_noeff", 292L)

adult_gradient <- annual_log_gradient(labels$value[adult_rows], gradient[adult_rows, , drop = FALSE])
depletion_gradient <- annual_log_gradient(
  labels$value[adult_rows] - labels_noeff$value[adult_noeff_rows],
  gradient[adult_rows, , drop = FALSE] - gradient_noeff[adult_noeff_rows, , drop = FALSE]
)
recruitment_gradient <- annual_log_gradient(
  labels$value[recruitment_rows], gradient[recruitment_rows, , drop = FALSE]
)

annual_gradient <- rbind(
  depletion_gradient,
  adult_gradient,
  recruitment_gradient
)
quarterly_gradient <- rbind(
  gradient[adult_rows, , drop = FALSE] - gradient_noeff[adult_noeff_rows, , drop = FALSE],
  gradient[adult_rows, , drop = FALSE],
  gradient[recruitment_rows, , drop = FALSE]
)
quantity <- rep(c("depletion", "spawning_potential", "recruitment"), each = 73L)
year <- rep(1952:2024, times = 3L)

time_series <- utils::read.csv(time_series_file, stringsAsFactors = FALSE)
required <- c("year", "depletion", "spawning_potential", "recruitment")
if (!all(required %in% names(time_series)) ||
    !identical(as.integer(time_series$year), 1952:2024)) {
  stop("The native annual point-estimate table is incomplete or out of order.", call. = FALSE)
}
estimate <- c(time_series$depletion, time_series$spawning_potential, time_series$recruitment)

# Validate the aggregation against the full-precision payload values before using
# those values as the plotted maximum-likelihood estimates.
adult_quarter <- exp(labels$value[adult_rows])
adult_noeff_quarter <- exp(labels_noeff$value[adult_noeff_rows])
recruitment_quarter <- exp(labels$value[recruitment_rows])
annual_sum <- function(value) rowSums(matrix(value, ncol = 4L, byrow = TRUE))
annual_mean <- function(value) rowMeans(matrix(value, ncol = 4L, byrow = TRUE))
label_estimate <- c(
  annual_mean(adult_quarter / adult_noeff_quarter),
  annual_mean(adult_quarter) / 1e6,
  annual_sum(recruitment_quarter) / 1e6
)
relative_error <- abs(label_estimate - estimate) / pmax(abs(estimate), .Machine$double.eps)
if (max(relative_error) > 5e-4) {
  stop("Annual aggregation does not reproduce the native MFCL point estimates.", call. = FALSE)
}

chol_hessian <- chol(hessian)
delta_se <- function(value) {
  solved <- backsolve(
    chol_hessian,
    forwardsolve(t(chol_hessian), t(value))
  )
  variance_log <- rowSums(value * t(solved))
  if (any(!is.finite(variance_log)) || any(variance_log < -1e-10)) {
    stop("Invalid delta-method variance from the native Hessian.", call. = FALSE)
  }
  sqrt(pmax(variance_log, 0))
}
se_log <- delta_se(annual_gradient)

result <- data.frame(
  year = year,
  quantity = quantity,
  estimate = estimate,
  se_log = se_log,
  lower_50 = estimate * exp(-stats::qnorm(0.75) * se_log),
  upper_50 = estimate * exp(stats::qnorm(0.75) * se_log),
  lower_80 = estimate * exp(-stats::qnorm(0.90) * se_log),
  upper_80 = estimate * exp(stats::qnorm(0.90) * se_log),
  lower_95 = estimate * exp(-stats::qnorm(0.975) * se_log),
  upper_95 = estimate * exp(stats::qnorm(0.975) * se_log),
  final_par_sha256 = unname(expected_sha[["final.par"]]),
  hessian_sha256 = unname(expected_sha[["bet.hes"]]),
  gradient_sha256 = unname(expected_sha[["bet.dep"]]),
  noeff_gradient_sha256 = unname(expected_sha[["bet.dp2"]]),
  method = paste(
    "native MFCL dependent-variable gradients; annual log-scale delta method",
    "retaining full within-year covariance"
  ),
  stringsAsFactors = FALSE
)

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(quarterly_output_file), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(result, output_file, row.names = FALSE)

quarterly_estimate <- c(
  adult_quarter / adult_noeff_quarter,
  adult_quarter / 1e6,
  recruitment_quarter / 1e6
)
quarterly_se_log <- delta_se(quarterly_gradient)
quarterly_result <- data.frame(
  year = rep(rep(1952:2024, each = 4L), times = 3L),
  quarter = rep(rep(seq_len(4L), times = 73L), times = 3L),
  period = rep(rep(1952:2024, each = 4L) + rep(0:3, times = 73L) / 4, times = 3L),
  quantity = rep(c("depletion", "spawning_potential", "recruitment"), each = 292L),
  estimate = quarterly_estimate,
  se_log = quarterly_se_log,
  lower_50 = quarterly_estimate * exp(-stats::qnorm(0.75) * quarterly_se_log),
  upper_50 = quarterly_estimate * exp(stats::qnorm(0.75) * quarterly_se_log),
  lower_80 = quarterly_estimate * exp(-stats::qnorm(0.90) * quarterly_se_log),
  upper_80 = quarterly_estimate * exp(stats::qnorm(0.90) * quarterly_se_log),
  lower_95 = quarterly_estimate * exp(-stats::qnorm(0.975) * quarterly_se_log),
  upper_95 = quarterly_estimate * exp(stats::qnorm(0.975) * quarterly_se_log),
  final_par_sha256 = unname(expected_sha[["final.par"]]),
  hessian_sha256 = unname(expected_sha[["bet.hes"]]),
  gradient_sha256 = unname(expected_sha[["bet.dep"]]),
  noeff_gradient_sha256 = unname(expected_sha[["bet.dp2"]]),
  method = "native MFCL quarterly dependent-variable gradients; log-scale delta method",
  stringsAsFactors = FALSE
)

utils::write.csv(quarterly_result, quarterly_output_file, row.names = FALSE)
message("Wrote ", nrow(result), " verified annual native-MFCL estimates to ", output_file)
message(
  "Wrote ", nrow(quarterly_result),
  " verified quarterly native-MFCL estimates to ", quarterly_output_file
)
