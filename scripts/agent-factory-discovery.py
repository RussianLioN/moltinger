#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

from agent_factory_common import (
    archive_confirmation_snapshot,
    archive_handoff_record,
    build_discovery_topic,
    build_discovery_topic_progress,
    canonical_discovery_topic_name,
    dedupe_preserve_order,
    discovery_example_contradictions,
    discovery_example_data_safety_status,
    discovery_next_topic,
    discovery_topic_names,
    discovery_topic_question,
    load_json,
    normalize_dict_list,
    normalize_list,
    normalize_text,
    render_template,
    slugify,
    to_bullets,
    utc_now,
    write_json,
)


AGENT_SUMMARY = (
    "Я выступаю как AI бизнес-аналитик: сначала помогу собрать требования простым бизнес-языком, "
    "потом из подтвержденного контекста можно будет перейти к requirements brief и downstream concept pack."
)
BRIEF_TEMPLATE_PATH = Path(__file__).resolve().parent.parent / "docs/templates/agent-factory/requirements-brief.md"
BRIEF_TOPIC_FIELD_MAP = {
    "problem": "problem_statement",
    "target_users": "target_users",
    "current_workflow": "current_process",
    "desired_outcome": "desired_outcome",
    "user_story": "user_story",
    "input_examples": "input_examples",
    "expected_outputs": "expected_outputs",
    "constraints": "constraints",
    "success_metrics": "success_metrics",
}
BRIEF_SECTION_ORDER = [
    "problem_statement",
    "target_users",
    "current_process",
    "desired_outcome",
    "scope_boundaries",
    "user_story",
    "input_examples",
    "expected_outputs",
    "business_rules",
    "exceptions",
    "constraints",
    "success_metrics",
    "open_risks",
]
BRIEF_LIST_FIELDS = {
    "target_users",
    "scope_boundaries",
    "input_examples",
    "expected_outputs",
    "business_rules",
    "exceptions",
    "constraints",
    "success_metrics",
    "open_risks",
}
BRIEF_SECTION_ALIASES = {
    "problem_statement": ["problem_statement", "problem", "target_business_problem", "business_problem"],
    "target_users": ["target_users", "users", "beneficiaries"],
    "current_process": ["current_process", "current_workflow", "current_workflow_summary", "current_process_summary"],
    "desired_outcome": ["desired_outcome", "goal", "desired_result"],
    "scope_boundaries": ["scope_boundaries", "scope_boundary", "scope"],
    "user_story": ["user_story"],
    "input_examples": ["input_examples", "example_inputs", "examples"],
    "expected_outputs": ["expected_outputs", "output_examples", "desired_outputs"],
    "business_rules": ["business_rules", "rules", "rule_examples"],
    "exceptions": ["exceptions", "exception_cases", "exception_case"],
    "constraints": ["constraints", "constraints_or_exclusions", "exclusions"],
    "success_metrics": ["success_metrics", "measurable_success_expectation", "metrics"],
    "open_risks": ["open_risks", "risks", "unresolved_questions"],
}
BRIEF_CONFIRMATION_PROMPT = (
    "Я собрал requirements brief. Проверь summary и ответь, что нужно исправить, "
    "или явно подтверди его для перехода к следующему этапу фабрики."
)
HANDOFF_DOWNSTREAM_TARGET = "specs/020-agent-factory-prototype"
HANDOFF_NEXT_STAGE = "concept_pack_generation"
EXPECTED_OUTPUT_HINT_MARKERS = (
    "pdf",
    "one-page",
    "onepage",
    "summary",
    "презентац",
    "документ",
    "файл",
    "карточк",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the discovery-first factory business analyst flow.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run = subparsers.add_parser("run", help="Build or refresh one discovery session snapshot")
    run.add_argument("--source", required=True, help="Path to a raw request or discovery session JSON document")
    run.add_argument("--output", help="Optional JSON output path (stdout when omitted)")
    run.add_argument("--project-key", help="Override normalized project key")
    run.add_argument("--session-id", help="Override normalized discovery session id")
    return parser.parse_args()


def load_source_document(path: str) -> dict[str, Any]:
    payload = load_json(path)
    if not isinstance(payload, dict):
        raise ValueError("source document must be a JSON object")
    return payload


def normalize_requester_identity(payload: dict[str, Any], existing_session: dict[str, Any]) -> dict[str, Any]:
    requester_identity = payload.get("requester_identity", {})
    if isinstance(requester_identity, dict) and requester_identity:
        return requester_identity
    existing_identity = existing_session.get("requester_identity", {})
    if isinstance(existing_identity, dict):
        return existing_identity
    return {}


def extract_raw_idea(payload: dict[str, Any], conversation_turns: list[dict[str, Any]]) -> str:
    raw_idea = normalize_text(payload.get("raw_idea")) or normalize_text(payload.get("raw_problem_statement"))
    if raw_idea:
        return raw_idea
    for turn in conversation_turns:
        if normalize_text(turn.get("actor")) != "user":
            continue
        if normalize_text(turn.get("turn_type")) != "idea_statement":
            continue
        text = normalize_text(turn.get("raw_text"))
        if text:
            return text
    return ""


def next_turn_id(conversation_turns: list[dict[str, Any]]) -> str:
    max_index = 0
    for turn in conversation_turns:
        match = re.search(r"(\d+)$", normalize_text(turn.get("turn_id")))
        if not match:
            continue
        max_index = max(max_index, int(match.group(1)))
    return f"turn-{max_index + 1:03d}"


def pending_agent_question(conversation_turns: list[dict[str, Any]]) -> tuple[str, str]:
    if not conversation_turns:
        return ("", "")
    last_turn = conversation_turns[-1]
    if normalize_text(last_turn.get("actor")) != "agent":
        return ("", "")
    if normalize_text(last_turn.get("turn_type")) != "clarifying_question":
        return ("", "")
    extracted_topics = last_turn.get("extracted_topics", [])
    next_topic = ""
    if isinstance(extracted_topics, list) and extracted_topics:
        next_topic = canonical_discovery_topic_name(extracted_topics[0])
    return (next_topic, normalize_text(last_turn.get("raw_text")))


def normalize_conversation_turns(payload: dict[str, Any]) -> list[dict[str, Any]]:
    turns = payload.get("conversation_turns", [])
    if not isinstance(turns, list):
        return []
    return [turn for turn in turns if isinstance(turn, dict)]


def normalized_answers_from_payload(payload: dict[str, Any], raw_idea: str) -> dict[str, Any]:
    answers: dict[str, Any] = {}

    for container_key in ("captured_answers", "discovery_answers"):
        container = payload.get(container_key, {})
        if not isinstance(container, dict):
            continue
        for key, value in container.items():
            canonical = canonical_discovery_topic_name(key)
            if not canonical:
                continue
            answers[canonical] = value

    existing_topics = payload.get("requirement_topics", [])
    if isinstance(existing_topics, list):
        for topic in existing_topics:
            if not isinstance(topic, dict):
                continue
            canonical = canonical_discovery_topic_name(topic.get("topic_name"))
            if not canonical:
                continue
            if canonical not in answers and normalize_text(topic.get("summary")):
                answers[canonical] = topic.get("summary")

    existing_brief = payload.get("requirement_brief", {})
    if isinstance(existing_brief, dict):
        for topic_name, brief_field in BRIEF_TOPIC_FIELD_MAP.items():
            if topic_name in answers:
                continue
            value = existing_brief.get(brief_field)
            if value not in (None, "", []):
                answers[topic_name] = value

    example_cases = payload.get("example_cases", [])
    if isinstance(example_cases, list) and example_cases:
        if "input_examples" not in answers:
            input_examples = [
                normalize_text(case.get("input_summary"))
                for case in example_cases
                if isinstance(case, dict) and normalize_text(case.get("input_summary"))
            ]
            if input_examples:
                answers["input_examples"] = input_examples
        if "expected_outputs" not in answers:
            expected_outputs = [
                normalize_text(case.get("expected_output_summary"))
                for case in example_cases
                if isinstance(case, dict) and normalize_text(case.get("expected_output_summary"))
            ]
            if expected_outputs:
                answers["expected_outputs"] = expected_outputs

    if raw_idea and "problem" not in answers:
        answers["problem"] = raw_idea

    if "expected_outputs" not in answers:
        desired_outcome = normalize_text(answers.get("desired_outcome"))
        if desired_outcome:
            lowered = desired_outcome.lower()
            if any(marker in lowered for marker in EXPECTED_OUTPUT_HINT_MARKERS):
                answers["expected_outputs"] = [desired_outcome]

    return answers


def existing_topics_by_name(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    topics = payload.get("requirement_topics", [])
    if not isinstance(topics, list):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for topic in topics:
        if not isinstance(topic, dict):
            continue
        canonical = canonical_discovery_topic_name(topic.get("topic_name"))
        if canonical:
            result[canonical] = topic
    return result


def normalize_clarification_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    clarifications = payload.get("clarification_items", [])
    if not isinstance(clarifications, list):
        return []
    return [item for item in clarifications if isinstance(item, dict)]


def apply_clarifications_to_topics(requirement_topics: list[dict[str, Any]], clarification_items: list[dict[str, Any]]) -> None:
    open_topics = {
        canonical_discovery_topic_name(item.get("topic_name"))
        for item in clarification_items
        if normalize_text(item.get("status")) == "open"
    }
    for topic in requirement_topics:
        canonical = canonical_discovery_topic_name(topic.get("topic_name"))
        if canonical in open_topics:
            topic["status"] = "unresolved"
            continue
        if normalize_text(topic.get("status")) == "unresolved" and normalize_text(topic.get("summary")):
            # Release stale unresolved status once clarification items are resolved.
            topic["status"] = "clarified"


def first_open_clarification(clarification_items: list[dict[str, Any]]) -> dict[str, Any] | None:
    for item in clarification_items:
        if normalize_text(item.get("status")) == "open":
            return item
    return None


def build_requirement_topics(payload: dict[str, Any], raw_idea: str, now: str) -> list[dict[str, Any]]:
    answers = normalized_answers_from_payload(payload, raw_idea)
    existing_topics = existing_topics_by_name(payload)
    requirement_topics: list[dict[str, Any]] = []
    for topic_name in discovery_topic_names():
        existing_topic = existing_topics.get(topic_name)
        value = answers.get(topic_name)
        source_turn_ids = list(existing_topic.get("source_turn_ids", [])) if existing_topic else []
        requirement_topics.append(
            build_discovery_topic(
                topic_name,
                value,
                now,
                existing_topic=existing_topic,
                source_turn_ids=source_turn_ids,
            )
        )
    requirement_topics.sort(key=lambda topic: discovery_topic_names().index(topic["topic_name"]))
    return requirement_topics


def determine_guidance(
    requirement_topics: list[dict[str, Any]],
    clarification_items: list[dict[str, Any]],
) -> tuple[str, str, str, str]:
    open_clarification = first_open_clarification(clarification_items)
    if open_clarification:
        next_topic = canonical_discovery_topic_name(open_clarification.get("topic_name"))
        next_question = normalize_text(open_clarification.get("question_text")) or discovery_topic_question(next_topic)
        return ("awaiting_clarification", "resolve_clarification", next_topic, next_question)

    next_topic = discovery_next_topic(requirement_topics)
    if next_topic:
        return ("awaiting_user_reply", "ask_next_question", next_topic, discovery_topic_question(next_topic))

    return ("in_progress", "prepare_brief", "", "")


def ensure_conversation_turns(
    conversation_turns: list[dict[str, Any]],
    raw_idea: str,
    next_topic: str,
    next_question: str,
    clarification_item: dict[str, Any] | None,
    now: str,
) -> list[dict[str, Any]]:
    turns = list(conversation_turns)
    if not turns and raw_idea:
        turns.append(
            {
                "turn_id": "turn-001",
                "actor": "user",
                "turn_type": "idea_statement",
                "raw_text": raw_idea,
                "extracted_topics": ["problem"],
                "linked_clarification_ids": [],
                "recorded_at": now,
            }
        )

    if not next_question:
        return turns

    if turns:
        last_turn = turns[-1]
        if normalize_text(last_turn.get("actor")) == "agent" and normalize_text(last_turn.get("raw_text")) == next_question:
            return turns

    turns.append(
        {
            "turn_id": next_turn_id(turns),
            "actor": "agent",
            "turn_type": "clarifying_question",
            "raw_text": next_question,
            "extracted_topics": [next_topic] if next_topic else [],
            "linked_clarification_ids": [normalize_text(clarification_item.get("clarification_item_id"))] if clarification_item else [],
            "recorded_at": now,
        }
    )
    return turns


def build_discovery_session(
    payload: dict[str, Any],
    *,
    project_key_override: str | None,
    session_id_override: str | None,
    requester_identity: dict[str, Any],
    status: str,
    next_action: str,
    next_topic: str,
    now: str,
) -> dict[str, Any]:
    existing = payload.get("discovery_session", {})
    existing = existing if isinstance(existing, dict) else {}
    project_key = normalize_text(project_key_override) or normalize_text(payload.get("project_key")) or normalize_text(existing.get("project_key"))
    if not project_key:
        seed = normalize_text(payload.get("raw_idea")) or normalize_text(payload.get("raw_problem_statement")) or "discovery-project"
        project_key = slugify(seed, "project")

    session_id = normalize_text(session_id_override) or normalize_text(existing.get("discovery_session_id")) or f"discovery-session-{project_key}"
    request_channel = normalize_text(payload.get("request_channel")) or normalize_text(existing.get("request_channel")) or "telegram"
    working_language = normalize_text(payload.get("working_language")) or normalize_text(existing.get("working_language")) or "ru"

    return {
        "discovery_session_id": session_id,
        "project_key": project_key,
        "request_channel": request_channel,
        "requester_identity": requester_identity,
        "working_language": working_language,
        "status": status,
        "current_topic": next_topic or normalize_text(existing.get("current_topic")) or "",
        "next_recommended_action": next_action,
        "latest_brief_version": normalize_text(existing.get("latest_brief_version")),
        "created_at": normalize_text(existing.get("created_at")) or now,
        "updated_at": now,
    }


def build_open_questions(clarification_items: list[dict[str, Any]], next_question: str) -> list[str]:
    questions = [
        normalize_text(item.get("question_text"))
        for item in clarification_items
        if normalize_text(item.get("status")) == "open" and normalize_text(item.get("question_text"))
    ]
    if questions:
        return questions
    if next_question:
        return [next_question]
    return []


def normalize_requirement_brief(payload: dict[str, Any]) -> dict[str, Any]:
    requirement_brief = payload.get("requirement_brief", {})
    if isinstance(requirement_brief, dict):
        return dict(requirement_brief)
    return {}


def normalize_brief_revisions(payload: dict[str, Any]) -> list[dict[str, Any]]:
    revisions = payload.get("brief_revisions", [])
    if not isinstance(revisions, list):
        return []
    return [dict(item) for item in revisions if isinstance(item, dict)]


def normalize_confirmation_snapshot(payload: dict[str, Any]) -> dict[str, Any]:
    snapshot = payload.get("confirmation_snapshot", {})
    if isinstance(snapshot, dict):
        return dict(snapshot)
    return {}


def normalize_factory_handoff_record(payload: dict[str, Any]) -> dict[str, Any]:
    record = payload.get("factory_handoff_record", {})
    if isinstance(record, dict):
        return dict(record)
    return {}


def normalize_confirmation_history(payload: dict[str, Any]) -> list[dict[str, Any]]:
    return normalize_dict_list(payload.get("confirmation_history"))


def normalize_handoff_history(payload: dict[str, Any]) -> list[dict[str, Any]]:
    return normalize_dict_list(payload.get("handoff_history"))


def normalize_brief_feedback_history(payload: dict[str, Any]) -> list[dict[str, Any]]:
    return normalize_dict_list(payload.get("brief_feedback_history"))


def feedback_requested_by(requester_identity: dict[str, Any]) -> str:
    return (
        normalize_text(requester_identity.get("display_name"))
        or normalize_text(requester_identity.get("telegram_user_id"))
        or "unknown-requester"
    )


def append_feedback_history_entry(
    feedback_history: list[dict[str, Any]],
    *,
    brief_id: str,
    source_brief_version: str,
    feedback_text: str,
    requested_by: str,
    now: str,
) -> list[dict[str, Any]]:
    text = normalize_text(feedback_text)
    if not text:
        return feedback_history
    if feedback_history:
        last = feedback_history[-1]
        if (
            normalize_text(last.get("feedback_text")) == text
            and normalize_text(last.get("source_brief_version")) == normalize_text(source_brief_version)
            and normalize_text(last.get("status")) in {"recorded", "applied"}
        ):
            return feedback_history
    updated = list(feedback_history)
    updated.append(
        {
            "brief_feedback_id": next_numbered_id(updated, "brief_feedback_id", "brief-feedback-"),
            "brief_id": brief_id,
            "source_brief_version": normalize_text(source_brief_version),
            "feedback_text": text,
            "requested_by": requested_by,
            "requested_at": now,
            "status": "recorded",
            "applied_in_brief_version": "",
        }
    )
    return updated


def mark_feedback_applied(
    feedback_history: list[dict[str, Any]],
    *,
    source_brief_version: str,
    applied_in_brief_version: str,
    now: str,
) -> list[dict[str, Any]]:
    source_version = normalize_text(source_brief_version)
    applied_version = normalize_text(applied_in_brief_version)
    if not source_version or not applied_version:
        return feedback_history
    updated: list[dict[str, Any]] = []
    for item in feedback_history:
        if not isinstance(item, dict):
            continue
        cloned = dict(item)
        if (
            normalize_text(cloned.get("status")) == "recorded"
            and normalize_text(cloned.get("source_brief_version")) == source_version
            and not normalize_text(cloned.get("applied_in_brief_version"))
        ):
            cloned["status"] = "applied"
            cloned["applied_in_brief_version"] = applied_version
            cloned["applied_at"] = now
        updated.append(cloned)
    return updated


def normalize_example_cases(payload: dict[str, Any], existing_brief: dict[str, Any]) -> list[dict[str, Any]]:
    explicit_cases = payload.get("example_cases", [])
    business_rules = normalize_brief_section_value(
        "business_rules",
        brief_value_from_payload(payload, "business_rules") or existing_brief.get("business_rules"),
    )
    exceptions = normalize_brief_section_value(
        "exceptions",
        brief_value_from_payload(payload, "exceptions") or existing_brief.get("exceptions"),
    )

    normalized_cases: list[dict[str, Any]] = []
    if isinstance(explicit_cases, list) and explicit_cases:
        for index, raw_case in enumerate(explicit_cases, start=1):
            if not isinstance(raw_case, dict):
                continue
            linked_rules = normalize_brief_section_value(
                "business_rules",
                raw_case.get("linked_rules") or business_rules,
            )
            exception_notes = normalize_text(raw_case.get("exception_notes"))
            data_safety_status = normalize_text(raw_case.get("data_safety_status")) or discovery_example_data_safety_status(
                raw_case.get("input_summary"),
                raw_case.get("expected_output_summary"),
                linked_rules,
                exception_notes,
            )
            normalized_cases.append(
                {
                    "example_case_id": normalize_text(raw_case.get("example_case_id")) or f"example-case-{index:03d}",
                    "case_type": normalize_text(raw_case.get("case_type")) or "representative",
                    "input_summary": normalize_text(raw_case.get("input_summary")),
                    "expected_output_summary": normalize_text(raw_case.get("expected_output_summary")),
                    "linked_rules": linked_rules,
                    "exception_notes": exception_notes,
                    "data_safety_status": data_safety_status,
                }
            )
        return normalized_cases

    input_examples = normalize_brief_section_value(
        "input_examples",
        brief_value_from_payload(payload, "input_examples") or existing_brief.get("input_examples"),
    )
    expected_outputs = normalize_brief_section_value(
        "expected_outputs",
        brief_value_from_payload(payload, "expected_outputs") or existing_brief.get("expected_outputs"),
    )

    if not input_examples and not expected_outputs:
        return []

    total_cases = max(len(input_examples), len(expected_outputs), 1)
    for index in range(total_cases):
        input_summary = input_examples[index] if index < len(input_examples) else ""
        expected_output_summary = expected_outputs[index] if index < len(expected_outputs) else ""
        exception_notes = "; ".join(exceptions) if exceptions and index == 0 else ""
        normalized_cases.append(
            {
                "example_case_id": f"example-case-{index + 1:03d}",
                "case_type": "representative",
                "input_summary": input_summary,
                "expected_output_summary": expected_output_summary,
                "linked_rules": business_rules,
                "exception_notes": exception_notes,
                "data_safety_status": discovery_example_data_safety_status(
                    input_summary,
                    expected_output_summary,
                    business_rules,
                    exception_notes,
                ),
            }
        )
    return normalized_cases


def clarification_item_from_example_case(
    *,
    clarification_id: str,
    topic_name: str,
    reason: str,
    question_text: str,
    existing_item: dict[str, Any] | None,
    now: str,
) -> dict[str, Any]:
    existing = existing_item or {}
    return {
        "clarification_item_id": clarification_id,
        "topic_name": topic_name,
        "reason": reason,
        "status": "open",
        "question_text": question_text,
        "opened_at": normalize_text(existing.get("opened_at")) or now,
        "resolved_at": "",
    }


def generated_example_clarifications(
    example_cases: list[dict[str, Any]],
    payload: dict[str, Any],
    existing_brief: dict[str, Any],
    existing_clarifications: list[dict[str, Any]],
    now: str,
) -> list[dict[str, Any]]:
    business_rules = normalize_brief_section_value(
        "business_rules",
        brief_value_from_payload(payload, "business_rules") or existing_brief.get("business_rules"),
    )
    constraints = normalize_brief_section_value(
        "constraints",
        brief_value_from_payload(payload, "constraints") or existing_brief.get("constraints"),
    )
    existing_by_id = {
        normalize_text(item.get("clarification_item_id")): item
        for item in existing_clarifications
        if normalize_text(item.get("clarification_item_id"))
    }
    generated: list[dict[str, Any]] = []
    for case in example_cases:
        case_id = normalize_text(case.get("example_case_id")) or "example-case"
        input_summary = normalize_text(case.get("input_summary"))
        expected_output_summary = normalize_text(case.get("expected_output_summary"))
        linked_rules = normalize_brief_section_value("business_rules", case.get("linked_rules"))
        exception_notes = normalize_text(case.get("exception_notes"))
        if normalize_text(case.get("data_safety_status")) == "needs_redaction":
            clarification_id = f"clarification-unsafe-{case_id}"
            generated.append(
                clarification_item_from_example_case(
                    clarification_id=clarification_id,
                    topic_name="input_examples",
                    reason="unsafe_data_example",
                    question_text=(
                        f"Можешь прислать пример '{input_summary or case_id}' без реальных реквизитов, номеров и названий контрагентов?"
                    ),
                    existing_item=existing_by_id.get(clarification_id),
                    now=now,
                )
            )
        contradictions = discovery_example_contradictions(
            input_summary=input_summary,
            expected_output_summary=expected_output_summary,
            linked_rules=linked_rules,
            business_rules=business_rules,
            constraints=constraints,
            exception_notes=exception_notes,
        )
        for index, contradiction in enumerate(contradictions, start=1):
            clarification_id = f"clarification-contradiction-{case_id}-{index:03d}"
            generated.append(
                clarification_item_from_example_case(
                    clarification_id=clarification_id,
                    topic_name="expected_outputs",
                    reason="contradictory_examples",
                    question_text=(
                        f"В примере '{input_summary or case_id}' есть противоречие: {contradiction} "
                        "Какой результат агент должен считать правильным в этом кейсе?"
                    ),
                    existing_item=existing_by_id.get(clarification_id),
                    now=now,
                )
            )
    return generated


def reconcile_clarification_items(
    existing_clarifications: list[dict[str, Any]],
    generated_clarifications: list[dict[str, Any]],
    now: str,
) -> list[dict[str, Any]]:
    generated_by_id = {
        normalize_text(item.get("clarification_item_id")): item
        for item in generated_clarifications
        if normalize_text(item.get("clarification_item_id"))
    }
    reconciled: list[dict[str, Any]] = []
    for item in existing_clarifications:
        clarification_id = normalize_text(item.get("clarification_item_id"))
        reason = normalize_text(item.get("reason"))
        if clarification_id in generated_by_id:
            merged = dict(item)
            merged.update(generated_by_id[clarification_id])
            merged["status"] = "open"
            merged["resolved_at"] = ""
            reconciled.append(merged)
            generated_by_id.pop(clarification_id, None)
            continue
        if reason in {"unsafe_data_example", "contradictory_examples"} and normalize_text(item.get("status")) == "open":
            resolved_item = dict(item)
            resolved_item["status"] = "resolved"
            resolved_item["resolved_at"] = normalize_text(item.get("resolved_at")) or now
            reconciled.append(resolved_item)
            continue
        reconciled.append(dict(item))
    reconciled.extend(generated_by_id.values())
    return reconciled


def example_case_brief_values(example_cases: list[dict[str, Any]], field_name: str) -> list[str]:
    values: list[str] = []
    for case in example_cases:
        if field_name == "input_examples":
            text = normalize_text(case.get("input_summary"))
            if text:
                values.append(text)
        elif field_name == "expected_outputs":
            text = normalize_text(case.get("expected_output_summary"))
            if text:
                values.append(text)
        elif field_name == "business_rules":
            values.extend(normalize_brief_section_value("business_rules", case.get("linked_rules")))
        elif field_name == "exceptions":
            text = normalize_text(case.get("exception_notes"))
            if text:
                values.append(text)
    return dedupe_preserve_order(values)


def normalize_brief_section_value(field_name: str, value: Any) -> Any:
    if field_name in BRIEF_LIST_FIELDS:
        if isinstance(value, list):
            return dedupe_preserve_order(normalize_list(value))
        text = normalize_text(value)
        if not text:
            return []
        if ";" in text:
            return dedupe_preserve_order([part.strip() for part in text.split(";") if part.strip()])
        values = normalize_list(text)
        if values:
            return dedupe_preserve_order(values)
        return [text]
    return normalize_text(value)


def brief_sections_equal(field_name: str, left: Any, right: Any) -> bool:
    return normalize_brief_section_value(field_name, left) == normalize_brief_section_value(field_name, right)


def next_brief_version(version: str) -> str:
    text = normalize_text(version)
    if not text:
        return "1.0"
    match = re.fullmatch(r"(\d+)\.(\d+)", text)
    if not match:
        return "1.0"
    major, minor = (int(part) for part in match.groups())
    return f"{major}.{minor + 1}"


def next_numbered_id(items: list[dict[str, Any]], field_name: str, prefix: str) -> str:
    max_index = 0
    for item in items:
        match = re.search(r"(\d+)$", normalize_text(item.get(field_name)))
        if not match:
            continue
        max_index = max(max_index, int(match.group(1)))
    return f"{prefix}{max_index + 1:03d}"


def topic_summary_by_name(requirement_topics: list[dict[str, Any]], topic_name: str) -> str:
    canonical = canonical_discovery_topic_name(topic_name)
    for topic in requirement_topics:
        if canonical_discovery_topic_name(topic.get("topic_name")) == canonical:
            return normalize_text(topic.get("summary"))
    return ""


def brief_value_from_payload(payload: dict[str, Any], field_name: str) -> Any:
    aliases = BRIEF_SECTION_ALIASES.get(field_name, [field_name])
    for container_name in ("brief_section_updates", "captured_answers", "discovery_answers"):
        container = payload.get(container_name, {})
        if not isinstance(container, dict):
            continue
        for alias in aliases:
            value = container.get(alias)
            if value not in (None, "", []):
                return value
    for alias in aliases:
        value = payload.get(alias)
        if value not in (None, "", []):
            return value
    return None


def derived_open_risks(
    requirement_topics: list[dict[str, Any]],
    clarification_items: list[dict[str, Any]],
) -> list[str]:
    risks: list[str] = []
    for item in clarification_items:
        if normalize_text(item.get("status")) != "open":
            continue
        question_text = normalize_text(item.get("question_text"))
        if question_text:
            risks.append(question_text)
    for topic in requirement_topics:
        status = normalize_text(topic.get("status"))
        if status not in {"partial", "unresolved"}:
            continue
        topic_name = canonical_discovery_topic_name(topic.get("topic_name"))
        if not topic_name:
            continue
        risks.append(f"Тема '{topic_name}' требует дополнительного уточнения")
    return dedupe_preserve_order(risks)


def build_requirement_brief_candidate(
    payload: dict[str, Any],
    requirement_topics: list[dict[str, Any]],
    clarification_items: list[dict[str, Any]],
    example_cases: list[dict[str, Any]],
    existing_brief: dict[str, Any],
    requester_identity: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    project_key = (
        normalize_text(payload.get("project_key"))
        or normalize_text(existing_brief.get("project_key"))
        or normalize_text(payload.get("discovery_session", {}).get("project_key"))
    )
    if not project_key:
        project_key = slugify("discovery-brief", "project")

    constraints = normalize_brief_section_value(
        "constraints",
        brief_value_from_payload(payload, "constraints")
        or existing_brief.get("constraints")
        or topic_summary_by_name(requirement_topics, "constraints"),
    )

    return {
        "brief_id": normalize_text(existing_brief.get("brief_id")) or f"brief-{project_key}",
        "discovery_session_id": (
            normalize_text(payload.get("discovery_session", {}).get("discovery_session_id"))
            or normalize_text(existing_brief.get("discovery_session_id"))
            or f"discovery-session-{project_key}"
        ),
        "project_key": project_key,
        "version": normalize_text(existing_brief.get("version")),
        "problem_statement": (
            brief_value_from_payload(payload, "problem_statement")
            or normalize_text(existing_brief.get("problem_statement"))
            or topic_summary_by_name(requirement_topics, "problem")
        ),
        "target_users": normalize_brief_section_value(
            "target_users",
            brief_value_from_payload(payload, "target_users")
            or existing_brief.get("target_users")
            or topic_summary_by_name(requirement_topics, "target_users")
        ),
        "current_process": (
            brief_value_from_payload(payload, "current_process")
            or normalize_text(existing_brief.get("current_process"))
            or topic_summary_by_name(requirement_topics, "current_workflow")
        ),
        "desired_outcome": (
            brief_value_from_payload(payload, "desired_outcome")
            or normalize_text(existing_brief.get("desired_outcome"))
            or topic_summary_by_name(requirement_topics, "desired_outcome")
        ),
        "scope_boundaries": normalize_brief_section_value(
            "scope_boundaries",
            brief_value_from_payload(payload, "scope_boundaries")
            or existing_brief.get("scope_boundaries")
            or constraints,
        ),
        "user_story": (
            brief_value_from_payload(payload, "user_story")
            or normalize_text(existing_brief.get("user_story"))
            or topic_summary_by_name(requirement_topics, "user_story")
        ),
        "input_examples": normalize_brief_section_value(
            "input_examples",
            brief_value_from_payload(payload, "input_examples")
            or existing_brief.get("input_examples")
            or topic_summary_by_name(requirement_topics, "input_examples")
            or example_case_brief_values(example_cases, "input_examples"),
        ),
        "expected_outputs": normalize_brief_section_value(
            "expected_outputs",
            brief_value_from_payload(payload, "expected_outputs")
            or existing_brief.get("expected_outputs")
            or topic_summary_by_name(requirement_topics, "expected_outputs")
            or example_case_brief_values(example_cases, "expected_outputs"),
        ),
        "business_rules": normalize_brief_section_value(
            "business_rules",
            brief_value_from_payload(payload, "business_rules")
            or existing_brief.get("business_rules")
            or example_case_brief_values(example_cases, "business_rules"),
        ),
        "exceptions": normalize_brief_section_value(
            "exceptions",
            brief_value_from_payload(payload, "exceptions")
            or existing_brief.get("exceptions")
            or example_case_brief_values(example_cases, "exceptions"),
        ),
        "constraints": constraints,
        "success_metrics": normalize_brief_section_value(
            "success_metrics",
            brief_value_from_payload(payload, "success_metrics")
            or existing_brief.get("success_metrics")
            or topic_summary_by_name(requirement_topics, "success_metrics")
        ),
        "open_risks": normalize_brief_section_value(
            "open_risks",
            brief_value_from_payload(payload, "open_risks")
            or existing_brief.get("open_risks")
            or derived_open_risks(requirement_topics, clarification_items),
        ),
        "status": normalize_text(existing_brief.get("status")) or "draft",
        "created_at": normalize_text(existing_brief.get("created_at")) or now,
        "updated_at": now,
        "owner": normalize_text(requester_identity.get("display_name")) or "Не указан",
    }


def brief_changed_sections(existing_brief: dict[str, Any], candidate_brief: dict[str, Any]) -> list[str]:
    if not existing_brief:
        return list(BRIEF_SECTION_ORDER)
    changed_sections: list[str] = []
    for field_name in BRIEF_SECTION_ORDER:
        if not brief_sections_equal(field_name, existing_brief.get(field_name), candidate_brief.get(field_name)):
            changed_sections.append(field_name)
    return changed_sections


def normalize_confirmation_reply(
    payload: dict[str, Any],
    requester_identity: dict[str, Any],
) -> dict[str, Any]:
    reply = payload.get("confirmation_reply", {})
    if not isinstance(reply, dict):
        return {}
    if reply.get("confirmed") is not True:
        return {}
    confirmed_by = (
        normalize_text(reply.get("confirmed_by"))
        or normalize_text(requester_identity.get("telegram_user_id"))
        or normalize_text(requester_identity.get("display_name"))
        or "unknown-requester"
    )
    return {
        "confirmed": True,
        "confirmed_by": confirmed_by,
        "confirmation_text": normalize_text(reply.get("confirmation_text")) or "Да, brief подтвержден.",
    }


def build_brief_revision(
    brief_id: str,
    version: str,
    existing_revisions: list[dict[str, Any]],
    change_reason: str,
    changed_sections: list[str],
    requested_by: str,
    now: str,
) -> dict[str, Any]:
    return {
        "brief_revision_id": next_numbered_id(existing_revisions, "brief_revision_id", "brief-revision-"),
        "brief_id": brief_id,
        "version": version,
        "change_reason": change_reason,
        "changed_sections": changed_sections,
        "requested_by": requested_by,
        "created_at": now,
    }


def build_confirmation_snapshot(
    brief: dict[str, Any],
    existing_snapshot: dict[str, Any],
    confirmation_history: list[dict[str, Any]],
    confirmation_reply: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    known_snapshots = list(confirmation_history)
    if existing_snapshot:
        known_snapshots.append(existing_snapshot)
    return {
        "confirmation_snapshot_id": next_numbered_id(known_snapshots, "confirmation_snapshot_id", "confirmation-snapshot-"),
        "brief_id": brief["brief_id"],
        "brief_version": brief["version"],
        "confirmed_by": confirmation_reply["confirmed_by"],
        "confirmation_text": confirmation_reply["confirmation_text"],
        "confirmed_at": now,
        "status": "active",
    }


def append_turn_if_missing(
    conversation_turns: list[dict[str, Any]],
    *,
    actor: str,
    turn_type: str,
    raw_text: str,
    extracted_topics: list[str] | None,
    now: str,
) -> list[dict[str, Any]]:
    text = normalize_text(raw_text)
    if not text:
        return conversation_turns
    if conversation_turns:
        last_turn = conversation_turns[-1]
        if (
            normalize_text(last_turn.get("actor")) == actor
            and normalize_text(last_turn.get("turn_type")) == turn_type
            and normalize_text(last_turn.get("raw_text")) == text
        ):
            return conversation_turns
    updated_turns = list(conversation_turns)
    updated_turns.append(
        {
            "turn_id": next_turn_id(updated_turns),
            "actor": actor,
            "turn_type": turn_type,
            "raw_text": text,
            "extracted_topics": extracted_topics or [],
            "linked_clarification_ids": [],
            "recorded_at": now,
        }
    )
    return updated_turns


def brief_agent_name(payload: dict[str, Any], brief: dict[str, Any]) -> str:
    explicit_name = normalize_text(payload.get("agent_name"))
    if explicit_name:
        return explicit_name
    updates = payload.get("brief_section_updates", {})
    if isinstance(updates, dict):
        explicit_name = normalize_text(updates.get("agent_name"))
        if explicit_name:
            return explicit_name
    project_key = normalize_text(brief.get("project_key"))
    if project_key:
        return f"AI-агент проекта {project_key}"
    return "Новый AI-агент"


def brief_confirmation_guidance(brief_status: str) -> str:
    if brief_status == "confirmed":
        return "Brief уже явно подтвержден пользователем и готов к следующему этапу фабрики."
    if brief_status == "reopened":
        return "Brief переоткрыт. Сначала проверь актуальную версию, затем заново подтверди ее."
    return (
        "Проверь, что summary корректно отражает задачу бизнеса. Если нужно, попроси поправить конкретные разделы. "
        "Если все верно, явно подтверди brief."
    )


def brief_next_step_summary(brief_status: str) -> str:
    if brief_status == "confirmed":
        return "Brief подтвержден. Следующий шаг: подготовить canonical handoff в downstream concept-pack pipeline."
    return "Следующий шаг: получить явное подтверждение brief или внести поправки до downstream handoff."


def handoff_blocking_reasons(
    brief: dict[str, Any],
    confirmation_snapshot: dict[str, Any],
    clarification_items: list[dict[str, Any]],
) -> list[str]:
    reasons: list[str] = []
    brief_status = normalize_text(brief.get("status"))
    brief_id = normalize_text(brief.get("brief_id"))
    brief_version = normalize_text(brief.get("version"))
    snapshot_status = normalize_text(confirmation_snapshot.get("status"))
    snapshot_brief_id = normalize_text(confirmation_snapshot.get("brief_id"))
    snapshot_brief_version = normalize_text(confirmation_snapshot.get("brief_version"))
    open_clarification_ids = [
        normalize_text(item.get("clarification_item_id"))
        for item in clarification_items
        if normalize_text(item.get("status")) == "open"
    ]

    if brief_status != "confirmed":
        reasons.append("Requirement brief еще не подтвержден.")
    if snapshot_status != "active":
        reasons.append("Нет активного confirmation snapshot для текущей версии brief.")
    if brief_id and snapshot_brief_id and brief_id != snapshot_brief_id:
        reasons.append("Confirmation snapshot ссылается на другой brief.")
    if brief_version and snapshot_brief_version and brief_version != snapshot_brief_version:
        reasons.append("Confirmation snapshot относится к другой версии brief.")
    if open_clarification_ids:
        reasons.append("Есть незакрытые clarification items, handoff должен оставаться заблокированным.")
    return reasons


def build_factory_handoff_record(
    payload: dict[str, Any],
    discovery_session: dict[str, Any],
    brief: dict[str, Any],
    confirmation_snapshot: dict[str, Any],
    clarification_items: list[dict[str, Any]],
    now: str,
) -> dict[str, Any]:
    brief_status = normalize_text(brief.get("status"))
    if brief_status != "confirmed":
        return {}

    confirmation_reply = payload.get("confirmation_reply", {})
    if isinstance(confirmation_reply, dict) and confirmation_reply.get("confirmed") is True:
        return {}

    existing_record = normalize_factory_handoff_record(payload)
    project_key = (
        normalize_text(brief.get("project_key"))
        or normalize_text(discovery_session.get("project_key"))
        or "discovery-project"
    )
    brief_id = normalize_text(brief.get("brief_id"))
    brief_version = normalize_text(brief.get("version"))
    version_token = brief_version.replace(".", "-") if brief_version else "unknown"
    blocking_reasons = handoff_blocking_reasons(brief, confirmation_snapshot, clarification_items)

    handoff_status = "blocked" if blocking_reasons else "ready"
    existing_status = normalize_text(existing_record.get("handoff_status"))
    if existing_status in {"consumed", "superseded"} and not blocking_reasons:
        handoff_status = existing_status

    record = {
        "factory_handoff_id": normalize_text(existing_record.get("factory_handoff_id"))
        or f"factory-handoff-{project_key}-v{version_token}",
        "discovery_session_id": normalize_text(brief.get("discovery_session_id"))
        or normalize_text(discovery_session.get("discovery_session_id")),
        "brief_id": brief_id,
        "brief_version": brief_version,
        "confirmation_snapshot_id": normalize_text(confirmation_snapshot.get("confirmation_snapshot_id")),
        "handoff_status": handoff_status,
        "next_stage": HANDOFF_NEXT_STAGE if handoff_status in {"ready", "consumed"} else "brief_confirmation",
        "downstream_target": normalize_text(existing_record.get("downstream_target")) or HANDOFF_DOWNSTREAM_TARGET,
        "created_at": normalize_text(existing_record.get("created_at")) or now,
        "consumed_at": normalize_text(existing_record.get("consumed_at")) if handoff_status == "consumed" else "",
    }
    if blocking_reasons:
        record["blocking_reasons"] = blocking_reasons
    return record


def handoff_next_action(factory_handoff_record: dict[str, Any]) -> str:
    handoff_status = normalize_text(factory_handoff_record.get("handoff_status"))
    if handoff_status == "ready":
        return "run_factory_intake"
    if handoff_status == "consumed":
        return "generate_artifacts"
    return "return_to_brief_confirmation"


def build_resume_context(
    discovery_session: dict[str, Any],
    topic_progress: dict[str, Any],
    clarification_items: list[dict[str, Any]],
    conversation_turns: list[dict[str, Any]],
    requirement_brief: dict[str, Any],
    confirmation_snapshot: dict[str, Any],
    confirmation_history: list[dict[str, Any]],
    *,
    existing_session: dict[str, Any],
    next_question: str,
) -> dict[str, Any]:
    if not isinstance(existing_session, dict) or not existing_session:
        return {}

    resumed_from_status = normalize_text(existing_session.get("status"))
    restored_status = normalize_text(discovery_session.get("status"))
    current_topic = normalize_text(discovery_session.get("current_topic"))
    pending_topic, pending_agent_question_text = pending_agent_question(conversation_turns)
    active_question = next_question or pending_agent_question_text
    latest_brief_version = (
        normalize_text(requirement_brief.get("version"))
        or normalize_text(discovery_session.get("latest_brief_version"))
    )
    latest_confirmed_brief_version = normalize_text(confirmation_snapshot.get("brief_version"))
    if not latest_confirmed_brief_version:
        for archived_snapshot in reversed(confirmation_history):
            archived_version = normalize_text(archived_snapshot.get("brief_version"))
            if archived_version:
                latest_confirmed_brief_version = archived_version
                break

    summary_text = "Возобновляю discovery-сессию с сохраненного состояния."
    if restored_status == "awaiting_clarification" and active_question:
        summary_text = (
            f"Возобновляю discovery-сессию: осталось закрыть уточнение по теме "
            f"'{current_topic or pending_topic or 'clarification'}'."
        )
    elif restored_status in {"awaiting_confirmation", "reopened"} and latest_brief_version:
        summary_text = f"Возобновляю discovery-сессию: brief версии {latest_brief_version} ожидает повторной проверки."
    elif restored_status == "confirmed" and latest_confirmed_brief_version:
        summary_text = f"Возобновляю discovery-сессию: подтвержден brief версии {latest_confirmed_brief_version}."

    return {
        "resumed": True,
        "resumed_from_status": resumed_from_status,
        "restored_status": restored_status,
        "current_topic": current_topic or pending_topic,
        "pending_question": active_question,
        "resolved_topic_names": list(topic_progress.get("resolved_topic_names", [])),
        "remaining_topics": list(topic_progress.get("remaining_topics", [])),
        "open_clarification_ids": [
            normalize_text(item.get("clarification_item_id"))
            for item in clarification_items
            if normalize_text(item.get("status")) == "open"
        ],
        "latest_brief_version": latest_brief_version,
        "latest_confirmed_brief_version": latest_confirmed_brief_version,
        "summary_text": summary_text,
    }


def render_requirement_brief_markdown(
    payload: dict[str, Any],
    brief: dict[str, Any],
    discovery_session: dict[str, Any],
    open_questions: list[str],
) -> str:
    context = {
        "project_key": normalize_text(brief.get("project_key")),
        "brief_id": normalize_text(brief.get("brief_id")),
        "brief_version": normalize_text(brief.get("version")),
        "brief_status": normalize_text(brief.get("status")),
        "working_language": normalize_text(discovery_session.get("working_language")) or "ru",
        "owner": normalize_text(brief.get("owner")) or "Не указан",
        "discovery_session_id": normalize_text(brief.get("discovery_session_id")),
        "agent_name": brief_agent_name(payload, brief),
        "problem_statement": normalize_text(brief.get("problem_statement")) or "Не указано",
        "target_users": to_bullets(normalize_brief_section_value("target_users", brief.get("target_users")), "- Не указано"),
        "current_process": normalize_text(brief.get("current_process")) or "Не указано",
        "desired_outcome": normalize_text(brief.get("desired_outcome")) or "Не указано",
        "scope_boundaries": to_bullets(normalize_brief_section_value("scope_boundaries", brief.get("scope_boundaries")), "- Не указано"),
        "user_story": normalize_text(brief.get("user_story")) or "Не указано",
        "input_examples": to_bullets(normalize_brief_section_value("input_examples", brief.get("input_examples")), "- Не указано"),
        "expected_outputs": to_bullets(normalize_brief_section_value("expected_outputs", brief.get("expected_outputs")), "- Не указано"),
        "business_rules": to_bullets(normalize_brief_section_value("business_rules", brief.get("business_rules")), "- Пока не зафиксированы"),
        "exception_cases": to_bullets(normalize_brief_section_value("exceptions", brief.get("exceptions")), "- Пока не зафиксированы"),
        "constraints": to_bullets(normalize_brief_section_value("constraints", brief.get("constraints")), "- Не указано"),
        "success_metrics": to_bullets(normalize_brief_section_value("success_metrics", brief.get("success_metrics")), "- Не указано"),
        "open_risks": to_bullets(normalize_brief_section_value("open_risks", brief.get("open_risks")), "- Нет открытых рисков"),
        "unresolved_questions": to_bullets(open_questions, "- Нет открытых вопросов"),
        "confirmation_guidance": brief_confirmation_guidance(normalize_text(brief.get("status"))),
        "next_recommended_action": brief_next_step_summary(normalize_text(brief.get("status"))),
    }
    return render_template(BRIEF_TEMPLATE_PATH, context)


def process_brief_stage(
    payload: dict[str, Any],
    requirement_topics: list[dict[str, Any]],
    clarification_items: list[dict[str, Any]],
    example_cases: list[dict[str, Any]],
    topic_progress: dict[str, Any],
    discovery_session: dict[str, Any],
    conversation_turns: list[dict[str, Any]],
    requester_identity: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    existing_brief = normalize_requirement_brief(payload)
    existing_revisions = normalize_brief_revisions(payload)
    existing_feedback_history = normalize_brief_feedback_history(payload)
    existing_snapshot = normalize_confirmation_snapshot(payload)
    existing_confirmation_history = normalize_confirmation_history(payload)
    existing_handoff_record = normalize_factory_handoff_record(payload)
    existing_handoff_history = normalize_handoff_history(payload)
    confirmation_reply = normalize_confirmation_reply(payload, requester_identity)
    correction_text = normalize_text(payload.get("brief_feedback_text") or payload.get("correction_request_text"))
    can_prepare_brief = bool(existing_brief) or bool(topic_progress.get("ready_for_brief"))

    if not can_prepare_brief:
        return {
            "conversation_turns": conversation_turns,
            "brief_feedback_history": existing_feedback_history,
        }

    candidate_brief = build_requirement_brief_candidate(
        payload,
        requirement_topics,
        clarification_items,
        example_cases,
        existing_brief,
        requester_identity,
        now,
    )
    changed_sections = brief_changed_sections(existing_brief, candidate_brief)
    open_clarification = first_open_clarification(clarification_items)
    existing_brief_status = normalize_text(existing_brief.get("status"))
    reopening_from_confirmed = existing_brief_status == "confirmed" and bool(changed_sections)
    confirmation_history = list(existing_confirmation_history)
    handoff_history = list(existing_handoff_history)
    feedback_history = list(existing_feedback_history)
    requested_by = feedback_requested_by(requester_identity)

    if correction_text:
        feedback_history = append_feedback_history_entry(
            feedback_history,
            brief_id=normalize_text(existing_brief.get("brief_id")) or normalize_text(candidate_brief.get("brief_id")),
            source_brief_version=normalize_text(existing_brief.get("version")) or normalize_text(candidate_brief.get("version")),
            feedback_text=correction_text,
            requested_by=requested_by,
            now=now,
        )
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="user",
            turn_type="revision_request",
            raw_text=correction_text,
            extracted_topics=["brief_confirmation"],
            now=now,
        )

    if open_clarification and existing_brief:
        next_question = normalize_text(open_clarification.get("question_text")) or discovery_topic_question(
            canonical_discovery_topic_name(open_clarification.get("topic_name"))
        )
        current_brief = candidate_brief if changed_sections else dict(existing_brief)
        revisions = list(existing_revisions)
        if changed_sections:
            current_brief["version"] = next_brief_version(normalize_text(existing_brief.get("version")))
            current_brief["created_at"] = now
            current_brief["updated_at"] = now
            feedback_history = mark_feedback_applied(
                feedback_history,
                source_brief_version=normalize_text(existing_brief.get("version")),
                applied_in_brief_version=normalize_text(current_brief.get("version")),
                now=now,
            )
            revisions.append(
                build_brief_revision(
                    current_brief["brief_id"],
                    current_brief["version"],
                    existing_revisions,
                    correction_text or "Brief обновлен, но требует дополнительного уточнения перед подтверждением",
                    changed_sections,
                    "user" if correction_text else "agent",
                    now,
                )
            )
        if reopening_from_confirmed:
            current_brief["status"] = "reopened"
            confirmation_history = archive_confirmation_snapshot(
                existing_snapshot,
                confirmation_history,
                now=now,
                superseded_by_brief_version=normalize_text(current_brief.get("version")),
                brief_snapshot=existing_brief,
            )
            handoff_history = archive_handoff_record(
                existing_handoff_record,
                handoff_history,
                now=now,
                superseded_by_brief_version=normalize_text(current_brief.get("version")),
            )
        else:
            current_brief["status"] = normalize_text(current_brief.get("status")) or "draft"
        current_brief["owner"] = normalize_text(current_brief.get("owner")) or candidate_brief["owner"]
        open_questions = build_open_questions(clarification_items, next_question)
        return {
            "status": "awaiting_clarification",
            "next_action": "resolve_clarification",
            "next_topic": canonical_discovery_topic_name(open_clarification.get("topic_name")),
            "next_question": next_question,
            "requirement_brief": current_brief,
            "brief_revisions": revisions,
            "brief_feedback_history": feedback_history,
            "confirmation_snapshot": {},
            "confirmation_history": confirmation_history,
            "handoff_history": handoff_history,
            "conversation_turns": conversation_turns,
            "brief_markdown": render_requirement_brief_markdown(payload, current_brief, discovery_session, open_questions),
            "brief_template_path": str(BRIEF_TEMPLATE_PATH),
            "open_questions": open_questions,
        }

    if not existing_brief:
        candidate_brief["version"] = "1.0"
        candidate_brief["status"] = "awaiting_confirmation"
        candidate_brief["created_at"] = now
        candidate_brief["updated_at"] = now
        revisions = [
            build_brief_revision(
                candidate_brief["brief_id"],
                candidate_brief["version"],
                existing_revisions,
                "Собран первый полный черновик brief после discovery dialogue",
                changed_sections,
                "agent",
                now,
            )
        ]
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="agent",
            turn_type="summary",
            raw_text=f"Я собрал черновик requirements brief версии {candidate_brief['version']}.",
            extracted_topics=["brief_confirmation"],
            now=now,
        )
        next_question = BRIEF_CONFIRMATION_PROMPT
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="agent",
            turn_type="confirmation_request",
            raw_text=next_question,
            extracted_topics=["brief_confirmation"],
            now=now,
        )
        open_questions = build_open_questions(clarification_items, next_question)
        return {
            "status": "awaiting_confirmation",
            "next_action": "request_explicit_confirmation",
            "next_topic": "brief_confirmation",
            "next_question": next_question,
            "requirement_brief": candidate_brief,
            "brief_revisions": revisions,
            "brief_feedback_history": feedback_history,
            "confirmation_snapshot": {},
            "conversation_turns": conversation_turns,
            "brief_markdown": render_requirement_brief_markdown(payload, candidate_brief, discovery_session, open_questions),
            "brief_template_path": str(BRIEF_TEMPLATE_PATH),
            "open_questions": open_questions,
        }

    if changed_sections:
        candidate_brief["version"] = next_brief_version(normalize_text(existing_brief.get("version")))
        candidate_brief["status"] = "reopened" if reopening_from_confirmed else "awaiting_confirmation"
        candidate_brief["created_at"] = now
        candidate_brief["updated_at"] = now
        feedback_history = mark_feedback_applied(
            feedback_history,
            source_brief_version=normalize_text(existing_brief.get("version")),
            applied_in_brief_version=normalize_text(candidate_brief.get("version")),
            now=now,
        )
        revisions = list(existing_revisions)
        revisions.append(
            build_brief_revision(
                candidate_brief["brief_id"],
                candidate_brief["version"],
                existing_revisions,
                correction_text or "Пользователь запросил обновление brief перед подтверждением",
                changed_sections,
                "user" if correction_text else "agent",
                now,
            )
        )
        if reopening_from_confirmed:
            confirmation_history = archive_confirmation_snapshot(
                existing_snapshot,
                confirmation_history,
                now=now,
                superseded_by_brief_version=candidate_brief["version"],
                brief_snapshot=existing_brief,
            )
            handoff_history = archive_handoff_record(
                existing_handoff_record,
                handoff_history,
                now=now,
                superseded_by_brief_version=candidate_brief["version"],
            )
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="agent",
            turn_type="summary",
            raw_text=f"Я обновил requirements brief и собрал новую версию {candidate_brief['version']}.",
            extracted_topics=["brief_confirmation"],
            now=now,
        )
        next_question = BRIEF_CONFIRMATION_PROMPT
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="agent",
            turn_type="confirmation_request",
            raw_text=next_question,
            extracted_topics=["brief_confirmation"],
            now=now,
        )
        open_questions = build_open_questions(clarification_items, next_question)
        return {
            "status": "reopened" if reopening_from_confirmed else "awaiting_confirmation",
            "next_action": "request_explicit_confirmation",
            "next_topic": "brief_confirmation",
            "next_question": next_question,
            "requirement_brief": candidate_brief,
            "brief_revisions": revisions,
            "brief_feedback_history": feedback_history,
            "confirmation_snapshot": {},
            "confirmation_history": confirmation_history,
            "handoff_history": handoff_history,
            "conversation_turns": conversation_turns,
            "brief_markdown": render_requirement_brief_markdown(payload, candidate_brief, discovery_session, open_questions),
            "brief_template_path": str(BRIEF_TEMPLATE_PATH),
            "open_questions": open_questions,
        }

    current_brief = dict(existing_brief)
    current_brief["owner"] = normalize_text(current_brief.get("owner")) or candidate_brief["owner"]

    if confirmation_reply and normalize_text(current_brief.get("status")) != "confirmed":
        current_brief["status"] = "confirmed"
        current_brief["updated_at"] = now
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="user",
            turn_type="confirmation_reply",
            raw_text=confirmation_reply["confirmation_text"],
            extracted_topics=["brief_confirmation"],
            now=now,
        )
        return {
            "status": "confirmed",
            "next_action": "start_concept_pack_handoff",
            "next_topic": "handoff",
            "next_question": "",
            "requirement_brief": current_brief,
            "brief_revisions": existing_revisions,
            "brief_feedback_history": feedback_history,
            "confirmation_snapshot": build_confirmation_snapshot(
                current_brief,
                existing_snapshot,
                confirmation_history,
                confirmation_reply,
                now,
            ),
            "confirmation_history": confirmation_history,
            "handoff_history": handoff_history,
            "conversation_turns": conversation_turns,
            "brief_markdown": render_requirement_brief_markdown(payload, current_brief, discovery_session, []),
            "brief_template_path": str(BRIEF_TEMPLATE_PATH),
            "open_questions": [],
        }

    brief_status = normalize_text(current_brief.get("status")) or "awaiting_confirmation"
    if brief_status == "draft":
        brief_status = "awaiting_confirmation"
        current_brief["status"] = brief_status
    next_question = BRIEF_CONFIRMATION_PROMPT if brief_status != "confirmed" else ""
    if next_question:
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="agent",
            turn_type="confirmation_request",
            raw_text=next_question,
            extracted_topics=["brief_confirmation"],
            now=now,
        )
    open_questions = build_open_questions(clarification_items, next_question)
    return {
        "status": brief_status,
        "next_action": "request_explicit_confirmation" if brief_status != "confirmed" else "start_concept_pack_handoff",
        "next_topic": "brief_confirmation" if brief_status != "confirmed" else "handoff",
        "next_question": next_question,
        "requirement_brief": current_brief,
        "brief_revisions": existing_revisions,
        "brief_feedback_history": feedback_history,
        "confirmation_snapshot": existing_snapshot if brief_status == "confirmed" else {},
        "confirmation_history": confirmation_history,
        "handoff_history": handoff_history,
        "conversation_turns": conversation_turns,
        "brief_markdown": render_requirement_brief_markdown(payload, current_brief, discovery_session, open_questions),
        "brief_template_path": str(BRIEF_TEMPLATE_PATH),
        "open_questions": open_questions,
    }


def main() -> int:
    args = parse_args()
    now = utc_now()

    try:
        payload = load_source_document(args.source)
    except Exception as exc:
        print(f'{{"status":"error","error":"{normalize_text(exc)}"}}')
        return 2

    conversation_turns = normalize_conversation_turns(payload)
    raw_idea = extract_raw_idea(payload, conversation_turns)
    existing_brief = normalize_requirement_brief(payload)
    example_cases = normalize_example_cases(payload, existing_brief)
    clarification_items = reconcile_clarification_items(
        normalize_clarification_items(payload),
        generated_example_clarifications(
            example_cases,
            payload,
            existing_brief,
            normalize_clarification_items(payload),
            now,
        ),
        now,
    )
    requirement_topics = build_requirement_topics(payload, raw_idea, now)
    apply_clarifications_to_topics(requirement_topics, clarification_items)
    status, next_action, next_topic, next_question = determine_guidance(requirement_topics, clarification_items)
    pending_topic, pending_question = pending_agent_question(conversation_turns)
    if next_action == "ask_next_question" and pending_question:
        if pending_topic:
            next_topic = pending_topic
        next_question = pending_question
    active_clarification = first_open_clarification(clarification_items)
    conversation_turns = ensure_conversation_turns(
        conversation_turns,
        raw_idea,
        next_topic,
        next_question,
        active_clarification,
        now,
    )
    requester_identity = normalize_requester_identity(payload, payload.get("discovery_session", {}) if isinstance(payload.get("discovery_session"), dict) else {})
    discovery_session = build_discovery_session(
        payload,
        project_key_override=args.project_key,
        session_id_override=args.session_id,
        requester_identity=requester_identity,
        status=status,
        next_action=next_action,
        next_topic=next_topic,
        now=now,
    )
    topic_progress = build_discovery_topic_progress(requirement_topics, clarification_items)
    brief_state = process_brief_stage(
        payload,
        requirement_topics,
        clarification_items,
        example_cases,
        topic_progress,
        discovery_session,
        conversation_turns,
        requester_identity,
        now,
    )
    if normalize_text(brief_state.get("status")):
        status = normalize_text(brief_state.get("status"))
    if normalize_text(brief_state.get("next_action")):
        next_action = normalize_text(brief_state.get("next_action"))
    if normalize_text(brief_state.get("next_topic")):
        next_topic = normalize_text(brief_state.get("next_topic"))
    if "next_question" in brief_state and brief_state.get("next_question") is not None:
        next_question = normalize_text(brief_state.get("next_question"))
    conversation_turns = brief_state.get("conversation_turns", conversation_turns)

    discovery_session["status"] = status
    discovery_session["current_topic"] = next_topic or discovery_session.get("current_topic", "")
    discovery_session["next_recommended_action"] = next_action

    requirement_brief = brief_state.get("requirement_brief", {})
    if isinstance(requirement_brief, dict) and requirement_brief:
        discovery_session["latest_brief_version"] = normalize_text(requirement_brief.get("version"))
    confirmation_snapshot = brief_state.get("confirmation_snapshot")
    if not isinstance(confirmation_snapshot, dict):
        confirmation_snapshot = {}
    confirmation_history = brief_state.get("confirmation_history")
    if not isinstance(confirmation_history, list):
        confirmation_history = normalize_confirmation_history(payload)
    brief_feedback_history = brief_state.get("brief_feedback_history")
    if not isinstance(brief_feedback_history, list):
        brief_feedback_history = normalize_brief_feedback_history(payload)
    handoff_history = brief_state.get("handoff_history")
    if not isinstance(handoff_history, list):
        handoff_history = normalize_handoff_history(payload)
    factory_handoff_record = {}
    if isinstance(requirement_brief, dict) and requirement_brief:
        factory_handoff_record = build_factory_handoff_record(
            payload,
            discovery_session,
            requirement_brief,
            confirmation_snapshot,
            clarification_items,
            now,
        )
    if factory_handoff_record:
        next_action = handoff_next_action(factory_handoff_record)
        next_topic = "handoff"
        next_question = ""
        discovery_session["next_recommended_action"] = next_action

    normalized_answers = {
        topic["topic_name"]: topic["summary"]
        for topic in requirement_topics
        if normalize_text(topic.get("summary"))
    }

    response: dict[str, Any] = {
        "status": status,
        "next_action": next_action,
        "next_topic": next_topic,
        "next_question": next_question,
        "agent_summary": AGENT_SUMMARY,
        "discovery_session": discovery_session,
        "topic_progress": topic_progress,
        "requirement_topics": requirement_topics,
        "clarification_items": clarification_items,
        "example_cases": example_cases,
        "conversation_turns": conversation_turns,
        "open_questions": brief_state.get("open_questions") or build_open_questions(clarification_items, next_question),
        "normalized_answers": normalized_answers,
    }
    if isinstance(requirement_brief, dict) and requirement_brief:
        response["requirement_brief"] = requirement_brief
    brief_revisions = brief_state.get("brief_revisions")
    if isinstance(brief_revisions, list) and brief_revisions:
        response["brief_revisions"] = brief_revisions
    if isinstance(brief_feedback_history, list) and brief_feedback_history:
        response["brief_feedback_history"] = brief_feedback_history
    if isinstance(confirmation_snapshot, dict) and confirmation_snapshot:
        response["confirmation_snapshot"] = confirmation_snapshot
    if isinstance(confirmation_history, list) and confirmation_history:
        response["confirmation_history"] = confirmation_history
    if factory_handoff_record:
        response["factory_handoff_record"] = factory_handoff_record
    if isinstance(handoff_history, list) and handoff_history:
        response["handoff_history"] = handoff_history
    brief_markdown = normalize_text(brief_state.get("brief_markdown"))
    if brief_markdown:
        response["brief_markdown"] = brief_markdown
        response["brief_template_path"] = brief_state.get("brief_template_path")
    resume_context = build_resume_context(
        discovery_session,
        topic_progress,
        clarification_items,
        conversation_turns,
        requirement_brief if isinstance(requirement_brief, dict) else {},
        confirmation_snapshot,
        confirmation_history if isinstance(confirmation_history, list) else [],
        existing_session=payload.get("discovery_session", {}) if isinstance(payload.get("discovery_session"), dict) else {},
        next_question=next_question,
    )
    if resume_context:
        response["resume_context"] = resume_context

    write_json(response, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
