options(stringsAsFactors = FALSE)

template_file <- file.path("diagnostic-report", "likelihood-profile-viewer-template.html")
if (!file.exists(template_file)) stop("Missing likelihood-profile viewer template.", call. = FALSE)
template <- paste(readLines(template_file, warn = FALSE), collapse = "\n")

marker_count <- function(marker) {
  sum(gregexpr(marker, template, fixed = TRUE)[[1L]] >= 0L)
}
if (marker_count("__VIEWER_DATA__") != 1L || marker_count("__SPC_LOGO__") != 1L ||
    marker_count("__MFCLSHINY_LOGO__") != 1L) {
  stop("The viewer must retain exactly one data and one marker for each logo.", call. = FALSE)
}
for (required in c(
  "Select all", "Clear all", "parentComponent", "parentGroup", "detail-panel",
  "detail-actions", "each curve minimum = 0",
  "Tag opens programme totals", "Download plotted CSV",
  "Kyuhan Kim", "kyuhank@spc.int"
)) {
  if (!grepl(required, template, fixed = TRUE)) {
    stop("Viewer is missing required element: ", required, call. = FALSE)
  }
}
for (forbidden in c("data-tier=", "fitted = 1", "Diagnostic fitted baseline", "base-dot", "fit-line")) {
  if (grepl(forbidden, template, fixed = TRUE)) {
    stop("Viewer retains obsolete fitted-baseline UI: ", forbidden, call. = FALSE)
  }
}
for (forbidden in c("/home/", "corp.spc.int", "ghp_", "github_pat_", "JOB[0-9]", "Job [0-9]")) {
  if (grepl(forbidden, template, fixed = TRUE)) {
    stop("Viewer template contains non-public text: ", forbidden, call. = FALSE)
  }
}

chrome <- Sys.which("google-chrome")
if (!nzchar(chrome)) {
  cat("Validated likelihood-profile viewer template markers and public-safe content (browser smoke test skipped: Google Chrome unavailable).\n")
  quit(save = "no")
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite is required for the likelihood-profile viewer browser smoke test.", call. = FALSE)
}

curve_rows <- function(id, label, values, is_total = FALSE, colour = NULL) {
  lapply(seq_along(values), function(index) {
    list(
      id = id, label = label, x = c(0.9, 1, 1.1)[[index]], y = values[[index]],
      is_total = is_total, colour = colour
    )
  })
}
payload <- list(
  title = "Viewer smoke test",
  groups = list(
    list(
      key = "broad", label = "Broad components", kind = "broad",
      curves = c(
        curve_rows("total", "Total", c(30, 0, 15), TRUE, "#073c5b"),
        curve_rows("cpue", "CPUE", c(8, 10, 13), FALSE, "#0072B2"),
        curve_rows("lf", "LF", c(9, 13, 14), FALSE, "#D55E00"),
        curve_rows("caal", "CAAL", c(7, 9, 12), FALSE, "#6A5AA7"),
        curve_rows("tag", "Tag", c(5, 8, 8), FALSE, "#009E73"),
        curve_rows("penalty", "Penalty", c(4, 7, 9), FALSE, "#6B7280")
      )
    ),
    list(
      key = "cpue", label = "CPUE indices", kind = "detail",
      parent_component = "CPUE", panel = "CPUE indices",
      curves = c(
        curve_rows("total", "CPUE total", c(12, 0, 8), TRUE, "#073c5b"),
        # This offset is intentional: the child must still plot from its own zero.
        curve_rows("index-a", "Index A", c(100, 101, 105), FALSE, "#ca6b26")
      )
    ),
    list(
      key = "tag-programmes", label = "Tag programmes", kind = "detail",
      parent_component = "Tag", panel = "Tag programme totals",
      curves = c(
        curve_rows("total", "Tag total", c(8, 0, 6), TRUE, "#073c5b"),
        curve_rows("program-a", "Program A total", c(5, 1, 4), FALSE, "#168a72")
      )
    ),
    list(
      key = "tag-program-a", label = "Program A release groups", kind = "detail",
      parent_group = "tag-programmes", parent_curve = "Program A total",
      panel = "Tag release groups — Program A",
      curves = c(
        curve_rows("total", "Tag total — Program A", c(5, 0, 4), TRUE, "#073c5b"),
        curve_rows("release-a", "Release A", c(4, 2, 3), FALSE, "#2874b9")
      )
    )
  )
)
probe <- paste0(
  "<script>(function(){",
  "var overview=document.getElementById('selected-count').textContent+'|'+document.getElementById('plot-status').textContent;",
  "var toggle=[].slice.call(document.querySelectorAll('.detail-toggle')).filter(function(x){return x.textContent.indexOf('CPUE indices')===0})[0];toggle.click();",
  "var labels=function(){return [].slice.call(document.querySelectorAll('label.curve'))};",
  "labels().filter(function(x){return x.textContent.indexOf('Index A')===0})[0].querySelector('input').click();",
  "var parent=[].slice.call(document.querySelectorAll('.detail-total')).some(function(x){return x.textContent.indexOf('CPUE total')===0});",
  "var path=[].slice.call(document.querySelectorAll('path')).filter(function(x){return x.getAttribute('stroke')==='#ca6b26'})[0];",
  "var ownMinimum=path&&/,415\\.00(?: |$)/.test(path.getAttribute('d'));",
  "var tagToggle=[].slice.call(document.querySelectorAll('.detail-toggle')).filter(function(x){return x.textContent.indexOf('Tag programme totals')===0})[0];tagToggle.click();",
  "var tagOpenToggle=[].slice.call(document.querySelectorAll('.detail-toggle')).filter(function(x){return x.textContent.indexOf('Tag programme totals')===0})[0];",
  "var tagPanel=tagOpenToggle.closest('.detail-panel');tagPanel.querySelector('.detail-actions button').click();",
  "var nestedToggle=[].slice.call(document.querySelectorAll('.detail-toggle')).filter(function(x){return x.textContent.indexOf('Tag release groups')===0})[0];",
  "var nested=Boolean(nestedToggle);if(nestedToggle)nestedToggle.click();",
  "var localActions=document.querySelectorAll('.detail-actions').length;",
  "var result=document.createElement('p');result.id='viewer-smoke-result';",
  "result.textContent='SMOKE '+overview+' parent='+parent+' ownMinimum='+ownMinimum+' nested='+nested+' actions='+localActions+' panels='+document.querySelectorAll('.detail-grid .chart-card').length;",
  "document.body.appendChild(result);",
  "})();</script>"
)
viewer_html <- sub("__SPC_LOGO__", "data:image/svg+xml,", template, fixed = TRUE)
viewer_html <- sub("__MFCLSHINY_LOGO__", "data:image/svg+xml,", viewer_html, fixed = TRUE)
viewer_html <- sub(
  "__VIEWER_DATA__", jsonlite::toJSON(payload, auto_unbox = TRUE, dataframe = "rows"),
  viewer_html, fixed = TRUE
)
viewer_html <- sub("</body>", paste0(probe, "</body>"), viewer_html, fixed = TRUE)
viewer_file <- tempfile("likelihood-profile-viewer-", fileext = ".html")
chrome_dir <- tempfile("likelihood-profile-viewer-chrome-")
writeLines(viewer_html, viewer_file, useBytes = TRUE)
dir.create(chrome_dir)
on.exit(unlink(c(viewer_file, chrome_dir), recursive = TRUE, force = TRUE), add = TRUE)
browser_output <- system2(
  chrome,
  c(
    "--headless=new", "--no-sandbox", "--disable-gpu", paste0("--user-data-dir=", chrome_dir),
    "--dump-dom", paste0("file://", viewer_file)
  ),
  stdout = TRUE, stderr = TRUE
)
browser_document <- paste(browser_output, collapse = "\n")
result_match <- regexec(
  "<p id=\"viewer-smoke-result\">([^<]+)</p>", browser_document, perl = TRUE
)
result <- regmatches(browser_document, result_match)[[1L]]
if (length(result) >= 2L) result <- result[[2L]] else result <- character()
expected <- "SMOKE 6 selected|6 broad · 0 detail panels parent=true ownMinimum=true nested=true actions=3 panels=3"
if (!length(result) || !grepl(expected, result, fixed = TRUE)) {
  stop(
    "Likelihood-profile browser smoke test failed: ",
    paste(result, collapse = " "),
    call. = FALSE
  )
}
cat("Validated nested broad/detail selection, per-level actions, detail-panel totals, own-minimum ΔNLL and public-safe viewer template.\n")
