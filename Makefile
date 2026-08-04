.PHONY: all report

# Kflow's standard report runner invokes `make all`.  Keep the report
# checkout self-contained while delegating the actual build to the
# paper-ready diagnostic report script.
all: report

report:
	bash diagnostic-report/run.sh
