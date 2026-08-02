#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
repo_root <- if (length(args) >= 1L) normalizePath(args[[1L]], mustWork = TRUE) else normalizePath(".", mustWork = TRUE)
output_dir <- if (length(args) >= 2L) args[[2L]] else file.path(repo_root, "diagnostic-report-output")
variance_file <- if (length(args) >= 3L) args[[3L]] else file.path(repo_root, "results", "reference", "uncertainty", "bet.var")
model_dir <- Sys.getenv("DIAGNOSTIC_MODEL_DIR", file.path(repo_root, "final-run-release-check"))
if (!grepl("^/", model_dir)) model_dir <- file.path(repo_root, model_dir)
model_dir <- normalizePath(model_dir, mustWork = TRUE)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
figure_dir <- file.path(output_dir, "figures")
table_dir <- file.path(output_dir, "tables")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(variance_file)) {
  stop("Missing native MFCL delta-method file: ", variance_file, call. = FALSE)
}

parse_native_var <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines)) & !grepl("^\\s*#", lines)]
  rx <- "^\\s*([0-9]+)\\s+(\\*+|[-+0-9.eE]+)\\s+([-+0-9.eE]+)\\s+(.+?)\\s*$"
  matched <- regexec(rx, lines)
  pieces <- regmatches(lines, matched)
  pieces <- pieces[lengths(pieces) == 5L]
  out <- data.frame(
    row = as.integer(vapply(pieces, `[[`, character(1), 2L)),
    se_text = vapply(pieces, `[[`, character(1), 3L),
    estimate = as.numeric(vapply(pieces, `[[`, character(1), 4L)),
    remainder = vapply(pieces, `[[`, character(1), 5L),
    stringsAsFactors = FALSE
  )
  out$se <- suppressWarnings(as.numeric(out$se_text))
  out$se[grepl("^[*]+$", out$se_text)] <- 0
  out$section <- cumsum(c(TRUE, diff(out$row) <= 0L))
  out
}

extract_index <- function(x, stem) {
  out <- sub(paste0("^", stem, "\\(([0-9]+)\\).*$"), "\\1", x)
  suppressWarnings(as.integer(ifelse(out == x, NA_character_, out)))
}

period_table <- function(index, start_year = 1952L, seasons = 4L) {
  data.frame(
    period = index,
    year = start_year + (index - 1L) %/% seasons,
    quarter = 1L + (index - 1L) %% seasons,
    time = start_year + (index - 1L) / seasons
  )
}

log_interval <- function(estimate, se, scale = 1) {
  data.frame(
    estimate = exp(estimate) / scale,
    lower = exp(estimate - 1.96 * se) / scale,
    upper = exp(estimate + 1.96 * se) / scale
  )
}

raw_interval <- function(estimate, se, nonnegative = TRUE) {
  lower <- estimate - 1.96 * se
  if (isTRUE(nonnegative)) lower <- pmax(0, lower)
  data.frame(estimate = estimate, lower = lower, upper = estimate + 1.96 * se)
}

var <- parse_native_var(variance_file)
general <- var[var$section == min(var$section), , drop = FALSE]
contrasts <- var[var$section == max(var$section), , drop = FALSE]

spawning <- general[grepl("^adult_rbio\\([0-9]+\\)$", general$remainder), , drop = FALSE]
spawning$period <- extract_index(spawning$remainder, "adult_rbio")
spawning <- spawning[!duplicated(spawning$period) & spawning$period <= 292L, , drop = FALSE]
spawning <- cbind(period_table(spawning$period), log_interval(spawning$estimate, spawning$se, 1e6))
spawning$quantity <- "Spawning potential"
spawning$unit <- "10^3 MT"

recruitment <- general[grepl("^ln_abs_recr\\([0-9]+\\)$", general$remainder), , drop = FALSE]
recruitment$period <- extract_index(recruitment$remainder, "ln_abs_recr")
recruitment <- recruitment[!duplicated(recruitment$period) & recruitment$period <= 292L, , drop = FALSE]
recruitment <- cbind(period_table(recruitment$period), log_interval(recruitment$estimate, recruitment$se, 1e6))
recruitment$quantity <- "Recruitment"
recruitment$unit <- "millions"

dynamic_rx <- "^adult_rbio\\(([0-9]+)\\) - adult_rbio_noeff\\(([0-9]+)\\).*$"
dynamic <- contrasts[grepl(dynamic_rx, contrasts$remainder), , drop = FALSE]
dynamic$period <- as.integer(sub(dynamic_rx, "\\1", dynamic$remainder))
dynamic <- dynamic[dynamic$period <= 292L & !duplicated(dynamic$period), , drop = FALSE]
dynamic <- cbind(period_table(dynamic$period), log_interval(dynamic$estimate, dynamic$se))
dynamic$quantity <- "Dynamic spawning depletion"
dynamic$unit <- "SB(t) / SB(F=0,t)"

numbers <- general[grepl("^ln_abs_N_term_age\\([0-9]+,[0-9]+\\)$", general$remainder), , drop = FALSE]
if (nrow(numbers)) {
  numbers$region <- as.integer(sub("^ln_abs_N_term_age\\(([0-9]+),.*$", "\\1", numbers$remainder))
  numbers$age <- as.integer(sub("^ln_abs_N_term_age\\([0-9]+,([0-9]+)\\)$", "\\1", numbers$remainder))
  n_int <- log_interval(numbers$estimate, numbers$se, 1e6)
  numbers <- cbind(numbers[c("region", "age")], n_int)
  numbers$quantity <- "Terminal abundance at age"
  numbers$unit <- "millions"
}

management_row <- function(label, definition, period, estimate, se, transform = c("log", "raw"), note = "") {
  transform <- match.arg(transform)
  interval <- if (transform == "log") log_interval(estimate, se) else raw_interval(estimate, se)
  data.frame(
    quantity = label,
    definition = definition,
    averaging_period = period,
    estimate = interval$estimate,
    lower_95 = interval$lower,
    upper_95 = interval$upper,
    scale = transform,
    note = note,
    stringsAsFactors = FALSE
  )
}

pick_general <- function(pattern) general[grepl(pattern, general$remainder), , drop = FALSE]
pick_contrast <- function(pattern) contrasts[grepl(pattern, contrasts$remainder), , drop = FALSE]

terminal_mgmt <- pick_contrast("^adult_rbio\\(292\\) - average_adult_rbio_noeff\\(40_periods\\) ")
recent_mgmt <- pick_contrast("^adult_rbio\\(recent\\) - average_adult_rbio_noeff\\(40_periods\\) ")
f_recent <- pick_general("^average_F/Fmsy\\(recent\\)$")
sb_recent <- pick_general("^average_SB/SBmsy\\(recent\\)$")
msy <- pick_general("^MSY$")

management <- do.call(rbind, list(
  management_row(
    "Terminal spawning depletion", "SB(2024 Q4) / mean SBF=0", "SBF=0: 2014 Q1–2023 Q4",
    terminal_mgmt$estimate[[1L]], terminal_mgmt$se[[1L]], "log"
  ),
  management_row(
    "Recent spawning depletion", "mean SB / mean SBF=0", "SB: 2021 Q1–2024 Q4; SBF=0: 2014 Q1–2023 Q4",
    recent_mgmt$estimate[[1L]], recent_mgmt$se[[1L]], "log"
  ),
  management_row(
    "Recent fishing intensity", "Frecent / FMSY", "F: 2020 Q1–2023 Q4",
    f_recent$estimate[[1L]], f_recent$se[[1L]], "raw"
  ),
  management_row(
    "Recent spawning biomass status", "SBrecent / SBMSY", "SB: 2021 Q1–2024 Q4",
    sb_recent$estimate[[1L]], sb_recent$se[[1L]], "raw"
  ),
  management_row(
    "Maximum sustainable yield", "MSY", "Equilibrium reference point",
    msy$estimate[[1L]], msy$se[[1L]], "raw",
    "Point estimate only: this MFCL derivative mode returned zero MSY derivative, so no Hessian interval is reported."
  )
))
management$lower_95[management$quantity == "Maximum sustainable yield"] <- NA_real_
management$upper_95[management$quantity == "Maximum sustainable yield"] <- NA_real_

write.csv(spawning, file.path(table_dir, "spawning-potential-uncertainty.csv"), row.names = FALSE)
write.csv(recruitment, file.path(table_dir, "recruitment-uncertainty.csv"), row.names = FALSE)
write.csv(dynamic, file.path(table_dir, "dynamic-depletion-uncertainty.csv"), row.names = FALSE)
if (nrow(numbers)) write.csv(numbers, file.path(table_dir, "terminal-abundance-at-age-uncertainty.csv"), row.names = FALSE)
write.csv(management, file.path(table_dir, "management-quantities.csv"), row.names = FALSE)
saveRDS(
  list(spawning = spawning, recruitment = recruitment, depletion = dynamic, numbers_at_age = numbers, management = management),
  file.path(output_dir, "diagnostic-uncertainty.rds"),
  compress = "xz"
)

if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Package ggplot2 is required.", call. = FALSE)
if (!requireNamespace("patchwork", quietly = TRUE)) stop("Package patchwork is required.", call. = FALSE)
library(ggplot2)

theme_bet <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", colour = "#153f5f", size = 13),
      plot.subtitle = element_text(colour = "#4b6173"),
      panel.grid.minor = element_blank(),
      axis.title = element_text(face = "bold"),
      legend.position = "bottom"
    )
}

band_plot <- function(data, ylab, title, colour = "#087f8c", log_y = FALSE) {
  p <- ggplot(data, aes(time, estimate)) +
    geom_ribbon(aes(ymin = lower, ymax = upper), fill = colour, alpha = 0.20) +
    geom_line(colour = colour, linewidth = 0.65) +
    labs(x = NULL, y = ylab, title = title) +
    theme_bet()
  if (isTRUE(log_y)) p <- p + scale_y_log10(labels = scales::label_number())
  p
}

p_sb <- band_plot(spawning, "Spawning potential (10³ MT)", "Spawning potential", "#0b7285")
p_dep <- band_plot(dynamic, "SB(t) / SB(F=0,t)", "Dynamic spawning depletion", "#c75b12") +
  geom_hline(yintercept = c(0.2, 0.5), linetype = "dashed", colour = c("#b22222", "#2e7d32"), linewidth = 0.45)
p_rec <- band_plot(recruitment, "Recruitment (millions)", "Quarterly recruitment", "#6a3d9a", log_y = TRUE)

combined <- (p_dep | p_sb) / p_rec +
  patchwork::plot_annotation(
    title = "BET 2026 Diagnostic model: Hessian uncertainty",
    subtitle = "Lines are maximum-likelihood estimates; ribbons are pointwise 95% delta-method intervals."
  )
ggsave(file.path(figure_dir, "hessian-time-series.png"), combined, width = 13, height = 10, dpi = 220, bg = "white")
ggsave(file.path(figure_dir, "hessian-time-series.pdf"), combined, width = 13, height = 10, device = cairo_pdf, bg = "white")

status_plot <- management[management$quantity %in% c("Recent fishing intensity", "Recent spawning biomass status"), ]
p_status <- ggplot(status_plot, aes(estimate, quantity)) +
  geom_vline(xintercept = 1, colour = "#6b7280", linetype = "dashed", linewidth = 0.5) +
  geom_errorbar(aes(xmin = lower_95, xmax = upper_95), orientation = "y", width = 0.12, linewidth = 0.8, colour = "#1b7280") +
  geom_point(size = 3.2, colour = "#c75b12") +
  labs(
    x = "Ratio to MSY reference point",
    y = NULL,
    title = "Recent stock status",
    subtitle = "Pointwise 95% delta-method intervals from the fitted Hessian"
  ) +
  theme_bet()
ggsave(file.path(figure_dir, "management-status-uncertainty.png"), p_status, width = 9, height = 4.5, dpi = 220, bg = "white")
ggsave(file.path(figure_dir, "management-status-uncertainty.pdf"), p_status, width = 9, height = 4.5, device = cairo_pdf, bg = "white")

if (nrow(numbers)) {
  p_numbers <- ggplot(numbers, aes(age, estimate, colour = factor(region), fill = factor(region))) +
    geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.10, colour = NA) +
    geom_line(linewidth = 0.55) +
    facet_wrap(~ region, scales = "free_y", ncol = 3) +
    labs(x = "Age class", y = "Abundance (millions)", colour = "Region", fill = "Region", title = "Terminal abundance at age") +
    theme_bet() + theme(legend.position = "none")
  ggsave(file.path(figure_dir, "terminal-abundance-at-age-uncertainty.png"), p_numbers, width = 12, height = 8, dpi = 220, bg = "white")
}

hessian_file <- file.path(repo_root, "results", "reference", "hessian", "hessian_info.rds")
fit_file <- file.path(repo_root, "results", "reference", "fit-summary.csv")
hessian_summary <- data.frame()
if (file.exists(hessian_file)) {
  h <- readRDS(hessian_file)
  hessian_summary <- data.frame(
    item = c("Parameters", "Positive eigenvalues", "Non-positive eigenvalues", "Smallest eigenvalue", "Largest eigenvalue", "Condition number", "Reliability"),
    value = c(
      h$meta$npars,
      h$eigen$n_positive_eigenvalues,
      h$eigen$n_nonpositive_eigenvalues,
      format(h$eigen$minimum_eigenvalue, digits = 6, scientific = TRUE),
      format(h$eigen$maximum_eigenvalue, digits = 6, scientific = TRUE),
      format(h$eigen$positive_condition_number, digits = 6, scientific = TRUE),
      h$eigen$reliability
    )
  )
  write.csv(hessian_summary, file.path(table_dir, "hessian-summary.csv"), row.names = FALSE)
}
if (file.exists(fit_file)) invisible(file.copy(fit_file, file.path(table_dir, "fit-summary.csv"), overwrite = TRUE))

read_native_hessian <- function(path) {
  if (!file.exists(path)) stop("Missing native MFCL Hessian: ", path, call. = FALSE)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  n <- readBin(con, integer(), n = 1L, size = 4L, endian = .Platform$endian)
  values <- readBin(con, numeric(), n = n * n, size = 8L, endian = .Platform$endian)
  if (!is.finite(n) || n < 1L || length(values) != n * n) {
    stop("Native MFCL Hessian is incomplete or has an invalid dimension.", call. = FALSE)
  }
  hessian <- matrix(values, nrow = n, ncol = n, byrow = TRUE)
  # MFCL itself averages the two finite-difference triangles before its
  # eigendecomposition (ongoing-development src/newl9.cpp).
  (hessian + t(hessian)) / 2
}

mfcl_bound_jacobian <- function(value, lower, upper, scale, constant = 1.570795) {
  internal <- scale * asin(2 * (value - lower) / (upper - lower) - 1) / constant
  (upper - lower) / 2 * cos(internal / scale * constant) * constant / scale
}

mfcl_bound_inverse <- function(value, lower, upper, scale, constant = 1.570795) {
  scale * asin(2 * (value - lower) / (upper - lower) - 1) / constant
}

mfcl_bound_forward <- function(internal, lower, upper, scale, constant = 1.570795) {
  lower + (upper - lower) * (sin(internal / scale * constant) + 1) / 2
}

growth_schedule <- function(parameters, n_age) {
  age <- seq_len(n_age)
  rho <- exp(-parameters[[3L]])
  relative_growth <- (1 - rho^(age - 1)) / (1 - rho^(n_age - 1))
  mean_length <- parameters[[1L]] + (parameters[[2L]] - parameters[[1L]]) * relative_growth
  sd_length <- parameters[[4L]] * exp(parameters[[5L]] * (-1 + 2 * relative_growth))
  data.frame(age = age, mean_length = mean_length, sd_length = sd_length)
}

numeric_gradient <- function(fn, parameters) {
  vapply(seq_along(parameters), function(index) {
    step <- max(abs(parameters[[index]]), 1) * 1e-6
    upper <- lower <- parameters
    upper[[index]] <- upper[[index]] + step
    lower[[index]] <- lower[[index]] - step
    (fn(upper) - fn(lower)) / (2 * step)
  }, numeric(1))
}

delta_se <- function(gradient, covariance) {
  sqrt(max(0, drop(t(gradient) %*% covariance %*% gradient)))
}

build_growth_uncertainty <- function(model_dir,
                                     hessian_path,
                                     hessian_metadata,
                                     draws = 100000L,
                                     seed = 20260803L) {
  if (!requireNamespace("FLR4MFCL", quietly = TRUE)) {
    stop("FLR4MFCL is required for growth uncertainty.", call. = FALSE)
  }
  par_path <- file.path(model_dir, "evaluated.par")
  rep_path <- file.path(model_dir, "plot-evaluated.par.rep")
  par <- FLR4MFCL::read.MFCLPar(par_path)
  rep <- FLR4MFCL::read.MFCLRep(rep_path)
  vb <- FLR4MFCL::growth(par)
  variance <- FLR4MFCL::growth_var_pars(par)
  estimate <- c(as.numeric(vb[, "est"]), as.numeric(variance[, "ini"]))
  lower <- c(as.numeric(vb[, "min"]), as.numeric(variance[, "min"]))
  upper <- c(as.numeric(vb[, "max"]), as.numeric(variance[, "max"]))
  names(estimate) <- names(lower) <- names(upper) <- c("L1", "L40", "K", "SD scale", "SD gradient")

  flag_387 <- tryCatch(FLR4MFCL::flagval(par, 1, 387)$value[[1L]], error = function(e) 0)
  growth_scale <- if (isTRUE(flag_387 != 0)) 3000 else 1000
  bound_scale <- c(1000, growth_scale, growth_scale, 1000, 1000)

  labels <- hessian_metadata$diagnostics$parameter_table$par
  target <- c("vb_coff(1)", "vb_coff(2)", "vb_coff(3)", "var_coff(1)", "var_coff(2)")
  index <- match(target, labels)
  if (anyNA(index) || anyDuplicated(index)) {
    stop("Could not uniquely match all five active growth parameters to the Hessian.", call. = FALSE)
  }

  hessian <- read_native_hessian(hessian_path)
  if (nrow(hessian) != length(labels)) {
    stop("Hessian dimension does not match its parameter map.", call. = FALSE)
  }
  rhs <- matrix(0, nrow(hessian), length(index))
  rhs[cbind(index, seq_along(index))] <- 1
  covariance_internal <- tryCatch({
    chol_hessian <- chol(hessian)
    backsolve(chol_hessian, forwardsolve(t(chol_hessian), rhs))
  }, error = function(e) solve(hessian, rhs))
  covariance_internal <- covariance_internal[index, , drop = FALSE]
  covariance_internal <- (covariance_internal + t(covariance_internal)) / 2
  internal_estimate <- mfcl_bound_inverse(estimate, lower, upper, bound_scale)
  jacobian <- mfcl_bound_jacobian(estimate, lower, upper, bound_scale)
  covariance <- outer(jacobian, jacobian) * covariance_internal
  covariance <- (covariance + t(covariance)) / 2

  draws <- suppressWarnings(as.integer(draws[[1L]]))
  seed <- suppressWarnings(as.integer(seed[[1L]]))
  if (!is.finite(draws) || draws < 10000L) stop("At least 10,000 Hessian draws are required.", call. = FALSE)
  if (!is.finite(seed)) seed <- 20260803L
  set.seed(seed)
  normal_draws <- matrix(stats::rnorm(draws * length(index)), nrow = draws, ncol = length(index))
  internal_draws <- sweep(normal_draws %*% chol(covariance_internal), 2, internal_estimate, "+")
  outside_bounds <- colSums(abs(sweep(internal_draws, 2, bound_scale, "/")) >= 0.9999)
  if (any(outside_bounds > 0L)) {
    stop("Hessian draws reached the penalized edge of an MFCL bound.", call. = FALSE)
  }
  parameter_draws <- vapply(seq_along(index), function(column) {
    mfcl_bound_forward(
      internal_draws[, column], lower[[column]], upper[[column]], bound_scale[[column]]
    )
  }, numeric(draws))
  colnames(parameter_draws) <- names(estimate)

  fitted <- growth_schedule(estimate, n_age = 40L)
  report_mean <- suppressWarnings(as.numeric(c(aperm(FLR4MFCL::mean_laa(rep), c(4, 1, 2, 3, 5, 6)))))
  report_sd <- suppressWarnings(as.numeric(c(aperm(FLR4MFCL::sd_laa(rep), c(4, 1, 2, 3, 5, 6)))))
  if (length(report_mean) < 40L || length(report_sd) < 40L ||
      max(abs(fitted$mean_length - report_mean[seq_len(40L)])) > 1e-3 ||
      max(abs(fitted$sd_length - report_sd[seq_len(40L)])) > 1e-3) {
    stop("Reconstructed mean/SD length-at-age does not match the native MFCL report.", call. = FALSE)
  }

  rows <- lapply(seq_len(nrow(fitted)), function(age) {
    mean_fn <- function(x) growth_schedule(x, 40L)$mean_length[[age]]
    sd_fn <- function(x) growth_schedule(x, 40L)$sd_length[[age]]
    lower_fn <- function(x) mean_fn(x) - 1.96 * sd_fn(x)
    upper_fn <- function(x) mean_fn(x) + 1.96 * sd_fn(x)
    rho_draw <- exp(-parameter_draws[, 3L])
    relative_growth_draw <- (1 - rho_draw^(age - 1)) / (1 - rho_draw^39)
    mean_draw <- parameter_draws[, 1L] +
      (parameter_draws[, 2L] - parameter_draws[, 1L]) * relative_growth_draw
    sd_draw <- parameter_draws[, 4L] *
      exp(parameter_draws[, 5L] * (-1 + 2 * relative_growth_draw))
    lower_draw <- mean_draw - 1.96 * sd_draw
    upper_draw <- mean_draw + 1.96 * sd_draw
    mean_interval <- stats::quantile(mean_draw, c(0.025, 0.975), names = FALSE, type = 8)
    sd_interval <- stats::quantile(sd_draw, c(0.025, 0.975), names = FALSE, type = 8)
    lower_interval <- stats::quantile(lower_draw, c(0.025, 0.975), names = FALSE, type = 8)
    upper_interval <- stats::quantile(upper_draw, c(0.025, 0.975), names = FALSE, type = 8)
    distribution_lower <- lower_fn(estimate)
    distribution_upper <- upper_fn(estimate)
    data.frame(
      age = age,
      mean_length = mean_fn(estimate),
      mean_se = stats::sd(mean_draw),
      mean_lower = mean_interval[[1L]],
      mean_upper = mean_interval[[2L]],
      sd_length = sd_fn(estimate),
      sd_se = stats::sd(sd_draw),
      sd_lower = sd_interval[[1L]],
      sd_upper = sd_interval[[2L]],
      distribution_lower = distribution_lower,
      distribution_upper = distribution_upper,
      distribution_lower_se = stats::sd(lower_draw),
      distribution_upper_se = stats::sd(upper_draw),
      distribution_lower_ci = lower_interval[[1L]],
      distribution_lower_ci_upper = lower_interval[[2L]],
      distribution_upper_ci_lower = upper_interval[[1L]],
      distribution_upper_ci = upper_interval[[2L]],
      stringsAsFactors = FALSE
    )
  })
  curve <- do.call(rbind, rows)
  delta_curve <- do.call(rbind, lapply(seq_len(nrow(fitted)), function(age) {
    mean_fn <- function(x) growth_schedule(x, 40L)$mean_length[[age]]
    sd_fn <- function(x) growth_schedule(x, 40L)$sd_length[[age]]
    lower_fn <- function(x) mean_fn(x) - 1.96 * sd_fn(x)
    upper_fn <- function(x) mean_fn(x) + 1.96 * sd_fn(x)
    mean_se <- delta_se(numeric_gradient(mean_fn, estimate), covariance)
    sd_se <- delta_se(numeric_gradient(sd_fn, estimate), covariance)
    lower_se <- delta_se(numeric_gradient(lower_fn, estimate), covariance)
    upper_se <- delta_se(numeric_gradient(upper_fn, estimate), covariance)
    data.frame(
      age = age,
      mean_lower = mean_fn(estimate) - 1.96 * mean_se,
      mean_upper = mean_fn(estimate) + 1.96 * mean_se,
      sd_lower = pmax(0, sd_fn(estimate) - 1.96 * sd_se),
      sd_upper = sd_fn(estimate) + 1.96 * sd_se,
      distribution_lower_ci = lower_fn(estimate) - 1.96 * lower_se,
      distribution_lower_ci_upper = lower_fn(estimate) + 1.96 * lower_se,
      distribution_upper_ci_lower = upper_fn(estimate) - 1.96 * upper_se,
      distribution_upper_ci = upper_fn(estimate) + 1.96 * upper_se
    )
  }))
  interval_columns <- setdiff(names(delta_curve), "age")
  delta_comparison <- data.frame(
    endpoint = interval_columns,
    maximum_absolute_difference_cm = vapply(
      interval_columns,
      function(column) max(abs(curve[[column]] - delta_curve[[column]])),
      numeric(1)
    ),
    stringsAsFactors = FALSE
  )
  parameter_se <- apply(parameter_draws, 2, stats::sd)
  parameter_interval <- apply(parameter_draws, 2, stats::quantile, probs = c(0.025, 0.975), names = FALSE, type = 8)
  parameter_table <- data.frame(
    parameter = names(estimate),
    estimate = estimate,
    standard_error = parameter_se,
    lower_95 = parameter_interval[1L, ],
    upper_95 = parameter_interval[2L, ],
    lower_bound = lower,
    upper_bound = upper,
    stringsAsFactors = FALSE
  )
  list(
    curve = curve,
    parameters = parameter_table,
    covariance = covariance,
    covariance_internal = covariance_internal,
    internal_estimate = internal_estimate,
    hessian_index = index,
    bound_scale = bound_scale,
    interval_method = "Multivariate-normal Hessian approximation on the MFCL bounded internal scale, transformed through the native sine bounds",
    draws = draws,
    seed = seed,
    draws_at_penalized_bound = outside_bounds,
    transformed_vs_delta = delta_comparison,
    max_report_mean_difference = max(abs(fitted$mean_length - report_mean[seq_len(40L)])),
    max_report_sd_difference = max(abs(fitted$sd_length - report_sd[seq_len(40L)]))
  )
}

if (file.exists(hessian_file)) {
  native_hessian_file <- file.path(repo_root, "results", "reference", "hessian", "bet.hes")
  growth_uncertainty <- build_growth_uncertainty(
    model_dir = model_dir,
    hessian_path = native_hessian_file,
    hessian_metadata = h
  )
  write.csv(growth_uncertainty$curve, file.path(table_dir, "growth-curve-uncertainty.csv"), row.names = FALSE)
  write.csv(growth_uncertainty$parameters, file.path(table_dir, "growth-parameter-uncertainty.csv"), row.names = FALSE)
  write.csv(growth_uncertainty$transformed_vs_delta, file.path(table_dir, "growth-uncertainty-method-check.csv"), row.names = FALSE)
  saveRDS(growth_uncertainty$covariance, file.path(table_dir, "growth-parameter-covariance.rds"), compress = "xz")

  if (!requireNamespace("mfclshiny", quietly = TRUE)) {
    stop("mfclshiny is required for the regional growth plot.", call. = FALSE)
  }
  age_file <- list.files(model_dir, pattern = "\\.age_length$", full.names = TRUE)
  if (length(age_file) != 1L) stop("Expected one age-length input file.", call. = FALSE)
  age_fit <- mfclshiny::summarise_mfcl_age_length_fit(
    age_file[[1L]],
    file.path(model_dir, "agelengthresids.dat")
  )
  map_environment <- new.env(parent = baseenv())
  sys.source(file.path(model_dir, "fishery_map.R"), envir = map_environment)
  growth_plot <- mfclshiny::plot_mfcl_age_length_growth(
    age_fit,
    growth_uncertainty$curve,
    fishery_map = map_environment$fishery_map,
    facet_ncol = 3L
  ) + ggplot2::labs(
    subtitle = paste(
      "Observed age-length cells by region; all five growth/SD parameters and their covariance are propagated from the native MFCL Hessian"
    )
  )
  uncertainty_width <- rbind(
    data.frame(age = growth_uncertainty$curve$age, quantity = "Mean length", half_width = (growth_uncertainty$curve$mean_upper - growth_uncertainty$curve$mean_lower) / 2),
    data.frame(age = growth_uncertainty$curve$age, quantity = "Length SD", half_width = (growth_uncertainty$curve$sd_upper - growth_uncertainty$curve$sd_lower) / 2),
    data.frame(age = growth_uncertainty$curve$age, quantity = "Lower distribution limit", half_width = (growth_uncertainty$curve$distribution_lower_ci_upper - growth_uncertainty$curve$distribution_lower_ci) / 2),
    data.frame(age = growth_uncertainty$curve$age, quantity = "Upper distribution limit", half_width = (growth_uncertainty$curve$distribution_upper_ci - growth_uncertainty$curve$distribution_upper_ci_lower) / 2)
  )
  uncertainty_width$quantity <- factor(
    uncertainty_width$quantity,
    levels = c("Mean length", "Length SD", "Lower distribution limit", "Upper distribution limit")
  )
  width_plot <- ggplot(uncertainty_width, aes(age, half_width, colour = quantity)) +
    geom_line(linewidth = 0.72) +
    facet_wrap(~quantity, nrow = 1, scales = "free_y") +
    scale_colour_manual(values = c("#0077B6", "#3A7D44", "#B65C00", "#8A4F00")) +
    labs(
      x = "Age class", y = "95% CI half-width (cm)",
      title = "Hessian uncertainty at the plotted curves and distribution limits"
    ) +
    theme_bet() +
    theme(legend.position = "none", strip.text = element_text(face = "bold", size = 9))
  combined_growth_plot <- patchwork::wrap_plots(
    growth_plot, width_plot, ncol = 1, heights = c(4.3, 1.25)
  )
  ggsave(file.path(figure_dir, "regional-age-length-growth-uncertainty.png"), combined_growth_plot, width = 12, height = 10.2, dpi = 220, bg = "white")
  ggsave(file.path(figure_dir, "regional-age-length-growth-uncertainty.pdf"), combined_growth_plot, width = 12, height = 10.2, device = cairo_pdf, bg = "white")

  uncertainty_path <- file.path(output_dir, "diagnostic-uncertainty.rds")
  uncertainty_payload <- readRDS(uncertainty_path)
  uncertainty_payload$growth <- growth_uncertainty
  saveRDS(uncertainty_payload, uncertainty_path, compress = "xz")
}

message("Wrote native MFCL uncertainty outputs to ", normalizePath(output_dir, mustWork = TRUE))
