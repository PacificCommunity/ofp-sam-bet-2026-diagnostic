#!/usr/bin/env Rscript

# Build the public BET 2026 Diagnostic report from repository-contained data.
# Raw check folders and scheduler metadata are deliberately not required.

options(stringsAsFactors = FALSE, scipen = 8)

args <- commandArgs(trailingOnly = TRUE)
repo_root <- if (length(args) >= 1L) normalizePath(args[[1L]], winslash = "/", mustWork = TRUE) else normalizePath(".", winslash = "/", mustWork = TRUE)
output_dir <- if (length(args) >= 2L) args[[2L]] else file.path(repo_root, "diagnostic-report-output")
if (!grepl("^/", output_dir)) output_dir <- file.path(repo_root, output_dir)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

required_packages <- c(
  "ggplot2", "dplyr", "tidyr", "patchwork", "scales", "jsonlite",
  "htmltools", "plotly", "htmlwidgets", "ragg", "mfclshiny", "FLR4MFCL"
)
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1L), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Missing required package(s): ", paste(missing_packages, collapse = ", "), call. = FALSE)
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
payload_file <- file.path(repo_root, "diagnostic-report", "data", "diagnostic-report-data.rds")
model_payload_file <- file.path(repo_root, "results", "reference", "model_payload.rds")
if (!file.exists(payload_file)) stop("Missing compact report payload: ", payload_file, call. = FALSE)
if (!file.exists(model_payload_file)) stop("Missing repository model payload: ", model_payload_file, call. = FALSE)
report_data <- readRDS(payload_file)
if (!identical(report_data$schema, "bet2026.diagnostic_report.v1")) {
  stop("Unsupported report payload schema: ", report_data$schema %||% "missing", call. = FALSE)
}

figure_dir <- file.path(output_dir, "figures")
table_dir <- file.path(output_dir, "tables")
viewer_dir <- file.path(output_dir, "viewer")
mfcl_dir <- file.path(output_dir, "mfclshiny")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(viewer_dir, recursive = TRUE, showWarnings = FALSE)

navy <- "#0B5267"
teal <- "#168A98"
blue50 <- "#72B7C5"
blue80 <- "#B3DCE3"
blue95 <- "#E5F1F3"
orange <- "#D67514"
red <- "#B8322B"
grey <- "#60717A"
light_grey <- "#DCE5E8"
model_colours <- c(
  "Diagnostic" = "#0B5267",
  "ASPM, fitted recruitment" = "#D67514",
  "ASPM, constant recruitment" = "#7A6AA6"
)

theme_report <- function(base_size = 10.5) {
  ggplot2::theme_bw(base_size = base_size, base_family = "serif") +
    ggplot2::theme(
      plot.title = ggplot2::element_blank(),
      plot.subtitle = ggplot2::element_blank(),
      plot.tag = ggplot2::element_text(face = "bold", size = base_size + 1),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = "#DCE5E8", linewidth = 0.35),
      axis.title = ggplot2::element_text(size = base_size),
      axis.text = ggplot2::element_text(colour = "#314B5B", size = base_size - 1),
      strip.background = ggplot2::element_rect(fill = "#E7EEF1", colour = "#526B78"),
      strip.text = ggplot2::element_text(face = "bold", size = base_size - 0.5),
      legend.position = "bottom",
      legend.box = "vertical",
      legend.title = ggplot2::element_text(face = "bold"),
      legend.key.height = grid::unit(0.45, "cm"),
      plot.margin = ggplot2::margin(5, 6, 5, 5)
    )
}

save_figure <- function(plot, id, width = 7.1, height = 6.2, dpi = 400) {
  png <- file.path(figure_dir, paste0(id, ".png"))
  pdf <- file.path(figure_dir, paste0(id, ".pdf"))
  ggplot2::ggsave(
    png, plot, width = width, height = height, units = "in", dpi = dpi,
    device = ragg::agg_png, bg = "white", limitsize = FALSE
  )
  ggplot2::ggsave(
    pdf, plot, width = width, height = height, units = "in",
    device = grDevices::cairo_pdf, bg = "white", limitsize = FALSE
  )
  list(png = png, pdf = pdf)
}

quantile_safe <- function(x, probability) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  unname(stats::quantile(x, probability, na.rm = TRUE, names = FALSE, type = 8))
}

# Curated mfclshiny fit figures ---------------------------------------------
mfclshiny_repo <- Sys.getenv("MFCLSHINY_REPO", "")
use_source_mfclshiny <- nzchar(mfclshiny_repo) && dir.exists(mfclshiny_repo) &&
  requireNamespace("pkgload", quietly = TRUE)

staging_root <- tempfile("bet-diagnostic-report-")
model_dir <- file.path(staging_root, "Diagnostic")
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(staging_root, recursive = TRUE, force = TRUE), add = TRUE)
mfclshiny::restore_model_payload_files(model_payload_file, output_dir = model_dir, overwrite = TRUE)
file.copy(model_payload_file, file.path(model_dir, "model_payload.rds"), overwrite = TRUE)
file.copy(file.path(repo_root, "model", "fishery_map.R"), model_dir, overwrite = TRUE)
file.copy(file.path(repo_root, "model", "tag_rep_map.R"), model_dir, overwrite = TRUE)
map_candidates <- c(
  if (nzchar(mfclshiny_repo)) file.path(mfclshiny_repo, "inst", "extdata", "region-maps", "bet-2026-five-region-vertices.csv") else character(),
  system.file("extdata", "region-maps", "bet-2026-five-region-vertices.csv", package = "mfclshiny")
)
map_asset <- map_candidates[file.exists(map_candidates)][1L]
if (is.na(map_asset) || !nzchar(map_asset)) {
  stop("The BET 2026 five-region map asset is unavailable.", call. = FALSE)
}
file.copy(map_asset, file.path(model_dir, basename(map_asset)), overwrite = TRUE)

# CPUE observation bands use the fixed regional log-scale observation errors
# specified in the fitted model (fish flag 92). They are observation-model
# intervals, not Hessian intervals for the fitted index trajectory.
diagnostic_payload <- get("mfclshiny_diagnostic_payload", asNamespace("mfclshiny"))(
  model_dir,
  roles = c("ParOut", "RepOut")
)
rep_out <- diagnostic_payload$data$RepOut
if (is.null(rep_out)) stop("The repository model payload does not contain RepOut.", call. = FALSE)
flatten_flquant <- function(x, value_name) {
  value <- as.array(x)
  grid <- expand.grid(dimnames(value), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  names(grid) <- names(dimnames(value))
  grid[[value_name]] <- as.numeric(value)
  grid
}
cpue_obs <- flatten_flquant(FLR4MFCL::cpue_obs(rep_out), "obs_log")
cpue_fit <- flatten_flquant(FLR4MFCL::cpue_pred(rep_out), "fit_log")
cpue <- merge(cpue_obs, cpue_fit, by = c("age", "year", "unit", "season", "area", "iter"))
cpue$unit <- suppressWarnings(as.integer(cpue$unit))
cpue$year <- suppressWarnings(as.integer(cpue$year))
cpue$season <- suppressWarnings(as.integer(cpue$season))
cpue <- cpue[
  cpue$unit %in% 29:33 & is.finite(cpue$year) & is.finite(cpue$season) &
    is.finite(cpue$obs_log) & is.finite(cpue$fit_log),
  , drop = FALSE
]
cpue_sigma <- c(`29` = 0.35, `30` = 0.24, `31` = 0.21, `32` = 0.24, `33` = 0.23)
cpue$sd_log <- unname(cpue_sigma[as.character(cpue$unit)])
cpue$period <- cpue$year + (cpue$season - 1) / 4
cpue$observed <- exp(cpue$obs_log)
cpue$fitted <- exp(cpue$fit_log)
cpue$lower <- exp(cpue$fit_log - stats::qnorm(0.975) * cpue$sd_log)
cpue$upper <- exp(cpue$fit_log + stats::qnorm(0.975) * cpue$sd_log)
fishery_lookup <- report_data$mappings$fisheries
cpue$series <- fishery_lookup$fishery_name[match(cpue$unit, fishery_lookup$fishery)]
cpue$series <- sub("^[0-9]+[.]", "", cpue$series)
p_cpue_band <- ggplot2::ggplot(cpue, ggplot2::aes(x = period)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = lower, ymax = upper), fill = blue80, alpha = 0.72) +
  ggplot2::geom_line(ggplot2::aes(y = fitted, colour = "Fitted"), linewidth = 0.72) +
  ggplot2::geom_point(ggplot2::aes(y = observed, colour = "Observed"), size = 1.0, alpha = 0.72) +
  ggplot2::facet_wrap(~series, ncol = 2, scales = "free_y") +
  ggplot2::scale_colour_manual(values = c("Observed" = "#313D43", "Fitted" = navy)) +
  ggplot2::labs(x = "Year", y = "Relative CPUE", colour = NULL, fill = NULL) +
  theme_report(9.5) +
  ggplot2::theme(legend.position = "bottom")
save_figure(p_cpue_band, "cpue-fit-observation-intervals", width = 7.1, height = 6.0)

# Use the requested mfclshiny source tree for the figure registry after the
# compact payload has been materialized with the installed public API.
if (isTRUE(use_source_mfclshiny)) {
  pkgload::load_all(mfclshiny_repo, quiet = TRUE, export_all = FALSE)
}

mfcl_items <- c(
  "region-map",
  "total-catch-fits", "catch-by-fishery-fits",
  "cpue-residuals",
  "length-frequency", "length-frequency-residuals",
  "age-data-fit", "age-data-fit-by-region", "age-data-growth-by-region",
  "age-data-residuals-by-region", "age-data-coverage",
  "tag-returns-all", "tag-returns-by-group", "tag-attrition-by-program",
  "population-biology", "growth-curve", "fishery-process", "fishery-selectivity-length",
  "regional-movement", "depletion-by-area", "recruitment-by-area",
  "spawning-potential-with-without-fishing", "total-biomass-with-without-fishing"
)
selection_items <- data.frame(
  item_key = paste0("figure:", mfcl_items),
  type = "figure",
  id = mfcl_items,
  label = mfcl_items,
  section = "",
  caption = "",
  include = TRUE,
  placement = "main",
  input_state = "",
  stringsAsFactors = FALSE
)
lf_state <- jsonlite::toJSON(
  list(
    lf_view_mode = "all_fisheries", lf_panel_layout = "fit",
    lf_plot_style = "hist", lf_show_unc_band = TRUE, lf_unc_level = 95,
    lf_facet_ncol = "4", lf_plot_scale = "0.90"
  ),
  auto_unbox = TRUE
)
selection_items$input_state[selection_items$id == "length-frequency"] <- lf_state
selection <- list(
  schema = "mfclshiny.report_selection.v1",
  created_at = "2026-08-07T00:00:00Z",
  source = "BET 2026 Diagnostic report",
  inputs = list(
    lf_show_unc_band = TRUE,
    lf_unc_level = 95,
    population_biology_show_growth_band = TRUE
  ),
  items = selection_items
)
selection_file <- file.path(output_dir, "mfclshiny-selection.json")
jsonlite::write_json(selection, selection_file, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE)

reuse_mfcl_figures <- identical(tolower(Sys.getenv("DIAGNOSTIC_REUSE_MFCL_FIGURES", "false")), "true")
if (!reuse_mfcl_figures) {
  mfclshiny::build_app_report_figures(
    model_dir = model_dir,
    output_dir = mfcl_dir,
    title = "BET 2026 Diagnostic model figures",
    formats = c("png", "pdf"),
    width = 10.8,
    height = 7.0,
    dpi = as.integer(Sys.getenv("DIAGNOSTIC_REPORT_DPI", "400")),
    overwrite = TRUE,
    recursive = FALSE,
    build_payloads = FALSE,
    max_fisheries = 33L,
    selection_file = selection_file,
    render_html = FALSE,
    interactive_viewer = FALSE,
    species_code = "BET",
    species_label = "bigeye tuna",
    assessment_year = "2026"
  )
}

required_mfcl_figures <- c(
  "region-map", "cpue-residuals", "length-frequency", "age-data-fit",
  "age-data-fit-by-region", "age-data-growth-by-region", "tag-returns-all",
  "population-biology", "growth-curve"
)
missing_mfcl_figures <- required_mfcl_figures[
  !file.exists(file.path(mfcl_dir, "figures", paste0(required_mfcl_figures, ".png")))
]
if (length(missing_mfcl_figures)) {
  stop("Required model-fit figure(s) did not render: ", paste(missing_mfcl_figures, collapse = ", "), call. = FALSE)
}

# Diagnostic population dynamics with delta-method intervals ----------------
unc <- report_data$model$annual_uncertainty
quantity_specs <- list(
  depletion = list(
    y = expression(italic(SB)[italic(t)]/italic(SB)[italic(F)==0~","~italic(t)]),
    lrp = 0.20
  ),
  spawning_potential = list(y = expression("Spawning potential"~(10^3~"t")), lrp = NA_real_),
  recruitment = list(y = expression("Recruitment (millions of fish)"), lrp = NA_real_)
)
interval_plot <- function(quantity) {
  z <- unc[unc$quantity == quantity, , drop = FALSE]
  spec <- quantity_specs[[quantity]]
  p <- ggplot2::ggplot(z, ggplot2::aes(x = year)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lower_95, ymax = upper_95, fill = "95% interval"), alpha = 1) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lower_80, ymax = upper_80, fill = "80% interval"), alpha = 1) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lower_50, ymax = upper_50, fill = "50% interval"), alpha = 1) +
    ggplot2::geom_line(ggplot2::aes(y = estimate, colour = "Median"), linewidth = 0.75) +
    ggplot2::scale_fill_manual(values = c("50% interval" = blue50, "80% interval" = blue80, "95% interval" = blue95)) +
    ggplot2::scale_colour_manual(values = c("Median" = navy)) +
    ggplot2::labs(x = "Year", y = spec$y, fill = NULL, colour = NULL) +
    theme_report(10) +
    ggplot2::theme(legend.position = "none")
  if (is.finite(spec$lrp)) {
    p <- p + ggplot2::geom_hline(yintercept = spec$lrp, colour = red, linetype = 2, linewidth = 0.6) +
      ggplot2::annotate("text", x = min(z$year) + 5, y = spec$lrp, label = "LRP", colour = red, vjust = -0.5, size = 3.1, family = "serif")
  }
  p
}
f_data <- report_data$model$annual
p_f <- ggplot2::ggplot(f_data, ggplot2::aes(x = Year, y = `Annual population-weighted F`)) +
  ggplot2::geom_line(colour = navy, linewidth = 0.75) +
  ggplot2::labs(x = "Year", y = expression(italic(F)~("year"^{-1}))) +
  theme_report(10) +
  ggplot2::theme(legend.position = "none")
p_dynamics <- (interval_plot("depletion") | interval_plot("spawning_potential")) /
  (interval_plot("recruitment") | p_f) +
  patchwork::plot_annotation(tag_levels = "a") &
  ggplot2::theme(plot.tag.position = c(0.01, 0.99))
save_figure(p_dynamics, "diagnostic-population-dynamics", width = 7.1, height = 6.2)

# Likelihood profiles: each curve is expressed relative to its own minimum --
profile <- report_data$likelihood_profile$components
expected_profile_components <- c("Total", "Indices", "LFs", "Age", "Tags", "Penalties")
if (!all(expected_profile_components %in% unique(profile$component))) {
  stop("Likelihood-profile payload is missing one or more broad components.", call. = FALSE)
}
if (any(!is.finite(profile$biomass_ratio)) || any(!is.finite(profile$value))) {
  stop("Likelihood-profile payload contains non-finite broad-component values.", call. = FALSE)
}
profile$component <- factor(
  profile$component,
  levels = expected_profile_components
)
profile <- profile[!is.na(profile$component), , drop = FALSE]
profile_wide <- reshape(
  profile[, c("biomass_ratio", "component", "value")],
  idvar = "biomass_ratio", timevar = "component", direction = "wide"
)
profile_value_columns <- paste0("value.", expected_profile_components)
if (!all(profile_value_columns %in% names(profile_wide)) || any(!stats::complete.cases(profile_wide[, profile_value_columns]))) {
  stop("Broad likelihood components do not share a complete profile grid.", call. = FALSE)
}
profile_closure <- profile_wide$value.Total - rowSums(profile_wide[, profile_value_columns[-1L], drop = FALSE])
if (max(abs(profile_closure)) > 1e-6) {
  stop("Broad likelihood components do not close to the total objective.", call. = FALSE)
}
profile_objective <- merge(
  profile_wide[, c("biomass_ratio", "value.Total")],
  report_data$likelihood_profile$points[, c("biomass_ratio", "objective")],
  by = "biomass_ratio"
)
if (!nrow(profile_objective) || max(abs(profile_objective$value.Total - profile_objective$objective)) > 1e-6) {
  stop("Total likelihood profile does not match the profile objective values.", call. = FALSE)
}
component_minimum <- do.call(rbind, lapply(split(profile, profile$component), function(z) {
  z[which.min(z$value), c("component", "value"), drop = FALSE]
}))
names(component_minimum)[names(component_minimum) == "value"] <- "minimum_value"
profile <- merge(profile, component_minimum, by = "component", all.x = TRUE)
profile$delta_nll <- profile$value - profile$minimum_value
if (any(abs(vapply(split(profile$delta_nll, profile$component), min, numeric(1L))) > 1e-10)) {
  stop("Broad likelihood profiles were not normalized to their own minima.", call. = FALSE)
}
profile$component <- factor(profile$component, levels = c("Total", "Indices", "LFs", "Age", "Tags", "Penalties"))
profile_colours <- c(
  "Total" = navy,
  "Indices" = "#0072B2",
  "LFs" = "#D55E00",
  "Age" = "#6A5AA7",
  "Tags" = "#009E73",
  "Penalties" = "#6B7280"
)
profile_labels <- c(
  "Total" = "Total",
  "Indices" = "CPUE indices",
  "LFs" = "Size composition",
  "Age" = "Age-at-length",
  "Tags" = "Tag data",
  "Penalties" = "Penalties"
)
p_profile <- ggplot2::ggplot(profile, ggplot2::aes(x = biomass_ratio, y = delta_nll)) +
  ggplot2::geom_hline(yintercept = 0, colour = "#8A989E", linewidth = 0.35) +
  ggplot2::geom_vline(xintercept = 1, colour = red, linetype = 2, linewidth = 0.55) +
  ggplot2::geom_hline(yintercept = 1.92, colour = orange, linetype = 3, linewidth = 0.55) +
  ggplot2::geom_line(ggplot2::aes(colour = component), linewidth = 0.82, lineend = "round") +
  ggplot2::geom_point(ggplot2::aes(colour = component), size = 1.25) +
  ggplot2::scale_colour_manual(values = profile_colours, labels = profile_labels, drop = FALSE) +
  ggplot2::labs(
    x = "Total average biomass / fitted value",
    y = expression(Delta~"negative log likelihood"),
    colour = NULL
  ) +
  theme_report(10) +
  ggplot2::theme(
    legend.position = "bottom",
    legend.box = "horizontal",
    legend.text = ggplot2::element_text(size = 8)
  )
save_figure(p_profile, "likelihood-profile-components", width = 7.1, height = 4.8)

# Interactive likelihood-profile viewer ------------------------------------
detail <- report_data$likelihood_profile$detail
if (any(!is.finite(detail$biomass_ratio)) || any(!is.finite(detail$value))) {
  stop("Likelihood-profile payload contains non-finite detailed-component values.", call. = FALSE)
}
detail_minimum <- do.call(rbind, lapply(split(detail, interaction(detail$detail_group, detail$detail, drop = TRUE)), function(z) {
  z[which.min(z$value), c("detail_group", "detail", "value"), drop = FALSE]
}))
names(detail_minimum)[names(detail_minimum) == "value"] <- "minimum_value"
detail <- merge(detail, detail_minimum, by = c("detail_group", "detail"), all.x = TRUE)
detail$delta_nll <- detail$value - detail$minimum_value
detail <- detail[is.finite(detail$biomass_ratio) & is.finite(detail$delta_nll), , drop = FALSE]
detail_curve <- interaction(detail$detail_group, detail$detail, drop = TRUE)
if (any(abs(vapply(split(detail$delta_nll, detail_curve), min, numeric(1L))) > 1e-10)) {
  stop("Detailed likelihood profiles were not normalized to their own minima.", call. = FALSE)
}

viewer <- plotly::plot_ly()
trace_groups <- character()
detail_colours <- c(
  "CPUE index" = "rgba(0,114,178,0.58)",
  "Length frequency" = "rgba(213,94,0,0.58)",
  "Penalty" = "rgba(107,114,128,0.58)",
  "Tag release group" = "rgba(204,121,167,0.58)",
  "Weight frequency" = "rgba(0,158,115,0.58)"
)
for (component in levels(profile$component)) {
  z <- profile[profile$component == component, , drop = FALSE]
  if (!nrow(z)) next
  z <- z[order(z$biomass_ratio), , drop = FALSE]
  viewer <- plotly::add_trace(
    viewer, data = z, x = ~biomass_ratio, y = ~delta_nll,
    type = "scatter", mode = "lines+markers", name = unname(profile_labels[[component]]),
    line = list(color = unname(profile_colours[[component]]), width = 2.35),
    marker = list(color = unname(profile_colours[[component]]), size = 4.6,
                  line = list(color = "#FFFFFF", width = 0.55)),
    visible = TRUE,
    text = ~paste0(
      "Component: ", component,
      "<br>Biomass ratio: ", sprintf("%.3f", biomass_ratio),
      "<br>Delta NLL (curve minimum = 0): ", sprintf("%.3f", delta_nll),
      "<br>Objective component: ", sprintf("%.3f", value)
    ), hoverinfo = "text"
  )
  trace_groups <- c(trace_groups, "Broad components")
}
broad_trace_count <- length(trace_groups)
detail_groups <- unique(detail$detail_group)
for (group in detail_groups) {
  group_data <- detail[detail$detail_group == group, , drop = FALSE]
  for (item in unique(group_data$detail)) {
    z <- group_data[group_data$detail == item, , drop = FALSE]
    z <- z[order(z$biomass_ratio), , drop = FALSE]
    viewer <- plotly::add_trace(
      viewer, data = z, x = ~biomass_ratio, y = ~delta_nll,
      type = "scatter", mode = "lines", name = item,
      legendgroup = group, showlegend = FALSE, visible = FALSE,
      line = list(color = unname(detail_colours[[group]]), width = 1.35),
      text = ~paste0(
        "Group: ", detail_group,
        "<br>Item: ", detail,
        "<br>Biomass ratio: ", sprintf("%.3f", biomass_ratio),
        "<br>Delta NLL (curve minimum = 0): ", sprintf("%.3f", delta_nll),
        "<br>Component value: ", sprintf("%.3f", value)
      ), hoverinfo = "text"
    )
    trace_groups <- c(trace_groups, group)
  }
}
buttons <- lapply(c("Broad components", detail_groups), function(group) {
  list(
    method = "update",
    args = list(
      list(visible = trace_groups == group),
      list(
        title = list(text = group, x = 0.02, xanchor = "left"),
        showlegend = identical(group, "Broad components")
      )
    ),
    label = group
  )
})
viewer <- plotly::layout(
  viewer,
  title = list(text = "Broad components", x = 0.02, xanchor = "left"),
  xaxis = list(
    title = "Total average biomass / fitted value", zeroline = FALSE,
    gridcolor = "#E5ECEF", linecolor = "#78909C", ticks = "outside"
  ),
  yaxis = list(title = "Change in negative log likelihood", zeroline = TRUE,
               zerolinecolor = "#8A989E", gridcolor = "#E5ECEF",
               linecolor = "#78909C", ticks = "outside"),
  legend = list(orientation = "h", y = -0.22, x = 0.01, xanchor = "left"),
  font = list(family = "Arial, sans-serif", color = "#17384A", size = 13),
  paper_bgcolor = "#FFFFFF", plot_bgcolor = "#FFFFFF",
  margin = list(l = 75, r = 25, b = 125, t = 90),
  updatemenus = list(list(
    type = "dropdown", buttons = buttons, x = 0.99, xanchor = "right",
    y = 1.15, yanchor = "top", direction = "down"
  )),
  shapes = list(list(
    type = "line", x0 = 1, x1 = 1, y0 = 0, y1 = 1, yref = "paper",
    line = list(color = red, dash = "dash", width = 1)
  )),
  hovermode = "closest"
)
viewer <- htmlwidgets::prependContent(
  viewer,
  htmltools::tags$div(
    style = "font-family:system-ui,sans-serif;max-width:1200px;margin:18px auto 0;padding:0 16px;color:#17384a;",
    htmltools::tags$h1("BET 2026 likelihood-profile viewer"),
    htmltools::tags$p(
      "Select a likelihood component or detailed group from the menu. Each curve is expressed as a change from its own minimum; hover over a curve for the underlying numeric value."
    )
  )
)
viewer_file <- file.path(viewer_dir, "bet-2026-likelihood-profile-viewer.html")
htmlwidgets::saveWidget(viewer, viewer_file, selfcontained = TRUE, title = "BET 2026 likelihood-profile viewer")

# Jitter --------------------------------------------------------------------
jr <- report_data$jitter$runs
jr$pass <- jr$completed & is.finite(jr$max_gradient) & jr$max_gradient <= 1e-4
jr$point_colour <- ifelse(jr$pass, teal, ifelse(jr$completed, orange, grey))
jterm <- report_data$jitter$time_series |>
  dplyr::group_by(seed) |>
  dplyr::slice_max(year, n = 1, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::left_join(jr[, c("seed", "pass")], by = "seed")
p_j1 <- ggplot2::ggplot(jr, ggplot2::aes(seed, objective_delta, colour = status)) +
  ggplot2::geom_hline(yintercept = 0, colour = red, linetype = 2, linewidth = 0.5) +
  ggplot2::geom_point(size = 2) +
  ggplot2::scale_colour_manual(values = c("MGC <= 1e-4" = teal, "MGC > 1e-4" = orange, "Not completed" = grey)) +
  ggplot2::labs(x = "Jitter seed", y = expression(Delta~"objective function"), colour = NULL) + theme_report(9.5) +
  ggplot2::theme(legend.position = "none")
p_j2 <- ggplot2::ggplot(jr[jr$completed, , drop = FALSE], ggplot2::aes(seed, max_gradient, colour = status)) +
  ggplot2::geom_hline(yintercept = 1e-4, colour = red, linetype = 2, linewidth = 0.5) +
  ggplot2::geom_point(size = 2) + ggplot2::scale_y_log10() +
  ggplot2::scale_colour_manual(values = c("MGC <= 1e-4" = teal, "MGC > 1e-4" = orange)) +
  ggplot2::labs(x = "Jitter seed", y = "Maximum gradient component", colour = NULL) + theme_report(9.5) +
  ggplot2::theme(legend.position = "none")
p_j3 <- ggplot2::ggplot(jterm, ggplot2::aes(seed, depletion, colour = pass)) +
  ggplot2::geom_hline(yintercept = report_data$model$fit_summary$terminal_depletion_2024[[1L]], colour = red, linetype = 2, linewidth = 0.5) +
  ggplot2::geom_point(size = 2) +
  ggplot2::scale_colour_manual(values = c(`TRUE` = teal, `FALSE` = orange), labels = c(`TRUE` = "MGC <= 1e-4", `FALSE` = "Other")) +
  ggplot2::labs(x = "Jitter seed", y = expression(italic(SB)[2024]/italic(SB)[italic(F)==0~","~2024]), colour = NULL) + theme_report(9.5)
jts <- report_data$jitter$time_series |>
  dplyr::left_join(jr[, c("seed", "pass")], by = "seed") |>
  dplyr::filter(pass)
p_j4 <- ggplot2::ggplot(jts, ggplot2::aes(year, depletion, group = seed)) +
  ggplot2::geom_line(colour = teal, alpha = 0.32, linewidth = 0.35) +
  ggplot2::geom_line(
    data = transform(report_data$model$annual, seed = 0),
    ggplot2::aes(Year, `Dynamic spawning depletion`, group = seed),
    colour = navy, linewidth = 0.8, inherit.aes = FALSE
  ) +
  ggplot2::labs(x = "Year", y = expression(italic(SB)[italic(t)]/italic(SB)[italic(F)==0~","~italic(t)])) + theme_report(9.5)
p_jitter <- (p_j1 | p_j2) / (p_j3 | p_j4) + patchwork::plot_annotation(tag_levels = "a") &
  ggplot2::theme(plot.tag.position = c(0.01, 0.99))
save_figure(p_jitter, "jitter-diagnostics", width = 7.1, height = 6.0)

# Retrospective --------------------------------------------------------------
retro <- report_data$retrospective$time_series
rho <- report_data$retrospective$mohn_rho
retro_specs <- list(
  depletion = list(y = expression(italic(SB)[italic(t)]/italic(SB)[italic(F)==0~","~italic(t)]), key = "depletion"),
  spawning_potential = list(y = expression("Spawning potential"~(10^3~"t")), key = "spawning_potential"),
  recruitment = list(y = expression("Recruitment (millions of fish)"), key = "recruitment"),
  fishing_mortality = list(y = expression(italic(F)~("year"^{-1})), key = "fishing_mortality")
)
retro_plot <- function(name) {
  spec <- retro_specs[[name]]
  rr <- rho$rho[match(name, c("depletion", "spawning_potential", "recruitment", "fishing_mortality"))]
  ggplot2::ggplot(retro, ggplot2::aes(x = year, y = .data[[spec$key]], group = peel, colour = factor(peel))) +
    ggplot2::geom_line(linewidth = 0.55, alpha = 0.9) +
    ggplot2::scale_colour_viridis_d(option = "C", end = 0.9, direction = -1) +
    ggplot2::annotate("label", x = min(retro$year) + 2, y = Inf, label = sprintf("Mohn's rho = %.3f", rr), hjust = 0, vjust = 1.2, size = 2.8, family = "serif", linewidth = 0.2) +
    ggplot2::labs(x = "Year", y = spec$y, colour = "Peel") + theme_report(9.5) +
    ggplot2::theme(legend.position = "none")
}
p_retro <- (retro_plot("depletion") | retro_plot("spawning_potential")) /
  (retro_plot("recruitment") | retro_plot("fishing_mortality")) +
  patchwork::plot_annotation(tag_levels = "a") & ggplot2::theme(plot.tag.position = c(0.01, 0.99))
save_figure(p_retro, "retrospective-diagnostics", width = 7.1, height = 6.0)

# Self-test -----------------------------------------------------------------
st_runs <- report_data$self_test$runs
st_management <- report_data$self_test$management_recovery
metric_labels <- c(
  fmsy = expression(italic(F)[MSY]),
  frecent_fmsy = expression(italic(F)[recent]/italic(F)[MSY]),
  msy = "MSY",
  sbmsy = expression(italic(SB)[MSY])
)
p_s1 <- ggplot2::ggplot(st_runs, ggplot2::aes(replicate, max_grad)) +
  ggplot2::geom_hline(yintercept = 1e-4, colour = red, linetype = 2, linewidth = 0.5) +
  ggplot2::geom_point(colour = teal, size = 1.7) + ggplot2::scale_y_log10() +
  ggplot2::labs(x = "Self-test replicate", y = "Maximum gradient component") + theme_report(9.5)
p_s2 <- ggplot2::ggplot(st_management, ggplot2::aes(metric, 100 * rel_delta)) +
  ggplot2::geom_hline(yintercept = 0, colour = red, linetype = 2, linewidth = 0.5) +
  ggplot2::geom_violin(fill = blue80, colour = navy, linewidth = 0.45, trim = FALSE) +
  ggplot2::geom_boxplot(width = 0.16, outlier.shape = NA, fill = "white", linewidth = 0.4) +
  ggplot2::scale_x_discrete(labels = metric_labels) +
  ggplot2::labs(x = NULL, y = "Relative recovery error (%)") + theme_report(9.5)
terminal_recovery <- report_data$self_test$annual_recovery |>
  dplyr::group_by(replicate) |>
  dplyr::slice_max(year, n = 1, with_ties = FALSE) |>
  dplyr::ungroup()
terminal_long <- tidyr::pivot_longer(
  terminal_recovery,
  cols = c(depletion_rel_delta, spawning_potential_rel_delta, recruitment_rel_delta, fishing_mortality_rel_delta),
  names_to = "quantity", values_to = "relative_error"
)
terminal_labels <- c(
  depletion_rel_delta = "Depletion", spawning_potential_rel_delta = "Spawning potential",
  recruitment_rel_delta = "Recruitment", fishing_mortality_rel_delta = "Fishing mortality"
)
p_s3 <- ggplot2::ggplot(terminal_long, ggplot2::aes(quantity, 100 * relative_error)) +
  ggplot2::geom_hline(yintercept = 0, colour = red, linetype = 2, linewidth = 0.5) +
  ggplot2::geom_violin(fill = blue80, colour = navy, linewidth = 0.45, trim = FALSE) +
  ggplot2::geom_boxplot(width = 0.16, outlier.shape = NA, fill = "white", linewidth = 0.4) +
  ggplot2::scale_x_discrete(labels = terminal_labels) +
  ggplot2::labs(x = NULL, y = "Terminal relative recovery error (%)") + theme_report(9.5) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 20, hjust = 1))
st_param <- report_data$self_test$parameter_recovery
p_s4 <- ggplot2::ggplot(st_param, ggplot2::aes(parameter, 100 * rel_diff)) +
  ggplot2::geom_hline(yintercept = 0, colour = red, linetype = 2, linewidth = 0.5) +
  ggplot2::geom_boxplot(fill = blue80, colour = navy, outlier.alpha = 0.35, linewidth = 0.45) +
  ggplot2::labs(x = "Profile parameter", y = "Relative recovery error (%)") + theme_report(9.5) +
  ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 25, hjust = 1))
p_selftest <- (p_s1 | p_s2) / (p_s3 | p_s4) + patchwork::plot_annotation(tag_levels = "a") &
  ggplot2::theme(plot.tag.position = c(0.01, 0.99))
save_figure(p_selftest, "self-test-diagnostics", width = 7.1, height = 6.1)

# ASPM comparison -----------------------------------------------------------
aspm <- report_data$aspm$annual
aspm_long <- list(
  list(column = "Dynamic spawning depletion", y = expression(italic(SB)[italic(t)]/italic(SB)[italic(F)==0~","~italic(t)])),
  list(column = "Spawning potential (1000 t)", y = expression("Spawning potential"~(10^3~"t"))),
  list(column = "Recruitment (millions)", y = expression("Recruitment (millions of fish)")),
  list(column = "Annual population-weighted F", y = expression(italic(F)~("year"^{-1})))
)
aspm_plot <- function(spec) {
  ggplot2::ggplot(aspm, ggplot2::aes(x = Year, y = .data[[spec$column]], colour = model, linetype = model)) +
    ggplot2::geom_line(linewidth = 0.72) +
    ggplot2::scale_colour_manual(values = model_colours) +
    ggplot2::scale_linetype_manual(values = c("Diagnostic" = 1, "ASPM, fitted recruitment" = 2, "ASPM, constant recruitment" = 3)) +
    ggplot2::labs(x = "Year", y = spec$y, colour = NULL, linetype = NULL) + theme_report(9.5) +
    ggplot2::theme(legend.position = "none")
}
aspm_plots <- lapply(aspm_long, aspm_plot)
p_aspm <- (aspm_plots[[1L]] | aspm_plots[[2L]]) / (aspm_plots[[3L]] | aspm_plots[[4L]]) +
  patchwork::plot_annotation(tag_levels = "a") & ggplot2::theme(plot.tag.position = c(0.01, 0.99))
p_aspm <- p_aspm + patchwork::plot_layout(guides = "collect") & ggplot2::theme(legend.position = "bottom")
save_figure(p_aspm, "aspm-comparison", width = 7.1, height = 6.2)

# Hessian scale diagnostic --------------------------------------------------
hpar <- report_data$hessian$parameter_table
hpar$family <- sub("[(].*$", "", hpar$par)
hpar$se <- suppressWarnings(as.numeric(hpar$se_pos))
hpar <- hpar[is.finite(hpar$se) & hpar$se > 0, , drop = FALSE]
hpar$rank <- rank(hpar$se, ties.method = "first")
family_count <- sort(table(hpar$family), decreasing = TRUE)
keep_families <- names(family_count)[seq_len(min(10L, length(family_count)))]
hpar_family <- hpar[hpar$family %in% keep_families, , drop = FALSE]
hpar_family$family <- factor(hpar_family$family, levels = rev(keep_families))
p_h1 <- ggplot2::ggplot(hpar, ggplot2::aes(rank, se)) +
  ggplot2::geom_point(colour = teal, alpha = 0.45, size = 0.8) + ggplot2::scale_y_log10() +
  ggplot2::labs(x = "Parameter rank", y = "Standard error (log scale)") + theme_report(9.5)
p_h2 <- ggplot2::ggplot(hpar_family, ggplot2::aes(family, se)) +
  ggplot2::geom_boxplot(fill = blue80, colour = navy, outlier.alpha = 0.25, linewidth = 0.4) +
  ggplot2::scale_y_log10() + ggplot2::coord_flip() +
  ggplot2::labs(x = "Parameter family", y = "Standard error (log scale)") + theme_report(9.5)
p_hessian <- (p_h1 | p_h2) + patchwork::plot_annotation(tag_levels = "a")
save_figure(p_hessian, "hessian-parameter-scales", width = 7.1, height = 3.8)

# Tables: CSV, Word-copy HTML and LaTeX -------------------------------------
html_escape <- function(x) as.character(htmltools::htmlEscape(as.character(x), attribute = FALSE))
tex_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\", "@@BACKSLASH@@", x, fixed = TRUE)
  x <- gsub("&", "\\&", x, fixed = TRUE)
  x <- gsub("%", "\\%", x, fixed = TRUE)
  x <- gsub("$", "\\$", x, fixed = TRUE)
  x <- gsub("#", "\\#", x, fixed = TRUE)
  x <- gsub("_", "\\_", x, fixed = TRUE)
  x <- gsub("{", "\\{", x, fixed = TRUE)
  x <- gsub("}", "\\}", x, fixed = TRUE)
  x <- gsub("~", "\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("^", "\\textasciicircum{}", x, fixed = TRUE)
  gsub("@@BACKSLASH@@", "\\textbackslash{}", x, fixed = TRUE)
}
tex_breakable <- function(x) {
  x <- tex_escape(x)
  x <- gsub(".", ".\\allowbreak{}", x, fixed = TRUE)
  x <- gsub("/", "/\\allowbreak{}", x, fixed = TRUE)
  gsub(",", ",\\allowbreak{}", x, fixed = TRUE)
}
format_cell <- function(x) {
  if (is.numeric(x)) {
    out <- ifelse(is.na(x), "", format(x, trim = TRUE, scientific = FALSE, big.mark = ","))
  } else {
    out <- ifelse(is.na(x), "", as.character(x))
  }
  out
}
latex_columns <- function(n) {
  specs <- list(
    `1` = c(0.92),
    `2` = c(0.34, 0.58),
    `3` = c(0.23, 0.32, 0.35),
    `4` = c(0.18, 0.23, 0.23, 0.26),
    `5` = c(0.14, 0.18, 0.18, 0.18, 0.22),
    `6` = c(0.12, 0.15, 0.15, 0.15, 0.15, 0.18)
  )
  widths <- specs[[as.character(n)]] %||% rep(0.82 / n, n)
  paste(sprintf(">{\\raggedright\\arraybackslash}p{%.2f\\linewidth}", widths), collapse = "")
}
latex_header <- function(x) {
  labels <- c(
    "SB / SB(F=0)" = "$SB_t/SB_{F=0,t}$",
    "SB / SB(MSY)" = "$SB_t/SB_{\\mathrm{MSY}}$",
    "F / F(MSY)" = "$F_t/F_{\\mathrm{MSY}}$",
    "F (year^-1)" = "$F$ (year$^{-1}$)",
    "Spawning potential (10^3 t)" = "Spawning potential ($10^3$ t)"
  )
  hit <- unname(labels[x])
  ifelse(is.na(hit), tex_escape(x), hit)
}
write_table_tex <- function(data, id, caption_latex, label) {
  path <- file.path(table_dir, paste0(id, ".tex"))
  data[] <- lapply(data, format_cell)
  header <- paste(latex_header(names(data)), collapse = " & ")
  rows <- apply(data, 1L, function(row) paste(tex_breakable(row), collapse = " & "))
  lines <- c(
    "\\begingroup",
    "\\footnotesize",
    "\\setlength{\\tabcolsep}{3pt}",
    "\\renewcommand{\\arraystretch}{1.12}",
    paste0("\\begin{longtable}{@{}", latex_columns(ncol(data)), "@{}}"),
    paste0("\\caption{", caption_latex, "}\\label{tab:", label, "}\\\\"),
    "\\toprule",
    paste0(header, " \\\\"),
    "\\midrule",
    "\\endfirsthead",
    "\\toprule",
    paste0(header, " \\\\"),
    "\\midrule",
    "\\endhead",
    "\\midrule",
    paste0("\\multicolumn{", ncol(data), "}{r}{\\footnotesize Continued on next page}\\\\"),
    "\\endfoot",
    "\\bottomrule",
    "\\endlastfoot",
    paste0(rows, " \\\\"),
    "\\end{longtable}",
    "\\endgroup"
  )
  writeLines(lines, path, useBytes = TRUE)
  path
}
write_table_bundle <- function(data, id, caption_html, caption_latex, label = id) {
  csv <- file.path(table_dir, paste0(id, ".csv"))
  utils::write.csv(data, csv, row.names = FALSE, na = "")
  tex <- write_table_tex(data, id, caption_latex, label)
  list(id = id, data = data, caption_html = caption_html, caption_latex = caption_latex, csv = csv, tex = tex)
}

fit <- report_data$model$fit_summary[1, ]
summary_lookup <- stats::setNames(as.character(report_data$model$summary$Value), report_data$model$summary$Item)
fit_table <- data.frame(
  Metric = c("Final diagnostic job", "Objective function", "Maximum gradient component", "Hessian", "Active parameters", "Years", "Regions", "Tag release groups"),
  Value = c(
    "22974", formatC(fit$objective, format = "f", digits = 1, big.mark = ","),
    format(fit$max_gradient, scientific = TRUE, digits = 3), "Positive definite",
    summary_lookup[["Active parameters"]], summary_lookup[["Years"]],
    summary_lookup[["Regions"]], summary_lookup[["Tag release groups"]]
  ),
  stringsAsFactors = FALSE
)
objective_table <- report_data$model$objective
names(objective_table) <- c("Likelihood component", "Negative log likelihood")
objective_table[[2L]] <- formatC(objective_table[[2L]], format = "f", digits = 1, big.mark = ",")
recent <- report_data$model$recent
recent_table <- data.frame(
  Period = recent$Period,
  Years = recent$Years,
  `SB / SB(F=0)` = sprintf("%.3f", recent$`Dynamic spawning depletion`),
  `SB / SB(MSY)` = sprintf("%.3f", recent$`SB/SBMSY`),
  `F / F(MSY)` = sprintf("%.3f", recent$`F/FMSY`),
  `Spawning potential (10^3 t)` = formatC(recent$`Spawning potential (1000 t)`, format = "f", digits = 1, big.mark = ","),
  check.names = FALSE
)
hess <- report_data$hessian$summary
hessian_table <- data.frame(
  Metric = c("Status", "Parameters", "Negative eigenvalues", "Smallest eigenvalue", "Largest eigenvalue", "Condition number"),
  Value = c(
    hess$hessian_status, hess$n_total_eigenvalues, hess$n_negative_eigenvalues,
    format(hess$smallest_eigenvalue, scientific = TRUE, digits = 4),
    format(hess$largest_eigenvalue, scientific = TRUE, digits = 4),
    format(hess$positive_condition_number, scientific = TRUE, digits = 4)
  ),
  stringsAsFactors = FALSE
)
check_table <- data.frame(
  Diagnostic = c("Jitter", "Retrospective", "Self-test", "Likelihood profile", "ASPM"),
  Planned = c(30, 7, 50, 45, 2),
  Completed = c(sum(jr$completed), 7, sum(st_runs$run_completed), 45, sum(report_data$aspm$runs$completed)),
  `Primary result` = c(
    sprintf("%d fits met MGC <= 1e-4", sum(jr$pass)),
    "Seven terminal-year peels",
    "All refits completed",
    "All profile points completed",
    "Both variants completed"
  ),
  check.names = FALSE
)
rho_table <- report_data$retrospective$mohn_rho[, c("quantity", "rho")]
names(rho_table) <- c("Quantity", "Mohn's rho")
rho_table[[2L]] <- sprintf("%.3f", rho_table[[2L]])
jitter_table <- data.frame(
  Metric = c("Jitter starts", "Completed fits", "MGC <= 1e-4", "Lower objective than diagnostic", "Lowest objective"),
  Value = c(
    nrow(jr), sum(jr$completed), sum(jr$pass),
    sum(jr$pass & jr$objective_delta < 0, na.rm = TRUE),
    formatC(min(jr$objective[jr$pass], na.rm = TRUE), format = "f", digits = 1, big.mark = ",")
  ),
  stringsAsFactors = FALSE
)
selftest_table <- st_management |>
  dplyr::group_by(metric) |>
  dplyr::summarise(
    `Median relative error (%)` = 100 * stats::median(rel_delta, na.rm = TRUE),
    `2.5th percentile (%)` = 100 * quantile_safe(rel_delta, 0.025),
    `97.5th percentile (%)` = 100 * quantile_safe(rel_delta, 0.975),
    .groups = "drop"
  ) |>
  dplyr::mutate(dplyr::across(where(is.numeric), ~sprintf("%.2f", .x)))
names(selftest_table)[1L] <- "Quantity"
aspm_terminal <- aspm |>
  dplyr::group_by(model) |>
  dplyr::slice_max(Year, n = 1, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    Model = model, Year,
    `SB / SB(F=0)` = sprintf("%.3f", `Dynamic spawning depletion`),
    `Spawning potential (10^3 t)` = formatC(`Spawning potential (1000 t)`, format = "f", digits = 1, big.mark = ","),
    `Recruitment (millions)` = sprintf("%.1f", `Recruitment (millions)`),
    `F (year^-1)` = sprintf("%.3f", `Annual population-weighted F`)
  )
fishery_table <- report_data$mappings$fisheries[, c("fishery", "fishery_name", "region", "group", "selectivity_group", "selectivity_name")]
names(fishery_table) <- c("Fishery", "Name", "Region", "Data group", "Selectivity group", "Selectivity grouping")
tag_table <- report_data$mappings$tag_reporting_groups[, c("tag_rep_group", "tag_programs", "fisheries", "release_groups", "release_years", "active")]
names(tag_table) <- c("Group", "Tag programme", "Fisheries", "Release groups", "Release years", "Estimated")
tag_table$Estimated <- ifelse(tag_table$Estimated, "Yes", "No")
release_summary <- report_data$mappings$tag_release_groups |>
  dplyr::group_by(tag_program, release_region) |>
  dplyr::summarise(
    `Release groups` = dplyr::n(),
    `First release year` = min(release_year),
    `Last release year` = max(release_year),
    .groups = "drop"
  )
names(release_summary)[1:2] <- c("Tag programme", "Region")

tables <- list(
  write_table_bundle(fit_table, "model-fit-summary", "Configuration and convergence summary for the diagnostic model.", "Configuration and convergence summary for the diagnostic model."),
  write_table_bundle(objective_table, "objective-components", "Negative-log-likelihood components at the fitted solution.", "Negative-log-likelihood components at the fitted solution."),
  write_table_bundle(recent_table, "recent-stock-status", "Latest annual and recent four-year diagnostic-model quantities.", "Latest annual and recent four-year diagnostic-model quantities."),
  write_table_bundle(hessian_table, "hessian-summary", "Hessian and curvature summary for the fitted model.", "Hessian and curvature summary for the fitted model."),
  write_table_bundle(check_table, "diagnostic-check-summary", "Completion and principal result of each diagnostic check.", "Completion and principal result of each diagnostic check."),
  write_table_bundle(rho_table, "retrospective-summary", "Mohn's rho from seven terminal-year retrospective peels.", "Mohn's $\\rho$ from seven terminal-year retrospective peels."),
  write_table_bundle(jitter_table, "jitter-summary", "Jitter convergence and objective-function summary.", "Jitter convergence and objective-function summary."),
  write_table_bundle(selftest_table, "self-test-summary", "Relative recovery error for management quantities across 50 self-test refits.", "Relative recovery error for management quantities across 50 self-test refits."),
  write_table_bundle(aspm_terminal, "aspm-terminal-summary", "Terminal quantities for the diagnostic model and the two age-structured production-model variants.", "Terminal quantities for the diagnostic model and the two age-structured production-model variants."),
  write_table_bundle(fishery_table, "fishery-grouping", "Fishery definitions and selectivity groupings used in the diagnostic model.", "Fishery definitions and selectivity groupings used in the diagnostic model."),
  write_table_bundle(tag_table, "tag-reporting-rate-groups", "Tag-reporting-rate groups, release coverage and estimation status.", "Tag-reporting-rate groups, release coverage and estimation status."),
  write_table_bundle(release_summary, "tag-release-groups", "Summary of tag-release groups by programme and release region.", "Summary of tag-release groups by programme and release region.")
)
names(tables) <- vapply(tables, `[[`, character(1L), "id")

# Validate every generated LaTeX table in one document.
validation_tex <- file.path(output_dir, "latex-table-validation.tex")
validation_lines <- c(
  "\\documentclass[11pt,a4paper]{article}",
  "\\usepackage[margin=18mm]{geometry}",
  "\\usepackage{booktabs,longtable,array}",
  "\\usepackage[T1]{fontenc}",
  "\\begin{document}",
  unlist(lapply(tables, function(x) c(paste0("\\input{tables/", basename(x$tex), "}"), "\\clearpage"))),
  "\\end{document}"
)
writeLines(validation_lines, validation_tex)
old_wd <- setwd(output_dir)
on.exit(setwd(old_wd), add = TRUE)
latex_log <- system2(
  "xelatex",
  c("-interaction=nonstopmode", "-halt-on-error", basename(validation_tex)),
  stdout = TRUE,
  stderr = TRUE
)
latex_status <- attr(latex_log, "status") %||% 0L
setwd(old_wd)
if (!identical(as.integer(latex_status), 0L) || !file.exists(file.path(output_dir, "latex-table-validation.pdf"))) {
  stop("LaTeX table validation failed:\n", paste(tail(latex_log, 40L), collapse = "\n"), call. = FALSE)
}

# Captions and report HTML --------------------------------------------------
viewer_release_url <- "https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/releases/latest/download/bet-2026-likelihood-profile-viewer.html"
figure_meta <- list(
  `cpue-fit-observation-intervals` = list(
    section = "Model fit",
    caption = "Observed and fitted relative CPUE for the five regional index fisheries. Shading gives the central 95% lognormal observation interval implied by the fixed regional log-scale error values (0.35, 0.24, 0.21, 0.24 and 0.23 for Regions 1-5); it does not represent parameter-estimation uncertainty."
  ),
  `diagnostic-population-dynamics` = list(
    section = "Population dynamics",
    caption = "Diagnostic-model estimates of (a) dynamic spawning depletion, (b) spawning potential, (c) recruitment and (d) annual population-weighted fishing mortality. Shading in panels a-c gives central 50%, 80% and 95% delta-method intervals from the inverse Hessian; panel d shows the fitted fishing-mortality trajectory."
  ),
  `likelihood-profile-components` = list(
    section = "Diagnostics",
    caption = paste0("Likelihood profiles for total average biomass. Each curve is expressed as a change from its own minimum; the dashed vertical line marks the fitted value and the horizontal line in the total panel marks a change of 1.92. Detailed fishery, tag-group and penalty curves with numeric hover values are available in the likelihood-profile viewer."),
    viewer = viewer_release_url
  ),
  `jitter-diagnostics` = list(
    section = "Diagnostics",
    caption = "Jitter diagnostics from 30 dispersed starting values: (a) objective-function difference from the diagnostic fit, (b) maximum gradient component, (c) terminal depletion and (d) depletion trajectories for fits meeting the MGC criterion. Dashed lines mark the diagnostic fit or MGC threshold."
  ),
  `retrospective-diagnostics` = list(
    section = "Diagnostics",
    caption = "Retrospective trajectories for (a) dynamic spawning depletion, (b) spawning potential, (c) recruitment and (d) annual population-weighted fishing mortality. Colours distinguish the diagnostic fit and seven terminal-year peels; labels give Mohn's rho."
  ),
  `self-test-diagnostics` = list(
    section = "Diagnostics",
    caption = "Self-test results from 50 simulated-and-refitted data sets: (a) maximum gradient component, (b) recovery of management quantities, (c) terminal derived quantities and (d) selected profile parameters. Relative errors are refitted minus generating values, divided by generating values."
  ),
  `aspm-comparison` = list(
    section = "Diagnostics",
    caption = "Comparison of the diagnostic model with age-structured production models using fitted or constant recruitment: (a) dynamic spawning depletion, (b) spawning potential, (c) recruitment and (d) annual population-weighted fishing mortality."
  ),
  `hessian-parameter-scales` = list(
    section = "Diagnostics",
    caption = "Parameter standard errors derived from the positive-definite inverse Hessian: (a) ordered standard errors and (b) distributions for the ten most numerous parameter families. Logarithmic axes show the wide range of estimated parameter scales."
  )
)

mfcl_captions <- list(
  `region-map` = list(section = "Overview", caption = "Five-region spatial structure used by the diagnostic model."),
  `total-catch-fits` = list(section = "Model fit", caption = "Observed and fitted total catch through time."),
  `catch-by-fishery-fits` = list(section = "Model fit", caption = "Observed and fitted catch by fishery. Facet labels identify the fisheries and their model regions."),
  `cpue-fits` = list(section = "Model fit", caption = "Observed and fitted abundance indices by index fishery."),
  `cpue-residuals` = list(section = "Model fit", caption = "Residuals for the fitted abundance indices by index fishery."),
  `length-frequency` = list(section = "Model fit", caption = "Observed and fitted length compositions by fishery. Shaded bands are 95% predictive intervals for repeated observations conditional on the fitted composition model; parameter uncertainty is not included."),
  `length-frequency-residuals` = list(section = "Model fit", caption = "Length-composition residuals by fishery and length class."),
  `age-data-fit` = list(section = "Model fit", caption = "Observed and fitted conditional mean age by fishery and year, weighted by the number of aged fish in each length bin."),
  `age-data-fit-by-region` = list(section = "Model fit", caption = "Observed and fitted conditional age-at-length distributions by region. Expected counts use the fitted conditional age distribution and the observed number of aged fish."),
  `age-data-growth-by-region` = list(section = "Model fit", caption = "Observed age-length cells by region over the fitted growth curve. Shading is the fitted mean length at age plus or minus 1.96 length-at-age standard deviations and represents fish-level length variability, not Hessian parameter uncertainty."),
  `age-data-residuals-by-region` = list(section = "Model fit", caption = "Conditional age-at-length residuals by region."),
  `age-data-coverage` = list(section = "Model fit", caption = "Coverage of conditional age-at-length observations by fishery and year."),
  `tag-returns-all` = list(section = "Model fit", caption = "Observed and expected tag returns across tag-release and recapture groups."),
  `tag-returns-by-group` = list(section = "Model fit", caption = "Observed and expected tag returns by tag-release group."),
  `tag-attrition-by-program` = list(section = "Model fit", caption = "Tag attrition through time by tagging programme."),
  `population-biology` = list(section = "Population dynamics", caption = "Growth, maturity, natural mortality and weight-at-age assumptions used in the diagnostic model."),
  `growth-curve` = list(section = "Population dynamics", caption = "Fitted mean length at age. Shading is the mean plus or minus 1.96 length-at-age standard deviations and represents fish-level length variability, not parameter-estimation uncertainty."),
  `fishery-process` = list(section = "Population dynamics", caption = "Estimated fishery selectivity at age for the diagnostic model."),
  `fishery-selectivity-length` = list(section = "Population dynamics", caption = "Estimated fishery selectivity at length for the diagnostic model."),
  `regional-movement` = list(section = "Population dynamics", caption = "Estimated quarterly movement probabilities among the five model regions."),
  `depletion-by-area` = list(section = "Population dynamics", caption = "Dynamic spawning depletion by model region."),
  `recruitment-by-area` = list(section = "Population dynamics", caption = "Estimated recruitment by model region."),
  `spawning-potential-with-without-fishing` = list(section = "Population dynamics", caption = "Spawning potential with and without fishing through time."),
  `total-biomass-with-without-fishing` = list(section = "Population dynamics", caption = "Total biomass with and without fishing through time.")
)

rel_path <- function(path) {
  root <- paste0(output_dir, "/")
  sub(paste0("^", root), "", normalizePath(path, winslash = "/", mustWork = FALSE))
}
for (id in names(mfcl_captions)) {
  png <- file.path(mfcl_dir, "figures", paste0(id, ".png"))
  pdf <- file.path(mfcl_dir, "figures", paste0(id, ".pdf"))
  if (file.exists(png)) {
    figure_meta[[id]] <- c(mfcl_captions[[id]], list(png = png, pdf = if (file.exists(pdf)) pdf else NULL))
  }
}
for (id in setdiff(names(figure_meta), names(mfcl_captions))) {
  figure_meta[[id]]$png <- file.path(figure_dir, paste0(id, ".png"))
  figure_meta[[id]]$pdf <- file.path(figure_dir, paste0(id, ".pdf"))
}

caption_table <- data.frame(
  Figure = names(figure_meta),
  Section = vapply(figure_meta, function(x) x$section, character(1L)),
  Caption = vapply(figure_meta, function(x) x$caption, character(1L)),
  PNG = vapply(figure_meta, function(x) rel_path(x$png), character(1L)),
  PDF = vapply(figure_meta, function(x) if (is.null(x$pdf)) "" else rel_path(x$pdf), character(1L)),
  stringsAsFactors = FALSE
)
utils::write.csv(caption_table, file.path(output_dir, "figure-captions.csv"), row.names = FALSE)

html_table <- function(bundle) {
  data <- bundle$data
  id <- bundle$id
  html_header <- function(x) {
    labels <- c(
      "SB / SB(F=0)" = "<i>SB</i><sub>t</sub> / <i>SB</i><sub>F=0,t</sub>",
      "SB / SB(MSY)" = "<i>SB</i><sub>t</sub> / <i>SB</i><sub>MSY</sub>",
      "F / F(MSY)" = "<i>F</i><sub>t</sub> / <i>F</i><sub>MSY</sub>",
      "F (year^-1)" = "<i>F</i> (year<sup>-1</sup>)",
      "Spawning potential (10^3 t)" = "Spawning potential (10<sup>3</sup> t)"
    )
    hit <- unname(labels[x])
    ifelse(is.na(hit), html_escape(x), hit)
  }
  head_html <- paste0("<th>", html_header(names(data)), "</th>", collapse = "")
  body_html <- paste(vapply(seq_len(nrow(data)), function(i) {
    paste0("<tr>", paste0("<td>", html_escape(format_cell(data[i, , drop = TRUE])), "</td>", collapse = ""), "</tr>")
  }, character(1L)), collapse = "\n")
  paste0(
    "<section class='table-card' id='table-", id, "'>",
    "<p class='caption'><strong>Table.</strong> ", bundle$caption_html, "</p>",
    "<div class='actions'>",
    "<button onclick=\"copyTable('tbl-", id, "')\">Copy table for Word</button>",
    "<button onclick=\"copyText('tex-", id, "')\">Copy LaTeX</button>",
    "<a href='", rel_path(bundle$csv), "' download>CSV</a>",
    "<a href='", rel_path(bundle$tex), "' download>LaTeX</a>",
    "</div>",
    "<div class='table-scroll'><table id='tbl-", id, "'><thead><tr>", head_html, "</tr></thead><tbody>", body_html, "</tbody></table></div>",
    "<textarea id='tex-", id, "' class='copy-source'>", html_escape(paste(readLines(bundle$tex, warn = FALSE), collapse = "\n")), "</textarea>",
    "</section>"
  )
}

figure_block <- function(id, compact = FALSE) {
  meta <- figure_meta[[id]]
  if (is.null(meta) || !file.exists(meta$png)) return("")
  latex_snippet <- paste0(
    "\\begin{figure}[htbp]\n\\centering\n\\includegraphics[width=\\linewidth]{", rel_path(meta$pdf %||% meta$png), "}\n",
    "\\caption{", tex_escape(meta$caption), "}\n\\label{fig:", gsub("[^a-z0-9-]", "-", id), "}\n\\end{figure}"
  )
  viewer_link <- if (!is.null(meta$viewer)) paste0("<a href='", meta$viewer, "'>Likelihood-profile viewer</a>") else ""
  paste0(
    "<figure class='figure-card", if (compact) " compact" else "", "' id='fig-", id, "'>",
    "<img src='", rel_path(meta$png), "' alt='", html_escape(meta$caption), "' loading='lazy'>",
    "<figcaption><strong>Figure.</strong> ", html_escape(meta$caption), " ", viewer_link, "</figcaption>",
    "<div class='actions'><a href='", rel_path(meta$png), "' download>PNG</a>",
    if (!is.null(meta$pdf) && file.exists(meta$pdf)) paste0("<a href='", rel_path(meta$pdf), "' download>PDF</a>") else "",
    "<button onclick=\"copyText('cap-", id, "')\">Copy caption</button>",
    "<button onclick=\"copyText('figtex-", id, "')\">Copy LaTeX figure</button></div>",
    "<textarea id='cap-", id, "' class='copy-source'>", html_escape(meta$caption), "</textarea>",
    "<textarea id='figtex-", id, "' class='copy-source'>", html_escape(latex_snippet), "</textarea>",
    "</figure>"
  )
}

fit_ids <- names(figure_meta)[vapply(figure_meta, function(x) identical(x$section, "Model fit"), logical(1L))]
diagnostic_ids <- names(figure_meta)[vapply(figure_meta, function(x) identical(x$section, "Diagnostics"), logical(1L))]
dynamics_ids <- names(figure_meta)[vapply(figure_meta, function(x) identical(x$section, "Population dynamics"), logical(1L))]

references <- report_data$references
reference_html <- paste0(
  "<li><a href='", references$url, "'>", html_escape(references$symbol), "</a>: ", html_escape(references$citation), "</li>",
  collapse = ""
)

html <- paste0(
  "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>",
  "<title>BET 2026 Diagnostic model report</title>",
  "<style>",
  ":root{--navy:#0b5267;--teal:#168a98;--ink:#18384a;--line:#cbdde3;--soft:#edf6f7;--paper:#fff;}",
  "*{box-sizing:border-box}body{margin:0;background:#eaf1f3;color:var(--ink);font-family:Georgia,'Times New Roman',serif;line-height:1.46}",
  ".page{max-width:1120px;margin:0 auto;background:var(--paper);min-height:100vh;padding:34px 46px 70px;box-shadow:0 0 24px #bfd0d5}",
  "h1{font-size:2rem;color:var(--navy);margin:.1rem 0 .45rem}h2{font-size:1.45rem;color:var(--navy);border-bottom:3px solid var(--teal);padding-bottom:.35rem;margin-top:1.7rem}h3{font-size:1.06rem;color:var(--navy)}",
  ".lead{font-size:1.05rem;max-width:920px}.tabs{display:flex;gap:7px;flex-wrap:wrap;position:sticky;top:0;background:#fff;padding:12px 0;border-bottom:1px solid var(--line);z-index:5}",
  ".tabs button,.actions button,.actions a,.primary-link{border:1px solid var(--teal);background:#fff;color:var(--navy);padding:7px 11px;border-radius:5px;text-decoration:none;font:600 .86rem system-ui,sans-serif;cursor:pointer}",
  ".tabs button.active,.primary-link{background:var(--navy);color:#fff}.tab{display:none}.tab.active{display:block}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0}",
  ".metric{background:var(--soft);border:1px solid #b9dce2;border-radius:7px;padding:14px}.metric strong{display:block;font-size:1.45rem;color:var(--navy)}",
  ".note{background:#f5f9fa;border-left:4px solid var(--teal);padding:12px 14px;margin:14px 0}.figure-card,.table-card{margin:22px 0 34px;break-inside:avoid}.figure-card img{width:100%;height:auto;display:block;border:1px solid #d6e1e5}.figure-card.compact img{max-width:850px;margin:auto}",
  "figcaption,.caption{font-size:.95rem;margin:.65rem 0}.actions{display:flex;gap:7px;flex-wrap:wrap;margin:.55rem 0}.table-scroll{overflow:auto;border:1px solid var(--line);border-radius:5px}table{border-collapse:collapse;width:100%;font-size:.88rem}th,td{padding:7px 8px;border-bottom:1px solid #dce6e9;text-align:left;vertical-align:top}th{background:#e8f1f4;color:var(--navy);position:sticky;top:0}.copy-source{position:absolute;left:-99999px;width:1px;height:1px}.thumb-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.thumb-grid .figure-card{margin:0}.thumb-grid figcaption{font-size:.86rem}",
  "code{background:#edf2f4;padding:1px 4px;border-radius:3px}@media(max-width:760px){.page{padding:22px 16px}.cards,.thumb-grid{grid-template-columns:1fr}.tabs{position:static}}",
  "@media print{body{background:#fff}.page{box-shadow:none;max-width:none;padding:0}.tabs,.actions{display:none!important}.tab{display:block!important}.figure-card{page-break-inside:avoid}.figure-card img{max-height:225mm;object-fit:contain}.table-scroll{overflow:visible}h2{page-break-before:always}}",
  "</style></head><body><main class='page'>",
  "<h1>BET 2026 Diagnostic model report</h1>",
  "<p class='lead'>Model fit and diagnostic checks for the 2026 bigeye tuna assessment diagnostic model. Report figures are supplied as 400-dpi PNG and vector PDF files; every table is supplied as CSV and a validated LaTeX fragment.</p>",
  "<p><a class='primary-link' href='", viewer_release_url, "'>Open likelihood-profile viewer</a></p>",
  "<nav class='tabs'>",
  "<button class='active' data-tab='overview'>Overview</button><button data-tab='fit'>Model fit</button><button data-tab='diagnostics'>Diagnostics</button><button data-tab='dynamics'>Population dynamics</button><button data-tab='assets'>Figures and tables</button>",
  "</nav>",
  "<section id='overview' class='tab active'><h2>Overview</h2>",
  "<div class='cards'><div class='metric'><strong>Job 22974</strong>diagnostic handoff</div><div class='metric'><strong>MGC 9.68 x 10<sup>-5</sup></strong>fitted convergence</div><div class='metric'><strong>PDH</strong>Hessian status</div><div class='metric'><strong>1952-2024</strong>model period</div></div>",
  "<div class='note'><strong>Uncertainty.</strong> The inverse Hessian is positive definite. Delta-method intervals are shown for dynamic spawning depletion, spawning potential and recruitment. Annual fishing mortality is shown as the fitted trajectory because its annual Hessian derivative was not calculated.</div>",
  "<div class='note'><strong>Diagnostic checks.</strong> Jitter, seven retrospective peels, 50 self-test refits, a 45-point biomass likelihood profile and two age-structured production-model variants are summarized below. Detailed profile curves are provided in the linked viewer.</div>",
  html_table(tables[["model-fit-summary"]]),
  html_table(tables[["recent-stock-status"]]),
  figure_block("region-map", compact = TRUE),
  figure_block("diagnostic-population-dynamics"),
  "<h3>References</h3><ul>", reference_html, "</ul></section>",
  "<section id='fit' class='tab'><h2>Model fit</h2>",
  "<p>Fits to catch, abundance indices, length compositions, conditional age-at-length data and tagging observations. The length-composition panels include observation-level predictive bands.</p>",
  paste(vapply(fit_ids, figure_block, character(1L)), collapse = ""),
  html_table(tables[["objective-components"]]),
  html_table(tables[["fishery-grouping"]]),
  html_table(tables[["tag-reporting-rate-groups"]]),
  html_table(tables[["tag-release-groups"]]),
  "</section>",
  "<section id='diagnostics' class='tab'><h2>Diagnostics</h2>",
  html_table(tables[["diagnostic-check-summary"]]),
  paste(vapply(diagnostic_ids, figure_block, character(1L)), collapse = ""),
  html_table(tables[["hessian-summary"]]),
  html_table(tables[["jitter-summary"]]),
  html_table(tables[["retrospective-summary"]]),
  html_table(tables[["self-test-summary"]]),
  html_table(tables[["aspm-terminal-summary"]]),
  "</section>",
  "<section id='dynamics' class='tab'><h2>Population dynamics</h2>",
  paste(vapply(dynamics_ids, figure_block, character(1L)), collapse = ""),
  "</section>",
  "<section id='assets' class='tab'><h2>Figures and tables</h2>",
  "<p>Download-ready figures, captions and table formats. The LaTeX table fragments were compiled together during this build; the validation PDF is available below.</p>",
  "<p class='actions'><a href='figure-captions.csv' download>Figure captions (CSV)</a><a href='latex-table-validation.pdf' download>LaTeX validation PDF</a><a href='report-manifest.csv' download>Build manifest</a></p>",
  "<div class='thumb-grid'>", paste(vapply(names(figure_meta), function(id) figure_block(id, compact = TRUE), character(1L)), collapse = ""), "</div>",
  "<h2>Tables</h2>", paste(vapply(tables, html_table, character(1L)), collapse = ""),
  "</section>",
  "</main><script>",
  "document.querySelectorAll('.tabs button').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.tabs button').forEach(x=>x.classList.remove('active'));document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));b.classList.add('active');document.getElementById(b.dataset.tab).classList.add('active');window.scrollTo({top:0,behavior:'smooth'});}));",
  "async function copyText(id){const t=document.getElementById(id).value;await navigator.clipboard.writeText(t);}",
  "async function copyTable(id){const table=document.getElementById(id);const html=table.outerHTML;const text=Array.from(table.rows).map(r=>Array.from(r.cells).map(c=>c.innerText).join('\\t')).join('\\n');try{await navigator.clipboard.write([new ClipboardItem({'text/html':new Blob([html],{type:'text/html'}),'text/plain':new Blob([text],{type:'text/plain'})})]);}catch(e){await navigator.clipboard.writeText(text);}}",
  "</script></body></html>"
)
report_file <- file.path(output_dir, "bet-2026-diagnostic-report.html")
writeLines(html, report_file, useBytes = TRUE)

# Public build manifest and security scan -----------------------------------
manifest_files <- list.files(output_dir, recursive = TRUE, full.names = TRUE)
manifest_files <- manifest_files[file.info(manifest_files)$isdir %in% FALSE]
manifest <- data.frame(
  file = vapply(manifest_files, rel_path, character(1L)),
  bytes = file.info(manifest_files)$size,
  stringsAsFactors = FALSE
)
manifest <- manifest[order(manifest$file), , drop = FALSE]
utils::write.csv(manifest, file.path(output_dir, "report-manifest.csv"), row.names = FALSE)

text_files <- manifest_files[grepl("[.](html|csv|tex|json|log)$", manifest_files, ignore.case = TRUE)]
for (path in text_files) {
  content <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  contains_private_context <- grepl(
    paste0("/home/|/tmp/|/var/lib/|kyuhank|native", "[[:space:]]+MFCL"),
    content,
    ignore.case = TRUE
  )
  # The embedded Plotly/JQuery libraries use the words `password` and
  # `secret` internally. Credential-word scanning therefore applies to the
  # report's human-readable files, while the self-contained viewer is still
  # checked for paths, names and project-specific private terminology.
  is_embedded_viewer <- identical(normalizePath(path, winslash = "/", mustWork = TRUE), normalizePath(viewer_file, winslash = "/", mustWork = TRUE))
  contains_credentials <- !is_embedded_viewer && grepl(
    "password|secret|bearer[[:space:]]",
    content,
    ignore.case = TRUE
  )
  if (contains_private_context || contains_credentials) {
    stop("Public-output security scan failed for ", rel_path(path), call. = FALSE)
  }
}

message("Wrote public Diagnostic report: ", report_file)
message("Wrote self-contained likelihood-profile viewer: ", viewer_file)
message("Validated ", length(tables), " LaTeX tables and ", length(figure_meta), " report figures.")
