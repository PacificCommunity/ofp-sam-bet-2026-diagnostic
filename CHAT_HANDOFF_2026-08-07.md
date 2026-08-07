# Diagnostic report handoff — 7 August 2026

## Current state

The public diagnostic report and the likelihood-profile viewer are being finalised in this repository.  The current worktree changes are deliberate and limited to:

- `diagnostic-report/R/build_report.R`
- `diagnostic-report/R/prepare_public_payload.R`
- `diagnostic-report/likelihood-profile-viewer-template.html` (new)
- `model/fishery_map.R`

Do not add `diagnostic-report/__pycache__/` to version control.

## Completed in the current worktree

- The report reloads the checked-in fishery map so its public tables use the final diagnostic configuration: all 33 selectivities are independent; the only relevant weak monotonicity constraints are for fisheries 10 and 33.
- Public fishery display labels align the suffix with the model region (for example, `.WEST.3` and `.EAST.4`) without changing frozen model input names.
- The likelihood-profile report and viewer now include the original fitted model point at biomass ratio 1.0.  Profile curves are shown as Delta negative log likelihood from each curve's own minimum, rather than being forced to share the total-objective minimum.
- The viewer supports broad components and detailed CPUE, length-frequency, CAAL-by-region, tag-release and penalty curves.  Detailed views include an optional summed component, searchable multi-select controls, clean line-only plots and the developer contact in the interface.
- The report selection requests three-column age panels, two-column quarterly movement panels, and includes the juvenile/adult fishing-mortality figure.  Static dynamic panels start their y axis at zero; the depletion LRP is 0.20.
- The ASPM comparison is being simplified to one solid line labelled `ASPM`.

## Still to complete before the final release render

1. Add genuine annual fishing-mortality estimation intervals.  This requires a derivative evaluation using the *same* Hessian provenance as the existing biomass, spawning-potential and recruitment intervals.  Do not claim Hessian uncertainty for annual F until this has completed; do not mix the alternative Hessian file found under `final-run-release-check`.
2. Render and inspect the report after the F update, paying particular attention to the profile-viewer baseline, All-regions facets, 3-by-2 age layouts, and captions/LaTeX table exports.
3. Submit the final render to Kflow Local.  A current-worktree render has been requested for Suva separately while finalisation continues.
4. Upload `bet-2026-likelihood-profile-viewer.html` to the GitHub release using the same asset name.  The stable public URL is:
   `https://github.com/PacificCommunity/ofp-sam-bet-2026-diagnostic/releases/latest/download/bet-2026-likelihood-profile-viewer.html`
   Keeping the filename unchanged means the link resolves to the newest release asset.

## Kflow and CI notes

- An earlier Local Kflow job remained queued because the submission constraint used an obsolete host name.  Verify that the local constraint targets `NC240124` before final Local submission.
- Before pushing, run `./verify`.  If `model/fishery_map.R` is the only checksum failure, update only its corresponding line in `model/MANIFEST.sha256` after reviewing the final map.
- The prior GitHub Actions failure was the frozen-file verification job.  Re-run the verification workflow after the manifest update.

## Public-report guardrails

- Keep the report free of local paths, private host names, temporary URLs, and personal development commentary.
- Keep citations and captions concise and report-oriented; retain mathematical subscripts in HTML/LaTeX exports.
- Current biomass/recruitment/spawning-potential intervals use available Hessian estimation uncertainty.  Annual F presently needs the additional derivative calculation described above.
