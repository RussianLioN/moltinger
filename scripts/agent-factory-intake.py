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
        request = load_request_document(args.source)
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

    artifact_context = {
        "agent_name": agent_name,
        "owner": requester_name,
        "desired_outcome": desired_outcome,
        "requested_decision": DEFAULT_REQUESTED_DECISION,
        "next_step_summary": DEFAULT_NEXT_STEP_SUMMARY,
        "delivery_channel": "telegram",
        "working_language": request_language,
    }

    response["concept_record"] = concept_record
    response["artifact_context"] = artifact_context

    write_json(response, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
