#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import binascii
import io
import json
import mimetypes
import os
import re
import subprocess
import sys
import tempfile
import time
import zipfile
from copy import deepcopy
from html import unescape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse
from xml.etree import ElementTree

from agent_factory_llm import (
    LLMError,
    chat_completion_json,
    llm_settings_from_env,
)
from agent_factory_common import (
    build_web_reply_card,
    build_web_demo_status_snapshot,
    build_web_reply_cards,
    load_json,
    normalize_download_artifacts,
    normalize_text,
    sha256_hex,
    slugify,
    utc_now,
    web_session_runtime_status,
    write_json,
)


SCRIPT_ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_ROOT.parent
DISCOVERY_SCRIPT = SCRIPT_ROOT / "agent-factory-discovery.py"
INTAKE_SCRIPT = SCRIPT_ROOT / "agent-factory-intake.py"
ARTIFACT_SCRIPT = SCRIPT_ROOT / "agent-factory-artifacts.py"
DEFAULT_STATE_ROOT = PROJECT_ROOT / "data/agent-factory/web-demo"
DEFAULT_ASSET_ROOT = PROJECT_ROOT / "web/agent-factory-demo"
STATE_DIRS = ("sessions", "pointers", "resume", "access", "history", "downloads", "uploads", "employees")
DISCOVERY_STATE_KEYS = (
    "project_key",
    "raw_idea",
    "request_channel",
    "requester_identity",
    "working_language",
    "discovery_session",
    "requirement_topics",
    "clarification_items",
    "example_cases",
    "conversation_turns",
    "open_questions",
    "normalized_answers",
    "captured_answers",
    "discovery_answers",
    "requirement_brief",
    "brief_revisions",
    "brief_feedback_history",
    "confirmation_snapshot",
    "confirmation_history",
    "factory_handoff_record",
    "handoff_history",
    "production_simulation",
    "status",
    "next_action",
    "next_topic",
    "next_question",
    "brief_markdown",
)
MAX_UPLOADED_FILES = 4
MAX_UPLOADED_FILE_BYTES = 512 * 1024
MAX_UPLOADED_EXCERPT_CHARS = 2200
TEXT_UPLOAD_SUFFIXES = {
    ".txt",
    ".md",
    ".csv",
    ".tsv",
    ".json",
    ".yaml",
    ".yml",
    ".xml",
    ".html",
    ".htm",
    ".log",
    ".docx",
}
ARCHITECT_AGENT_DISPLAY_NAME_DEFAULT = "Агент-архитектор Moltis"
LOW_SIGNAL_MARKERS = {
    "ok",
    "okay",
    "test",
    "ping",
    "ок",
    "ага",
    "угу",
    "да",
    "нет",
    "норм",
    "понял",
    "поняла",
    "хз",
    "лол",
    "+",
}
CONFIRM_BRIEF_TEXT_MARKERS = (
    "подтверждаю",
    "подтверждено",
    "подтвердить",
    "confirm brief",
    "confirmed brief",
    "approve brief",
    "согласен",
    "согласна",
    "ок подтверждаю",
)
CONFIRM_BRIEF_NEGATION_MARKERS = (
    "не подтверж",
    "не готов подтверж",
    "not confirm",
    "don't confirm",
)
REPEAT_ACK_MARKERS = (
    "уже отвечал",
    "уже отвечала",
    "на этот вопрос я тоже отвечал",
    "на этот вопрос я уже отвечал",
    "дублирую ответ",
    "дублирую",
    "перефразируй",
    "неправильно понимаю",
    "already answered",
)
BRIEF_CORRECTION_TEXT_MARKERS = (
    "правк",
    "исправ",
    "уточни",
    "доработ",
    "переоткрой",
    "переоткры",
    "измени",
    "обнови brief",
    "нужно изменить",
)
PRODUCTION_SIMULATION_TEXT_MARKERS = (
    "имитац",
    "симуляц",
    "запусти цифров",
    "цифровой сущности",
    "production simulation",
    "стартовый результат",
)
REDACTION_ACK_MARKERS = (
    "обезлич",
    "без реквизит",
    "без реальных",
    "без назван",
    "синтетич",
    "synthetic",
    "anonym",
    "redact",
    "masked",
)
REDACTION_NEGATION_MARKERS = (
    "не обезлич",
    "без обезлич",
    "не могу обезлич",
)
UPLOAD_REFERENCE_MARKERS = (
    "файл",
    "файлы",
    "влож",
    "прикреп",
    "прилож",
    "attached",
    "attachment",
    "upload",
)
SENSITIVE_DIGIT_PATTERN = re.compile(r"\b\d{6,}\b")
STRUCTURED_EXAMPLE_RECORD_PATTERN = re.compile(
    r"[0-9A-Za-zА-Яа-я_<>.\-]+(?:[,;|\t][0-9A-Za-zА-Яа-я_<>.\-]+){1,8}"
)
BUSINESS_IDEA_SIGNALS = (
    "автомат",
    "процесс",
    "заявк",
    "скоринг",
    "согласован",
    "обработ",
    "клиент",
    "договор",
    "счет",
    "счёт",
    "invoice",
    "approval",
    "support",
    "тикет",
    "ticket",
    "анализ",
    "отчет",
    "отчёт",
    "проверк",
    "кредит",
    "документ",
    "эскалац",
    "workflow",
)
ARCHITECT_TOPIC_FRAMES: dict[str, dict[str, str]] = {
    "problem": {
        "lead": "Начинаем с контекста задачи.",
        "question": "Какую конкретную бизнес-проблему должен решить будущий агент?",
        "example": "Например: заявки согласуются слишком долго, из-за чего сделки теряются.",
    },
    "target_users": {
        "lead": "Чтобы спроектировать рабочие сценарии агента, уточню роли пользователей.",
        "question": "Кто будет основным пользователем или выгодоприобретателем результата?",
        "example": "Например: оператор первой линии и руководитель кредитного комитета.",
    },
    "current_workflow": {
        "lead": "Теперь нужно зафиксировать текущий процесс как есть.",
        "question": "Как этот процесс работает сейчас и где основные потери?",
        "example": "Например: часть шагов делается в Excel вручную и теряется время на сверку.",
    },
    "desired_outcome": {
        "lead": "Дальше уточним целевое состояние после автоматизации.",
        "question": "Какой результат должен получать бизнес после автоматизации?",
        "example": "Например: время обработки сокращено вдвое, а исключения автоматически эскалируются.",
    },
    "user_story": {
        "lead": "Нужно закрепить приоритетный пользовательский сценарий.",
        "question": "Какому сотруднику и в какой ситуации агент должен помогать в первую очередь?",
        "example": "Например: дежурному аналитику при первичной проверке входящей заявки.",
    },
    "input_examples": {
        "lead": "Теперь зафиксируем входы, на которых агент будет работать.",
        "question": "Приведи 1-2 типовых примера входных данных или ситуаций, с которыми агент будет работать.",
        "example": "Например: заявка клиента, письмо в свободной форме, CSV-выгрузка.",
    },
    "expected_outputs": {
        "lead": "Фиксируем ожидаемый результат работы агента.",
        "question": "Что пользователь должен получить на выходе по итогам обработки?",
        "example": "Например: решение, пояснение причин и список шагов для исполнения.",
    },
    "constraints": {
        "lead": "Перед сборкой решения уточним ограничения и запреты.",
        "question": "Какие ограничения, запреты или исключения нужно учитывать?",
        "example": "Например: не использовать персональные данные и не отправлять сообщения клиенту без согласования.",
    },
    "success_metrics": {
        "lead": "Нужны измеримые критерии, по которым проверим пользу автоматизации.",
        "question": "По каким признакам поймем, что решение действительно приносит пользу?",
        "example": "Например: время обработки, точность классификации и доля ручных эскалаций.",
    },
}
ARCHITECT_TOPIC_ORDER = list(ARCHITECT_TOPIC_FRAMES.keys())
VALID_WEB_UI_ACTIONS = {
    "start_project",
    "submit_turn",
    "request_status",
    "request_brief_review",
    "request_brief_correction",
    "confirm_brief",
    "reopen_brief",
    "download_artifact",
    "request_demo_access",
    "submit_access_token",
}
LLM_DECISION_PROMPT = """Ты фабричный агент-архитектор Moltis.
Текущий этап: discovery требований.

Верни строго JSON-объект следующего формата:
{
  "decision": "accept|clarify|rephrase|advance",
  "next_topic": "problem|target_users|current_workflow|desired_outcome|user_story|input_examples|expected_outputs|constraints|success_metrics|",
  "next_question": "один следующий вопрос пользователю",
  "low_signal": false,
  "topic_summary": "краткое подтверждение зафиксированного ответа"
}

Ограничения:
1. Не используй markdown и не добавляй текст вне JSON.
2. Не выходи за список allowed_topics, который передан во входе.
3. Если пользователь пишет "уже отвечал", "перефразируй" или аналог — используй decision=rephrase.
4. Если ответ недостаточно конкретный для текущей темы — decision=clarify и оставь ту же тему.
5. Если тема закрыта, можно переходить к следующей теме по цепочке через decision=advance.
6. Не добавляй "Например:" и не пиши служебные статусы в next_question.
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve or run the web-first factory demo adapter.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    handle_turn = subparsers.add_parser("handle-turn", help="Normalize one browser turn and route it into discovery.")
    handle_turn.add_argument("--source", required=True, help="Path to a browser-envelope JSON document")
    handle_turn.add_argument("--output", help="Optional JSON output path")
    handle_turn.add_argument(
        "--state-root",
        default=str(DEFAULT_STATE_ROOT),
        help="Adapter state root for sessions/access/history persistence",
    )

    serve = subparsers.add_parser("serve", help="Serve the browser demo shell and JSON API.")
    serve.add_argument("--host", default="127.0.0.1", help="Bind host")
    serve.add_argument("--port", default=18791, type=int, help="Bind port")
    serve.add_argument(
        "--state-root",
        default=str(DEFAULT_STATE_ROOT),
        help="Adapter state root for sessions/access/history persistence",
    )
    serve.add_argument(
        "--assets-root",
        default=str(DEFAULT_ASSET_ROOT),
        help="Static browser shell root",
    )
    return parser.parse_args()


def ensure_state_layout(state_root: Path) -> None:
    for dirname in STATE_DIRS:
        (state_root / dirname).mkdir(parents=True, exist_ok=True)


def env_text(name: str, default: str = "") -> str:
    return normalize_text(os.environ.get(name)) or default


def access_gate_settings() -> dict[str, Any]:
    demo_domain = env_text("ASC_DEMO_DOMAIN")
    public_base_url = env_text("ASC_DEMO_PUBLIC_BASE_URL") or (f"https://{demo_domain}" if demo_domain else "")
    shared_token = env_text("ASC_DEMO_SHARED_TOKEN")
    shared_token_hash = env_text("ASC_DEMO_SHARED_TOKEN_HASH") or (sha256_hex(shared_token) if shared_token else "")
    access_gate_mode = env_text("ASC_DEMO_ACCESS_MODE") or ("shared_token_hash" if shared_token_hash else "fixture_trust")
    access_gate_configured = access_gate_mode != "shared_token_hash" or bool(shared_token_hash)
    access_gate_ready = access_gate_mode != "fixture_trust" and access_gate_configured
    return {
        "demo_domain": demo_domain,
        "public_base_url": public_base_url,
        "access_gate_mode": access_gate_mode,
        "shared_token_hash": shared_token_hash,
        "access_gate_configured": access_gate_configured,
        "access_gate_ready": access_gate_ready,
        "operator_label": env_text("ASC_DEMO_OPERATOR_LABEL") or "factory-demo-operator",
    }


def count_json_files(root: Path) -> int:
    if not root.is_dir():
        return 0
    return sum(1 for item in root.iterdir() if item.is_file() and item.suffix == ".json")


def count_child_dirs(root: Path) -> int:
    if not root.is_dir():
        return 0
    return sum(1 for item in root.iterdir() if item.is_dir())


def summarize_session_statuses(state_root: Path) -> dict[str, Any]:
    summary = {
        "active_session_count": 0,
        "awaiting_user_reply_count": 0,
        "awaiting_confirmation_count": 0,
        "handoff_running_count": 0,
        "download_ready_count": 0,
        "needs_attention_session_count": 0,
        "last_session_updated_at": "",
    }
    sessions_root = state_root / "sessions"
    if not sessions_root.is_dir():
        return summary

    last_session_update = ""
    for session_path in sessions_root.iterdir():
        if not session_path.is_file() or session_path.suffix != ".json":
            continue
        session_payload = load_json(session_path)
        if not isinstance(session_payload, dict):
            continue
        summary["active_session_count"] += 1
        web_demo_session = session_payload.get("web_demo_session", {})
        web_demo_session = web_demo_session if isinstance(web_demo_session, dict) else {}
        status_snapshot = session_payload.get("status_snapshot", {})
        status_snapshot = status_snapshot if isinstance(status_snapshot, dict) else {}
        session_status = normalize_text(web_demo_session.get("status"))
        user_visible_status = normalize_text(status_snapshot.get("user_visible_status"))
        if session_status == "awaiting_user_reply":
            summary["awaiting_user_reply_count"] += 1
        if session_status == "awaiting_confirmation" or user_visible_status == "awaiting_confirmation":
            summary["awaiting_confirmation_count"] += 1
        if session_status == "handoff_running" or user_visible_status == "handoff_running":
            summary["handoff_running_count"] += 1
        if session_status == "download_ready" or normalize_text(status_snapshot.get("download_readiness")) == "ready":
            summary["download_ready_count"] += 1
        if bool(status_snapshot.get("needs_operator_attention")) or user_visible_status == "needs_attention":
            summary["needs_attention_session_count"] += 1
        updated_at = normalize_text(web_demo_session.get("updated_at")) or normalize_text(status_snapshot.get("captured_at"))
        if updated_at and (not last_session_update or updated_at > last_session_update):
            last_session_update = updated_at

    summary["last_session_updated_at"] = last_session_update
    return summary


def build_operator_status_publication(state_root: Path) -> dict[str, Any]:
    settings = access_gate_settings()
    ensure_state_layout(state_root)
    state_root_ready = all((state_root / dirname).is_dir() for dirname in STATE_DIRS)
    session_summary = summarize_session_statuses(state_root)
    publication_status = (
        "ready"
        if state_root_ready and settings["access_gate_ready"]
        else "degraded"
    )
    needs_operator_attention = publication_status != "ready"
    return {
        "publication_status": publication_status,
        "needs_operator_attention": needs_operator_attention,
        "state_root_ready": state_root_ready,
        "active_session_count": session_summary["active_session_count"],
        "awaiting_user_reply_count": session_summary["awaiting_user_reply_count"],
        "awaiting_confirmation_count": session_summary["awaiting_confirmation_count"],
        "handoff_running_count": session_summary["handoff_running_count"],
        "download_ready_count": session_summary["download_ready_count"],
        "needs_attention_session_count": session_summary["needs_attention_session_count"],
        "last_session_updated_at": session_summary["last_session_updated_at"],
        "access_grant_count": count_json_files(state_root / "access"),
        "pointer_count": count_json_files(state_root / "pointers"),
        "resume_context_count": count_json_files(state_root / "resume"),
        "history_entry_count": count_json_files(state_root / "history"),
        "download_session_count": count_child_dirs(state_root / "downloads"),
        "access_gate_mode": settings["access_gate_mode"],
        "access_gate_configured": settings["access_gate_configured"],
        "access_gate_ready": settings["access_gate_ready"],
        "public_base_url": settings["public_base_url"],
        "demo_domain": settings["demo_domain"],
        "published_at": utc_now(),
    }


def sanitize_download_artifacts(
    download_artifacts: list[dict[str, Any]] | None,
    *,
    web_demo_session_id: str = "",
) -> list[dict[str, Any]]:
    sanitized: list[dict[str, Any]] = []
    for item in normalize_download_artifacts(download_artifacts or []):
        artifact_kind = normalize_text(item.get("artifact_kind"))
        download_name = normalize_text(item.get("download_name"))
        project_key = normalize_text(item.get("project_key"))
        brief_version = normalize_text(item.get("brief_version"))
        download_token = normalize_text(item.get("download_token")) or sha256_hex(
            f"{web_demo_session_id}:{artifact_kind}:{download_name}:{brief_version}"
        )[:16]
        raw_status = normalize_text(item.get("download_status")) or "pending"
        public_status = "ready" if raw_status in {"available", "ready"} else "pending"
        sanitized.append(
            {
                "artifact_kind": artifact_kind,
                "download_name": download_name,
                "download_status": public_status,
                "project_key": project_key,
                "brief_version": brief_version,
                "download_token": download_token,
                "download_url": f"/api/download?session_id={web_demo_session_id}&token={download_token}"
                if web_demo_session_id and download_token and public_status == "ready"
                else "",
            }
        )
    return sanitized


def delivery_root(state_root: Path, web_demo_session_id: str) -> Path:
    return state_root / "downloads" / (web_demo_session_id or "anonymous-session")


def delivery_index_path(state_root: Path, web_demo_session_id: str) -> Path:
    return delivery_root(state_root, web_demo_session_id) / "delivery-index.json"


def write_delivery_index(state_root: Path, web_demo_session_id: str, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    root = delivery_root(state_root, web_demo_session_id)
    root.mkdir(parents=True, exist_ok=True)
    normalized = normalize_download_artifacts(manifest)
    private_items: list[dict[str, Any]] = []
    public_items: list[dict[str, Any]] = []
    for item in normalized:
        artifact_kind = normalize_text(item.get("artifact_kind"))
        download_name = normalize_text(item.get("download_name"))
        project_key = normalize_text(item.get("project_key"))
        brief_version = normalize_text(item.get("brief_version"))
        download_ref = normalize_text(item.get("download_ref"))
        download_token = sha256_hex(f"{web_demo_session_id}:{artifact_kind}:{download_name}:{brief_version}")[:16]
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
                "download_status": "ready" if download_ref else "pending",
                "project_key": project_key,
                "brief_version": brief_version,
                "download_token": download_token,
            }
        )
    write_json(
        {
            "web_demo_session_id": web_demo_session_id,
            "generated_at": utc_now(),
            "items": private_items,
        },
        delivery_index_path(state_root, web_demo_session_id),
    )
    return sanitize_download_artifacts(public_items, web_demo_session_id=web_demo_session_id)


def load_delivery_entry(state_root: Path, web_demo_session_id: str, download_token: str) -> dict[str, Any]:
    index_path = delivery_index_path(state_root, web_demo_session_id)
    if not index_path.is_file():
        return {}
    index = load_json(index_path)
    if not isinstance(index, dict):
        return {}
    items = index.get("items", [])
    if not isinstance(items, list):
        return {}
    for item in items:
        if not isinstance(item, dict):
            continue
        if normalize_text(item.get("download_token")) == download_token:
            return item
    return {}


def employee_registry_path(state_root: Path) -> Path:
    return state_root / "employees" / "digital-employees-registry.json"


def employee_execution_dir(state_root: Path) -> Path:
    return state_root / "employees" / "executions"


def load_employee_registry(state_root: Path) -> dict[str, Any]:
    registry_path = employee_registry_path(state_root)
    if registry_path.is_file():
        payload = load_json(registry_path)
        if isinstance(payload, dict):
            employees = payload.get("employees")
            return {
                "schema_version": normalize_text(payload.get("schema_version")) or "v1",
                "updated_at": normalize_text(payload.get("updated_at")),
                "employees": [dict(item) for item in employees if isinstance(item, dict)] if isinstance(employees, list) else [],
            }
    return {
        "schema_version": "v1",
        "updated_at": "",
        "employees": [],
    }


def starter_request_from_runtime_state(runtime_state: dict[str, Any], requirement_brief: dict[str, Any]) -> str:
    raw_idea = normalize_text(runtime_state.get("raw_idea"))
    if raw_idea:
        return raw_idea
    turns = runtime_state.get("conversation_turns")
    if isinstance(turns, list):
        for turn in turns:
            if not isinstance(turn, dict):
                continue
            if normalize_text(turn.get("actor")) != "user":
                continue
            turn_type = normalize_text(turn.get("turn_type"))
            if turn_type not in {"idea_statement", "browser_reply"}:
                continue
            text = normalize_text(turn.get("raw_text"))
            if text:
                return text
    return normalize_text(requirement_brief.get("problem_statement")) or "Собери one-page по текущему клиентскому кейсу."


def upsert_registry_employee(registry: dict[str, Any], employee_entry: dict[str, Any]) -> None:
    employees = registry.get("employees")
    if not isinstance(employees, list):
        employees = []
    employee_id = normalize_text(employee_entry.get("digital_employee_id"))
    if not employee_id:
        return
    for index, item in enumerate(employees):
        if not isinstance(item, dict):
            continue
        if normalize_text(item.get("digital_employee_id")) == employee_id:
            merged = dict(item)
            merged.update(employee_entry)
            employees[index] = merged
            registry["employees"] = employees
            return
    employees.append(employee_entry)
    registry["employees"] = employees


def simulate_post_handoff_production(
    state_root: Path,
    web_demo_session_id: str,
    runtime_state: dict[str, Any],
    uploaded_files: list[dict[str, Any]] | None,
) -> dict[str, Any]:
    existing = runtime_state.get("production_simulation")
    if isinstance(existing, dict):
        execution_ref = Path(normalize_text(existing.get("execution_ref")))
        registry_ref = Path(normalize_text(existing.get("registry_ref")))
        if normalize_text(existing.get("status")) == "completed" and execution_ref.is_file() and registry_ref.is_file():
            return existing

    now = utc_now()
    requirement_brief = (
        runtime_state.get("requirement_brief", {})
        if isinstance(runtime_state.get("requirement_brief"), dict)
        else {}
    )
    project_key = normalize_text(requirement_brief.get("project_key")) or normalize_text(runtime_state.get("project_key")) or "project"
    brief_id = normalize_text(requirement_brief.get("brief_id")) or f"brief-{slugify(project_key, 'brief')}"
    brief_version = normalize_text(requirement_brief.get("version")) or "1.0"
    employee_id = f"digital-employee-{slugify(f'{project_key}-{brief_version}', 'employee')}"
    employee_name = f"Цифровой сотрудник: {compact_display_title(requirement_brief.get('problem_statement'), runtime_state.get('raw_idea'))}"
    starter_request = starter_request_from_runtime_state(runtime_state, requirement_brief)

    normalized_uploads = normalize_uploaded_files(uploaded_files)
    upload_names = [normalize_text(item.get("name")) for item in normalized_uploads if normalize_text(item.get("name"))]
    data_profile = "live_user_data" if upload_names else "live_user_dialog_context"
    data_profile_summary = (
        f"боевые данные пользователя из вложений: {', '.join(upload_names[:3])}"
        if upload_names
        else "боевой контекст из пользовательского диалога без вложений"
    )
    expected_outputs = requirement_brief.get("expected_outputs")
    expected_output_hint = ""
    if isinstance(expected_outputs, list) and expected_outputs:
        expected_output_hint = normalize_text(expected_outputs[0])
    elif expected_outputs is not None:
        expected_output_hint = normalize_text(expected_outputs)
    if not expected_output_hint:
        expected_output_hint = "one-page PDF с рекомендацией"

    execution_summary = (
        f"Стартовый запрос выполнен в имитации production: «{starter_request}». "
        f"Использован источник данных: {data_profile_summary}. "
        f"Результат: сформирован прототипный выходной артефакт ({expected_output_hint}) и подготовлен для пользовательской проверки."
    )

    executions_dir = employee_execution_dir(state_root)
    executions_dir.mkdir(parents=True, exist_ok=True)
    execution_stamp = now.replace(":", "").replace("-", "").replace("T", "_")
    execution_id = f"execution-{slugify(web_demo_session_id, 'session')}-{execution_stamp}"
    execution_path = executions_dir / f"{execution_id}.json"
    execution_payload = {
        "execution_id": execution_id,
        "digital_employee_id": employee_id,
        "web_demo_session_id": web_demo_session_id,
        "starter_request": starter_request,
        "data_profile": data_profile,
        "data_profile_summary": data_profile_summary,
        "status": "completed",
        "output_summary": execution_summary,
        "started_at": now,
        "completed_at": now,
    }
    write_json(execution_payload, execution_path)

    registry = load_employee_registry(state_root)
    employee_entry = {
        "digital_employee_id": employee_id,
        "display_name": employee_name,
        "lifecycle_state": "prototype_simulated",
        "project_key": project_key,
        "source_brief_id": brief_id,
        "source_brief_version": brief_version,
        "registered_at": normalize_text(now),
        "updated_at": normalize_text(now),
        "last_execution_id": execution_id,
        "capabilities": [
            "onepage.generation",
            "requirements.aligned-output",
            "initial_live_data_execution",
        ],
    }
    upsert_registry_employee(registry, employee_entry)
    registry["updated_at"] = now
    registry_path = employee_registry_path(state_root)
    registry_path.parent.mkdir(parents=True, exist_ok=True)
    write_json(registry, registry_path)

    return {
        "status": "completed",
        "digital_employee_id": employee_id,
        "digital_employee_name": employee_name,
        "starter_request": starter_request,
        "data_profile": data_profile,
        "data_profile_summary": data_profile_summary,
        "execution_summary": execution_summary,
        "execution_ref": str(execution_path),
        "registry_ref": str(registry_path),
        "completed_at": now,
    }


def write_production_simulation_download(
    state_root: Path,
    web_demo_session_id: str,
    simulation: dict[str, Any],
    requirement_brief: dict[str, Any],
) -> dict[str, Any]:
    session_root = delivery_root(state_root, web_demo_session_id)
    downloads_root = session_root / "downloads"
    downloads_root.mkdir(parents=True, exist_ok=True)
    download_name = "digital-employee-demo.md"
    download_path = downloads_root / download_name
    markdown = "\n".join(
        [
            "# Имитация production цифрового сотрудника",
            "",
            f"- `digital_employee_id`: `{normalize_text(simulation.get('digital_employee_id'))}`",
            f"- `name`: {normalize_text(simulation.get('digital_employee_name'))}",
            f"- `source_brief_id`: {normalize_text(requirement_brief.get('brief_id'))}",
            f"- `source_brief_version`: {normalize_text(requirement_brief.get('version'))}",
            f"- `data_profile`: {normalize_text(simulation.get('data_profile'))}",
            f"- `registry_ref`: {normalize_text(simulation.get('registry_ref'))}",
            f"- `execution_ref`: {normalize_text(simulation.get('execution_ref'))}",
            "",
            "## Стартовый запрос пользователя",
            normalize_text(simulation.get("starter_request")) or "Не указан",
            "",
            "## Результат имитации исполнения",
            normalize_text(simulation.get("execution_summary")) or "Не указан",
            "",
            "_Примечание: это MVP0-имитация production path. Фактический deployment остаётся в MVP1._",
            "",
        ]
    )
    download_path.write_text(markdown, encoding="utf-8")
    return {
        "artifact_kind": "production_simulation",
        "download_name": download_name,
        "download_ref": str(download_path),
        "download_status": "available",
        "project_key": normalize_text(requirement_brief.get("project_key")),
        "brief_version": normalize_text(requirement_brief.get("version")),
    }


def load_payload(path: str) -> dict[str, Any]:
    payload = load_json(path)
    if not isinstance(payload, dict):
        raise ValueError("browser source document must be a JSON object")
    return payload


def copy_discovery_state(source: dict[str, Any]) -> dict[str, Any]:
    copied: dict[str, Any] = {}
    for key in DISCOVERY_STATE_KEYS:
        if key in source:
            copied[key] = deepcopy(source[key])
    return copied


def load_saved_session(state_root: Path, session_id: str) -> dict[str, Any]:
    if not session_id:
        return {}
    session_path = state_root / "sessions" / f"{session_id}.json"
    if not session_path.is_file():
        return {}
    saved = load_json(session_path)
    if not isinstance(saved, dict):
        return {}
    return saved


def load_saved_pointer(state_root: Path, session_id: str) -> dict[str, Any]:
    if not session_id:
        return {}
    pointer_path = state_root / "pointers" / f"{session_id}.json"
    if not pointer_path.is_file():
        return {}
    pointer = load_json(pointer_path)
    if not isinstance(pointer, dict):
        return {}
    return pointer


def load_saved_resume_context(state_root: Path, session_id: str) -> dict[str, Any]:
    if not session_id:
        return {}
    resume_path = state_root / "resume" / f"{session_id}.json"
    if not resume_path.is_file():
        return {}
    resume_context = load_json(resume_path)
    if not isinstance(resume_context, dict):
        return {}
    return resume_context


def hydrate_saved_session_response(state_root: Path, saved_session: dict[str, Any]) -> dict[str, Any]:
    response = deepcopy(saved_session) if isinstance(saved_session, dict) else {}
    session_id = normalize_text(response.get("web_demo_session", {}).get("web_demo_session_id"))
    if not session_id:
        return response
    saved_pointer = load_saved_pointer(state_root, session_id)
    if saved_pointer:
        response["browser_project_pointer"] = saved_pointer
    saved_resume = load_saved_resume_context(state_root, session_id)
    if saved_resume:
        response["resume_context"] = saved_resume
    return response


def upload_session_root(state_root: Path, session_id: str) -> Path:
    return state_root / "uploads" / (session_id or "anonymous-session")


def sanitize_upload_name(value: Any) -> str:
    name = Path(normalize_text(value) or "attachment").name
    sanitized = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-")
    return sanitized or "attachment"


def truncate_excerpt(text: str, *, limit: int = MAX_UPLOADED_EXCERPT_CHARS) -> str:
    normalized_lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines()]
    normalized = "\n".join(line for line in normalized_lines if line)
    if len(normalized) <= limit:
        return normalized
    shortened = normalized[:limit].rsplit(" ", 1)[0].rstrip()
    return f"{shortened or normalized[:limit]}…"


def decode_text_excerpt(raw_bytes: bytes) -> str:
    for encoding in ("utf-8-sig", "utf-16", "cp1251", "latin-1"):
        try:
            return raw_bytes.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw_bytes.decode("utf-8", errors="ignore")


def extract_docx_excerpt(raw_bytes: bytes) -> str:
    with zipfile.ZipFile(io.BytesIO(raw_bytes)) as archive:
        document_xml = archive.read("word/document.xml")
    root = ElementTree.fromstring(document_xml)
    text_parts = [chunk.strip() for chunk in root.itertext() if normalize_text(chunk)]
    return "\n".join(text_parts)


def extract_upload_excerpt(raw_bytes: bytes, *, content_type: str, upload_name: str) -> tuple[str, str]:
    suffix = Path(upload_name).suffix.lower()
    media_type = normalize_text(content_type).lower()
    try:
        if suffix == ".docx":
            excerpt = extract_docx_excerpt(raw_bytes)
            return truncate_excerpt(unescape(excerpt)), "excerpt_ready"
        if media_type.startswith("text/") or suffix in TEXT_UPLOAD_SUFFIXES or media_type in {
            "application/json",
            "application/xml",
            "application/x-yaml",
            "text/csv",
            "application/csv",
        }:
            excerpt = decode_text_excerpt(raw_bytes)
            return truncate_excerpt(unescape(excerpt)), "excerpt_ready"
    except (OSError, ValueError, zipfile.BadZipFile, KeyError, ElementTree.ParseError):
        return "", "metadata_only"
    return "", "metadata_only"


def normalize_uploaded_files(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    normalized: list[dict[str, Any]] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        try:
            size_bytes = int(item.get("size_bytes") or 0)
        except (TypeError, ValueError):
            size_bytes = 0
        try:
            original_size_bytes = int(item.get("original_size_bytes") or item.get("size_bytes") or 0)
        except (TypeError, ValueError):
            original_size_bytes = size_bytes
        normalized.append(
            {
                "upload_id": normalize_text(item.get("upload_id")),
                "name": sanitize_upload_name(item.get("name")),
                "content_type": normalize_text(item.get("content_type")) or "application/octet-stream",
                "size_bytes": size_bytes,
                "original_size_bytes": original_size_bytes,
                "truncated": bool(item.get("truncated")),
                "ingest_status": normalize_text(item.get("ingest_status")) or "metadata_only",
                "excerpt": normalize_text(item.get("excerpt")),
                "uploaded_at": normalize_text(item.get("uploaded_at")),
            }
        )
    return normalized


def merge_uploaded_files(existing: list[dict[str, Any]], new_items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in [*new_items, *existing]:
        key = normalize_text(item.get("upload_id")) or f"{normalize_text(item.get('name'))}:{item.get('original_size_bytes')}"
        if not key or key in seen:
            continue
        seen.add(key)
        merged.append(item)
    return merged


def materialize_uploaded_files(
    payload: dict[str, Any],
    saved_session: dict[str, Any],
    *,
    state_root: Path,
    session_id: str,
    now: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    existing = normalize_uploaded_files(saved_session.get("uploaded_files"))
    raw_uploads = payload.get("uploaded_files")
    if not isinstance(raw_uploads, list) or not raw_uploads:
        return existing, []

    upload_root = upload_session_root(state_root, session_id)
    upload_root.mkdir(parents=True, exist_ok=True)
    materialized: list[dict[str, Any]] = []
    for index, item in enumerate(raw_uploads[:MAX_UPLOADED_FILES], start=1):
        if not isinstance(item, dict):
            continue
        upload_name = sanitize_upload_name(item.get("name"))
        upload_id = normalize_text(item.get("upload_id")) or f"upload-{slugify(upload_name, 'file')}-{index:02d}"
        content_type = normalize_text(item.get("content_type")) or mimetypes.guess_type(upload_name)[0] or "application/octet-stream"
        raw_base64 = normalize_text(item.get("content_base64"))
        raw_bytes = b""
        if raw_base64:
            try:
                raw_bytes = base64.b64decode(raw_base64, validate=True)
            except (ValueError, binascii.Error):
                raw_bytes = b""
        try:
            original_size = int(item.get("original_size_bytes") or item.get("size_bytes") or len(raw_bytes))
        except (TypeError, ValueError):
            original_size = len(raw_bytes)
        truncated = bool(item.get("truncated"))
        if len(raw_bytes) > MAX_UPLOADED_FILE_BYTES:
            raw_bytes = raw_bytes[:MAX_UPLOADED_FILE_BYTES]
            truncated = True
        stored_name = f"{upload_id}{Path(upload_name).suffix.lower()}"
        if raw_bytes:
            (upload_root / stored_name).write_bytes(raw_bytes)
        excerpt, ingest_status = extract_upload_excerpt(raw_bytes, content_type=content_type, upload_name=upload_name)
        materialized.append(
            {
                "upload_id": upload_id,
                "name": upload_name,
                "content_type": content_type,
                "size_bytes": len(raw_bytes) or original_size,
                "original_size_bytes": original_size,
                "truncated": truncated,
                "ingest_status": ingest_status,
                "excerpt": excerpt,
                "uploaded_at": now,
            }
        )
    return merge_uploaded_files(existing, materialized), materialized


def uploaded_files_context(uploaded_files: list[dict[str, Any]]) -> str:
    normalized = normalize_uploaded_files(uploaded_files)
    if not normalized:
        return ""
    parts = [
        "Контекст из прикреплённых файлов:",
        "Важно: данные в прикреплённых файлах считаются синтетически сгенерированными и не имеют ничего общего с реальными; любые совпадения случайны.",
    ]
    for item in normalized:
        header = f"- {normalize_text(item.get('name'))} ({normalize_text(item.get('content_type')) or 'file'})"
        if bool(item.get("truncated")):
            header += ", файл обрезан до безопасного объёма"
        parts.append(header)
        excerpt = normalize_text(item.get("excerpt"))
        if excerpt:
            parts.append(f"  Фрагмент:\n{excerpt}")
        else:
            parts.append("  Содержимое не извлечено автоматически; используй файл как вспомогательный контекст.")
    return "\n".join(parts)


def architect_agent_display_name() -> str:
    return env_text("ASC_DEMO_ARCHITECT_AGENT_LABEL") or ARCHITECT_AGENT_DISPLAY_NAME_DEFAULT


def shorten_text(value: Any, limit: int = 120) -> str:
    text = normalize_text(value)
    if not text:
        return ""
    compact = re.sub(r"\s+", " ", text).strip()
    if len(compact) <= limit:
        return compact
    trimmed = compact[:limit].rsplit(" ", 1)[0].strip()
    return f"{trimmed or compact[:limit]}…"


def is_low_signal_reply(user_text: str, uploaded_files: list[dict[str, Any]] | None = None) -> bool:
    if normalize_uploaded_files(uploaded_files):
        return False
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    if normalized in LOW_SIGNAL_MARKERS:
        return True
    if len(normalized) <= 2:
        return True
    if re.fullmatch(r"[0-9\s.,!?+\-_/\\]+", normalized):
        return True
    words = [word for word in re.split(r"\s+", normalized) if word]
    return len(words) <= 2 and len(normalized) < 20


def has_business_idea_signal(user_text: str) -> bool:
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    return any(token in normalized for token in BUSINESS_IDEA_SIGNALS)


def is_adequate_start_idea(user_text: str, uploaded_files: list[dict[str, Any]] | None = None) -> bool:
    if normalize_uploaded_files(uploaded_files):
        return True
    normalized = normalize_text(user_text)
    if not normalized:
        return False
    if is_low_signal_reply(normalized, uploaded_files):
        return False
    words = [word for word in re.split(r"\s+", normalized) if word]
    if has_business_idea_signal(normalized) and len(words) >= 3:
        return True
    return len(normalized) >= 48 and len(words) >= 6


def is_text_brief_confirmation(user_text: str) -> bool:
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    if any(marker in normalized for marker in CONFIRM_BRIEF_NEGATION_MARKERS):
        return False
    return any(marker in normalized for marker in CONFIRM_BRIEF_TEXT_MARKERS)


def is_likely_brief_correction_text(user_text: str) -> bool:
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    return any(marker in normalized for marker in BRIEF_CORRECTION_TEXT_MARKERS)


def is_production_simulation_request_text(user_text: str) -> bool:
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    return any(marker in normalized for marker in PRODUCTION_SIMULATION_TEXT_MARKERS)


def has_redaction_acknowledgement(user_text: str) -> bool:
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    if any(marker in normalized for marker in REDACTION_NEGATION_MARKERS):
        return False
    return any(marker in normalized for marker in REDACTION_ACK_MARKERS)


def mentions_upload_reference(user_text: str) -> bool:
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    return any(marker in normalized for marker in UPLOAD_REFERENCE_MARKERS)


def looks_like_structured_example_record(user_text: str) -> bool:
    normalized = normalize_text(user_text)
    if not normalized:
        return False
    compact = re.sub(r"\s+", "", normalized)
    if len(compact) < 5 or len(compact) > 180:
        return False
    if not re.search(r"[,;|\t]", compact):
        return False
    return bool(STRUCTURED_EXAMPLE_RECORD_PATTERN.fullmatch(compact))


def has_sensitive_identifiers(user_text: str) -> bool:
    normalized = normalize_text(user_text)
    if not normalized:
        return False
    if SENSITIVE_DIGIT_PATTERN.search(normalized):
        return True
    lowered = normalized.lower()
    return any(
        marker in lowered
        for marker in (
            "инн",
            "кпп",
            "р/с",
            "расчетный счет",
            "расчётный счёт",
            "бик",
            "огрн",
            "паспорт",
            "снилс",
        )
    )


def unsafe_clarification_retry_hint(user_text: str, *, turn_uploaded_files: list[dict[str, Any]] | None = None) -> str:
    if normalize_uploaded_files(turn_uploaded_files):
        return (
            "Похоже, в примере всё ещё есть реальные реквизиты. "
            "Пришли 1 обезличенную строку (например: `<ИНН_КЛИЕНТА>,<РЕЙТИНГ>,<СУММА_СДЕЛКИ>`) "
            "или явно напиши, что реквизиты в файле замаскированы."
        )
    if has_sensitive_identifiers(user_text):
        return (
            "В этом ответе выглядят как реальные реквизиты. "
            "Замени их на маски вида `<ИНН_КЛИЕНТА>`, `<НОМЕР_ДОГОВОРА>`, `<СУММА_СДЕЛКИ>`."
        )
    if is_low_signal_reply(user_text, turn_uploaded_files):
        return "Нужен конкретный обезличенный пример входных данных в 1-2 строках."
    return ""


def is_confirmation_stage(
    *,
    status: str,
    next_action: str,
    current_topic: str,
    next_topic: str,
) -> bool:
    normalized_status = normalize_text(status)
    if normalized_status in {"awaiting_confirmation", "reopened"}:
        return True
    if normalize_text(next_action) in {"request_explicit_confirmation", "await_for_confirmation", "confirm_brief"}:
        return True
    return normalize_text(current_topic) == "brief_confirmation" or normalize_text(next_topic) == "brief_confirmation"


def should_auto_resolve_unsafe_clarification(
    user_text: str,
    *,
    turn_uploaded_files: list[dict[str, Any]] | None = None,
) -> bool:
    normalized = normalize_text(user_text)
    if not normalized:
        return False
    if has_redaction_acknowledgement(normalized):
        return True
    if has_sensitive_identifiers(normalized):
        return False
    if mentions_upload_reference(normalized):
        return True
    if looks_like_structured_example_record(normalized):
        return True
    if has_repeat_ack_marker(normalized):
        return True
    return False


def redact_sensitive_example_summary(value: Any) -> str:
    text = normalize_text(value)
    if not text:
        return "Обезличенный пример входных данных (реквизиты удалены)."
    redacted = SENSITIVE_DIGIT_PATTERN.sub("<скрыто>", text)
    return redacted or "Обезличенный пример входных данных (реквизиты удалены)."


def has_open_unsafe_input_clarification(discovery_request: dict[str, Any]) -> bool:
    clarification_items = discovery_request.get("clarification_items")
    if not isinstance(clarification_items, list):
        return False
    for item in clarification_items:
        if not isinstance(item, dict):
            continue
        if normalize_text(item.get("topic_name")) != "input_examples":
            continue
        if normalize_text(item.get("reason")) != "unsafe_data_example":
            continue
        if normalize_text(item.get("status")) == "open":
            return True
    return False


def resolve_unsafe_input_clarification(discovery_request: dict[str, Any], *, user_text: str, now: str) -> None:
    safe_input_example = (
        normalize_text(user_text) or "Пользователь подтвердил, что входные примеры обезличены."
    )

    clarification_items = discovery_request.get("clarification_items")
    if isinstance(clarification_items, list):
        for item in clarification_items:
            if not isinstance(item, dict):
                continue
            if normalize_text(item.get("topic_name")) != "input_examples":
                continue
            if normalize_text(item.get("reason")) != "unsafe_data_example":
                continue
            if normalize_text(item.get("status")) != "open":
                continue
            item["status"] = "resolved"
            item["resolved_at"] = now

    example_cases = discovery_request.get("example_cases")
    if isinstance(example_cases, list):
        for case in example_cases:
            if not isinstance(case, dict):
                continue
            case["input_summary"] = redact_sensitive_example_summary(case.get("input_summary"))
            case["data_safety_status"] = "safe"

    captured_answers = discovery_request.get("captured_answers")
    if not isinstance(captured_answers, dict):
        captured_answers = {}
    captured_answers["input_examples"] = safe_input_example
    discovery_request["captured_answers"] = captured_answers

    discovery_answers = discovery_request.get("discovery_answers")
    if not isinstance(discovery_answers, dict):
        discovery_answers = {}
    discovery_answers["input_examples"] = safe_input_example
    discovery_request["discovery_answers"] = discovery_answers

    normalized_answers = discovery_request.get("normalized_answers")
    if not isinstance(normalized_answers, dict):
        normalized_answers = {}
    normalized_answers["input_examples"] = safe_input_example
    discovery_request["normalized_answers"] = normalized_answers

    brief_section_updates = discovery_request.get("brief_section_updates")
    if not isinstance(brief_section_updates, dict):
        brief_section_updates = {}
    brief_section_updates["input_examples"] = [safe_input_example]
    discovery_request["brief_section_updates"] = brief_section_updates

    requirement_brief = discovery_request.get("requirement_brief")
    if isinstance(requirement_brief, dict):
        requirement_brief["input_examples"] = [safe_input_example]
        discovery_request["requirement_brief"] = requirement_brief

    discovery_request.pop("_web_clarification_retry_hint", None)


def hydrate_runtime_input_examples_answer(runtime_state: dict[str, Any], discovery_request: dict[str, Any]) -> None:
    captured_from_request = discovery_request.get("captured_answers")
    if not isinstance(captured_from_request, dict):
        return
    input_examples_answer = normalize_text(captured_from_request.get("input_examples"))
    if not input_examples_answer:
        return

    captured_answers = runtime_state.get("captured_answers")
    if not isinstance(captured_answers, dict):
        captured_answers = {}
    if not normalize_text(captured_answers.get("input_examples")):
        captured_answers["input_examples"] = input_examples_answer
    runtime_state["captured_answers"] = captured_answers

    normalized_answers = runtime_state.get("normalized_answers")
    if not isinstance(normalized_answers, dict):
        normalized_answers = {}
    if not normalize_text(normalized_answers.get("input_examples")):
        normalized_answers["input_examples"] = input_examples_answer
    runtime_state["normalized_answers"] = normalized_answers


def requirement_topic_summaries(runtime_state: dict[str, Any]) -> dict[str, str]:
    summaries: dict[str, str] = {}
    topics = runtime_state.get("requirement_topics")
    if not isinstance(topics, list):
        return summaries
    for item in topics:
        if not isinstance(item, dict):
            continue
        topic_name = normalize_text(item.get("topic_name"))
        summary = normalize_text(item.get("summary"))
        if topic_name and summary:
            summaries[topic_name] = summary
    return summaries


def context_hint_for_topic(
    next_topic: str,
    topic_summaries: dict[str, str],
    uploaded_files: list[dict[str, Any]],
) -> str:
    problem = topic_summaries.get("problem", "")
    target_users = topic_summaries.get("target_users", "")
    current_workflow = topic_summaries.get("current_workflow", "")
    desired_outcome = topic_summaries.get("desired_outcome", "")
    normalized_uploads = normalize_uploaded_files(uploaded_files)
    upload_names = [normalize_text(item.get("name")) for item in normalized_uploads if normalize_text(item.get("name"))]

    if next_topic == "target_users" and problem:
        return "Проблему зафиксировал."
    if next_topic == "current_workflow" and target_users:
        return "Пользователей и выгодоприобретателей зафиксировал."
    if next_topic == "desired_outcome" and current_workflow:
        return "Текущий процесс зафиксировал."
    if next_topic == "user_story":
        if desired_outcome:
            return "Бизнес-эффект зафиксировал."
        if target_users:
            return "Роли пользователей зафиксировал."
    if next_topic == "input_examples" and upload_names:
        listed = ", ".join(upload_names[:2])
        suffix = " и ещё файлы" if len(upload_names) > 2 else ""
        return f"Вижу приложенные файлы: {listed}{suffix}."
    if next_topic == "expected_outputs" and upload_names and not desired_outcome:
        listed = ", ".join(upload_names[:2])
        suffix = " и ещё файлы" if len(upload_names) > 2 else ""
        return f"Входные примеры уже приложены файлами: {listed}{suffix}."
    if next_topic == "expected_outputs" and desired_outcome:
        return "Уточним финальный формат результата для пользователя."
    if next_topic == "constraints" and desired_outcome:
        return "Чтобы решение было безопасным и выполнимым, уточним ограничения."
    if next_topic == "success_metrics" and desired_outcome:
        return "Осталось зафиксировать измеримые критерии успеха для запуска в фабрику."
    return ""


def next_architect_topic(current_topic: str) -> str:
    topic = normalize_text(current_topic)
    if not topic:
        return ""
    ordered_topics = list(ARCHITECT_TOPIC_FRAMES.keys())
    try:
        index = ordered_topics.index(topic)
    except ValueError:
        return ""
    if index + 1 >= len(ordered_topics):
        return ""
    return ordered_topics[index + 1]


def next_uncovered_topic_after(runtime_state: dict[str, Any], topic_name: str) -> str:
    topic = normalize_text(topic_name)
    if topic not in ARCHITECT_TOPIC_ORDER:
        return ""
    summaries = requirement_topic_summaries(runtime_state)
    start_index = ARCHITECT_TOPIC_ORDER.index(topic)
    for candidate in ARCHITECT_TOPIC_ORDER[start_index + 1:]:
        if not normalize_text(summaries.get(candidate)):
            return candidate
    return ""


def topic_position(topic_name: str) -> int:
    topic = normalize_text(topic_name)
    if not topic:
        return -1
    try:
        return ARCHITECT_TOPIC_ORDER.index(topic)
    except ValueError:
        return -1


def sanitize_architect_question_text(value: Any) -> str:
    text = normalize_text(value)
    if not text:
        return ""
    text = re.sub(r"(?im)^\s*следующий\s+вопрос\s*[:\-]*\s*", "", text).strip()
    lines: list[str] = []
    for line in text.splitlines():
        compact = normalize_text(line)
        if not compact:
            if lines and lines[-1] != "":
                lines.append("")
            continue
        if re.match(r"(?i)^например[:\s]", compact):
            continue
        if re.match(r"(?i)^(бизнес-эффект|проблему|роли|пользователей|текущий процесс|ожидаемый выход|ограничения|метрики)\s+.*зафикс", compact):
            continue
        lines.append(compact)
    while lines and lines[0] == "":
        lines.pop(0)
    while lines and lines[-1] == "":
        lines.pop()
    cleaned = "\n".join(lines).strip()
    if not cleaned:
        return ""
    if "?" in cleaned:
        segments = [segment.strip() for segment in re.split(r"(?<=[.?!])\s+", cleaned) if normalize_text(segment)]
        for segment in reversed(segments):
            if "?" in segment:
                return segment
    return cleaned


def llm_upload_context(uploaded_files: list[dict[str, Any]]) -> list[dict[str, str]]:
    context: list[dict[str, str]] = []
    for item in normalize_uploaded_files(uploaded_files):
        name = normalize_text(item.get("name"))
        excerpt = shorten_text(item.get("excerpt"), 220)
        if not name and not excerpt:
            continue
        context.append(
            {
                "name": name,
                "excerpt": excerpt,
            }
        )
    return context[:3]


def llm_topic_summary_context(runtime_state: dict[str, Any]) -> dict[str, str]:
    summaries = requirement_topic_summaries(runtime_state)
    normalized: dict[str, str] = {}
    for key, value in summaries.items():
        compact = shorten_text(value, 180)
        if compact:
            normalized[key] = compact
    return normalized


def llm_adaptive_architect_question(
    *,
    current_topic: str,
    runtime_next_topic: str,
    runtime_next_question: str,
    runtime_state: dict[str, Any],
    envelope: dict[str, Any],
    uploaded_files: list[dict[str, Any]],
) -> tuple[str, str, str]:
    settings = llm_settings_from_env()
    if not settings.enabled:
        return "", "", "llm_disabled"
    if not settings.configured:
        return "", "", "llm_not_configured"

    topic_now = normalize_text(current_topic) or normalize_text(runtime_next_topic)
    if not topic_now:
        return "", "", "llm_no_topic"
    expected_next = normalize_text(runtime_next_topic) or topic_now
    user_text = normalize_text(envelope.get("user_text"))
    if not user_text and not normalize_uploaded_files(uploaded_files):
        return "", "", "llm_no_user_input"

    prompt_payload = {
        "allowed_topics": ARCHITECT_TOPIC_ORDER,
        "current_topic": topic_now,
        "runtime_next_topic": expected_next,
        "runtime_next_question": sanitize_architect_question_text(runtime_next_question),
        "next_topic_by_order": normalize_text(next_architect_topic(topic_now)),
        "repeat_marker_detected": has_repeat_ack_marker(user_text),
        "low_signal_heuristic": is_low_signal_reply(user_text, uploaded_files),
        "user_reply": user_text,
        "topic_summaries": llm_topic_summary_context(runtime_state),
        "uploaded_files": llm_upload_context(uploaded_files),
    }
    user_prompt = (
        "Сформируй решение по следующему ходу discovery.\n"
        f"{json.dumps(prompt_payload, ensure_ascii=False, indent=2)}"
    )
    try:
        decision_data = chat_completion_json(
            system_prompt=LLM_DECISION_PROMPT,
            user_prompt=user_prompt,
            settings=settings,
        )
    except LLMError:
        return "", "", "llm_error"

    decision = normalize_text(decision_data.get("decision")).lower()
    if decision not in {"accept", "clarify", "rephrase", "advance"}:
        decision = "accept"
    returned_topic = normalize_text(decision_data.get("next_topic"))
    returned_question = sanitize_architect_question_text(decision_data.get("next_question"))
    returned_low_signal = bool(decision_data.get("low_signal"))
    summary = normalize_text(decision_data.get("topic_summary"))
    if re.search(r"example-case-\d+", returned_question, re.IGNORECASE) and not re.search(
        r"example-case-\d+",
        user_text,
        re.IGNORECASE,
    ):
        returned_question = ""

    current_pos = topic_position(topic_now)
    expected_pos = topic_position(expected_next)
    next_by_order = normalize_text(next_architect_topic(topic_now))
    allowed_transition = {
        topic_now,
        expected_next,
        next_by_order,
    }
    allowed_transition = {topic for topic in allowed_transition if topic}

    if decision in {"clarify", "rephrase"} or returned_low_signal:
        target_topic = topic_now
    elif decision == "advance":
        target_topic = returned_topic or next_by_order or expected_next
    else:
        target_topic = returned_topic or expected_next

    if target_topic not in ARCHITECT_TOPIC_FRAMES:
        target_topic = expected_next or topic_now
    if target_topic not in allowed_transition:
        target_topic = expected_next or topic_now

    if current_pos >= 0 and expected_pos >= 0 and expected_pos < current_pos:
        target_topic = topic_now

    canonical_question = normalize_text(ARCHITECT_TOPIC_FRAMES.get(target_topic, {}).get("question")) or sanitize_architect_question_text(
        runtime_next_question
    )
    if decision in {"clarify", "rephrase"} or returned_low_signal:
        target_question = returned_question or canonical_question
    else:
        target_question = canonical_question
    if not target_question:
        return "", "", "llm_empty_question"

    if summary and decision in {"accept", "advance"} and not returned_low_signal:
        topic_ack = {
            "problem": "Проблему зафиксировал.",
            "target_users": "Пользователей и выгодоприобретателей зафиксировал.",
            "current_workflow": "Текущий процесс зафиксировал.",
            "desired_outcome": "Бизнес-эффект зафиксировал.",
            "user_story": "Приоритетный сценарий зафиксировал.",
            "input_examples": "Входные примеры зафиксировал.",
            "expected_outputs": "Ожидаемый выход зафиксировал.",
            "constraints": "Ограничения зафиксировал.",
            "success_metrics": "Метрики успеха зафиксировал.",
        }.get(topic_now, "Ответ зафиксировал.")
        target_question = f"{topic_ack}\n\n{target_question}"

    source = f"llm_{decision}"
    if returned_low_signal:
        source = "llm_low_signal"
    return target_question, target_topic, source


def has_repeat_ack_marker(user_text: str) -> bool:
    normalized = normalize_text(user_text).lower()
    if not normalized:
        return False
    return any(marker in normalized for marker in REPEAT_ACK_MARKERS)


def upsert_topic_summary(runtime_state: dict[str, Any], *, topic_name: str, summary: str, now: str) -> None:
    topic = normalize_text(topic_name)
    summary_text = normalize_text(summary)
    if not topic or not summary_text or not isinstance(runtime_state, dict):
        return

    captured_answers = runtime_state.get("captured_answers")
    if not isinstance(captured_answers, dict):
        captured_answers = {}
    captured_answers[topic] = summary_text
    runtime_state["captured_answers"] = captured_answers

    requirement_topics = runtime_state.get("requirement_topics")
    if not isinstance(requirement_topics, list):
        requirement_topics = []
    updated = False
    for item in requirement_topics:
        if not isinstance(item, dict):
            continue
        if normalize_text(item.get("topic_name")) != topic:
            continue
        item["summary"] = summary_text
        item["status"] = "clarified"
        item["last_updated_at"] = now
        updated = True
        break
    if not updated:
        requirement_topics.append(
            {
                "topic_id": f"topic-{topic}-bridge",
                "topic_name": topic,
                "category": "functional",
                "status": "clarified",
                "summary": summary_text,
                "source_turn_ids": [],
                "last_updated_at": now,
            }
        )
    runtime_state["requirement_topics"] = requirement_topics


def bridge_repeat_answer(
    runtime_state: dict[str, Any],
    *,
    next_topic: str,
    next_question: str,
    envelope: dict[str, Any],
    now: str,
) -> tuple[str, str, bool, bool, str]:
    topic = normalize_text(next_topic)
    if not topic:
        return next_topic, next_question, False, False, "runtime"
    if not has_repeat_ack_marker(normalize_text(envelope.get("user_text"))):
        return next_topic, next_question, False, False, "runtime"

    summaries = requirement_topic_summaries(runtime_state)
    topic_summary = normalize_text(summaries.get(topic))
    if not topic_summary:
        if topic == "expected_outputs":
            business_effect = normalize_text(summaries.get("desired_outcome"))
            if business_effect:
                rephrased = (
                    f"Понял. Зафиксировал целевой эффект: {shorten_text(business_effect, 90)}.\n\n"
                    "Уточни именно формат выхода для пользователя: какой конкретный файл, материал или экран агент должен выдавать после обработки?"
                )
                return topic, rephrased, True, True, "repeat_marker_rephrase"
            rephrased = (
                "Понял, что ты уже отвечал. Уточню формулировку: "
                "какой конкретный артефакт должен получить пользователь на выходе "
                "(например, PDF, one-page summary, карточка клиента или письмо-рекомендация)?"
            )
            return topic, rephrased, True, True, "repeat_marker_rephrase"
        rephrased = (
            "Понял, что ты уже давал ответ. Сформулирую проще: "
            f"{normalize_text(ARCHITECT_TOPIC_FRAMES.get(topic, {}).get('question')) or normalize_text(next_question)}"
        )
        return topic, rephrased, True, True, "repeat_marker_rephrase"

    upsert_topic_summary(runtime_state, topic_name=topic, summary=topic_summary, now=now)
    bridged_topic = normalize_text(next_architect_topic(topic))
    if not bridged_topic:
        return topic, next_question, False, False, "runtime"
    bridged_question = normalize_text(ARCHITECT_TOPIC_FRAMES.get(bridged_topic, {}).get("question")) or normalize_text(next_question)
    return bridged_topic, bridged_question, True, False, "repeat_marker_bridge"


def adaptive_architect_question(
    *,
    next_question: str,
    next_topic: str,
    runtime_state: dict[str, Any],
    envelope: dict[str, Any],
    uploaded_files: list[dict[str, Any]],
    force_low_signal_guard: bool = False,
) -> tuple[str, str]:
    topic = normalize_text(next_topic)
    frame = ARCHITECT_TOPIC_FRAMES.get(topic, {})
    base_question = normalize_text(frame.get("question")) or normalize_text(next_question)
    if not base_question:
        base_question = "Опиши, пожалуйста, подробнее рабочий контекст, чтобы я корректно зафиксировал требования."
    lead = normalize_text(frame.get("lead"))
    user_text = normalize_text(envelope.get("user_text"))
    low_signal = force_low_signal_guard or is_low_signal_reply(user_text, uploaded_files)
    if low_signal:
        reprompt = (
            "Описание предмета автоматизации пока слишком общее, его нельзя зафиксировать в brief."
            if topic == "problem"
            else "Ответ пока слишком общий, из него нельзя зафиксировать требование в brief."
        )
        question = "\n\n".join((reprompt, base_question))
        return question, "low_signal_guard"

    summaries = requirement_topic_summaries(runtime_state)
    context_hint = context_hint_for_topic(topic, summaries, uploaded_files)
    intro = normalize_text(context_hint) or lead
    parts = [part for part in (intro, base_question) if normalize_text(part)]
    question = "\n\n".join(parts)
    return question, "adaptive_architect"


def patch_runtime_next_question(
    runtime_state: dict[str, Any],
    *,
    next_question: str,
    next_topic: str,
    next_action: str = "",
) -> None:
    if not isinstance(runtime_state, dict):
        return
    question = normalize_text(next_question)
    topic = normalize_text(next_topic)
    action = normalize_text(next_action)
    if question:
        runtime_state["next_question"] = question
    if topic:
        runtime_state["next_topic"] = topic
    if action:
        runtime_state["next_action"] = action

    discovery_session = runtime_state.get("discovery_session")
    if not isinstance(discovery_session, dict):
        discovery_session = {}
    if topic:
        discovery_session["current_topic"] = topic
    if action:
        discovery_session["next_recommended_action"] = action
    runtime_state["discovery_session"] = discovery_session

    if not question:
        return
    open_questions = runtime_state.get("open_questions")
    if isinstance(open_questions, list):
        runtime_state["open_questions"] = [question]
    turns = runtime_state.get("conversation_turns")
    if not isinstance(turns, list):
        return
    for turn in reversed(turns):
        if not isinstance(turn, dict):
            continue
        if normalize_text(turn.get("actor")) != "agent":
            continue
        if normalize_text(turn.get("turn_type")) != "clarifying_question":
            continue
        turn["raw_text"] = question
        if topic:
            turn["extracted_topics"] = [topic]
        break


def normalize_requester_identity(payload: dict[str, Any], discovery_state: dict[str, Any]) -> dict[str, Any]:
    requester_identity = payload.get("requester_identity", {})
    if isinstance(requester_identity, dict) and requester_identity:
        result = dict(requester_identity)
    else:
        result = {}

    state_identity = discovery_state.get("requester_identity", {})
    if isinstance(state_identity, dict):
        for key, value in state_identity.items():
            result.setdefault(key, value)

    discovery_session = discovery_state.get("discovery_session", {})
    if isinstance(discovery_session, dict):
        session_identity = discovery_session.get("requester_identity", {})
        if isinstance(session_identity, dict):
            for key, value in session_identity.items():
                result.setdefault(key, value)

    display_name = normalize_text(result.get("display_name")) or "Demo user"
    browser_session_label = normalize_text(result.get("browser_session_label")) or slugify(display_name, "browser")
    result["display_name"] = display_name
    result["browser_session_label"] = browser_session_label
    return result


def normalize_web_conversation_envelope(payload: dict[str, Any], discovery_state: dict[str, Any], now: str) -> dict[str, Any]:
    envelope = payload.get("web_conversation_envelope", {})
    envelope = dict(envelope) if isinstance(envelope, dict) else {}
    raw_idea = normalize_text(payload.get("raw_idea"))
    user_text = normalize_text(envelope.get("user_text")) or raw_idea or normalize_text(payload.get("user_text"))

    ui_action = normalize_text(envelope.get("ui_action"))
    if not ui_action:
        ui_action = "submit_turn" if discovery_state else "start_project"

    request_slug_source = f"{ui_action}-{user_text or now}"
    request_id = normalize_text(envelope.get("request_id")) or f"request-{slugify(request_slug_source, 'web')}"
    return {
        "web_conversation_envelope_id": normalize_text(envelope.get("web_conversation_envelope_id"))
        or f"web-envelope-{slugify(request_id, 'envelope')}",
        "request_id": request_id,
        "transport_mode": normalize_text(envelope.get("transport_mode")) or "synthetic_fixture",
        "ui_action": ui_action,
        "user_text": user_text,
        "normalized_payload": {},
        "linked_discovery_session_id": normalize_text(envelope.get("linked_discovery_session_id")),
        "linked_brief_id": normalize_text(envelope.get("linked_brief_id")),
        "received_at": normalize_text(envelope.get("received_at")) or now,
    }


def normalize_web_demo_session(
    payload: dict[str, Any],
    saved_session: dict[str, Any],
    discovery_state: dict[str, Any],
    requester_identity: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    session = payload.get("web_demo_session", {})
    if not isinstance(session, dict):
        session = {}
    saved = saved_session.get("web_demo_session", {}) if isinstance(saved_session.get("web_demo_session"), dict) else {}
    discovery_session = discovery_state.get("discovery_session", {}) if isinstance(discovery_state.get("discovery_session"), dict) else {}

    project_key = (
        normalize_text(session.get("active_project_key"))
        or normalize_text(saved.get("active_project_key"))
        or normalize_text(payload.get("project_key"))
        or normalize_text(discovery_session.get("project_key"))
    )
    session_id = (
        normalize_text(session.get("web_demo_session_id"))
        or normalize_text(saved.get("web_demo_session_id"))
        or f"web-demo-session-{project_key or slugify(requester_identity.get('display_name'), 'session')}"
    )

    return {
        "web_demo_session_id": session_id,
        "session_cookie_id": normalize_text(session.get("session_cookie_id"))
        or normalize_text(saved.get("session_cookie_id"))
        or f"cookie-{slugify(session_id, 'cookie')}",
        "access_grant_id": normalize_text(session.get("access_grant_id")) or normalize_text(saved.get("access_grant_id")),
        "status": normalize_text(session.get("status")) or normalize_text(saved.get("status")) or "gate_pending",
        "active_project_key": project_key,
        "active_discovery_session_id": normalize_text(session.get("active_discovery_session_id"))
        or normalize_text(saved.get("active_discovery_session_id"))
        or normalize_text(discovery_session.get("discovery_session_id")),
        "active_brief_id": normalize_text(session.get("active_brief_id")) or normalize_text(saved.get("active_brief_id")),
        "last_user_turn_at": normalize_text(session.get("last_user_turn_at")) or normalize_text(saved.get("last_user_turn_at")),
        "last_agent_turn_at": normalize_text(session.get("last_agent_turn_at")) or normalize_text(saved.get("last_agent_turn_at")),
        "created_at": normalize_text(session.get("created_at")) or normalize_text(saved.get("created_at")) or now,
        "updated_at": now,
    }


def normalize_project_pointer(
    payload: dict[str, Any],
    saved_session: dict[str, Any],
    discovery_state: dict[str, Any],
    web_demo_session: dict[str, Any],
    envelope: dict[str, Any],
    now: str,
) -> dict[str, Any]:
    pointer = payload.get("browser_project_pointer", {})
    if not isinstance(pointer, dict):
        pointer = {}
    saved = (
        saved_session.get("browser_project_pointer", {})
        if isinstance(saved_session.get("browser_project_pointer"), dict)
        else {}
    )
    discovery_session = discovery_state.get("discovery_session", {}) if isinstance(discovery_state.get("discovery_session"), dict) else {}
    brief = discovery_state.get("requirement_brief", {}) if isinstance(discovery_state.get("requirement_brief"), dict) else {}

    selection_mode_map = {
        "start_project": "new_project",
        "submit_turn": "continue_active",
        "request_brief_review": "review_brief",
        "request_brief_correction": "review_brief",
        "confirm_brief": "review_brief",
        "reopen_brief": "reopen_brief",
        "request_status": "status_only",
        "download_artifact": "download_ready",
    }
    selection_mode = normalize_text(pointer.get("selection_mode")) or selection_mode_map.get(
        normalize_text(envelope.get("ui_action")),
        "continue_active",
    )
    project_key = (
        normalize_text(pointer.get("project_key"))
        or normalize_text(saved.get("project_key"))
        or normalize_text(web_demo_session.get("active_project_key"))
        or normalize_text(discovery_session.get("project_key"))
    )
    return {
        "pointer_id": normalize_text(pointer.get("pointer_id")) or normalize_text(saved.get("pointer_id"))
        or f"browser-pointer-{project_key or slugify(web_demo_session.get('web_demo_session_id'), 'pointer')}",
        "web_demo_session_id": normalize_text(web_demo_session.get("web_demo_session_id")),
        "project_key": project_key,
        "selection_mode": selection_mode,
        "linked_discovery_session_id": normalize_text(pointer.get("linked_discovery_session_id"))
        or normalize_text(saved.get("linked_discovery_session_id"))
        or normalize_text(discovery_session.get("discovery_session_id")),
        "linked_brief_id": normalize_text(pointer.get("linked_brief_id"))
        or normalize_text(saved.get("linked_brief_id"))
        or normalize_text(brief.get("brief_id")),
        "linked_brief_version": normalize_text(pointer.get("linked_brief_version"))
        or normalize_text(saved.get("linked_brief_version"))
        or normalize_text(brief.get("version")),
        "pointer_status": normalize_text(pointer.get("pointer_status")) or normalize_text(saved.get("pointer_status")) or "active",
        "updated_at": now,
    }


def normalize_history_entries(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    return [dict(item) for item in value if isinstance(item, dict)]


def latest_confirmed_brief_version(runtime_state: dict[str, Any]) -> str:
    confirmation_snapshot = (
        runtime_state.get("confirmation_snapshot", {})
        if isinstance(runtime_state.get("confirmation_snapshot"), dict)
        else {}
    )
    version = normalize_text(confirmation_snapshot.get("brief_version"))
    if version:
        return version
    for entry in reversed(normalize_history_entries(runtime_state.get("confirmation_history"))):
        version = normalize_text(entry.get("brief_version"))
        if version:
            return version
    return ""


def normalize_access_grant(payload: dict[str, Any], web_demo_session: dict[str, Any], now: str) -> dict[str, Any]:
    grant = payload.get("demo_access_grant", payload.get("access_grant", {}))
    grant = dict(grant) if isinstance(grant, dict) else {}
    grant_value = normalize_text(grant.get("grant_value"))
    grant_hash = normalize_text(grant.get("grant_value_hash")) or sha256_hex(grant_value)
    return {
        "demo_access_grant_id": normalize_text(grant.get("demo_access_grant_id"))
        or normalize_text(grant.get("access_grant_id"))
        or f"access-{slugify(web_demo_session.get('web_demo_session_id'), 'grant')}",
        "grant_type": normalize_text(grant.get("grant_type")) or "shared_demo_token",
        "grant_value_hash": grant_hash,
        "grant_value": grant_value,
        "issued_by": normalize_text(grant.get("issued_by")) or "operator",
        "issued_for": normalize_text(grant.get("issued_for")) or normalize_text(web_demo_session.get("session_cookie_id")),
        "status": normalize_text(grant.get("status")) or "active",
        "expires_at": normalize_text(grant.get("expires_at")),
        "created_at": normalize_text(grant.get("created_at")) or now,
    }


def access_gate_result(payload: dict[str, Any], discovery_state: dict[str, Any], web_demo_session: dict[str, Any], now: str) -> tuple[bool, dict[str, Any], str]:
    grant = normalize_access_grant(payload, web_demo_session, now)
    settings = access_gate_settings()
    resume_ready = bool(discovery_state) and normalize_text(web_demo_session.get("web_demo_session_id"))
    granted = False
    message = ""
    provided_hash = normalize_text(grant.get("grant_value_hash"))
    expected_hash = normalize_text(settings.get("shared_token_hash"))

    if resume_ready and normalize_text(web_demo_session.get("status")) not in {"gate_pending", "error"}:
        granted = True
        if not normalize_text(grant.get("grant_type")):
            grant["grant_type"] = "allowlisted_session"
        if not normalize_text(grant.get("status")):
            grant["status"] = "active"
    else:
        access_gate_mode = normalize_text(settings.get("access_gate_mode"))
        if access_gate_mode == "shared_token_hash":
            if not settings.get("access_gate_configured"):
                message = "Демо-доступ ещё не подготовлен оператором. Нужен настроенный shared access token для subdomain demo."
            elif normalize_text(grant.get("status")) == "active" and provided_hash and provided_hash == expected_hash:
                granted = True
            else:
                message = "Этот demo access token не подходит. Проверь токен или запроси актуальный доступ у оператора."
        elif normalize_text(grant.get("status")) == "active" and (
            normalize_text(grant.get("grant_value")) or normalize_text(grant.get("grant_value_hash"))
        ):
            granted = True
        else:
            message = "Укажи активный demo access token, чтобы открыть рабочую сессию фабрики."

    grant["granted"] = granted
    grant["access_gate_mode"] = normalize_text(settings.get("access_gate_mode"))
    grant["access_gate_configured"] = bool(settings.get("access_gate_configured"))
    grant["public_base_url"] = normalize_text(settings.get("public_base_url"))
    grant["demo_domain"] = normalize_text(settings.get("demo_domain"))
    grant["grant_value"] = ""
    return granted, grant, message


def build_confirmation_reply(user_text: str, requester_identity: dict[str, Any]) -> dict[str, Any]:
    return {
        "confirmed": True,
        "confirmation_text": user_text or "Да, brief подтвержден.",
        "confirmed_by": normalize_text(requester_identity.get("display_name"))
        or normalize_text(requester_identity.get("browser_session_label"))
        or "web-demo-user",
    }


def seed_discovery_request(payload: dict[str, Any], discovery_state: dict[str, Any], requester_identity: dict[str, Any]) -> dict[str, Any]:
    seeded = copy_discovery_state(discovery_state or payload)
    seeded["request_channel"] = "web"
    seeded["requester_identity"] = requester_identity
    seeded["working_language"] = normalize_text(payload.get("working_language")) or normalize_text(
        seeded.get("working_language")
    ) or "ru"
    if normalize_text(payload.get("project_key")):
        seeded["project_key"] = normalize_text(payload.get("project_key"))
    return seeded


def append_user_turn(discovery_request: dict[str, Any], user_text: str, topic_name: str, now: str) -> None:
    if not user_text:
        return
    turns = discovery_request.get("conversation_turns", [])
    if not isinstance(turns, list):
        turns = []
    turns = [dict(turn) for turn in turns if isinstance(turn, dict)]
    turns.append(
        {
            "turn_id": f"browser-turn-{len(turns) + 1:03d}",
            "actor": "user",
            "turn_type": "browser_reply",
            "raw_text": user_text,
            "extracted_topics": [topic_name] if topic_name else [],
            "linked_clarification_ids": [],
            "recorded_at": now,
        }
    )
    discovery_request["conversation_turns"] = turns


def infer_brief_section_updates_from_feedback(feedback_text: str) -> dict[str, Any]:
    text = normalize_text(feedback_text)
    lowered = text.lower()
    if not text:
        return {}
    if any(marker in lowered for marker in ("огранич", "запрет", "исключ", "compliance", "policy")):
        return {"constraints": [text]}
    if any(marker in lowered for marker in ("метрик", "kpi", "sla", "критери")):
        return {"success_metrics": [text]}
    if any(marker in lowered for marker in ("пользоват", "роль", "выгодоприобрет")):
        return {"target_users": [text]}
    if any(marker in lowered for marker in ("процесс", "workflow", "как сейчас", "current process")):
        return {"current_process": text}
    if any(marker in lowered for marker in ("выход", "результат", "pdf", "one-page", "onepage", "презентац")):
        return {"expected_outputs": [text]}
    return {"scope_boundaries": [text]}


def build_discovery_request(
    payload: dict[str, Any],
    discovery_state: dict[str, Any],
    requester_identity: dict[str, Any],
    envelope: dict[str, Any],
    web_demo_session: dict[str, Any],
    pointer: dict[str, Any],
    uploaded_files: list[dict[str, Any]],
    turn_uploaded_files: list[dict[str, Any]],
    now: str,
) -> tuple[dict[str, Any], bool, bool]:
    ui_action = normalize_text(envelope.get("ui_action"))
    user_text = normalize_text(envelope.get("user_text"))
    attachment_context = uploaded_files_context(turn_uploaded_files)
    combined_text = "\n\n".join(part for part in (user_text, attachment_context) if part)
    request = seed_discovery_request(payload, discovery_state, requester_identity)
    current_topic = normalize_text(
        request.get("discovery_session", {}).get("current_topic")
        if isinstance(request.get("discovery_session"), dict)
        else ""
    ) or normalize_text(request.get("next_topic"))
    current_next_action = normalize_text(request.get("next_action"))
    runtime_next_topic = normalize_text(request.get("next_topic"))
    request["project_key"] = normalize_text(pointer.get("project_key")) or normalize_text(web_demo_session.get("active_project_key"))
    low_signal_submission = False
    current_status = normalize_text(request.get("status"))
    if ui_action not in VALID_WEB_UI_ACTIONS:
        ui_action = "request_status" if current_status in {"confirmed", "download_ready"} else "submit_turn"

    if ui_action == "request_status" and discovery_state:
        in_confirmation = is_confirmation_stage(
            status=current_status,
            next_action=current_next_action,
            current_topic=current_topic,
            next_topic=runtime_next_topic,
        )
        in_download_ready = current_status in {"confirmed", "download_ready"}
        if combined_text and (in_confirmation or in_download_ready):
            if in_confirmation and is_text_brief_confirmation(combined_text):
                request["confirmation_reply"] = build_confirmation_reply(combined_text, requester_identity)
                append_user_turn(request, combined_text, "brief_confirmation", now)
                return request, False, low_signal_submission
            if is_likely_brief_correction_text(combined_text):
                request["brief_feedback_text"] = combined_text
                inferred_updates = infer_brief_section_updates_from_feedback(combined_text)
                if inferred_updates:
                    request["brief_section_updates"] = inferred_updates
                append_user_turn(request, combined_text, "brief_feedback", now)
                return request, False, low_signal_submission
        return request, True, low_signal_submission

    if ui_action in {"request_brief_review"} and discovery_state:
        return request, True, low_signal_submission

    if ui_action == "submit_turn" and discovery_state and current_status in {"confirmed", "download_ready"}:
        if combined_text and is_likely_brief_correction_text(combined_text):
            request["brief_feedback_text"] = combined_text
            inferred_updates = infer_brief_section_updates_from_feedback(combined_text)
            if inferred_updates:
                request["brief_section_updates"] = inferred_updates
            append_user_turn(request, combined_text, "brief_feedback", now)
            return request, False, low_signal_submission
        return request, True, low_signal_submission

    if ui_action == "start_project":
        low_signal_submission = not is_adequate_start_idea(combined_text, turn_uploaded_files)
        if not low_signal_submission:
            request["raw_idea"] = combined_text or normalize_text(payload.get("raw_idea"))
    elif ui_action == "submit_turn":
        if is_confirmation_stage(
            status=current_status,
            next_action=current_next_action,
            current_topic=current_topic,
            next_topic=runtime_next_topic,
        ) and is_text_brief_confirmation(combined_text):
            request["confirmation_reply"] = build_confirmation_reply(combined_text, requester_identity)
            append_user_turn(request, combined_text, "brief_confirmation", now)
            return request, False, low_signal_submission

        unsafe_clarification_open = has_open_unsafe_input_clarification(request)
        if unsafe_clarification_open:
            append_user_turn(request, combined_text, current_topic or "input_examples", now)
            if should_auto_resolve_unsafe_clarification(combined_text, turn_uploaded_files=turn_uploaded_files):
                resolve_unsafe_input_clarification(request, user_text=combined_text, now=now)
            else:
                request["_web_clarification_retry_hint"] = unsafe_clarification_retry_hint(
                    combined_text,
                    turn_uploaded_files=turn_uploaded_files,
                )
            return request, False, low_signal_submission

        repeat_ack_submission = has_repeat_ack_marker(combined_text)
        low_signal_submission = False if repeat_ack_submission else is_low_signal_reply(combined_text, turn_uploaded_files)
        captured_answers = request.get("captured_answers", {})
        if not isinstance(captured_answers, dict):
            captured_answers = {}
        if current_topic and combined_text and not low_signal_submission and not repeat_ack_submission:
            captured_answers[current_topic] = combined_text
        elif combined_text and not normalize_text(request.get("raw_idea")) and not low_signal_submission and not repeat_ack_submission:
            request["raw_idea"] = combined_text
        request["captured_answers"] = captured_answers
        append_user_turn(request, combined_text, current_topic, now)
    elif ui_action == "request_brief_correction":
        request["brief_feedback_text"] = combined_text or normalize_text(payload.get("brief_feedback_text"))
        if isinstance(payload.get("brief_section_updates"), dict):
            request["brief_section_updates"] = deepcopy(payload["brief_section_updates"])
        elif request["brief_feedback_text"]:
            inferred_updates = infer_brief_section_updates_from_feedback(request["brief_feedback_text"])
            if inferred_updates:
                request["brief_section_updates"] = inferred_updates
    elif ui_action == "confirm_brief":
        if combined_text and not is_text_brief_confirmation(combined_text):
            request["brief_feedback_text"] = combined_text
            inferred_updates = infer_brief_section_updates_from_feedback(combined_text)
            if inferred_updates:
                request["brief_section_updates"] = inferred_updates
            append_user_turn(request, combined_text, "brief_confirmation", now)
        else:
            request["confirmation_reply"] = build_confirmation_reply(combined_text, requester_identity)
    elif ui_action == "reopen_brief":
        request["brief_feedback_text"] = combined_text or "Нужно переоткрыть brief и уточнить детали."
        if isinstance(payload.get("brief_section_updates"), dict):
            request["brief_section_updates"] = deepcopy(payload["brief_section_updates"])
        else:
            inferred_updates = infer_brief_section_updates_from_feedback(request["brief_feedback_text"])
            if inferred_updates:
                request["brief_section_updates"] = inferred_updates

    return request, False, low_signal_submission


def run_discovery_runtime(discovery_request: dict[str, Any]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = Path(tmpdir) / "discovery-request.json"
        output_path = Path(tmpdir) / "discovery-response.json"
        source_path.write_text(json.dumps(discovery_request, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(DISCOVERY_SCRIPT), "run", "--source", str(source_path), "--output", str(output_path)],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            detail = normalize_text(proc.stderr) or normalize_text(proc.stdout) or "discovery runtime failed"
            raise RuntimeError(detail)
        response = load_json(output_path)
        if not isinstance(response, dict):
            raise RuntimeError("discovery runtime returned a non-object response")
        return response


def run_intake_runtime(source_payload: dict[str, Any]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = Path(tmpdir) / "intake-request.json"
        output_path = Path(tmpdir) / "intake-response.json"
        source_path.write_text(json.dumps(source_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(INTAKE_SCRIPT), "--source", str(source_path), "--output", str(output_path)],
            capture_output=True,
            text=True,
            check=False,
            cwd=PROJECT_ROOT,
        )
        if proc.returncode != 0:
            detail = normalize_text(proc.stderr) or normalize_text(proc.stdout) or "intake runtime failed"
            raise RuntimeError(detail)
        response = load_json(output_path)
        if not isinstance(response, dict):
            raise RuntimeError("intake runtime returned a non-object response")
        return response


def run_artifact_runtime(source_payload: dict[str, Any], *, output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        source_path = Path(tmpdir) / "artifact-request.json"
        output_path = Path(tmpdir) / "artifact-response.json"
        source_path.write_text(json.dumps(source_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        proc = subprocess.run(
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
            capture_output=True,
            text=True,
            check=False,
            cwd=PROJECT_ROOT,
        )
        if proc.returncode != 0:
            detail = normalize_text(proc.stderr) or normalize_text(proc.stdout) or "artifact generation failed"
            raise RuntimeError(detail)
        response = load_json(output_path)
        if not isinstance(response, dict):
            raise RuntimeError("artifact generation returned a non-object response")
        return response


def sanitize_discovery_runtime_state(runtime_response: dict[str, Any]) -> dict[str, Any]:
    sanitized = copy_discovery_state(runtime_response)
    sanitized.pop("brief_template_path", None)
    return sanitized


def prepare_delivery_runtime_state(runtime_state: dict[str, Any], requester_identity: dict[str, Any]) -> dict[str, Any]:
    delivery_state = copy_discovery_state(runtime_state)
    delivery_state["request_channel"] = normalize_text(delivery_state.get("request_channel")) or "web"
    delivery_state["requester_identity"] = requester_identity
    delivery_state["working_language"] = normalize_text(delivery_state.get("working_language")) or "ru"
    return delivery_state


def ensure_ready_handoff(runtime_state: dict[str, Any], requester_identity: dict[str, Any]) -> dict[str, Any]:
    handoff = runtime_state.get("factory_handoff_record", {}) if isinstance(runtime_state.get("factory_handoff_record"), dict) else {}
    if normalize_text(handoff.get("handoff_status")) == "ready":
        return runtime_state

    status = normalize_text(runtime_state.get("status"))
    next_action = normalize_text(runtime_state.get("next_action"))
    if status != "confirmed" and next_action not in {"start_concept_pack_handoff", "run_factory_intake"}:
        return runtime_state

    handoff_request = prepare_delivery_runtime_state(runtime_state, requester_identity)
    replayed_state = run_discovery_runtime(handoff_request)
    return sanitize_discovery_runtime_state(replayed_state)


def generate_browser_downloads(
    state_root: Path,
    web_demo_session_id: str,
    runtime_state: dict[str, Any],
    requester_identity: dict[str, Any],
    uploaded_files: list[dict[str, Any]] | None = None,
) -> tuple[dict[str, Any], list[dict[str, Any]], str]:
    ready_state = ensure_ready_handoff(runtime_state, requester_identity)
    handoff = ready_state.get("factory_handoff_record", {}) if isinstance(ready_state.get("factory_handoff_record"), dict) else {}
    if normalize_text(handoff.get("handoff_status")) != "ready":
        return ready_state, [], ""

    intake_response = run_intake_runtime(ready_state)
    if normalize_text(intake_response.get("status")) != "ready_for_pack":
        return ready_state, [], normalize_text(intake_response.get("block_reason")) or "Factory intake did not reach ready_for_pack."

    artifact_output_dir = delivery_root(state_root, web_demo_session_id)
    artifact_manifest = run_artifact_runtime(intake_response, output_dir=artifact_output_dir)
    if normalize_text(artifact_manifest.get("status")) != "generated":
        return ready_state, [], "Concept pack generation did not complete successfully."

    normalized_manifest_items = normalize_download_artifacts(artifact_manifest)
    requirement_brief = (
        ready_state.get("requirement_brief", {})
        if isinstance(ready_state.get("requirement_brief"), dict)
        else {}
    )
    production_simulation = simulate_post_handoff_production(
        state_root,
        web_demo_session_id,
        ready_state,
        uploaded_files,
    )
    if production_simulation:
        ready_state["production_simulation"] = production_simulation
        normalized_manifest_items.append(
            write_production_simulation_download(
                state_root,
                web_demo_session_id,
                production_simulation,
                requirement_brief,
            )
        )

    return ready_state, write_delivery_index(state_root, web_demo_session_id, normalized_manifest_items), ""


def build_audit_record(
    web_demo_session: dict[str, Any],
    pointer: dict[str, Any],
    runtime_state: dict[str, Any],
    envelope: dict[str, Any],
    *,
    access_granted: bool,
    error_message: str = "",
) -> dict[str, Any]:
    discovery_session = runtime_state.get("discovery_session", {}) if isinstance(runtime_state.get("discovery_session"), dict) else {}
    requirement_brief = runtime_state.get("requirement_brief", {}) if isinstance(runtime_state.get("requirement_brief"), dict) else {}
    factory_handoff = runtime_state.get("factory_handoff_record", {}) if isinstance(runtime_state.get("factory_handoff_record"), dict) else {}
    stage = "browser_turn_received" if access_granted else "access_granted"
    stage_status = "started" if access_granted else "failed"
    if normalize_text(runtime_state.get("status")) in {"awaiting_confirmation", "reopened"}:
        stage = "brief_rendered"
        stage_status = "completed"
    elif normalize_text(runtime_state.get("status")) == "confirmed":
        stage = "brief_confirmed"
        stage_status = "completed"
    elif normalize_text(runtime_state.get("next_action")) == "run_factory_intake":
        stage = "handoff_started"
        stage_status = "completed"
    summary_text = error_message or normalize_text(runtime_state.get("next_question")) or normalize_text(envelope.get("ui_action"))
    audit_slug_source = (
        f"{normalize_text(web_demo_session.get('web_demo_session_id'))}-"
        f"{normalize_text(envelope.get('request_id'))}"
    )
    return {
        "web_demo_audit_id": f"audit-{slugify(audit_slug_source, 'audit')}",
        "web_demo_session_id": normalize_text(web_demo_session.get("web_demo_session_id")),
        "project_key": normalize_text(pointer.get("project_key")),
        "correlation_id": normalize_text(envelope.get("request_id")),
        "stage": stage,
        "stage_status": stage_status,
        "summary_text": summary_text,
        "linked_discovery_session_id": normalize_text(discovery_session.get("discovery_session_id")),
        "linked_brief_id": normalize_text(requirement_brief.get("brief_id")),
        "linked_handoff_id": normalize_text(factory_handoff.get("factory_handoff_id")),
        "linked_concept_manifest_id": "",
        "recorded_at": utc_now(),
    }


def preferred_ui_action(reply_cards: list[dict[str, Any]], *, fallback: str = "") -> str:
    priority = (
        "submit_turn",
        "confirm_brief",
        "request_brief_correction",
        "request_status",
        "reopen_brief",
        "download_artifact",
        "start_project",
    )
    discovered_actions: list[str] = []
    for card in reply_cards:
        if not isinstance(card, dict):
            continue
        for action in card.get("action_hints", []):
            normalized = normalize_text(action)
            if normalized and normalized not in discovered_actions:
                discovered_actions.append(normalized)

    for action in priority:
        if action in discovered_actions:
            return action
    return normalize_text(fallback) or (discovered_actions[0] if discovered_actions else "")


def compact_display_title(*candidates: Any) -> str:
    def is_generic_title(value: str) -> bool:
        normalized = re.sub(r"\s+", " ", normalize_text(value).lower()).strip(" .-")
        if not normalized:
            return True
        return normalized in {
            "new",
            "new project",
            "project",
            "discovery project",
            "demo project",
            "factory project",
            "новый",
            "новый проект",
            "проект",
        }

    for candidate in candidates:
        text = normalize_text(candidate)
        if not text:
            continue
        first_sentence = re.split(r"[.!?\n]", text, maxsplit=1)[0].strip()
        cleaned = re.sub(r"^(нужен агент[,]?\s*|который\s+|хочу автоматизировать\s*|нужно автоматизировать\s*|нужна автоматизация\s*)", "", first_sentence, flags=re.IGNORECASE)
        normalized = re.sub(r"\s+", " ", cleaned).strip(" -")
        if normalized and not is_generic_title(normalized):
            return normalized[:72].rstrip()
    return "Новый проект"


def bridge_input_examples_topic(
    runtime_state: dict[str, Any],
    *,
    next_topic: str,
    next_question: str,
    adapter_status: str,
    next_action: str,
    uploaded_files: list[dict[str, Any]],
    now: str,
) -> tuple[str, str, bool]:
    topic = normalize_text(next_topic)
    status = normalize_text(adapter_status)
    action = normalize_text(next_action)
    normalized_uploads = normalize_uploaded_files(uploaded_files)
    if (
        topic != "input_examples"
        or not normalized_uploads
        or status == "awaiting_clarification"
        or action == "resolve_clarification"
    ):
        return next_topic, next_question, False

    upload_names = [normalize_text(item.get("name")) for item in normalized_uploads if normalize_text(item.get("name"))]
    listed = ", ".join(upload_names[:2]) if upload_names else "прикреплённые файлы"
    suffix = " и ещё файлы" if len(upload_names) > 2 else ""
    summary = f"Примеры входов получены через файлы: {listed}{suffix}."

    captured_answers = runtime_state.get("captured_answers")
    if not isinstance(captured_answers, dict):
        captured_answers = {}
    captured_answers["input_examples"] = summary
    runtime_state["captured_answers"] = captured_answers

    requirement_topics = runtime_state.get("requirement_topics")
    if isinstance(requirement_topics, list):
        updated = False
        for item in requirement_topics:
            if not isinstance(item, dict):
                continue
            if normalize_text(item.get("topic_name")) != "input_examples":
                continue
            item["summary"] = summary
            item["status"] = "clarified"
            item["last_updated_at"] = now
            updated = True
            break
        if not updated:
            requirement_topics.append(
                {
                    "topic_id": "topic-input_examples-uploaded",
                    "topic_name": "input_examples",
                    "category": "functional",
                    "status": "clarified",
                    "summary": summary,
                    "source_turn_ids": [],
                    "last_updated_at": now,
                }
            )
        runtime_state["requirement_topics"] = requirement_topics

    next_topic_key = normalize_text(next_uncovered_topic_after(runtime_state, "input_examples")) or "expected_outputs"
    next_topic_frame = ARCHITECT_TOPIC_FRAMES.get(next_topic_key, {})
    bridged_question = normalize_text(next_topic_frame.get("question")) or next_question
    return next_topic_key, bridged_question, True


def side_panel_mode(reply_cards: list[dict[str, Any]], download_artifacts: list[dict[str, Any]] | None) -> str:
    artifacts = normalize_download_artifacts(download_artifacts or [])
    if artifacts:
        return "downloads"
    for card in reply_cards:
        if isinstance(card, dict) and normalize_text(card.get("card_kind")) == "brief_summary_section":
            return "brief_review"
    return "hidden"


def composer_helper_example(*, next_question: str, current_topic: str, adapter_status: str) -> str:
    question = normalize_text(next_question)
    topic = normalize_text(current_topic)
    status = normalize_text(adapter_status)

    if status in {"awaiting_confirmation", "reopened"}:
        return "Например: подтверждаю brief. Или: добавь отдельные правила для срочных заявок."
    if status in {"confirmed", "download_ready"}:
        return (
            "Например: запусти имитацию цифрового сотрудника на моих данных. "
            "Или: нужно доработать brief по ограничениям."
        )
    if topic == "target_users" or "пользоват" in question.lower():
        return "Например: пользователи — члены кредитного комитета и клиентская служба."
    if topic == "current_workflow" or "как этот процесс" in question.lower():
        return "Например: сотрудник вручную собирает данные из нескольких систем и сверяет их в Excel."
    if topic == "input_examples" or "пример" in question.lower() or "входн" in question.lower():
        return "Например: можно приложить файл с образцом заявки, отчёта или one-page summary."
    if topic == "expected_outputs" or "результат" in question.lower() or "выход" in question.lower():
        return "Например: на выходе нужны аналитическая карточка, рекомендация и краткое заключение."
    if topic == "problem" or "бизнес-проблем" in question.lower():
        return "Например: нужно сократить время согласования и увеличить число рассмотренных кейсов."
    return "Отвечай простыми рабочими формулировками. Если есть примеры в файлах, прикрепи их прямо сюда."


def build_web_resume_context(
    saved_session: dict[str, Any],
    web_demo_session: dict[str, Any],
    pointer: dict[str, Any],
    runtime_state: dict[str, Any],
    status_snapshot: dict[str, Any],
    *,
    next_question: str,
    download_artifacts: list[dict[str, Any]] | None = None,
    uploaded_files: list[dict[str, Any]] | None = None,
    resumed_from_saved_session: bool = False,
    now: str,
) -> dict[str, Any]:
    runtime_resume = runtime_state.get("resume_context", {}) if isinstance(runtime_state.get("resume_context"), dict) else {}
    requirement_brief = runtime_state.get("requirement_brief", {}) if isinstance(runtime_state.get("requirement_brief"), dict) else {}
    discovery_session = runtime_state.get("discovery_session", {}) if isinstance(runtime_state.get("discovery_session"), dict) else {}
    confirmation_history = normalize_history_entries(runtime_state.get("confirmation_history"))
    handoff_history = normalize_history_entries(runtime_state.get("handoff_history"))
    latest_brief_version = (
        normalize_text(runtime_resume.get("latest_brief_version"))
        or normalize_text(requirement_brief.get("version"))
        or normalize_text(pointer.get("linked_brief_version"))
    )
    confirmed_version = normalize_text(runtime_resume.get("latest_confirmed_brief_version")) or latest_confirmed_brief_version(
        runtime_state
    )
    current_topic = (
        normalize_text(runtime_resume.get("current_topic"))
        or normalize_text(discovery_session.get("current_topic"))
        or normalize_text(status_snapshot.get("current_topic"))
    )
    pending_question = normalize_text(runtime_resume.get("pending_question")) or next_question
    user_visible_status = normalize_text(status_snapshot.get("user_visible_status"))
    summary_text = normalize_text(runtime_resume.get("summary_text"))
    artifacts = sanitize_download_artifacts(
        download_artifacts or [],
        web_demo_session_id=normalize_text(web_demo_session.get("web_demo_session_id")),
    )
    upload_count = len(normalize_uploaded_files(uploaded_files))
    if not summary_text:
        if user_visible_status == "downloads_ready" and artifacts:
            summary_text = "Возобновляю browser-сессию: concept pack уже готов к скачиванию."
        elif normalize_text(requirement_brief.get("status")) == "reopened" and latest_brief_version:
            summary_text = (
                f"Возобновляю browser-сессию: brief версии {latest_brief_version} переоткрыт и ждёт повторной проверки."
            )
        elif user_visible_status == "awaiting_confirmation" and latest_brief_version:
            summary_text = f"Возобновляю browser-сессию: brief версии {latest_brief_version} ждёт подтверждения."
        elif user_visible_status == "confirmed" and confirmed_version:
            summary_text = f"Возобновляю browser-сессию: подтверждён brief версии {confirmed_version}."
        elif pending_question:
            summary_text = "Возобновляю browser-сессию: можно продолжать discovery с последнего вопроса."
        else:
            summary_text = "Возобновляю browser-сессию с последнего сохранённого состояния."

    fingerprint_source = ":".join(
        [
            normalize_text(web_demo_session.get("web_demo_session_id")),
            normalize_text(pointer.get("project_key")),
            user_visible_status,
            latest_brief_version,
            confirmed_version,
            normalize_text(web_demo_session.get("last_agent_turn_at")),
            str(len(artifacts)),
            str(upload_count),
        ]
    )
    return {
        "resume_available": bool(normalize_text(web_demo_session.get("web_demo_session_id"))),
        "resumed_from_saved_session": resumed_from_saved_session,
        "resumed_from_status": normalize_text(runtime_resume.get("resumed_from_status"))
        or normalize_text(saved_session.get("web_demo_session", {}).get("status")),
        "restored_status": normalize_text(runtime_resume.get("restored_status")) or normalize_text(runtime_state.get("status")),
        "summary_text": summary_text,
        "current_status": user_visible_status,
        "current_status_label": normalize_text(status_snapshot.get("user_visible_status_label")),
        "current_topic": current_topic,
        "pending_question": pending_question,
        "latest_brief_version": latest_brief_version,
        "latest_confirmed_brief_version": confirmed_version,
        "active_project_key": normalize_text(pointer.get("project_key")),
        "linked_discovery_session_id": normalize_text(pointer.get("linked_discovery_session_id")),
        "linked_brief_id": normalize_text(pointer.get("linked_brief_id")),
        "linked_brief_version": normalize_text(pointer.get("linked_brief_version")),
        "confirmation_history_count": len(confirmation_history),
        "handoff_history_count": len(handoff_history),
        "download_artifact_count": len(artifacts),
        "uploaded_file_count": upload_count,
        "last_user_turn_at": normalize_text(web_demo_session.get("last_user_turn_at")),
        "last_agent_turn_at": normalize_text(web_demo_session.get("last_agent_turn_at")),
        "resume_fingerprint": sha256_hex(fingerprint_source)[:16],
        "updated_at": now,
    }


def persist_adapter_state(state_root: Path, response: dict[str, Any], access_gate: dict[str, Any]) -> None:
    ensure_state_layout(state_root)
    session_id = normalize_text(response.get("web_demo_session", {}).get("web_demo_session_id"))
    request_id = normalize_text(response.get("web_conversation_envelope", {}).get("request_id"))
    if session_id:
        write_json(response, state_root / "sessions" / f"{session_id}.json")
        pointer = response.get("browser_project_pointer", {})
        if isinstance(pointer, dict) and pointer:
            write_json(pointer, state_root / "pointers" / f"{session_id}.json")
        resume_context = response.get("resume_context", {})
        if isinstance(resume_context, dict) and resume_context:
            write_json(resume_context, state_root / "resume" / f"{session_id}.json")
        history_id = request_id or utc_now().replace(":", "-")
        write_json(response, state_root / "history" / f"{session_id}-{history_id}.json")
    grant_id = normalize_text(access_gate.get("demo_access_grant_id"))
    if grant_id:
        write_json(access_gate, state_root / "access" / f"{grant_id}.json")


def handle_turn_payload(payload: dict[str, Any], *, state_root: Path) -> dict[str, Any]:
    now = utc_now()
    ensure_state_layout(state_root)
    llm_settings = llm_settings_from_env()

    hinted_session = payload.get("web_demo_session", {})
    hinted_session_id = normalize_text(hinted_session.get("web_demo_session_id")) if isinstance(hinted_session, dict) else ""
    saved_session = load_saved_session(state_root, hinted_session_id)
    resumed_from_saved_session = bool(saved_session)
    discovery_state = payload.get("discovery_runtime_state", {})
    if not isinstance(discovery_state, dict):
        discovery_state = {}
    saved_discovery_state = (
        saved_session.get("discovery_runtime_state", {})
        if isinstance(saved_session.get("discovery_runtime_state"), dict)
        else {}
    )
    if not discovery_state:
        discovery_state = deepcopy(saved_discovery_state)
    seeded_discovery_session = (
        discovery_state.get("discovery_session", {})
        if isinstance(discovery_state.get("discovery_session"), dict)
        else {}
    )
    current_topic_before_turn = normalize_text(seeded_discovery_session.get("current_topic")) or normalize_text(
        discovery_state.get("next_topic")
    )

    requester_identity = normalize_requester_identity(payload, discovery_state)
    envelope = normalize_web_conversation_envelope(payload, discovery_state, now)
    action_hint = normalize_text(envelope.get("ui_action"))
    user_text_hint = normalize_text(envelope.get("user_text"))
    saved_status_hint = normalize_text(saved_discovery_state.get("status"))
    if saved_discovery_state:
        prefer_saved_runtime = action_hint in {"request_status", "download_artifact", "request_brief_review"}
        prefer_saved_runtime = prefer_saved_runtime or (
            action_hint in {"submit_turn", "confirm_brief", "reopen_brief"}
            and saved_status_hint in {"awaiting_confirmation", "reopened", "confirmed", "download_ready"}
        )
        if prefer_saved_runtime:
            discovery_state = deepcopy(saved_discovery_state)
            if (
                action_hint == "submit_turn"
                and saved_status_hint in {"confirmed", "download_ready"}
                and not is_likely_brief_correction_text(user_text_hint)
                and not is_text_brief_confirmation(user_text_hint)
            ):
                envelope["ui_action"] = "request_status"
    web_demo_session = normalize_web_demo_session(payload, saved_session, discovery_state, requester_identity, now)
    pointer = normalize_project_pointer(payload, saved_session, discovery_state, web_demo_session, envelope, now)
    uploaded_files, turn_uploaded_files = materialize_uploaded_files(
        payload,
        saved_session,
        state_root=state_root,
        session_id=normalize_text(web_demo_session.get("web_demo_session_id")),
        now=now,
    )

    access_granted, access_gate, access_message = access_gate_result(payload, discovery_state, web_demo_session, now)
    web_demo_session["access_grant_id"] = normalize_text(access_gate.get("demo_access_grant_id"))

    download_artifacts: list[dict[str, Any]] = []
    runtime_state: dict[str, Any] = {}
    delivery_error = ""
    if access_granted:
        ui_action = normalize_text(envelope.get("ui_action"))
        reuse_saved_downloads = ui_action in {"request_status", "download_artifact"}
        discovery_request, skip_runtime, low_signal_submission = build_discovery_request(
            payload,
            discovery_state,
            requester_identity,
            envelope,
            web_demo_session,
            pointer,
            uploaded_files,
            turn_uploaded_files,
            now,
        )
        runtime_state = discovery_state if skip_runtime and discovery_state else run_discovery_runtime(discovery_request)
        runtime_state = sanitize_discovery_runtime_state(runtime_state)
        hydrate_runtime_input_examples_answer(runtime_state, discovery_request)
        if reuse_saved_downloads:
            download_artifacts = sanitize_download_artifacts(
                payload.get("download_artifacts"),
                web_demo_session_id=normalize_text(web_demo_session.get("web_demo_session_id")),
            )
            if not download_artifacts:
                download_artifacts = sanitize_download_artifacts(
                    saved_session.get("download_artifacts"),
                    web_demo_session_id=normalize_text(web_demo_session.get("web_demo_session_id")),
                )
        if not download_artifacts and ui_action in {"request_status", "download_artifact"}:
            try:
                runtime_state, download_artifacts, delivery_error = generate_browser_downloads(
                    state_root,
                    normalize_text(web_demo_session.get("web_demo_session_id")),
                    runtime_state,
                    requester_identity,
                    uploaded_files,
                )
            except Exception as exc:  # noqa: BLE001
                delivery_error = normalize_text(exc) or "Concept pack generation failed."
    else:
        low_signal_submission = False
        runtime_state = {
            "status": "gate_pending",
            "next_action": "request_demo_access",
            "next_topic": "",
            "next_question": access_message,
            "discovery_session": {},
        }

    requirement_brief = runtime_state.get("requirement_brief", {}) if isinstance(runtime_state.get("requirement_brief"), dict) else {}
    discovery_session = runtime_state.get("discovery_session", {}) if isinstance(runtime_state.get("discovery_session"), dict) else {}
    pointer["project_key"] = normalize_text(pointer.get("project_key")) or normalize_text(discovery_session.get("project_key"))
    pointer["linked_discovery_session_id"] = normalize_text(discovery_session.get("discovery_session_id"))
    pointer["linked_brief_id"] = normalize_text(requirement_brief.get("brief_id"))
    pointer["linked_brief_version"] = normalize_text(requirement_brief.get("version"))
    pointer["updated_at"] = now

    adapter_status = "download_ready" if download_artifacts else (normalize_text(runtime_state.get("status")) or "active")
    next_action = "download_artifact" if download_artifacts else normalize_text(runtime_state.get("next_action"))
    next_topic = normalize_text(runtime_state.get("next_topic"))
    production_simulation = (
        runtime_state.get("production_simulation", {})
        if isinstance(runtime_state.get("production_simulation"), dict)
        else {}
    )
    simulation_requested = is_production_simulation_request_text(normalize_text(envelope.get("user_text")))
    primary_artifact_kind = "one_page_summary"
    if simulation_requested and any(normalize_text(item.get("artifact_kind")) == "production_simulation" for item in download_artifacts):
        primary_artifact_kind = "production_simulation"
    next_question = (
        (
            (
                "Имитация запуска выполнена. Открой отчёт production simulation: там есть регистрация цифрового сотрудника "
                "в реестре и результат выполнения стартового запроса на боевых данных."
                if simulation_requested and primary_artifact_kind == "production_simulation"
                else "Concept pack готов. Цифровой сотрудник зарегистрирован в реестре, "
                "стартовый запрос пользователя выполнен в имитации production. "
                "Можно скачать project doc, agent spec, presentation и отчёт по имитации."
            )
            if normalize_text(production_simulation.get("status")) == "completed"
            else (
                "Запрос на имитацию принят. Открой отчёт production simulation, как только он станет доступен."
                if simulation_requested and primary_artifact_kind == "production_simulation"
                else "Concept pack готов. Можно скачать project doc, agent spec и presentation из этой browser session."
            )
        )
        if download_artifacts
        else normalize_text(runtime_state.get("next_question"))
    )
    clarification_retry_hint = (
        normalize_text(discovery_request.get("_web_clarification_retry_hint"))
        if access_granted and isinstance(discovery_request, dict)
        else ""
    )
    if (
        clarification_retry_hint
        and adapter_status == "awaiting_clarification"
        and next_action == "resolve_clarification"
        and normalize_text(next_topic) == "input_examples"
    ):
        if next_question:
            if clarification_retry_hint not in next_question:
                next_question = f"{next_question}\n\n{clarification_retry_hint}"
        else:
            next_question = clarification_retry_hint
    architect_question_source = "runtime"
    bridged_from_uploaded_examples = False
    bridged_repeat_ack = False
    skip_adaptive_architect = False
    if access_granted and not download_artifacts:
        if adapter_status == "awaiting_user_reply":
            next_topic, next_question, bridged_from_uploaded_examples = bridge_input_examples_topic(
                runtime_state,
                next_topic=next_topic,
                next_question=next_question,
                adapter_status=adapter_status,
                next_action=next_action,
                uploaded_files=turn_uploaded_files,
                now=now,
            )
            (
                next_topic,
                next_question,
                bridged_repeat_ack,
                skip_adaptive_architect,
                repeat_source,
            ) = bridge_repeat_answer(
                runtime_state,
                next_topic=next_topic,
                next_question=next_question,
                envelope=envelope,
                now=now,
            )
            if bridged_repeat_ack:
                architect_question_source = repeat_source
            elif bridged_from_uploaded_examples:
                architect_question_source = "uploaded_examples_bridge"
    if access_granted and low_signal_submission and adapter_status == "awaiting_user_reply":
        next_action = "ask_next_question"
        if not next_topic:
            next_topic = (
                normalize_text(discovery_session.get("current_topic"))
                or normalize_text(runtime_state.get("next_topic"))
            )
    if (
        access_granted
        and not download_artifacts
        and next_question
        and adapter_status == "awaiting_user_reply"
        and not skip_adaptive_architect
    ):
        llm_question = ""
        llm_topic = ""
        if not low_signal_submission:
            llm_question, llm_topic, llm_source = llm_adaptive_architect_question(
                current_topic=current_topic_before_turn,
                runtime_next_topic=next_topic,
                runtime_next_question=next_question,
                runtime_state=runtime_state,
                envelope=envelope,
                uploaded_files=uploaded_files,
            )
            if llm_question:
                next_question = normalize_text(llm_question) or next_question
                next_topic = normalize_text(llm_topic) or next_topic
                architect_question_source = llm_source
        if not llm_question:
            adaptive_question, architect_question_source = adaptive_architect_question(
                next_question=next_question,
                next_topic=next_topic,
                runtime_state=runtime_state,
                envelope=envelope,
                uploaded_files=uploaded_files,
                force_low_signal_guard=low_signal_submission,
            )
            next_question = normalize_text(adaptive_question) or next_question
    if access_granted and not download_artifacts and adapter_status == "awaiting_user_reply":
        if not normalize_text(next_question):
            fallback_topic = normalize_text(next_topic) or normalize_text(discovery_session.get("current_topic")) or "problem"
            fallback_frame = ARCHITECT_TOPIC_FRAMES.get(fallback_topic, {})
            fallback_question = normalize_text(fallback_frame.get("question"))
            if fallback_question:
                next_topic = fallback_topic
                next_question = fallback_question
                architect_question_source = "fallback_question_guard"
    if access_granted and not download_artifacts:
        patch_runtime_next_question(
            runtime_state,
            next_question=next_question,
            next_topic=next_topic,
            next_action=next_action,
        )
        discovery_session = runtime_state.get("discovery_session", {}) if isinstance(runtime_state.get("discovery_session"), dict) else {}
    else:
        discovery_session = runtime_state.get("discovery_session", {}) if isinstance(runtime_state.get("discovery_session"), dict) else {}
    status_snapshot = build_web_demo_status_snapshot(
        web_demo_session.get("web_demo_session_id"),
        pointer.get("project_key"),
        adapter_status=adapter_status,
        next_action=next_action,
        brief=requirement_brief,
        now=now,
        download_artifacts=download_artifacts,
        uploaded_files=uploaded_files,
        needs_operator_attention=not access_granted,
    )
    web_demo_session["status"] = web_session_runtime_status(
        adapter_status,
        next_action=next_action,
        needs_operator_attention=not access_granted,
        download_artifacts=download_artifacts,
    )
    web_demo_session["active_project_key"] = normalize_text(pointer.get("project_key"))
    web_demo_session["active_discovery_session_id"] = normalize_text(pointer.get("linked_discovery_session_id"))
    web_demo_session["active_brief_id"] = normalize_text(pointer.get("linked_brief_id"))
    web_demo_session["updated_at"] = now
    if normalize_text(envelope.get("user_text")):
        web_demo_session["last_user_turn_at"] = now
    if next_question:
        web_demo_session["last_agent_turn_at"] = now
    resume_context = build_web_resume_context(
        saved_session,
        web_demo_session,
        pointer,
        runtime_state,
        status_snapshot,
        next_question=next_question,
        download_artifacts=download_artifacts,
        uploaded_files=uploaded_files,
        resumed_from_saved_session=resumed_from_saved_session,
        now=now,
    )

    envelope["linked_discovery_session_id"] = normalize_text(pointer.get("linked_discovery_session_id"))
    envelope["linked_brief_id"] = normalize_text(pointer.get("linked_brief_id"))
    envelope["normalized_payload"] = {
        "ui_action": normalize_text(envelope.get("ui_action")),
        "project_key": normalize_text(pointer.get("project_key")),
        "current_topic": normalize_text(discovery_session.get("current_topic")) or next_topic,
        "request_channel": "web",
        "uploaded_file_count": len(uploaded_files),
    }

    card_runtime_state = deepcopy(runtime_state)
    card_runtime_state["status"] = adapter_status
    card_runtime_state["next_action"] = next_action
    card_runtime_state["next_question"] = next_question
    reply_cards = build_web_reply_cards(
        card_runtime_state,
        web_demo_session_id=web_demo_session.get("web_demo_session_id"),
        access_granted=access_granted,
        now=now,
        download_artifacts=download_artifacts,
        uploaded_files=uploaded_files,
    )
    if download_artifacts and normalize_text(production_simulation.get("status")) == "completed":
        reply_cards.append(
            build_web_reply_card(
                "status_update",
                title="Production-имитация выполнена",
                body_text=(
                    f"Цифровой сотрудник `{normalize_text(production_simulation.get('digital_employee_id'))}` "
                    "зарегистрирован в реестре и выполнил стартовый запрос пользователя на боевом контексте данных."
                ),
                web_demo_session_id=web_demo_session.get("web_demo_session_id"),
                action_hints=["download_artifact", "request_status"],
                linked_discovery_session_id=discovery_session.get("discovery_session_id"),
                linked_brief_id=requirement_brief.get("brief_id"),
                linked_handoff_id=runtime_state.get("factory_handoff_record", {}).get("factory_handoff_id")
                if isinstance(runtime_state.get("factory_handoff_record"), dict)
                else "",
                now=now,
            )
        )
    if delivery_error:
        reply_cards.append(
            build_web_reply_card(
                "error_message",
                title="Concept pack пока не готов",
                body_text=delivery_error,
                web_demo_session_id=web_demo_session.get("web_demo_session_id"),
                action_hints=["request_status"],
                linked_discovery_session_id=discovery_session.get("discovery_session_id"),
                linked_brief_id=requirement_brief.get("brief_id"),
                linked_handoff_id=runtime_state.get("factory_handoff_record", {}).get("factory_handoff_id")
                if isinstance(runtime_state.get("factory_handoff_record"), dict)
                else "",
                now=now,
            )
        )
    audit_record = build_audit_record(
        web_demo_session,
        pointer,
        runtime_state,
        envelope,
        access_granted=access_granted,
        error_message=access_message,
    )

    response = {
        "status": adapter_status,
        "next_action": next_action,
        "next_topic": next_topic,
        "next_question": next_question,
        "access_gate": {
            "granted": access_granted,
            "reason": access_message,
            "demo_access_grant_id": normalize_text(access_gate.get("demo_access_grant_id")),
            "grant_type": normalize_text(access_gate.get("grant_type")),
            "grant_value_hash": normalize_text(access_gate.get("grant_value_hash")),
            "status": normalize_text(access_gate.get("status")),
            "expires_at": normalize_text(access_gate.get("expires_at")),
            "mode": normalize_text(access_gate.get("access_gate_mode")),
            "configured": bool(access_gate.get("access_gate_configured")),
            "public_base_url": normalize_text(access_gate.get("public_base_url")),
            "demo_domain": normalize_text(access_gate.get("demo_domain")),
        },
        "web_demo_session": web_demo_session,
        "browser_project_pointer": pointer,
        "web_conversation_envelope": envelope,
        "status_snapshot": status_snapshot,
        "reply_cards": reply_cards,
        "audit_record": audit_record,
        "resume_context": resume_context,
        "uploaded_files": uploaded_files,
        "ui_projection": {
            "preferred_ui_action": preferred_ui_action(reply_cards, fallback="request_status" if access_granted else "submit_access_token"),
            "current_question": next_question,
            "current_topic": envelope["normalized_payload"]["current_topic"],
            "question_source": architect_question_source,
            "agent_role": "architect",
            "agent_display_name": architect_agent_display_name(),
            "project_title": normalize_text(pointer.get("project_key")) or "Новый проект фабрики",
            "display_project_title": compact_display_title(
                requirement_brief.get("problem_statement"),
                runtime_state.get("raw_idea"),
                envelope["normalized_payload"].get("user_text"),
                normalize_text(pointer.get("project_key")).replace("-", " "),
            ),
            "project_stage_label": normalize_text(status_snapshot.get("user_visible_status_label")),
            "side_panel_mode": side_panel_mode(reply_cards, download_artifacts),
            "primary_artifact": primary_artifact_kind if download_artifacts else "",
            "composer_helper_example": composer_helper_example(
                next_question=next_question,
                current_topic=envelope["normalized_payload"]["current_topic"],
                adapter_status=adapter_status,
            ),
            "brief_version": normalize_text(requirement_brief.get("version")),
            "brief_status": normalize_text(requirement_brief.get("status")) or adapter_status,
            "uploaded_file_count": len(uploaded_files),
            "llm_enabled": llm_settings.enabled,
            "llm_configured": llm_settings.configured,
            "production_simulation_status": normalize_text(production_simulation.get("status")),
        },
    }
    if access_granted:
        response["discovery_runtime_state"] = runtime_state
    if normalize_text(production_simulation.get("status")):
        response["production_simulation"] = production_simulation
    if download_artifacts:
        response["download_artifacts"] = download_artifacts
    if delivery_error:
        response["delivery_error"] = delivery_error

    persist_adapter_state(state_root, response, access_gate)
    return response


def render_json(handler: BaseHTTPRequestHandler, payload: dict[str, Any], *, status_code: int = 200) -> None:
    body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    handler.send_response(status_code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def render_text(handler: BaseHTTPRequestHandler, body_text: str, *, content_type: str, status_code: int = 200) -> None:
    body = body_text.encode("utf-8")
    handler.send_response(status_code)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def render_file(handler: BaseHTTPRequestHandler, path: Path) -> None:
    if not path.is_file():
        render_json(handler, {"status": "error", "error": "asset_not_found"}, status_code=404)
        return
    body = path.read_bytes()
    content_type, _encoding = mimetypes.guess_type(str(path))
    handler.send_response(200)
    handler.send_header("Content-Type", content_type or "application/octet-stream")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def render_download(handler: BaseHTTPRequestHandler, path: Path, download_name: str) -> None:
    if not path.is_file():
        render_json(handler, {"status": "error", "error": "download_not_found"}, status_code=404)
        return
    body = path.read_bytes()
    content_type, _encoding = mimetypes.guess_type(str(path))
    handler.send_response(200)
    handler.send_header("Content-Type", content_type or "application/octet-stream")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Content-Disposition", f'attachment; filename="{download_name or path.name}"')
    handler.end_headers()
    handler.wfile.write(body)


def render_health(handler: BaseHTTPRequestHandler, state_root: Path) -> None:
    settings = access_gate_settings()
    llm_settings = llm_settings_from_env()
    operator_status = build_operator_status_publication(state_root)
    payload = {
        "status": "ok",
        "service": "agent-factory-web-adapter",
        "demo_domain": normalize_text(settings.get("demo_domain")),
        "public_base_url": normalize_text(settings.get("public_base_url")),
        "access_gate_mode": normalize_text(settings.get("access_gate_mode")),
        "access_gate_configured": bool(settings.get("access_gate_configured")),
        "access_gate_ready": bool(settings.get("access_gate_ready")),
        "llm_enabled": llm_settings.enabled,
        "llm_configured": llm_settings.configured,
        "llm_model": llm_settings.model_name if llm_settings.configured else "",
        "llm_base_url": llm_settings.base_url if llm_settings.configured else "",
        "operator_status": operator_status,
    }
    render_json(handler, payload)


def render_metrics(handler: BaseHTTPRequestHandler, state_root: Path) -> None:
    operator_status = build_operator_status_publication(state_root)
    metrics_body = "\n".join(
        [
            "# HELP agent_factory_web_demo_active_sessions Number of persisted active browser sessions.",
            "# TYPE agent_factory_web_demo_active_sessions gauge",
            f"agent_factory_web_demo_active_sessions {operator_status['active_session_count']}",
            "# HELP agent_factory_web_demo_awaiting_user_reply_sessions Number of sessions waiting for the next business reply.",
            "# TYPE agent_factory_web_demo_awaiting_user_reply_sessions gauge",
            f"agent_factory_web_demo_awaiting_user_reply_sessions {operator_status['awaiting_user_reply_count']}",
            "# HELP agent_factory_web_demo_awaiting_confirmation_sessions Number of sessions currently in brief confirmation.",
            "# TYPE agent_factory_web_demo_awaiting_confirmation_sessions gauge",
            f"agent_factory_web_demo_awaiting_confirmation_sessions {operator_status['awaiting_confirmation_count']}",
            "# HELP agent_factory_web_demo_handoff_running_sessions Number of sessions currently running downstream handoff.",
            "# TYPE agent_factory_web_demo_handoff_running_sessions gauge",
            f"agent_factory_web_demo_handoff_running_sessions {operator_status['handoff_running_count']}",
            "# HELP agent_factory_web_demo_access_grants Number of persisted demo access grants.",
            "# TYPE agent_factory_web_demo_access_grants gauge",
            f"agent_factory_web_demo_access_grants {operator_status['access_grant_count']}",
            "# HELP agent_factory_web_demo_saved_pointers Number of persisted active browser project pointers.",
            "# TYPE agent_factory_web_demo_saved_pointers gauge",
            f"agent_factory_web_demo_saved_pointers {operator_status['pointer_count']}",
            "# HELP agent_factory_web_demo_resume_contexts Number of persisted browser resume context snapshots.",
            "# TYPE agent_factory_web_demo_resume_contexts gauge",
            f"agent_factory_web_demo_resume_contexts {operator_status['resume_context_count']}",
            "# HELP agent_factory_web_demo_download_sessions Number of download-ready browser sessions.",
            "# TYPE agent_factory_web_demo_download_sessions gauge",
            f"agent_factory_web_demo_download_sessions {operator_status['download_session_count']}",
            "# HELP agent_factory_web_demo_download_ready_sessions Number of sessions with ready browser downloads.",
            "# TYPE agent_factory_web_demo_download_ready_sessions gauge",
            f"agent_factory_web_demo_download_ready_sessions {operator_status['download_ready_count']}",
            "# HELP agent_factory_web_demo_attention_sessions Number of sessions currently needing operator attention.",
            "# TYPE agent_factory_web_demo_attention_sessions gauge",
            f"agent_factory_web_demo_attention_sessions {operator_status['needs_attention_session_count']}",
            "# HELP agent_factory_web_demo_publication_ready Whether the web demo publication state is ready.",
            "# TYPE agent_factory_web_demo_publication_ready gauge",
            f"agent_factory_web_demo_publication_ready {0 if operator_status['needs_operator_attention'] else 1}",
            "# HELP agent_factory_web_demo_access_gate_configured Whether the configured access gate is ready.",
            "# TYPE agent_factory_web_demo_access_gate_configured gauge",
            f"agent_factory_web_demo_access_gate_configured {1 if operator_status['access_gate_configured'] else 0}",
            "# HELP agent_factory_web_demo_access_gate_ready Whether the current access gate mode is publishable for controlled demo use.",
            "# TYPE agent_factory_web_demo_access_gate_ready gauge",
            f"agent_factory_web_demo_access_gate_ready {1 if operator_status['access_gate_ready'] else 0}",
            "",
        ]
    )
    render_text(handler, metrics_body, content_type="text/plain; version=0.0.4; charset=utf-8")


def serve(host: str, port: int, *, state_root: Path, assets_root: Path) -> int:
    ensure_state_layout(state_root)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
            return

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path in {"/health", "/api/health"}:
                render_health(self, state_root)
                return
            if parsed.path == "/metrics":
                render_metrics(self, state_root)
                return
            if parsed.path == "/api/session":
                session_id = normalize_text(parse_qs(parsed.query).get("session_id", [""])[0])
                if not session_id:
                    render_json(self, {"status": "gate_pending", "next_action": "request_demo_access"}, status_code=400)
                    return
                session = load_saved_session(state_root, session_id)
                if not session:
                    render_json(self, {"status": "error", "error": "session_not_found"}, status_code=404)
                    return
                pointer = load_saved_pointer(state_root, session_id)
                status_payload = {
                    "web_demo_session": {
                        "web_demo_session_id": session_id,
                    },
                    "browser_project_pointer": {
                        "project_key": normalize_text(pointer.get("project_key")) or normalize_text(
                            session.get("browser_project_pointer", {}).get("project_key")
                        ),
                    },
                    "web_conversation_envelope": {
                        "request_id": f"session-fetch-{int(time.time() * 1000)}",
                        "ui_action": "request_status",
                        "user_text": "",
                        "linked_discovery_session_id": session_id,
                    },
                }
                try:
                    render_json(self, handle_turn_payload(status_payload, state_root=state_root))
                except Exception:
                    render_json(self, hydrate_saved_session_response(state_root, session))
                return
            if parsed.path == "/api/download":
                session_id = normalize_text(parse_qs(parsed.query).get("session_id", [""])[0])
                download_token = normalize_text(parse_qs(parsed.query).get("token", [""])[0])
                if not session_id or not download_token:
                    render_json(self, {"status": "error", "error": "missing_download_locator"}, status_code=400)
                    return
                entry = load_delivery_entry(state_root, session_id, download_token)
                download_ref = Path(normalize_text(entry.get("download_ref")))
                if not entry or not download_ref.is_file():
                    render_json(self, {"status": "error", "error": "download_not_found"}, status_code=404)
                    return
                render_download(self, download_ref, normalize_text(entry.get("download_name")) or download_ref.name)
                return
            if parsed.path in {"/", "/index.html"}:
                render_file(self, assets_root / "index.html")
                return
            if parsed.path == "/app.css":
                render_file(self, assets_root / "app.css")
                return
            if parsed.path == "/app.js":
                render_file(self, assets_root / "app.js")
                return
            render_json(self, {"status": "error", "error": "not_found"}, status_code=404)

        def do_POST(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path != "/api/turn":
                render_json(self, {"status": "error", "error": "not_found"}, status_code=404)
                return
            try:
                content_length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                content_length = 0
            body = self.rfile.read(content_length)
            try:
                payload = json.loads(body.decode("utf-8"))
            except json.JSONDecodeError:
                render_json(self, {"status": "error", "error": "invalid_json"}, status_code=400)
                return
            if not isinstance(payload, dict):
                render_json(self, {"status": "error", "error": "body_must_be_object"}, status_code=400)
                return
            try:
                response = handle_turn_payload(payload, state_root=state_root)
            except Exception as exc:  # noqa: BLE001
                render_json(self, {"status": "error", "error": normalize_text(exc)}, status_code=500)
                return
            render_json(self, response)

    server = ThreadingHTTPServer((host, port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    finally:
        server.server_close()
    return 0


def main() -> int:
    args = parse_args()
    if args.command == "handle-turn":
        payload = load_payload(args.source)
        response = handle_turn_payload(payload, state_root=Path(args.state_root))
        write_json(response, args.output)
        return 0
    if args.command == "serve":
        return serve(args.host, args.port, state_root=Path(args.state_root), assets_root=Path(args.assets_root))
    raise ValueError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    sys.exit(main())
