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

native_indepvar <- file.path(source_dir, "indepvar.rpt")
if (!file.exists(native_indepvar)) {
  message(
    "[mfclrtmb-hessian-pack source-job=",
    source_job,
    "] generating the direct native MFCL parameter-order manifest"
  )
  model_input_dirs <- unique(c(
    file.path(dirname(source_dir), "mfcl-inputs"),
    dirname(list.files(
      input_root,
      pattern = paste0("^", root_name, "[.]frq$"),
      recursive = TRUE,
      full.names = TRUE
    ))
  ))
  model_input_dirs <- model_input_dirs[
    dir.exists(model_input_dirs) &
      file.exists(file.path(model_input_dirs, paste0(root_name, ".frq"))) &
      file.exists(file.path(model_input_dirs, paste0(root_name, ".ini")))
  ]
  if (nzchar(model_selector)) {
    selected_dirs <- model_input_dirs[
      grepl(model_selector, model_input_dirs, fixed = TRUE)
    ]
    if (length(selected_dirs)) {
      model_input_dirs <- selected_dirs
    }
  }
  if (!length(model_input_dirs)) {
    stop(
      "Could not locate the matching native MFCL model inputs needed to ",
      "generate indepvar.rpt",
      call. = FALSE
    )
  }
  input_signatures <- vapply(model_input_dirs, function(path) {
    files <- list.files(
      path,
      pattern = paste0("^", root_name, "[.]"),
      full.names = TRUE
    )
    paste(vapply(sort(files), sha256_file, character(1L)), collapse = "::")
  }, character(1L))
  model_input_dirs <- model_input_dirs[
    !duplicated(input_signatures)
  ]
  if (length(model_input_dirs) != 1L) {
    stop(
      "Found multiple distinct native model-input sets; set ",
      "MCMC_MODEL_SELECTOR to select one",
      call. = FALSE
    )
  }

  native_exe <- Sys.getenv("MFCL_EXE", "/home/mfcl/mfclo64")
  if (!file.exists(native_exe)) {
    native_exe <- Sys.which("mfclo64")
  }
  if (!nzchar(native_exe) || !file.exists(native_exe)) {
    stop("MFCL_EXE does not identify a usable native MFCL executable",
         call. = FALSE)
  }

  eval_dir <- tempfile("mfclrtmb-native-order-")
  dir.create(eval_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(eval_dir, recursive = TRUE, force = TRUE), add = TRUE)
  input_files <- list.files(
    model_input_dirs[[1L]],
    pattern = paste0("^", root_name, "[.]"),
    full.names = TRUE
  )
  support_files <- file.path(
    model_input_dirs[[1L]],
    c("mfcl.cfg", "selblocks.dat")
  )
  input_files <- c(input_files, support_files[file.exists(support_files)])
  copied <- file.copy(
    input_files,
    eval_dir,
    overwrite = TRUE,
    copy.date = TRUE
  )
  if (!all(copied) ||
      !file.copy(
        required[["final_par"]],
        file.path(eval_dir, "final.par"),
        overwrite = TRUE,
        copy.date = TRUE
      )) {
    stop("Could not stage the native MFCL order-manifest evaluation",
         call. = FALSE)
  }
  if (!file.exists(file.path(eval_dir, "mfcl.cfg"))) {
    writeLines(c("100000000", "850000000", "1500000000"),
               file.path(eval_dir, "mfcl.cfg"))
  }

  old_dir <- getwd()
  on.exit(setwd(old_dir), add = TRUE)
  setwd(eval_dir)
  log_file <- file.path(eval_dir, "native-order.log")
  status <- system2(
    native_exe,
    c(
      paste0(root_name, ".frq"),
      "final.par",
      "eval.par",
      "-switch", "1", "1", "0", "1", "246", "1"
    ),
    stdout = log_file,
    stderr = log_file
  )
  setwd(old_dir)
  if (!identical(as.integer(status), 0L) ||
      !file.exists(file.path(eval_dir, "indepvar.rpt"))) {
    detail <- if (file.exists(log_file)) {
      paste(tail(readLines(log_file, warn = FALSE), 30L), collapse = "\n")
    } else {
      ""
    }
    stop(
      "Native MFCL failed to generate indepvar.rpt",
      if (nzchar(detail)) paste0(":\n", detail) else "",
      call. = FALSE
    )
  }
  native_indepvar <- file.path(eval_dir, "indepvar.rpt")
}

indep_fields <- strsplit(
  trimws(readLines(native_indepvar, warn = FALSE)[-1L]),
  "[[:space:]]+"
)
indep_labels <- vapply(indep_fields, `[`, character(1L), 2L)
info_labels <- as.character(info$diagnostics$parameter_table$par)
if (!identical(indep_labels, info_labels)) {
  stop(
    "Direct native indepvar.rpt order does not match hessian_info.rds",
    call. = FALSE
  )
}

bundle_dir <- file.path(output_root, "hessian-preconditioner")
dir.create(bundle_dir, recursive = TRUE, showWarnings = FALSE)
destinations <- c(
  hessian = file.path(bundle_dir, paste0(root_name, ".hes")),
  hessian_info = file.path(bundle_dir, "hessian_info.rds"),
  final_par = file.path(bundle_dir, "final.par"),
  indepvar = file.path(bundle_dir, "indepvar.rpt")
)
required <- c(required, indepvar = native_indepvar)
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
