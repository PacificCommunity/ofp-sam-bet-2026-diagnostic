#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

model_dir <- Sys.getenv("DIAGNOSTIC_MODEL_DIR", "")
output_dir <- Sys.getenv("DIAGNOSTIC_REPORT_OUTPUT_DIR", "")
if (!nzchar(model_dir) || !dir.exists(model_dir)) {
  stop("DIAGNOSTIC_MODEL_DIR must identify the restored Job 21641 model.", call. = FALSE)
}
if (!nzchar(output_dir)) {
  stop("DIAGNOSTIC_REPORT_OUTPUT_DIR is required.", call. = FALSE)
}

model_dir <- normalizePath(model_dir, winslash = "/", mustWork = TRUE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
table_dir <- file.path(output_dir, "tables")
figure_dir <- file.path(output_dir, "figures")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

hessian_file <- file.path(model_dir, "hessian", "hessian_info.rds")
if (!file.exists(hessian_file)) {
  stop("Job 21641 Hessian metadata is required: ", hessian_file, call. = FALSE)
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

status <- data.frame(
  item = c(
    "Source model", "Source Kflow model job", "Source Hessian job",
    "Hessian result", "Parameter uncertainty", "Derived-quantity uncertainty"
  ),
  value = c(
    "Diagnostic", "21641", "22020", "60/60 partitions; PDH; HIGH reliability",
    "Available for all 1,997 active parameters on the native MFCL optimization scale",
    "Not reported: the compact attachment contains no matching native bet.var"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(status, file.path(table_dir, "uncertainty-status.csv"), row.names = FALSE)

if (requireNamespace("ggplot2", quietly = TRUE)) {
  dpi <- suppressWarnings(as.integer(Sys.getenv("DIAGNOSTIC_REPORT_DPI", "400")))
  if (!is.finite(dpi) || dpi < 300L) dpi <- 400L
  plot_data <- uncertainty[
    is.finite(uncertainty$hessian_se_internal) & uncertainty$hessian_se_internal > 0,
    , drop = FALSE
  ]
  keep_families <- names(sort(table(plot_data$parameter_family), decreasing = TRUE))[1:min(18L, length(unique(plot_data$parameter_family)))]
  plot_data <- plot_data[plot_data$parameter_family %in% keep_families, , drop = FALSE]
  ordering <- family_summary$parameter_family[family_summary$parameter_family %in% keep_families]
  plot_data$parameter_family <- factor(plot_data$parameter_family, levels = rev(ordering))
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(hessian_se_internal, parameter_family)) +
    ggplot2::geom_boxplot(
      fill = "#8ecae6", colour = "#164e63", width = 0.62,
      outlier.alpha = 0.18, outlier.size = 0.7
    ) +
    ggplot2::scale_x_log10() +
    ggplot2::labs(
      x = "Native Hessian marginal SE (log scale)", y = NULL,
      title = "Local parameter uncertainty by model component",
      subtitle = "Job 21641; positive-curvature covariance from the 60-partition Hessian"
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold", colour = "#153f5f"),
      axis.text.y = ggplot2::element_text(size = 8.5)
    )
  ggplot2::ggsave(
    file.path(figure_dir, "hessian-parameter-uncertainty.png"), p,
    width = 10.5, height = 7.2, dpi = dpi, bg = "white"
  )
  ggplot2::ggsave(
    file.path(figure_dir, "hessian-parameter-uncertainty.pdf"), p,
    width = 10.5, height = 7.2, device = grDevices::cairo_pdf, bg = "white"
  )
}

fragment <- c(
  '<section class="section-card" id="hessian-uncertainty">',
  '<h2>Hessian uncertainty and quality control</h2>',
  '<p>The Job 22020 calculation completed all 60 partitions and produced a positive-definite 1,997-parameter Hessian. The smallest eigenvalue is 2.55194e-07 and the positive condition number is approximately 4.23e9. This supports local, model-conditional inference while also indicating substantial scaling differences among parameter blocks.</p>',
  '<figure><img src="figures/hessian-parameter-uncertainty.png" alt="Hessian parameter uncertainty by model component"><figcaption><strong>Figure.</strong> Native marginal Hessian standard errors by parameter family. The logarithmic scale preserves the full range without hiding tightly estimated components.</figcaption></figure>',
  '<p><a href="tables/hessian-summary.csv" download>Hessian summary (CSV)</a> · <a href="tables/hessian-parameter-uncertainty.csv" download>All parameter SEs (CSV)</a> · <a href="tables/hessian-uncertainty-by-parameter-family.csv" download>Component summary (CSV)</a> · <a href="figures/hessian-parameter-uncertainty.pdf" download>Figure (PDF)</a></p>',
  '<p class="note"><strong>Scope.</strong> Parameter SEs are reported on the native MFCL optimization scale. The compact attachment does not contain a matching <code>bet.var</code>, so this report does not fabricate confidence ribbons for derived biomass, depletion or recruitment series.</p>',
  '</section>'
)
writeLines(fragment, file.path(output_dir, "hessian-report-fragment.html"), useBytes = TRUE)

message("Wrote Job 21641 Hessian uncertainty summaries to ", output_dir)
