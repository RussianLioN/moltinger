#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path
from typing import Any

from agent_factory_common import (
    build_telegram_reply_payload,
    build_telegram_reply_payloads,
    build_telegram_resume_projection,
    build_telegram_status_snapshot,
    canonical_discovery_topic_name,
    discovery_topic_question,
    load_json,
    normalize_download_artifacts,
    normalize_dict_list,
    normalize_list,
    normalize_text,
    sanitize_transport_text,
    slugify,
    telegram_session_runtime_status,
    utc_now,
    write_json,
)


SCRIPT_ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_ROOT.parent
DISCOVERY_SCRIPT = SCRIPT_ROOT / "agent-factory-discovery.py"
INTAKE_SCRIPT = SCRIPT_ROOT / "agent-factory-intake.py"
ARTIFACT_SCRIPT = SCRIPT_ROOT / "agent-factory-artifacts.py"
DELIVERY_SCRIPT = SCRIPT_ROOT / "telegram-bot-send-document.sh"

DEFAULT_STATE_ROOT = PROJECT_ROOT / "data/agent-factory/telegram"
STATE_DIRS = ("sessions", "deliveries", "history")
DISCOVERY_RUNTIME_TIMEOUT_SEC = 120
INTAKE_RUNTIME_TIMEOUT_SEC = 120
ARTIFACT_RUNTIME_TIMEOUT_SEC = 180
DELIVERY_RETRY_LIMIT = 1
DELIVERY_MODE = normalize_text(os.environ.get("MOLTIS_TELEGRAM_DELIVERY_MODE")).lower() or "dry_run"

TOPIC_CAPTURE_FIELD_MAP = {
    "problem": "target_business_problem",
    "target_users": "target_users",
    "current_workflow": "current_workflow_summary",
    "desired_outcome": "desired_outcome",
    "user_story": "user_story",
    "input_examples": "input_examples",
    "expected_outputs": "expected_outputs",
    "constraints": "constraints_or_exclusions",
    "success_metrics": "measurable_success_expectation",
}
LIST_CAPTURE_FIELDS = {"target_users", "input_examples", "expected_outputs", "constraints_or_exclusions", "measurable_success_expectation"}
BRIEF_LIST_FIELDS = {"target_users", "input_examples", "expected_outputs", "constraints", "success_metrics", "open_risks"}
BRIEF_SECTION_HINTS: tuple[tuple[str, str], ...] = (
    ("проблем", "problem_statement"),
    ("пользоват", "target_users"),
    ("выгодоприобрет", "target_users"),
    ("процесс", "current_process"),
    ("как сейчас", "current_process"),
    ("результат", "expected_outputs"),
    ("выход", "expected_outputs"),
    ("формат", "expected_outputs"),
    ("огранич", "constraints"),
    ("запрет", "constraints"),
    ("метрик", "success_metrics"),
    ("kpi", "success_metrics"),
    ("риски", "open_risks"),
)

START_PROJECT_MARKERS = ("/start", "/new", "/new_project", "новый проект")
STATUS_MARKERS = ("/status", "статус", "проверь статус")
PROJECT_LIST_MARKERS = ("/projects", "список проектов", "мои проекты")
HELP_MARKERS = ("/help", "помощь", "что умеешь")
CONFIRM_MARKERS = ("подтверждаю", "подтвердить", "confirm brief", "approve brief")
REOPEN_MARKERS = ("переоткры", "reopen", "исправ", "правк")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Telegram adapter for the factory discovery runtime.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    handle = subparsers.add_parser("handle-update", help="Normalize one Telegram update and route it to discovery runtime.")
    handle.add_argument("--source", required=True, help="Path to Telegram update JSON payload")
    handle.add_argument("--output", help="Optional output JSON path (stdout when omitted)")
    handle.add_argument(
        "--state-root",
        default=normalize_text(os.environ.get("MOLTIS_FACTORY_TELEGRAM_OUTPUT_ROOT")) or str(DEFAULT_STATE_ROOT),
        help="Adapter state root for sessions/history persistence",
    )
    handle.add_argument(
        "--transport-mode",
        default="synthetic_fixture",
        choices=("webhook", "synthetic_fixture", "live_probe"),
        help="Transport mode label for normalized envelope",
    )
    return parser.parse_args()


def ensure_state_dirs(state_root: Path) -> None:
    for name in STATE_DIRS:
        (state_root / name).mkdir(parents=True, exist_ok=True)


def session_id_from_envelope(envelope: dict[str, Any]) -> str:
    chat_id = normalize_text(envelope.get("chat_id"))
    from_user_id = normalize_text(envelope.get("from_user_id"))
    return f"tg-session-{slugify(f'{chat_id}-{from_user_id}', 'tg-session')}"


def session_path(state_root: Path, telegram_adapter_session_id: str) -> Path:
    return state_root / "sessions" / f"{telegram_adapter_session_id}.json"


def history_path(state_root: Path, telegram_adapter_session_id: str) -> Path:
    return state_root / "history" / f"{telegram_adapter_session_id}.jsonl"


def load_session(state_root: Path, telegram_adapter_session_id: str) -> dict[str, Any]:
    path = session_path(state_root, telegram_adapter_session_id)
    if not path.is_file():
        return {}
    payload = load_json(path)
    return payload if isinstance(payload, dict) else {}


def append_history_event(state_root: Path, telegram_adapter_session_id: str, event: dict[str, Any]) -> None:
    path = history_path(state_root, telegram_adapter_session_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(event, ensure_ascii=False) + "\n")


def normalize_telegram_update_envelope(payload: dict[str, Any], *, transport_mode: str, now: str) -> dict[str, Any]:
    if isinstance(payload.get("telegram_update_envelope"), dict):
        envelope = deepcopy(payload["telegram_update_envelope"])
    else:
        envelope = {}

    update_id = normalize_text(payload.get("update_id")) or normalize_text(envelope.get("telegram_update_id"))
    callback = payload.get("callback_query", {}) if isinstance(payload.get("callback_query"), dict) else {}
    callback_message = callback.get("message", {}) if isinstance(callback.get("message"), dict) else {}
    message = payload.get("message", {}) if isinstance(payload.get("message"), dict) else {}
    if not message and isinstance(payload.get("edited_message"), dict):
        message = payload["edited_message"]

    message_chat = message.get("chat", {}) if isinstance(message.get("chat"), dict) else {}
    callback_chat = callback_message.get("chat", {}) if isinstance(callback_message.get("chat"), dict) else {}
    chat = message_chat or callback_chat

    message_from = message.get("from", {}) if isinstance(message.get("from"), dict) else {}
    callback_from = callback.get("from", {}) if isinstance(callback.get("from"), dict) else {}
    from_user = message_from or callback_from

    message_text = normalize_text(message.get("text")) or normalize_text(message.get("caption")) or normalize_text(payload.get("message_text"))
    callback_data = normalize_text(callback.get("data")) or normalize_text(payload.get("callback_data"))
    if not message_text and callback_data:
        message_text = callback_data

    command_text = ""
    if message_text.startswith("/"):
        command_text = message_text.split(maxsplit=1)[0]

    return {
        "telegram_update_id": update_id,
        "bot_id": normalize_text(payload.get("bot_id")) or normalize_text(envelope.get("bot_id")),
        "chat_id": normalize_text(chat.get("id")) or normalize_text(envelope.get("chat_id")),
        "chat_type": normalize_text(chat.get("type")) or normalize_text(envelope.get("chat_type")) or "private",
        "message_id": normalize_text(message.get("message_id")) or normalize_text(callback_message.get("message_id")) or normalize_text(envelope.get("message_id")),
        "from_user_id": normalize_text(from_user.get("id")) or normalize_text(envelope.get("from_user_id")),
        "from_display_name": (
            normalize_text(from_user.get("first_name"))
            or normalize_text(from_user.get("username"))
            or normalize_text(envelope.get("from_display_name"))
        ),
        "language_code": normalize_text(from_user.get("language_code")) or normalize_text(envelope.get("language_code")) or "ru",
        "message_text": message_text,
        "command_text": command_text or normalize_text(envelope.get("command_text")),
        "callback_data": callback_data or normalize_text(envelope.get("callback_data")),
        "received_at": normalize_text(envelope.get("received_at")) or now,
        "transport_mode": normalize_text(envelope.get("transport_mode")) or transport_mode,
    }


def infer_intent(envelope: dict[str, Any], session_payload: dict[str, Any]) -> tuple[str, str]:
    command = normalize_text(envelope.get("command_text")).lower()
    text = normalize_text(envelope.get("message_text")).lower()
    active_status = normalize_text(session_payload.get("telegram_adapter_session", {}).get("status")).lower()
    has_active_pointer = bool(normalize_text(session_payload.get("active_project_pointer", {}).get("project_key")))

    if command in {"/status"} or any(marker in text for marker in STATUS_MARKERS):
        return ("request_status", "status_only")
    if command in {"/projects"} or any(marker in text for marker in PROJECT_LIST_MARKERS):
        return ("list_projects", "project_list")
    if command in {"/help"} or any(marker in text for marker in HELP_MARKERS):
        return ("request_help", "status_only")
    if command in {"/start", "/new", "/new_project"} or any(marker in text for marker in START_PROJECT_MARKERS):
        return ("start_project", "new_project")
    if text.startswith("/project ") or text.startswith("проект ") or text.startswith("выбрать проект "):
        return ("select_project", "project_select")
    if any(marker in text for marker in CONFIRM_MARKERS):
        return ("confirm_brief", "review_brief")
    if any(marker in text for marker in REOPEN_MARKERS):
        return ("reopen_brief", "reopen_brief")
    if has_active_pointer and active_status in {"awaiting_confirmation", "reopened"}:
        return ("reopen_brief", "reopen_brief")
    if has_active_pointer and active_status in {"awaiting_user_reply", "awaiting_clarification", "handoff_running"}:
        return ("answer_discovery_question", "continue_active")
    if has_active_pointer:
        return ("continue_project", "continue_active")
    return ("start_project", "new_project")


def build_project_key(envelope: dict[str, Any], session_payload: dict[str, Any], *, start_new: bool) -> str:
    if not start_new:
        existing = normalize_text(session_payload.get("active_project_pointer", {}).get("project_key"))
        if existing:
            return existing
    seed = normalize_text(envelope.get("message_text")) or normalize_text(envelope.get("callback_data"))
    if seed:
        return slugify(seed, "telegram-project")
    chat_id = normalize_text(envelope.get("chat_id")) or "chat"
    message_id = normalize_text(envelope.get("message_id")) or utc_now()
    return slugify(f"{chat_id}-{message_id}", "telegram-project")


def append_user_turn(discovery_request: dict[str, Any], envelope: dict[str, Any], *, now: str, next_topic: str) -> None:
    message_text = normalize_text(envelope.get("message_text"))
    if not message_text:
        return
    turns = normalize_dict_list(discovery_request.get("conversation_turns"))
    turn_id = f"turn-user-{len(turns) + 1}"
    turn = {
        "turn_id": turn_id,
        "actor": "user",
        "turn_type": "answer",
        "raw_text": message_text,
        "extracted_topics": [next_topic] if next_topic else [],
        "timestamp": now,
    }
    turns.append(turn)
    discovery_request["conversation_turns"] = turns


def apply_captured_answer(discovery_request: dict[str, Any], envelope: dict[str, Any], next_topic: str) -> None:
    canonical_topic = canonical_discovery_topic_name(next_topic)
    if not canonical_topic:
        return
    field_name = TOPIC_CAPTURE_FIELD_MAP.get(canonical_topic)
    if not field_name:
        return
    message_text = normalize_text(envelope.get("message_text"))
    if not message_text:
        return
    captured_answers = discovery_request.get("captured_answers", {})
    captured_answers = dict(captured_answers) if isinstance(captured_answers, dict) else {}
    if field_name in LIST_CAPTURE_FIELDS:
        existing_values = normalize_list(captured_answers.get(field_name))
        existing_values.append(message_text)
        captured_answers[field_name] = existing_values
    else:
        captured_answers[field_name] = message_text
    discovery_request["captured_answers"] = captured_answers


def infer_brief_feedback_target(message_text: str) -> str:
    text = normalize_text(message_text).lower()
    if not text:
        return "open_risks"
    for marker, target_field in BRIEF_SECTION_HINTS:
        if marker in text:
            return target_field
    return "open_risks"


def normalize_feedback_text(message_text: str) -> str:
    text = normalize_text(message_text)
    if not text:
        return ""
    prefix_match = text.split(":", 1)
    if len(prefix_match) == 2 and len(prefix_match[0].split()) <= 4:
        candidate = normalize_text(prefix_match[1])
        if candidate:
            return candidate
    return text


def build_brief_section_updates(message_text: str) -> dict[str, Any]:
    clean_text = normalize_feedback_text(message_text)
    if not clean_text:
        return {}
    target_field = infer_brief_feedback_target(clean_text)
    if target_field in BRIEF_LIST_FIELDS:
        return {target_field: [clean_text]}
    return {target_field: clean_text}


def build_confirmation_reply(envelope: dict[str, Any]) -> dict[str, Any]:
    display_name = normalize_text(envelope.get("from_display_name")) or normalize_text(envelope.get("from_user_id")) or "telegram-user"
    return {
        "confirmed": True,
        "confirmed_by": display_name,
        "confirmation_text": normalize_text(envelope.get("message_text")) or "Подтверждаю brief.",
    }


def build_discovery_request(
    envelope: dict[str, Any],
    session_payload: dict[str, Any],
    *,
    now: str,
    start_new: bool,
    intent_type: str,
) -> dict[str, Any]:
    previous_state = session_payload.get("discovery_state", {}) if isinstance(session_payload.get("discovery_state"), dict) else {}
    discovery_request = {} if start_new else deepcopy(previous_state)

    project_key = build_project_key(envelope, session_payload, start_new=start_new)
    discovery_request["project_key"] = project_key
    discovery_request["request_channel"] = "telegram"
    discovery_request["working_language"] = normalize_text(envelope.get("language_code")) or "ru"
    discovery_request["requester_identity"] = {
        "telegram_user_id": normalize_text(envelope.get("from_user_id")),
        "display_name": normalize_text(envelope.get("from_display_name")) or "Telegram user",
        "telegram_chat_id": normalize_text(envelope.get("chat_id")),
    }

    if start_new:
        discovery_request.pop("conversation_turns", None)
        discovery_request.pop("captured_answers", None)
        discovery_request.pop("discovery_answers", None)
        discovery_request.pop("clarification_items", None)
        discovery_request.pop("requirement_topics", None)
        discovery_request["raw_idea"] = normalize_text(envelope.get("message_text")) or "Новый проект из Telegram"
        return discovery_request

    if not normalize_text(discovery_request.get("raw_idea")):
        discovery_request["raw_idea"] = normalize_text(envelope.get("message_text")) or "Telegram follow-up"

    next_topic = canonical_discovery_topic_name(discovery_request.get("next_topic"))
    message_text = normalize_text(envelope.get("message_text"))
    if intent_type == "confirm_brief":
        discovery_request["confirmation_reply"] = build_confirmation_reply(envelope)
        discovery_request.pop("brief_feedback_text", None)
        discovery_request.pop("brief_section_updates", None)
    elif intent_type == "reopen_brief":
        discovery_request["brief_feedback_text"] = message_text or "Нужно уточнить brief."
        section_updates = build_brief_section_updates(message_text)
        if section_updates:
            discovery_request["brief_section_updates"] = section_updates
        discovery_request.pop("confirmation_reply", None)
    else:
        apply_captured_answer(discovery_request, envelope, next_topic)
        append_user_turn(discovery_request, envelope, now=now, next_topic=next_topic)
    return discovery_request


def run_discovery_runtime(discovery_request: dict[str, Any]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = Path(tmpdir) / "telegram-discovery-request.json"
        output_path = Path(tmpdir) / "telegram-discovery-response.json"
        source_path.write_text(json.dumps(discovery_request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        try:
            proc = subprocess.run(
                [sys.executable, str(DISCOVERY_SCRIPT), "run", "--source", str(source_path), "--output", str(output_path)],
                capture_output=True,
                text=True,
                check=False,
                cwd=PROJECT_ROOT,
                timeout=DISCOVERY_RUNTIME_TIMEOUT_SEC,
            )
        except subprocess.TimeoutExpired as exc:
            detail = normalize_text(exc.stderr) or normalize_text(exc.stdout)
            raise RuntimeError(f"discovery runtime timed out after {DISCOVERY_RUNTIME_TIMEOUT_SEC}s: {detail}") from exc

        if proc.returncode != 0:
            detail = normalize_text(proc.stderr) or normalize_text(proc.stdout) or "discovery runtime failed"
            raise RuntimeError(detail)
        response = load_json(output_path)
        if not isinstance(response, dict):
            raise RuntimeError("discovery runtime returned non-object response")
        return response


def run_runtime_subprocess(command: list[str], *, timeout_sec: int, label: str) -> None:
    try:
        proc = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            cwd=PROJECT_ROOT,
            timeout=timeout_sec,
        )
    except subprocess.TimeoutExpired as exc:
        detail = normalize_text(exc.stderr) or normalize_text(exc.stdout)
        raise RuntimeError(f"{label} runtime timed out after {timeout_sec}s: {detail}") from exc
    if proc.returncode != 0:
        detail = normalize_text(proc.stderr) or normalize_text(proc.stdout) or f"{label} runtime failed"
        raise RuntimeError(detail)


def run_intake_runtime(source_payload: dict[str, Any]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = Path(tmpdir) / "telegram-intake-request.json"
        output_path = Path(tmpdir) / "telegram-intake-response.json"
        source_path.write_text(json.dumps(source_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        run_runtime_subprocess(
            [sys.executable, str(INTAKE_SCRIPT), "--source", str(source_path), "--output", str(output_path)],
            timeout_sec=INTAKE_RUNTIME_TIMEOUT_SEC,
            label="intake",
        )
        response = load_json(output_path)
        if not isinstance(response, dict):
            raise RuntimeError("intake runtime returned non-object response")
        return response


def run_artifact_runtime(source_payload: dict[str, Any], *, output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = Path(tmpdir) / "telegram-artifact-request.json"
        output_path = Path(tmpdir) / "telegram-artifact-response.json"
        source_path.write_text(json.dumps(source_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        run_runtime_subprocess(
            [
                sys.executable,
                str(ARTIFACT_SCRIPT),
                "generate",
                "--input",
                str(source_path),
                "--output-dir",
                str(output_dir),
                "--output",
                str(output_path),
            ],
            timeout_sec=ARTIFACT_RUNTIME_TIMEOUT_SEC,
            label="artifact",
        )
        response = load_json(output_path)
        if not isinstance(response, dict):
            raise RuntimeError("artifact runtime returned non-object response")
        return response


def copy_discovery_state(runtime_state: dict[str, Any]) -> dict[str, Any]:
    return {key: deepcopy(value) for key, value in runtime_state.items()}


def sanitize_discovery_runtime_state(runtime_state: dict[str, Any]) -> dict[str, Any]:
    sanitized = copy_discovery_state(runtime_state)
    for transient_key in (
        "brief_feedback_text",
        "correction_request_text",
        "brief_section_updates",
        "confirmation_reply",
    ):
        sanitized.pop(transient_key, None)
    return sanitized


def prepare_delivery_runtime_state(runtime_state: dict[str, Any], envelope: dict[str, Any]) -> dict[str, Any]:
    delivery_state = copy_discovery_state(runtime_state)
    delivery_state["request_channel"] = normalize_text(delivery_state.get("request_channel")) or "telegram"
    delivery_state["working_language"] = normalize_text(delivery_state.get("working_language")) or normalize_text(envelope.get("language_code")) or "ru"
    requester_identity = (
        delivery_state.get("requester_identity", {})
        if isinstance(delivery_state.get("requester_identity"), dict)
        else {}
    )
    if not requester_identity:
        requester_identity = {
            "telegram_user_id": normalize_text(envelope.get("from_user_id")),
            "display_name": normalize_text(envelope.get("from_display_name")) or "Telegram user",
            "telegram_chat_id": normalize_text(envelope.get("chat_id")),
        }
    delivery_state["requester_identity"] = requester_identity
    return delivery_state


def ensure_ready_handoff(runtime_state: dict[str, Any], envelope: dict[str, Any]) -> dict[str, Any]:
    handoff = runtime_state.get("factory_handoff_record", {}) if isinstance(runtime_state.get("factory_handoff_record"), dict) else {}
    if normalize_text(handoff.get("handoff_status")) == "ready":
        return runtime_state

    status = normalize_text(runtime_state.get("status"))
    next_action = normalize_text(runtime_state.get("next_action"))
    if status != "confirmed" and next_action not in {"start_concept_pack_handoff", "run_factory_intake"}:
        return runtime_state

    handoff_request = prepare_delivery_runtime_state(runtime_state, envelope)
    replayed_state = run_discovery_runtime(handoff_request)
    return sanitize_discovery_runtime_state(replayed_state)


def delivery_root(state_root: Path, telegram_adapter_session_id: str) -> Path:
    return state_root / "deliveries" / (telegram_adapter_session_id or "anonymous-session")


def delivery_index_path(state_root: Path, telegram_adapter_session_id: str) -> Path:
    return delivery_root(state_root, telegram_adapter_session_id) / "delivery-index.json"


def write_delivery_index(
    state_root: Path,
    telegram_adapter_session_id: str,
    manifest_items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    root = delivery_root(state_root, telegram_adapter_session_id)
    root.mkdir(parents=True, exist_ok=True)
    private_items: list[dict[str, Any]] = []
    public_items: list[dict[str, Any]] = []
    for item in normalize_download_artifacts(manifest_items):
        artifact_kind = normalize_text(item.get("artifact_kind"))
        download_name = normalize_text(item.get("download_name"))
        project_key = normalize_text(item.get("project_key"))
        brief_version = normalize_text(item.get("brief_version"))
        download_ref = normalize_text(item.get("download_ref"))
        token_seed = f"{telegram_adapter_session_id}:{artifact_kind}:{download_name}:{brief_version}"
        download_token = slugify(token_seed, "delivery")
        private_items.append(
            {
                "download_token": download_token,
                "artifact_kind": artifact_kind,
                "download_name": download_name,
                "download_ref": download_ref,
                "project_key": project_key,
                "brief_version": brief_version,
            }
        )
        public_items.append(
            {
                "artifact_kind": artifact_kind,
                "download_name": download_name,
                "download_token": download_token,
                "download_status": "ready" if download_ref else "pending",
                "project_key": project_key,
                "brief_version": brief_version,
            }
        )

    write_json(
        {
            "telegram_adapter_session_id": telegram_adapter_session_id,
            "generated_at": utc_now(),
            "items": private_items,
        },
        delivery_index_path(state_root, telegram_adapter_session_id),
    )
    return public_items


def load_delivery_items(state_root: Path, telegram_adapter_session_id: str) -> list[dict[str, Any]]:
    index_path = delivery_index_path(state_root, telegram_adapter_session_id)
    if not index_path.is_file():
        return []
    payload = load_json(index_path)
    if not isinstance(payload, dict):
        return []
    items = payload.get("items")
    if not isinstance(items, list):
        return []
    return [dict(item) for item in items if isinstance(item, dict)]


def build_telegram_delivery_payloads(
    *,
    telegram_adapter_session_id: str,
    runtime_state: dict[str, Any],
    delivery_items: list[dict[str, Any]],
    now: str,
) -> list[dict[str, Any]]:
    discovery_session = runtime_state.get("discovery_session", {}) if isinstance(runtime_state.get("discovery_session"), dict) else {}
    requirement_brief = runtime_state.get("requirement_brief", {}) if isinstance(runtime_state.get("requirement_brief"), dict) else {}
    factory_handoff = runtime_state.get("factory_handoff_record", {}) if isinstance(runtime_state.get("factory_handoff_record"), dict) else {}
    reply_payloads: list[dict[str, Any]] = [
        build_telegram_reply_payload(
            "status_update",
            rendered_text="Concept pack готов. Подготовил документы для отправки в Telegram.",
            telegram_adapter_session_id=telegram_adapter_session_id,
            linked_discovery_session_id=discovery_session.get("discovery_session_id"),
            linked_brief_id=requirement_brief.get("brief_id"),
            linked_handoff_id=factory_handoff.get("factory_handoff_id"),
            now=now,
        )
    ]
    if not delivery_items:
        return reply_payloads

    lines: list[str] = []
    for item in delivery_items:
        if normalize_text(item.get("download_status")) != "ready":
            continue
        artifact_kind = normalize_text(item.get("artifact_kind")) or "artifact"
        download_name = normalize_text(item.get("download_name")) or f"{artifact_kind}.md"
        lines.append(f"- {artifact_kind}: {download_name}")
    if lines:
        payload = build_telegram_reply_payload(
            "artifact_delivery",
            rendered_text="Доступные артефакты:\n" + "\n".join(lines),
            telegram_adapter_session_id=telegram_adapter_session_id,
            linked_discovery_session_id=discovery_session.get("discovery_session_id"),
            linked_brief_id=requirement_brief.get("brief_id"),
            linked_handoff_id=factory_handoff.get("factory_handoff_id"),
            now=now,
        )
        reply_payloads.append(payload)
    return reply_payloads


def run_delivery_script(
    *,
    chat_id: str,
    file_path: str,
    caption: str,
) -> tuple[bool, str]:
    if not DELIVERY_SCRIPT.is_file():
        return (False, "delivery_helper_missing")

    command = [str(DELIVERY_SCRIPT), "--chat-id", chat_id, "--file", file_path]
    if caption:
        command.extend(["--caption", caption])
    if DELIVERY_MODE != "live":
        command.append("--dry-run")
    if DELIVERY_MODE == "live" and DELIVERY_RETRY_LIMIT > 0:
        command.extend(["--retry", str(DELIVERY_RETRY_LIMIT)])
    proc = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
        cwd=PROJECT_ROOT,
    )
    output = normalize_text(proc.stdout) or normalize_text(proc.stderr)
    if proc.returncode != 0:
        return (False, output or "delivery_helper_failed")
    return (True, output or "ok")


def attempt_telegram_document_delivery(
    *,
    envelope: dict[str, Any],
    delivery_items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    chat_id = normalize_text(envelope.get("chat_id"))
    if not chat_id:
        return []
    private_items = [item for item in delivery_items if normalize_text(item.get("download_status")) == "ready"]
    if not private_items:
        return []

    delivery_results: list[dict[str, Any]] = []
    for item in private_items:
        file_path = normalize_text(item.get("download_ref"))
        if not file_path or not Path(file_path).is_file():
            delivery_results.append(
                {
                    "artifact_kind": normalize_text(item.get("artifact_kind")),
                    "download_name": normalize_text(item.get("download_name")),
                    "delivery_status": "missing_file",
                }
            )
            continue
        success, detail = run_delivery_script(
            chat_id=chat_id,
            file_path=file_path,
            caption=normalize_text(item.get("download_name")),
        )
        delivery_results.append(
            {
                "artifact_kind": normalize_text(item.get("artifact_kind")),
                "download_name": normalize_text(item.get("download_name")),
                "delivery_status": "sent" if success else "failed",
                "delivery_detail": sanitize_transport_text(detail),
            }
        )
    return delivery_results


def run_concept_pack_delivery(
    *,
    state_root: Path,
    telegram_adapter_session_id: str,
    runtime_state: dict[str, Any],
    envelope: dict[str, Any],
    now: str,
) -> tuple[dict[str, Any], list[dict[str, Any]], str, list[dict[str, Any]]]:
    ready_state = ensure_ready_handoff(runtime_state, envelope)
    handoff = ready_state.get("factory_handoff_record", {}) if isinstance(ready_state.get("factory_handoff_record"), dict) else {}
    if normalize_text(handoff.get("handoff_status")) != "ready":
        return ready_state, [], "", []

    intake_response = run_intake_runtime(ready_state)
    if normalize_text(intake_response.get("status")) != "ready_for_pack":
        return (
            ready_state,
            [],
            normalize_text(intake_response.get("block_reason")) or "Factory intake did not reach ready_for_pack.",
            [],
        )

    artifact_output_dir = delivery_root(state_root, telegram_adapter_session_id)
    artifact_manifest = run_artifact_runtime(intake_response, output_dir=artifact_output_dir)
    if normalize_text(artifact_manifest.get("status")) != "generated":
        return ready_state, [], "Concept pack generation did not complete successfully.", []

    manifest_items = normalize_download_artifacts(artifact_manifest)
    delivery_index_items = write_delivery_index(state_root, telegram_adapter_session_id, manifest_items)
    private_items = load_delivery_items(state_root, telegram_adapter_session_id)
    items_by_token = {
        normalize_text(item.get("download_token")): item
        for item in private_items
        if normalize_text(item.get("download_token"))
    }
    delivery_items: list[dict[str, Any]] = []
    for item in delivery_index_items:
        token = normalize_text(item.get("download_token"))
        merged = dict(item)
        private = items_by_token.get(token, {})
        if private:
            merged["download_ref"] = normalize_text(private.get("download_ref"))
        delivery_items.append(merged)

    delivery_results = attempt_telegram_document_delivery(
        envelope=envelope,
        delivery_items=delivery_items,
    )
    completed_state = copy_discovery_state(ready_state)
    completed_state["status"] = "completed"
    completed_state["next_action"] = "publish_downloads"
    completed_state["next_topic"] = "delivery"
    completed_state["next_question"] = ""
    if isinstance(completed_state.get("factory_handoff_record"), dict):
        completed_state["factory_handoff_record"]["handoff_status"] = "consumed"
        completed_state["factory_handoff_record"]["consumed_at"] = now
    return completed_state, delivery_items, "", delivery_results


def build_adapter_session(
    *,
    previous_session: dict[str, Any],
    envelope: dict[str, Any],
    runtime_response: dict[str, Any],
    telegram_adapter_session_id: str,
    now: str,
) -> dict[str, Any]:
    discovery_session = runtime_response.get("discovery_session", {}) if isinstance(runtime_response.get("discovery_session"), dict) else {}
    requirement_brief = runtime_response.get("requirement_brief", {}) if isinstance(runtime_response.get("requirement_brief"), dict) else {}
    existing = previous_session if isinstance(previous_session, dict) else {}
    status = telegram_session_runtime_status(
        runtime_response.get("status"),
        next_action=runtime_response.get("next_action"),
    )
    return {
        "telegram_adapter_session_id": telegram_adapter_session_id,
        "chat_id": normalize_text(envelope.get("chat_id")),
        "from_user_id": normalize_text(envelope.get("from_user_id")),
        "status": status,
        "active_project_key": normalize_text(discovery_session.get("project_key")) or normalize_text(existing.get("active_project_key")),
        "active_discovery_session_id": normalize_text(discovery_session.get("discovery_session_id")) or normalize_text(existing.get("active_discovery_session_id")),
        "active_brief_id": normalize_text(requirement_brief.get("brief_id")) or normalize_text(existing.get("active_brief_id")),
        "last_seen_update_id": normalize_text(envelope.get("telegram_update_id")),
        "last_seen_message_id": normalize_text(envelope.get("message_id")),
        "last_user_message_at": normalize_text(envelope.get("received_at")) or now,
        "last_agent_message_at": now,
        "created_at": normalize_text(existing.get("created_at")) or now,
        "updated_at": now,
    }


def build_active_pointer(
    *,
    previous_pointer: dict[str, Any],
    telegram_adapter_session_id: str,
    runtime_response: dict[str, Any],
    selection_mode: str,
    now: str,
) -> dict[str, Any]:
    discovery_session = runtime_response.get("discovery_session", {}) if isinstance(runtime_response.get("discovery_session"), dict) else {}
    requirement_brief = runtime_response.get("requirement_brief", {}) if isinstance(runtime_response.get("requirement_brief"), dict) else {}
    existing = previous_pointer if isinstance(previous_pointer, dict) else {}
    project_key = normalize_text(discovery_session.get("project_key")) or normalize_text(existing.get("project_key"))
    return {
        "pointer_id": normalize_text(existing.get("pointer_id")) or f"tg-pointer-{slugify(f'{telegram_adapter_session_id}-{project_key}', 'tg-pointer')}",
        "telegram_adapter_session_id": telegram_adapter_session_id,
        "project_key": project_key,
        "selection_mode": selection_mode,
        "linked_discovery_session_id": normalize_text(discovery_session.get("discovery_session_id")) or normalize_text(existing.get("linked_discovery_session_id")),
        "linked_brief_id": normalize_text(requirement_brief.get("brief_id")) or normalize_text(existing.get("linked_brief_id")),
        "linked_brief_version": normalize_text(requirement_brief.get("version")) or normalize_text(existing.get("linked_brief_version")),
        "pointer_status": "active",
        "updated_at": now,
    }


def parse_selected_project_value(envelope: dict[str, Any]) -> str:
    text = normalize_text(envelope.get("message_text"))
    lower = text.lower()
    for prefix in ("/project ", "проект ", "выбрать проект "):
        if lower.startswith(prefix):
            return normalize_text(text[len(prefix):])
    return ""


def normalize_project_registry(session_payload: dict[str, Any]) -> dict[str, Any]:
    registry = session_payload.get("project_registry", {}) if isinstance(session_payload.get("project_registry"), dict) else {}
    projects = normalize_dict_list(registry.get("projects"))
    if not projects:
        fallback_runtime = session_payload.get("last_runtime_response", {}) if isinstance(session_payload.get("last_runtime_response"), dict) else {}
        fallback_pointer = session_payload.get("active_project_pointer", {}) if isinstance(session_payload.get("active_project_pointer"), dict) else {}
        fallback_key = normalize_text(fallback_pointer.get("project_key")) or normalize_text(fallback_runtime.get("discovery_session", {}).get("project_key"))
        if fallback_key:
            projects = [
                {
                    "project_key": fallback_key,
                    "project_title": fallback_key,
                    "pointer": dict(fallback_pointer),
                    "discovery_state": session_payload.get("discovery_state", {}) if isinstance(session_payload.get("discovery_state"), dict) else {},
                    "last_runtime_response": dict(fallback_runtime),
                    "status_snapshot": session_payload.get("status_snapshot", {}) if isinstance(session_payload.get("status_snapshot"), dict) else {},
                    "resume_context": fallback_runtime.get("resume_context", {}) if isinstance(fallback_runtime.get("resume_context"), dict) else {},
                }
            ]
    return {
        "active_project_key": normalize_text(registry.get("active_project_key")) or normalize_text(session_payload.get("active_project_pointer", {}).get("project_key")),
        "projects": projects,
    }


def project_record_for_key(project_registry: dict[str, Any], project_key: str) -> dict[str, Any]:
    key = normalize_text(project_key)
    if not key:
        return {}
    for item in normalize_dict_list(project_registry.get("projects")):
        if normalize_text(item.get("project_key")) == key:
            return dict(item)
    return {}


def upsert_project_record(project_registry: dict[str, Any], record: dict[str, Any], *, active_project_key: str) -> dict[str, Any]:
    key = normalize_text(record.get("project_key"))
    projects = normalize_dict_list(project_registry.get("projects"))
    if not key:
        return {
            "active_project_key": normalize_text(active_project_key) or normalize_text(project_registry.get("active_project_key")),
            "projects": projects,
        }

    merged: list[dict[str, Any]] = []
    replaced = False
    for existing in projects:
        if normalize_text(existing.get("project_key")) == key:
            merged.append(dict(record))
            replaced = True
        else:
            merged.append(dict(existing))
    if not replaced:
        merged.append(dict(record))
    return {
        "active_project_key": key if key else normalize_text(active_project_key),
        "projects": merged,
    }


def build_project_record(
    *,
    pointer_obj: dict[str, Any],
    runtime_response: dict[str, Any],
    discovery_state: dict[str, Any],
    status_snapshot: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    discovery_session = runtime_response.get("discovery_session", {}) if isinstance(runtime_response.get("discovery_session"), dict) else {}
    requirement_brief = runtime_response.get("requirement_brief", {}) if isinstance(runtime_response.get("requirement_brief"), dict) else {}
    project_key = normalize_text(pointer_obj.get("project_key")) or normalize_text(discovery_session.get("project_key"))
    project_title = normalize_text(discovery_session.get("project_title")) or project_key
    return {
        "project_key": project_key,
        "project_title": project_title,
        "pointer": dict(pointer_obj),
        "discovery_state": copy_discovery_state(discovery_state),
        "last_runtime_response": copy_discovery_state(runtime_response),
        "status_snapshot": dict(status_snapshot),
        "resume_context": runtime_response.get("resume_context", {}) if isinstance(runtime_response.get("resume_context"), dict) else {},
        "linked_discovery_session_id": normalize_text(discovery_session.get("discovery_session_id")),
        "linked_brief_id": normalize_text(requirement_brief.get("brief_id")),
        "linked_brief_version": normalize_text(requirement_brief.get("version")),
        "updated_at": now,
    }


def resolve_selected_project_key(project_registry: dict[str, Any], selected_value: str) -> str:
    query = normalize_text(selected_value).lower()
    if not query:
        return ""
    projects = normalize_dict_list(project_registry.get("projects"))
    for item in projects:
        key = normalize_text(item.get("project_key"))
        if key.lower() == query:
            return key
    for item in projects:
        key = normalize_text(item.get("project_key"))
        title = normalize_text(item.get("project_title"))
        if key.lower().startswith(query) or title.lower().startswith(query):
            return key
    query_slug = slugify(query, "project")
    for item in projects:
        key = normalize_text(item.get("project_key"))
        if key == query_slug:
            return key
    return ""


def render_project_registry(project_registry: dict[str, Any]) -> str:
    projects = normalize_dict_list(project_registry.get("projects"))
    if not projects:
        return "Проектов пока нет. Напиши идею автоматизации, чтобы открыть новый проект."

    active_key = normalize_text(project_registry.get("active_project_key"))
    lines = ["Доступные проекты:"]
    for item in projects:
        key = normalize_text(item.get("project_key"))
        status_snapshot = item.get("status_snapshot", {}) if isinstance(item.get("status_snapshot"), dict) else {}
        status_label = normalize_text(status_snapshot.get("user_visible_status_label")) or "Статус неизвестен"
        brief_version = normalize_text(item.get("linked_brief_version"))
        marker = "●" if key == active_key else "○"
        suffix = f", brief v{brief_version}" if brief_version else ""
        lines.append(f"{marker} {key} — {status_label}{suffix}")
    lines.append("Чтобы переключиться: /project <project_key>")
    return "\n".join(lines)

def build_intent_record(intent_type: str, selection_mode: str, envelope: dict[str, Any], *, telegram_adapter_session_id: str, now: str) -> dict[str, Any]:
    raw_text = normalize_text(envelope.get("message_text")) or normalize_text(envelope.get("command_text")) or normalize_text(envelope.get("callback_data"))
    return {
        "telegram_intent_id": f"tg-intent-{slugify(f'{telegram_adapter_session_id}-{now}-{intent_type}', 'tg-intent')}",
        "telegram_adapter_session_id": telegram_adapter_session_id,
        "intent_type": intent_type,
        "selection_mode": selection_mode,
        "raw_text": raw_text,
        "normalized_payload": {
            "command_text": normalize_text(envelope.get("command_text")),
            "callback_data": normalize_text(envelope.get("callback_data")),
        },
        "confidence": 0.9 if raw_text else 0.3,
        "recorded_at": now,
    }


def unsupported_update_response(envelope: dict[str, Any], *, telegram_adapter_session_id: str, now: str) -> dict[str, Any]:
    fallback_text = "Пока могу обработать только текстовые сообщения. Пришли ответ текстом, и я продолжу сбор требований."
    payload = build_telegram_reply_payload(
        "error_message",
        rendered_text=fallback_text,
        telegram_adapter_session_id=telegram_adapter_session_id,
        now=now,
    )
    return {
        "ok": False,
        "error": "unsupported_update_type",
        "telegram_update_envelope": envelope,
        "telegram_adapter_session": {
            "telegram_adapter_session_id": telegram_adapter_session_id,
            "status": "error",
            "updated_at": now,
        },
        "reply_payloads": [payload],
    }


def write_session_state(
    state_root: Path,
    telegram_adapter_session_id: str,
    *,
    session_obj: dict[str, Any],
    pointer_obj: dict[str, Any],
    discovery_state: dict[str, Any],
    last_runtime_response: dict[str, Any],
    status_snapshot: dict[str, Any],
    last_intent: dict[str, Any],
    project_registry: dict[str, Any] | None = None,
    delivery_items: list[dict[str, Any]] | None = None,
    delivery_results: list[dict[str, Any]] | None = None,
) -> None:
    payload = {
        "telegram_adapter_session": session_obj,
        "active_project_pointer": pointer_obj,
        "discovery_state": discovery_state,
        "last_runtime_response": last_runtime_response,
        "status_snapshot": status_snapshot,
        "last_intent": last_intent,
        "project_registry": project_registry or {},
        "delivery_items": delivery_items or [],
        "delivery_results": delivery_results or [],
    }
    write_json(payload, session_path(state_root, telegram_adapter_session_id))


def handle_update(args: argparse.Namespace) -> dict[str, Any]:
    now = utc_now()
    source = load_json(args.source)
    if not isinstance(source, dict):
        raise ValueError("source payload must be a JSON object")

    state_root = Path(args.state_root).expanduser().resolve()
    ensure_state_dirs(state_root)

    envelope = normalize_telegram_update_envelope(
        source,
        transport_mode=normalize_text(args.transport_mode) or "synthetic_fixture",
        now=now,
    )
    telegram_adapter_session_id = session_id_from_envelope(envelope)
    previous_session_payload = load_session(state_root, telegram_adapter_session_id)
    previous_session = previous_session_payload.get("telegram_adapter_session", {}) if isinstance(previous_session_payload.get("telegram_adapter_session"), dict) else {}
    previous_pointer = previous_session_payload.get("active_project_pointer", {}) if isinstance(previous_session_payload.get("active_project_pointer"), dict) else {}
    project_registry = normalize_project_registry(previous_session_payload)

    has_user_text = bool(normalize_text(envelope.get("message_text")))
    if not has_user_text:
        response = unsupported_update_response(envelope, telegram_adapter_session_id=telegram_adapter_session_id, now=now)
        append_history_event(
            state_root,
            telegram_adapter_session_id,
            {
                "recorded_at": now,
                "stage": "update_received",
                "status": "failed",
                "summary_text": "Unsupported Telegram update type",
                "telegram_update_id": normalize_text(envelope.get("telegram_update_id")),
            },
        )
        return response

    intent_type, selection_mode = infer_intent(envelope, previous_session_payload)
    intent_record = build_intent_record(
        intent_type,
        selection_mode,
        envelope,
        telegram_adapter_session_id=telegram_adapter_session_id,
        now=now,
    )

    if intent_type == "request_help":
        help_payload = build_telegram_reply_payload(
            "status_update",
            rendered_text=(
                "Я веду discovery как агент-архитектор фабрики. Пришли бизнес-задачу, затем отвечай на уточняющие вопросы, "
                "или используй /status для текущего состояния проекта."
            ),
            telegram_adapter_session_id=telegram_adapter_session_id,
            now=now,
        )
        append_history_event(
            state_root,
            telegram_adapter_session_id,
            {
                "recorded_at": now,
                "stage": "intent_resolved",
                "status": "completed",
                "summary_text": "Help response returned",
                "intent_type": intent_type,
            },
        )
        return {
            "ok": True,
            "telegram_update_envelope": envelope,
            "telegram_intent": intent_record,
            "telegram_adapter_session": previous_session if previous_session else {
                "telegram_adapter_session_id": telegram_adapter_session_id,
                "status": "idle",
                "updated_at": now,
            },
            "reply_payloads": [help_payload],
        }

    if intent_type == "list_projects":
        projects_payload = build_telegram_reply_payload(
            "status_update",
            rendered_text=render_project_registry(project_registry),
            telegram_adapter_session_id=telegram_adapter_session_id,
            now=now,
        )
        return {
            "ok": True,
            "telegram_update_envelope": envelope,
            "telegram_intent": intent_record,
            "telegram_adapter_session": previous_session if previous_session else {
                "telegram_adapter_session_id": telegram_adapter_session_id,
                "status": "idle",
                "updated_at": now,
            },
            "active_project_pointer": previous_pointer,
            "reply_payloads": [projects_payload],
            "project_registry": project_registry,
        }

    if intent_type == "select_project":
        requested_value = parse_selected_project_value(envelope)
        selected_key = resolve_selected_project_key(project_registry, requested_value)
        if not selected_key:
            unavailable_payload = build_telegram_reply_payload(
                "status_update",
                rendered_text=(
                    "Не нашел такой проект. "
                    + render_project_registry(project_registry)
                ),
                telegram_adapter_session_id=telegram_adapter_session_id,
                now=now,
            )
            return {
                "ok": True,
                "telegram_update_envelope": envelope,
                "telegram_intent": intent_record,
                "telegram_adapter_session": previous_session if previous_session else {
                    "telegram_adapter_session_id": telegram_adapter_session_id,
                    "status": "idle",
                    "updated_at": now,
                },
                "active_project_pointer": previous_pointer,
                "reply_payloads": [unavailable_payload],
                "project_registry": project_registry,
            }

        selected_record = project_record_for_key(project_registry, selected_key)
        selected_runtime = (
            selected_record.get("last_runtime_response", {})
            if isinstance(selected_record.get("last_runtime_response"), dict)
            else {}
        )
        if not selected_runtime:
            unavailable_payload = build_telegram_reply_payload(
                "status_update",
                rendered_text=(
                    f"Проект {selected_key} найден, но в нем пока нет runtime состояния. "
                    "Продолжи диалог сообщением в свободной форме."
                ),
                telegram_adapter_session_id=telegram_adapter_session_id,
                now=now,
            )
            return {
                "ok": True,
                "telegram_update_envelope": envelope,
                "telegram_intent": intent_record,
                "telegram_adapter_session": previous_session if previous_session else {
                    "telegram_adapter_session_id": telegram_adapter_session_id,
                    "status": "idle",
                    "updated_at": now,
                },
                "active_project_pointer": previous_pointer,
                "reply_payloads": [unavailable_payload],
                "project_registry": project_registry,
            }

        selected_pointer = selected_record.get("pointer", {}) if isinstance(selected_record.get("pointer"), dict) else {}
        if not normalize_text(selected_pointer.get("project_key")):
            selected_pointer = {
                "pointer_id": f"tg-pointer-{slugify(f'{telegram_adapter_session_id}-{selected_key}', 'tg-pointer')}",
                "telegram_adapter_session_id": telegram_adapter_session_id,
                "project_key": selected_key,
                "selection_mode": "project_select",
                "linked_discovery_session_id": normalize_text(selected_runtime.get("discovery_session", {}).get("discovery_session_id")),
                "linked_brief_id": normalize_text(selected_runtime.get("requirement_brief", {}).get("brief_id")),
                "linked_brief_version": normalize_text(selected_runtime.get("requirement_brief", {}).get("version")),
                "pointer_status": "active",
                "updated_at": now,
            }
        status_snapshot = build_telegram_status_snapshot(
            telegram_adapter_session_id,
            selected_key,
            adapter_status=selected_runtime.get("status"),
            next_action=selected_runtime.get("next_action"),
            brief=selected_runtime.get("requirement_brief", {}),
            now=now,
        )
        resume_projection = build_telegram_resume_projection(selected_runtime)
        reply_payloads: list[dict[str, Any]] = []
        if normalize_text(resume_projection.get("summary_text")):
            reply_payloads.append(
                build_telegram_reply_payload(
                    "status_update",
                    rendered_text=f"Переключил на проект {selected_key}. {resume_projection.get('summary_text')}",
                    telegram_adapter_session_id=telegram_adapter_session_id,
                    now=now,
                )
            )
        else:
            reply_payloads.append(
                build_telegram_reply_payload(
                    "status_update",
                    rendered_text=f"Переключил на проект {selected_key}.",
                    telegram_adapter_session_id=telegram_adapter_session_id,
                    now=now,
                )
            )
        reply_payloads.extend(
            build_telegram_reply_payloads(
                selected_runtime,
                telegram_adapter_session_id=telegram_adapter_session_id,
                now=now,
            )
        )

        selected_registry = dict(project_registry)
        selected_registry["active_project_key"] = selected_key
        session_obj = {
            "telegram_adapter_session_id": telegram_adapter_session_id,
            "chat_id": normalize_text(envelope.get("chat_id")),
            "from_user_id": normalize_text(envelope.get("from_user_id")),
            "status": telegram_session_runtime_status(
                selected_runtime.get("status"),
                next_action=selected_runtime.get("next_action"),
            ),
            "active_project_key": selected_key,
            "active_discovery_session_id": normalize_text(selected_runtime.get("discovery_session", {}).get("discovery_session_id")),
            "active_brief_id": normalize_text(selected_runtime.get("requirement_brief", {}).get("brief_id")),
            "last_seen_update_id": normalize_text(envelope.get("telegram_update_id")),
            "last_seen_message_id": normalize_text(envelope.get("message_id")),
            "last_user_message_at": normalize_text(envelope.get("received_at")) or now,
            "last_agent_message_at": now,
            "created_at": normalize_text(previous_session.get("created_at")) or now,
            "updated_at": now,
        }
        write_session_state(
            state_root,
            telegram_adapter_session_id,
            session_obj=session_obj,
            pointer_obj=selected_pointer,
            discovery_state=selected_record.get("discovery_state", {}) if isinstance(selected_record.get("discovery_state"), dict) else {},
            last_runtime_response=selected_runtime,
            status_snapshot=status_snapshot,
            last_intent=intent_record,
            project_registry=selected_registry,
            delivery_items=previous_session_payload.get("delivery_items", []) if isinstance(previous_session_payload.get("delivery_items"), list) else [],
            delivery_results=previous_session_payload.get("delivery_results", []) if isinstance(previous_session_payload.get("delivery_results"), list) else [],
        )
        append_history_event(
            state_root,
            telegram_adapter_session_id,
            {
                "recorded_at": now,
                "stage": "project_selected",
                "status": "completed",
                "summary_text": f"Selected project {selected_key}",
                "intent_type": intent_type,
                "project_key": selected_key,
                "telegram_update_id": normalize_text(envelope.get("telegram_update_id")),
            },
        )
        return {
            "ok": True,
            "telegram_update_envelope": envelope,
            "telegram_intent": intent_record,
            "telegram_adapter_session": session_obj,
            "active_project_pointer": selected_pointer,
            "status_snapshot": status_snapshot,
            "reply_payloads": reply_payloads,
            "project_registry": selected_registry,
            "runtime_response": {
                "status": normalize_text(selected_runtime.get("status")),
                "next_action": normalize_text(selected_runtime.get("next_action")),
                "next_topic": normalize_text(selected_runtime.get("next_topic")),
                "next_question": normalize_text(selected_runtime.get("next_question")),
                "discovery_session_id": normalize_text(selected_runtime.get("discovery_session", {}).get("discovery_session_id")),
                "brief_id": normalize_text(selected_runtime.get("requirement_brief", {}).get("brief_id")),
                "brief_version": normalize_text(selected_runtime.get("requirement_brief", {}).get("version")),
            },
        }

    if intent_type == "request_status":
        runtime_response = {}
        active_key = normalize_text(project_registry.get("active_project_key")) or normalize_text(previous_pointer.get("project_key"))
        if active_key:
            selected_record = project_record_for_key(project_registry, active_key)
            if selected_record:
                runtime_response = selected_record.get("last_runtime_response", {}) if isinstance(selected_record.get("last_runtime_response"), dict) else {}
        if not runtime_response:
            runtime_response = previous_session_payload.get("last_runtime_response", {}) if isinstance(previous_session_payload.get("last_runtime_response"), dict) else {}
        if not runtime_response:
            status_payload = build_telegram_reply_payload(
                "status_update",
                rendered_text="Активной сессии пока нет. Напиши идею автоматизации, чтобы открыть новый проект.",
                telegram_adapter_session_id=telegram_adapter_session_id,
                now=now,
            )
            return {
                "ok": True,
                "telegram_update_envelope": envelope,
                "telegram_intent": intent_record,
                "telegram_adapter_session": previous_session if previous_session else {
                    "telegram_adapter_session_id": telegram_adapter_session_id,
                    "status": "idle",
                    "updated_at": now,
                },
                "reply_payloads": [status_payload],
            }

        private_delivery_items = load_delivery_items(state_root, telegram_adapter_session_id)
        delivery_items = [
            {
                "artifact_kind": normalize_text(item.get("artifact_kind")),
                "download_name": normalize_text(item.get("download_name")),
                "download_status": "ready" if normalize_text(item.get("download_ref")) else "pending",
                "brief_version": normalize_text(item.get("brief_version")),
                "project_key": normalize_text(item.get("project_key")),
                "download_ref": normalize_text(item.get("download_ref")),
                "download_token": normalize_text(item.get("download_token")),
            }
            for item in private_delivery_items
        ]
        if delivery_items:
            runtime_response = copy_discovery_state(runtime_response)
            runtime_response["status"] = "completed"
            runtime_response["next_action"] = "publish_downloads"
            runtime_response["next_question"] = ""

        status_snapshot = build_telegram_status_snapshot(
            telegram_adapter_session_id,
            runtime_response.get("discovery_session", {}).get("project_key"),
            adapter_status=runtime_response.get("status"),
            next_action=runtime_response.get("next_action"),
            brief=runtime_response.get("requirement_brief", {}),
            now=now,
        )
        if delivery_items:
            reply_payloads = build_telegram_delivery_payloads(
                telegram_adapter_session_id=telegram_adapter_session_id,
                runtime_state=runtime_response,
                delivery_items=delivery_items,
                now=now,
            )
        else:
            reply_payloads = build_telegram_reply_payloads(
                runtime_response,
                telegram_adapter_session_id=telegram_adapter_session_id,
                now=now,
            )
        return {
            "ok": True,
            "telegram_update_envelope": envelope,
            "telegram_intent": intent_record,
            "telegram_adapter_session": previous_session,
            "active_project_pointer": previous_pointer,
            "status_snapshot": status_snapshot,
            "reply_payloads": reply_payloads,
            "delivery_items": delivery_items,
            "project_registry": project_registry,
        }

    start_new = intent_type == "start_project"
    request_session_payload = dict(previous_session_payload)
    if not start_new:
        active_key = normalize_text(project_registry.get("active_project_key")) or normalize_text(previous_pointer.get("project_key"))
        if active_key:
            selected_record = project_record_for_key(project_registry, active_key)
            if selected_record:
                if isinstance(selected_record.get("discovery_state"), dict):
                    request_session_payload["discovery_state"] = dict(selected_record.get("discovery_state"))
                if isinstance(selected_record.get("pointer"), dict):
                    request_session_payload["active_project_pointer"] = dict(selected_record.get("pointer"))

    discovery_request = build_discovery_request(
        envelope,
        request_session_payload,
        now=now,
        start_new=start_new,
        intent_type=intent_type,
    )
    runtime_response = run_discovery_runtime(discovery_request)
    runtime_response = sanitize_discovery_runtime_state(runtime_response)
    delivery_items: list[dict[str, Any]] = []
    delivery_results: list[dict[str, Any]] = []
    delivery_error = ""
    runtime_status = normalize_text(runtime_response.get("status"))
    runtime_next_action = normalize_text(runtime_response.get("next_action"))
    should_try_delivery = runtime_status in {"confirmed", "handoff_running", "completed"} or runtime_next_action in {
        "start_concept_pack_handoff",
        "run_factory_intake",
        "generate_artifacts",
        "publish_downloads",
    }

    current_brief_version = normalize_text(runtime_response.get("requirement_brief", {}).get("version"))
    cached_private_items = load_delivery_items(state_root, telegram_adapter_session_id)
    cached_items: list[dict[str, Any]] = []
    if cached_private_items:
        cached_items = [
            {
                "artifact_kind": normalize_text(item.get("artifact_kind")),
                "download_name": normalize_text(item.get("download_name")),
                "download_status": "ready" if normalize_text(item.get("download_ref")) else "pending",
                "brief_version": normalize_text(item.get("brief_version")),
                "project_key": normalize_text(item.get("project_key")),
                "download_ref": normalize_text(item.get("download_ref")),
                "download_token": normalize_text(item.get("download_token")),
            }
            for item in cached_private_items
        ]
    cached_brief_versions = {
        normalize_text(item.get("brief_version"))
        for item in cached_items
        if normalize_text(item.get("brief_version"))
    }
    can_reuse_cached_delivery = bool(cached_items) and (
        not current_brief_version or current_brief_version in cached_brief_versions
    )

    if should_try_delivery:
        if can_reuse_cached_delivery:
            delivery_items = cached_items
            runtime_response["status"] = "completed"
            runtime_response["next_action"] = "publish_downloads"
            runtime_response["next_question"] = ""
            if isinstance(runtime_response.get("factory_handoff_record"), dict):
                runtime_response["factory_handoff_record"]["handoff_status"] = "consumed"
                runtime_response["factory_handoff_record"]["consumed_at"] = normalize_text(runtime_response["factory_handoff_record"].get("consumed_at")) or now
        else:
            try:
                runtime_response, delivery_items, delivery_error, delivery_results = run_concept_pack_delivery(
                    state_root=state_root,
                    telegram_adapter_session_id=telegram_adapter_session_id,
                    runtime_state=runtime_response,
                    envelope=envelope,
                    now=now,
                )
            except Exception as exc:  # noqa: BLE001
                delivery_error = normalize_text(exc) or "Не удалось завершить downstream handoff."

    if delivery_error:
        runtime_response = copy_discovery_state(runtime_response)
        runtime_response["status"] = "handoff_running"
        runtime_response["next_action"] = "request_status"
        runtime_response["next_question"] = (
            "Фабрика обрабатывает confirmed brief, но delivery пока не завершен. "
            "Повтори /status через несколько секунд."
        )

    session_obj = build_adapter_session(
        previous_session=previous_session,
        envelope=envelope,
        runtime_response=runtime_response,
        telegram_adapter_session_id=telegram_adapter_session_id,
        now=now,
    )
    pointer_obj = build_active_pointer(
        previous_pointer=previous_pointer,
        telegram_adapter_session_id=telegram_adapter_session_id,
        runtime_response=runtime_response,
        selection_mode=selection_mode,
        now=now,
    )
    status_snapshot = build_telegram_status_snapshot(
        telegram_adapter_session_id,
        pointer_obj.get("project_key"),
        adapter_status=runtime_response.get("status"),
        next_action=runtime_response.get("next_action"),
        brief=runtime_response.get("requirement_brief", {}),
        now=now,
    )
    project_record = build_project_record(
        pointer_obj=pointer_obj,
        runtime_response=runtime_response,
        discovery_state=runtime_response,
        status_snapshot=status_snapshot,
        now=now,
    )
    project_registry = upsert_project_record(
        project_registry,
        project_record,
        active_project_key=normalize_text(pointer_obj.get("project_key")),
    )
    if delivery_items:
        reply_payloads = build_telegram_delivery_payloads(
            telegram_adapter_session_id=telegram_adapter_session_id,
            runtime_state=runtime_response,
            delivery_items=delivery_items,
            now=now,
        )
        if delivery_results:
            failed_count = sum(1 for item in delivery_results if normalize_text(item.get("delivery_status")) == "failed")
            if failed_count > 0:
                reply_payloads.append(
                    build_telegram_reply_payload(
                        "delivery_warning",
                        rendered_text=(
                            "Часть файлов не удалось отправить автоматически. "
                            "Проверь /status и повтори доставку из operator shell."
                        ),
                        telegram_adapter_session_id=telegram_adapter_session_id,
                        linked_discovery_session_id=runtime_response.get("discovery_session", {}).get("discovery_session_id"),
                        linked_brief_id=runtime_response.get("requirement_brief", {}).get("brief_id"),
                        linked_handoff_id=runtime_response.get("factory_handoff_record", {}).get("factory_handoff_id"),
                        now=now,
                    )
                )
    else:
        reply_payloads = build_telegram_reply_payloads(
            runtime_response,
            telegram_adapter_session_id=telegram_adapter_session_id,
            now=now,
        )

    write_session_state(
        state_root,
        telegram_adapter_session_id,
        session_obj=session_obj,
        pointer_obj=pointer_obj,
        discovery_state=runtime_response,
        last_runtime_response=runtime_response,
        status_snapshot=status_snapshot,
        last_intent=intent_record,
        project_registry=project_registry,
        delivery_items=delivery_items,
        delivery_results=delivery_results,
    )
    append_history_event(
        state_root,
        telegram_adapter_session_id,
        {
            "recorded_at": now,
            "stage": "discovery_routed",
            "status": "completed",
            "summary_text": normalize_text(runtime_response.get("next_question")) or "Telegram turn processed",
            "intent_type": intent_type,
            "project_key": pointer_obj.get("project_key"),
            "telegram_update_id": normalize_text(envelope.get("telegram_update_id")),
            "next_action": normalize_text(runtime_response.get("next_action")),
            "next_topic": normalize_text(runtime_response.get("next_topic")),
        },
    )

    response = {
        "ok": True,
        "telegram_update_envelope": envelope,
        "telegram_intent": intent_record,
        "telegram_adapter_session": session_obj,
        "active_project_pointer": pointer_obj,
        "status_snapshot": status_snapshot,
        "reply_payloads": reply_payloads,
        "project_registry": project_registry,
        "runtime_response": {
            "status": normalize_text(runtime_response.get("status")),
            "next_action": normalize_text(runtime_response.get("next_action")),
            "next_topic": normalize_text(runtime_response.get("next_topic")),
            "next_question": normalize_text(runtime_response.get("next_question")),
            "discovery_session_id": normalize_text(runtime_response.get("discovery_session", {}).get("discovery_session_id")),
            "brief_id": normalize_text(runtime_response.get("requirement_brief", {}).get("brief_id")),
            "brief_version": normalize_text(runtime_response.get("requirement_brief", {}).get("version")),
        },
    }
    if delivery_items:
        response["delivery_items"] = delivery_items
    if delivery_results:
        response["delivery_results"] = delivery_results
    if delivery_error:
        response["delivery_error"] = sanitize_transport_text(delivery_error)
    return response


def main() -> int:
    args = parse_args()
    if args.command == "handle-update":
        response = handle_update(args)
        write_json(response, args.output)
        return 0
    raise ValueError(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    sys.exit(main())
