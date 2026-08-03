#!/usr/bin/env python3
"""Submit one completed BET Diagnostic model job for a paper-ready report."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


TASK = "ofp-sam-bet-2026-diagnostic-model-report"
REPO = "PacificCommunity/ofp-sam-bet-2026-diagnostic"
IMAGE = (
    "ghcr.io/pacificcommunity/tuna-flow:v2.5@"
    "sha256:c87f1f6d9d4f62dc447844b58afe35f96af175bf933cb6cffbbbe39a59172360"
)
FLR4MFCL_REF = "ff8367fcec19baff98333170c0f1bca3f9903029"
MFCLKIT_REF = "cf786007b5261f84faac8f3d24f7084bd323119d"
MFCLSHINY_REF = "542ac93b7ce0b6d0df70301891e668701d439857"


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model_job")
    parser.add_argument("--branch", default="main")
    parser.add_argument("--dpi", type=int, default=300)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--api-url", default=os.getenv("KFLOW_API_URL", "http://127.0.0.1:8089"))
    args = parser.parse_args()

    token = os.getenv("KFLOW_API_TOKEN", "").strip()
    if not token:
        raise RuntimeError("KFLOW_API_TOKEN is required.")
    api = Kflow(args.api_url, token)
    response = api.request("GET", f"/api/job/{args.model_job.lstrip('#')}")
    model = response.get("job", response)
    status = str(model.get("status") or "").lower()
    if status not in {"completed", "success"}:
        raise RuntimeError(f"Model job #{args.model_job} is {status or 'unknown'}, not completed.")
    source_number = job_number(model)
    source_id = str(model.get("id") or "")
    if source_number is None or not source_id:
        raise RuntimeError("The source job is missing its Kflow number or internal id.")

    provenance = {
        "model_job": source_number,
        "model_job_id": source_id,
        "model_report_code": model.get("report_code", ""),
        "model_repo": model.get("repo", ""),
        "model_branch": model.get("branch", ""),
        "model_commit": model.get("commit_hash", model.get("source_version", "")),
    }
    title = f"BET 2026 Diagnostic model report | Job #{source_number}"
    description = (
        f"Paper-ready report from Diagnostic model Job #{source_number}: model and convergence summary, "
        "objective components, annual/recent stock status, fishery impact, data fits, selectivity, "
        "movement, biology, Hessian QC, Word/LaTeX copy controls, PNG/PDF and CSV outputs."
    )
    payload = {
        "repo": REPO,
        "branch": args.branch,
        "docker_image": IMAGE,
        "batch_name": f"bet-2026-diagnostic-report-job-{source_number}",
        "remote_user": "kyuhank",
        "remote_host": "suva",
        "remote_base_dir": "/home/kyuhank/KflowOutput",
        "input_jobs": [source_id],
        "output_patterns": ["diagnostic-report-output/**"],
        "cpus": 4,
        "memory": "16GB",
        "disk": "30GB",
        "env": {
            "JOB_TITLE": title,
            "JOB_DESCRIPTION": description,
            "MODEL_JOB": str(source_number),
            "KFLOW_JOB_PROVENANCE": json.dumps(provenance, separators=(",", ":")),
            "REPORT_OUTPUT_DIR": "diagnostic-report-output",
            "DIAGNOSTIC_REPORT_DPI": str(args.dpi),
            "FLOW_SPECIES": "BET",
            "FLOW_SPECIES_LABEL": "bigeye tuna",
            "FLOW_ASSESSMENT_YEAR": "2026",
            "FLR4MFCL_GITHUB_REF": FLR4MFCL_REF,
            "MFCLKIT_GITHUB_REF": MFCLKIT_REF,
            "MFCLSHINY_GITHUB_REF": MFCLSHINY_REF,
            "KFLOW_RUNTIME_GITHUB_AUTH": "true",
            "KFLOW_FORWARD_GITHUB_TOKEN_TO_RUNTIME": "true",
        },
        "tags": {
            "stage": "diagnostic-model-report",
            "species": "BET",
            "assessment_year": "2026",
            "source_model_job": str(source_number),
        },
        "metadata": {
            "input_jobs_override": True,
            "source_model_job": provenance,
            "job_title": title,
            "job_description": description,
            "source_model_policy": "staged-job-only",
        },
    }
    if args.dry_run:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    task_payload = {
            "name": "BET 2026 Diagnostic model report",
            "description": "Paper-ready report generated from exactly one staged BET Diagnostic model job.",
            "repo": REPO,
            "branch": args.branch,
            "make_target": "all",
            "docker_image": IMAGE,
            "remote_user": "kyuhank",
            "remote_host": "suva",
            "remote_base_dir": "/home/kyuhank/KflowOutput",
            "cpus": 4,
            "memory": "16GB",
            "disk": "30GB",
            "output_patterns": ["diagnostic-report-output/**"],
            "tags": {"stage": "diagnostic-model-report", "species": "BET", "assessment_year": "2026"},
            "metadata": {"internal_task": False, "task_visibility": "primary", "task_role": "diagnostic-model-report"},
        }
    try:
        api.request("POST", f"/api/report/{TASK}", task_payload)
    except RuntimeError as error:
        if "Kflow API 409" not in str(error) and "already exists" not in str(error).lower():
            raise
    response = api.request("POST", f"/api/job/{TASK}", payload)
    job = response.get("job", response)
    print(f"Submitted report Job #{job_number(job)} from Diagnostic model Job #{source_number} ({job.get('status')}).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, urllib.error.URLError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
