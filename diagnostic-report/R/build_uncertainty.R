#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
repo_root <- if (length(args) >= 1L) normalizePath(args[[1L]], mustWork = TRUE) else normalizePath(".", mustWork = TRUE)
output_dir <- if (length(args) >= 2L) args[[2L]] else file.path(repo_root, "diagnostic-report-output")
variance_file <- if (length(args) >= 3L) args[[3L]] else file.path(repo_root, "results", "reference", "uncertainty", "bet.var")

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

message("Wrote native MFCL uncertainty outputs to ", normalizePath(output_dir, mustWork = TRUE))
