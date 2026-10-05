.PHONY: all report

# Kflow's standard report runner invokes `make all`.  Keep the report
# checkout self-contained while delegating the actual build to the
# paper-ready diagnostic report script.
all: report

report:
	bash diagnostic-report/run.sh

# Reader entry points. Existing all/report targets above are retained.
CASE ?= profiles
OUT ?=
export CASE OUT
.PHONY: help verify prepare rerun refit profiles aspm restore _check-output

help:
	@printf '%s\n' 'make verify                         Check saved inputs and results' 'make hessian CASE=diagnostic OUT=/absolute/bet-hessian' 'make rerun OUT=/tmp/bet-final        Regenerate five original REP files' 'make refit OUT=/tmp/bet-refit        Full fit from original inputs' 'make profiles CASE=profiles OUT=/tmp/bet-profile' 'make aspm CASE=constant OUT=/tmp/bet-aspm' 'make restore CASE=profile-75 OUT=/tmp/bet-inputs' 'MFCL runs require Linux x86-64; choose a new OUT each time.'

verify:
	python3 reproduce/hessian.py --verify
	./verify
	python3 ci/verify-preserved-files.py
	python3 ci/verify-mfcl-files.py
	python3 reproduce/restore.py --verify

prepare: verify _check-output
	@python3 -c 'import os,sys; from pathlib import Path; sys.path.insert(0,"reproduce"); import restore; names=("bet.age_length","bet.frq","bet.ini","bet.reg_scaling","bet.tag","mfcl.cfg","mfclo64","doitall.sh","final.par","run-final"); files={n:((Path("MFCL")/n).read_bytes(),0o755 if n in ("mfclo64","doitall.sh","run-final") else 0o644) for n in names}; restore.save_files(Path(os.environ["OUT"]),files,"diagnostic-working-copy")'

rerun: prepare
	@case "$$(uname -s):$$(uname -m)" in Linux:x86_64|Linux:amd64) ;; *) echo 'MFCL requires Linux x86-64.' >&2; exit 2;; esac
	@cd "$$OUT" && ./run-final

refit: prepare
	@case "$$(uname -s):$$(uname -m)" in Linux:x86_64|Linux:amd64) ;; *) echo 'MFCL requires Linux x86-64.' >&2; exit 2;; esac
	@cd "$$OUT" && ./doitall.sh

profiles: _check-output
	python3 reproduce/run-native.py "$$CASE" "$$OUT"

aspm: _check-output
	python3 reproduce/replay-aspm.py "$$CASE" "$$OUT"

restore: _check-output
	python3 reproduce/restore.py "$$CASE" "$$OUT"

_check-output:
	@python3 -c 'import os; from pathlib import Path; raw=os.environ.get("OUT", ""); p=Path(raw); root=Path.cwd().resolve(); assert raw and p.is_absolute(), "Set OUT to an absolute, new directory"; assert not os.path.lexists(p), "OUT already exists; choose a new directory"; q=p.resolve(); assert q != root and (root not in q.parents or root/"outputs" in q.parents), "OUT inside the checkout must be beneath outputs/"'

# Install the helper, manifest and offline tests in reproduce/.
export CASE OUT ARCHIVE
.PHONY: hessian hessian-verify

hessian:
	@if [ -n "$$ARCHIVE" ]; then \
		python3 reproduce/hessian.py --case "$$CASE" --out "$$OUT" --archive "$$ARCHIVE"; \
	else \
		python3 reproduce/hessian.py --case "$$CASE" --out "$$OUT"; \
	fi

hessian-verify:
	@if [ -n "$$ARCHIVE" ]; then \
		python3 reproduce/hessian.py --verify --case "$$CASE" --archive "$$ARCHIVE"; \
	else \
		python3 reproduce/hessian.py --verify; \
	fi
