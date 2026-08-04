#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

model_dir <- Sys.getenv("DIAGNOSTIC_MODEL_DIR", "")
output_dir <- Sys.getenv("DIAGNOSTIC_REPORT_OUTPUT_DIR", "")
reference_dir <- Sys.getenv("DIAGNOSTIC_REPORT_REFERENCE_DIR", "")
if (!nzchar(model_dir) || !dir.exists(model_dir)) {
  stop("DIAGNOSTIC_MODEL_DIR must identify the restored Diagnostic model.", call. = FALSE)
}
if (!nzchar(output_dir)) {
  stop("DIAGNOSTIC_REPORT_OUTPUT_DIR is required.", call. = FALSE)
}
if (!nzchar(reference_dir) || !dir.exists(reference_dir)) {
  stop("DIAGNOSTIC_REPORT_REFERENCE_DIR is required.", call. = FALSE)
}

model_dir <- normalizePath(model_dir, winslash = "/", mustWork = TRUE)
reference_dir <- normalizePath(reference_dir, winslash = "/", mustWork = TRUE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
table_dir <- file.path(output_dir, "tables")
figure_dir <- file.path(output_dir, "figures")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

expected_final_sha <- "21dcaea9db8c89ddc8c29fa3c3a5e514b50bef6e26587c168c00c05f35fbebc3"
expected_hessian_sha <- "e289a150c45930c2f4f164fb43432d5c034d8caec7bda7ce664caca9e4ad20c5"

sha256 <- function(path) {
  if (!file.exists(path)) stop("Missing required file: ", path, call. = FALSE)
  output <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  if (!length(output)) stop("Could not calculate SHA-256 for ", path, call. = FALSE)
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

final_file <- file.path(model_dir, "final.par")
hessian_file_raw <- file.path(model_dir, "hessian", "bet.hes")
observed_final_sha <- sha256(final_file)
observed_hessian_sha <- sha256(hessian_file_raw)
if (!identical(observed_final_sha, expected_final_sha)) {
  stop("Unexpected final.par SHA-256: ", observed_final_sha, call. = FALSE)
}
if (!identical(observed_hessian_sha, expected_hessian_sha)) {
  stop("Unexpected bet.hes SHA-256: ", observed_hessian_sha, call. = FALSE)
}

hessian_file <- file.path(model_dir, "hessian", "hessian_info.rds")
if (!file.exists(hessian_file)) {
  stop("Hessian metadata is required: ", hessian_file, call. = FALSE)
}
h <- readRDS(hessian_file)
if (!is.list(h) || !is.list(h$eigen) || !is.list(h$diagnostics)) {
  stop("Invalid hessian_info.rds structure.", call. = FALSE)
}

first_value <- function(...) {
  values <- list(...)
  for (value in values) {
    if (length(value) && !is.null(value[[1L]]) && !is.na(value[[1L]])) return(value[[1L]])
  }
  NA
}

hessian_summary <- data.frame(
  diagnostic = c(
    "Parameters", "Completed partitions", "Positive eigenvalues",
    "Non-positive eigenvalues", "Smallest eigenvalue", "Largest eigenvalue",
    "Positive condition number", "Status", "Reliability"
  ),
  value = as.character(c(
    first_value(h$meta$npars, h$eigen$n_total_eigenvalues),
    first_value(h$meta$n_parts),
    first_value(h$eigen$n_positive_eigenvalues),
    first_value(h$eigen$n_nonpositive_eigenvalues),
    format(first_value(h$eigen$minimum_eigenvalue), digits = 7L, scientific = TRUE),
    format(first_value(h$eigen$maximum_eigenvalue), digits = 7L, scientific = TRUE),
    format(first_value(h$eigen$positive_condition_number), digits = 7L, scientific = TRUE),
    first_value(h$eigen$hessian_status),
    first_value(h$eigen$reliability)
  )),
  stringsAsFactors = FALSE
)
utils::write.csv(hessian_summary, file.path(table_dir, "hessian-summary.csv"), row.names = FALSE)

parameter_table <- h$diagnostics$parameter_table
if (!is.data.frame(parameter_table) || !all(c("idx", "par", "se_pos") %in% names(parameter_table))) {
  stop("Hessian parameter labels and positive-curvature SEs are missing.", call. = FALSE)
}

indepvar_file <- file.path(model_dir, "indepvar.rpt")
if (!file.exists(indepvar_file)) {
  stop("The Hessian-enriched payload did not restore indepvar.rpt.", call. = FALSE)
}
lines <- readLines(indepvar_file, warn = FALSE)
pattern <- paste0(
  "^\\s*([0-9]+)\\s+(\\S+)\\s+",
  "([-+0-9.eE]+)\\s+([-+0-9.eE]+)\\s+([-+0-9.eE]+)\\s+([-+0-9.eE]+)"
)
matches <- regmatches(lines, regexec(pattern, lines))
matches <- matches[lengths(matches) == 7L]
indep <- data.frame(
  idx = as.integer(vapply(matches, `[[`, character(1L), 2L)),
  parameter = vapply(matches, `[[`, character(1L), 3L),
  estimate = as.numeric(vapply(matches, `[[`, character(1L), 4L)),
  lower_bound = as.numeric(vapply(matches, `[[`, character(1L), 5L)),
  upper_bound = as.numeric(vapply(matches, `[[`, character(1L), 6L)),
  gradient = as.numeric(vapply(matches, `[[`, character(1L), 7L)),
  stringsAsFactors = FALSE
)
if (nrow(indep) != nrow(parameter_table) || !identical(indep$idx, as.integer(parameter_table$idx))) {
  stop("indepvar.rpt does not match the 1,997-parameter Hessian map.", call. = FALSE)
}

uncertainty <- cbind(
  indep,
  hessian_parameter = as.character(parameter_table$par),
  hessian_se_internal = as.numeric(parameter_table$se_pos)
)
uncertainty$parameter_family <- sub("[(].*$", "", uncertainty$hessian_parameter)
uncertainty$absolute_gradient <- abs(uncertainty$gradient)
uncertainty$distance_to_nearest_bound <- pmin(
  uncertainty$estimate - uncertainty$lower_bound,
  uncertainty$upper_bound - uncertainty$estimate
)
utils::write.csv(
  uncertainty,
  file.path(table_dir, "hessian-parameter-uncertainty.csv"),
  row.names = FALSE
)

family <- split(uncertainty, uncertainty$parameter_family)
family_summary <- do.call(rbind, lapply(names(family), function(name) {
  x <- family[[name]]
  data.frame(
    parameter_family = name,
    parameters = nrow(x),
    median_hessian_se_internal = stats::median(x$hessian_se_internal, na.rm = TRUE),
    p95_hessian_se_internal = as.numeric(stats::quantile(x$hessian_se_internal, 0.95, na.rm = TRUE)),
    maximum_hessian_se_internal = max(x$hessian_se_internal, na.rm = TRUE),
    maximum_absolute_gradient = max(x$absolute_gradient, na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))
family_summary <- family_summary[order(family_summary$p95_hessian_se_internal, decreasing = TRUE), ]
rownames(family_summary) <- NULL
utils::write.csv(
  family_summary,
  file.path(table_dir, "hessian-uncertainty-by-parameter-family.csv"),
  row.names = FALSE
)

annual_file <- file.path(reference_dir, "annual-hessian-time-series.csv")
if (!file.exists(annual_file)) {
  stop("Missing verified annual Hessian uncertainty table: ", annual_file, call. = FALSE)
}
annual <- utils::read.csv(annual_file, stringsAsFactors = FALSE)
annual_required <- c(
  "year", "quantity", "estimate", "se_log",
  "lower_50", "upper_50", "lower_80", "upper_80", "lower_95", "upper_95",
  "final_par_sha256", "hessian_sha256", "method"
)
if (!all(annual_required %in% names(annual))) {
  stop("The annual Hessian uncertainty table is incomplete.", call. = FALSE)
}
quantities <- c("depletion", "spawning_potential", "recruitment")
if (!identical(sort(unique(annual$quantity)), sort(quantities)) ||
    any(table(annual$quantity) != 73L) ||
    !identical(sort(unique(as.integer(annual$year))), 1952:2024) ||
    any(!is.finite(annual$estimate)) || any(annual$estimate < 0) ||
    any(!is.finite(annual$lower_95)) || any(annual$lower_95 < 0) ||
    any(!is.finite(annual$upper_95)) || any(annual$upper_95 < annual$lower_95) ||
    any(annual$lower_95 > annual$lower_80) || any(annual$lower_80 > annual$lower_50) ||
    any(annual$lower_50 > annual$estimate) || any(annual$estimate > annual$upper_50) ||
    any(annual$upper_50 > annual$upper_80) || any(annual$upper_80 > annual$upper_95) ||
    !all(annual$final_par_sha256 == expected_final_sha) ||
    !all(annual$hessian_sha256 == expected_hessian_sha)) {
  stop("The annual Hessian uncertainty table failed its source or range checks.", call. = FALSE)
}
annual <- annual[order(match(annual$quantity, quantities), annual$year), , drop = FALSE]
utils::write.csv(
  annual,
  file.path(table_dir, "annual-hessian-time-series.csv"),
  row.names = FALSE
)
saveRDS(
  list(
    time_series = annual,
    source = list(
      model = "Diagnostic model",
      final_par_sha256 = expected_final_sha,
      hessian_sha256 = expected_hessian_sha,
      hessian_parameters = 1997L,
      interval = "nested pointwise 50%, 80% and 95% Hessian delta method"
    )
  ),
  file.path(output_dir, "diagnostic-annual-uncertainty.rds"),
  compress = "xz"
)

status <- data.frame(
  item = c(
    "Source model", "Source Kflow model job", "Source Hessian calculation",
    "Raw Hessian restoration", "Hessian result", "Parameter uncertainty",
    "Derived-quantity uncertainty"
  ),
  value = c(
    "Diagnostic model", "21641", "22020", "22196",
    "60/60 partitions; PDH; HIGH reliability",
    "Available for all 1,997 active parameters on the native MFCL optimization scale",
    "Annual depletion, spawning potential and recruitment with full within-year covariance"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(status, file.path(table_dir, "uncertainty-status.csv"), row.names = FALSE)

if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Package ggplot2 is required.", call. = FALSE)
if (!requireNamespace("patchwork", quietly = TRUE)) stop("Package patchwork is required.", call. = FALSE)
dpi <- suppressWarnings(as.integer(Sys.getenv("DIAGNOSTIC_REPORT_DPI", "400")))
if (!is.finite(dpi) || dpi < 300L) dpi <- 400L

theme_paper <- function() {
  ggplot2::theme_minimal(base_size = 11.5) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "#dbe3e8", linewidth = 0.35),
      axis.line = ggplot2::element_line(colour = "#334155", linewidth = 0.35),
      axis.title = ggplot2::element_text(face = "bold", colour = "#172033"),
      axis.text = ggplot2::element_text(colour = "#334155"),
      plot.margin = ggplot2::margin(8, 10, 8, 8)
    )
}

annual_panel <- function(quantity, y_label, colour, show_x = TRUE) {
  data <- annual[annual$quantity == quantity, , drop = FALSE]
  p <- ggplot2::ggplot(data, ggplot2::aes(year, estimate)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = lower_95, ymax = upper_95),
      fill = colour, alpha = 0.16, colour = NA
    ) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = lower_80, ymax = upper_80),
      fill = colour, alpha = 0.22, colour = NA
    ) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = lower_50, ymax = upper_50),
      fill = colour, alpha = 0.30, colour = NA
    ) +
    ggplot2::geom_line(colour = colour, linewidth = 0.72, lineend = "round") +
    ggplot2::scale_x_continuous(
      breaks = seq(1960, 2020, by = 20),
      expand = ggplot2::expansion(mult = c(0.015, 0.015))
    ) +
    ggplot2::scale_y_continuous(
      limits = c(0, NA),
      expand = ggplot2::expansion(mult = c(0, 0.055))
    ) +
    ggplot2::labs(x = if (isTRUE(show_x)) "Year" else NULL, y = y_label) +
    theme_paper()
  if (!isTRUE(show_x)) {
    p <- p + ggplot2::theme(axis.text.x = ggplot2::element_blank(), axis.ticks.x = ggplot2::element_blank())
  }
  p
}

p_depletion <- annual_panel(
  "depletion", expression(italic(SB)(t) / italic(SB)(F == 0, t)), "#c75415", FALSE
) +
  ggplot2::geom_hline(
    yintercept = c(0.2, 0.5), linetype = "dashed",
    colour = c("#b42318", "#2f855a"), linewidth = 0.45
  )
p_spawning <- annual_panel(
  "spawning_potential", expression("Spawning potential (" * 10^3 * " MT)"), "#087f8c", FALSE
)
p_recruitment <- annual_panel("recruitment", "Recruitment (millions)", "#6f42a1", TRUE)
combined <- (p_depletion | p_spawning) / p_recruitment +
  patchwork::plot_layout(heights = c(1, 1.05))

ggplot2::ggsave(
  file.path(figure_dir, "hessian-annual-time-series.png"), combined,
  width = 13, height = 8.8, dpi = dpi, bg = "white"
)
ggplot2::ggsave(
  file.path(figure_dir, "hessian-annual-time-series.pdf"), combined,
  width = 13, height = 8.8, device = grDevices::cairo_pdf, bg = "white"
)

plot_data <- uncertainty[
  is.finite(uncertainty$hessian_se_internal) & uncertainty$hessian_se_internal > 0,
  , drop = FALSE
]
keep_families <- names(sort(table(plot_data$parameter_family), decreasing = TRUE))[1:min(18L, length(unique(plot_data$parameter_family)))]
plot_data <- plot_data[plot_data$parameter_family %in% keep_families, , drop = FALSE]
ordering <- family_summary$parameter_family[family_summary$parameter_family %in% keep_families]
plot_data$parameter_family <- factor(plot_data$parameter_family, levels = rev(ordering))
p_parameter <- ggplot2::ggplot(plot_data, ggplot2::aes(hessian_se_internal, parameter_family)) +
  ggplot2::geom_boxplot(
    fill = "#8ecae6", colour = "#164e63", width = 0.62,
    outlier.alpha = 0.18, outlier.size = 0.7
  ) +
  ggplot2::scale_x_log10() +
  ggplot2::labs(x = "Native Hessian marginal SE (log scale)", y = NULL) +
  theme_paper() +
  ggplot2::theme(axis.text.y = ggplot2::element_text(size = 8.5))
ggplot2::ggsave(
  file.path(figure_dir, "hessian-parameter-uncertainty.png"), p_parameter,
  width = 10.5, height = 7.2, dpi = dpi, bg = "white"
)
ggplot2::ggsave(
  file.path(figure_dir, "hessian-parameter-uncertainty.pdf"), p_parameter,
  width = 10.5, height = 7.2, device = grDevices::cairo_pdf, bg = "white"
)

fragment <- c(
  '<section class="section-card" id="hessian-uncertainty">',
  '<h2>Hessian uncertainty</h2>',
  '<figure><img src="figures/hessian-annual-time-series.png" alt="Annual Hessian uncertainty for the Diagnostic model"><figcaption><strong>Figure.</strong> Annual estimates (lines) and pointwise 50%, 80% and 95% Hessian delta-method intervals (shaded from darkest to lightest) for the Diagnostic model. Recruitment is summed over quarters, spawning potential is averaged over quarters, and depletion is the annual mean of the quarterly spawning-potential ratios. Annual uncertainty retains the full within-year covariance among quarterly estimates. Dashed lines in the depletion panel mark 0.2 and 0.5.</figcaption></figure>',
  '<p><a href="figures/hessian-annual-time-series.pdf" download>Annual uncertainty figure (PDF)</a> · <a href="tables/annual-hessian-time-series.csv" download>Annual estimates and intervals (CSV)</a> · <a href="diagnostic-annual-uncertainty.rds" download>Annual uncertainty data (RDS)</a></p>',
  '<h3>Hessian quality control</h3>',
  '<p>All 60 partitions were completed and the 1,997-parameter Hessian is positive definite. The condition number indicates substantial scaling differences among parameter blocks, so the intervals are local and model-conditional.</p>',
  '<figure><img src="figures/hessian-parameter-uncertainty.png" alt="Hessian parameter uncertainty by model component"><figcaption><strong>Figure.</strong> Native marginal Hessian standard errors by parameter family. The logarithmic axis retains the full range of parameter scales.</figcaption></figure>',
  '<p><a href="tables/hessian-summary.csv" download>Hessian summary (CSV)</a> · <a href="tables/hessian-parameter-uncertainty.csv" download>All parameter SEs (CSV)</a> · <a href="tables/hessian-uncertainty-by-parameter-family.csv" download>Component summary (CSV)</a> · <a href="figures/hessian-parameter-uncertainty.pdf" download>Parameter figure (PDF)</a></p>',
  '</section>'
)
writeLines(fragment, file.path(output_dir, "hessian-report-fragment.html"), useBytes = TRUE)

message("Wrote verified annual Hessian uncertainty summaries to ", output_dir)
