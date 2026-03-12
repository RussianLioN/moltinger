#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path
from typing import Any

from agent_factory_common import (
    bump_minor_version,
    dedupe_preserve_order,
    load_json,
    normalize_list,
    normalize_text,
    slugify,
    utc_now,
    write_json,
)


ALLOWED_OUTCOMES = {
    "approved",
    "rework_requested",
    "rejected",
    "pending_decision",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Record one defense review for an existing concept pack.")
    parser.add_argument("--manifest", required=True, help="Path to the current concept-pack manifest")
    parser.add_argument("--feedback", required=True, help="Path to the defense feedback JSON payload")
    parser.add_argument("--output", help="Optional output JSON path")
    parser.add_argument("--next-version", help="Override the next concept version for rework_requested")
    return parser.parse_args()


def load_pack_state(manifest_path: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], Path]:
    manifest_file = Path(manifest_path)
    manifest = load_json(manifest_file)
    concept_record_path = manifest_file.parent / "concept-record.json"
    concept_record = load_json(concept_record_path)
    artifact_context = manifest.get("artifact_context", {}) if isinstance(manifest.get("artifact_context"), dict) else {}
    if not artifact_context:
        snapshot = manifest.get("alignment_snapshot", {}) if isinstance(manifest.get("alignment_snapshot"), dict) else {}
        artifact_context = {
            "agent_name": normalize_text(snapshot.get("agent_name")) or normalize_text(concept_record.get("title")) or "Концепт AI-агента",
            "owner": normalize_text(manifest.get("owner")) or "Сергей",
            "desired_outcome": normalize_text(concept_record.get("success_metrics", [""])[0] if concept_record.get("success_metrics") else ""),
            "requested_decision": normalize_text(snapshot.get("requested_decision")) or "Подтвердить концепцию.",
            "next_step_summary": normalize_text(manifest.get("next_action")) or "Ожидается решение по защите.",
            "delivery_channel": normalize_text(manifest.get("delivery_channel")) or "telegram",
            "working_language": normalize_text(manifest.get("artifact_context", {}).get("working_language")) or "ru",
        }
    return manifest, concept_record, artifact_context, manifest_file.parent


def normalize_review_input(payload: dict[str, Any], concept_id: str, concept_version: str) -> tuple[dict[str, Any], list[dict[str, Any]], str]:
    defense_review = payload.get("defense_review", {}) if isinstance(payload.get("defense_review"), dict) else {}
    feedback_items = payload.get("feedback_items", [])
    if not isinstance(feedback_items, list):
        raise ValueError("feedback_items must be a list")

    outcome = normalize_text(defense_review.get("outcome"))
    if outcome not in ALLOWED_OUTCOMES:
        raise ValueError(f"unsupported defense outcome: {outcome}")

    review_concept_id = normalize_text(defense_review.get("concept_id"))
    review_concept_version = normalize_text(defense_review.get("concept_version"))
    if review_concept_id != concept_id:
        raise ValueError(f"feedback concept_id mismatch: {review_concept_id} != {concept_id}")
    if review_concept_version != concept_version:
        raise ValueError(f"feedback concept_version mismatch: {review_concept_version} != {concept_version}")

    review_id = normalize_text(defense_review.get("review_id")) or f"defense-review-{slugify(f'{concept_id}-{concept_version}-{outcome}', 'review')}"
    reviewers = normalize_list(defense_review.get("reviewers"))
    normalized_review = {
        "review_id": review_id,
        "concept_id": concept_id,
        "concept_version": concept_version,
        "outcome": outcome,
        "reviewers": reviewers,
        "feedback_summary": normalize_text(defense_review.get("feedback_summary")),
        "decision_notes": normalize_text(defense_review.get("decision_notes")),
        "reviewed_at": normalize_text(defense_review.get("reviewed_at")) or utc_now(),
    }

    normalized_feedback_items: list[dict[str, Any]] = []
    for index, item in enumerate(feedback_items, start=1):
        if not isinstance(item, dict):
            raise ValueError("each feedback item must be an object")
        normalized_feedback_items.append(
            {
                "feedback_item_id": normalize_text(item.get("feedback_item_id")) or f"{review_id}-feedback-{index:02d}",
                "review_id": review_id,
                "category": normalize_text(item.get("category")) or "general",
                "severity": normalize_text(item.get("severity")) or "medium",
                "summary": normalize_text(item.get("summary")),
                "affected_artifacts": normalize_list(item.get("affected_artifacts")),
                "required_action": normalize_text(item.get("required_action")),
                "resolution_state": normalize_text(item.get("resolution_state")) or "open",
            }
        )

    return normalized_review, normalized_feedback_items, normalize_text(payload.get("expected_next_step_summary"))


def requested_decision_for_outcome(outcome: str) -> str:
    if outcome == "approved":
        return "Решение зафиксировано: концепция одобрена для перехода к production swarm."
    if outcome == "rework_requested":
        return "Решение зафиксировано: концепция требует доработки и повторной защиты."
    if outcome == "rejected":
        return "Решение зафиксировано: концепция отклонена, запуск production swarm запрещен."
    return "Решение еще не принято: production swarm остается заблокирован до явного approval."


def default_next_step_summary(outcome: str, next_version: str, current_version: str) -> str:
    if outcome == "approved":
        return f"Concept version {current_version} готова к запуску production swarm."
    if outcome == "rework_requested":
        return f"Обновить concept pack до версии {next_version} и повторно вынести на защиту."
    if outcome == "rejected":
        return "Production swarm не запускается; требуется новая концепция или закрытие инициативы."
    return "Ожидается итоговое решение по защите; production swarm остается заблокирован."


def next_action_for_outcome(outcome: str) -> str:
    if outcome == "approved":
        return "ready_for_production"
    if outcome == "rework_requested":
        return "regenerate_artifacts"
    if outcome == "rejected":
        return "concept_rejected"
    return "wait_for_decision"


def approval_record(concept_id: str, concept_version: str, review: dict[str, Any]) -> dict[str, Any]:
    approved_by = review["reviewers"][0] if review["reviewers"] else "defense-board"
    return {
        "approval_id": f"approval-{slugify(f'{concept_id}-{concept_version}', 'approval')}",
        "concept_id": concept_id,
        "approved_version": concept_version,
        "approved_by": approved_by,
        "approval_basis": review["review_id"],
        "approved_at": review["reviewed_at"],
        "expires_at": None,
        "status": "active",
    }


def merge_open_risks(existing_risks: list[str], feedback_items: list[dict[str, Any]], outcome: str) -> list[str]:
    risks = list(existing_risks)
    if outcome == "rework_requested":
        for item in feedback_items:
            summary = normalize_text(item.get("summary"))
            required_action = normalize_text(item.get("required_action"))
            affected = ", ".join(normalize_list(item.get("affected_artifacts"))) or "concept_pack"
            risks.append(f"Defense feedback ({affected}): {summary}. Требуемое действие: {required_action}")
    elif outcome == "approved":
        risks = [risk for risk in risks if not risk.startswith("Defense feedback (")]
    return dedupe_preserve_order(risks)


def main() -> int:
    args = parse_args()

    try:
        manifest, concept_record, artifact_context, _pack_dir = load_pack_state(args.manifest)
        feedback_payload = load_json(args.feedback)
        if not isinstance(feedback_payload, dict):
            raise ValueError("feedback payload must be an object")
    except Exception as exc:
        print(f'{{"status":"error","error":"{normalize_text(exc)}"}}')
        return 2

    concept_id = normalize_text(concept_record.get("concept_id"))
    current_version = normalize_text(concept_record.get("current_version"))

    try:
        defense_review, feedback_items, expected_next_step_summary = normalize_review_input(feedback_payload, concept_id, current_version)
    except Exception as exc:
        print(f'{{"status":"error","error":"{normalize_text(exc)}"}}')
        return 2

    outcome = defense_review["outcome"]
    next_version = args.next_version or (bump_minor_version(current_version) if outcome == "rework_requested" else current_version)
    next_action = next_action_for_outcome(outcome)
    updated_concept_record = copy.deepcopy(concept_record)
    updated_concept_record["decision_state"] = outcome
    updated_concept_record["updated_at"] = utc_now()
    updated_concept_record["current_version"] = next_version
    updated_concept_record["review_history"] = list(updated_concept_record.get("review_history", [])) + [defense_review]
    updated_concept_record["feedback_history"] = list(updated_concept_record.get("feedback_history", [])) + feedback_items
    updated_concept_record["open_risks"] = merge_open_risks(normalize_list(updated_concept_record.get("open_risks")), feedback_items, outcome)
    updated_concept_record["last_review_id"] = defense_review["review_id"]
    updated_concept_record["last_reviewed_version"] = current_version

    current_feedback_items = feedback_items if outcome == "rework_requested" else []
    production_approval = approval_record(concept_id, current_version, defense_review) if outcome == "approved" else None
    updated_concept_record["production_approval"] = production_approval

    updated_artifact_context = copy.deepcopy(artifact_context)
    updated_artifact_context["requested_decision"] = requested_decision_for_outcome(outcome)
    updated_artifact_context["next_step_summary"] = expected_next_step_summary or default_next_step_summary(outcome, next_version, current_version)
    if outcome == "rework_requested":
        updated_artifact_context["desired_outcome"] = f"Обновить concept pack до версии {next_version} и повторно пройти defense gate."

    requested_changes = [normalize_text(item.get("required_action")) for item in feedback_items if normalize_text(item.get("required_action"))]
    post_defense_summary = {
        "review_id": defense_review["review_id"],
        "outcome": outcome,
        "decision_notes": defense_review["decision_notes"],
        "requested_changes": requested_changes,
        "next_action": next_action,
        "next_step_summary": updated_artifact_context["next_step_summary"],
        "production_blocked": outcome != "approved",
    }

    response = {
        "status": "review_recorded",
        "history_reason": f"defense_{outcome}",
        "next_action": next_action,
        "concept_record": updated_concept_record,
        "artifact_context": updated_artifact_context,
        "defense_review": defense_review,
        "feedback_items": current_feedback_items,
        "post_defense_summary": post_defense_summary,
        "production_approval": production_approval,
    }
    write_json(response, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
