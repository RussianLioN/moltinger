#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from typing import Any

from agent_factory_common import (
    build_discovery_topic,
    build_discovery_topic_progress,
    canonical_discovery_topic_name,
    discovery_next_topic,
    discovery_summary,
    discovery_topic_names,
    discovery_topic_question,
    discovery_topic_sort_rank,
    load_json,
    normalize_text,
    slugify,
    utc_now,
    write_json,
)


AGENT_SUMMARY = (
    "Я выступаю как AI бизнес-аналитик: сначала помогу собрать требования простым бизнес-языком, "
    "потом из подтвержденного контекста можно будет перейти к requirements brief и downstream concept pack."
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

    normalized_answers = {
        topic["topic_name"]: topic["summary"]
        for topic in requirement_topics
        if normalize_text(topic.get("summary"))
    }

    response = {
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
        "open_questions": build_open_questions(clarification_items, next_question),
        "normalized_answers": normalized_answers,
    }

    write_json(response, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
