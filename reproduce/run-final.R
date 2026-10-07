#!/usr/bin/env Rscript
# Base-R reader for unchanged Diagnostic, profile and ASPM native files.
options(stringsAsFactors = FALSE)
fail <- function(...) stop(..., call. = FALSE)
need <- function(x, ...) if (!isTRUE(x)) fail(...)
linked <- function(p) { x <- Sys.readlink(p); !is.na(x) && nzchar(x) }
exists_path <- function(p) file.exists(p) || dir.exists(p) || linked(p)
regular <- function(p) {
  i <- file.info(p)
  need(nrow(i) == 1L && !is.na(i$isdir) && !i$isdir && file_test("-f", p) &&
         !linked(p), "Expected an ordinary file: ", p)
  i
}
directory <- function(p) {
  need(dir.exists(p) && !linked(p), "Expected an ordinary directory: ", p)
}
command <- function(program, args, ...) {
  executable <- Sys.which(program)
  need(nzchar(executable), "Required command is unavailable: ", program)
  out <- suppressWarnings(system2(executable, shQuote(args), stdout = TRUE, stderr = TRUE, ...))
  status <- attr(out, "status")
  need(is.null(status) || status == 0L, program, " failed: ", paste(out, collapse = "\n"))
  out
}
sha256 <- function(p) {
  invisible(lapply(p, regular))
  tool <- if (nzchar(Sys.which("sha256sum"))) "sha256sum" else "shasum"
  x <- command(tool, c(if (tool == "shasum") c("-a", "256"), "--", p))
  need(length(x) == length(p) && all(grepl("^[0-9a-f]{64}[[:space:]]", x)), "Invalid SHA256 output")
  substr(x, 1L, 64L)
}
read_csv <- function(p) {
  regular(p)
  x <- utils::read.csv(p, colClasses = "character", check.names = FALSE, na.strings = NULL)
  need(!anyDuplicated(names(x)), "Duplicate CSV columns: ", p)
  x
}
safe_names <- function(x) {
  length(x) > 0L && all(grepl("^[A-Za-z0-9._/-]+$", x)) &&
    !any(startsWith(x, "/")) &&
    all(vapply(strsplit(x, "/", fixed = TRUE), function(p) all(!p %in% c("", ".", "..")), logical(1)))
}
check_files <- function(root, files, modes = TRUE) {
  need(safe_names(files$path) && !anyDuplicated(files$path) &&
         all(grepl("^[0-9a-f]{64}$", files$sha256)), "Invalid file ledger")
  paths <- file.path(root, files$path)
  invisible(lapply(paths, regular))
  invisible(lapply(unique(dirname(paths)), directory))
  info <- file.info(paths)
  need(identical(as.numeric(info$size), as.numeric(files$bytes)) &&
         identical(sha256(paths), files$sha256), "Saved file bytes differ")
  if (modes) need(identical(as.integer(info$mode), as.integer(files$mode)), "Saved file modes differ")
  links <- command("stat", c(if (Sys.info()[["sysname"]] == "Darwin") c("-f", "%l") else c("-c", "%h"), paths))
  need(length(links) == length(paths) && all(links == "1"), "Saved files must have one ordinary link")
  invisible(TRUE)
}
fresh_output <- function(root, raw, external = FALSE) {
  need(length(raw) == 1L && !is.na(raw) && nzchar(raw) && startsWith(raw, "/"), "Set OUT to an absolute, fresh directory")
  need(!exists_path(raw), "OUT already exists; choose a new directory")
  parent <- normalizePath(dirname(raw), mustWork = TRUE)
  directory(parent)
  output <- file.path(parent, basename(raw))
  need(!basename(raw) %in% c("", ".", ".."), "Invalid OUT name")
  root <- normalizePath(root, mustWork = TRUE)
  need(output != root && !startsWith(root, paste0(output, "/")), "OUT must not replace the package or its ancestors")
  candidate <- root
  while (candidate != dirname(candidate)) {
    if (exists_path(file.path(candidate, ".git"))) {
      need(output != candidate && (!startsWith(output, paste0(candidate, "/")) ||
             (!external && startsWith(output, paste0(candidate, "/outputs/")))),
           if (external) "OUT must be outside the checkout" else "OUT inside the checkout must be beneath outputs/")
      break
    }
    candidate <- dirname(candidate)
  }
  need(!startsWith(output, paste0(root, "/")), "OUT must be outside the package")
  output
}
scalar <- function(p, label) {
  regular(p)
  lines <- trimws(readLines(p, warn = FALSE))
  i <- which(lines == paste("#", label))
  need(length(i) == 1L && i < length(lines), "Missing or duplicate PAR scalar: ", label)
  tokens <- strsplit(lines[i + 1L], "[[:space:]]+")[[1L]]
  n <- suppressWarnings(as.numeric(tokens))
  need(length(n) == 1L && is.finite(n), "Invalid PAR scalar: ", label)
  n
}
kit_inventory <- function(root) {
  lines <- readLines(file.path(root, "CONTENTS.sha256"), warn = FALSE)
  need(length(lines) == 7L && all(grepl("^[0-9a-f]{64}  [A-Za-z0-9._-]+$", lines)), "Invalid kit content ledger")
  names <- substring(lines, 67L)
  need(!anyDuplicated(names) && setequal(names, c("run-final.R", "Makefile", "MODELS.csv", "FILES.csv", "native.tar.xz", "README.md", "source-manifest.json")), "Kit content roster differs")
  need(identical(sha256(file.path(root, names)), substring(lines, 1L, 64L)), "Kit checksum differs")
  models <- read_csv(file.path(root, "MODELS.csv"))
  files <- read_csv(file.path(root, "FILES.csv"))
  need(nrow(models) == 48L && !anyDuplicated(models$case) &&
         sum(models$kind == "profile") == 44L && sum(models$kind == "profile-anchor") == 1L && sum(models$kind == "aspm") == 2L &&
         sum(models$kind == "diagnostic") == 1L && "profile-100" %in% models$case,
       "Expected Diagnostic, 45 profile points and two ASPM source cases")
  need(setequal(models$case, c("diagnostic", paste0("profile-", as.character(seq(50, 160, by = 2.5))), "aspm-constant", "aspm-fitted")), "Exact profile/ASPM case roster differs")
  need(safe_names(files$path) && !anyDuplicated(files$path), "Invalid native file inventory")
  list(models = models, files = files)
}
unpack <- function(root, inventory) {
  expected <- inventory$files$path
  archive <- file.path(root, "native.tar.xz")
  members <- command("tar", c("-tf", archive))
  types <- command("tar", c("-tvf", archive))
  need(length(members) == length(expected) && !anyDuplicated(members) && setequal(members, expected) &&
         length(types) == length(expected) && all(startsWith(types, "-")), "Archive must contain only the exact regular file roster")
  target <- file.path(root, "native")
  if (!exists_path(target)) {
    need(dir.create(target, mode = "0700"), "Cannot create native extraction directory")
    command("tar", c("-xpf", archive, "-C", target))
  }
  directory(target)
  observed <- list.files(target, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  need(setequal(observed, expected), "Extracted native file roster differs")
  check_files(target, inventory$files)
  target
}
prepare <- function(root, native, inventory, row, raw) {
  output <- fresh_output(root, raw)
  prefix <- paste0("models/", row$case, "/")
  selected <- inventory$files[startsWith(inventory$files$path, prefix), , drop = FALSE]
  engine <- inventory$files[inventory$files$path == row$engine_path, , drop = FALSE]
  need(nrow(selected) >= 8L && nrow(engine) == 1L, "Incomplete case closure")
  relative <- substring(selected$path, nchar(prefix) + 1L)
  need(all(c("bet.frq", "bet.ini", "bet.tag", "bet.age_length", "bet.reg_scaling", "mfcl.cfg", "doitall.sh", row$source_par) %in% relative), "Incomplete native inputs/PAR/script")
  need(dir.create(output, mode = "0700"), "Cannot create OUT")
  source <- rbind(selected, engine)
  source$target <- c(relative, "mfclo64")
  # Retain original ASPM files under saved names so the original replay output
  # and native input names cannot overwrite the saved source PAR/input.
  if (row$kind == "aspm") {
    source$target[source$target == "aspm.par"] <- "saved-aspm.par"
    source$target[source$target == "aspm-input-final.par"] <- "saved-aspm-input-final.par"
    row$source_par <- "saved-aspm.par"
  }
  for (i in seq_len(nrow(source))) {
    target <- file.path(output, source$target[i])
    need(file.copy(file.path(native, source$path[i]), target, overwrite = FALSE, copy.mode = TRUE), "Cannot copy saved native file")
    need(Sys.chmod(target, as.octmode(as.integer(source$mode[i])), use_umask = FALSE), "Cannot preserve native mode")
  }
  receipt <- source[c("target", "bytes", "sha256", "mode")]
  names(receipt)[1L] <- "path"
  check_files(output, receipt)
  utils::write.csv(receipt, file.path(output, "saved-inputs.csv"), row.names = FALSE)
  writeLines(c(paste("Case:", row$case), paste("Source role:", row$source_role),
               paste("Original terminal PAR available:", row$terminal_available),
               "Original generated profile continuation scripts and fitted ASPM terminal/restart inputs remain unavailable."),
             file.path(output, "source-role.txt"))
  list(output = output, files = receipt, row = row)
}
require_linux <- function() {
  need(Sys.info()[["sysname"]] == "Linux" && tolower(Sys.info()[["machine"]]) %in% c("x86_64", "amd64"), "Native execution requires Linux x86-64; prepare/verify do not execute MFCL")
}
evaluate <- function(prepared, replay_aspm = FALSE) {
  output <- prepared$output; row <- prepared$row
  if (!replay_aspm) need(row$terminal_available == "TRUE", "Original terminal PAR and restart input are missing; terminal-PAR rerun refused")
  check_files(output, prepared$files)
  old <- setwd(output); on.exit(setwd(old), add = TRUE)
  source <- row$source_par
  input <- if (replay_aspm) row$replay_input else "input.par"
  result <- if (replay_aspm) row$replay_output else "evaluated.par"
  need(file.copy(source, input, overwrite = FALSE, copy.mode = TRUE), "Cannot create native input PAR")
  before <- sha256(c(source, input))
  args <- c("bet.frq", input, result)
  if (row$kind == "profile") {
    switches <- strsplit(row$profile_switches, "|", fixed = TRUE)[[1L]]
    need(length(switches) == 32L && identical(switches[1:2], c("-switch", "10")) && identical(switches[6:8], c("1", "1", "1")), "Original one-evaluation profile recipe differs")
    args <- c(args, "-switch", "11", switches[-c(1L, 2L)], "1", "246", "1")
    status <- suppressWarnings(system2("./mfclo64", shQuote(args), stdout = "mfcl-native.log", stderr = "mfcl-native.log", timeout = 600L))
  } else {
    if (row$kind == "aspm") {
      original <- readLines("aspm_control.txt", warn = FALSE)
      need(sum(original == "1 1 10000") == 1L, "Original ASPM evaluation limit is ambiguous")
      quick <- c(sub("^1 1 10000$", "1 1 1", original), "1 246 1")
    } else {
      need(row$kind == "profile-anchor", "Unknown evaluation controls")
      quick <- c("1 1 1", "1 246 1")
    }
    writeLines(quick, "evaluation-controls.txt", useBytes = TRUE)
    status <- suppressWarnings(system2("./mfclo64", shQuote(c(args, "-file", "-")), stdin = "evaluation-controls.txt", stdout = "mfcl-native.log", stderr = "mfcl-native.log", timeout = 600L))
  }
  need(status %in% c(0L, 3L), "Native evaluation failed; inspect mfcl-native.log (exit ", status, ")")
  check_files(output, prepared$files)
  need(identical(before, sha256(c(source, input))), "Saved or staged PAR changed")
  count <- scalar(result, "The number of parameters")
  need(count == scalar(source, "The number of parameters") && count > 0 && count == as.integer(count), "Active parameter count changed")
  if (row$kind == "aspm") need(count == 1L, "ASPM active parameter count differs")
  objective <- scalar(result, "Objective function value")
  log <- readLines("mfcl-native.log", warn = FALSE)
  total <- grep("^[[:space:]]*Total func[[:space:]]+[^[:space:]]+[[:space:]]*$", log, value = TRUE)
  first <- if (length(total)) suppressWarnings(as.numeric(trimws(sub("^[[:space:]]*Total func[[:space:]]+", "", total[1L])))) else NA_real_
  expected <- as.numeric(row$objective)
  need(is.finite(first) && is.finite(expected) && max(abs(c(first, objective) - expected)) <= 1e-6, "Original native objective differs")
  report <- paste0("plot-", result, ".rep")
  need(regular(report)$size > 0, "Native REP is empty")
  if (replay_aspm) need(regular(report)$size == as.numeric(row$rep_bytes) && sha256(report) == row$rep_sha256, "Complete original ASPM REP checksum differs")
  utils::write.csv(data.frame(case = row$case, source_role = row$source_role, original_terminal_par_available = row$terminal_available,
                              expected_objective = expected, native_objective = objective, first_logged_objective = first,
                              active_parameters = count, native_exit_code = status, function_evaluation_ceiling = 1L,
                              source_par_sha256 = before[1L], report_sha256 = sha256(report), complete_rep_checked = replay_aspm,
                              source_inputs_unchanged = TRUE), "native-check.csv", row.names = FALSE)
  cat(row$case, ": original objective checked; preserved files unchanged", if (replay_aspm) "; complete REP checksum checked" else "", ".\n", sep = "")
}
diagnostic_run <- function(prepared, refit = FALSE) {
  check_files(prepared$output, prepared$files)
  old <- setwd(prepared$output); on.exit(setwd(old), add = TRUE)
  script <- if (refit) "doitall.sh" else "run-final"
  status <- suppressWarnings(system2("sh", shQuote(script), stdout = "reader-native.log", stderr = "reader-native.log", timeout = if (refit) 0L else 600L))
  need(status == 0L, "Diagnostic native script failed; inspect reader-native.log")
  check_files(prepared$output, prepared$files)
  regular("11.par")
  cat(if (refit) "Original Diagnostic full-fit script completed; output 11.par. Full-refit equality is not established.\n" else "Original Diagnostic saved-PAR script completed and checked its five complete REP checksums.\n")
}
repository_package <- function(script_dir, args) {
  repo <- normalizePath(dirname(script_dir), mustWork = TRUE)
  if (args[1L] == "verify") {
    sources <- read_csv(file.path(script_dir, "repository-files.csv"))
    check_files(repo, sources)
    cat("Verified ", nrow(sources), " original repository scientific/source files.\n", sep = "")
  }
  if (length(args) == 3L) {
    output <- fresh_output(script_dir, args[3L])
    need(output != repo && (!startsWith(output, paste0(repo, "/")) || startsWith(output, paste0(repo, "/outputs/"))), "OUT inside the checkout must be beneath outputs/")
  }
  zip <- file.path(script_dir, "bet-2026-diagnostic-readers.zip")
  regular(zip)
  members <- utils::unzip(zip, list = TRUE)$Name
  prefix <- "bet-2026-diagnostic-readers/"
  expected <- paste0(prefix, c("run-final.R", "Makefile", "MODELS.csv", "FILES.csv", "native.tar.xz", "CONTENTS.sha256", "README.md", "source-manifest.json"))
  need(length(members) == length(expected) && !anyDuplicated(members) && setequal(members, expected), "Diagnostic reader ZIP roster differs")
  scratch <- tempfile("bet-diagnostic-readers-"); need(dir.create(scratch, mode = "0700"), "Cannot create temporary package directory")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  utils::unzip(zip, exdir = scratch)
  runner <- file.path(scratch, prefix, "run-final.R")
  status <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), shQuote(c(runner, args))))
  need(status == 0L, "Diagnostic R reader command failed (exit ", status, ")")
}
main <- function(args = commandArgs(trailingOnly = TRUE)) {
  script <- commandArgs()[grepl("^--file=", commandArgs())]
  need(length(script) == 1L, "Run with Rscript")
  root <- dirname(normalizePath(sub("^--file=", "", script), mustWork = TRUE))
  need(length(args) >= 1L, "Use list|verify|unpack or prepare|restore|rerun|refit|profiles|aspm CASE absolute-fresh-OUT")
  action <- args[1L]
  need(action %in% c("list", "verify", "unpack", "prepare", "restore", "rerun", "refit", "profiles", "aspm"), "Unknown action")
  need(length(args) == if (action %in% c("list", "verify", "unpack")) 1L else 3L, "Invalid action arguments")
  if (!file.exists(file.path(root, "MODELS.csv"))) return(repository_package(root, args))
  inventory <- kit_inventory(root)
  if (action == "list") { cat(paste(inventory$models$case, collapse = "\n"), "\n", sep = ""); return(invisible(NULL)) }
  native <- unpack(root, inventory)
  if (action %in% c("verify", "unpack")) {
    for (i in seq_len(nrow(inventory$models))) {
      row <- inventory$models[i, , drop = FALSE]
      par <- file.path(native, "models", row$case, row$source_par)
      count <- scalar(par, "The number of parameters")
      need(count > 0 && count == as.integer(count), "Invalid saved parameter count")
    }
    cat("Verified Diagnostic, 45 original profile points and both ASPM source closures; no model run.\n")
    return(invisible(NULL))
  }
  case <- args[2L]
  if (action %in% c("rerun", "refit", "profiles", "aspm")) require_linux()
  if (action == "aspm" && case %in% c("constant", "fitted")) case <- paste0("aspm-", case)
  selected <- if (action == "profiles" && case %in% c("profiles", "available")) inventory$models$case[startsWith(inventory$models$case, "profile-") | (case == "available" & inventory$models$terminal_available == "TRUE" & inventory$models$kind == "aspm")] else case
  need(all(selected %in% inventory$models$case), "Unknown case")
  if (length(selected) > 1L) {
    output <- fresh_output(root, args[3L]); need(dir.create(output, mode = "0700"), "Cannot create collection OUT")
    for (model in selected) {
      row <- inventory$models[inventory$models$case == model, , drop = FALSE]
      prepared <- prepare(root, native, inventory, row, file.path(output, model))
      evaluate(prepared)
    }
  } else {
    row <- inventory$models[inventory$models$case == selected, , drop = FALSE]
    if (action == "restore") need(row$terminal_available == "TRUE", "Original terminal PAR and restart input missing; terminal restoration refused")
    if (action == "refit") need(row$kind == "diagnostic", "Original generated profile continuation scripts are unavailable; full fit supported only for Diagnostic")
    if (action == "aspm") need(row$kind == "aspm", "Choose constant or fitted ASPM")
    if (action == "profiles") need(row$kind %in% c("profile", "profile-anchor", "aspm") && row$terminal_available == "TRUE", "Missing original terminal PAR; use the explicit ASPM report replay")
    prepared <- prepare(root, native, inventory, row, args[3L])
    if (action %in% c("prepare", "restore")) cat("Prepared exact source files for ", row$case, " in ", prepared$output, ".\n", sep = "")
    else if (row$kind == "diagnostic") diagnostic_run(prepared, action == "refit")
    else evaluate(prepared, action == "aspm")
  }
}
if (sys.nframe() == 0L) tryCatch(main(), error = function(e) { cat(conditionMessage(e), "\n", file = stderr()); quit(status = 1L) })
