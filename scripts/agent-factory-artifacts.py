#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path
from typing import Any

from agent_factory_common import (
    DEFAULT_EXTERNAL_DEPENDENCIES,
    DEFAULT_FACTORY_PATTERNS,
    DEFAULT_NEXT_STEP_SUMMARY,
    DEFAULT_NON_GOALS,
    DEFAULT_REQUESTED_DECISION,
    alignment_comment,
    alignment_digest,
    build_alignment_payload,
    load_json,
    normalize_list,
    normalize_text,
    parse_alignment_comment,
    render_template,
    to_bullets,
    utc_now,
    write_json,
)


ARTIFACT_SPECS = {
    "project_doc": "project-doc.md",
    "agent_spec": "agent-spec.md",
    "presentation": "presentation.md",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate and validate synchronized concept-pack artifacts.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser("generate", help="Generate working and downloadable artifacts")
    generate.add_argument("--input", required=True, help="Path to intake output JSON or concept-pack source JSON")
    generate.add_argument("--output-dir", required=True, help="Directory where concept pack should be written")
    generate.add_argument("--template-root", default="docs/templates/agent-factory", help="Template root directory")
    generate.add_argument("--artifact-revision", default="r1", help="Artifact revision tag for this generation")
    generate.add_argument("--output", help="Optional JSON summary output path")

    check = subparsers.add_parser("check-alignment", help="Validate artifact synchronization from manifest")
    check.add_argument("--manifest", required=True, help="Path to generated concept-pack manifest JSON")
    check.add_argument("--output", help="Optional JSON report output path")

    return parser.parse_args()


def derive_artifact_context(source: dict[str, Any], concept_record: dict[str, Any]) -> dict[str, Any]:
    artifact_context = source.get("artifact_context", {}) if isinstance(source.get("artifact_context"), dict) else {}
    owner = normalize_text(artifact_context.get("owner")) or "Сергей"
    desired_outcome = normalize_text(artifact_context.get("desired_outcome")) or normalize_text(concept_record["success_metrics"][0] if concept_record.get("success_metrics") else "")
    if not desired_outcome:
        desired_outcome = "Подготовить концепцию к защите и следующему запуску playground path."

    return {
        "agent_name": normalize_text(artifact_context.get("agent_name")) or concept_record["title"],
        "owner": owner,
        "desired_outcome": desired_outcome,
        "requested_decision": normalize_text(artifact_context.get("requested_decision")) or DEFAULT_REQUESTED_DECISION,
        "next_step_summary": normalize_text(artifact_context.get("next_step_summary")) or DEFAULT_NEXT_STEP_SUMMARY,
        "delivery_channel": normalize_text(artifact_context.get("delivery_channel")) or "telegram",
        "working_language": normalize_text(artifact_context.get("working_language")) or "ru",
    }


def load_source_document(path: str) -> tuple[dict[str, Any], dict[str, Any]]:
    source = load_json(path)
    if not isinstance(source, dict):
        raise ValueError("input document must be a JSON object")
    if "concept_record" in source:
        concept_record = source["concept_record"]
    else:
        concept_record = source
    if not isinstance(concept_record, dict):
        raise ValueError("concept_record must be a JSON object")
    artifact_context = derive_artifact_context(source, concept_record)
    return concept_record, artifact_context


def build_render_context(concept_record: dict[str, Any], artifact_context: dict[str, Any], artifact_revision: str) -> dict[str, str]:
    target_users = normalize_list(concept_record.get("target_users"))
    success_metrics = normalize_list(concept_record.get("success_metrics"))
    constraints = normalize_list(concept_record.get("constraints"))
    assumptions = normalize_list(concept_record.get("assumptions"))
    open_risks = normalize_list(concept_record.get("open_risks"))
    patterns = normalize_list(concept_record.get("applied_factory_patterns")) or list(DEFAULT_FACTORY_PATTERNS)

    capabilities = [
        "Собирает и структурирует идею автоматизации через Telegram intake.",
        "Формирует synchronized concept pack из project doc, agent spec и presentation.",
        "Подготавливает концепцию к защите и следующему transition в defense loop.",
    ]
    inputs = [
        "Идея автоматизации и описание бизнес-проблемы.",
        "Целевые пользователи и текущий процесс.",
        "Ограничения, исключения и метрики успеха.",
    ]
    outputs = [
        "Проектная документация в working и download видах.",
        "Спецификация будущего агента в working и download видах.",
        "Презентация защиты концепции в working и download видах.",
    ]
    integrations = [
        "Telegram как intake и delivery channel.",
        "Moltis/Moltinger runtime как coordinator.",
        "Локальный ASC mirror как context source.",
    ]
    acceptance_criteria = [
        "Concept pack собирается из одной canonical concept version.",
        "Project doc, spec и presentation совпадают по scope, constraints и success metrics.",
        "Каждый артефакт доступен как working source и download copy.",
    ]
    test_expectations = [
        "Artifact alignment check должен проходить без drift.",
        "Intake flow должен возвращать ready_for_pack при полном наборе критичных данных.",
    ]
    validation_expectations = [
        "Concept pack не должен терять version linkage между артефактами.",
        "Russian-first output обязателен для MVP0.",
    ]
    audit_expectations = [
        "Каждая generation должна иметь manifest с concept id, version и sync hash.",
        "Downloads не должны требовать прямого доступа к server filesystem.",
    ]

    return {
        "concept_id": concept_record["concept_id"],
        "concept_version": concept_record["current_version"],
        "artifact_revision": artifact_revision,
        "owner": artifact_context["owner"],
        "decision_state": normalize_text(concept_record.get("decision_state")) or "draft",
        "agent_name": artifact_context["agent_name"],
        "problem_statement": concept_record["problem_statement"],
        "target_users": to_bullets(target_users, "- Пользователи будут уточнены на следующем шаге"),
        "current_process": normalize_text(concept_record.get("current_process")) or "Текущий процесс будет уточнен на intake stage.",
        "desired_outcome": artifact_context["desired_outcome"],
        "non_goals": to_bullets(list(DEFAULT_NON_GOALS)),
        "success_metrics": to_bullets(success_metrics, "- Метрики успеха будут уточнены"),
        "constraints": to_bullets(constraints, "- Ограничения будут уточнены"),
        "external_dependencies": to_bullets(list(DEFAULT_EXTERNAL_DEPENDENCIES)),
        "assumptions": to_bullets(assumptions, "- Допущения будут уточнены"),
        "open_risks": to_bullets(open_risks, "- Открытые риски не зафиксированы"),
        "applied_factory_patterns": to_bullets(patterns),
        "requested_decision": artifact_context["requested_decision"],
        "next_step_summary": artifact_context["next_step_summary"],
        "target_runtime": "Moltinger coordinator + future factory swarm roles",
        "primary_scenario": "Пользователь описывает идею автоматизации, получает concept pack и выносит его на защиту.",
        "capabilities": to_bullets(capabilities),
        "inputs": to_bullets(inputs),
        "outputs": to_bullets(outputs),
        "integrations": to_bullets(integrations),
        "functional_boundaries": to_bullets([
            "US1 ограничивается intake и concept pack.",
            "Defense loop и swarm начинаются на следующих фазах.",
        ]),
        "non_functional_requirements": to_bullets([
            "Russian-first UX.",
            "Source-first artifacts with git-friendly formats.",
            "Version traceability between all artifacts.",
        ]),
        "exclusions": to_bullets(list(DEFAULT_NON_GOALS)),
        "acceptance_criteria": to_bullets(acceptance_criteria),
        "test_expectations": to_bullets(test_expectations),
        "validation_expectations": to_bullets(validation_expectations),
        "audit_expectations": to_bullets(audit_expectations),
        "playground_scope": to_bullets([
            "В US1 фиксируется только будущий playground scope.",
            "Демонстрация должна использовать synthetic/test data.",
        ]),
        "allowed_data_profile": "synthetic / test only",
        "why_now": "Идея требует согласованной фиксации до защиты, иначе документы и презентация расходятся.",
        "current_pain_points": to_bullets([
            "Идея и документы живут в разных местах.",
            "Презентация и спецификация собираются вручную.",
            "Нет одного канонического concept record.",
        ]),
        "agent_summary": "Фабрика превращает сырую идею автоматизации в защищаемый concept pack без ручной сборки документов.",
        "automation_scope": to_bullets([
            "Сбор недостающего контекста через guided intake.",
            "Синхронная генерация project doc, spec и presentation.",
            "Подготовка к defense gate и следующему production path.",
        ]),
    }


def generate_pack(args: argparse.Namespace) -> int:
    concept_record, artifact_context = load_source_document(args.input)
    output_dir = Path(args.output_dir)
    working_dir = output_dir / "working"
    download_dir = output_dir / "downloads"
    working_dir.mkdir(parents=True, exist_ok=True)
    download_dir.mkdir(parents=True, exist_ok=True)

    render_context = build_render_context(concept_record, artifact_context, args.artifact_revision)
    alignment_payload = build_alignment_payload(concept_record, artifact_context, args.artifact_revision)
    sync_hash = alignment_digest(alignment_payload)
    generated_at = utc_now()

    manifest: dict[str, Any] = {
        "status": "generated",
        "sync_status": "aligned",
        "delivery_channel": artifact_context["delivery_channel"],
        "generated_at": generated_at,
        "concept_id": concept_record["concept_id"],
        "concept_version": concept_record["current_version"],
        "artifact_revision": args.artifact_revision,
        "working_root": str(working_dir),
        "download_root": str(download_dir),
        "alignment_snapshot": alignment_payload,
        "sync_hash": sync_hash,
        "artifacts": {},
    }

    for artifact_type, filename in ARTIFACT_SPECS.items():
        template_path = Path(args.template_root) / filename
        rendered = render_template(template_path, render_context)
        rendered = rendered.rstrip() + "\n\n" + alignment_comment(artifact_type, alignment_payload)

        working_path = working_dir / filename
        download_path = download_dir / filename
        working_path.write_text(rendered, encoding="utf-8")
        shutil.copyfile(working_path, download_path)

        manifest["artifacts"][artifact_type] = {
            "artifact_type": artifact_type,
            "working_source_ref": str(working_path),
            "download_ref": str(download_path),
            "download_name": filename,
            "generated_at": generated_at,
        }

    (output_dir / "concept-record.json").write_text(
        __import__("json").dumps(concept_record, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    manifest_path = output_dir / "concept-pack.json"
    write_json(manifest, manifest_path)
    manifest["manifest_path"] = str(manifest_path)
    write_json(manifest, args.output)
    return 0


def check_alignment(args: argparse.Namespace) -> int:
    manifest = load_json(args.manifest)
    issues: list[str] = []
    checked_artifacts: list[str] = []
    expected_snapshot = manifest.get("alignment_snapshot", {})
    expected_hash = normalize_text(manifest.get("sync_hash"))
    required_content_by_artifact = {
        "project_doc": [
            normalize_text(expected_snapshot.get("concept_id")),
            normalize_text(expected_snapshot.get("concept_version")),
            normalize_text(expected_snapshot.get("problem_statement")),
            normalize_text(expected_snapshot.get("requested_decision")),
        ],
        "agent_spec": [
            normalize_text(expected_snapshot.get("concept_id")),
            normalize_text(expected_snapshot.get("concept_version")),
            normalize_text(expected_snapshot.get("problem_statement")),
        ],
        "presentation": [
            normalize_text(expected_snapshot.get("concept_id")),
            normalize_text(expected_snapshot.get("concept_version")),
            normalize_text(expected_snapshot.get("problem_statement")),
            normalize_text(expected_snapshot.get("requested_decision")),
        ],
    }

    for artifact_type, artifact_entry in manifest.get("artifacts", {}).items():
        working_path = Path(artifact_entry["working_source_ref"])
        download_path = Path(artifact_entry["download_ref"])
        checked_artifacts.append(artifact_type)

        if not working_path.is_file():
            issues.append(f"{artifact_type}: missing working artifact")
            continue
        if not download_path.is_file():
            issues.append(f"{artifact_type}: missing download artifact")
            continue

        working_text = working_path.read_text(encoding="utf-8")
        download_text = download_path.read_text(encoding="utf-8")
        if working_text != download_text:
            issues.append(f"{artifact_type}: working and download copies diverged")

        alignment_meta = parse_alignment_comment(working_text)
        if not alignment_meta:
            issues.append(f"{artifact_type}: alignment metadata missing")
            continue

        for field in ("concept_id", "concept_version", "artifact_revision"):
            expected_value = normalize_text(expected_snapshot.get(field))
            actual_value = normalize_text(alignment_meta.get(field))
            if expected_value != actual_value:
                issues.append(f"{artifact_type}: {field} mismatch ({actual_value} != {expected_value})")
        if normalize_text(alignment_meta.get("artifact_type")) != artifact_type:
            issues.append(f"{artifact_type}: artifact_type marker mismatch")
        if normalize_text(alignment_meta.get("sync_hash")) != expected_hash:
            issues.append(f"{artifact_type}: sync_hash mismatch")

        for required_value in required_content_by_artifact.get(artifact_type, []):
            if required_value and required_value not in working_text:
                issues.append(f"{artifact_type}: expected content missing -> {required_value}")

    status = "aligned" if not issues else "drift_detected"
    report = {
        "status": status,
        "checked_artifacts": checked_artifacts,
        "issues": issues,
        "sync_hash": expected_hash,
        "concept_id": manifest.get("concept_id"),
        "concept_version": manifest.get("concept_version"),
    }
    write_json(report, args.output)
    return 0 if not issues else 1


def main() -> int:
    args = parse_args()
    if args.command == "generate":
        return generate_pack(args)
    if args.command == "check-alignment":
        return check_alignment(args)
    raise ValueError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    sys.exit(main())
