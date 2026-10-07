.PHONY: all report

# Kflow's standard report runner invokes `make all`.  Keep the report
# checkout self-contained while delegating the actual build to the
# paper-ready diagnostic report script.
all: report

report:
	bash diagnostic-report/run.sh

# Reader entry points. Existing all/report targets above are retained.
.DEFAULT_GOAL := help
CASE ?= profiles
OUT ?=
RSCRIPT ?= Rscript
export CASE OUT ARCHIVE
.PHONY: help list verify prepare rerun refit profiles aspm restore hessian hessian-verify

help:
	@printf '%s\n' 'make verify                         Check saved inputs and results with base R' 'make list                           List Diagnostic/profile/ASPM source cases' 'make hessian CASE=diagnostic OUT=/absolute/bet-hessian' 'make prepare OUT=/tmp/bet-inputs     Copy ordinary Diagnostic MFCL files' 'make rerun OUT=/tmp/bet-final        Regenerate five original REP files' 'make refit OUT=/tmp/bet-refit        New full fit from original inputs' 'make profiles CASE=profiles OUT=/tmp/bet-profile' 'make aspm CASE=constant OUT=/tmp/bet-aspm' 'make restore CASE=profile-75 OUT=/tmp/bet-profile-inputs' 'Readers need Make, base R, tar/XZ, stat and SHA-256 tools; no Python.' 'MFCL runs require Linux x86-64; choose a new OUT each time.'

list:
	@"$(RSCRIPT)" reproduce/run-final.R list

verify:
	@"$(RSCRIPT)" reproduce/run-final.R verify
	@"$(RSCRIPT)" reproduce/hessian.R --verify

prepare rerun refit:
	@"$(RSCRIPT)" reproduce/run-final.R "$@" diagnostic "$$OUT"

profiles aspm restore:
	@"$(RSCRIPT)" reproduce/run-final.R "$@" "$$CASE" "$$OUT"

hessian:
	@if [ -n "$$ARCHIVE" ]; then \
		"$(RSCRIPT)" reproduce/hessian.R --case "$$CASE" --out "$$OUT" --archive "$$ARCHIVE"; \
	else \
		"$(RSCRIPT)" reproduce/hessian.R --case "$$CASE" --out "$$OUT"; \
	fi

hessian-verify:
	@if [ -n "$$ARCHIVE" ]; then \
		"$(RSCRIPT)" reproduce/hessian.R --verify --case "$$CASE" --archive "$$ARCHIVE"; \
	else \
		"$(RSCRIPT)" reproduce/hessian.R --verify; \
	fi

.PHONY: verify-source
verify: verify-source
verify-source:
	@sha256sum --quiet -c ci/PRESERVED.sha256
