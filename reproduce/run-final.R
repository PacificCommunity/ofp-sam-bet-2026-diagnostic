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
numeric_file <- function(path) {
  need(regular(path)$size > 0, "Native output is empty: ", path)
  lines <- trimws(readLines(path, warn = FALSE))
  values <- unlist(strsplit(lines[nzchar(lines) & !startsWith(lines, "#")], "[[:space:]]+"), use.names = FALSE)
  need(length(values) > 0L && all(is.finite(suppressWarnings(as.numeric(values)))), "Nonfinite or nonnumeric native output: ", path)
}
rep_sections <- function(path) {
  numeric_file(path)
  lines <- readLines(path, warn = FALSE)
  headers <- which(grepl("^[[:space:]]*#", lines))
  labels <- trimws(sub("^[[:space:]]*#[[:space:]]*", "", lines[headers]))
  section <- function(label, rows = 1L, columns = 1L, tokens = FALSE) {
    index <- which(labels == label)
    need(length(index) == 1L, "Missing or duplicate REP section: ", label)
    first <- headers[index] + 1L
    last <- if (index < length(headers)) headers[index + 1L] - 1L else length(lines)
    need(first <= last, "Empty REP section: ", label)
    text <- trimws(lines[seq.int(first, last)])
    text <- text[nzchar(text)]
    fields <- strsplit(text, "[[:space:]]+")
    need(length(text) == rows && all(lengths(fields) == columns), "REP row/column count differs: ", label)
    fields <- unlist(fields, use.names = FALSE)
    numbers <- suppressWarnings(as.numeric(fields))
    need(all(is.finite(numbers)), "Nonfinite REP section: ", label)
    matrix(if (tokens) fields else numbers, nrow = rows, ncol = columns, byrow = TRUE)
  }
  attr(section, "labels") <- labels
  section
}
dimension_labels <- c("Number of time periods", "Year 1", "Number of regions", "Number of species", "Number of age classes", "Number of recruitments per year")
biomass_labels <- c("Total biomass", "Adult biomass", "Total biomass in absence of fishing", "Adult biomass in absence of fishing")
rep_values <- function(path, full = TRUE) {
  section <- rep_sections(path)
  dimensions <- vapply(dimension_labels, function(label) as.numeric(section(label)), numeric(1))
  need(all(dimensions > 0 & dimensions == as.integer(dimensions)) && dimensions[1L] <= 2000 && dimensions[3L] <= 100 && dimensions[6L] <= 12 && dimensions[1L] %% dimensions[6L] == 0, "Invalid REP dimensions")
  values <- setNames(as.list(dimensions), dimension_labels)
  required <- c("Total biomass", "Adult biomass", "Recruitment")
  additional <- c(biomass_labels[3:4], "Total biomass at MSY", "Adult biomass at MSY", "F multiplier at MSY")
  checked <- c(required, if(full) additional else additional[additional %in% attr(section, "labels")])
  for (label in checked) {
    shape <- if (label %in% c(biomass_labels, "Recruitment")) dimensions[c(1L, 3L)] else c(1L, 1L)
    values[[label]] <- section(label, shape[1L], shape[2L])
    if (full || label %in% required) need(all(values[[label]] >= 0) && (label == "Recruitment" || all(values[[label]] > 0)), "Invalid central REP quantity: ", label)
  }
  # Half a last printed digit bounds rounding in each scientific-notation token.
  text <- section("Total biomass", dimensions[1L], dimensions[3L], tokens = TRUE)
  rounding <- vapply(as.vector(text), function(token) {
    parts <- strsplit(tolower(token), "e", fixed = TRUE)[[1L]]
    exponent <- if (length(parts) == 2L) as.numeric(parts[2L]) else 0
    decimals <- if (grepl(".", parts[1L], fixed = TRUE)) nchar(sub("^[^.]*[.]", "", parts[1L])) else 0
    0.5 * 10^(exponent - decimals)
  }, numeric(1))
  list(dimensions = dimensions, values = values, checked_sections = checked, full_unfished_msy_sections = all(additional %in% checked), average_biomass = mean(rowSums(values[["Total biomass"]])), average_biomass_rounding = sum(rounding) / dimensions[1L])
}
native_log <- function(path, parameters, ceiling_source = "native-log", expected_criterion = NULL) {
  need(regular(path)$size > 0, "Native log is empty")
  lines <- readLines(path, warn = FALSE)
  controls <- grep("^[[:space:]]*optfile\\.cpp[[:space:]]+", lines, value = TRUE)
  ceiling <- 0L
  for (line in controls) {
    fields <- strsplit(trimws(sub("^[[:space:]]*optfile\\.cpp[[:space:]]+", "", line)), "[[:space:]]+")[[1L]]
    need(length(fields) >= 3L && all(grepl("^[-+]?[0-9]+$", fields[1:3])), "Malformed native controls")
    if (identical(as.numeric(fields[1:2]), c(1, 1))) {
      need(as.numeric(fields[3L]) == 1, "Native function ceiling differs from one")
      ceiling <- ceiling + 1L
    }
  }
  counters <- lines[grepl("variables;", lines, fixed = TRUE)]
  counters <- sub("^Initial statistics:[[:space:]]*", "", trimws(counters))
  pattern <- "^[[:space:]]*([0-9]+)[[:space:]]+variables;[[:space:]]+iteration[[:space:]]+([0-9]+);[[:space:]]+function[[:space:]]+evaluation[[:space:]]+([0-9]+)[[:space:]]*$"
  observed <- lapply(counters, function(line) {
    values <- regmatches(line, regexec(pattern, line))[[1L]]
    need(length(values) == 4L && identical(as.numeric(values[2:4]), c(parameters, 0, 0)), "Native parameter/iteration/function counters differ from the saved PAR and zero counters")
    as.numeric(values[2:4])
  })
  need(length(observed) > 0L && (ceiling > 0L || identical(ceiling_source, "fixed-profile-cli")), "Native ceiling/zero-counter evidence is missing")
  criterion_lines <- grep("converg criter", lines, value = TRUE, fixed = TRUE)
  criterion <- vapply(criterion_lines, function(line) {
    fields <- regmatches(line, regexec("^[[:space:]]*Exit code = [-+]?[0-9]+;[[:space:]]+converg criter[[:space:]]+([^[:space:]]+)[[:space:]]*$", line))[[1L]]
    need(length(fields) == 2L && is.finite(suppressWarnings(as.numeric(fields[2L]))), "Malformed native gradient criterion")
    as.numeric(fields[2L])
  }, numeric(1))
  gradient_lines <- grep("maximum gradient component mag", lines, value = TRUE, fixed = TRUE)
  gradients <- vapply(gradient_lines, function(line) {
    fields <- regmatches(line, regexec("^[[:space:]]*Function value[[:space:]]+([^[:space:]]+);[[:space:]]+maximum gradient component mag[[:space:]]+([^[:space:]]+)[[:space:]]*$", line))[[1L]]
    need(length(fields) == 3L && all(is.finite(suppressWarnings(as.numeric(fields[2:3])))), "Malformed native gradient statistics")
    as.numeric(fields[3L])
  }, numeric(1))
  if (!is.null(expected_criterion)) need(length(criterion) > 0L && all(criterion == expected_criterion) && length(gradients) > 0L, "Generated evaluation-only gradient criterion evidence differs or is missing")
  total <- grep("^[[:space:]]*Total func[[:space:]]+[^[:space:]]+[[:space:]]*$", lines, value = TRUE)
  objectives <- suppressWarnings(as.numeric(trimws(sub("^[[:space:]]*Total func[[:space:]]+", "", total))))
  need(length(objectives) > 0L && all(is.finite(objectives)), "Native objective evidence is missing or nonfinite")
  list(objective = objectives[1L], parameters = observed[[1L]][1L], iteration = observed[[1L]][2L], function_counter = observed[[1L]][3L], counter_records = length(observed), ceiling_records = ceiling, ceiling_source = if (ceiling > 0L) "native-log" else ceiling_source, gradient_criterion = if(length(criterion)) criterion[1L] else NA_real_, initial_gradient = if(length(gradients)) gradients[1L] else NA_real_)
}
check_report <- function(path, source, row, reference) {
  need(is.list(reference) && identical(reference$schema, "bet2026.reader_reference.v1"), "Pinned historical reader reference is missing")
  # Original constrained-profile controls may omit unfished/MSY output modes.
  # All present sections remain checked; the original fished fields are required.
  report <- rep_values(path, full = row$kind != "profile")
  need(identical(report$dimensions, reference$dimensions), "Native REP dimensions differ from the original reference")
  need(sha256("bet.frq") == reference$frq_sha256 && scalar(source, "The number of age classes") == report$dimensions[5L] && scalar(source, "First year in model") == report$dimensions[2L], "Native dimensions differ from the exact saved PAR/FRQ")
  difference <- NA_real_; expected <- NA_real_; scope <- "objective-count-dimensions-finite-central-shapes"
  if (row$kind %in% c("profile", "profile-anchor")) {
    point <- reference$profile_points[reference$profile_points$scalar == as.numeric(sub("^profile-", "", row$case)), , drop = FALSE]
    need(nrow(point) == 1L && is.finite(point$total_average_biomass_1000_t), "Original profile biomass target is missing")
    expected <- point$total_average_biomass_1000_t * 1000
    difference <- abs(report$average_biomass - expected)
    need(difference <= report$average_biomass_rounding + 1e-6, "Original profile total-average biomass differs beyond native REP printed precision")
    scope <- "objective-count-dimensions-finite-central-shapes-original-average-biomass"
  }
  if (row$kind %in% c("profile-anchor", "diagnostic")) {
    for (label in names(reference$values)) {
      x <- report$values[[label]]; y <- reference$values[[label]]
      need(identical(dim(x), dim(y)) && length(x) == length(y) && all(abs(x-y) <= 1e-10*pmax(1,abs(y))), "Original anchor central REP differs: ", label)
    }
    scope <- paste0(scope, "-anchor-central-equality")
  }
  list(report = report, expected_average_biomass = expected, average_biomass_abs_diff = difference, scope = scope)
}
kit_inventory <- function(root) {
  lines <- readLines(file.path(root, "CONTENTS.sha256"), warn = FALSE)
  need(length(lines) == 8L && all(grepl("^[0-9a-f]{64}  [A-Za-z0-9._-]+$", lines)), "Invalid kit content ledger")
  names <- substring(lines, 67L)
  need(!anyDuplicated(names) && setequal(names, c("run-final.R", "Makefile", "MODELS.csv", "FILES.csv", "native.tar.xz", "README.md", "source-manifest.json", "REFERENCE.rds")), "Kit content roster differs")
  need(identical(sha256(file.path(root, names)), substring(lines, 1L, 64L)), "Kit checksum differs")
  models <- read_csv(file.path(root, "MODELS.csv"))
  files <- read_csv(file.path(root, "FILES.csv"))
  need(nrow(models) == 48L && !anyDuplicated(models$case) &&
         sum(models$kind == "profile") == 44L && sum(models$kind == "profile-anchor") == 1L && sum(models$kind == "aspm") == 2L &&
         sum(models$kind == "diagnostic") == 1L && "profile-100" %in% models$case,
       "Expected Diagnostic, 45 profile points and two ASPM source cases")
  need(setequal(models$case, c("diagnostic", paste0("profile-", as.character(seq(50, 160, by = 2.5))), "aspm-constant", "aspm-fitted")), "Exact profile/ASPM case roster differs")
  need(safe_names(files$path) && !anyDuplicated(files$path), "Invalid native file inventory")
  reference <- readRDS(file.path(root, "REFERENCE.rds"))
  need(is.list(reference) && identical(reference$schema, "bet2026.reader_reference.v1"), "Invalid historical reference schema")
  list(models = models, files = files, reference = reference)
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
  list(output = output, files = receipt, row = row, reference = inventory$reference)
}
require_linux <- function() {
  need(Sys.info()[["sysname"]] == "Linux" && tolower(Sys.info()[["machine"]]) %in% c("x86_64", "amd64"), "Native execution requires Linux x86-64; prepare/verify do not execute MFCL")
}
profile_arguments <- function(row, input, result) {
  switches <- strsplit(row$profile_switches, "|", fixed = TRUE)[[1L]]
  need(length(switches) == 32L && identical(switches[1:2], c("-switch", "10")) && identical(switches[6:8], c("1", "1", "1")), "Original one-evaluation profile recipe differs")
  # Reader-only stop criterion; unchanged original ten switch groups remain first.
  c("bet.frq", input, result, "-switch", "12", switches[-c(1L, 2L)], "1", "246", "1", "1", "50", "6")
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
    args <- profile_arguments(row, input, result)
    writeLines(c("./mfclo64", args), "native-command.txt", useBytes = TRUE)
    status <- suppressWarnings(system2("./mfclo64", shQuote(args), stdout = "mfcl-native.log", stderr = "mfcl-native.log", timeout = 600L))
  } else {
    if (row$kind == "aspm") {
      original <- readLines("aspm_control.txt", warn = FALSE)
      need(sum(original == "1 1 10000") == 1L, "Original ASPM evaluation limit is ambiguous")
      quick <- c(sub("^1 1 10000$", "1 1 1", original), "1 246 1")
    } else {
      need(row$kind == "profile-anchor", "Unknown evaluation controls")
      quick <- c("1 1 1", "1 246 1", "1 50 6")
    }
    writeLines(quick, "evaluation-controls.txt", useBytes = TRUE)
    writeLines(c("./mfclo64", args, "-file", "-"), "native-command.txt", useBytes = TRUE)
    status <- suppressWarnings(system2("./mfclo64", shQuote(c(args, "-file", "-")), stdin = "evaluation-controls.txt", stdout = "mfcl-native.log", stderr = "mfcl-native.log", timeout = 600L))
  }
  need(status %in% c(0L, 3L), "Native evaluation failed; inspect mfcl-native.log (exit ", status, ")")
  check_files(output, prepared$files)
  need(identical(before, sha256(c(source, input))), "Saved or staged PAR changed")
  numeric_file(result)
  count <- scalar(result, "The number of parameters")
  need(count == scalar(source, "The number of parameters") && count > 0 && count == as.integer(count), "Active parameter count changed")
  if (row$kind == "aspm") need(count == 1L, "ASPM active parameter count differs")
  objective <- scalar(result, "Objective function value")
  is_profile <- row$kind %in% c("profile", "profile-anchor")
  logged <- native_log("mfcl-native.log", count, if (row$kind == "profile") "fixed-profile-cli" else "native-log", if(is_profile) 1e6 else NULL)
  first <- logged$objective
  expected <- as.numeric(row$objective)
  need(is.finite(first) && is.finite(expected) && max(abs(c(first, objective) - expected)) <= 1e-6, "Original native objective differs")
  report <- paste0("plot-", result, ".rep")
  central <- check_report(report, source, row, prepared$reference)
  if (replay_aspm) need(regular(report)$size == as.numeric(row$rep_bytes) && sha256(report) == row$rep_sha256, "Complete original ASPM REP checksum differs")
  utils::write.csv(data.frame(case = row$case, source_role = row$source_role, original_terminal_par_available = row$terminal_available,
                              expected_objective = expected, native_objective = objective, first_logged_objective = first,
                              active_parameters = count, native_exit_code = status, function_evaluation_ceiling = 1L,
                              observed_native_parameters = logged$parameters, observed_iteration = logged$iteration,
                              observed_function_counter = logged$function_counter, native_counter_records = logged$counter_records,
                              native_ceiling_records = logged$ceiling_records, validation_scope = central$scope,
                              function_ceiling_evidence = logged$ceiling_source, reported_gradient_criterion = logged$gradient_criterion,
                              initial_logged_gradient = logged$initial_gradient, evaluation_only = TRUE,
                              total_average_biomass = central$report$average_biomass,
                              expected_total_average_biomass = central$expected_average_biomass,
                              total_average_biomass_abs_diff = central$average_biomass_abs_diff,
                              total_average_biomass_rounding_bound = central$report$average_biomass_rounding,
                              central_rep_sections_checked = paste(central$report$checked_sections, collapse = "|"),
                              unfished_msy_rep_sections_complete = central$report$full_unfished_msy_sections,
                              source_par_sha256 = before[1L], report_sha256 = sha256(report), complete_rep_checked = replay_aspm,
                              source_inputs_unchanged = TRUE), "native-check.csv", row.names = FALSE)
  cat(row$case, ": original objective, dimensions and observed zero counters checked; preserved files unchanged", if (replay_aspm) "; complete REP checksum checked" else "", ".\n", sep = "")
}
diagnostic_run <- function(prepared, refit = FALSE) {
  check_files(prepared$output, prepared$files)
  old <- setwd(prepared$output); on.exit(setwd(old), add = TRUE)
  script <- if (refit) "doitall.sh" else "run-final"
  status <- suppressWarnings(system2("sh", shQuote(script), stdout = "reader-native.log", stderr = "reader-native.log", timeout = if (refit) 0L else 600L))
  need(status == 0L, "Diagnostic native script failed; inspect reader-native.log")
  check_files(prepared$output, prepared$files)
  regular("11.par")
  if (!refit) {
    numeric_file("11.par")
    count <- scalar("11.par", "The number of parameters")
    need(count == scalar(prepared$row$source_par, "The number of parameters"), "Diagnostic active parameter count changed")
    logged <- native_log("mfcl-final.log", count)
    expected <- scalar(prepared$row$source_par, "Objective function value")
    need(max(abs(c(scalar("11.par", "Objective function value"), logged$objective) - expected)) <= 1e-6, "Diagnostic objective differs")
    central <- check_report("plot-11.par.rep", prepared$row$source_par, prepared$row, prepared$reference)
    utils::write.csv(data.frame(case = prepared$row$case, function_evaluation_ceiling = 1L,
      observed_native_parameters = logged$parameters, observed_iteration = logged$iteration,
      observed_function_counter = logged$function_counter, native_counter_records = logged$counter_records,
      native_ceiling_records = logged$ceiling_records, validation_scope = central$scope,
      complete_rep_checked = TRUE, source_inputs_unchanged = TRUE), "native-check.csv", row.names = FALSE)
  }
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
  expected <- paste0(prefix, c("run-final.R", "Makefile", "MODELS.csv", "FILES.csv", "native.tar.xz", "CONTENTS.sha256", "README.md", "source-manifest.json", "REFERENCE.rds"))
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
