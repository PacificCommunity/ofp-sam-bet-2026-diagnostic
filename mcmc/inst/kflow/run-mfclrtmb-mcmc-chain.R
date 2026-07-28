#!/usr/bin/env Rscript

options(warn = 1)
suppressPackageStartupMessages(library(mfclrtmb))

env_integer <- function(name, default) {
  value <- suppressWarnings(as.integer(Sys.getenv(name, as.character(default))))
  if (length(value) != 1L || !is.finite(value) || value < 1L) {
    stop(name, " must be a positive integer", call. = FALSE)
  }
  value
}

env_number <- function(name, default) {
  value <- suppressWarnings(as.numeric(Sys.getenv(name, as.character(default))))
  if (length(value) != 1L || !is.finite(value)) {
    stop(name, " must be a finite number", call. = FALSE)
  }
  value
}

input_root <- Sys.getenv(
  "KFLOW_INPUT_ROOT",
  Sys.getenv("KFLOW_INPUT_DIR", file.path(dirname(getwd()), "inputs"))
)
work_root <- Sys.getenv("KFLOW_WORK_ROOT", file.path(getwd(), "work"))
output_root <- Sys.getenv("KFLOW_OUTPUT_ROOT", file.path(getwd(), "outputs"))
source_job <- trimws(Sys.getenv("MCMC_SOURCE_JOB", ""))
if (!nzchar(source_job)) {
  stop("MCMC_SOURCE_JOB is required", call. = FALSE)
}
source_key <- gsub("[^[:alnum:]_.-]+", "-", source_job)
model_selector <- trimws(Sys.getenv("MCMC_MODEL_SELECTOR", ""))
requested_root <- trimws(Sys.getenv("MCMC_ROOT", ""))
objective_tolerance <- env_number("MCMC_OBJECTIVE_TOLERANCE", 1e-4)
if (objective_tolerance <= 0) {
  stop("MCMC_OBJECTIVE_TOLERANCE must be positive", call. = FALSE)
}
log_prefix <- paste0("[mfclrtmb-mcmc source-job=", source_job, "]")
preconditioner <- match.arg(
  tolower(trimws(Sys.getenv("MCMC_PRECONDITIONER", "adaptive"))),
  c("adaptive", "native")
)

chain_id <- env_integer("MCMC_CHAIN_ID", 1L)
total_chains <- env_integer("MCMC_TOTAL_CHAINS", 10L)
if (chain_id > total_chains) {
  stop("MCMC_CHAIN_ID cannot exceed MCMC_TOTAL_CHAINS", call. = FALSE)
}
chain_key <- sprintf("chain-%02d", chain_id)
result_dir <- file.path(
  output_root,
  paste0("source-job-", source_key, "-mfclrtmb-mcmc"),
  chain_key
)
case_dir <- file.path(
  work_root,
  paste0("source-job-", source_key, "-case-", chain_key)
)
fit_dir <- file.path(result_dir, "fit")
mcmc_dir <- file.path(result_dir, "mcmc")
posterior_dir <- file.path(result_dir, "posterior")
figure_dir <- file.path(result_dir, "figures")
diagnostic_dir <- file.path(result_dir, "diagnostics")

for (path in c(
  result_dir, case_dir, fit_dir, mcmc_dir, posterior_dir, figure_dir,
  diagnostic_dir
)) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

chains <- 1L
cores <- 1L
warmup <- env_integer("MCMC_WARMUP", 100L)
samples <- env_integer("MCMC_SAMPLES", 20L)
base_seed <- env_integer("MCMC_SEED", 20260728L)
seed <- base_seed + chain_id - 1L
max_treedepth <- env_integer("MCMC_MAX_TREEDEPTH", 10L)
adapt_delta <- env_number("MCMC_ADAPT_DELTA", 0.9)
if (adapt_delta <= 0 || adapt_delta >= 1) {
  stop("MCMC_ADAPT_DELTA must be between zero and one", call. = FALSE)
}

sha256_file <- function(path) {
  output <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) {
    stop("sha256sum failed for ", path, call. = FALSE)
  }
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

payload_par_bytes <- function(payload) {
  record <- tryCatch(payload$artifacts$files$par, error = function(e) NULL)
  if (!is.list(record) || !is.raw(record$bytes)) {
    return(NULL)
  }
  value <- record$bytes
  compression <- as.character(
    if (!is.null(record$compression)) record$compression else "none"
  )[[1L]]
  if (!identical(compression, "none")) {
    value <- tryCatch(memDecompress(value, type = compression), error = function(e) NULL)
  }
  value
}

sha256_raw <- function(value) {
  path <- tempfile("mfclrtmb-payload-par-")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  con <- file(path, open = "wb")
  writeBin(value, con)
  close(con)
  sha256_file(path)
}

payload_candidates <- list.files(
  input_root,
  pattern = "^model_payload[.]rds$",
  recursive = TRUE,
  full.names = TRUE
)
if (!length(payload_candidates)) {
  stop("No model_payload.rds was found in the Kflow inputs", call. = FALSE)
}

payloads <- lapply(payload_candidates, function(path) {
  value <- tryCatch(readRDS(path), error = function(e) NULL)
  par_bytes <- if (is.list(value)) payload_par_bytes(value) else NULL
  objective <- suppressWarnings(as.numeric(
    if (is.list(value) && !is.null(value$obj_fun)) value$obj_fun else NA_real_
  ))
  list(
    path = path,
    value = value,
    par_bytes = par_bytes,
    par_sha256 = if (is.raw(par_bytes)) sha256_raw(par_bytes) else NA_character_,
    objective = objective,
    raw_input_dir = file.path(dirname(path), "mfcl-inputs")
  )
})
valid_payload <- vapply(payloads, function(item) {
  is.list(item$value) &&
    is.raw(item$par_bytes) &&
    length(item$objective) == 1L &&
    is.finite(item$objective) &&
    dir.exists(item$raw_input_dir)
}, logical(1L))
payloads <- payloads[valid_payload]
if (nzchar(model_selector)) {
  payloads <- payloads[vapply(
    payloads,
    function(item) grepl(model_selector, item$path, fixed = TRUE),
    logical(1L)
  )]
}
if (!length(payloads)) {
  stop(
    "No usable model payload matched MCMC_MODEL_SELECTOR='",
    model_selector,
    "'",
    call. = FALSE
  )
}

# A diagnostic archive may repeat the source model. Collapse exact copies by
# final-PAR checksum and objective, but reject genuinely different fits.
payload_signature <- vapply(payloads, function(item) {
  paste(
    item$par_sha256,
    format(item$objective, digits = 17L, scientific = FALSE),
    sep = "::"
  )
}, character(1L))
unique_signature <- unique(payload_signature)
if (length(unique_signature) != 1L) {
  stop(
    "Kflow inputs contain ",
    length(unique_signature),
    " distinct fitted models; set MCMC_MODEL_SELECTOR to select one",
    call. = FALSE
  )
}
payload_item <- payloads[[which(payload_signature == unique_signature)[[1L]]]]
payload_file <- payload_item$path
payload <- payload_item$value
raw_input_dir <- payload_item$raw_input_dir

frq_files <- list.files(
  raw_input_dir,
  pattern = "[.]frq$",
  full.names = FALSE
)
if (nzchar(requested_root)) {
  frq_files <- frq_files[frq_files == paste0(requested_root, ".frq")]
}
if (length(frq_files) != 1L) {
  stop(
    "Expected exactly one model .frq file",
    if (nzchar(requested_root)) {
      paste0(" for MCMC_ROOT='", requested_root, "'")
    } else {
      ""
    },
    "; found ",
    length(frq_files),
    call. = FALSE
  )
}
root_name <- sub("[.]frq$", "", frq_files[[1L]])

candidate_inputs <- paste0(
  root_name,
  c(".frq", ".ini", ".tag", ".age_length", ".reg_scaling")
)
input_names <- candidate_inputs[
  file.exists(file.path(raw_input_dir, candidate_inputs))
]
for (name in input_names) {
  source <- file.path(raw_input_dir, name)
  if (!file.copy(source, file.path(case_dir, name), overwrite = TRUE)) {
    stop("Could not copy source input ", name, call. = FALSE)
  }
}
required_inputs <- paste0(root_name, c(".frq", ".ini"))
missing_inputs <- required_inputs[
  !file.exists(file.path(case_dir, required_inputs))
]
if (length(missing_inputs)) {
  stop(
    "Missing required model inputs: ",
    paste(missing_inputs, collapse = ", "),
    call. = FALSE
  )
}

par_bytes <- payload_item$par_bytes
final_par <- file.path(case_dir, "final.par")
con <- file(final_par, open = "wb")
writeBin(par_bytes, con)
close(con)

actual_par_sha <- sha256_file(final_par)
if (!identical(actual_par_sha, payload_item$par_sha256)) {
  stop(
    "Embedded final PAR checksum changed while staging: ",
    actual_par_sha,
    call. = FALSE
  )
}

manifest_files <- c(input_names, "final.par")
input_manifest <- data.frame(
  source_job = source_job,
  source_payload = payload_file,
  model_selector = model_selector,
  model_root = root_name,
  file = manifest_files,
  sha256 = vapply(
    file.path(case_dir, manifest_files),
    sha256_file,
    character(1L)
  ),
  bytes = as.numeric(file.info(
    file.path(case_dir, manifest_files)
  )$size),
  stringsAsFactors = FALSE
)
utils::write.csv(
  input_manifest,
  file.path(result_dir, "source-input-manifest.csv"),
  row.names = FALSE
)

settings <- data.frame(
  source_job = source_job,
  model_selector = model_selector,
  model_root = root_name,
  sampler = "SparseNUTS",
  metric = if (preconditioner == "native") {
    "native_hessian_dense"
  } else {
    "adaptive_diagonal"
  },
  preconditioner = preconditioner,
  chain_id = chain_id,
  total_chains = total_chains,
  chains = chains,
  cores = cores,
  warmup_per_chain = warmup,
  post_warmup_per_chain = samples,
  expected_post_warmup_draws = samples,
  adapt_delta = adapt_delta,
  max_treedepth = max_treedepth,
  seed = seed,
  init = "last.par.best",
  openmp_threads = 1L,
  stringsAsFactors = FALSE
)
utils::write.csv(
  settings,
  file.path(result_dir, "mcmc-run-settings.csv"),
  row.names = FALSE
)

started_at <- Sys.time()
message(log_prefix, " Building the exact source objective")
fit <- mfclrtmb_fit(
  case_dir = case_dir,
  root = root_name,
  par = final_par,
  output_dir = fit_dir,
  run_optimization = FALSE,
  write_outputs = FALSE,
  write_payload = FALSE,
  write_mfcl_files = FALSE,
  copy_inputs = FALSE,
  build_report = FALSE,
  exact_report = FALSE,
  run_sdreport = FALSE,
  openmp_threads = 1L,
  openmp_autopar = FALSE,
  verbose = TRUE
)

n_parameters <- length(fit$par)
native_objective <- payload_item$objective
if (abs(fit$objective - native_objective) > objective_tolerance) {
  stop(
    "mfclrtmb objective is ",
    format(fit$objective, digits = 16L),
    ", native payload objective is ",
    format(native_objective, digits = 16L),
    ", exceeding tolerance ",
    objective_tolerance,
    call. = FALSE
  )
}

parity <- data.frame(
  source_job = source_job,
  model_selector = model_selector,
  model_root = root_name,
  native_objective = native_objective,
  mfclrtmb_objective = fit$objective,
  difference = fit$objective - native_objective,
  relative_difference =
    (fit$objective - native_objective) / native_objective,
  objective_tolerance = objective_tolerance,
  n_parameters = n_parameters,
  mfclrtmb_max_gradient = fit$max_gradient,
  final_par_sha256 = actual_par_sha,
  passed = TRUE,
  stringsAsFactors = FALSE
)
utils::write.csv(
  parity,
  file.path(result_dir, "mfcl-mfclrtmb-parity.csv"),
  row.names = FALSE
)

native_covariance <- NULL
if (identical(preconditioner, "native")) {
  message(log_prefix, " Loading and exactly mapping the native MFCL Hessian")
  hes_header <- getFromNamespace(".mfclrtmb_hes_header", "mfclrtmb")
  hes_candidates <- list.files(
    input_root,
    pattern = "[.]hes$",
    recursive = TRUE,
    full.names = TRUE
  )
  hes_candidates <- hes_candidates[
    basename(hes_candidates) == paste0(root_name, ".hes")
  ]
  hes_headers <- lapply(hes_candidates, function(path) {
    tryCatch(hes_header(path), error = function(e) NULL)
  })
  full_hes <- hes_candidates[vapply(
    hes_headers,
    function(value) {
      is.list(value) &&
        isTRUE(value$full) &&
        identical(as.integer(value$npar), n_parameters)
    },
    logical(1L)
  )]
  if (length(full_hes) != 1L) {
    stop(
      "Expected exactly one full ",
      n_parameters,
      " x ",
      n_parameters,
      " native ",
      root_name,
      ".hes input; found ",
      length(full_hes),
      call. = FALSE
    )
  }

  hessian_dir <- dirname(full_hes[[1L]])
  hessian_final_par <- file.path(hessian_dir, "final.par")
  hessian_info_file <- file.path(hessian_dir, "hessian_info.rds")
  native_indepvar_file <- file.path(hessian_dir, "indepvar.rpt")
  native_xinit_file <- file.path(hessian_dir, "xinit.rpt")
  required_hessian_files <- c(
    final_par = hessian_final_par
  )
  missing_hessian_files <- required_hessian_files[
    !file.exists(required_hessian_files)
  ]
  if (length(missing_hessian_files)) {
    stop(
      "Native Hessian bundle is missing: ",
      paste(names(missing_hessian_files), collapse = ", "),
      call. = FALSE
    )
  }
  if (!file.exists(native_indepvar_file) &&
      !file.exists(native_xinit_file)) {
    stop(
      "Native Hessian bundle requires indepvar.rpt or xinit.rpt for exact ",
      "model-specific parameter order",
      call. = FALSE
    )
  }
  if (!identical(sha256_file(hessian_final_par), actual_par_sha)) {
    stop(
      "Native Hessian final PAR does not match the selected source model",
      call. = FALSE
    )
  }

  imported_hessian <- mfclrtmb_import_native_hessian(
    fit,
    hessian = full_hes[[1L]],
    hessian_info = if (file.exists(hessian_info_file)) {
      hessian_info_file
    } else {
      NULL
    },
    native_final_par = hessian_final_par,
    source_par = final_par,
    indepvar = if (file.exists(native_indepvar_file)) {
      native_indepvar_file
    } else {
      NULL
    },
    xinit = if (file.exists(native_xinit_file)) {
      native_xinit_file
    } else {
      NULL
    },
    require_order_manifest = TRUE,
    require_pdh = TRUE,
    check_final_par = TRUE
  )
  rtmb_hessian <- imported_hessian$hessian
  hessian_chol <- chol(rtmb_hessian)
  native_covariance <- chol2inv(hessian_chol)
  if (!all(is.finite(native_covariance)) ||
      any(diag(native_covariance) <= 0)) {
    stop("Native Hessian inverse is invalid", call. = FALSE)
  }

  utils::write.csv(
    imported_hessian$map,
    file.path(diagnostic_dir, "native-hessian-parameter-map.csv"),
    row.names = FALSE
  )
  hessian_info <- if (file.exists(hessian_info_file)) {
    readRDS(hessian_info_file)
  } else {
    NULL
  }
  hessian_summary <- data.frame(
    source_file = full_hes[[1L]],
    n_parameters = nrow(rtmb_hessian),
    native_order_source =
      imported_hessian$checks$native_order_source,
    complete_permutation =
      imported_hessian$checks$complete_permutation,
    exact_semantic_labels =
      imported_hessian$checks$exact_semantic_labels,
    hessian_info_cross_check =
      imported_hessian$checks$hessian_info_cross_check,
    status = imported_hessian$checks$native_hessian_status,
    negative_eigenvalues = if (is.null(hessian_info)) {
      NA_integer_
    } else {
      hessian_info$eigen$n_negative_eigenvalues
    },
    zero_eigenvalues = if (is.null(hessian_info)) {
      NA_integer_
    } else {
      hessian_info$eigen$n_zero_eigenvalues
    },
    minimum_eigenvalue = if (is.null(hessian_info)) {
      NA_real_
    } else {
      hessian_info$eigen$minimum_eigenvalue
    },
    maximum_eigenvalue = if (is.null(hessian_info)) {
      NA_real_
    } else {
      hessian_info$eigen$maximum_eigenvalue
    },
    condition_number = if (is.null(hessian_info)) {
      NA_real_
    } else {
      hessian_info$eigen$positive_condition_number
    },
    native_symmetry_error =
      imported_hessian$checks$symmetry_error,
    mapped_estimate_max_abs_error =
      imported_hessian$checks$transformed_estimate_error,
    final_par_match =
      imported_hessian$checks$final_par_match,
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    hessian_summary,
    file.path(diagnostic_dir, "native-hessian-preconditioner.csv"),
    row.names = FALSE
  )
} else {
  message(
    log_prefix,
    " Using standalone adaptive diagonal SparseNUTS geometry"
  )
}

message(sprintf(
  paste0(
    log_prefix,
    " Sampling %d chain with %d warmup and %d ",
    "post-warmup draws per chain (adapt_delta=%.2f)"
  ),
  chains, warmup, samples, adapt_delta
))

snuts <- mfclrtmb_snuts(
  fit,
  num_samples = samples,
  num_warmup = warmup,
  chains = chains,
  cores = cores,
  parallel_chains = cores > 1L,
  thin = 1L,
  seed = seed,
  metric = if (identical(preconditioner, "native")) "dense" else "diag",
  adapt_stan_metric = !identical(preconditioner, "native"),
  adapt_delta = adapt_delta,
  max_treedepth = max_treedepth,
  init = "last.par.best",
  laplace = FALSE,
  skip_optimization = TRUE,
  skip_cor = TRUE,
  skip_monitor = samples < 2L,
  globals = NULL,
  refresh = 10L,
  print = TRUE,
  max_report_draws = chains * samples,
  postprocess = FALSE,
  verbose = TRUE,
  output_dir = mcmc_dir,
  save = TRUE,
  snuts_args = if (identical(preconditioner, "native")) {
    list(Qinv = native_covariance)
  } else {
    list()
  }
)

# The native Qinv is identical for every chain and can be reconstructed exactly
# from the compact Hessian plus the saved parameter map. Keep all chain-specific
# warmup, sampler, timing, initial-value and draw state, but do not duplicate a
# roughly npar^2 dense matrix in every chain archive.
if (identical(preconditioner, "native") &&
    is.list(snuts$snuts_fit$mle) &&
    !is.null(snuts$snuts_fit$mle$Qinv)) {
  snuts$snuts_fit$mle$Qinv <- NULL
  snuts_fit_file <- file.path(mcmc_dir, "snuts-fit.rds")
  if (file.exists(snuts_fit_file)) {
    saveRDS(snuts$snuts_fit, snuts_fit_file)
  }
}

draws <- snuts$draws
expected_draws <- chains * samples
if (!is.matrix(draws) ||
    nrow(draws) != expected_draws ||
    ncol(draws) != n_parameters ||
    !all(is.finite(draws))) {
  stop(
    "SparseNUTS returned an unexpected draw matrix: ",
    paste(dim(draws), collapse = " x "),
    call. = FALSE
  )
}

draw_index <- data.frame(
  draw = seq_len(nrow(draws)),
  chain = rep(chain_id, samples),
  post_warmup_iteration = seq_len(samples),
  stringsAsFactors = FALSE
)
utils::write.csv(
  draw_index,
  file.path(mcmc_dir, "draws", "draw-index.csv"),
  row.names = FALSE
)

period_time <- getFromNamespace(
  ".mfcl_rtmb_period_decimal_year",
  "mfclrtmb"
)(fit$inputs$frq$period_levels)
biomass_by_region <- getFromNamespace(
  ".mfcl_output_biomass_by_region",
  "mfclrtmb"
)
growth_context_fun <- getFromNamespace(
  ".mfcl_rtmb_report_growth_context",
  "mfclrtmb"
)
yield_analysis_fun <- getFromNamespace(
  ".mfcl_output_bh_yield_analysis",
  "mfclrtmb"
)
exact_report_fun <- getFromNamespace("mfcl_rtmb_exact_report", "mfclrtmb")

quantity_names <- c(
  "total_biomass",
  "spawning_potential",
  "spawning_potential_nofishing",
  "depletion",
  "recruitment",
  "aggregate_f",
  "sb_sbmsy",
  "f_fmsy"
)
quantity_draws <- lapply(
  quantity_names,
  function(name) matrix(
    NA_real_,
    nrow = nrow(draws),
    ncol = length(period_time),
    dimnames = list(
      sprintf("chain_%02d_draw_%03d", chain_id, seq_len(nrow(draws))),
      paste0("period_", seq_along(period_time))
    )
  )
)
names(quantity_draws) <- quantity_names
reference_quantities <- lapply(quantity_names, function(name) {
  rep(NA_real_, length(period_time))
})
names(reference_quantities) <- quantity_names
yield_draws <- data.frame(
  chain = rep(chain_id, nrow(draws)),
  draw = seq_len(nrow(draws)),
  msy = NA_real_,
  fmsy = NA_real_,
  bmsy = NA_real_,
  sbmsy = NA_real_,
  recent_depletion_2021_2024 = NA_real_,
  terminal_depletion = NA_real_,
  valid = FALSE,
  error = "",
  stringsAsFactors = FALSE
)

derive_quantities <- function(par, report = NULL) {
  if (is.null(report)) {
    report <- fit$rtmb$model$report(par)
    report <- exact_report_fun(fit$rtmb, par, report)
  }
  nofishing <- mfcl_rtmb_nofishing_abundance(fit$rtmb, report)
  growth <- growth_context_fun(fit$rtmb, par)
  total_region <- biomass_by_region(
    fit$rtmb,
    report$N,
    adult = FALSE,
    weight_at_age = growth$weight_at_age
  )
  adult_region <- biomass_by_region(
    fit$rtmb,
    report$N,
    adult = TRUE,
    weight_at_age = growth$weight_at_age
  )
  adult0_region <- biomass_by_region(
    fit$rtmb,
    nofishing,
    adult = TRUE,
    weight_at_age = growth$weight_at_age
  )
  total <- rowSums(total_region)
  adult <- rowSums(adult_region)
  adult0 <- rowSums(adult0_region)
  recruitment <- apply(
    report$N[, 1L, , drop = FALSE],
    1L,
    sum,
    na.rm = TRUE
  )
  yield <- yield_analysis_fun(
    fit$rtmb,
    report,
    total_region,
    adult_region,
    par = par
  )
  aggregate_f <- if (!is.null(yield)) {
    as.numeric(yield$aggregate_f)
  } else {
    rep(NA_real_, length(total))
  }
  list(
    quantities = list(
      total_biomass = total,
      spawning_potential = adult,
      spawning_potential_nofishing = adult0,
      depletion = adult / adult0,
      recruitment = recruitment,
      aggregate_f = aggregate_f,
      sb_sbmsy = if (!is.null(yield)) {
        as.numeric(yield$adult_ratio)
      } else {
        rep(NA_real_, length(total))
      },
      f_fmsy = if (!is.null(yield)) {
        as.numeric(yield$f_ratio)
      } else {
        rep(NA_real_, length(total))
      }
    ),
    yield = if (!is.null(yield)) {
      c(
        msy = yield$msy,
        fmsy = yield$fmsy,
        bmsy = yield$bmsy,
        sbmsy = yield$sbmsy
      )
    } else {
      c(msy = NA_real_, fmsy = NA_real_, bmsy = NA_real_, sbmsy = NA_real_)
    }
  )
}

reference <- derive_quantities(fit$par, report = fit$report)
for (name in quantity_names) {
  reference_quantities[[name]] <- reference$quantities[[name]]
}

for (i in seq_len(nrow(draws))) {
  if (i == 1L || i == nrow(draws) || i %% 10L == 0L) {
    message(sprintf(
      paste0(log_prefix, " posterior quantities draw %d/%d"),
      i,
      nrow(draws)
    ))
  }
  current <- tryCatch(
    derive_quantities(draws[i, ]),
    error = function(e) e
  )
  if (inherits(current, "error")) {
    yield_draws$error[[i]] <- conditionMessage(current)
    next
  }
  for (name in quantity_names) {
    quantity_draws[[name]][i, ] <- current$quantities[[name]]
  }
  yield_draws[i, c("msy", "fmsy", "bmsy", "sbmsy")] <-
    as.list(current$yield)
  recent <- period_time >= 2021 & period_time < 2025
  yield_draws$recent_depletion_2021_2024[[i]] <-
    mean(current$quantities$depletion[recent], na.rm = TRUE)
  yield_draws$terminal_depletion[[i]] <-
    utils::tail(current$quantities$depletion, 1L)
  yield_draws$valid[[i]] <- all(vapply(
    current$quantities[c(
      "total_biomass", "spawning_potential", "depletion", "recruitment"
    )],
    function(value) all(is.finite(value)),
    logical(1L)
  ))
}

if (!any(yield_draws$valid)) {
  stop("No posterior draw produced valid core derived quantities", call. = FALSE)
}

saveRDS(
  quantity_draws,
  file.path(posterior_dir, "key-quantity-draws.rds")
)
saveRDS(
  reference_quantities,
  file.path(posterior_dir, "key-quantity-mle.rds")
)
utils::write.csv(
  yield_draws,
  file.path(posterior_dir, "reference-point-and-depletion-draws.csv"),
  row.names = FALSE
)

quantile_summary <- function(matrix, reference) {
  probabilities <- c(0.025, 0.10, 0.25, 0.50, 0.75, 0.90, 0.975)
  values <- apply(
    matrix,
    2L,
    stats::quantile,
    probs = probabilities,
    na.rm = TRUE,
    names = FALSE
  )
  data.frame(
    period = seq_along(period_time),
    time = period_time,
    mle = reference,
    q025 = values[1L, ],
    q10 = values[2L, ],
    q25 = values[3L, ],
    median = values[4L, ],
    q75 = values[5L, ],
    q90 = values[6L, ],
    q975 = values[7L, ],
    n_valid = colSums(is.finite(matrix)),
    stringsAsFactors = FALSE
  )
}

quantity_summaries <- lapply(quantity_names, function(name) {
  quantile_summary(quantity_draws[[name]], reference_quantities[[name]])
})
names(quantity_summaries) <- quantity_names
summary_long <- do.call(rbind, lapply(quantity_names, function(name) {
  data.frame(quantity = name, quantity_summaries[[name]], check.names = FALSE)
}))
utils::write.csv(
  summary_long,
  file.path(posterior_dir, "key-quantity-posterior-summary.csv"),
  row.names = FALSE
)

plot_band <- function(summary, title, ylab, file, reference_lines = NULL) {
  grDevices::png(file, width = 1800, height = 1050, res = 180)
  old <- graphics::par(
    mar = c(4.6, 5.2, 3.2, 1.2),
    las = 1,
    family = "sans"
  )
  on.exit({
    graphics::par(old)
    grDevices::dev.off()
  })
  ylim <- range(c(summary$q025, summary$q975, summary$mle), finite = TRUE)
  graphics::plot(
    summary$time,
    summary$median,
    type = "n",
    xlab = "Year",
    ylab = ylab,
    main = title,
    ylim = ylim,
    bty = "l"
  )
  ribbon <- function(lower, upper, colour) {
    graphics::polygon(
      c(summary$time, rev(summary$time)),
      c(lower, rev(upper)),
      col = colour,
      border = NA
    )
  }
  ribbon(summary$q025, summary$q975, "#2C7FB81F")
  ribbon(summary$q10, summary$q90, "#2C7FB83D")
  ribbon(summary$q25, summary$q75, "#2C7FB866")
  if (length(reference_lines)) {
    for (value in reference_lines) {
      graphics::abline(h = value, lty = 2L, col = "#666666")
    }
  }
  graphics::lines(summary$time, summary$median, lwd = 2.5, col = "#08519C")
  graphics::lines(summary$time, summary$mle, lwd = 2, col = "#CB181D")
  graphics::legend(
    "topright",
    legend = c("Posterior median", "Source-job MLE", "50/80/95% intervals"),
    col = c("#08519C", "#CB181D", "#2C7FB866"),
    lwd = c(2.5, 2, 8),
    bty = "n"
  )
}

plot_specs <- list(
  depletion = c("Depletion", "Spawning potential / no-fishing spawning potential"),
  spawning_potential = c("Spawning potential", "Spawning potential"),
  total_biomass = c("Total biomass", "Biomass"),
  recruitment = c("Recruitment", "Recruits"),
  aggregate_f = c("Aggregate fishing mortality", "Aggregate F"),
  sb_sbmsy = c("Spawning potential relative to MSY", "SB / SBMSY"),
  f_fmsy = c("Fishing mortality relative to MSY", "F / FMSY")
)
for (name in names(plot_specs)) {
  values <- quantity_summaries[[name]]
  if (!any(is.finite(values$median))) {
    next
  }
  plot_band(
    values,
    plot_specs[[name]][[1L]],
    plot_specs[[name]][[2L]],
    file.path(figure_dir, paste0(name, ".png")),
    reference_lines = if (name %in% c("depletion", "sb_sbmsy", "f_fmsy")) 1 else NULL
  )
}

samples_array <- snuts$snuts_fit$samples
if (is.array(samples_array) && length(dim(samples_array)) == 3L) {
  lp_index <- which(dimnames(samples_array)[[3L]] == "lp__")
  if (length(lp_index) == 1L) {
    lp <- samples_array[, , lp_index, drop = FALSE]
    dim(lp) <- dim(samples_array)[1:2]
    grDevices::png(
      file.path(figure_dir, "log-posterior-trace.png"),
      width = 1800,
      height = 1050,
      res = 180
    )
    graphics::matplot(
      seq_len(nrow(lp)),
      lp,
      type = "l",
      lty = 1L,
      col = grDevices::hcl.colors(ncol(lp), "Dark 3"),
      xlab = "Iteration (warmup then retained draws)",
      ylab = "Log posterior",
      main = "SparseNUTS chain traces"
    )
    graphics::abline(v = warmup, lty = 2L, col = "#555555")
    graphics::legend(
      "bottomright",
      legend = paste("Chain", seq_len(ncol(lp))),
      col = grDevices::hcl.colors(ncol(lp), "Dark 3"),
      lty = 1L,
      ncol = 2L,
      bty = "n"
    )
    grDevices::dev.off()
  }
}

overview <- snuts$diagnostics$overview
utils::write.csv(
  overview,
  file.path(diagnostic_dir, "posterior-diagnostics-overview.csv"),
  row.names = FALSE
)

finished_at <- Sys.time()
status <- data.frame(
  status = "completed",
  source_job = source_job,
  model_selector = model_selector,
  model_root = root_name,
  preconditioner = preconditioner,
  chain_id = chain_id,
  total_chains = total_chains,
  chains = chains,
  warmup_per_chain = warmup,
  post_warmup_per_chain = samples,
  posterior_draws = nrow(draws),
  valid_quantity_draws = sum(yield_draws$valid),
  adapt_delta = adapt_delta,
  max_treedepth = max_treedepth,
  objective = fit$objective,
  n_parameters = length(fit$par),
  started_at = format(started_at, "%Y-%m-%dT%H:%M:%S%z"),
  finished_at = format(finished_at, "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_seconds = as.numeric(difftime(finished_at, started_at, units = "secs")),
  stringsAsFactors = FALSE
)
utils::write.csv(
  status,
  file.path(result_dir, "mcmc-status.csv"),
  row.names = FALSE
)

format_table <- function(data) {
  header <- paste0(
    "<tr>",
    paste0("<th>", names(data), "</th>", collapse = ""),
    "</tr>"
  )
  rows <- apply(data, 1L, function(row) {
    paste0(
      "<tr>",
      paste0("<td>", row, "</td>", collapse = ""),
      "</tr>"
    )
  })
  paste0("<table>", header, paste(rows, collapse = "\n"), "</table>")
}

figure_files <- list.files(figure_dir, pattern = "[.]png$", full.names = FALSE)
figure_html <- paste0(
  "<figure><img src='figures/",
  figure_files,
  "'><figcaption>",
  sub("[.]png$", "", figure_files),
  "</figcaption></figure>",
  collapse = "\n"
)
html <- c(
  "<!doctype html>",
  "<html><head><meta charset='utf-8'>",
  paste0("<title>Source job ", source_job, " mfclrtmb MCMC ", chain_key, "</title>"),
  "<style>",
  "body{font-family:system-ui,sans-serif;max-width:1200px;margin:2rem auto;padding:0 1rem;color:#172033}",
  "h1,h2{color:#102A43} .note{background:#FFF7E6;border-left:5px solid #F59E0B;padding:1rem}",
  "table{border-collapse:collapse;width:100%;margin:1rem 0}th,td{border:1px solid #D9E2EC;padding:.5rem;text-align:right}",
  "th{background:#EAF2F8}figure{margin:2rem 0}img{width:100%;height:auto;border:1px solid #D9E2EC}",
  "figcaption{text-align:center;color:#52606D}.ok{background:#E6FFFA;border-left:5px solid #0F766E;padding:1rem}",
  "</style></head><body>",
  paste0("<h1>Source job ", source_job, " mfclrtmb MCMC ", chain_key, "</h1>"),
  paste0(
    "<div class='ok'>Exact source-job final PAR: ",
    length(fit$par),
    " parameters; mfclrtmb objective ",
    format(fit$objective, digits = 12L),
    ".</div>"
  ),
  paste0(
    "<p>",
    "Chain ",
    chain_id,
    " of ",
    total_chains,
    "; ",
    warmup,
    " warmup and ",
    samples,
    " retained iterations per chain; ",
    nrow(draws),
    " posterior draws; adapt_delta ",
    format(adapt_delta, nsmall = 2L),
    ".</p>"
  ),
  paste0(
    "<div class='note'>This is one component chain. Final R-hat, ESS and posterior intervals are calculated only after all ",
    total_chains,
    " independent chains are merged.</div>"
  ),
  "<h2>Parity</h2>",
  format_table(parity),
  "<h2>Sampler diagnostics</h2>",
  format_table(overview),
  "<h2>Key posterior quantities</h2>",
  figure_html,
  "<h2>Saved data</h2>",
  "<ul>",
  "<li><code>mcmc/draws/parameter-draws.rds</code>: this chain's posterior parameter draws</li>",
  "<li><code>mcmc/snuts-fit.rds</code>: SparseNUTS warmup, draws, sampler state and chain metadata (the duplicate native Qinv is omitted)</li>",
  "<li><code>posterior/key-quantity-draws.rds</code>: this chain's draw-by-time key quantities</li>",
  "<li><code>posterior/key-quantity-posterior-summary.csv</code>: MLE and posterior intervals</li>",
  "<li><code>posterior/reference-point-and-depletion-draws.csv</code>: MSY quantities and recent/terminal depletion by draw</li>",
  "</ul>",
  "</body></html>"
)
writeLines(html, file.path(result_dir, "mcmc-chain-report.html"))

print(status)
print(overview)
message(log_prefix, " Completed")
