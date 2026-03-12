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

from agent_factory_common import dedupe_preserve_order, load_json, normalize_text, utc_now, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run one approved concept through the factory swarm prototype.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run = subparsers.add_parser("run", help="Execute swarm stages and assemble a playground bundle")
    run.add_argument("--manifest", required=True, help="Path to the approved concept-pack manifest")
    run.add_argument("--output-dir", required=True, help="Directory where swarm artifacts should be written")
    run.add_argument("--registry", default="config/fleet/agents-registry.json", help="Fleet registry path")
    run.add_argument("--policy", default="config/fleet/policy.json", help="Fleet policy path")
    run.add_argument("--playground-script", default="scripts/agent-factory-playground.py", help="Playground packager entrypoint")
    run.add_argument("--fail-stage", help="Optional stage name to force-fail for validation or drill scenarios")
    run.add_argument(
        "--failure-summary",
        default="Prototype swarm stage failed and requires administrator review.",
        help="Summary used when --fail-stage is provided or when a stage fails unexpectedly",
    )
    run.add_argument("--failure-class", default="prototype_failure", help="Failure class for synthetic failure handling")
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


def audit_event(
    event_type: str,
    summary: str,
    *,
    stage_name: str = "",
    status: str = "",
    refs: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "event_type": event_type,
        "stage_name": stage_name,
        "status": status,
        "summary": summary,
        "recorded_at": utc_now(),
        "refs": dedupe_preserve_order([normalize_text(ref) for ref in (refs or []) if normalize_text(ref)]),
    }


def build_stage_execution(
    swarm_run_id: str,
    stage_name: str,
    role_owner: str,
    depends_on: list[str],
    status: str,
    failure_class: str,
    required_capabilities: list[Any],
    policy_item: dict[str, Any],
    evidence_refs: list[str],
) -> dict[str, Any]:
    timestamp = utc_now()
    return {
        "stage_execution_id": f"{swarm_run_id}-{stage_name}",
        "stage_name": stage_name,
        "role_owner": role_owner,
        "depends_on": depends_on,
        "status": status,
        "started_at": timestamp,
        "ended_at": timestamp,
        "failure_class": failure_class,
        "required_capabilities": required_capabilities,
        "policy": {
            "entry_condition": normalize_text(policy_item.get("entry_condition")),
            "exit_condition": normalize_text(policy_item.get("exit_condition")),
        },
        "evidence_refs": dedupe_preserve_order(evidence_refs),
    }


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


def build_evidence_bundle(
    output_dir: Path,
    stage_executions: list[dict[str, Any]],
    *,
    playground_payload: dict[str, Any] | None = None,
    extra_refs: list[str] | None = None,
) -> dict[str, str]:
    evidence_dir = output_dir / "artifacts" / "evidence"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = evidence_dir / "bundle-manifest.json"
    archive_path = evidence_dir / "bundle.zip"

    refs: list[str] = []
    for stage in stage_executions:
        refs.extend(stage.get("evidence_refs", []))
    if playground_payload:
        refs.extend(
            [
                normalize_text(playground_payload["files"]["manifest_ref"]),
                normalize_text(playground_payload["files"]["launch_instructions_ref"]),
                normalize_text(playground_payload["files"]["archive_ref"]),
            ]
        )
    refs.extend(extra_refs or [])
    refs = dedupe_preserve_order([normalize_text(ref) for ref in refs if normalize_text(ref)])

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


def build_failure_evidence(
    output_dir: Path,
    stage_name: str,
    concept_id: str,
    concept_version: str,
    summary: str,
    failure_class: str,
) -> str:
    failure_path = output_dir / "artifacts" / stage_name / "failure-summary.md"
    write_text(
        failure_path,
        textwrap.dedent(
            f"""
            # Stage Failure Summary

            - `Concept ID`: `{concept_id}`
            - `Concept Version`: `{concept_version}`
            - `Stage`: `{stage_name}`
            - `Failure Class`: `{failure_class}`
            - `Summary`: {summary}
            """
        ).strip(),
    )
    return str(failure_path)


def build_escalation_packet(
    output_dir: Path,
    swarm_run: dict[str, Any],
    stage_name: str,
    summary: str,
    failure_class: str,
    evidence_refs: list[str],
    evidence_bundle_ref: str,
    evidence_manifest_ref: str,
) -> dict[str, Any]:
    packet = {
        "escalation_id": f"escalation-{swarm_run['swarm_run_id']}-{stage_name}",
        "concept_id": swarm_run["concept_id"],
        "swarm_run_id": swarm_run["swarm_run_id"],
        "stage_name": stage_name,
        "severity": "high",
        "summary": summary,
        "failure_class": failure_class,
        "recommended_action": f"Проверить stage `{stage_name}`, изучить evidence bundle и решить: rerun stage или вернуть концепцию на доработку.",
        "evidence_refs": dedupe_preserve_order(evidence_refs),
        "evidence_bundle_ref": evidence_bundle_ref,
        "evidence_manifest_ref": evidence_manifest_ref,
        "assigned_to": "factory_admin",
        "created_at": utc_now(),
        "status": "open",
    }
    packet_path = output_dir / "artifacts" / "escalations" / f"{stage_name}-escalation.json"
    packet["packet_ref"] = str(packet_path)
    write_json(packet, packet_path)
    return packet


def finalize_response(args: argparse.Namespace, response: dict[str, Any], output_dir: Path) -> int:
    manifest_path = output_dir / "swarm-run.json"
    write_json(response, manifest_path)
    response_with_path = dict(response)
    response_with_path["manifest_path"] = str(manifest_path)
    write_json(response_with_path, args.output)
    return 0 if normalize_text(response.get("status")) == "completed" else 1


def finalize_failure(
    args: argparse.Namespace,
    output_dir: Path,
    swarm_run: dict[str, Any],
    stage_executions: list[dict[str, Any]],
    audit_trail: list[dict[str, Any]],
    *,
    stage_name: str,
    role_owner: str,
    depends_on: list[str],
    required_capabilities: list[Any],
    policy_item: dict[str, Any],
    summary: str,
    failure_class: str,
    run_status: str = "failed",
    stage_status: str = "failed",
) -> int:
    failure_ref = build_failure_evidence(
        output_dir,
        stage_name,
        swarm_run["concept_id"],
        swarm_run["concept_version"],
        summary,
        failure_class,
    )
    failed_stage = build_stage_execution(
        swarm_run["swarm_run_id"],
        stage_name,
        role_owner,
        depends_on,
        stage_status,
        failure_class,
        required_capabilities,
        policy_item,
        [failure_ref],
    )
    stage_executions.append(failed_stage)
    audit_trail.append(
        audit_event(
            "stage_failed" if stage_status == "failed" else "stage_blocked",
            summary,
            stage_name=stage_name,
            status=stage_status,
            refs=[failure_ref],
        )
    )

    planned_evidence_bundle_ref = str(output_dir / "artifacts" / "evidence" / "bundle.zip")
    planned_evidence_manifest_ref = str(output_dir / "artifacts" / "evidence" / "bundle-manifest.json")
    escalation_input_refs: list[str] = []
    for stage in stage_executions:
        escalation_input_refs.extend(stage.get("evidence_refs", []))
    escalation_input_refs = dedupe_preserve_order(escalation_input_refs)
    escalation_packet = build_escalation_packet(
        output_dir,
        swarm_run,
        stage_name,
        summary,
        failure_class,
        escalation_input_refs,
        planned_evidence_bundle_ref,
        planned_evidence_manifest_ref,
    )
    evidence_bundle = build_evidence_bundle(
        output_dir,
        stage_executions,
        extra_refs=[failure_ref, escalation_packet["packet_ref"]],
    )
    escalation_packet["evidence_bundle_ref"] = evidence_bundle["archive_ref"]
    escalation_packet["evidence_manifest_ref"] = evidence_bundle["manifest_ref"]
    write_json(escalation_packet, escalation_packet["packet_ref"])
    audit_trail.append(
        audit_event(
            "evidence_bundle_created",
            "Failure evidence bundle assembled for administrator review.",
            stage_name=stage_name,
            status=run_status,
            refs=[evidence_bundle["manifest_ref"], evidence_bundle["archive_ref"]],
        )
    )
    audit_trail.append(
        audit_event(
            "escalation_created",
            "Administrator escalation packet created for blocker failure.",
            stage_name=stage_name,
            status="open",
            refs=[escalation_packet["packet_ref"], evidence_bundle["archive_ref"]],
        )
    )

    swarm_run["current_stage"] = stage_name
    swarm_run["completed_at"] = utc_now()
    swarm_run["run_status"] = run_status
    swarm_run["terminal_summary"] = summary

    response = {
        "status": "needs_admin_attention",
        "swarm_run": swarm_run,
        "stage_executions": stage_executions,
        "playground_package": {},
        "evidence_bundle": evidence_bundle,
        "escalation_packets": [escalation_packet],
        "audit_trail": audit_trail,
    }
    return finalize_response(args, response, output_dir)


def run_swarm(args: argparse.Namespace) -> int:
    manifest = load_json(args.manifest)
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be a JSON object")
    concept_id, concept_version, approval_id = ensure_approved_manifest(manifest)
    stage_contracts = load_stage_contracts(args.registry, args.policy)

    available_stage_names = [normalize_text(item["registry"].get("stage_name")) for item in stage_contracts]
    if args.fail_stage and normalize_text(args.fail_stage) not in available_stage_names:
        raise ValueError(f"unsupported fail-stage: {args.fail_stage}")

    output_dir = Path(args.output_dir)
    artifacts_dir = output_dir / "artifacts"
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    swarm_run_id = f"swarm-run-{concept_id}-{concept_version}".replace(".", "-")
    started_at = utc_now()
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
        "current_stage": "",
        "terminal_summary": "",
    }
    audit_trail: list[dict[str, Any]] = [
        audit_event(
            "swarm_requested",
            "Approved concept entered the prototype production swarm.",
            status="running",
        )
    ]

    stage_executions: list[dict[str, Any]] = []
    completed_stage_names: list[str] = []
    for contract in stage_contracts:
        registry_item = contract["registry"]
        policy_item = contract["policy"]
        stage_name = normalize_text(registry_item.get("stage_name"))
        role_owner = normalize_text(registry_item.get("role_owner"))
        depends_on = [normalize_text(item) for item in registry_item.get("depends_on", []) if normalize_text(item)]
        required_capabilities = registry_item.get("required_capabilities", [])
        swarm_run["current_stage"] = stage_name

        for dependency in depends_on:
            if dependency not in completed_stage_names:
                return finalize_failure(
                    args,
                    output_dir,
                    swarm_run,
                    stage_executions,
                    audit_trail,
                    stage_name=stage_name,
                    role_owner=role_owner,
                    depends_on=depends_on,
                    required_capabilities=required_capabilities,
                    policy_item=policy_item,
                    summary=f"Stage `{stage_name}` cannot start before dependency `{dependency}` completes.",
                    failure_class="dependency_blocked",
                    run_status="blocked",
                    stage_status="blocked",
                )

        if stage_name == normalize_text(args.fail_stage):
            return finalize_failure(
                args,
                output_dir,
                swarm_run,
                stage_executions,
                audit_trail,
                stage_name=stage_name,
                role_owner=role_owner,
                depends_on=depends_on,
                required_capabilities=required_capabilities,
                policy_item=policy_item,
                summary=normalize_text(args.failure_summary),
                failure_class=normalize_text(args.failure_class) or "prototype_failure",
            )

        if stage_name == "assembly":
            planned_bundle_ref = str(artifacts_dir / "evidence" / "bundle.zip")
            prepackage_source = build_prepackage_payload(swarm_run, stage_executions, output_dir, planned_bundle_ref)
            try:
                playground_payload = run_playground_packager(args.playground_script, prepackage_source, output_dir / "assembly", planned_bundle_ref)
            except subprocess.CalledProcessError as exc:
                return finalize_failure(
                    args,
                    output_dir,
                    swarm_run,
                    stage_executions,
                    audit_trail,
                    stage_name=stage_name,
                    role_owner=role_owner,
                    depends_on=depends_on,
                    required_capabilities=required_capabilities,
                    policy_item=policy_item,
                    summary=normalize_text(args.failure_summary) or f"Assembly stage failed with exit code {exc.returncode}.",
                    failure_class=normalize_text(args.failure_class) or "assembly_failure",
                )

            assembly_evidence_refs = [
                normalize_text(playground_payload["files"]["manifest_ref"]),
                normalize_text(playground_payload["files"]["launch_instructions_ref"]),
                normalize_text(playground_payload["files"]["archive_ref"]),
            ]
            stage_executions.append(
                build_stage_execution(
                    swarm_run_id,
                    stage_name,
                    role_owner,
                    depends_on,
                    "completed",
                    "",
                    required_capabilities,
                    policy_item,
                    assembly_evidence_refs,
                )
            )
            completed_stage_names.append(stage_name)
            audit_trail.append(
                audit_event(
                    "playground_packaged",
                    "Assembly stage packaged the runnable playground bundle.",
                    stage_name=stage_name,
                    status="completed",
                    refs=assembly_evidence_refs,
                )
            )

            evidence_bundle = build_evidence_bundle(output_dir, stage_executions, playground_payload=playground_payload)
            playground_package = playground_payload["playground_package"]
            playground_package["evidence_bundle_ref"] = evidence_bundle["archive_ref"]
            assembly_manifest_path = Path(playground_payload["files"]["manifest_ref"])
            updated_package = load_json(assembly_manifest_path)
            updated_package["evidence_bundle_ref"] = evidence_bundle["archive_ref"]
            write_json(updated_package, assembly_manifest_path)
            audit_trail.append(
                audit_event(
                    "evidence_bundle_created",
                    "Complete reviewable evidence bundle assembled for the successful swarm run.",
                    stage_name=stage_name,
                    status="completed",
                    refs=[evidence_bundle["manifest_ref"], evidence_bundle["archive_ref"]],
                )
            )
            swarm_run["completed_at"] = utc_now()
            swarm_run["run_status"] = "completed"
            swarm_run["terminal_summary"] = "Playground package assembled with complete evidence bundle."
            audit_trail.append(
                audit_event(
                    "swarm_completed",
                    "Approved concept reached playground-ready terminal state.",
                    stage_name=stage_name,
                    status="completed",
                    refs=[evidence_bundle["archive_ref"]],
                )
            )
            response = {
                "status": "completed",
                "swarm_run": swarm_run,
                "stage_executions": stage_executions,
                "playground_package": playground_package,
                "evidence_bundle": evidence_bundle,
                "escalation_packets": [],
                "audit_trail": audit_trail,
            }
            return finalize_response(args, response, output_dir)

        try:
            filename, body = stage_body(stage_name, concept_id, concept_version)
        except Exception as exc:  # pragma: no cover - defensive contract guard
            return finalize_failure(
                args,
                output_dir,
                swarm_run,
                stage_executions,
                audit_trail,
                stage_name=stage_name,
                role_owner=role_owner,
                depends_on=depends_on,
                required_capabilities=required_capabilities,
                policy_item=policy_item,
                summary=f"Stage `{stage_name}` failed before evidence generation: {exc}",
                failure_class="stage_generation_failure",
            )

        evidence_path = artifacts_dir / stage_name / filename
        write_text(evidence_path, body)
        stage_executions.append(
            build_stage_execution(
                swarm_run_id,
                stage_name,
                role_owner,
                depends_on,
                "completed",
                "",
                required_capabilities,
                policy_item,
                [str(evidence_path)],
            )
        )
        completed_stage_names.append(stage_name)
        audit_trail.append(
            audit_event(
                "stage_completed",
                f"Stage `{stage_name}` completed with reviewable evidence.",
                stage_name=stage_name,
                status="completed",
                refs=[str(evidence_path)],
            )
        )

    raise ValueError("production stage contracts must include assembly as the terminal stage")


def main() -> int:
    args = parse_args()
    if args.command == "run":
        return run_swarm(args)
    raise ValueError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
