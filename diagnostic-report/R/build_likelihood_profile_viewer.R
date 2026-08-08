#!/usr/bin/env Rscript

# Build the public likelihood-profile viewer without rendering the complete
# diagnostic report.  This is deliberately small and depends only on the
# compact public report payload, the checked-in fishery map and the viewer
# template.  It allows the release viewer to be reproduced independently of
# the heavier static-figure exporter.

options(stringsAsFactors = FALSE, scipen = 8)

args <- commandArgs(trailingOnly = TRUE)
repo_root <- if (length(args) >= 1L) {
  normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
} else {
  normalizePath(".", winslash = "/", mustWork = TRUE)
}
output_dir <- if (length(args) >= 2L) args[[2L]] else file.path(repo_root, "diagnostic-report-output", "viewer")
if (!grepl("^/", output_dir)) output_dir <- file.path(repo_root, output_dir)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite is required to build the likelihood-profile viewer.", call. = FALSE)
}
if (!requireNamespace("mfclshiny", quietly = TRUE)) {
  stop("mfclshiny is required to supply the SPC logo asset.", call. = FALSE)
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

payload_file <- file.path(repo_root, "diagnostic-report", "data", "diagnostic-report-data.rds")
template_file <- file.path(repo_root, "diagnostic-report", "likelihood-profile-viewer-template.html")
if (!file.exists(payload_file) || !file.exists(template_file)) {
  stop("The compact report payload or viewer template is missing.", call. = FALSE)
}
report_data <- readRDS(payload_file)
if (!identical(report_data$schema, "bet2026.diagnostic_report.v1")) {
  stop("Unsupported compact report payload schema.", call. = FALSE)
}

fishery_map_env <- new.env(parent = baseenv())
sys.source(file.path(repo_root, "model", "fishery_map.R"), envir = fishery_map_env)
fisheries <- get("fishery_map", envir = fishery_map_env, inherits = FALSE)

navy <- "#0B5267"
profile_colours <- c(
  "Total" = navy,
  "Indices" = "#0072B2",
  "LFs" = "#D55E00",
  "Age" = "#6A5AA7",
  "Tags" = "#009E73",
  "Penalties" = "#6B7280"
)
profile_labels <- c(
  "Total" = "Total", "Indices" = "CPUE", "LFs" = "LF",
  "Age" = "CAAL", "Tags" = "Tag", "Penalties" = "Penalty"
)
expected_components <- names(profile_colours)

normalise_curves <- function(z, group_columns) {
  key <- interaction(z[, group_columns, drop = FALSE], drop = TRUE, lex.order = TRUE)
  minima <- do.call(rbind, lapply(split(z, key), function(curve) {
    curve[which.min(curve$value), c(group_columns, "value"), drop = FALSE]
  }))
  names(minima)[names(minima) == "value"] <- "minimum_value"
  z <- merge(z, minima, by = group_columns, all.x = TRUE, sort = FALSE)
  z$delta_nll <- pmax(0, z$value - z$minimum_value)
  z
}

profile <- report_data$likelihood_profile$components
if (!all(expected_components %in% unique(as.character(profile$component)))) {
  stop("The broad profile payload is incomplete.", call. = FALSE)
}
objective_values <- stats::setNames(
  as.numeric(report_data$model$objective$Value),
  as.character(report_data$model$objective$Component)
)
if (!is.finite(objective_values[["Total objective"]])) {
  stop("The fitted total objective is unavailable.", call. = FALSE)
}
# Only the total likelihood receives the exact fitted objective.  Per-component
# anchors are intentionally not injected: they are not conditional-profile
# evaluations and create artificial kinks in component curves.
profile <- profile[!(profile$component == "Total" & abs(profile$biomass_ratio - 1) <= 1e-10), , drop = FALSE]
profile <- rbind(profile, data.frame(
  scalar = 100, biomass_ratio = 1, component = "Total",
  value = as.numeric(objective_values[["Total objective"]]), stringsAsFactors = FALSE
))
profile$component <- factor(as.character(profile$component), levels = expected_components)
profile <- profile[!is.na(profile$component), , drop = FALSE]
profile <- normalise_curves(profile, "component")

detail <- report_data$likelihood_profile$detail
if (!nrow(detail) || any(!is.finite(detail$biomass_ratio)) || any(!is.finite(detail$value))) {
  stop("The detailed likelihood-profile payload is unavailable or invalid.", call. = FALSE)
}
detail$detail_group[detail$detail_group == "Length frequency"] <- "LF"
detail$detail_group[detail$detail_group == "Weight frequency"] <- "Weight frequency"
fishery_detail <- detail$detail_group %in% c("CPUE index", "LF", "Weight frequency")
fishery_id <- suppressWarnings(as.integer(sub("^([0-9]+).*", "\\1", as.character(detail$detail))))
fishery_label <- fisheries$fishery_name[match(fishery_id, fisheries$fishery)]
detail$detail[fishery_detail & !is.na(fishery_label)] <- fishery_label[fishery_detail & !is.na(fishery_label)]
detail <- normalise_curves(detail, c("detail_group", "detail"))
detail_key <- interaction(detail$detail_group, detail$detail, drop = TRUE)
detail_span <- vapply(split(detail$delta_nll, detail_key), function(x) max(x) - min(x), numeric(1L))
detail <- detail[as.character(detail_key) %in% names(detail_span)[detail_span > 1e-10], , drop = FALSE]

profile_viewer_group <- function(key, label, z, colour, labels = NULL, total_label = NULL,
                                 parent_component = NULL, panel = NULL, kind = "detail") {
  if (is.null(z) || !nrow(z)) return(NULL)
  z <- z[order(as.character(z$curve), z$biomass_ratio), , drop = FALSE]
  curve_names <- sort(unique(as.character(z$curve)))
  total_key <- "__component_total__"
  if (!is.null(total_label)) {
    total_values <- stats::aggregate(value ~ biomass_ratio, data = z, FUN = sum)
    total <- z[rep.int(1L, nrow(total_values)), , drop = FALSE]
    total$biomass_ratio <- total_values$biomass_ratio
    total$value <- total_values$value
    total$curve <- total_key
    total$delta_nll <- total$value - min(total$value)
    z <- rbind(z, total)
    curve_names <- c(total_key, curve_names)
  }
  curve_colours <- stats::setNames(
    grDevices::hcl.colors(length(curve_names), palette = "Dark 3"), curve_names
  )
  curve_colours[[total_key]] <- navy
  rows <- do.call(rbind, lapply(curve_names, function(curve_key) {
    curve <- z[as.character(z$curve) == curve_key, , drop = FALSE]
    data.frame(
      id = paste(key, curve_key, sep = "::"),
      label = if (identical(curve_key, total_key)) total_label else if (is.null(labels)) curve_key else unname(labels[[curve_key]] %||% curve_key),
      group = label,
      colour = unname(curve_colours[[curve_key]]),
      is_total = identical(curve_key, total_key) || identical(curve_key, "Total"),
      x = round(curve$biomass_ratio, 10),
      y = round(curve$delta_nll, 10),
      stringsAsFactors = FALSE
    )
  }))
  list(
    key = key, label = label, kind = kind,
    parent_component = parent_component, panel = panel %||% label,
    curves = rows
  )
}

detail_group <- function(group) {
  z <- detail[detail$detail_group == group, , drop = FALSE]
  if (!nrow(z)) return(NULL)
  transform(z, curve = detail)
}
groups <- list(profile_viewer_group(
  "broad", "Broad components", transform(profile, curve = as.character(component)),
  profile_colours, stats::setNames(unname(profile_labels), names(profile_labels)), kind = "broad"
))
append_group <- function(group) if (!is.null(group)) groups[[length(groups) + 1L]] <<- group

append_group(profile_viewer_group(
  "cpue", "CPUE indices", detail_group("CPUE index"), "#0072B2",
  total_label = "CPUE total", parent_component = "CPUE", panel = "CPUE indices"
))
lf_parts <- Filter(Negate(is.null), list(
  {
    z <- detail_group("LF")
    if (!is.null(z)) transform(z, curve = paste("Length", curve, sep = " | ")) else NULL
  },
  {
    z <- detail_group("Weight frequency")
    if (!is.null(z)) transform(z, curve = paste("Weight", curve, sep = " | ")) else NULL
  }
))
if (length(lf_parts)) append_group(profile_viewer_group(
  "lf", "LF data", do.call(rbind, lf_parts), "#D55E00",
  total_label = "LF total", parent_component = "LF", panel = "LF data"
))

caal <- detail_group("CAAL region")
if (!is.null(caal)) {
  for (region_name in sort(unique(as.character(caal$curve)))) {
    key <- gsub("[^a-z0-9]+", "-", tolower(region_name))
    append_group(profile_viewer_group(
      paste0("caal-", key), region_name,
      caal[as.character(caal$curve) == region_name, , drop = FALSE], "#6A5AA7",
      total_label = paste("CAAL total —", region_name),
      parent_component = "CAAL", panel = region_name
    ))
  }
}

tag_map <- report_data$mappings$tag_release_groups
tag_labels <- stats::setNames(
  sprintf("Group %d | %s | Region %d | %d Q%d", tag_map$release_group, tag_map$tag_program,
          tag_map$release_region, tag_map$release_year, (tag_map$release_month - 1L) %/% 3L + 1L),
  paste("Group", tag_map$release_group)
)
tag <- detail_group("Tag release group")
if (!is.null(tag)) {
  programme_lookup <- stats::setNames(as.character(tag_map$tag_program), paste("Group", tag_map$release_group))
  tag$programme <- unname(programme_lookup[as.character(tag$curve)])
  tag$programme[is.na(tag$programme) | !nzchar(tag$programme)] <- "Other"
  for (programme in sort(unique(tag$programme))) {
    key <- gsub("[^a-z0-9]+", "-", tolower(programme))
    append_group(profile_viewer_group(
      paste0("tag-", key), paste("Tag programme:", programme),
      tag[tag$programme == programme, , drop = FALSE], "#009E73", tag_labels,
      total_label = paste("Tag total —", programme),
      parent_component = "Tag", panel = paste("Tag programme:", programme)
    ))
  }
}
append_group(profile_viewer_group(
  "penalty", "Penalty components", detail_group("Penalty"), "#6B7280",
  total_label = "Penalty total", parent_component = "Penalty", panel = "Penalty components"
))
groups <- Filter(Negate(is.null), groups)

viewer_payload <- list(
  title = "BET 2026 likelihood-profile viewer",
  subtitle = "Diagnostic-model biomass profiles: broad components with expandable data-set detail",
  developer = list(name = "Kyuhan Kim", email = "kyuhank@spc.int"),
  groups = groups
)
template <- paste(readLines(template_file, warn = FALSE), collapse = "\n")
if (sum(gregexpr("__VIEWER_DATA__", template, fixed = TRUE)[[1L]] >= 0L) != 1L ||
    sum(gregexpr("__SPC_LOGO__", template, fixed = TRUE)[[1L]] >= 0L) != 1L ||
    sum(gregexpr("__MFCLSHINY_LOGO__", template, fixed = TRUE)[[1L]] >= 0L) != 1L) {
  stop("The viewer template markers are invalid.", call. = FALSE)
}
embedded_svg_uri <- function(file, label) {
  if (!nzchar(file) || !file.exists(file)) stop(label, " logo asset is unavailable.", call. = FALSE)
  svg <- paste(readLines(file, warn = FALSE), collapse = "\n")
  if (!nzchar(svg)) stop(label, " logo asset is empty.", call. = FALSE)
  paste0("data:image/svg+xml;charset=utf-8,", utils::URLencode(svg, reserved = TRUE))
}
logo_uri <- embedded_svg_uri(
  system.file("app", "www", "spc-logo.svg", package = "mfclshiny"), "The SPC"
)
mfclshiny_logo_uri <- embedded_svg_uri(
  system.file("app", "www", "mfclshiny-logo.svg", package = "mfclshiny"), "The mfclshiny"
)
viewer_json <- jsonlite::toJSON(viewer_payload, auto_unbox = TRUE, dataframe = "rows", digits = 10, na = "null")
viewer_json <- gsub("</", "<\\/", viewer_json, fixed = TRUE)
viewer_html <- sub("__SPC_LOGO__", logo_uri, template, fixed = TRUE)
viewer_html <- sub("__MFCLSHINY_LOGO__", mfclshiny_logo_uri, viewer_html, fixed = TRUE)
viewer_html <- sub("__VIEWER_DATA__", viewer_json, viewer_html, fixed = TRUE)
viewer_file <- file.path(output_dir, "bet-2026-likelihood-profile-viewer.html")
writeLines(viewer_html, viewer_file, useBytes = TRUE)

message("Wrote self-contained likelihood-profile viewer: ", viewer_file)
