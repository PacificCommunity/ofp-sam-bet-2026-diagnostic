#!/usr/bin/env Rscript

# Build the compact, public report payload from completed Kflow check archives.
# The output contains numeric summaries only: no raw model files, scheduler
# paths, log files, executable paths, or authentication material are retained.

options(stringsAsFactors = FALSE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L) {
  stop(
    paste(
      "Usage: prepare_public_payload.R REPO_ROOT EXTRACTED_JOB_ROOT OUTPUT_RDS",
      "where EXTRACTED_JOB_ROOT contains job-021747, job-022020,",
      "job-022028, job-022062, job-022072, job-023026 and job-023102."
    ),
    call. = FALSE
  )
}

repo_root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
source_root <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
output_file <- normalizePath(args[[3L]], winslash = "/", mustWork = FALSE)
dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

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
read_csv <- function(path) {
  if (!file.exists(path)) stop("Missing required table: ", path, call. = FALSE)
  utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
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
relative_path <- function(path, root) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  root <- sub("/+$", "", normalizePath(root, winslash = "/", mustWork = TRUE))
  sub(paste0("^", gsub("([][{}()+*^$|\\?.])", "\\\\\\1", root), "/?"), "", path)
}
sha256 <- function(path) {
  value <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  if (!length(value)) return(NA_character_)
  strsplit(value[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

model_key <- "S0.90-F2-tau2-fixed"
job_dir <- function(job) file.path(source_root, sprintf("job-%06d", as.integer(job)))
model_dir <- function(job) file.path(job_dir(job), "outputs", "models", model_key)

jobs <- c(
  model_payload = 21747L,
  hessian = 22020L,
  retrospective = 22028L,
  jitter = 22062L,
  likelihood_profile = 22072L,
  self_test = 23026L,
  aspm = 23102L
)
missing_jobs <- names(jobs)[!dir.exists(vapply(jobs, job_dir, character(1L)))]
if (length(missing_jobs)) {
  stop("Missing extracted job archive(s): ", paste(missing_jobs, collapse = ", "), call. = FALSE)
}

model_payload_dir <- file.path(model_dir(jobs[["model_payload"]]))
payload_file <- file.path(model_payload_dir, "model_payload.rds")
payload <- get("mfclshiny_diagnostic_payload", asNamespace("mfclshiny"))(
  model_payload_dir,
  roles = c("ParOut", "RepOut", "TagRepOut", "TagTempOut", "LengOut", "TagOut", "AgeOut", "AgeFitOut", "IndepOut")
)
model_tables <- get("mfclshiny_diagnostic_model_tables", asNamespace("mfclshiny"))(
  payload,
  model_payload_dir,
  model_job = "22974",
  recent_years = 4L
)

fit_summary <- read_csv(file.path(repo_root, "results", "reference", "fit-summary.csv"))
run_summary <- read_csv(file.path(repo_root, "results", "reference", "run-summary.csv"))
annual_uncertainty <- read_csv(file.path(
  repo_root, "results", "reference", "uncertainty", "annual-hessian-time-series.csv"
))
quarterly_uncertainty <- read_csv(file.path(
  repo_root, "results", "reference", "uncertainty", "quarterly-hessian-time-series.csv"
))
hessian_info <- readRDS(file.path(repo_root, "results", "reference", "hessian", "hessian_info.rds"))
private_method_prefix <- paste0("^native", "[[:space:]]+MFCL")
annual_uncertainty$method <- sub(private_method_prefix, "MFCL", annual_uncertainty$method)
quarterly_uncertainty$method <- sub(private_method_prefix, "MFCL", quarterly_uncertainty$method)
hessian_summary_fields <- c(
  "requested", "attempted", "run_ok", "is_pdh", "hessian_ok",
  "n_negative_eigenvalues", "n_total_eigenvalues", "smallest_eigenvalue",
  "largest_eigenvalue", "smallest_positive_eigenvalue",
  "relative_negative_curvature", "positive_condition_number",
  "hessian_status", "reliability", "n_nonpositive_eigenvalues",
  "n_strictly_negative_eigenvalues", "n_zero_eigenvalues",
  "n_positive_eigenvalues", "eigenvalue_counts_status"
)
hessian_public <- list(
  summary = hessian_info$diagnostics$summary[
    intersect(hessian_summary_fields, names(hessian_info$diagnostics$summary))
  ],
  parameter_table = hessian_info$diagnostics$parameter_table
)

read_mapping <- function(path, object) {
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)
  get(object, envir = env, inherits = FALSE)
}
fishery_map <- read_mapping(file.path(repo_root, "model", "fishery_map.R"), "fishery_map")
tag_reporting_groups <- read_mapping(file.path(repo_root, "model", "tag_rep_map.R"), "tag_rep_map")
tag_release_groups <- read_mapping(file.path(repo_root, "model", "tag_rep_map.R"), "tag_release_map")

# Retrospective checks -------------------------------------------------------
retro_root <- file.path(model_dir(jobs[["retrospective"]]), "retro")
retro_files <- list.files(
  retro_root,
  pattern = "retro_metrics[.]rds$",
  recursive = TRUE,
  full.names = TRUE
)
retro <- bind_rows_base(lapply(retro_files, readRDS))
reference_annual <- model_tables$annual
reference_retro <- data.frame(
  year = reference_annual$Year,
  depletion = reference_annual$`Dynamic spawning depletion`,
  spawning_potential = reference_annual$`Spawning potential (1000 t)`,
  recruitment = reference_annual$`Recruitment (millions)`,
  fishing_mortality = reference_annual$`Annual population-weighted F`,
  scenario = "Diagnostic",
  peel = 0L,
  stringsAsFactors = FALSE
)
retro <- bind_rows_base(list(reference_retro, retro))
retro_summary <- read_csv(file.path(retro_root, "check-summary.csv"))

mohn_rho <- function(metric) {
  peels <- sort(unique(retro$peel[retro$peel > 0]))
  value <- vapply(peels, function(peel) {
    terminal <- max(retro$year[retro$peel == peel], na.rm = TRUE)
    estimate <- retro[retro$peel == peel & retro$year == terminal, metric]
    reference <- retro[retro$peel == 0 & retro$year == terminal, metric]
    if (!length(estimate) || !length(reference) || !is.finite(reference[[1L]]) || reference[[1L]] == 0) {
      return(NA_real_)
    }
    (estimate[[1L]] - reference[[1L]]) / reference[[1L]]
  }, numeric(1L))
  mean(value, na.rm = TRUE)
}
retro_rho <- data.frame(
  quantity = c("Dynamic spawning depletion", "Spawning potential", "Recruitment", "Fishing mortality"),
  symbol = c("SB/SB[F=0]", "SB", "R", "F"),
  rho = vapply(
    c("depletion", "spawning_potential", "recruitment", "fishing_mortality"),
    mohn_rho,
    numeric(1L)
  ),
  stringsAsFactors = FALSE
)

# Jitter checks --------------------------------------------------------------
jitter_root <- file.path(model_dir(jobs[["jitter"]]), "jitter")
jitter_files <- list.files(jitter_root, pattern = "jitter_result[.]rds$", recursive = TRUE, full.names = TRUE)
jitter_objects <- lapply(jitter_files, readRDS)
jitter_runs <- bind_rows_base(lapply(jitter_objects, function(x) {
  data.frame(
    seed = as.integer(first_value(x$seed)),
    objective = as.numeric(first_value(x$obj_fun)),
    objective_delta = as.numeric(first_value(x$obj_fun)) - fit_summary$objective[[1L]],
    max_gradient = as.numeric(first_value(x$max_grad)),
    completed = isTRUE(first_value(x$run_completed, FALSE)),
    converged = isTRUE(first_value(x$converged, FALSE)),
    hessian_pdh = isTRUE(first_value(x$hessian_ok, FALSE)),
    stringsAsFactors = FALSE
  )
}))
jitter_runs$status <- ifelse(
  !jitter_runs$completed,
  "Not completed",
  ifelse(jitter_runs$max_gradient <= 1e-4, "MGC <= 1e-4", "MGC > 1e-4")
)
jitter_derived <- bind_rows_base(lapply(jitter_objects, function(x) x$derived_quantities))
jitter_family <- bind_rows_base(lapply(jitter_objects, function(x) {
  value <- x$fitted_parameter_changes$family_stats
  if (is.data.frame(value) && nrow(value)) value else data.frame()
}))
jitter_summary <- read_csv(file.path(jitter_root, "check-summary.csv"))

# Self-test checks -----------------------------------------------------------
selftest_root <- file.path(model_dir(jobs[["self_test"]]), "selftest")
selftest_runs <- readRDS(file.path(selftest_root, "selftest_runs.rds"))
read_recovery_set <- function(name) {
  files <- list.files(
    file.path(selftest_root, "recovery"),
    pattern = paste0("^", name, "[.]csv$"),
    recursive = TRUE,
    full.names = TRUE
  )
  bind_rows_base(lapply(files, function(path) {
    value <- read_csv(path)
    value$replicate <- as.integer(sub("rep_([0-9]+).*", "\\1", basename(dirname(path))))
    value
  }))
}
selftest_derived <- read_recovery_set("derived_recovery")
selftest_management <- read_recovery_set("management_recovery")
selftest_parameters <- read_recovery_set("profile_parameter_recovery")
selftest_summary <- read_csv(file.path(selftest_root, "check-summary.csv"))

# ASPM checks ----------------------------------------------------------------
aspm_root <- file.path(model_dir(jobs[["aspm"]]), "aspm")
aspm_variants <- c(constant = "ASPM, constant recruitment", fitted = "ASPM, fitted recruitment")
aspm_annual <- bind_rows_base(lapply(names(aspm_variants), function(variant) {
  folder <- file.path(aspm_root, variant)
  value <- get("mfclshiny_diagnostic_payload", asNamespace("mfclshiny"))(
    folder,
    roles = c("ParOut", "RepOut", "TagRepOut")
  )
  tables <- get("mfclshiny_diagnostic_model_tables", asNamespace("mfclshiny"))(
    value,
    folder,
    model_job = "23102",
    recent_years = 4L
  )
  out <- tables$annual
  out$model <- unname(aspm_variants[[variant]])
  out
}))
diagnostic_annual <- reference_annual
diagnostic_annual$model <- "Diagnostic"
aspm_annual <- bind_rows_base(list(diagnostic_annual, aspm_annual))
aspm_info <- bind_rows_base(lapply(names(aspm_variants), function(variant) {
  x <- readRDS(file.path(aspm_root, variant, "aspm_info.rds"))
  data.frame(
    model = unname(aspm_variants[[variant]]),
    objective = as.numeric(first_value(x$obj_fun)),
    max_gradient = as.numeric(first_value(x$max_grad)),
    completed = isTRUE(first_value(x$run_completed, FALSE)),
    converged = isTRUE(first_value(x$converged, FALSE)),
    active_parameters = as.integer(first_value(x$active_parameter_count)),
    recruitment = if (identical(variant, "constant")) "Constant" else "Estimated",
    stringsAsFactors = FALSE
  )
}))
aspm_summary <- read_csv(file.path(aspm_root, "check-summary.csv"))

# Likelihood profile ---------------------------------------------------------
profile_root <- file.path(model_dir(jobs[["likelihood_profile"]]), "profile", "total_average_biomass")
profile_files <- list.files(profile_root, pattern = "profile_payload[.]rds$", recursive = TRUE, full.names = TRUE)

tool_candidates <- c(
  if (nzchar(Sys.getenv("MFCLSHINY_REPO", ""))) file.path(Sys.getenv("MFCLSHINY_REPO"), "inst", "app", "tools", "model_payload.R") else "",
  system.file("app", "tools", "model_payload.R", package = "mfclshiny")
)
tool_candidates <- tool_candidates[nzchar(tool_candidates) & file.exists(tool_candidates)]
if (!length(tool_candidates)) {
  stop("Could not locate mfclshiny model_payload.R helpers.", call. = FALSE)
}
tool_file <- tool_candidates[[1L]]
tool_env <- new.env(parent = globalenv())
sys.source(tool_file, envir = tool_env)
likelihood_module_candidates <- c(
  if (nzchar(Sys.getenv("MFCLSHINY_REPO", ""))) file.path(Sys.getenv("MFCLSHINY_REPO"), "inst", "app", "R", "modules", "mod_likelihood.R") else "",
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
  if (is.list(value)) {
    numbers <- vapply(value, sum_numeric, numeric(1L))
  } else {
    numbers <- suppressWarnings(as.numeric(value))
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

profile_points <- list()
profile_components <- list()
profile_detail <- list()
for (i in seq_along(profile_files)) {
  path <- profile_files[[i]]
  x <- readRDS(path)
  point_dir <- dirname(path)
  output <- file.path(point_dir, "test_plot_output")
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

  if (is.data.frame(component_rows) && nrow(component_rows)) {
    broad <- tool_env$mfclshiny_profile_component_values(
      component_rows,
      total = objective,
      regional_scaling_in_indices = TRUE
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
    slot_detail(likelihood, "total_length_fish", "Length frequency", fishery_map$fishery_name),
    slot_detail(likelihood, "total_weight_fish", "Weight frequency", fishery_map$fishery_name),
    slot_detail(likelihood, "tag_rel_fish", "Tag release group", paste0("Group ", seq_len(98L)))
  ))
  if (is.data.frame(component_rows) && nrow(component_rows)) {
    data_components <- c("Tag", "Length frequency", "Weight frequency", "Age", "CPUE", "Catch")
    penalties <- component_rows[!(component_rows$Component %in% data_components), , drop = FALSE]
    if (nrow(penalties)) {
      penalties <- data.frame(
        detail_group = "Penalty",
        detail = penalties$Component,
        value = penalties$Value,
        stringsAsFactors = FALSE
      )
      detail <- bind_rows_base(list(detail, penalties))
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
profile_summary <- read_csv(file.path(dirname(profile_root), "check-summary.csv"))

# Remove stored scheduler paths and retain only report variables.
selftest_runs <- selftest_runs[, intersect(
  c("rep", "replicate", "seed", "run_completed", "convergence_status", "converged", "obj_fun", "max_grad", "tag_likelihood_family", "tag_likelihood_matched", "tag_contract_status"),
  names(selftest_runs)
), drop = FALSE]

public_payload <- list(
  schema = "bet2026.diagnostic_report.v1",
  data_vintage = "2026-08-07",
  source = list(
    final_diagnostic_job = 22974L,
    jobs = jobs,
    model_key = model_key,
    final_par_sha256 = fit_summary$final_par_sha256[[1L]],
    model_payload_sha256 = sha256(payload_file),
    notes = "Numeric report payload only; raw model outputs and execution paths are excluded."
  ),
  model = list(
    fit_summary = fit_summary,
    run_summary = run_summary,
    summary = model_tables$model_summary,
    objective = model_tables$objective,
    annual = model_tables$annual,
    recent = model_tables$recent,
    annual_uncertainty = annual_uncertainty,
    quarterly_uncertainty = quarterly_uncertainty
  ),
  hessian = hessian_public,
  mappings = list(
    fisheries = fishery_map,
    tag_reporting_groups = tag_reporting_groups,
    tag_release_groups = tag_release_groups
  ),
  retrospective = list(
    summary = retro_summary,
    time_series = retro,
    mohn_rho = retro_rho
  ),
  jitter = list(
    summary = jitter_summary,
    runs = jitter_runs[order(jitter_runs$seed), , drop = FALSE],
    time_series = jitter_derived,
    family_summary = jitter_family
  ),
  self_test = list(
    summary = selftest_summary,
    runs = selftest_runs,
    annual_recovery = selftest_derived,
    management_recovery = selftest_management,
    parameter_recovery = selftest_parameters
  ),
  aspm = list(
    summary = aspm_summary,
    runs = aspm_info,
    annual = aspm_annual
  ),
  likelihood_profile = list(
    summary = profile_summary,
    points = profile_points[order(profile_points$biomass_ratio), , drop = FALSE],
    components = profile_components[order(profile_components$biomass_ratio), , drop = FALSE],
    detail = profile_detail[order(profile_detail$detail_group, profile_detail$detail, profile_detail$biomass_ratio), , drop = FALSE]
  ),
  references = data.frame(
    citation = c(
      "Stock assessment of bigeye tuna in the western and central Pacific Ocean: 2023",
      "Developing a set of diagnostics and outputs for MULTIFAN-CL stock assessments",
      "Natural mortality estimation for WCPO bigeye tuna: a joint cohort analysis of Coral Sea and Region 4 tagging data",
      "Analysis of tag seeding data for the 2026 bigeye and yellowfin assessments: reporting rates for purse seine fleets"
    ),
    symbol = c(
      "WCPFC-SC19-2023-SA-WP05",
      "WCPFC-SC16-2020-MI-IP07",
      "WCPFC-SC22-2026-SA-IP14",
      "WCPFC-SC22-2026-SA-IP05"
    ),
    url = c(
      "https://meetings.wcpfc.int/node/19353",
      "https://meetings.wcpfc.int/node/12181",
      "https://meetings.wcpfc.int/meetings/sc22",
      "https://meetings.wcpfc.int/node/32332"
    ),
    stringsAsFactors = FALSE
  )
)

# Fail before writing if any public field contains a workstation path,
# credential-like text, a personal identifier or private project wording.
audit_pattern <- paste0(
  "/home/|/tmp/|/var/lib/|kyuhank|password|secret|bearer[[:space:]]|native",
  "[[:space:]]+MFCL"
)
audit_public_object <- function(x, field = "root") {
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x)) {
    if (any(grepl(audit_pattern, x, ignore.case = TRUE))) {
      stop("Public payload audit failed at field: ", field, call. = FALSE)
    }
    return(invisible(TRUE))
  }
  if (is.list(x)) {
    child_names <- names(x)
    if (is.null(child_names)) child_names <- as.character(seq_along(x))
    for (i in seq_along(x)) {
      audit_public_object(x[[i]], paste0(field, "$", child_names[[i]]))
    }
  }
  invisible(TRUE)
}
audit_public_object(public_payload)

saveRDS(public_payload, output_file, compress = "xz")
manifest <- data.frame(
  file = basename(output_file),
  bytes = file.info(output_file)$size,
  sha256 = sha256(output_file),
  schema = public_payload$schema,
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest,
  file.path(dirname(output_file), "diagnostic-report-data-manifest.csv"),
  row.names = FALSE
)
writeLines(
  paste(manifest$sha256, manifest$file),
  file.path(dirname(output_file), "SHA256SUMS")
)
message(
  "Wrote compact public Diagnostic report payload: ", output_file,
  " (", format(file.info(output_file)$size, big.mark = ","), " bytes)"
)
