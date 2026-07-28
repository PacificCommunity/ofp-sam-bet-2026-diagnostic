#!/usr/bin/env Rscript

options(warn = 1)

env_integer <- function(name, default) {
  value <- suppressWarnings(as.integer(Sys.getenv(name, as.character(default))))
  if (length(value) != 1L || !is.finite(value) || value < 1L) {
    stop(name, " must be a positive integer", call. = FALSE)
  }
  value
}

input_root <- Sys.getenv(
  "KFLOW_INPUT_ROOT",
  Sys.getenv("KFLOW_INPUT_DIR", file.path(dirname(getwd()), "inputs"))
)
output_root <- Sys.getenv("KFLOW_OUTPUT_ROOT", file.path(getwd(), "outputs"))
source_job <- trimws(Sys.getenv("MCMC_SOURCE_JOB", ""))
if (!nzchar(source_job)) {
  stop("MCMC_SOURCE_JOB is required", call. = FALSE)
}
source_key <- gsub("[^[:alnum:]_.-]+", "-", source_job)
log_prefix <- paste0("[mfclrtmb-mcmc-merge source-job=", source_job, "]")
result_dir <- file.path(
  output_root,
  paste0("source-job-", source_key, "-mfclrtmb-mcmc")
)
draw_dir <- file.path(result_dir, "draws")
posterior_dir <- file.path(result_dir, "posterior")
figure_dir <- file.path(result_dir, "figures")
diagnostic_dir <- file.path(result_dir, "diagnostics")
for (path in c(
  result_dir, draw_dir, posterior_dir, figure_dir, diagnostic_dir
)) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

expected_chains <- env_integer("MCMC_TOTAL_CHAINS", 10L)
expected_samples <- env_integer("MCMC_SAMPLES", 20L)
warmup <- env_integer("MCMC_WARMUP", 100L)
max_treedepth <- env_integer("MCMC_MAX_TREEDEPTH", 10L)
adapt_delta <- as.numeric(Sys.getenv("MCMC_ADAPT_DELTA", "0.9"))

status_files <- list.files(
  input_root,
  pattern = "^mcmc-status[.]csv$",
  recursive = TRUE,
  full.names = TRUE
)
statuses <- lapply(status_files, function(path) {
  value <- tryCatch(
    utils::read.csv(path, stringsAsFactors = FALSE),
    error = function(e) NULL
  )
  if (is.null(value) || nrow(value) != 1L ||
      !"chain_id" %in% names(value) ||
      !"source_job" %in% names(value) ||
      !identical(as.character(value$source_job[[1L]]), source_job) ||
      !identical(as.character(value$status[[1L]]), "completed")) {
    return(NULL)
  }
  list(path = path, root = dirname(path), value = value)
})
statuses <- Filter(Negate(is.null), statuses)
chain_ids <- vapply(
  statuses,
  function(value) as.integer(value$value$chain_id[[1L]]),
  integer(1L)
)
if (!identical(sort(chain_ids), seq_len(expected_chains)) ||
    anyDuplicated(chain_ids)) {
  stop(
    "Expected one completed input for each chain 1:",
    expected_chains,
    "; found ",
    paste(sort(chain_ids), collapse = ","),
    call. = FALSE
  )
}
statuses <- statuses[order(chain_ids)]
chain_ids <- sort(chain_ids)
n_parameters <- unique(vapply(
  statuses,
  function(value) as.integer(value$value$n_parameters[[1L]]),
  integer(1L)
))
if (length(n_parameters) != 1L || !is.finite(n_parameters) ||
    n_parameters < 1L) {
  stop("Chain parameter counts are missing or inconsistent", call. = FALSE)
}
preconditioner <- unique(vapply(
  statuses,
  function(value) as.character(value$value$preconditioner[[1L]]),
  character(1L)
))
if (length(preconditioner) != 1L ||
    !preconditioner %in% c("adaptive", "native")) {
  stop("Chain preconditioner settings are missing or inconsistent", call. = FALSE)
}

required_path <- function(root, ...) {
  path <- file.path(root, ...)
  if (!file.exists(path)) {
    stop("Missing chain output: ", path, call. = FALSE)
  }
  path
}

parameter_draws <- lapply(statuses, function(value) {
  readRDS(required_path(
    value$root, "mcmc", "draws", "parameter-draws.rds"
  ))
})
if (!all(vapply(
  parameter_draws,
  function(value) {
    is.matrix(value) &&
      nrow(value) == expected_samples &&
      ncol(value) == n_parameters &&
      all(is.finite(value))
  },
  logical(1L)
))) {
  stop("At least one chain has invalid parameter draws", call. = FALSE)
}
reference_names <- colnames(parameter_draws[[1L]])
if (!all(vapply(
  parameter_draws,
  function(value) identical(colnames(value), reference_names),
  logical(1L)
))) {
  stop("Parameter columns differ among chains", call. = FALSE)
}

occurrence <- as.integer(ave(
  seq_along(reference_names),
  reference_names,
  FUN = seq_along
))
name_count <- table(reference_names)
parameter_labels <- ifelse(
  as.integer(name_count[reference_names]) > 1L,
  sprintf("%s[%d]", reference_names, occurrence),
  reference_names
)
draw_array <- array(
  NA_real_,
  dim = c(expected_samples, expected_chains, length(reference_names)),
  dimnames = list(
    iteration = seq_len(expected_samples),
    chain = chain_ids,
    variable = parameter_labels
  )
)
for (chain in seq_len(expected_chains)) {
  draw_array[, chain, ] <- parameter_draws[[chain]]
}
combined_parameter_draws <- do.call(rbind, parameter_draws)
colnames(combined_parameter_draws) <- parameter_labels
saveRDS(
  draw_array,
  file.path(draw_dir, "parameter-draws-array.rds")
)
saveRDS(
  combined_parameter_draws,
  file.path(draw_dir, "parameter-draws.rds")
)

draw_index <- data.frame(
  draw = seq_len(nrow(combined_parameter_draws)),
  chain = rep(chain_ids, each = expected_samples),
  post_warmup_iteration = rep(
    seq_len(expected_samples),
    times = expected_chains
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  draw_index,
  file.path(draw_dir, "draw-index.csv"),
  row.names = FALSE
)

posterior_draws <- posterior::as_draws_array(draw_array)
parameter_summary <- posterior::summarise_draws(
  posterior_draws,
  "mean",
  "sd",
  "rhat",
  "ess_bulk",
  "ess_tail"
)
parameter_summary <- as.data.frame(parameter_summary)
utils::write.csv(
  parameter_summary,
  file.path(diagnostic_dir, "parameter-diagnostics.csv"),
  row.names = FALSE
)

sampler_rows <- lapply(seq_along(statuses), function(i) {
  path <- required_path(
    statuses[[i]]$root,
    "mcmc", "diagnostics", "sampler-params.csv"
  )
  value <- utils::read.csv(path, stringsAsFactors = FALSE)
  value$chain <- chain_ids[[i]]
  value
})
sampler_params <- do.call(rbind, sampler_rows)
utils::write.csv(
  sampler_params,
  file.path(diagnostic_dir, "sampler-params.csv"),
  row.names = FALSE
)
required_sampler_columns <- c(
  "chain", "accept_stat__", "stepsize__", "treedepth__",
  "n_leapfrog__", "divergent__", "energy__"
)
missing_sampler_columns <- setdiff(required_sampler_columns, names(sampler_params))
if (length(missing_sampler_columns)) {
  stop(
    "Sampler diagnostics are missing: ",
    paste(missing_sampler_columns, collapse = ", "),
    call. = FALSE
  )
}

chain_diagnostics <- do.call(rbind, lapply(seq_along(statuses), function(i) {
  chain <- chain_ids[[i]]
  value <- sampler_params[sampler_params$chain == chain, , drop = FALSE]
  energy <- suppressWarnings(as.numeric(value$energy__))
  energy_variance <- stats::var(energy, na.rm = TRUE)
  bfmi <- if (sum(is.finite(energy)) > 2L &&
              is.finite(energy_variance) &&
              energy_variance > 0) {
    mean(diff(energy)^2, na.rm = TRUE) / energy_variance
  } else {
    NA_real_
  }
  data.frame(
    chain = chain,
    retained_draws = nrow(value),
    divergences = sum(value$divergent__ > 0, na.rm = TRUE),
    treedepth_hits = sum(
      value$treedepth__ >= max_treedepth,
      na.rm = TRUE
    ),
    mean_accept_stat = mean(value$accept_stat__, na.rm = TRUE),
    min_accept_stat = min(value$accept_stat__, na.rm = TRUE),
    mean_stepsize = mean(value$stepsize__, na.rm = TRUE),
    mean_leapfrog = mean(value$n_leapfrog__, na.rm = TRUE),
    max_leapfrog = max(value$n_leapfrog__, na.rm = TRUE),
    ebfmi = bfmi,
    elapsed_seconds = as.numeric(
      statuses[[i]]$value$elapsed_seconds[[1L]]
    ),
    valid_quantity_draws = as.integer(
      statuses[[i]]$value$valid_quantity_draws[[1L]]
    ),
    diagnostic_flag = if (
      any(value$divergent__ > 0, na.rm = TRUE) ||
      any(value$treedepth__ >= max_treedepth, na.rm = TRUE) ||
      (is.finite(bfmi) && bfmi < 0.3)
    ) {
      "review"
    } else {
      "ok"
    },
    stringsAsFactors = FALSE
  )
}))
utils::write.csv(
  chain_diagnostics,
  file.path(diagnostic_dir, "chain-sampler-diagnostics.csv"),
  row.names = FALSE
)

finite_rhat <- parameter_summary$rhat[is.finite(parameter_summary$rhat)]
finite_bulk <- parameter_summary$ess_bulk[
  is.finite(parameter_summary$ess_bulk)
]
finite_tail <- parameter_summary$ess_tail[
  is.finite(parameter_summary$ess_tail)
]
overview <- data.frame(
  sampler = "SparseNUTS",
  metric = if (identical(preconditioner, "native")) {
    "native_hessian_dense"
  } else {
    "adaptive_diagonal"
  },
  chains = expected_chains,
  warmup_per_chain = warmup,
  post_warmup_per_chain = expected_samples,
  posterior_draws = nrow(combined_parameter_draws),
  divergent_transitions = sum(
    sampler_params$divergent__ > 0,
    na.rm = TRUE
  ),
  max_treedepth = max_treedepth,
  treedepth_hits = sum(
    sampler_params$treedepth__ >= max_treedepth,
    na.rm = TRUE
  ),
  max_rhat = if (length(finite_rhat)) max(finite_rhat) else NA_real_,
  min_ess_bulk = if (length(finite_bulk)) min(finite_bulk) else NA_real_,
  min_ess_tail = if (length(finite_tail)) min(finite_tail) else NA_real_,
  mean_accept_stat = mean(
    sampler_params$accept_stat__,
    na.rm = TRUE
  ),
  min_ebfmi = if (any(is.finite(chain_diagnostics$ebfmi))) {
    min(chain_diagnostics$ebfmi, na.rm = TRUE)
  } else {
    NA_real_
  },
  chains_flagged_for_review = sum(
    chain_diagnostics$diagnostic_flag != "ok"
  ),
  stringsAsFactors = FALSE
)
utils::write.csv(
  overview,
  file.path(diagnostic_dir, "posterior-diagnostics-overview.csv"),
  row.names = FALSE
)
parameter_summary_order <- order(
  -ifelse(is.finite(parameter_summary$rhat), parameter_summary$rhat, -Inf),
  ifelse(is.finite(parameter_summary$ess_bulk), parameter_summary$ess_bulk, Inf)
)
utils::write.csv(
  utils::head(parameter_summary[parameter_summary_order, , drop = FALSE], 100L),
  file.path(diagnostic_dir, "parameters-needing-review.csv"),
  row.names = FALSE
)

quantity_draws_by_chain <- lapply(statuses, function(value) {
  readRDS(required_path(
    value$root, "posterior", "key-quantity-draws.rds"
  ))
})
quantity_names <- names(quantity_draws_by_chain[[1L]])
if (!length(quantity_names) ||
    !all(vapply(
      quantity_draws_by_chain,
      function(value) identical(names(value), quantity_names),
      logical(1L)
    ))) {
  stop("Key-quantity names differ among chains", call. = FALSE)
}
quantity_draws <- lapply(quantity_names, function(name) {
  do.call(rbind, lapply(quantity_draws_by_chain, `[[`, name))
})
names(quantity_draws) <- quantity_names
saveRDS(
  quantity_draws,
  file.path(posterior_dir, "key-quantity-draws.rds")
)

reference_quantities <- readRDS(required_path(
  statuses[[1L]]$root,
  "posterior", "key-quantity-mle.rds"
))
for (i in seq_along(statuses)[-1L]) {
  current <- readRDS(required_path(
    statuses[[i]]$root,
    "posterior", "key-quantity-mle.rds"
  ))
  if (!isTRUE(all.equal(
    reference_quantities,
    current,
    tolerance = 1e-10
  ))) {
    stop("MLE key quantities differ among chain jobs", call. = FALSE)
  }
}
saveRDS(
  reference_quantities,
  file.path(posterior_dir, "key-quantity-mle.rds")
)

chain_summary <- utils::read.csv(
  required_path(
    statuses[[1L]]$root,
    "posterior", "key-quantity-posterior-summary.csv"
  ),
  stringsAsFactors = FALSE
)
period_time <- chain_summary$time[
  chain_summary$quantity == quantity_names[[1L]]
]
if (length(period_time) != ncol(quantity_draws[[1L]])) {
  stop("Could not reconstruct the model time axis", call. = FALSE)
}

yield_draws <- do.call(rbind, lapply(seq_along(statuses), function(i) {
  value <- utils::read.csv(
    required_path(
      statuses[[i]]$root,
      "posterior", "reference-point-and-depletion-draws.csv"
    ),
    stringsAsFactors = FALSE
  )
  value$chain <- chain_ids[[i]]
  value
}))
yield_draws$combined_draw <- seq_len(nrow(yield_draws))
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
  data.frame(
    quantity = name,
    quantity_summaries[[name]],
    check.names = FALSE
  )
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
  graphics::lines(
    summary$time, summary$median, lwd = 2.5, col = "#08519C"
  )
  graphics::lines(
    summary$time, summary$mle, lwd = 2, col = "#CB181D"
  )
  graphics::legend(
    "topright",
    legend = c("Posterior median", "Source-job MLE", "50/80/95% intervals"),
    col = c("#08519C", "#CB181D", "#2C7FB866"),
    lwd = c(2.5, 2, 8),
    bty = "n"
  )
}

plot_specs <- list(
  depletion = c(
    "Depletion",
    "Spawning potential / no-fishing spawning potential"
  ),
  spawning_potential = c("Spawning potential", "Spawning potential"),
  total_biomass = c("Total biomass", "Biomass"),
  recruitment = c("Recruitment", "Recruits"),
  aggregate_f = c("Aggregate fishing mortality", "Aggregate F"),
  sb_sbmsy = c("Spawning potential relative to MSY", "SB / SBMSY"),
  f_fmsy = c("Fishing mortality relative to MSY", "F / FMSY")
)
for (name in intersect(names(plot_specs), names(quantity_summaries))) {
  values <- quantity_summaries[[name]]
  if (!any(is.finite(values$median))) {
    next
  }
  plot_band(
    values,
    plot_specs[[name]][[1L]],
    plot_specs[[name]][[2L]],
    file.path(figure_dir, paste0(name, ".png")),
    reference_lines = if (
      name %in% c("depletion", "sb_sbmsy", "f_fmsy")
    ) 1 else NULL
  )
}

grDevices::png(
  file.path(figure_dir, "sampler-energy-by-chain.png"),
  width = 1800,
  height = 1050,
  res = 180
)
graphics::matplot(
  seq_len(expected_samples),
  sapply(chain_ids, function(chain) {
    sampler_params$energy__[sampler_params$chain == chain]
  }),
  type = "l",
  lty = 1L,
  col = grDevices::hcl.colors(expected_chains, "Dark 3"),
  xlab = "Post-warmup iteration",
  ylab = "Hamiltonian energy",
  main = "SparseNUTS retained-draw energy by chain"
)
graphics::legend(
  "topright",
  legend = paste("Chain", chain_ids),
  col = grDevices::hcl.colors(expected_chains, "Dark 3"),
  lty = 1L,
  ncol = 2L,
  bty = "n"
)
grDevices::dev.off()

parity_files <- vapply(statuses, function(value) {
  required_path(value$root, "mfcl-mfclrtmb-parity.csv")
}, character(1L))
parity <- utils::read.csv(parity_files[[1L]], stringsAsFactors = FALSE)
if (!all(vapply(parity_files[-1L], function(path) {
  isTRUE(all.equal(
    parity,
    utils::read.csv(path, stringsAsFactors = FALSE),
    tolerance = 1e-12
  ))
}, logical(1L)))) {
  stop("MFCL-mfclrtmb parity evidence differs among chains", call. = FALSE)
}
utils::write.csv(
  parity,
  file.path(diagnostic_dir, "mfcl-mfclrtmb-parity.csv"),
  row.names = FALSE
)

hessian <- data.frame()
if (identical(preconditioner, "native")) {
  hessian_files <- vapply(statuses, function(value) {
    required_path(
      value$root,
      "diagnostics", "native-hessian-preconditioner.csv"
    )
  }, character(1L))
  hessian <- utils::read.csv(hessian_files[[1L]], stringsAsFactors = FALSE)
  utils::write.csv(
    hessian,
    file.path(diagnostic_dir, "native-hessian-preconditioner.csv"),
    row.names = FALSE
  )
}

chain_status <- do.call(rbind, lapply(statuses, `[[`, "value"))
utils::write.csv(
  chain_status,
  file.path(diagnostic_dir, "chain-status.csv"),
  row.names = FALSE
)

status <- data.frame(
  status = "completed",
  source_job = source_job,
  preconditioner = preconditioner,
  chains = expected_chains,
  warmup_per_chain = warmup,
  post_warmup_per_chain = expected_samples,
  posterior_draws = nrow(combined_parameter_draws),
  valid_quantity_draws = sum(yield_draws$valid),
  adapt_delta = adapt_delta,
  max_treedepth = max_treedepth,
  objective = parity$mfclrtmb_objective[[1L]],
  n_parameters = ncol(combined_parameter_draws),
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

figure_files <- list.files(
  figure_dir,
  pattern = "[.]png$",
  full.names = FALSE
)
figure_html <- paste0(
  "<figure><img src='figures/",
  figure_files,
  "'><figcaption>",
  sub("[.]png$", "", figure_files),
  "</figcaption></figure>",
  collapse = "\n"
)
preconditioner_html <- if (identical(preconditioner, "native")) {
  c("<h2>Native Hessian preconditioner</h2>", format_table(hessian))
} else {
  c(
    "<h2>MCMC geometry</h2>",
    "<p>SparseNUTS used its standalone adaptive diagonal metric; no native MFCL Hessian was required.</p>"
  )
}
html <- c(
  "<!doctype html>",
  "<html><head><meta charset='utf-8'>",
  paste0("<title>Source job ", source_job, " mfclrtmb MCMC pilot</title>"),
  "<style>",
  "body{font-family:system-ui,sans-serif;max-width:1200px;margin:2rem auto;padding:0 1rem;color:#172033}",
  "h1,h2{color:#102A43}.note{background:#FFF7E6;border-left:5px solid #F59E0B;padding:1rem}",
  "table{border-collapse:collapse;width:100%;margin:1rem 0}th,td{border:1px solid #D9E2EC;padding:.5rem;text-align:right}",
  "th{background:#EAF2F8}figure{margin:2rem 0}img{width:100%;height:auto;border:1px solid #D9E2EC}",
  "figcaption{text-align:center;color:#52606D}.ok{background:#E6FFFA;border-left:5px solid #0F766E;padding:1rem}",
  "</style></head><body>",
  paste0("<h1>Source job ", source_job, " mfclrtmb MCMC pilot</h1>"),
  paste0(
    "<div class='ok'>Exact source-job final PAR: ",
    n_parameters,
    " parameters; ",
    "mfclrtmb objective ",
    format(parity$mfclrtmb_objective[[1L]], digits = 12L),
    ".</div>"
  ),
  paste0(
    "<p>",
    expected_chains,
    " independent chains; ",
    warmup,
    " warmup and ",
    expected_samples,
    " retained iterations per chain; ",
    nrow(combined_parameter_draws),
    " posterior draws; adapt_delta ",
    format(adapt_delta, nsmall = 2L),
    ".</p>"
  ),
  "<div class='note'>This is a short workflow pilot. Twenty retained draws per chain are not enough to establish final posterior precision. Interpret intervals only after reviewing divergences, tree depth, R-hat and ESS below.</div>",
  "<h2>MFCL–mfclrtmb parity</h2>",
  format_table(parity),
  preconditioner_html,
  "<h2>Sampler diagnostics</h2>",
  format_table(overview),
  "<h2>Diagnostics by chain</h2>",
  format_table(chain_diagnostics),
  "<h2>Key posterior quantities</h2>",
  figure_html,
  "<h2>Saved data</h2>",
  "<ul>",
  "<li><code>draws/parameter-draws-array.rds</code>: iteration × chain × parameter draws</li>",
  paste0(
    "<li><code>diagnostics/parameter-diagnostics.csv</code>: R-hat and ESS for all ",
    n_parameters,
    " parameters</li>"
  ),
  "<li><code>diagnostics/chain-sampler-diagnostics.csv</code>: divergences, tree depth, acceptance, step size, leapfrog count, E-BFMI and runtime by chain</li>",
  "<li><code>diagnostics/parameters-needing-review.csv</code>: the 100 parameters with the least favourable R-hat/ESS diagnostics</li>",
  "<li><code>posterior/key-quantity-draws.rds</code>: combined draw-by-time key quantities</li>",
  "<li><code>posterior/key-quantity-posterior-summary.csv</code>: MLE and 50/80/95% intervals</li>",
  "<li><code>posterior/reference-point-and-depletion-draws.csv</code>: MSY quantities and recent/terminal depletion by draw</li>",
  "</ul>",
  "</body></html>"
)
writeLines(html, file.path(result_dir, "mcmc-report.html"))

print(status)
print(overview)
message(log_prefix, " Completed")
