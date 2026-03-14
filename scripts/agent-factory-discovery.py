#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

from agent_factory_common import (
    build_discovery_topic,
    build_discovery_topic_progress,
    canonical_discovery_topic_name,
    dedupe_preserve_order,
    discovery_next_topic,
    discovery_topic_names,
    discovery_topic_question,
    load_json,
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the discovery-first Telegram business analyst flow.")
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

    if raw_idea and "problem" not in answers:
        answers["problem"] = raw_idea

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
        if canonical_discovery_topic_name(topic.get("topic_name")) not in open_topics:
            continue
        topic["status"] = "unresolved"


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
        or topic_summary_by_name(requirement_topics, "constraints")
        or existing_brief.get("constraints"),
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
            or topic_summary_by_name(requirement_topics, "problem")
            or normalize_text(existing_brief.get("problem_statement"))
        ),
        "target_users": normalize_brief_section_value(
            "target_users",
            brief_value_from_payload(payload, "target_users")
            or topic_summary_by_name(requirement_topics, "target_users")
            or existing_brief.get("target_users"),
        ),
        "current_process": (
            brief_value_from_payload(payload, "current_process")
            or topic_summary_by_name(requirement_topics, "current_workflow")
            or normalize_text(existing_brief.get("current_process"))
        ),
        "desired_outcome": (
            brief_value_from_payload(payload, "desired_outcome")
            or topic_summary_by_name(requirement_topics, "desired_outcome")
            or normalize_text(existing_brief.get("desired_outcome"))
        ),
        "scope_boundaries": normalize_brief_section_value(
            "scope_boundaries",
            brief_value_from_payload(payload, "scope_boundaries")
            or existing_brief.get("scope_boundaries")
            or constraints,
        ),
        "user_story": (
            brief_value_from_payload(payload, "user_story")
            or topic_summary_by_name(requirement_topics, "user_story")
            or normalize_text(existing_brief.get("user_story"))
        ),
        "input_examples": normalize_brief_section_value(
            "input_examples",
            brief_value_from_payload(payload, "input_examples")
            or topic_summary_by_name(requirement_topics, "input_examples")
            or existing_brief.get("input_examples"),
        ),
        "expected_outputs": normalize_brief_section_value(
            "expected_outputs",
            brief_value_from_payload(payload, "expected_outputs")
            or topic_summary_by_name(requirement_topics, "expected_outputs")
            or existing_brief.get("expected_outputs"),
        ),
        "business_rules": normalize_brief_section_value(
            "business_rules",
            brief_value_from_payload(payload, "business_rules") or existing_brief.get("business_rules"),
        ),
        "exceptions": normalize_brief_section_value(
            "exceptions",
            brief_value_from_payload(payload, "exceptions") or existing_brief.get("exceptions"),
        ),
        "constraints": constraints,
        "success_metrics": normalize_brief_section_value(
            "success_metrics",
            brief_value_from_payload(payload, "success_metrics")
            or topic_summary_by_name(requirement_topics, "success_metrics")
            or existing_brief.get("success_metrics"),
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
    confirmation_reply: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    return {
        "confirmation_snapshot_id": normalize_text(existing_snapshot.get("confirmation_snapshot_id"))
        or f"confirmation-snapshot-{brief['brief_id']}",
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
    topic_progress: dict[str, Any],
    discovery_session: dict[str, Any],
    conversation_turns: list[dict[str, Any]],
    requester_identity: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    existing_brief = normalize_requirement_brief(payload)
    existing_revisions = normalize_brief_revisions(payload)
    existing_snapshot = normalize_confirmation_snapshot(payload)
    confirmation_reply = normalize_confirmation_reply(payload, requester_identity)
    correction_text = normalize_text(payload.get("brief_feedback_text") or payload.get("correction_request_text"))
    can_prepare_brief = bool(existing_brief) or bool(topic_progress.get("ready_for_brief"))

    if not can_prepare_brief:
        return {
            "conversation_turns": conversation_turns,
        }

    candidate_brief = build_requirement_brief_candidate(
        payload,
        requirement_topics,
        clarification_items,
        existing_brief,
        requester_identity,
        now,
    )
    changed_sections = brief_changed_sections(existing_brief, candidate_brief)

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
            "confirmation_snapshot": {},
            "conversation_turns": conversation_turns,
            "brief_markdown": render_requirement_brief_markdown(payload, candidate_brief, discovery_session, open_questions),
            "brief_template_path": str(BRIEF_TEMPLATE_PATH),
            "open_questions": open_questions,
        }

    if correction_text:
        conversation_turns = append_turn_if_missing(
            conversation_turns,
            actor="user",
            turn_type="revision_request",
            raw_text=correction_text,
            extracted_topics=["brief_confirmation"],
            now=now,
        )

    if changed_sections:
        candidate_brief["version"] = next_brief_version(normalize_text(existing_brief.get("version")))
        candidate_brief["status"] = "awaiting_confirmation"
        candidate_brief["created_at"] = now
        candidate_brief["updated_at"] = now
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
            "status": "awaiting_confirmation",
            "next_action": "request_explicit_confirmation",
            "next_topic": "brief_confirmation",
            "next_question": next_question,
            "requirement_brief": candidate_brief,
            "brief_revisions": revisions,
            "confirmation_snapshot": {},
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
            "confirmation_snapshot": build_confirmation_snapshot(current_brief, existing_snapshot, confirmation_reply, now),
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
        "confirmation_snapshot": existing_snapshot if brief_status == "confirmed" else {},
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
    clarification_items = normalize_clarification_items(payload)
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
        "conversation_turns": conversation_turns,
        "open_questions": brief_state.get("open_questions") or build_open_questions(clarification_items, next_question),
        "normalized_answers": normalized_answers,
    }
    if isinstance(requirement_brief, dict) and requirement_brief:
        response["requirement_brief"] = requirement_brief
    brief_revisions = brief_state.get("brief_revisions")
    if isinstance(brief_revisions, list) and brief_revisions:
        response["brief_revisions"] = brief_revisions
    confirmation_snapshot = brief_state.get("confirmation_snapshot")
    if isinstance(confirmation_snapshot, dict) and confirmation_snapshot:
        response["confirmation_snapshot"] = confirmation_snapshot
    brief_markdown = normalize_text(brief_state.get("brief_markdown"))
    if brief_markdown:
        response["brief_markdown"] = brief_markdown
        response["brief_template_path"] = brief_state.get("brief_template_path")

    write_json(response, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
