#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_FACTORY_PATTERNS = [
    "telegram-intake",
    "synchronized-concept-pack",
    "defense-gate",
    "swarm-to-playground",
]

DEFAULT_NON_GOALS = [
    "Production deployment in MVP0",
    "Live business data in playground",
    "Implicit approval without defense outcome",
]

DEFAULT_EXTERNAL_DEPENDENCIES = [
    "Telegram Bot API",
    "Moltis/Moltinger runtime",
    "ASC in-repo mirror",
]

DEFAULT_REQUESTED_DECISION = "Подтвердить концепцию для перехода к defense и последующему playground production path."

DEFAULT_NEXT_STEP_SUMMARY = "После согласования concept pack направляется на защиту концепции."

ALIGNMENT_PREFIX = "<!-- agent-factory-alignment"
ALIGNMENT_SUFFIX = "-->"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: str | Path) -> Any:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(data: Any, output_path: str | Path | None = None) -> None:
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if output_path is None:
        print(text, end="")
        return
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    return str(value).strip()


def normalize_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [normalize_text(item) for item in value if normalize_text(item)]
    text = normalize_text(value)
    if not text:
        return []
    if "\n" in text:
        parts = re.split(r"\n+", text)
    else:
        parts = re.split(r"\s*,\s*", text)
    return [part.strip(" -") for part in parts if part.strip(" -")]


def dedupe_preserve_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for value in values:
        text = normalize_text(value)
        if not text or text in seen:
            continue
        seen.add(text)
        ordered.append(text)
    return ordered


def slugify(value: str, fallback_prefix: str = "concept") -> str:
    text = normalize_text(value).lower()
    ascii_text = text.encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_text).strip("-")
    if slug and len(slug) >= 5:
        return slug[:80]
    digest = hashlib.sha1(text.encode("utf-8")).hexdigest()[:10]
    return f"{fallback_prefix}-{digest}"


def bump_minor_version(version: str) -> str:
    text = normalize_text(version)
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", text)
    if not match:
        raise ValueError(f"unsupported concept version format: {version}")
    major, minor, _patch = (int(part) for part in match.groups())
    return f"{major}.{minor + 1}.0"


def next_artifact_revision(revision: str) -> str:
    text = normalize_text(revision)
    match = re.fullmatch(r"r(\d+)", text)
    if not match:
        raise ValueError(f"unsupported artifact revision format: {revision}")
    return f"r{int(match.group(1)) + 1}"


def trim_words(text: str, limit: int) -> str:
    words = normalize_text(text).split()
    if not words:
        return ""
    if len(words) <= limit:
        return " ".join(words)
    return " ".join(words[:limit]).rstrip(",.;:") + "..."


def to_bullets(values: list[str], fallback: str = "- Not specified") -> str:
    if not values:
        return fallback
    return "\n".join(f"- {value}" for value in values)


def to_paragraphs(values: list[str], fallback: str = "Not specified") -> str:
    if not values:
        return fallback
    return "\n\n".join(values)


def render_template(template_path: str | Path, context: dict[str, str]) -> str:
    text = Path(template_path).read_text(encoding="utf-8")

    def replace(match: re.Match[str]) -> str:
        key = match.group(1).strip()
        return context.get(key, "")

    return re.sub(r"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}", replace, text)


def build_alignment_payload(
    concept_record: dict[str, Any],
    artifact_context: dict[str, Any],
    artifact_revision: str,
) -> dict[str, Any]:
    return {
        "concept_id": concept_record["concept_id"],
        "concept_version": concept_record["current_version"],
        "artifact_revision": artifact_revision,
        "agent_name": artifact_context["agent_name"],
        "problem_statement": concept_record["problem_statement"],
        "success_metrics": concept_record["success_metrics"],
        "constraints": concept_record["constraints"],
        "open_risks": concept_record["open_risks"],
        "requested_decision": artifact_context["requested_decision"],
    }


def alignment_digest(payload: dict[str, Any]) -> str:
    serialized = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()


def alignment_comment(artifact_type: str, payload: dict[str, Any]) -> str:
    digest = alignment_digest(payload)
    lines = [
        ALIGNMENT_PREFIX,
        f"artifact_type={artifact_type}",
        f"concept_id={payload['concept_id']}",
        f"concept_version={payload['concept_version']}",
        f"artifact_revision={payload['artifact_revision']}",
        f"sync_hash={digest}",
        ALIGNMENT_SUFFIX,
    ]
    return "\n".join(lines) + "\n"


def parse_alignment_comment(text: str) -> dict[str, str]:
    match = re.search(r"<!-- agent-factory-alignment\n(.*?)\n-->", text, re.S)
    if not match:
        return {}
    payload: dict[str, str] = {}
    for raw_line in match.group(1).splitlines():
        line = raw_line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        payload[key.strip()] = value.strip()
    return payload
