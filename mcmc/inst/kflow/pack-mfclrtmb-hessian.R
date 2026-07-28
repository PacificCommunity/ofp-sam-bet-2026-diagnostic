#!/usr/bin/env Rscript

options(warn = 1)

input_root <- Sys.getenv(
  "KFLOW_INPUT_ROOT",
  Sys.getenv("KFLOW_INPUT_DIR", file.path(dirname(getwd()), "inputs"))
)
output_root <- Sys.getenv("KFLOW_OUTPUT_ROOT", file.path(getwd(), "outputs"))
source_job <- trimws(Sys.getenv("MCMC_SOURCE_JOB", ""))
model_selector <- trimws(Sys.getenv("MCMC_MODEL_SELECTOR", ""))
requested_root <- trimws(Sys.getenv("MCMC_ROOT", ""))
if (!nzchar(source_job)) {
  stop("MCMC_SOURCE_JOB is required", call. = FALSE)
}

sha256_file <- function(path) {
  output <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) {
    stop("sha256sum failed for ", path, call. = FALSE)
  }
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

hes_files <- list.files(
  input_root,
  pattern = "[.]hes$",
  recursive = TRUE,
  full.names = TRUE
)
hes_files <- hes_files[
  !grepl("/part_[0-9]+/", hes_files) &
    grepl("/hessian/", hes_files)
]
if (nzchar(model_selector)) {
  hes_files <- hes_files[grepl(model_selector, hes_files, fixed = TRUE)]
}
if (nzchar(requested_root)) {
  hes_files <- hes_files[
    basename(hes_files) == paste0(requested_root, ".hes")
  ]
}
hes_files <- hes_files[
  file.exists(file.path(dirname(hes_files), "hessian_info.rds")) &
    file.exists(file.path(dirname(hes_files), "final.par"))
]
if (length(hes_files) > 1L) {
  signatures <- vapply(hes_files, function(path) {
    paste(
      sha256_file(path),
      sha256_file(file.path(dirname(path), "final.par")),
      sep = "::"
    )
  }, character(1L))
  if (length(unique(signatures)) == 1L) {
    hes_files <- hes_files[[1L]]
  }
}
if (length(hes_files) != 1L) {
  stop(
    "Expected one unique merged full Hessian/final-PAR pair; found ",
    length(hes_files),
    ". Set MCMC_MODEL_SELECTOR or MCMC_ROOT when the archive has multiple models.",
    call. = FALSE
  )
}

hes_file <- hes_files[[1L]]
root_name <- sub("[.]hes$", "", basename(hes_file))
source_dir <- dirname(hes_file)
required <- c(
  hessian = hes_file,
  hessian_info = file.path(source_dir, "hessian_info.rds"),
  final_par = file.path(source_dir, "final.par")
)
missing <- required[!file.exists(required)]
if (length(missing)) {
  stop(
    "Merged Hessian bundle is missing: ",
    paste(names(missing), collapse = ", "),
    call. = FALSE
  )
}

info <- tryCatch(readRDS(required[["hessian_info"]]), error = function(e) NULL)
if (!is.list(info) ||
    !identical(as.character(info$eigen$hessian_status), "PDH") ||
    !identical(as.integer(info$eigen$n_negative_eigenvalues), 0L) ||
    !identical(as.integer(info$eigen$n_zero_eigenvalues), 0L)) {
  stop("The selected Hessian is not verified positive definite", call. = FALSE)
}

bundle_dir <- file.path(output_root, "hessian-preconditioner")
dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
destinations <- c(
  hessian = file.path(bundle_dir, paste0(root_name, ".hes")),
  hessian_info = file.path(bundle_dir, "hessian_info.rds"),
  final_par = file.path(bundle_dir, "final.par")
)
for (name in names(required)) {
  if (!file.copy(required[[name]], destinations[[name]], overwrite = TRUE)) {
    stop("Failed to copy ", required[[name]], call. = FALSE)
  }
}

manifest <- data.frame(
  source_job = source_job,
  model_selector = model_selector,
  model_root = root_name,
  role = names(destinations),
  file = basename(destinations),
  sha256 = vapply(destinations, sha256_file, character(1L)),
  bytes = as.numeric(file.info(destinations)$size),
  hessian_status = as.character(info$eigen$hessian_status),
  n_parameters = as.integer(info$meta$npars),
  stringsAsFactors = FALSE
)
utils::write.csv(
  manifest,
  file.path(bundle_dir, "hessian-preconditioner-manifest.csv"),
  row.names = FALSE
)
saveRDS(
  list(
    source_job = source_job,
    model_selector = model_selector,
    model_root = root_name,
    manifest = manifest,
    eigen = info$eigen
  ),
  file.path(bundle_dir, "hessian-preconditioner-metadata.rds")
)

print(manifest)
message(
  "[mfclrtmb-hessian-pack source-job=",
  source_job,
  "] retained ",
  format(sum(manifest$bytes), big.mark = ",", scientific = FALSE),
  " bytes"
)
