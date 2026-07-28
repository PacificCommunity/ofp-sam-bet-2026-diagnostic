#!/usr/bin/env python3
"""Register and submit the complete mfclrtmb MCMC Kflow dependency graph."""

from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import yaml


REPO = "PacificCommunity/ofp-sam-bet-2026-diagnostic"
ROOT = Path(__file__).resolve().parents[2]
MCMC_DIR = ROOT / "mcmc"
CONFIGS = {
    "pack": MCMC_DIR / "kflow-hessian-pack.yaml",
    "chain": MCMC_DIR / "kflow-chain.yaml",
    "merge": MCMC_DIR / "kflow-merge.yaml",
}


class Kflow:
    def __init__(self, base_url: str, token: str, github_token: str = "") -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.github_token = github_token.strip()

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }
        if self.github_token:
            headers["X-GitHub-Token"] = self.github_token
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=body,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"{method} {path} failed: HTTP {error.code}: {detail}"
            ) from error
        return json.loads(raw.decode("utf-8")) if raw else {}


def read_config(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        config = yaml.safe_load(handle) or {}
    if not isinstance(config, dict):
        raise RuntimeError(f"{path} must contain a YAML mapping.")
    return config


def register_task(api: Kflow, config: dict[str, Any], branch: str) -> str:
    name = str(config["name"])
    resources = config.get("resources") or {}
    metadata = dict(config.get("metadata") or {})
    metadata["local_apps"] = config.get("local_apps") or []
    payload = {
        "name": name,
        "description": config.get("description", ""),
        "repo_full_name": REPO,
        "repo": REPO,
        "branch": branch,
        "command": config.get("command"),
        "make_target": config.get("make_target", "all"),
        "target_folder": config.get("target_folder", ""),
        "docker_image": config.get("docker_image"),
        "remote_user": config.get("remote_user"),
        "remote_host": config.get("remote_host"),
        "remote_base_dir": config.get("remote_base_dir"),
        "cpus": resources.get("cpus"),
        "memory": resources.get("memory"),
        "disk": resources.get("disk"),
        "slot_requirements": config.get("slot_requirements", ""),
        "exclude_machines": config.get("exclude_machines", []),
        "exclude_slots": config.get("exclude_slots", []),
        "env": config.get("env", {}),
        "tags": config.get("tags", {}),
        "metadata": metadata,
        "output_patterns": config.get("output_patterns", []),
        "input_jobs": config.get("input_jobs", []),
    }
    api.request("POST", f"/api/report/{name}", payload)
    return name


def job_number(response: dict[str, Any]) -> str:
    job = response.get("job", response)
    value = job.get("job_number") or job.get("number") or job.get("id")
    if value in (None, ""):
        raise RuntimeError(f"Kflow response does not contain a job number: {response}")
    return str(value)


def submit(
    api: Kflow,
    task: str,
    payload: dict[str, Any],
    dry_run: bool,
) -> str:
    if dry_run:
        print(json.dumps({"task": task, "payload": payload}, indent=2))
        return f"DRY-{task}"
    return job_number(api.request("POST", f"/api/job/{task}", payload))


def common_env(args: argparse.Namespace) -> dict[str, str]:
    return {
        "MCMC_SOURCE_JOB": args.source_job,
        "MCMC_MODEL_SELECTOR": args.model_selector,
        "MCMC_ROOT": args.model_root,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-job", required=True)
    parser.add_argument("--hessian-job", default="")
    parser.add_argument(
        "--hessian-pack-job",
        default="",
        help="Reuse an already completed compact Hessian pack instead of submitting one.",
    )
    parser.add_argument("--model-selector", default="")
    parser.add_argument("--model-root", default="")
    parser.add_argument("--preconditioner", choices=("native", "adaptive"), default="native")
    parser.add_argument("--stage", choices=("smoke", "full"), default="full")
    parser.add_argument("--chains", type=int, default=10)
    parser.add_argument("--warmup", type=int, default=100)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--adapt-delta", type=float, default=0.9)
    parser.add_argument("--max-treedepth", type=int, default=10)
    parser.add_argument("--seed", type=int, default=20260728)
    parser.add_argument("--branch", default="main")
    parser.add_argument(
        "--kflow-url",
        default=os.environ.get("KFLOW_URL", "http://127.0.0.1:8089"),
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("KFLOW_API_TOKEN", "").strip()
    if not token and not args.dry_run:
        raise RuntimeError("Set KFLOW_API_TOKEN.")
    github_token = os.environ.get(
        "KFLOW_GITHUB_TOKEN",
        os.environ.get("GITHUB_PAT", os.environ.get("GITHUB_TOKEN", "")),
    )
    if args.preconditioner == "native" and not (
        args.hessian_job or args.hessian_pack_job
    ):
        raise RuntimeError(
            "--hessian-job or --hessian-pack-job is required with native preconditioning."
        )
    if args.chains < 1 or args.warmup < 1 or args.samples < 1:
        raise RuntimeError("chains, warmup, and samples must all be positive.")

    api = Kflow(args.kflow_url, token, github_token)
    configs = {key: read_config(path) for key, path in CONFIGS.items()}
    tasks = {
        key: register_task(api, config, args.branch)
        if not args.dry_run
        else str(config["name"])
        for key, config in configs.items()
    }
    base_env = common_env(args)

    pack_job = args.hessian_pack_job
    if args.preconditioner == "native" and not pack_job:
        pack_payload = {
            "repo": REPO,
            "branch": args.branch,
            "input_jobs": [args.hessian_job],
            "env": base_env,
            "batch_name": f"job{args.source_job}-mfclrtmb-hessian-pack",
            "tags": {
                "species": "BET",
                "assessment_year": "2026",
                "stage": "mcmc",
                "check_type": "mcmc-hessian-pack",
                "source_job": args.source_job,
                "base_job": args.source_job,
            },
            "metadata": {
                "internal_task": True,
                "task_visibility": "internal",
                "task_role": "diagnostic-support",
                "base_job": args.source_job,
                "source_hessian_job": args.hessian_job,
                "job_title": f"Job {args.source_job} compact Hessian preconditioner",
            },
        }
        pack_job = submit(api, tasks["pack"], pack_payload, args.dry_run)
        print(f"Hessian pack: #{pack_job}")

    if args.stage == "smoke":
        chains, warmup, samples, max_treedepth = 1, 1, 1, 1
    else:
        chains = args.chains
        warmup = args.warmup
        samples = args.samples
        max_treedepth = args.max_treedepth

    chain_jobs: list[str] = []
    for chain_id in range(1, chains + 1):
        env = {
            **base_env,
            "MCMC_PRECONDITIONER": args.preconditioner,
            "MCMC_CHAIN_ID": str(chain_id),
            "MCMC_TOTAL_CHAINS": str(chains),
            "MCMC_WARMUP": str(warmup),
            "MCMC_SAMPLES": str(samples),
            "MCMC_ADAPT_DELTA": str(args.adapt_delta),
            "MCMC_MAX_TREEDEPTH": str(max_treedepth),
            "MCMC_SEED": str(args.seed),
        }
        inputs = [args.source_job]
        if pack_job:
            inputs.append(pack_job)
        payload = {
            "repo": REPO,
            "branch": args.branch,
            "input_jobs": inputs,
            "env": env,
            "batch_name": (
                f"job{args.source_job}-mfclrtmb-mcmc-"
                f"{'smoke' if args.stage == 'smoke' else f'chain-{chain_id:02d}'}"
            ),
            "tags": {
                "species": "BET",
                "assessment_year": "2026",
                "stage": "mcmc",
                "check_type": "mcmc-chain",
                "source_job": args.source_job,
                "base_job": args.source_job,
                "chain": str(chain_id),
            },
            "metadata": {
                "internal_task": True,
                "task_visibility": "internal",
                "task_role": "diagnostic-support",
                "base_job": args.source_job,
                "chain_id": chain_id,
                "total_chains": chains,
                "hessian_pack_job": pack_job,
                "job_title": (
                    f"Job {args.source_job} mfclrtmb MCMC "
                    f"{'smoke test' if args.stage == 'smoke' else f'chain {chain_id:02d}/{chains:02d}'}"
                ),
            },
        }
        chain_job = submit(api, tasks["chain"], payload, args.dry_run)
        chain_jobs.append(chain_job)
        print(f"Chain {chain_id}: #{chain_job}")

    if args.stage == "smoke":
        return 0

    merge_env = {
        **base_env,
        "MCMC_TOTAL_CHAINS": str(chains),
        "MCMC_WARMUP": str(warmup),
        "MCMC_SAMPLES": str(samples),
        "MCMC_ADAPT_DELTA": str(args.adapt_delta),
        "MCMC_MAX_TREEDEPTH": str(max_treedepth),
    }
    merge_payload = {
        "repo": REPO,
        "branch": args.branch,
        "input_jobs": chain_jobs,
        "env": merge_env,
        "batch_name": f"job{args.source_job}-mfclrtmb-mcmc-merge",
        "tags": {
            "species": "BET",
            "assessment_year": "2026",
            "stage": "mcmc",
            "check_type": "mcmc",
            "source_job": args.source_job,
            "base_job": args.source_job,
        },
        "metadata": {
            "internal_task": True,
            "task_visibility": "internal",
            "task_role": "diagnostic-support",
            "base_job": args.source_job,
            "check_input_jobs": chain_jobs,
            "attached_work_parent_job": args.source_job,
            "attached_work_slot": f"job-{args.source_job}-mfclrtmb-mcmc",
            "attached_work_role": "posterior diagnostic",
            "attached_work_label": "mfclrtmb MCMC",
            "attached_work_headline": "Diagnostics",
            "attached_work_latest": True,
            "job_title": f"Job {args.source_job} mfclrtmb MCMC diagnostics",
            "job_description": (
                f"{chains} independent chains; {warmup} warmup and "
                f"{samples} retained draws per chain."
            ),
        },
    }
    merge_job = submit(api, tasks["merge"], merge_payload, args.dry_run)
    print(f"Merge/report: #{merge_job}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, urllib.error.URLError) as error:
        raise SystemExit(f"ERROR: {error}")

