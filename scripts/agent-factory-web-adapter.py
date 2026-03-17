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
import zipfile
from copy import deepcopy
from html import unescape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse
from xml.etree import ElementTree

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
STATE_DIRS = ("sessions", "pointers", "resume", "access", "history", "downloads", "uploads")
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
    "confirmation_snapshot",
    "confirmation_history",
    "factory_handoff_record",
    "handoff_history",
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
) -> list[dict[str, Any]]:
    existing = normalize_uploaded_files(saved_session.get("uploaded_files"))
    raw_uploads = payload.get("uploaded_files")
    if not isinstance(raw_uploads, list) or not raw_uploads:
        return existing

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
    return merge_uploaded_files(existing, materialized)


def uploaded_files_context(uploaded_files: list[dict[str, Any]]) -> str:
    normalized = normalize_uploaded_files(uploaded_files)
    if not normalized:
        return ""
    parts = ["Контекст из прикреплённых файлов:"]
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
        return f"Понял проблему: {shorten_text(problem, 90)}."
    if next_topic == "current_workflow" and target_users:
        return f"Зафиксировал пользователей: {shorten_text(target_users, 80)}."
    if next_topic == "desired_outcome" and current_workflow:
        return f"Принял текущий процесс: {shorten_text(current_workflow, 90)}."
    if next_topic == "user_story" and target_users:
        return f"Роли уже понятны: {shorten_text(target_users, 80)}."
    if next_topic == "input_examples" and upload_names:
        listed = ", ".join(upload_names[:2])
        suffix = " и ещё файлы" if len(upload_names) > 2 else ""
        return f"Вижу приложенные файлы: {listed}{suffix}."
    if next_topic == "expected_outputs" and desired_outcome:
        return f"Целевой бизнес-эффект уже зафиксирован: {shorten_text(desired_outcome, 90)}."
    if next_topic == "constraints" and desired_outcome:
        return "Чтобы решение было безопасным и выполнимым, уточним ограничения."
    if next_topic == "success_metrics" and desired_outcome:
        return "Осталось зафиксировать измеримые критерии успеха для запуска в фабрику."
    return ""


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
    example = normalize_text(frame.get("example"))
    example_hint = example if example.lower().startswith("например") else (f"Например: {example}" if example else "")
    lead = normalize_text(frame.get("lead"))
    user_text = normalize_text(envelope.get("user_text"))
    low_signal = force_low_signal_guard or is_low_signal_reply(user_text, uploaded_files)
    if low_signal:
        reprompt = "Ответ пока слишком общий, из него нельзя зафиксировать требование в brief."
        question = f"{reprompt} {base_question}"
        if example_hint:
            question = f"{question} {example_hint}"
        return question, "low_signal_guard"

    summaries = requirement_topic_summaries(runtime_state)
    context_hint = context_hint_for_topic(topic, summaries, uploaded_files)
    parts = [context_hint or lead, base_question]
    if example_hint:
        parts.append(example_hint)
    question = " ".join(part for part in parts if normalize_text(part))
    return question, "adaptive_architect"


def patch_runtime_next_question(runtime_state: dict[str, Any], *, next_question: str, next_topic: str) -> None:
    if not isinstance(runtime_state, dict):
        return
    question = normalize_text(next_question)
    topic = normalize_text(next_topic)
    if not question:
        return
    runtime_state["next_question"] = question
    if topic:
        runtime_state["next_topic"] = topic
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


def build_discovery_request(
    payload: dict[str, Any],
    discovery_state: dict[str, Any],
    requester_identity: dict[str, Any],
    envelope: dict[str, Any],
    web_demo_session: dict[str, Any],
    pointer: dict[str, Any],
    uploaded_files: list[dict[str, Any]],
    now: str,
) -> tuple[dict[str, Any], bool, bool]:
    ui_action = normalize_text(envelope.get("ui_action"))
    user_text = normalize_text(envelope.get("user_text"))
    attachment_context = uploaded_files_context(uploaded_files)
    combined_text = "\n\n".join(part for part in (user_text, attachment_context) if part)
    request = seed_discovery_request(payload, discovery_state, requester_identity)
    current_topic = normalize_text(
        request.get("discovery_session", {}).get("current_topic")
        if isinstance(request.get("discovery_session"), dict)
        else ""
    ) or normalize_text(request.get("next_topic"))
    request["project_key"] = normalize_text(pointer.get("project_key")) or normalize_text(web_demo_session.get("active_project_key"))
    low_signal_submission = False

    if ui_action == "request_status" and discovery_state:
        return request, True, low_signal_submission

    if ui_action in {"request_brief_review"} and discovery_state:
        return request, True, low_signal_submission

    if ui_action == "start_project":
        low_signal_submission = is_low_signal_reply(combined_text, uploaded_files)
        if not low_signal_submission:
            request["raw_idea"] = combined_text or normalize_text(payload.get("raw_idea"))
    elif ui_action == "submit_turn":
        low_signal_submission = is_low_signal_reply(combined_text, uploaded_files)
        captured_answers = request.get("captured_answers", {})
        if not isinstance(captured_answers, dict):
            captured_answers = {}
        if current_topic and combined_text and not low_signal_submission:
            captured_answers[current_topic] = combined_text
        elif combined_text and not normalize_text(request.get("raw_idea")) and not low_signal_submission:
            request["raw_idea"] = combined_text
        request["captured_answers"] = captured_answers
        append_user_turn(request, combined_text, current_topic, now)
    elif ui_action == "request_brief_correction":
        request["brief_feedback_text"] = combined_text or normalize_text(payload.get("brief_feedback_text"))
        if isinstance(payload.get("brief_section_updates"), dict):
            request["brief_section_updates"] = deepcopy(payload["brief_section_updates"])
    elif ui_action == "confirm_brief":
        request["confirmation_reply"] = build_confirmation_reply(combined_text, requester_identity)
    elif ui_action == "reopen_brief":
        request["brief_feedback_text"] = combined_text or "Нужно переоткрыть brief и уточнить детали."
        if isinstance(payload.get("brief_section_updates"), dict):
            request["brief_section_updates"] = deepcopy(payload["brief_section_updates"])

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

    return ready_state, write_delivery_index(state_root, web_demo_session_id, artifact_manifest), ""


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
    for candidate in candidates:
        text = normalize_text(candidate)
        if not text:
            continue
        first_sentence = re.split(r"[.!?\n]", text, maxsplit=1)[0].strip()
        cleaned = re.sub(r"^(нужен агент[,]?\s*|который\s+|хочу автоматизировать\s*|нужно автоматизировать\s*|нужна автоматизация\s*)", "", first_sentence, flags=re.IGNORECASE)
        normalized = re.sub(r"\s+", " ", cleaned).strip(" -")
        if normalized:
            return normalized[:72].rstrip()
    return "Новый проект"


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
        return "Например: материалы готовы, но нужно уточнить ограничения и вернуть brief на доработку."
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

    hinted_session = payload.get("web_demo_session", {})
    hinted_session_id = normalize_text(hinted_session.get("web_demo_session_id")) if isinstance(hinted_session, dict) else ""
    saved_session = load_saved_session(state_root, hinted_session_id)
    resumed_from_saved_session = bool(saved_session)
    discovery_state = payload.get("discovery_runtime_state", {})
    if not isinstance(discovery_state, dict):
        discovery_state = {}
    if not discovery_state:
        saved_state = saved_session.get("discovery_runtime_state", {})
        if isinstance(saved_state, dict):
            discovery_state = deepcopy(saved_state)

    requester_identity = normalize_requester_identity(payload, discovery_state)
    envelope = normalize_web_conversation_envelope(payload, discovery_state, now)
    web_demo_session = normalize_web_demo_session(payload, saved_session, discovery_state, requester_identity, now)
    pointer = normalize_project_pointer(payload, saved_session, discovery_state, web_demo_session, envelope, now)
    uploaded_files = materialize_uploaded_files(
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
            now,
        )
        runtime_state = discovery_state if skip_runtime and discovery_state else run_discovery_runtime(discovery_request)
        runtime_state = sanitize_discovery_runtime_state(runtime_state)
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
    next_question = (
        "Concept pack готов. Можно скачать project doc, agent spec и presentation из этой browser session."
        if download_artifacts
        else normalize_text(runtime_state.get("next_question"))
    )
    architect_question_source = "runtime"
    if access_granted and low_signal_submission and adapter_status in {"awaiting_user_reply", "awaiting_clarification"}:
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
        and adapter_status in {"awaiting_user_reply", "awaiting_clarification"}
    ):
        adaptive_question, architect_question_source = adaptive_architect_question(
            next_question=next_question,
            next_topic=next_topic,
            runtime_state=runtime_state,
            envelope=envelope,
            uploaded_files=uploaded_files,
            force_low_signal_guard=low_signal_submission,
        )
        next_question = normalize_text(adaptive_question) or next_question
        patch_runtime_next_question(runtime_state, next_question=next_question, next_topic=next_topic)
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
            "composer_helper_example": composer_helper_example(
                next_question=next_question,
                current_topic=envelope["normalized_payload"]["current_topic"],
                adapter_status=adapter_status,
            ),
            "brief_version": normalize_text(requirement_brief.get("version")),
            "brief_status": normalize_text(requirement_brief.get("status")) or adapter_status,
            "uploaded_file_count": len(uploaded_files),
        },
    }
    if access_granted:
        response["discovery_runtime_state"] = runtime_state
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
    operator_status = build_operator_status_publication(state_root)
    payload = {
        "status": "ok",
        "service": "agent-factory-web-adapter",
        "demo_domain": normalize_text(settings.get("demo_domain")),
        "public_base_url": normalize_text(settings.get("public_base_url")),
        "access_gate_mode": normalize_text(settings.get("access_gate_mode")),
        "access_gate_configured": bool(settings.get("access_gate_configured")),
        "access_gate_ready": bool(settings.get("access_gate_ready")),
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
