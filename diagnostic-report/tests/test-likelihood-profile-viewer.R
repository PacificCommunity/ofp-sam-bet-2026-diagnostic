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
  "Select all", "Clear all", "parentComponent", "detail-panel",
  "detail-actions", "each curve minimum = 0",
  "parentGroup", "parentProfile", "nested-details",
  "LF and CAAL first show region totals", "Tag first shows programme totals",
  "Chart added below",
  "Total average biomass (10³ t)",
  "Download plotted CSV",
  "Kyuhan Kim", "kyuhank@spc.int"
)) {
  if (!grepl(required, template, fixed = TRUE)) {
    stop("Viewer is missing required element: ", required, call. = FALSE)
  }
}
for (forbidden in c(
  "data-tier=", "fitted = 1", "Diagnostic fitted baseline", "base-dot",
  "fit-line", "Relative total average biomass", "relative_value",
  "Total average biomass / fitted value"
)) {
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
      id = id, label = label, x = c(850, 960, 1100)[[index]], y = values[[index]],
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
      key = "lf-regions", label = "LF regions", kind = "detail",
      parent_component = "LF", panel = "LF region totals",
      curves = c(
        curve_rows("total", "LF total", c(9, 0, 6), TRUE, "#073c5b"),
        curve_rows("region-1", "Region 1", c(6, 1, 5), FALSE, "#D55E00")
      )
    ),
    list(
      key = "lf-region-1", label = "Region 1 LF data", kind = "detail",
      parent_component = "LF", parent_group = "lf-regions",
      parent_profile = "region-1", panel = "Region 1 LF fisheries",
      curves = c(
        curve_rows("total", "Region 1 LF total", c(6, 1, 5), TRUE, "#073c5b"),
        curve_rows("fishery-1", "Length | Fishery 1", c(4, 0, 3), FALSE, "#D55E00")
      )
    ),
    list(
      key = "caal-regions", label = "CAAL regions", kind = "detail",
      parent_component = "CAAL", panel = "CAAL regions",
      curves = c(
        curve_rows("total", "CAAL total", c(7, 0, 5), TRUE, "#073c5b"),
        curve_rows("region-1", "Region 1", c(5, 1, 4), FALSE, "#6A5AA7")
      )
    ),
    list(
      key = "caal-region-1-fisheries", label = "Region 1 CAAL fisheries",
      kind = "detail", parent_component = "CAAL",
      parent_group = "caal-regions", parent_profile = "region-1",
      panel = "Region 1 CAAL fisheries",
      curves = c(
        curve_rows("total", "Region 1 CAAL total", c(5, 1, 4), TRUE, "#073c5b"),
        curve_rows("fishery-1", "Fishery 1", c(3, 0, 2), FALSE, "#6A5AA7")
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
      key = "tag-program-a-release-groups", label = "Program A release groups",
      kind = "detail", parent_component = "Tag",
      parent_group = "tag-programmes", parent_profile = "program-a",
      panel = "Program A release groups",
      curves = c(
        curve_rows("total", "Program A total", c(5, 1, 4), TRUE, "#073c5b"),
        curve_rows("group-1", "Group 1 | Region 2 | 1990 Q3", c(3, 0, 2), FALSE, "#b83d55"),
        curve_rows("group-2", "Group 2 | Region 2 | 1991 Q1", c(2, 1, 2), FALSE, "#2874b9")
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
  "tagPanel.querySelectorAll('.detail-actions button')[1].click();",
  "var releaseToggle=[].slice.call(document.querySelectorAll('.nested-details .detail-toggle')).filter(function(x){return x.textContent.indexOf('Program A release groups')===0})[0];releaseToggle.click();",
  "var lfToggle=[].slice.call(document.querySelectorAll('.detail-toggle')).filter(function(x){return x.textContent.indexOf('LF region totals')===0})[0];lfToggle.click();",
  "var lfNested=[].slice.call(document.querySelectorAll('.nested-details .detail-toggle')).filter(function(x){return x.textContent.indexOf('Region 1 LF fisheries')===0})[0];lfNested.click();",
  "var caalToggle=[].slice.call(document.querySelectorAll('.detail-toggle')).filter(function(x){return x.textContent.indexOf('CAAL regions')===0})[0];caalToggle.click();",
  "var caalNested=[].slice.call(document.querySelectorAll('.nested-details .detail-toggle')).filter(function(x){return x.textContent.indexOf('Region 1 CAAL fisheries')===0})[0];caalNested.click();",
  "var nested=document.querySelectorAll('.nested-details .detail-toggle').length;",
  "var nestedIds=['tag-program-a-release-groups','lf-region-1','caal-region-1-fisheries'];var nestedChart=nestedIds.every(function(id){return [].slice.call(document.querySelectorAll('.detail-grid .chart-card')).some(function(x){return x.getAttribute('data-group-id')===id})});",
  "var totalLines=document.querySelectorAll('.detail-grid .curve-line.total').length;",
  "var absoluteAxis=[].slice.call(document.querySelectorAll('.axis-label')).some(function(x){return x.textContent==='Total average biomass (10³ t)'});",
  "var localActions=document.querySelectorAll('.detail-actions').length;",
  "var result=document.createElement('p');result.id='viewer-smoke-result';",
  "result.textContent='SMOKE '+overview+' parent='+parent+' ownMinimum='+ownMinimum+' nested='+nested+' nestedChart='+nestedChart+' totals='+totalLines+' absoluteAxis='+absoluteAxis+' actions='+localActions+' panels='+document.querySelectorAll('.detail-grid .chart-card').length;",
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
expected <- "SMOKE 6 selected|6 broad · 0 detail panels parent=true ownMinimum=true nested=3 nestedChart=true totals=7 absoluteAxis=true actions=7 panels=7"
if (!length(result) || !grepl(expected, result, fixed = TRUE)) {
  stop(
    "Likelihood-profile browser smoke test failed: ",
    paste(result, collapse = " "),
    call. = FALSE
  )
}
cat("Validated nested LF/CAAL fishery and Tag release-group selection, visible panel placement, persistent detail totals, absolute biomass axis, own-minimum ΔNLL and public-safe viewer template.\n")
