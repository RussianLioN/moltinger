#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import mimetypes
import subprocess
import sys
import tempfile
from copy import deepcopy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

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
    for dirname in ("sessions", "access", "history", "downloads"):
        (state_root / dirname).mkdir(parents=True, exist_ok=True)


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
    resume_ready = bool(discovery_state) and normalize_text(web_demo_session.get("web_demo_session_id"))
    granted = False
    message = ""

    if resume_ready and normalize_text(web_demo_session.get("status")) not in {"gate_pending", "error"}:
        granted = True
        if not normalize_text(grant.get("grant_type")):
            grant["grant_type"] = "allowlisted_session"
        if not normalize_text(grant.get("status")):
            grant["status"] = "active"
    elif normalize_text(grant.get("status")) == "active" and (
        normalize_text(grant.get("grant_value")) or normalize_text(grant.get("grant_value_hash"))
    ):
        granted = True
    else:
        message = "Укажи активный demo access token, чтобы открыть рабочую сессию фабрики."

    grant["granted"] = granted
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
    now: str,
) -> tuple[dict[str, Any], bool]:
    ui_action = normalize_text(envelope.get("ui_action"))
    user_text = normalize_text(envelope.get("user_text"))
    request = seed_discovery_request(payload, discovery_state, requester_identity)
    current_topic = normalize_text(
        request.get("discovery_session", {}).get("current_topic")
        if isinstance(request.get("discovery_session"), dict)
        else ""
    ) or normalize_text(request.get("next_topic"))
    request["project_key"] = normalize_text(pointer.get("project_key")) or normalize_text(web_demo_session.get("active_project_key"))

    if ui_action == "request_status" and discovery_state:
        return request, True

    if ui_action in {"request_brief_review"} and discovery_state:
        return request, True

    if ui_action == "start_project":
        request["raw_idea"] = user_text or normalize_text(payload.get("raw_idea"))
    elif ui_action == "submit_turn":
        captured_answers = request.get("captured_answers", {})
        if not isinstance(captured_answers, dict):
            captured_answers = {}
        if current_topic and user_text:
            captured_answers[current_topic] = user_text
        elif user_text and not normalize_text(request.get("raw_idea")):
            request["raw_idea"] = user_text
        request["captured_answers"] = captured_answers
        append_user_turn(request, user_text, current_topic, now)
    elif ui_action == "request_brief_correction":
        request["brief_feedback_text"] = user_text or normalize_text(payload.get("brief_feedback_text"))
        if isinstance(payload.get("brief_section_updates"), dict):
            request["brief_section_updates"] = deepcopy(payload["brief_section_updates"])
    elif ui_action == "confirm_brief":
        request["confirmation_reply"] = build_confirmation_reply(user_text, requester_identity)
    elif ui_action == "reopen_brief":
        request["brief_feedback_text"] = user_text or "Нужно переоткрыть brief и уточнить детали."
        if isinstance(payload.get("brief_section_updates"), dict):
            request["brief_section_updates"] = deepcopy(payload["brief_section_updates"])

    return request, False


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


def persist_adapter_state(state_root: Path, response: dict[str, Any], access_gate: dict[str, Any]) -> None:
    ensure_state_layout(state_root)
    session_id = normalize_text(response.get("web_demo_session", {}).get("web_demo_session_id"))
    request_id = normalize_text(response.get("web_conversation_envelope", {}).get("request_id"))
    if session_id:
        write_json(response, state_root / "sessions" / f"{session_id}.json")
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

    access_granted, access_gate, access_message = access_gate_result(payload, discovery_state, web_demo_session, now)
    web_demo_session["access_grant_id"] = normalize_text(access_gate.get("demo_access_grant_id"))

    download_artifacts: list[dict[str, Any]] = []
    runtime_state: dict[str, Any] = {}
    delivery_error = ""
    if access_granted:
        discovery_request, skip_runtime = build_discovery_request(
            payload,
            discovery_state,
            requester_identity,
            envelope,
            web_demo_session,
            pointer,
            now,
        )
        runtime_state = discovery_state if skip_runtime and discovery_state else run_discovery_runtime(discovery_request)
        runtime_state = sanitize_discovery_runtime_state(runtime_state)
        download_artifacts = sanitize_download_artifacts(
            payload.get("download_artifacts"),
            web_demo_session_id=normalize_text(web_demo_session.get("web_demo_session_id")),
        )
        if not download_artifacts:
            download_artifacts = sanitize_download_artifacts(
                saved_session.get("download_artifacts"),
                web_demo_session_id=normalize_text(web_demo_session.get("web_demo_session_id")),
            )
        if not download_artifacts and normalize_text(envelope.get("ui_action")) in {"request_status", "download_artifact"}:
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
    status_snapshot = build_web_demo_status_snapshot(
        web_demo_session.get("web_demo_session_id"),
        pointer.get("project_key"),
        adapter_status=adapter_status,
        next_action=next_action,
        brief=requirement_brief,
        now=now,
        download_artifacts=download_artifacts,
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

    envelope["linked_discovery_session_id"] = normalize_text(pointer.get("linked_discovery_session_id"))
    envelope["linked_brief_id"] = normalize_text(pointer.get("linked_brief_id"))
    envelope["normalized_payload"] = {
        "ui_action": normalize_text(envelope.get("ui_action")),
        "project_key": normalize_text(pointer.get("project_key")),
        "current_topic": normalize_text(discovery_session.get("current_topic")) or next_topic,
        "request_channel": "web",
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
        },
        "web_demo_session": web_demo_session,
        "browser_project_pointer": pointer,
        "web_conversation_envelope": envelope,
        "status_snapshot": status_snapshot,
        "reply_cards": reply_cards,
        "audit_record": audit_record,
        "ui_projection": {
            "preferred_ui_action": preferred_ui_action(reply_cards, fallback="request_status" if access_granted else "submit_access_token"),
            "current_question": next_question,
            "current_topic": envelope["normalized_payload"]["current_topic"],
            "project_title": normalize_text(pointer.get("project_key")) or "Новый проект фабрики",
            "brief_version": normalize_text(requirement_brief.get("version")),
            "brief_status": normalize_text(requirement_brief.get("status")) or adapter_status,
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


def serve(host: str, port: int, *, state_root: Path, assets_root: Path) -> int:
    ensure_state_layout(state_root)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
            return

        def do_GET(self) -> None:  # noqa: N802
            parsed = urlparse(self.path)
            if parsed.path in {"/health", "/api/health"}:
                render_json(self, {"status": "ok", "service": "agent-factory-web-adapter"})
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
                render_json(self, session)
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
