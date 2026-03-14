#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from typing import Any

from agent_factory_common import (
    DEFAULT_FACTORY_PATTERNS,
    DEFAULT_NEXT_STEP_SUMMARY,
    DEFAULT_REQUESTED_DECISION,
    normalize_list,
    normalize_text,
    slugify,
    trim_words,
    utc_now,
    load_json,
    write_json,
)


CRITICAL_FIELD_QUESTIONS = {
    "target_business_problem": "Какую конкретную бизнес-проблему должен решить будущий агент?",
    "target_users": "Кто будет основным пользователем или выгодоприобретателем результата?",
    "current_workflow_summary": "Как этот процесс работает сейчас и где основные потери?",
    "constraints_or_exclusions": "Какие ограничения, исключения или запреты нужно учесть?",
    "measurable_success_expectation": "По каким метрикам поймем, что идея действительно сработала?",
}

DEFAULT_ASSUMPTIONS = [
    "MVP0 использует Telegram как основной канал intake и доставки артефактов.",
    "Concept pack должен оставаться синхронизированным между project doc, agent spec и presentation.",
    "Playground в MVP0 использует только synthetic или test data.",
]
DISCOVERY_HANDOFF_NEXT_STEP_SUMMARY = "Подготовить synchronized concept pack из confirmed requirements brief."


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Normalize one factory intake request into a canonical concept record.")
    parser.add_argument("--source", required=True, help="Path to intake JSON fixture or request payload")
    parser.add_argument("--output", help="Optional output JSON path (stdout when omitted)")
    parser.add_argument("--concept-id", help="Override generated concept id")
    parser.add_argument("--concept-version", default="0.1.0", help="Concept version to assign")
    parser.add_argument("--agent-name", help="Optional human-readable future agent name")
    return parser.parse_args()


def build_agent_name(problem_statement: str, explicit_name: str | None) -> str:
    if explicit_name and normalize_text(explicit_name):
        return normalize_text(explicit_name)
    trimmed = trim_words(problem_statement, 7)
    if not trimmed:
        return "Концепт AI-агента"
    return f"Концепт AI-агента: {trimmed}"


def load_request_document(path: str) -> dict[str, Any]:
    payload = load_json(path)
    if isinstance(payload, dict) and "concept_request" in payload:
        request = payload["concept_request"]
    else:
        request = payload
    if not isinstance(request, dict):
        raise ValueError("source payload must be an object or contain concept_request")
    return request


def is_discovery_payload(payload: dict[str, Any]) -> bool:
    return any(
        isinstance(payload.get(key), dict)
        for key in ("discovery_session", "requirement_brief", "confirmation_snapshot", "factory_handoff_record")
    )


def brief_list(value: Any) -> list[str]:
    return normalize_list(value)


def derive_discovery_handoff_request(payload: dict[str, Any]) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    discovery_session = payload.get("discovery_session", {}) if isinstance(payload.get("discovery_session"), dict) else {}
    requirement_brief = payload.get("requirement_brief", {}) if isinstance(payload.get("requirement_brief"), dict) else {}
    confirmation_snapshot = payload.get("confirmation_snapshot", {}) if isinstance(payload.get("confirmation_snapshot"), dict) else {}
    factory_handoff_record = payload.get("factory_handoff_record", {}) if isinstance(payload.get("factory_handoff_record"), dict) else {}

    if not requirement_brief:
        return None, {
            "status": "blocked",
            "next_action": "return_to_discovery_brief",
            "block_reason": "Discovery payload does not contain a requirement brief.",
            "factory_handoff_record": factory_handoff_record,
        }

    handoff_status = normalize_text(factory_handoff_record.get("handoff_status"))
    brief_status = normalize_text(requirement_brief.get("status"))
    snapshot_status = normalize_text(confirmation_snapshot.get("status"))
    brief_version = normalize_text(requirement_brief.get("version"))
    snapshot_brief_version = normalize_text(confirmation_snapshot.get("brief_version"))

    blocking_reasons = normalize_list(factory_handoff_record.get("blocking_reasons"))
    if brief_status != "confirmed":
        blocking_reasons.append("Requirement brief еще не подтвержден.")
    if snapshot_status != "active":
        blocking_reasons.append("Нет активного confirmation snapshot.")
    if brief_version and snapshot_brief_version and brief_version != snapshot_brief_version:
        blocking_reasons.append("Confirmation snapshot относится к другой версии brief.")
    if handoff_status != "ready":
        blocking_reasons.append("Factory handoff record не готов к downstream intake.")

    if blocking_reasons:
        return None, {
            "status": "blocked",
            "next_action": "return_to_discovery_handoff",
            "block_reason": "; ".join(dict.fromkeys(blocking_reasons)),
            "factory_handoff_record": factory_handoff_record,
            "requirement_brief": requirement_brief,
            "confirmation_snapshot": confirmation_snapshot,
            "discovery_session": discovery_session,
        }

    requester_identity = discovery_session.get("requester_identity", {}) if isinstance(discovery_session.get("requester_identity"), dict) else {}
    captured_answers = {
        "target_business_problem": normalize_text(requirement_brief.get("problem_statement")),
        "target_users": brief_list(requirement_brief.get("target_users")),
        "current_workflow_summary": normalize_text(requirement_brief.get("current_process")),
        "desired_outcome": normalize_text(requirement_brief.get("desired_outcome")),
        "scope_boundaries": brief_list(requirement_brief.get("scope_boundaries")),
        "user_story": normalize_text(requirement_brief.get("user_story")),
        "input_examples": brief_list(requirement_brief.get("input_examples")),
        "expected_outputs": brief_list(requirement_brief.get("expected_outputs")),
        "business_rules": brief_list(requirement_brief.get("business_rules")),
        "exceptions": brief_list(requirement_brief.get("exceptions")),
        "constraints_or_exclusions": brief_list(requirement_brief.get("constraints")),
        "measurable_success_expectation": brief_list(requirement_brief.get("success_metrics")),
        "open_risks": brief_list(requirement_brief.get("open_risks")),
    }
    concept_request = {
        "concept_request_id": normalize_text(factory_handoff_record.get("factory_handoff_id"))
        or f"concept-request-{normalize_text(requirement_brief.get('brief_id')) or 'discovery-handoff'}",
        "request_channel": normalize_text(discovery_session.get("request_channel")) or "telegram",
        "requester_identity": requester_identity,
        "request_language": normalize_text(discovery_session.get("working_language")) or "ru",
        "raw_problem_statement": normalize_text(requirement_brief.get("problem_statement")),
        "captured_answers": captured_answers,
        "missing_information_topics": [],
        "status": "ready_for_pack",
        "source_kind": "confirmed_discovery_handoff",
        "source_brief_id": normalize_text(requirement_brief.get("brief_id")),
        "source_brief_version": brief_version,
        "source_confirmation_snapshot_id": normalize_text(confirmation_snapshot.get("confirmation_snapshot_id")),
        "source_discovery_session_id": normalize_text(discovery_session.get("discovery_session_id")),
        "source_project_key": normalize_text(requirement_brief.get("project_key")),
    }
    return concept_request, None


def identify_missing_topics(captured_answers: dict[str, Any]) -> tuple[list[str], list[str]]:
    missing_keys: list[str] = []
    follow_up_questions: list[str] = []
    for key, question in CRITICAL_FIELD_QUESTIONS.items():
        value = captured_answers.get(key)
        if isinstance(value, list):
            has_value = len(normalize_list(value)) > 0
        else:
            has_value = bool(normalize_text(value))
        if has_value:
            continue
        missing_keys.append(key)
        follow_up_questions.append(question)
    return missing_keys, follow_up_questions


def main() -> int:
    args = parse_args()
    now = utc_now()

    try:
        raw_payload = load_json(args.source)
        if not isinstance(raw_payload, dict):
            raise ValueError("source payload must be a JSON object")
        discovery_request, blocked_response = derive_discovery_handoff_request(raw_payload) if is_discovery_payload(raw_payload) else (None, None)
        if blocked_response:
            write_json(blocked_response, args.output)
            return 0
        request = discovery_request if discovery_request is not None else load_request_document(args.source)
    except Exception as exc:
        print(f'{{"status":"error","error":"{normalize_text(exc)}"}}')
        return 2

    captured_answers = request.get("captured_answers", {}) if isinstance(request.get("captured_answers"), dict) else {}
    missing_keys, follow_up_questions = identify_missing_topics(captured_answers)
    request_language = normalize_text(request.get("request_language")) or "ru"
    requester_identity = request.get("requester_identity", {}) if isinstance(request.get("requester_identity"), dict) else {}
    requester_name = normalize_text(requester_identity.get("display_name")) or "Сергей"
    raw_problem_statement = normalize_text(request.get("raw_problem_statement"))
    problem_statement = normalize_text(captured_answers.get("target_business_problem")) or raw_problem_statement
    source_kind = normalize_text(request.get("source_kind"))
    is_discovery_handoff_request = source_kind == "confirmed_discovery_handoff"

    normalized_request = {
        "concept_request_id": normalize_text(request.get("concept_request_id")) or f"concept-request-{slugify(problem_statement, 'request')}",
        "request_channel": normalize_text(request.get("request_channel")) or "telegram",
        "requester_identity": requester_identity,
        "request_language": request_language,
        "raw_problem_statement": raw_problem_statement,
        "captured_answers": captured_answers,
        "missing_information_topics": normalize_list(request.get("missing_information_topics")),
        "status": "clarifying" if missing_keys else "ready_for_pack",
    }
    if source_kind:
        normalized_request["source_kind"] = source_kind
    for key in ("source_brief_id", "source_brief_version", "source_confirmation_snapshot_id", "source_discovery_session_id", "source_project_key"):
        value = normalize_text(request.get(key))
        if value:
            normalized_request[key] = value

    response: dict[str, Any] = {
        "status": normalized_request["status"],
        "concept_request": normalized_request,
        "critical_missing_topics": missing_keys,
        "follow_up_questions": follow_up_questions,
        "next_action": "ask_followup_questions" if missing_keys else "generate_artifacts",
    }

    if missing_keys:
        write_json(response, args.output)
        return 0

    target_users = normalize_list(captured_answers.get("target_users"))
    current_process = normalize_text(captured_answers.get("current_workflow_summary"))
    constraints = normalize_list(captured_answers.get("constraints_or_exclusions"))
    success_metrics = normalize_list(captured_answers.get("measurable_success_expectation"))
    assumptions = normalize_list(captured_answers.get("assumptions")) or list(DEFAULT_ASSUMPTIONS)
    open_risks = normalize_list(captured_answers.get("open_risks"))
    for topic in normalized_request["missing_information_topics"]:
        open_risks.append(f"Требует уточнения на следующем шаге: {topic}")

    agent_name = build_agent_name(problem_statement, args.agent_name)
    concept_id = normalize_text(args.concept_id) or slugify(agent_name)
    desired_outcome = normalize_text(captured_answers.get("desired_outcome")) or normalize_text(success_metrics[0] if success_metrics else "")
    if not desired_outcome:
        desired_outcome = "Получить согласованный concept pack и готовность к защите концепции."

    concept_record = {
        "concept_id": concept_id,
        "source_request_id": normalized_request["concept_request_id"],
        "title": agent_name,
        "problem_statement": problem_statement,
        "target_users": target_users,
        "current_process": current_process,
        "desired_outcome": normalize_text(captured_answers.get("desired_outcome")) or desired_outcome,
        "scope_boundaries": normalize_list(captured_answers.get("scope_boundaries")),
        "user_story": normalize_text(captured_answers.get("user_story")),
        "input_examples": normalize_list(captured_answers.get("input_examples")),
        "expected_outputs": normalize_list(captured_answers.get("expected_outputs")),
        "business_rules": normalize_list(captured_answers.get("business_rules")),
        "exceptions": normalize_list(captured_answers.get("exceptions")),
        "success_metrics": success_metrics,
        "constraints": constraints,
        "assumptions": assumptions,
        "open_risks": open_risks,
        "applied_factory_patterns": list(DEFAULT_FACTORY_PATTERNS),
        "current_version": args.concept_version,
        "decision_state": "draft",
        "created_at": now,
        "updated_at": now,
    }
    if is_discovery_handoff_request:
        concept_record["source_kind"] = source_kind
        concept_record["project_key"] = normalize_text(request.get("source_project_key"))
        concept_record["factory_handoff_id"] = normalized_request["concept_request_id"]
        concept_record["discovery_session_id"] = normalize_text(request.get("source_discovery_session_id"))
        concept_record["brief_id"] = normalize_text(request.get("source_brief_id"))
        concept_record["brief_version"] = normalize_text(request.get("source_brief_version"))
        concept_record["confirmation_snapshot_id"] = normalize_text(request.get("source_confirmation_snapshot_id"))
        confirmation_snapshot = raw_payload.get("confirmation_snapshot", {}) if isinstance(raw_payload.get("confirmation_snapshot"), dict) else {}
        factory_handoff_record = raw_payload.get("factory_handoff_record", {}) if isinstance(raw_payload.get("factory_handoff_record"), dict) else {}
        concept_record["confirmed_at"] = normalize_text(confirmation_snapshot.get("confirmed_at"))
        concept_record["confirmed_by"] = normalize_text(confirmation_snapshot.get("confirmed_by"))
        concept_record["downstream_target"] = normalize_text(factory_handoff_record.get("downstream_target"))
        concept_record["handoff_created_at"] = normalize_text(factory_handoff_record.get("created_at"))
        concept_record["handoff_consumed_at"] = normalize_text(factory_handoff_record.get("consumed_at"))

    artifact_context = {
        "agent_name": agent_name,
        "owner": requester_name,
        "desired_outcome": desired_outcome,
        "requested_decision": DEFAULT_REQUESTED_DECISION,
        "next_step_summary": DISCOVERY_HANDOFF_NEXT_STEP_SUMMARY if is_discovery_handoff_request else DEFAULT_NEXT_STEP_SUMMARY,
        "delivery_channel": "telegram",
        "working_language": request_language,
    }

    response["concept_record"] = concept_record
    response["artifact_context"] = artifact_context
    if is_discovery_handoff_request:
        for key in ("discovery_session", "requirement_brief", "confirmation_snapshot", "factory_handoff_record"):
            value = raw_payload.get(key)
            if isinstance(value, dict) and value:
                response[key] = value

    write_json(response, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
