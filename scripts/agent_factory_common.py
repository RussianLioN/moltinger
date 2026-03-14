#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from copy import deepcopy
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

DISCOVERY_TOPIC_SPECS = [
    {
        "name": "problem",
        "category": "problem",
        "question": "Какую конкретную бизнес-проблему должен решить будущий агент?",
        "blocking": True,
        "aliases": ["problem", "target_business_problem", "business_problem", "pain_point", "raw_problem_statement"],
    },
    {
        "name": "target_users",
        "category": "actor",
        "question": "Кто будет основным пользователем или выгодоприобретателем результата?",
        "blocking": True,
        "aliases": ["target_users", "users", "beneficiaries"],
    },
    {
        "name": "current_workflow",
        "category": "workflow",
        "question": "Как этот процесс работает сейчас и где основные потери?",
        "blocking": True,
        "aliases": ["current_workflow", "current_workflow_summary", "workflow", "current_process"],
    },
    {
        "name": "desired_outcome",
        "category": "goal",
        "question": "Какой результат должен получать бизнес после автоматизации?",
        "blocking": True,
        "aliases": ["desired_outcome", "goal", "desired_result"],
    },
    {
        "name": "user_story",
        "category": "user_story",
        "question": "Какому сотруднику и в какой ситуации агент должен помогать в первую очередь?",
        "blocking": False,
        "aliases": ["user_story"],
    },
    {
        "name": "input_examples",
        "category": "input",
        "question": "Приведи 1-2 типовых примера входных данных или ситуаций, с которыми агент будет работать.",
        "blocking": False,
        "aliases": ["input_examples", "example_inputs", "examples"],
    },
    {
        "name": "expected_outputs",
        "category": "output",
        "question": "Что пользователь должен получить на выходе по итогам обработки?",
        "blocking": False,
        "aliases": ["expected_outputs", "output_examples", "desired_outputs"],
    },
    {
        "name": "constraints",
        "category": "constraint",
        "question": "Какие ограничения, запреты или исключения нужно учитывать?",
        "blocking": True,
        "aliases": ["constraints", "constraints_or_exclusions", "exclusions"],
    },
    {
        "name": "success_metrics",
        "category": "success_metric",
        "question": "По каким признакам поймем, что решение действительно приносит пользу?",
        "blocking": True,
        "aliases": ["success_metrics", "measurable_success_expectation", "metrics"],
    },
]

DISCOVERY_AMBIGUOUS_MARKERS = (
    "не знаю",
    "пока не знаю",
    "еще не решили",
    "ещё не решили",
    "надо подумать",
    "пока не уверен",
    "пока не уверена",
    "требует уточнения",
    "нужно уточнить",
    "unknown",
    "tbd",
)

DISCOVERY_RESOLVED_STATUSES = {"clarified", "confirmed"}
DISCOVERY_PENDING_STATUSES = {"unasked", "partial", "unresolved"}
DISCOVERY_UNSAFE_EXAMPLE_PATTERNS = (
    re.compile(r"\b\d{10,}\b"),
    re.compile(r"\b(?:iban|swift|bik|инн|кпп|огрн|снилс|паспорт)\b", re.I),
    re.compile(r"\b(?:р/с|расчетный счет|расч[её]тный сч[её]т|номер карты|банковск(?:ие|ий) реквизит)\b", re.I),
)
DISCOVERY_SYNTHETIC_EXAMPLE_MARKERS = ("synthetic", "синтетич", "тестов")
DISCOVERY_SANITIZED_EXAMPLE_MARKERS = ("sanitized", "обезлич", "без реальных", "маскиров")
DISCOVERY_CONTRADICTION_RULESETS = [
    {
        "id": "approval_vs_escalation",
        "context_keywords": ("эскал", "дополнительного согласования", "доп. согласования", "нужна проверка руководителя"),
        "conflict_keywords": ("автоматически одобр", "сразу одобр", "без согласования", "мгновенно пропустить"),
        "message": "Правила требуют эскалации или дополнительного согласования, а ожидаемый результат описан как автоматическое одобрение.",
    },
    {
        "id": "blocked_vs_pass_through",
        "context_keywords": ("не должна проходить дальше", "нельзя пропускать дальше", "блокиров", "обязательных документов"),
        "conflict_keywords": ("пропустить дальше", "автоматически принять", "одобрить заявку", "разрешить оплату"),
        "message": "Пример ожидаемого результата противоречит правилу блокировки или обязательной проверки документов.",
    },
    {
        "id": "no_auto_reply_vs_auto_reply",
        "context_keywords": ("без автоматической отправки ответа", "не отправлять ответ клиенту", "без автоответа"),
        "conflict_keywords": ("автоматически отправить ответ", "автоответ клиенту", "сразу ответить клиенту"),
        "message": "Ограничения запрещают автоответ, но пример ожидает автоматическую отправку ответа клиенту.",
    },
    {
        "id": "text_only_vs_document_example",
        "context_keywords": ("только текстовые обращения", "без вложений", "без документов"),
        "conflict_keywords": ("pdf", "скан", "фото", "изображен", "вложен"),
        "message": "Ограничения описывают текстовый-only сценарий, а пример требует обработку документов или вложений.",
    },
]


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


def normalize_dict_list(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    return [dict(item) for item in value if isinstance(item, dict)]


def upsert_history_entry(
    history: list[dict[str, Any]],
    entry: dict[str, Any],
    *,
    id_field: str,
) -> list[dict[str, Any]]:
    entry_id = normalize_text(entry.get(id_field))
    normalized_history = normalize_dict_list(history)
    if not entry_id:
        return normalized_history

    updated_history: list[dict[str, Any]] = []
    replaced = False
    for existing in normalized_history:
        if normalize_text(existing.get(id_field)) == entry_id:
            updated_history.append(dict(entry))
            replaced = True
            continue
        updated_history.append(dict(existing))
    if not replaced:
        updated_history.append(dict(entry))
    return updated_history


def archive_confirmation_snapshot(
    snapshot: dict[str, Any],
    history: list[dict[str, Any]],
    *,
    now: str,
    superseded_by_brief_version: str = "",
    brief_snapshot: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    if not isinstance(snapshot, dict) or not snapshot:
        return normalize_dict_list(history)

    archived_snapshot = dict(snapshot)
    if normalize_text(archived_snapshot.get("status")) == "active":
        archived_snapshot["status"] = "superseded"
    archived_snapshot["superseded_at"] = now
    if superseded_by_brief_version:
        archived_snapshot["superseded_by_brief_version"] = superseded_by_brief_version
    if isinstance(brief_snapshot, dict) and brief_snapshot:
        archived_snapshot["brief_snapshot"] = deepcopy(brief_snapshot)
    return upsert_history_entry(
        history,
        archived_snapshot,
        id_field="confirmation_snapshot_id",
    )


def archive_handoff_record(
    record: dict[str, Any],
    history: list[dict[str, Any]],
    *,
    now: str,
    superseded_by_brief_version: str = "",
) -> list[dict[str, Any]]:
    if not isinstance(record, dict) or not record:
        return normalize_dict_list(history)

    archived_record = dict(record)
    previous_status = normalize_text(archived_record.get("handoff_status"))
    if previous_status and previous_status != "superseded":
        archived_record["previous_handoff_status"] = previous_status
    archived_record["handoff_status"] = "superseded"
    archived_record["superseded_at"] = now
    if superseded_by_brief_version:
        archived_record["superseded_by_brief_version"] = superseded_by_brief_version
    return upsert_history_entry(
        history,
        archived_record,
        id_field="factory_handoff_id",
    )


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


def discovery_topic_specs() -> list[dict[str, Any]]:
    return [dict(spec) for spec in DISCOVERY_TOPIC_SPECS]


def discovery_topic_names(*, blocking_only: bool = False) -> list[str]:
    return [spec["name"] for spec in DISCOVERY_TOPIC_SPECS if not blocking_only or spec["blocking"]]


def canonical_discovery_topic_name(name: Any) -> str:
    text = normalize_text(name).lower().replace("-", "_").replace(" ", "_")
    if not text:
        return ""
    for spec in DISCOVERY_TOPIC_SPECS:
        if text == spec["name"]:
            return spec["name"]
        if text in {alias.lower().replace("-", "_").replace(" ", "_") for alias in spec["aliases"]}:
            return spec["name"]
    return ""


def discovery_topic_question(topic_name: str) -> str:
    canonical = canonical_discovery_topic_name(topic_name)
    for spec in DISCOVERY_TOPIC_SPECS:
        if spec["name"] == canonical:
            return spec["question"]
    return ""


def discovery_topic_category(topic_name: str) -> str:
    canonical = canonical_discovery_topic_name(topic_name)
    for spec in DISCOVERY_TOPIC_SPECS:
        if spec["name"] == canonical:
            return spec["category"]
    return ""


def discovery_topic_is_blocking(topic_name: str) -> bool:
    canonical = canonical_discovery_topic_name(topic_name)
    for spec in DISCOVERY_TOPIC_SPECS:
        if spec["name"] == canonical:
            return bool(spec["blocking"])
    return False


def discovery_text_blob(*values: Any) -> str:
    parts: list[str] = []
    for value in values:
        if isinstance(value, list):
            parts.extend(normalize_list(value))
            continue
        text = normalize_text(value)
        if text:
            parts.append(text)
    return " ".join(parts)


def discovery_summary(value: Any) -> str:
    if isinstance(value, list):
        return "; ".join(dedupe_preserve_order(normalize_list(value)))
    text = normalize_text(value)
    if not text:
        return ""
    if "\n" in text:
        parts = normalize_list(text)
        if parts:
            return "; ".join(dedupe_preserve_order(parts))
    return trim_words(text, 28)


def discovery_example_data_safety_status(*values: Any) -> str:
    text = discovery_text_blob(*values).lower()
    if not text:
        return "sanitized"
    if any(marker in text for marker in DISCOVERY_SYNTHETIC_EXAMPLE_MARKERS):
        return "synthetic"
    if any(marker in text for marker in DISCOVERY_SANITIZED_EXAMPLE_MARKERS):
        return "sanitized"
    for pattern in DISCOVERY_UNSAFE_EXAMPLE_PATTERNS:
        if pattern.search(text):
            return "needs_redaction"
    return "sanitized"


def discovery_example_contradictions(
    *,
    input_summary: Any,
    expected_output_summary: Any,
    linked_rules: Any = None,
    business_rules: Any = None,
    constraints: Any = None,
    exception_notes: Any = None,
) -> list[str]:
    context_text = discovery_text_blob(linked_rules, business_rules, constraints, exception_notes).lower()
    output_text = discovery_text_blob(input_summary, expected_output_summary).lower()
    contradictions: list[str] = []
    if not context_text or not output_text:
        return contradictions
    for ruleset in DISCOVERY_CONTRADICTION_RULESETS:
        if any(keyword in context_text for keyword in ruleset["context_keywords"]) and any(
            keyword in output_text for keyword in ruleset["conflict_keywords"]
        ):
            contradictions.append(ruleset["message"])
    return dedupe_preserve_order(contradictions)


def discovery_value_present(value: Any) -> bool:
    if isinstance(value, list):
        return len(normalize_list(value)) > 0
    return bool(normalize_text(value))


def discovery_value_is_ambiguous(value: Any) -> bool:
    text = discovery_summary(value).lower()
    if not text:
        return False
    return any(marker in text for marker in DISCOVERY_AMBIGUOUS_MARKERS)


def discovery_topic_status(value: Any, existing_status: str = "") -> str:
    status = normalize_text(existing_status)
    if status == "confirmed":
        return "confirmed"
    if status == "unresolved":
        return "unresolved"
    if not discovery_value_present(value):
        return "unasked"
    if status == "clarified":
        return "clarified"
    summary = discovery_summary(value)
    if discovery_value_is_ambiguous(value):
        return "partial"
    if len(summary.split()) < 4:
        return "partial"
    return "clarified"


def discovery_topic_is_resolved(status: Any) -> bool:
    return normalize_text(status) in DISCOVERY_RESOLVED_STATUSES


def build_discovery_topic(
    topic_name: str,
    value: Any,
    now: str,
    *,
    existing_topic: dict[str, Any] | None = None,
    source_turn_ids: list[str] | None = None,
) -> dict[str, Any]:
    canonical = canonical_discovery_topic_name(topic_name)
    if not canonical:
        raise ValueError(f"unsupported discovery topic: {topic_name}")

    existing = existing_topic or {}
    summary = discovery_summary(value) or normalize_text(existing.get("summary"))
    existing_status = normalize_text(existing.get("status"))
    existing_summary = normalize_text(existing.get("summary"))
    if existing_status in {"confirmed", "clarified", "partial", "unresolved"} and summary == existing_summary:
        status = existing_status
    else:
        status = discovery_topic_status(summary, existing_status)
        if existing_status == "unresolved" and summary:
            status = "unresolved"

    return {
        "topic_id": normalize_text(existing.get("topic_id")) or f"topic-{canonical}",
        "topic_name": canonical,
        "category": discovery_topic_category(canonical),
        "status": status,
        "summary": summary,
        "source_turn_ids": source_turn_ids if source_turn_ids is not None else list(existing.get("source_turn_ids", [])),
        "last_updated_at": now,
    }


def discovery_topic_sort_rank(status: Any) -> int:
    normalized = normalize_text(status)
    ranks = {
        "unasked": 0,
        "unresolved": 1,
        "partial": 2,
        "clarified": 3,
        "confirmed": 4,
    }
    return ranks.get(normalized, 99)


def discovery_next_topic(requirement_topics: list[dict[str, Any]]) -> str:
    topics_by_name = {
        canonical_discovery_topic_name(topic.get("topic_name")): topic for topic in requirement_topics if canonical_discovery_topic_name(topic.get("topic_name"))
    }
    for status in ("unasked", "unresolved", "partial"):
        for topic_name in discovery_topic_names():
            topic = topics_by_name.get(topic_name)
            if topic and normalize_text(topic.get("status")) == status:
                return topic_name
    return ""


def build_discovery_topic_progress(
    requirement_topics: list[dict[str, Any]],
    clarification_items: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    clarifications = [item for item in clarification_items or [] if normalize_text(item.get("status")) == "open"]
    topics_by_name = {
        canonical_discovery_topic_name(topic.get("topic_name")): topic for topic in requirement_topics if canonical_discovery_topic_name(topic.get("topic_name"))
    }
    ordered_topics = [topics_by_name[name] for name in discovery_topic_names() if name in topics_by_name]
    resolved_topics = [topic["topic_name"] for topic in ordered_topics if discovery_topic_is_resolved(topic.get("status"))]
    partial_topics = [topic["topic_name"] for topic in ordered_topics if normalize_text(topic.get("status")) == "partial"]
    unresolved_topics = [topic["topic_name"] for topic in ordered_topics if normalize_text(topic.get("status")) == "unresolved"]
    unasked_topics = [topic["topic_name"] for topic in ordered_topics if normalize_text(topic.get("status")) == "unasked"]
    remaining_topics = [topic["topic_name"] for topic in ordered_topics if not discovery_topic_is_resolved(topic.get("status"))]
    blocking_topics_remaining = [name for name in remaining_topics if discovery_topic_is_blocking(name)]

    return {
        "total_topics": len(ordered_topics),
        "resolved_topics": len(resolved_topics),
        "partial_topics": len(partial_topics),
        "unresolved_topics": len(unresolved_topics),
        "unasked_topics": len(unasked_topics),
        "clarification_count": len(clarifications),
        "resolved_topic_names": resolved_topics,
        "remaining_topics": remaining_topics,
        "blocking_topics_remaining": blocking_topics_remaining,
        "ready_for_brief": len(remaining_topics) == 0 and len(clarifications) == 0,
    }

def sha256_hex(value: Any) -> str:
    text = normalize_text(value)
    if not text:
        return ""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def normalize_download_artifacts(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [dict(item) for item in value if isinstance(item, dict)]

    if not isinstance(value, dict):
        return []

    manifest = value
    source_provenance = manifest.get("source_provenance", {}) if isinstance(manifest.get("source_provenance"), dict) else {}
    artifacts = manifest.get("artifacts", {}) if isinstance(manifest.get("artifacts"), dict) else {}
    download_artifacts: list[dict[str, Any]] = []

    for artifact_kind, artifact_entry in artifacts.items():
        if not isinstance(artifact_entry, dict):
            continue
        download_artifacts.append(
            {
                "artifact_kind": artifact_kind,
                "download_name": normalize_text(artifact_entry.get("download_name")) or f"{artifact_kind}.md",
                "download_ref": normalize_text(artifact_entry.get("download_ref")),
                "download_status": "available" if normalize_text(artifact_entry.get("download_ref")) else "pending",
                "project_key": normalize_text(source_provenance.get("project_key")),
                "brief_version": normalize_text(source_provenance.get("brief_version")),
            }
        )

    return download_artifacts


def web_user_visible_status(
    adapter_status: Any,
    *,
    next_action: Any = "",
    needs_operator_attention: bool = False,
    download_artifacts: list[dict[str, Any]] | None = None,
) -> str:
    if needs_operator_attention:
        return "needs_attention"

    artifacts = normalize_download_artifacts(download_artifacts or [])
    if artifacts and all(normalize_text(item.get("download_status")) in {"available", "ready"} for item in artifacts):
        return "downloads_ready"

    status = normalize_text(adapter_status)
    action = normalize_text(next_action)
    if status in {"gate_pending", "error", "blocked"}:
        return "needs_attention"
    if status == "awaiting_clarification":
        return "awaiting_clarification"
    if status in {"awaiting_confirmation", "reopened"}:
        return "awaiting_confirmation"
    if status == "confirmed":
        return "confirmed"
    if status == "download_ready" or action in {"generate_artifacts", "publish_downloads"}:
        return "downloads_ready"
    if action in {"run_factory_intake", "return_to_brief_confirmation"}:
        return "handoff_running"
    return "discovery_in_progress"


def web_user_visible_status_label(status: Any) -> str:
    normalized = normalize_text(status)
    if normalized == "needs_attention":
        return "Нужно внимание"
    if normalized == "awaiting_clarification":
        return "Нужно уточнение"
    if normalized == "awaiting_confirmation":
        return "Brief ждёт подтверждения"
    if normalized == "confirmed":
        return "Brief подтвержден"
    if normalized == "handoff_running":
        return "Фабрика обрабатывает brief"
    if normalized == "downloads_ready":
        return "Артефакты готовы"
    return "Сбор требований продолжается"


def web_next_action_label(action: Any) -> str:
    normalized = normalize_text(action)
    if normalized == "request_demo_access":
        return "Открыть demo-доступ"
    if normalized == "ask_next_question":
        return "Ответить на следующий вопрос"
    if normalized == "resolve_clarification":
        return "Уточнить недостающие детали"
    if normalized in {"request_explicit_confirmation", "await_for_confirmation", "confirm_brief"}:
        return "Проверить и подтвердить brief"
    if normalized == "request_brief_correction":
        return "Уточнить brief"
    if normalized in {"run_factory_intake", "start_concept_pack_handoff"}:
        return "Передать brief в фабрику"
    if normalized == "generate_artifacts":
        return "Подготовить concept pack"
    if normalized in {"publish_downloads", "download_artifact"}:
        return "Скачать артефакты"
    if normalized == "request_status":
        return "Обновить статус"
    if normalized == "return_to_brief_confirmation":
        return "Вернуться к подтверждению brief"
    return "Ждать следующего шага"


def web_download_readiness(
    *,
    adapter_status: Any,
    needs_operator_attention: bool = False,
    download_artifacts: list[dict[str, Any]] | None = None,
) -> str:
    if needs_operator_attention:
        return "blocked"
    artifacts = normalize_download_artifacts(download_artifacts or [])
    if artifacts and all(normalize_text(item.get("download_status")) in {"available", "ready"} for item in artifacts):
        return "ready"
    status = normalize_text(adapter_status)
    if status in {"confirmed", "awaiting_confirmation", "download_ready"}:
        return "pending"
    return "not_ready"


def web_session_runtime_status(
    adapter_status: Any,
    *,
    next_action: Any = "",
    needs_operator_attention: bool = False,
    download_artifacts: list[dict[str, Any]] | None = None,
) -> str:
    if needs_operator_attention:
        return "gate_pending"
    readiness = web_download_readiness(
        adapter_status=adapter_status,
        needs_operator_attention=needs_operator_attention,
        download_artifacts=download_artifacts,
    )
    if readiness == "ready":
        return "download_ready"

    status = normalize_text(adapter_status)
    action = normalize_text(next_action)
    if status in {"error", "blocked"}:
        return "error"
    if status in {"awaiting_confirmation", "reopened"}:
        return "awaiting_confirmation"
    if status in {"awaiting_user_reply", "awaiting_clarification"}:
        return "awaiting_user_reply"
    if action in {"run_factory_intake", "generate_artifacts", "publish_downloads"}:
        return "handoff_running"
    if status == "confirmed":
        return "completed"
    return "active"


def build_web_demo_status_snapshot(
    web_demo_session_id: Any,
    project_key: Any,
    *,
    adapter_status: Any,
    next_action: Any,
    brief: dict[str, Any] | None,
    now: str,
    download_artifacts: list[dict[str, Any]] | None = None,
    needs_operator_attention: bool = False,
) -> dict[str, Any]:
    artifacts = normalize_download_artifacts(download_artifacts or [])
    user_visible_status = web_user_visible_status(
        adapter_status,
        next_action=next_action,
        needs_operator_attention=needs_operator_attention,
        download_artifacts=artifacts,
    )
    next_action_label = web_next_action_label(next_action)
    return {
        "web_demo_status_snapshot_id": f"status-{normalize_text(web_demo_session_id) or normalize_text(project_key) or 'web-demo'}",
        "web_demo_session_id": normalize_text(web_demo_session_id),
        "project_key": normalize_text(project_key),
        "user_visible_status": user_visible_status,
        "user_visible_status_label": web_user_visible_status_label(user_visible_status),
        "next_recommended_action": normalize_text(next_action),
        "next_recommended_action_label": next_action_label,
        "brief_version": normalize_text((brief or {}).get("version")),
        "download_readiness": web_download_readiness(
            adapter_status=adapter_status,
            needs_operator_attention=needs_operator_attention,
            download_artifacts=artifacts,
        ),
        "needs_operator_attention": needs_operator_attention,
        "captured_at": now,
    }


def build_web_reply_card(
    card_kind: str,
    *,
    title: str,
    body_text: str,
    web_demo_session_id: Any = "",
    section_id: str = "",
    action_hints: list[str] | None = None,
    linked_discovery_session_id: Any = "",
    linked_brief_id: Any = "",
    linked_handoff_id: Any = "",
    now: str = "",
) -> dict[str, Any]:
    now_value = now or utc_now()
    return {
        "web_reply_card_id": f"card-{slugify(f'{card_kind}-{title}-{now_value}', 'web-card')}",
        "web_demo_session_id": normalize_text(web_demo_session_id),
        "card_kind": card_kind,
        "title": normalize_text(title),
        "body_text": normalize_text(body_text),
        "section_id": normalize_text(section_id),
        "action_hints": dedupe_preserve_order(action_hints or []),
        "linked_discovery_session_id": normalize_text(linked_discovery_session_id),
        "linked_brief_id": normalize_text(linked_brief_id),
        "linked_handoff_id": normalize_text(linked_handoff_id),
        "created_at": now_value,
    }


def build_brief_preview_cards(
    brief: dict[str, Any],
    *,
    adapter_status: Any = "",
    web_demo_session_id: Any = "",
    linked_discovery_session_id: Any = "",
    linked_handoff_id: Any = "",
    now: str = "",
) -> list[dict[str, Any]]:
    if not isinstance(brief, dict) or not brief:
        return []

    brief_status = normalize_text(brief.get("status")) or normalize_text(adapter_status)
    is_confirmable = brief_status in {"awaiting_confirmation", "reopened"}
    version = normalize_text(brief.get("version")) or "без версии"
    section_actions = ["request_brief_correction", "confirm_brief"] if is_confirmable else ["reopen_brief", "request_status"]
    constraints = normalize_list(brief.get("constraints"))
    success_metrics = normalize_list(brief.get("success_metrics"))
    target_users = normalize_list(brief.get("target_users"))
    scope_boundaries = normalize_list(brief.get("scope_boundaries"))
    input_examples = normalize_list(brief.get("input_examples"))
    expected_outputs = normalize_list(brief.get("expected_outputs"))
    business_rules = normalize_list(brief.get("business_rules"))
    exceptions = normalize_list(brief.get("exceptions"))
    open_risks = normalize_list(brief.get("open_risks"))

    def multi_section_body(*sections: tuple[str, list[str] | str]) -> str:
        rendered: list[str] = []
        for title, value in sections:
            if isinstance(value, str):
                text_value = normalize_text(value)
                if text_value:
                    rendered.append(f"{title}:\n{text_value}")
                continue
            normalized_items = normalize_list(value)
            if normalized_items:
                rendered.append(f"{title}:\n{to_bullets(normalized_items)}")
        return "\n\n".join(rendered)

    cards = [
        build_web_reply_card(
            "brief_summary_section",
            title=f"Версия brief {version}",
            body_text=(
                f"Сейчас на проверке версия {version}. "
                "Проверь summary ниже, попроси правки обычным текстом или явно подтверди текущую редакцию."
                if is_confirmable
                else f"Текущая подтвержденная версия brief: {version}. При необходимости можно переоткрыть её и выпустить новую редакцию."
            ),
            web_demo_session_id=web_demo_session_id,
            section_id="brief_version",
            action_hints=section_actions,
            linked_discovery_session_id=linked_discovery_session_id,
            linked_brief_id=brief.get("brief_id"),
            linked_handoff_id=linked_handoff_id,
            now=now,
        ),
        build_web_reply_card(
            "brief_summary_section",
            title="Проблема и желаемый результат",
            body_text=multi_section_body(
                ("Проблема", normalize_text(brief.get("problem_statement")) or "Проблема ещё не зафиксирована."),
                ("Желаемый результат", normalize_text(brief.get("desired_outcome")) or "Результат ещё не описан."),
            ),
            web_demo_session_id=web_demo_session_id,
            section_id="problem_outcome",
            action_hints=section_actions,
            linked_discovery_session_id=linked_discovery_session_id,
            linked_brief_id=brief.get("brief_id"),
            linked_handoff_id=linked_handoff_id,
            now=now,
        ),
        build_web_reply_card(
            "brief_summary_section",
            title="Пользователи и процесс",
            body_text=multi_section_body(
                ("Кто пользуется результатом", target_users),
                ("Текущий процесс", normalize_text(brief.get("current_process"))),
            )
            or "Пользователи и текущий процесс ещё не описаны.",
            web_demo_session_id=web_demo_session_id,
            section_id="users_process",
            action_hints=section_actions,
            linked_discovery_session_id=linked_discovery_session_id,
            linked_brief_id=brief.get("brief_id"),
            linked_handoff_id=linked_handoff_id,
            now=now,
        ),
        build_web_reply_card(
            "brief_summary_section",
            title="User story и границы",
            body_text=multi_section_body(
                ("User story", normalize_text(brief.get("user_story"))),
                ("Границы scope", scope_boundaries),
            )
            or "User story и границы решения ещё не заполнены.",
            web_demo_session_id=web_demo_session_id,
            section_id="user_story_scope",
            action_hints=section_actions,
            linked_discovery_session_id=linked_discovery_session_id,
            linked_brief_id=brief.get("brief_id"),
            linked_handoff_id=linked_handoff_id,
            now=now,
        ),
        build_web_reply_card(
            "brief_summary_section",
            title="Примеры входов и выходов",
            body_text=multi_section_body(
                ("Входные примеры", input_examples),
                ("Ожидаемые выходы", expected_outputs),
            )
            or "Примеры входов и выходов ещё не собраны.",
            web_demo_session_id=web_demo_session_id,
            section_id="examples",
            action_hints=section_actions,
            linked_discovery_session_id=linked_discovery_session_id,
            linked_brief_id=brief.get("brief_id"),
            linked_handoff_id=linked_handoff_id,
            now=now,
        ),
        build_web_reply_card(
            "brief_summary_section",
            title="Правила, исключения и риски",
            body_text=multi_section_body(
                ("Бизнес-правила", business_rules),
                ("Исключения", exceptions),
                ("Открытые риски", open_risks),
            )
            or "Правила, исключения и риски ещё не зафиксированы.",
            web_demo_session_id=web_demo_session_id,
            section_id="rules_exceptions_risks",
            action_hints=section_actions,
            linked_discovery_session_id=linked_discovery_session_id,
            linked_brief_id=brief.get("brief_id"),
            linked_handoff_id=linked_handoff_id,
            now=now,
        ),
    ]
    if constraints or success_metrics:
        cards.append(
            build_web_reply_card(
                "brief_summary_section",
                title="Ограничения и метрики",
                body_text=multi_section_body(
                    ("Ограничения", constraints),
                    ("Метрики успеха", success_metrics),
                ),
                web_demo_session_id=web_demo_session_id,
                section_id="constraints_success_metrics",
                action_hints=section_actions,
                linked_discovery_session_id=linked_discovery_session_id,
                linked_brief_id=brief.get("brief_id"),
                linked_handoff_id=linked_handoff_id,
                now=now,
            )
        )
    return cards


def build_web_reply_cards(
    runtime_response: dict[str, Any],
    *,
    web_demo_session_id: Any,
    access_granted: bool,
    now: str,
    download_artifacts: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    session_id = normalize_text(web_demo_session_id)
    discovery_session = runtime_response.get("discovery_session", {}) if isinstance(runtime_response.get("discovery_session"), dict) else {}
    requirement_brief = runtime_response.get("requirement_brief", {}) if isinstance(runtime_response.get("requirement_brief"), dict) else {}
    factory_handoff = runtime_response.get("factory_handoff_record", {}) if isinstance(runtime_response.get("factory_handoff_record"), dict) else {}
    next_question = normalize_text(runtime_response.get("next_question"))
    adapter_status = normalize_text(runtime_response.get("status"))
    next_action = normalize_text(runtime_response.get("next_action"))

    status_snapshot = build_web_demo_status_snapshot(
        session_id,
        normalize_text(discovery_session.get("project_key")) or normalize_text(requirement_brief.get("project_key")),
        adapter_status=adapter_status,
        next_action=next_action,
        brief=requirement_brief,
        now=now,
        download_artifacts=download_artifacts,
        needs_operator_attention=not access_granted,
    )

    cards = [
        build_web_reply_card(
            "status_update",
            title="Статус проекта",
            body_text=(
                "Сессия активна. "
                f"{status_snapshot['user_visible_status_label']}. "
                f"Следующий шаг: {status_snapshot['next_recommended_action_label'].lower()}."
            )
            if access_granted
            else "Нужно подтвердить доступ к demo surface, прежде чем открывать проект.",
            web_demo_session_id=session_id,
            action_hints=["request_status"],
            linked_discovery_session_id=discovery_session.get("discovery_session_id"),
            linked_brief_id=requirement_brief.get("brief_id"),
            linked_handoff_id=factory_handoff.get("factory_handoff_id"),
            now=now,
        )
    ]

    if not access_granted:
        cards.append(
            build_web_reply_card(
                "error_message",
                title="Нужен код доступа",
                body_text="Укажи валидный код доступа к демо, чтобы фабрика открыла активный проект и продолжила discovery.",
                web_demo_session_id=session_id,
                action_hints=["submit_access_token"],
                now=now,
            )
        )
        return cards

    cards.extend(
        build_brief_preview_cards(
            requirement_brief,
            adapter_status=adapter_status,
            web_demo_session_id=session_id,
            linked_discovery_session_id=discovery_session.get("discovery_session_id"),
            linked_handoff_id=factory_handoff.get("factory_handoff_id"),
            now=now,
        )
        if status_snapshot["user_visible_status"] in {"awaiting_confirmation", "confirmed"}
        else []
    )

    artifacts = normalize_download_artifacts(download_artifacts or [])
    if artifacts:
        artifact_names = ", ".join(item["download_name"] for item in artifacts if normalize_text(item.get("download_name")))
        cards.append(
            build_web_reply_card(
                "download_prompt",
                title="Артефакты готовы",
                body_text=f"Можно скачать: {artifact_names}.",
                web_demo_session_id=session_id,
                action_hints=["download_artifact"],
                linked_discovery_session_id=discovery_session.get("discovery_session_id"),
                linked_brief_id=requirement_brief.get("brief_id"),
                linked_handoff_id=factory_handoff.get("factory_handoff_id"),
                now=now,
            )
        )
        return cards

    if status_snapshot["user_visible_status"] == "awaiting_confirmation":
        cards.append(
            build_web_reply_card(
                "confirmation_prompt",
                title=f"Подтвердить brief {normalize_text(requirement_brief.get('version')) or 'без версии'}",
                body_text=next_question
                or (
                    f"Проверь summary и явно подтверди версию {normalize_text(requirement_brief.get('version')) or 'без версии'}. "
                    "Если нужны изменения, попроси правки обычным текстом или переоткрой brief."
                ),
                web_demo_session_id=session_id,
                action_hints=["request_brief_correction", "confirm_brief", "reopen_brief"],
                linked_discovery_session_id=discovery_session.get("discovery_session_id"),
                linked_brief_id=requirement_brief.get("brief_id"),
                linked_handoff_id=factory_handoff.get("factory_handoff_id"),
                now=now,
            )
        )
    elif status_snapshot["user_visible_status"] == "confirmed":
        cards.append(
            build_web_reply_card(
                "status_update",
                title="Brief подтвержден",
                body_text=(
                    f"Зафиксирована версия {normalize_text(requirement_brief.get('version')) or 'без версии'}. "
                    "Следующий этап фабрики может использовать только эту подтвержденную редакцию."
                ),
                web_demo_session_id=session_id,
                action_hints=["request_status", "reopen_brief"],
                linked_discovery_session_id=discovery_session.get("discovery_session_id"),
                linked_brief_id=requirement_brief.get("brief_id"),
                linked_handoff_id=factory_handoff.get("factory_handoff_id"),
                now=now,
            )
        )
    elif next_question:
        cards.append(
            build_web_reply_card(
                "clarification_prompt" if next_action == "resolve_clarification" else "discovery_question",
                title="Нужно уточнение" if next_action == "resolve_clarification" else "Следующий вопрос",
                body_text=next_question,
                web_demo_session_id=session_id,
                action_hints=["submit_turn"],
                linked_discovery_session_id=discovery_session.get("discovery_session_id"),
                linked_brief_id=requirement_brief.get("brief_id"),
                linked_handoff_id=factory_handoff.get("factory_handoff_id"),
                now=now,
            )
        )
    return cards
