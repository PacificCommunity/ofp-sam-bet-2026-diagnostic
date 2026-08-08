#!/usr/bin/env Rscript

# Refresh only the likelihood-profile section of the compact public payload.
# This is useful when the completed profile/model outputs are available but
# the other diagnostic archives used by prepare_public_payload.R are not.

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) {
  stop(
    "Usage: refresh_likelihood_profile_payload.R REPO_ROOT MODEL_OUTPUT_DIR [OUTPUT_RDS]",
    call. = FALSE
  )
}

repo_root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
model_output_dir <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output_file <- if (length(args) >= 3L) {
  normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
} else {
  file.path(repo_root, "diagnostic-report", "data", "diagnostic-report-data.rds")
}

required_packages <- c("FLR4MFCL", "mfclshiny")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1L), quietly = TRUE)
]
if (length(missing_packages)) {
  stop("Missing required package(s): ", paste(missing_packages, collapse = ", "), call. = FALSE)
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
first_value <- function(x, default = NA) {
  if (is.null(x) || !length(x)) default else x[[1L]]
}
bind_rows_base <- function(rows) {
  rows <- Filter(function(x) is.data.frame(x) && nrow(x), rows)
  if (!length(rows)) return(data.frame())
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(x) {
    for (column in setdiff(columns, names(x))) x[[column]] <- NA
    x[, columns, drop = FALSE]
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
read_mapping <- function(path, object) {
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)
  get(object, envir = env, inherits = FALSE)
}

payload_path <- file.path(repo_root, "diagnostic-report", "data", "diagnostic-report-data.rds")
model_payload_path <- file.path(model_output_dir, "model_payload.rds")
profile_root <- file.path(model_output_dir, "profile", "total_average_biomass")
if (!file.exists(payload_path) || !file.exists(model_payload_path) || !dir.exists(profile_root)) {
  stop("The public payload, model payload or likelihood-profile directory is missing.", call. = FALSE)
}

public_payload <- readRDS(payload_path)
model_payload <- get("mfclshiny_diagnostic_payload", asNamespace("mfclshiny"))(
  model_output_dir, roles = c("AgeOut")
)
if (!identical(public_payload$schema, "bet2026.diagnostic_report.v1")) {
  stop("Unsupported compact public-payload schema.", call. = FALSE)
}
if (is.null(model_payload$data$AgeOut)) {
  stop("The model payload does not contain AgeOut.", call. = FALSE)
}

fishery_map <- read_mapping(file.path(repo_root, "model", "fishery_map.R"), "fishery_map")

age_profile_records <- function(age_out, fishery_map) {
  if (!("ALK" %in% methods::slotNames(age_out))) {
    stop("The model payload does not contain age-at-length records.", call. = FALSE)
  }
  alk <- methods::slot(age_out, "ALK")
  key <- c("year", "month", "fishery")
  if (!all(key %in% names(alk))) {
    stop("Age-at-length records are missing year, month or fishery identifiers.", call. = FALSE)
  }
  records <- alk[!duplicated(alk[, key, drop = FALSE]), key, drop = FALSE]
  records$fishery <- as.integer(records$fishery)
  records$region <- fishery_map$region[match(records$fishery, fishery_map$fishery)]
  if (!nrow(records) || any(!is.finite(records$region))) {
    stop("Could not map every age-at-length record to a model region.", call. = FALSE)
  }
  records
}
age_records <- age_profile_records(model_payload$data$AgeOut, fishery_map)

tool_candidates <- c(
  if (nzchar(Sys.getenv("MFCLSHINY_REPO", ""))) {
    file.path(Sys.getenv("MFCLSHINY_REPO"), "inst", "app", "tools", "model_payload.R")
  } else "",
  system.file("app", "tools", "model_payload.R", package = "mfclshiny")
)
tool_candidates <- tool_candidates[nzchar(tool_candidates) & file.exists(tool_candidates)]
if (!length(tool_candidates)) {
  stop("Could not locate mfclshiny model_payload.R helpers.", call. = FALSE)
}
tool_env <- new.env(parent = globalenv())
sys.source(tool_candidates[[1L]], envir = tool_env)

likelihood_module_candidates <- c(
  if (nzchar(Sys.getenv("MFCLSHINY_REPO", ""))) {
    file.path(Sys.getenv("MFCLSHINY_REPO"), "inst", "app", "R", "modules", "mod_likelihood.R")
  } else "",
  system.file("app", "R", "modules", "mod_likelihood.R", package = "mfclshiny")
)
likelihood_module_candidates <- likelihood_module_candidates[
  nzchar(likelihood_module_candidates) & file.exists(likelihood_module_candidates)
]
if (!length(likelihood_module_candidates)) {
  stop("Could not locate mfclshiny likelihood-profile helpers.", call. = FALSE)
}
sys.source(likelihood_module_candidates[[1L]], envir = tool_env)

sum_numeric <- function(x) {
  if (is.null(x)) return(NA_real_)
  values <- suppressWarnings(as.numeric(unlist(x, recursive = TRUE, use.names = FALSE)))
  values <- values[is.finite(values)]
  if (length(values)) sum(values) else NA_real_
}
slot_detail <- function(likelihood, slot_name, component, labels = NULL) {
  if (is.null(likelihood) || !(slot_name %in% methods::slotNames(likelihood))) return(data.frame())
  value <- methods::slot(likelihood, slot_name)
  numbers <- if (is.list(value)) {
    vapply(value, sum_numeric, numeric(1L))
  } else {
    suppressWarnings(as.numeric(value))
  }
  if (!length(numbers)) return(data.frame())
  if (is.null(labels) || length(labels) != length(numbers)) labels <- seq_along(numbers)
  data.frame(
    detail_group = component,
    detail = as.character(labels),
    value = numbers,
    stringsAsFactors = FALSE
  )
}
age_profile_detail <- function(likelihood, records, fishery_map, expected_age) {
  if (is.null(likelihood) || !("age_length" %in% methods::slotNames(likelihood))) return(data.frame())
  values <- suppressWarnings(as.numeric(methods::slot(likelihood, "age_length")))
  if (length(values) != nrow(records) || any(!is.finite(values))) {
    stop("Age-at-length likelihood values do not align with the observed-record map.", call. = FALSE)
  }
  region_totals <- vapply(
    seq_len(5L), function(region) sum(values[records$region == region]), numeric(1L)
  )
  tolerance <- 1e-6 * max(1, abs(expected_age))
  if (!is.finite(expected_age) || abs(sum(region_totals) - expected_age) > tolerance) {
    stop("Regional age-at-length likelihood does not close to the broad CAAL component.", call. = FALSE)
  }
  fishery_ids <- sort(unique(records$fishery))
  fishery_totals <- vapply(
    fishery_ids, function(fishery) sum(values[records$fishery == fishery]), numeric(1L)
  )
  if (abs(sum(fishery_totals) - expected_age) > tolerance) {
    stop("Fishery age-at-length likelihood does not close to the broad CAAL component.", call. = FALSE)
  }
  fishery_names <- fishery_map$fishery_name[match(fishery_ids, fishery_map$fishery)]
  bind_rows_base(list(
    data.frame(
      detail_group = "CAAL region",
      detail = paste("Region", seq_len(5L)),
      value = region_totals,
      stringsAsFactors = FALSE
    ),
    data.frame(
      detail_group = "CAAL fishery",
      detail = sprintf("F%02d | %s", fishery_ids, fishery_names),
      value = fishery_totals,
      stringsAsFactors = FALSE
    )
  ))
}

profile_files <- list.files(
  profile_root, pattern = "profile_payload[.]rds$", recursive = TRUE, full.names = TRUE
)
if (!length(profile_files)) stop("No likelihood-profile payloads were found.", call. = FALSE)

profile_points <- list()
profile_components <- list()
profile_detail <- list()
for (i in seq_along(profile_files)) {
  path <- profile_files[[i]]
  x <- readRDS(path)
  output <- file.path(dirname(path), "test_plot_output")
  likelihood <- if (file.exists(output)) {
    tryCatch(FLR4MFCL::read.MFCLLikelihood(output), error = function(e) NULL)
  } else {
    NULL
  }
  raw_lines <- x$lik_raw %||% if (file.exists(output)) readLines(output, warn = FALSE) else character()
  raw_rows <- tryCatch(
    tool_env$mp_likelihood_raw_component_rows_from_lines(raw_lines),
    error = function(e) NULL
  )
  slot_rows <- tryCatch(tool_env$mp_likelihood_component_rows(likelihood), error = function(e) NULL)
  component_rows <- tool_env$mp_authoritative_likelihood_component_rows(slot_rows, raw_rows)

  scalar <- as.numeric(first_value(x$scalar))
  actual <- as.numeric(first_value(x$actual_quantity))
  reference <- as.numeric(first_value(x$reference_quantity))
  objective <- as.numeric(first_value(x$obj_fun))
  profile_points[[i]] <- data.frame(
    scalar = scalar,
    biomass_ratio = actual / reference,
    total_average_biomass_1000_t = actual / 1000,
    objective = objective,
    max_gradient = as.numeric(first_value(x$max_grad)),
    point_valid = isTRUE(first_value(x$mfclkit$point_valid, FALSE)),
    chain_side = as.character(first_value(x$mfclkit$chain_side, "anchor")),
    stringsAsFactors = FALSE
  )

  broad <- NULL
  if (is.data.frame(component_rows) && nrow(component_rows)) {
    broad <- tool_env$mfclshiny_profile_component_values(
      component_rows, total = objective, regional_scaling_in_indices = TRUE
    )
    profile_components[[i]] <- data.frame(
      scalar = scalar,
      biomass_ratio = actual / reference,
      component = names(broad),
      value = as.numeric(broad),
      stringsAsFactors = FALSE
    )
  }

  detail <- bind_rows_base(list(
    slot_detail(likelihood, "survey_index", "CPUE index", fishery_map$fishery_name),
    slot_detail(likelihood, "total_length_fish", "LF", fishery_map$fishery_name),
    slot_detail(likelihood, "total_weight_fish", "Weight frequency", fishery_map$fishery_name),
    slot_detail(likelihood, "tag_rel_fish", "Tag release group", paste0("Group ", seq_len(98L))),
    if (!is.null(broad) && "Age" %in% names(broad)) {
      age_profile_detail(likelihood, age_records, fishery_map, as.numeric(broad[["Age"]]))
    } else data.frame()
  ))
  if (is.data.frame(component_rows) && nrow(component_rows)) {
    data_components <- c("Tag", "Length frequency", "Weight frequency", "Age", "CPUE", "Catch")
    penalties <- component_rows[!(component_rows$Component %in% data_components), , drop = FALSE]
    if (nrow(penalties)) {
      detail <- bind_rows_base(list(detail, data.frame(
        detail_group = "Penalty",
        detail = penalties$Component,
        value = penalties$Value,
        stringsAsFactors = FALSE
      )))
    }
  }
  if (nrow(detail)) {
    detail$scalar <- scalar
    detail$biomass_ratio <- actual / reference
    profile_detail[[i]] <- detail
  }
}

profile_points <- bind_rows_base(profile_points)
profile_components <- bind_rows_base(profile_components)
profile_detail <- bind_rows_base(profile_detail)
if (!nrow(profile_points) || !nrow(profile_components) || !nrow(profile_detail)) {
  stop("The likelihood-profile refresh produced incomplete tables.", call. = FALSE)
}

public_payload$likelihood_profile$points <-
  profile_points[order(profile_points$biomass_ratio), , drop = FALSE]
public_payload$likelihood_profile$components <-
  profile_components[order(profile_components$biomass_ratio), , drop = FALSE]
public_payload$likelihood_profile$detail <- profile_detail[
  order(profile_detail$detail_group, profile_detail$detail, profile_detail$biomass_ratio),
  , drop = FALSE
]
public_payload$mappings$fisheries <- fishery_map

dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
saveRDS(public_payload, output_file, compress = "xz")
cat(
  sprintf(
    "Refreshed %d profile points, %d broad-component rows and %d detail rows in %s\n",
    nrow(profile_points), nrow(profile_components), nrow(profile_detail), output_file
  )
)
