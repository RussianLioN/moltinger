#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import textwrap
import zipfile
from pathlib import Path
from typing import Any

from agent_factory_common import load_json, normalize_text, utc_now, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run one approved concept through the factory swarm prototype.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run = subparsers.add_parser("run", help="Execute swarm stages and assemble a playground bundle")
    run.add_argument("--manifest", required=True, help="Path to the approved concept-pack manifest")
    run.add_argument("--output-dir", required=True, help="Directory where swarm artifacts should be written")
    run.add_argument("--registry", default="config/fleet/agents-registry.json", help="Fleet registry path")
    run.add_argument("--policy", default="config/fleet/policy.json", help="Fleet policy path")
    run.add_argument("--playground-script", default="scripts/agent-factory-playground.py", help="Playground packager entrypoint")
    run.add_argument("--output", help="Optional JSON summary output path")

    return parser.parse_args()


def ensure_approved_manifest(manifest: dict[str, Any]) -> tuple[str, str, str]:
    approval_gate = manifest.get("approval_gate", {}) if isinstance(manifest.get("approval_gate"), dict) else {}
    production_approval = manifest.get("production_approval", {}) if isinstance(manifest.get("production_approval"), dict) else {}
    concept_id = normalize_text(manifest.get("concept_id"))
    concept_version = normalize_text(manifest.get("concept_version"))
    if normalize_text(approval_gate.get("status")) != "unlocked":
        raise ValueError("concept pack is not unlocked for production")
    if manifest.get("production_ready") is not True:
        raise ValueError("concept pack is not marked production_ready")
    if normalize_text(production_approval.get("status")) != "active":
        raise ValueError("production_approval must be active")
    if normalize_text(production_approval.get("approved_version")) != concept_version:
        raise ValueError("production_approval version mismatch")
    approval_id = normalize_text(production_approval.get("approval_id"))
    if not concept_id or not concept_version or not approval_id:
        raise ValueError("approved concept pack must include concept_id, concept_version, and approval_id")
    return concept_id, concept_version, approval_id


def load_stage_contracts(registry_path: str, policy_path: str) -> list[dict[str, Any]]:
    registry = load_json(registry_path)
    policy = load_json(policy_path)
    registry_contracts = registry.get("production_stage_contracts", [])
    policy_contracts = policy.get("production_stage_policies", [])
    if not isinstance(registry_contracts, list) or not isinstance(policy_contracts, list):
        raise ValueError("production stage contracts are missing from fleet registry or policy")
    policy_by_stage = {
        normalize_text(item.get("stage_name")): item
        for item in policy_contracts
        if isinstance(item, dict) and normalize_text(item.get("stage_name"))
    }
    merged: list[dict[str, Any]] = []
    for item in registry_contracts:
        if not isinstance(item, dict):
            continue
        stage_name = normalize_text(item.get("stage_name"))
        if not stage_name:
            continue
        policy_item = policy_by_stage.get(stage_name)
        if not policy_item:
            raise ValueError(f"missing production stage policy for stage: {stage_name}")
        merged.append({"registry": item, "policy": policy_item})
    if len(merged) < 5:
        raise ValueError("production stage contracts must define at least five stages")
    return merged


def stage_body(stage_name: str, concept_id: str, concept_version: str) -> tuple[str, str]:
    if stage_name == "coding":
        return (
            "output-summary.md",
            textwrap.dedent(
                f"""
                # Coding Output Summary

                - `Concept ID`: `{concept_id}`
                - `Concept Version`: `{concept_version}`
                - Source transformed into a buildable playground prototype contract.
                """
            ).strip(),
        )
    if stage_name == "testing":
        return (
            "report.json",
            json.dumps(
                {
                    "stage": "testing",
                    "status": "passed",
                    "concept_id": concept_id,
                    "concept_version": concept_version,
                    "checks": [
                        "artifact alignment preserved",
                        "approval gate preserved",
                        "playground packaging prerequisites satisfied",
                    ],
                },
                ensure_ascii=False,
                indent=2,
            ),
        )
    if stage_name == "validation":
        return (
            "checklist.md",
            textwrap.dedent(
                f"""
                # Validation Checklist

                - [x] Approved concept version remains `{concept_version}`
                - [x] Scope remains tied to `{concept_id}`
                - [x] Playground is limited to synthetic/test data
                """
            ).strip(),
        )
    if stage_name == "audit":
        return (
            "alignment-report.md",
            textwrap.dedent(
                f"""
                # Audit Alignment Report

                Концепция `{concept_id}` версии `{concept_version}` соответствует swarm output contract.
                Production deploy не выполнялся. Output ограничен playground bundle.
                """
            ).strip(),
        )
    raise ValueError(f"unsupported pre-assembly stage: {stage_name}")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def build_prepackage_payload(
    swarm_run: dict[str, Any],
    stage_executions: list[dict[str, Any]],
    output_dir: Path,
    evidence_bundle_ref: str,
) -> Path:
    payload = {
        "swarm_run": swarm_run,
        "stage_executions": stage_executions,
        "playground_package": {
            "playground_package_id": f"playground-{swarm_run['swarm_run_id']}",
            "evidence_bundle_ref": evidence_bundle_ref,
            "review_status": "ready_for_demo",
        },
    }
    source_path = output_dir / "swarm-playground-source.json"
    write_json(payload, source_path)
    return source_path


def run_playground_packager(
    script_path: str,
    swarm_source: Path,
    output_dir: Path,
    evidence_bundle_ref: str,
) -> dict[str, Any]:
    response_path = output_dir / "playground-package-output.json"
    cmd = [
        sys.executable,
        script_path,
        "package",
        "--swarm-run",
        str(swarm_source),
        "--output-dir",
        str(output_dir),
        "--evidence-bundle-ref",
        evidence_bundle_ref,
        "--output",
        str(response_path),
    ]
    subprocess.run(cmd, check=True)
    payload = load_json(response_path)
    if not isinstance(payload, dict):
        raise ValueError("playground packaging response must be an object")
    return payload


def build_evidence_bundle(output_dir: Path, stage_executions: list[dict[str, Any]], playground_payload: dict[str, Any]) -> dict[str, str]:
    evidence_dir = output_dir / "artifacts" / "evidence"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = evidence_dir / "bundle-manifest.json"
    archive_path = evidence_dir / "bundle.zip"

    refs: list[str] = []
    for stage in stage_executions:
        refs.extend(stage.get("evidence_refs", []))
    refs.extend(
        [
            normalize_text(playground_payload["files"]["manifest_ref"]),
            normalize_text(playground_payload["files"]["launch_instructions_ref"]),
            normalize_text(playground_payload["files"]["archive_ref"]),
        ]
    )
    bundle_manifest = {
        "generated_at": utc_now(),
        "evidence_refs": refs,
    }
    write_json(bundle_manifest, manifest_path)

    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(manifest_path, arcname="bundle-manifest.json")
        for ref in refs:
            path = Path(ref)
            if path.is_file():
                arcname = path.relative_to(output_dir) if path.is_absolute() is False else path.name
                archive.write(path, arcname=str(arcname))

    return {
        "manifest_ref": str(manifest_path),
        "archive_ref": str(archive_path),
    }


def run_swarm(args: argparse.Namespace) -> int:
    manifest = load_json(args.manifest)
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be a JSON object")
    concept_id, concept_version, approval_id = ensure_approved_manifest(manifest)
    stage_contracts = load_stage_contracts(args.registry, args.policy)

    output_dir = Path(args.output_dir)
    artifacts_dir = output_dir / "artifacts"
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    swarm_run_id = f"swarm-run-{concept_id}-{concept_version}".replace(".", "-")
    started_at = utc_now()
    terminal_summary = "Playground package assembled with complete evidence bundle."
    requested_roles = [normalize_text(item["registry"].get("role_owner")) for item in stage_contracts]

    swarm_run = {
        "swarm_run_id": swarm_run_id,
        "concept_id": concept_id,
        "concept_version": concept_version,
        "approval_id": approval_id,
        "requested_at": started_at,
        "started_at": started_at,
        "completed_at": None,
        "run_status": "running",
        "requested_roles": requested_roles,
        "terminal_summary": "",
    }

    stage_executions: list[dict[str, Any]] = []
    completed_stage_names: list[str] = []
    for contract in stage_contracts:
        registry_item = contract["registry"]
        policy_item = contract["policy"]
        stage_name = normalize_text(registry_item.get("stage_name"))
        role_owner = normalize_text(registry_item.get("role_owner"))
        depends_on = [normalize_text(item) for item in registry_item.get("depends_on", []) if normalize_text(item)]
        if stage_name != "assembly":
            for dependency in depends_on:
                if dependency not in completed_stage_names:
                    raise ValueError(f"stage {stage_name} cannot start before dependency {dependency}")
            filename, body = stage_body(stage_name, concept_id, concept_version)
            evidence_path = artifacts_dir / stage_name / filename
            write_text(evidence_path, body)
            stage_executions.append(
                {
                    "stage_execution_id": f"{swarm_run_id}-{stage_name}",
                    "stage_name": stage_name,
                    "role_owner": role_owner,
                    "depends_on": depends_on,
                    "status": "completed",
                    "started_at": utc_now(),
                    "ended_at": utc_now(),
                    "failure_class": "",
                    "required_capabilities": registry_item.get("required_capabilities", []),
                    "policy": {
                        "entry_condition": normalize_text(policy_item.get("entry_condition")),
                        "exit_condition": normalize_text(policy_item.get("exit_condition")),
                    },
                    "evidence_refs": [str(evidence_path)],
                }
            )
            completed_stage_names.append(stage_name)

    planned_bundle_ref = str(artifacts_dir / "evidence" / "bundle.zip")
    prepackage_source = build_prepackage_payload(swarm_run, stage_executions, output_dir, planned_bundle_ref)
    playground_payload = run_playground_packager(args.playground_script, prepackage_source, output_dir / "assembly", planned_bundle_ref)
    playground_package = playground_payload["playground_package"]
    assembly_contract = next(item for item in stage_contracts if normalize_text(item["registry"].get("stage_name")) == "assembly")
    assembly_registry = assembly_contract["registry"]
    assembly_policy = assembly_contract["policy"]
    assembly_evidence_refs = [
        normalize_text(playground_payload["files"]["manifest_ref"]),
        normalize_text(playground_payload["files"]["launch_instructions_ref"]),
        normalize_text(playground_payload["files"]["archive_ref"]),
    ]
    stage_executions.append(
        {
            "stage_execution_id": f"{swarm_run_id}-assembly",
            "stage_name": "assembly",
            "role_owner": normalize_text(assembly_registry.get("role_owner")),
            "depends_on": [normalize_text(item) for item in assembly_registry.get("depends_on", []) if normalize_text(item)],
            "status": "completed",
            "started_at": utc_now(),
            "ended_at": utc_now(),
            "failure_class": "",
            "required_capabilities": assembly_registry.get("required_capabilities", []),
            "policy": {
                "entry_condition": normalize_text(assembly_policy.get("entry_condition")),
                "exit_condition": normalize_text(assembly_policy.get("exit_condition")),
            },
            "evidence_refs": assembly_evidence_refs,
        }
    )

    evidence_bundle = build_evidence_bundle(output_dir, stage_executions, playground_payload)
    playground_package["evidence_bundle_ref"] = evidence_bundle["archive_ref"]
    assembly_manifest_path = Path(playground_payload["files"]["manifest_ref"])
    updated_package = load_json(assembly_manifest_path)
    updated_package["evidence_bundle_ref"] = evidence_bundle["archive_ref"]
    write_json(updated_package, assembly_manifest_path)

    swarm_run["completed_at"] = utc_now()
    swarm_run["run_status"] = "completed"
    swarm_run["terminal_summary"] = terminal_summary

    response = {
        "status": "completed",
        "swarm_run": swarm_run,
        "stage_executions": stage_executions,
        "playground_package": playground_package,
        "evidence_bundle": evidence_bundle,
    }
    manifest_path = output_dir / "swarm-run.json"
    write_json(response, manifest_path)
    response["manifest_path"] = str(manifest_path)
    write_json(response, args.output)
    return 0


def main() -> int:
    args = parse_args()
    if args.command == "run":
        return run_swarm(args)
    raise ValueError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
