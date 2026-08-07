#!/usr/bin/env python3
"""Submit the repository-contained BET 2026 Diagnostic report to Kflow."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


TASK = "ofp-sam-bet-2026-diagnostic-report"
REPO = "PacificCommunity/ofp-sam-bet-2026-diagnostic"
TASK_DISPLAY_NAME = "BET 2026 Diagnostic report"
LOCAL_HOST = "kflow-local-kyuhank-nc240124"
SUVA_HOST = "suva"
IMAGE = (
    "ghcr.io/pacificcommunity/tuna-flow:v2.5@"
    "sha256:c87f1f6d9d4f62dc447844b58afe35f96af175bf933cb6cffbbbe39a59172360"
)
FLR4MFCL_REF = "ff8367fcec19baff98333170c0f1bca3f9903029"
MFCLKIT_REF = "cf786007b5261f84faac8f3d24f7084bd323119d"
MFCLSHINY_REF = "a8dffd78de61c99af8cf5b1f6995e861157dc96c"
RUNTIME_PACKAGES = (
    f"FLR4MFCL=PacificCommunity/ofp-sam-flr4mfcl@{FLR4MFCL_REF},"
    f"mfclkit=PacificCommunity/ofp-sam-mfclkit@{MFCLKIT_REF},"
    f"mfclshiny=PacificCommunity/mfclshiny@{MFCLSHINY_REF}"
)


class Kflow:
    def __init__(self, url: str, token: str) -> None:
        self.url = url.rstrip("/")
        self.token = token

    def request(self, method: str, path: str, payload: dict | None = None) -> dict:
        body = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            self.url + path,
            data=body,
            method=method,
            headers={"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            raise RuntimeError(f"Kflow API {error.code}: {detail}") from error


def job_number(job: dict) -> int | None:
    try:
        return int(job.get("job_number", job.get("run_number")))
    except (TypeError, ValueError):
        return None


def build_payload(branch: str, dpi: int, site: str) -> dict:
    remote_host = SUVA_HOST if site == "suva" else LOCAL_HOST
    title = "BET 2026 Diagnostic model report"
    description = (
        "Public report for Diagnostic Job 22974 with model fit, diagnostic checks, "
        "supported Hessian intervals and a self-contained likelihood-profile viewer."
    )
    artifacts = [
        {
            "path": "diagnostic-report-output/bet-2026-diagnostic-report.html",
            "label": "BET 2026 Diagnostic model report",
            "render": True,
        },
        {
            "path": "diagnostic-report-output/viewer/bet-2026-likelihood-profile-viewer.html",
            "label": "Likelihood-profile viewer",
            "render": True,
        },
        {
            "path": "diagnostic-report-output/latex-table-validation.pdf",
            "label": "LaTeX table validation",
            "render": True,
        },
    ]
    return {
        "repo": REPO,
        "branch": branch,
        "docker_image": IMAGE,
        "batch_name": f"bet-2026-diagnostic-report-{site}",
        "remote_user": "kyuhank",
        "remote_host": remote_host,
        "remote_base_dir": "/home/kyuhank/KflowOutput",
        "input_jobs": [],
        "checkout": {
            "mode": "sparse",
            "paths": [
                "diagnostic-report",
                "results/reference/model_payload.rds",
                "model/fishery_map.R",
                "model/tag_rep_map.R",
            ],
        },
        "output_patterns": ["diagnostic-report-output/**"],
        "artifacts": artifacts,
        "cpus": 2,
        "memory": "8GB",
        "disk": "40GB",
        "slot_requirements": (
            'regexp("^suvofp", Machine)'
            if site == "suva"
            else f'regexp("^{LOCAL_HOST}$", Machine)'
        ),
        "env": {
            "JOB_TITLE": title,
            "JOB_DESCRIPTION": description,
            "MODEL_JOB": "22974",
            "REPORT_OUTPUT_DIR": "diagnostic-report-output",
            "DIAGNOSTIC_REPORT_DPI": str(dpi),
            "FLOW_SPECIES": "BET",
            "FLOW_SPECIES_LABEL": "bigeye tuna",
            "FLOW_ASSESSMENT_YEAR": "2026",
            "FLR4MFCL_GITHUB_REF": FLR4MFCL_REF,
            "MFCLKIT_GITHUB_REF": MFCLKIT_REF,
            "MFCLSHINY_GITHUB_REF": MFCLSHINY_REF,
            "KFLOW_RUNTIME_PACKAGES": RUNTIME_PACKAGES,
            "KFLOW_REPO_RUNTIME_PACKAGES": RUNTIME_PACKAGES,
            "KFLOW_REPO_RUNTIME_UPDATE": "always",
            "KFLOW_RUNTIME_UPDATE": "always",
            "TUNA_FLOW_RUNTIME_UPDATE": "always",
            "KFLOW_RUNTIME_UPDATE_INTERVAL_HOURS": "0",
            "KFLOW_RUNTIME_REQUIRE_PRIVATE_PACKAGES": "true",
            "KFLOW_RUNTIME_GITHUB_AUTH": "true",
            "KFLOW_FORWARD_GITHUB_TOKEN_TO_RUNTIME": "true",
        },
        "tags": {
            "stage": "diagnostic-model-report",
            "species": "BET",
            "assessment_year": "2026",
            "source_model_job": "22974",
            "execution": site,
        },
        "metadata": {
            "input_jobs_override": True,
            "source_model_job": 22974,
            "source_hessian_job": 22020,
            "raw_hessian_restore_job": 22196,
            "source_model_policy": "repository-compact-payload",
            "job_title": title,
            "job_description": description,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--branch", default="main")
    parser.add_argument("--dpi", type=int, default=400)
    parser.add_argument("--site", choices=("local", "suva"), default="local")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--api-url", default=os.getenv("KFLOW_API_URL", "http://127.0.0.1:8089"))
    args = parser.parse_args()

    payload = build_payload(args.branch, args.dpi, args.site)
    if args.dry_run:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    token = os.getenv("KFLOW_API_TOKEN", "").strip()
    if not token:
        raise RuntimeError("KFLOW_API_TOKEN is required.")
    api = Kflow(args.api_url, token)
    task_payload = {
        "name": TASK_DISPLAY_NAME,
        "description": "Public paper-ready Diagnostic model report and likelihood-profile viewer.",
        "repo": REPO,
        "branch": args.branch,
        "make_target": "all",
        "command": "bash diagnostic-report/run.sh",
        "docker_image": IMAGE,
        "remote_user": "kyuhank",
        "remote_host": payload["remote_host"],
        "remote_base_dir": "/home/kyuhank/KflowOutput",
        "cpus": 2,
        "memory": "8GB",
        "disk": "40GB",
        "slot_requirements": payload["slot_requirements"],
        "output_patterns": ["diagnostic-report-output/**"],
        "artifacts": payload["artifacts"],
        "env": payload["env"],
        "checkout": payload["checkout"],
        "tags": {"stage": "diagnostic-model-report", "species": "BET", "assessment_year": "2026"},
        "metadata": {
            "internal_task": False,
            "task_visibility": "primary",
            "task_role": "diagnostic-model-report",
            "execution": args.site,
        },
    }
    # Register on every submission so the task-level scheduler constraint is
    # switched with --site.  A stale task constraint would otherwise combine
    # a Local-machine requirement with the Suva job requirement, leaving the
    # Condor job permanently unmatched.
    api.request("POST", f"/api/report/{TASK}", task_payload)

    response = api.request("POST", f"/api/job/{TASK}", payload)
    job = response.get("job", response)
    print(f"Submitted Kflow {args.site.title()} report Job #{job_number(job)} ({job.get('status')}).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, urllib.error.URLError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
