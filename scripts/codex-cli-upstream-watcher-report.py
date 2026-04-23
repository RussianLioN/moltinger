#!/usr/bin/env python3

import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
from html.parser import HTMLParser

mode = sys.argv[1]
state_path = pathlib.Path(sys.argv[2])
release_source_id = sys.argv[3]
release_source_url = sys.argv[4]
release_source_path = pathlib.Path(sys.argv[5])
max_releases = int(sys.argv[6])
include_issue_signals = sys.argv[7] == "true"
issue_source_id = sys.argv[8]
issue_source_url = sys.argv[9]
issue_source_path = pathlib.Path(sys.argv[10])
telegram_enabled = sys.argv[11] == "true"
telegram_chat_id = sys.argv[12]
telegram_env_file = sys.argv[13]
telegram_silent = sys.argv[14] == "true"
delivery_mode = sys.argv[15]
digest_window_hours = int(sys.argv[16])
digest_max_items = int(sys.argv[17])
advisor_bridge_enabled = sys.argv[18] == "true"
advisor_bridge_path = pathlib.Path(sys.argv[19]) if sys.argv[19] else None
telegram_consent_enabled = sys.argv[20] == "true"
telegram_consent_window_hours = int(sys.argv[21])
telegram_consent_router_enabled = sys.argv[22] == "true"
telegram_consent_router_ready = sys.argv[23] == "true"
telegram_allow_getupdates = sys.argv[24] == "true"
updates_source_path = pathlib.Path(sys.argv[25]) if sys.argv[25] else None
warnings = json.loads(sys.argv[26])

checked_dt = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
checked_at = checked_dt.isoformat().replace("+00:00", "Z")


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in {"p", "li", "h1", "h2", "h3", "h4", "section", "div"}:
            self.parts.append("\n")

    def handle_data(self, data):
        stripped = data.strip()
        if stripped:
            self.parts.append(stripped)

    def text(self) -> str:
        text = "".join(self.parts)
        lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
        return "\n".join(line for line in lines if line)


def compact_notes(notes: list[str], limit: int = 10) -> list[str]:
    cleaned = [note for note in notes if note]
    return cleaned[-limit:]


def unique_preserve(items: list[str], limit: int | None = None) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        value = str(item).strip()
        if not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
    if limit is not None:
        return result[-limit:]
    return result


def parse_datetime(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def load_state(path: pathlib.Path) -> tuple[dict, list[str]]:
    default = {
        "last_status": "unknown",
        "notes": [],
        "delivered_fingerprints": [],
        "digest_pending": [],
        "last_update_id": 0,
    }
    notes: list[str] = []
    if not path.is_file():
        return default, notes
    try:
        raw = json.loads(path.read_text())
    except Exception as exc:
        notes.append(f"Не удалось разобрать файл состояния watcher-а: {exc}")
        return default, notes

    if not isinstance(raw, dict):
        notes.append("Файл состояния watcher-а не содержит JSON-объект и был проигнорирован.")
        return default, notes

    state = {
        "last_seen_fingerprint": str(raw.get("last_seen_fingerprint", "")).strip(),
        "last_delivered_fingerprint": str(raw.get("last_delivered_fingerprint", "")).strip(),
        "last_status": str(raw.get("last_status", "unknown")).strip() or "unknown",
        "last_checked_at": str(raw.get("last_checked_at", "")).strip(),
        "notes": [str(item).strip() for item in raw.get("notes", []) if str(item).strip()],
        "delivered_fingerprints": unique_preserve([str(item) for item in raw.get("delivered_fingerprints", [])], 20),
        "last_digest_sent_at": str(raw.get("last_digest_sent_at", "")).strip(),
        "last_update_id": int(raw.get("last_update_id", 0) or 0),
    }

    digest_pending = []
    for item in raw.get("digest_pending", []):
        if not isinstance(item, dict):
            continue
        fingerprint = str(item.get("fingerprint", "")).strip()
        version = str(item.get("version", "")).strip()
        checked = str(item.get("checked_at", "")).strip()
        headline = str(item.get("headline", "")).strip()
        severity = str(item.get("severity", "")).strip() or "info"
        explanations = [str(x).strip() for x in item.get("explanations", []) if str(x).strip()]
        if fingerprint and version and checked:
            digest_pending.append(
                {
                    "fingerprint": fingerprint,
                    "version": version,
                    "checked_at": checked,
                    "headline": headline or f"Вышла версия {version}.",
                    "severity": severity,
                    "explanations": explanations,
                }
            )
    state["digest_pending"] = digest_pending

    return state, notes


def parse_release_source(raw: str, limit: int) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []

    if stripped[0] in "[{":
        data = json.loads(stripped)
        releases = data.get("releases", data if isinstance(data, list) else [])
        normalized = []
        for item in releases:
            changes = item.get("changes", [])
            normalized.append(
                {
                    "version": str(item.get("version", "")).strip(),
                    "published_at": str(item.get("published_at", "")).strip(),
                    "changes": [str(change).strip() for change in changes if str(change).strip()],
                }
            )
        return [item for item in normalized if item["version"]][:limit]

    parser = TextExtractor()
    parser.feed(stripped)
    text = parser.text()
    lines = text.splitlines()

    releases: list[dict] = []
    current = None
    pending_date = ""
    version_pattern = re.compile(r"Codex CLI(?: Release:)?\s*(\d+\.\d+\.\d+)")
    date_pattern = re.compile(r"^\d{4}-\d{2}-\d{2}$")

    for line in lines:
        if date_pattern.match(line):
            pending_date = line
            continue

        match = version_pattern.search(line)
        if match:
            if current:
                releases.append(current)
            current = {
                "version": match.group(1),
                "published_at": pending_date,
                "changes": [],
            }
            pending_date = ""
            continue

        if current is None:
            continue

        if line.lower() in {"new features", "bug fixes", "documentation", "fixes", "improvements"}:
            continue
        if line == "Changelog":
            continue
        if re.search(r"\d+\.\d+\.\d+", line) and "Codex CLI" in line:
            continue
        if line:
            current["changes"].append(line)

    if current:
        releases.append(current)

    cleaned = []
    for item in releases[:limit]:
        deduped = unique_preserve(item["changes"])
        cleaned.append(
            {
                "version": item["version"],
                "published_at": item["published_at"],
                "changes": deduped,
            }
        )
    return cleaned


def parse_issue_signals(raw: str) -> list[dict]:
    stripped = raw.strip()
    if not stripped:
        return []
    data = json.loads(stripped)
    if isinstance(data, list):
        issues = data
    elif isinstance(data, dict):
        issues = data.get("issues", data.get("result", []))
    else:
        issues = []

    normalized = []
    for item in issues:
        if not isinstance(item, dict):
            continue
        if item.get("pull_request"):
            continue
        issue_id = item.get("id") or item.get("number")
        if issue_id is None:
            continue
        normalized.append(
            {
                "id": str(issue_id),
                "title": str(item.get("title", "")).strip(),
                "state": str(item.get("state", "unknown")).strip() or "unknown",
                "url": str(item.get("html_url", item.get("url", ""))).strip(),
            }
        )
    return normalized


def explain_change(change_text: str, advisory: bool = False) -> tuple[str, list[str], str]:
    text = change_text.lower()
    rules = [
        ("critical", ["breaking", "migration", "deprecated", "deprecation", "security", "vulnerability", "incompatible"], "Есть риск несовместимости или усиления требований безопасности; это стоит проверить до обновления.", ["breaking", "security"]),
        ("important", ["approval", "permission profile", "sandbox"], "Изменения затрагивают подтверждение действий и ограничения среды выполнения.", ["approval", "sandbox"]),
        ("important", ["worktree", "/new", "workspace"], "Изменения затрагивают работу с рабочими деревьями и отдельными ветками.", ["worktree"]),
        ("important", ["multi-agent", "multi agent", "resume", "session"], "Изменения затрагивают восстановление сессий и работу с несколькими агентами.", ["agents"]),
        ("important", ["js_repl", "js repl", "repl"], "Изменения затрагивают сценарии с js_repl и встроенными вычислениями.", ["js-repl"]),
        ("important", ["skill", "mcp", "plugin"], "Изменения затрагивают навыки, MCP-интеграции или связанный инструментальный слой.", ["skills", "mcp"]),
        ("info", ["docs", "documentation", "example"], "Обновились документы или примеры использования Codex CLI.", ["docs"]),
    ]

    for level, keywords, explanation, tags in rules:
        if any(keyword in text for keyword in keywords):
            if advisory and level == "info":
                return ("important", "Есть дополнительный сигнал из тикетов Codex CLI; его стоит проверить вместе с changelog.", ["advisory"])
            return level, explanation, tags

    if advisory:
        return ("important", "Есть дополнительный сигнал из тикетов Codex CLI; он не меняет вердикт сам по себе, но усиливает необходимость проверки.", ["advisory"])
    return ("info", "В официальной ленте появилось изменение; подробности сохранены в полном отчёте.", ["generic"])


def build_highlight_explanations(highlights: list[str], advisories: list[dict]) -> tuple[list[str], list[str], str]:
    explanations: list[str] = []
    tags: list[str] = []
    level_rank = {"info": 1, "important": 2, "critical": 3}
    strongest_level = "info"

    for change in highlights[:5]:
        level, explanation, change_tags = explain_change(change)
        explanations.append(explanation)
        tags.extend(change_tags)
        if level_rank[level] > level_rank[strongest_level]:
            strongest_level = level

    for item in advisories[:3]:
        level, explanation, change_tags = explain_change(item["title"], advisory=True)
        explanations.append(explanation)
        tags.extend(change_tags)
        if level_rank[level] > level_rank[strongest_level]:
            strongest_level = level

    explanations = unique_preserve(explanations, 5)
    tags = unique_preserve(tags, 10)
    return explanations, tags, strongest_level


def build_recent_releases(releases: list[dict], advisories: list[dict]) -> list[dict]:
    recent = []
    for index, item in enumerate(releases[:3]):
        explanations, _, strongest = build_highlight_explanations(item["changes"][:5], advisories if index == 0 else [])
        recent.append(
            {
                "version": item["version"],
                "published_at": item["published_at"],
                "change_count": len(item["changes"]),
                "headline": explanations[0] if explanations else f"Вышла версия {item['version']}.",
                "explanations": explanations,
                "severity": strongest,
            }
        )
    return recent


def build_severity(primary_status: str, advisories: list[dict], explanations: list[str], tags: list[str], latest_version: str) -> dict:
    if primary_status != "ok":
        return {
            "level": "investigate",
            "reason": "Нельзя честно оценить важность, пока официальный источник недоступен или сломан.",
        }
    if "breaking" in tags or "security" in tags:
        return {
            "level": "critical",
            "reason": f"Версия {latest_version} выглядит потенциально рискованной: есть признаки несовместимости, миграции или усиления ограничений.",
        }
    if any(tag in tags for tag in ["approval", "sandbox", "worktree", "agents", "js-repl", "advisory"]):
        return {
            "level": "important",
            "reason": f"Версия {latest_version} затрагивает рабочие сценарии, которые этот проект использует регулярно.",
        }
    if explanations:
        return {
            "level": "info",
            "reason": f"В версии {latest_version} есть новые возможности, но без явных признаков срочного риска.",
        }
    return {
        "level": "info",
        "reason": "Свежая версия найдена, но значимых деталей пока мало.",
    }


def build_fingerprint(latest_version: str, highlights: list[str], primary_status: str, advisories: list[dict]) -> str:
    payload = json.dumps(
        {
            "latest_version": latest_version,
            "highlights": highlights[:5],
            "primary_status": primary_status,
            "advisories": [item["id"] for item in advisories[:5]],
        },
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


SUGGESTION_LOCALIZATION = {
    "worktree-guidance": {
        "title": "Проверить правила работы с worktree и топологией веток",
        "rationale": "Новая версия Codex затрагивает сценарии с отдельными worktree, а этот проект активно их использует.",
        "next_steps": [
            "Сверить инструкции по worktree с текущим поведением Codex.",
            "Проверить вспомогательные команды и примеры переключения между ветками.",
        ],
    },
    "approval-profile-review": {
        "title": "Пересмотреть правила approval и sandbox",
        "rationale": "В проекте есть строгие границы по подтверждению действий и sandbox, поэтому обновление может менять ожидания оператора.",
        "next_steps": [
            "Проверить, не изменились ли правила подтверждения опасных действий.",
            "Сверить текущие launch/default-профили с новой версией Codex.",
        ],
    },
    "agent-delegation-review": {
        "title": "Освежить инструкции по мультиагентному режиму и resume-flow",
        "rationale": "Проект опирается на делегирование задач агентам и продолжение сессий, поэтому этот участок особенно чувствителен к изменениям Codex.",
        "next_steps": [
            "Проверить, как теперь ведут себя resume-сценарии и длинные сессии.",
            "Обновить инструкции по делегированию, если они начали расходиться с реальным поведением.",
        ],
    },
    "js-repl-guidance": {
        "title": "Обновить guidance по js_repl",
        "rationale": "В проекте js_repl используется как рабочий инструмент, и новая версия Codex может менять допустимые сценарии или ограничения.",
        "next_steps": [
            "Проверить актуальность примеров и caveats по js_repl.",
            "Уточнить ограничения, если появились новые edge cases.",
        ],
    },
    "skills-surface-review": {
        "title": "Проверить bridge навыков и MCP-интеграции",
        "rationale": "Изменения в навыках, MCP или bridge-слое могут затронуть локальные инструкции и генерацию skill-обвязок.",
        "next_steps": [
            "Проверить, что skill bridge и MCP guidance по-прежнему корректны.",
            "Обновить локальные правила, если поведение capabilities изменилось.",
        ],
    },
    "runbook-refresh": {
        "title": "Обновить runbook и пользовательские примеры",
        "rationale": "После обновления Codex чаще всего первыми устаревают рабочие инструкции и примеры запуска.",
        "next_steps": [
            "Сверить runbook с реальным поведением новой версии.",
            "Освежить примеры команд и последовательности действий.",
        ],
    },
    "investigate-gap": {
        "title": "Сначала разобраться с пробелом в данных monitor/advisor",
        "rationale": "Без надёжного входного сигнала нельзя безопасно давать точные проектные рекомендации.",
        "next_steps": [
            "Починить источник данных monitor/advisor.",
            "Повторно собрать надёжный отчёт перед изменением проектных инструкций.",
        ],
    },
    "codex-runtime-review": {
        "title": "Проверить runtime-guidance Codex для этого проекта",
        "rationale": "Найдены релевантные изменения, но они не попали в более узкий сценарий и требуют ручного разбора.",
        "next_steps": [
            "Посмотреть релевантные пункты changelog и решить, какие правила нужно обновить.",
        ],
    },
}


def localize_suggestion(item: dict) -> dict:
    suggestion_id = str(item.get("id", "")).strip()
    localized = SUGGESTION_LOCALIZATION.get(suggestion_id, {})
    return {
        "id": suggestion_id or "generic",
        "title": localized.get("title", "Проверить применимость изменений Codex к этому проекту"),
        "priority": str(item.get("priority", "medium")).strip() or "medium",
        "rationale": localized.get("rationale", "Есть upstream-изменения Codex, которые стоит соотнести с локальными правилами и процессами проекта."),
        "impacted_paths": [str(path).strip() for path in item.get("impacted_paths", []) if str(path).strip()],
        "next_steps": localized.get(
            "next_steps",
            [step for step in [str(step).strip() for step in item.get("next_steps", [])] if step] or ["Проверить затронутые инструкции и сценарии вручную."],
        ),
    }


def load_advisor_bridge(path: pathlib.Path | None) -> dict:
    if not advisor_bridge_enabled:
        return {
            "enabled": False,
            "status": "disabled",
            "summary": "Практические рекомендации отключены.",
            "top_priorities": [],
            "practical_recommendations": [],
            "notes": [],
            "question": "",
        }

    if path is None or not path.is_file():
        return {
            "enabled": True,
            "status": "unavailable",
            "summary": "Практические рекомендации пока недоступны: bridge к advisor-слою не собран.",
            "top_priorities": [],
            "practical_recommendations": [],
            "notes": ["Advisor bridge не смог подготовить отчёт."],
            "question": "",
        }

    try:
        raw = json.loads(path.read_text())
    except Exception as exc:
        return {
            "enabled": True,
            "status": "investigate",
            "summary": "Практические рекомендации пока недоступны: advisor report не разобрался.",
            "top_priorities": [],
            "practical_recommendations": [],
            "notes": [f"Не удалось разобрать advisor report: {exc}"],
            "question": "",
        }

    practical_recommendations = [
        localize_suggestion(item)
        for item in raw.get("project_change_suggestions", [])
        if isinstance(item, dict)
    ]
    top_priorities = [item["title"] for item in practical_recommendations[:3]]

    if practical_recommendations:
        summary = "Можно подготовить конкретные шаги для этого проекта и связать их с затронутыми файлами."
        status = "ready"
    else:
        summary = "Срочных проектных правок не найдено; можно ограничиться наблюдением за релизом."
        status = "ready"

    return {
        "enabled": True,
        "status": status,
        "summary": summary,
        "top_priorities": top_priorities,
        "practical_recommendations": practical_recommendations,
        "notes": [str(item).strip() for item in raw.get("implementation_brief", {}).get("notes", []) if str(item).strip()],
        "question": "Хотите получить практические рекомендации по применению этих новых возможностей в вашем проекте?",
    }


def build_alert_message(
    latest_version: str,
    severity: dict,
    explanations: list[str],
    decision_reason: str,
    delivery_kind: str,
    digest_entries: list[dict],
    advisor_bridge: dict,
) -> str:
    severity_label = {
        "info": "обычная",
        "important": "высокая",
        "critical": "критическая",
        "investigate": "нужно проверить",
    }.get(severity["level"], severity["level"])
    lines: list[str] = []
    if delivery_kind == "digest":
        lines.extend(
            [
                "Дайджест обновлений Codex CLI",
                f"Накоплено новых upstream-событий: {len(digest_entries)}",
                f"Самая свежая версия: {latest_version}",
                f"Важность: {severity_label}",
                f"Почему это важно: {decision_reason}",
                "Коротко по событиям:",
            ]
        )
        for item in digest_entries[:5]:
            lines.append(f"- {item['version']}: {item['headline']}")
    else:
        lines.extend(
            [
                "Обновление Codex CLI",
                f"Последняя версия из официального источника: {latest_version}",
                f"Важность: {severity_label}",
                f"Почему это важно: {severity['reason']}",
                "Простыми словами:",
            ]
        )
        for explanation in explanations[:4]:
            lines.append(f"- {explanation}")

    if advisor_bridge["status"] == "ready":
        lines.append("Что это может дать проекту:")
        lines.append(f"- {advisor_bridge['summary']}")

    return "\n".join(lines)


previous_state, state_warnings = load_state(state_path)
notes = list(warnings) + state_warnings

primary_notes: list[str] = []
releases: list[dict] = []
primary_status = "unavailable"

if release_source_path.is_file():
    try:
        releases = parse_release_source(release_source_path.read_text(), max_releases)
        if releases:
            primary_status = "ok"
            primary_notes.append(f"Из основного источника разобрано релизов: {len(releases)}.")
        else:
            primary_status = "investigate"
            primary_notes.append("Основной источник прочитан, но релизы Codex CLI из него не разобрались.")
    except Exception as exc:
        primary_status = "investigate"
        primary_notes.append(f"Не удалось разобрать основной источник: {exc}")
else:
    primary_status = "unavailable"
    primary_notes.append("Не удалось получить основной источник.")

advisory_sources: list[dict] = []
advisory_items: list[dict] = []
if include_issue_signals:
    advisory_notes: list[str] = []
    advisory_status = "unavailable"
    if issue_source_path.is_file():
        try:
            advisory_items = parse_issue_signals(issue_source_path.read_text())
            advisory_status = "ok"
            advisory_notes.append(f"Проверено дополнительных сигналов из тикетов: {len(advisory_items)}.")
            if advisory_items:
                advisory_notes.append("Найдены дополнительные сигналы из тикетов; они усиливают контекст, но не меняют официальный вердикт сами по себе.")
        except Exception as exc:
            advisory_status = "investigate"
            advisory_notes.append(f"Не удалось разобрать advisory issue signals: {exc}")
    else:
        advisory_status = "unavailable"
        advisory_notes.append("Не удалось получить источник advisory issue signals.")

    advisory_sources.append(
        {
            "name": "codex-advisory-issues",
            "status": advisory_status,
            "url": issue_source_url,
            "notes": advisory_notes,
        }
    )

latest_version = releases[0]["version"] if releases else "unknown"
highlights = releases[0]["changes"][:5] if releases else []
if releases and not highlights:
    highlights = [f"Опубликован релиз {latest_version}."]

highlight_explanations, explanation_tags, _ = build_highlight_explanations(highlights, advisory_items)
recent_releases = build_recent_releases(releases, advisory_items)
severity = build_severity(primary_status, advisory_items, highlight_explanations, explanation_tags, latest_version)
fingerprint = build_fingerprint(latest_version, highlights, primary_status, advisory_items)

seen_matches = previous_state.get("last_seen_fingerprint", "") == fingerprint
delivered_fingerprints = previous_state.get("delivered_fingerprints", [])
delivered_matches = fingerprint in delivered_fingerprints or previous_state.get("last_delivered_fingerprint", "") == fingerprint
release_status = "unavailable"
if primary_status == "ok":
    release_status = "known" if seen_matches else "new"
elif primary_status == "investigate":
    release_status = "investigate"

advisor_bridge = load_advisor_bridge(advisor_bridge_path)
state = dict(previous_state)
state["notes"] = list(previous_state.get("notes", []))
state["last_checked_at"] = checked_at
state["last_update_id"] = int(previous_state.get("last_update_id", 0) or 0)
state["delivered_fingerprints"] = delivered_fingerprints
state["digest_pending"] = list(previous_state.get("digest_pending", []))
state.pop("pending_consent", None)

recommendations_action = {
    "action": "skip",
    "reason": "Repo-side watcher не владеет интерактивным Telegram follow-up и не отправляет рекомендации напрямую.",
    "text": "",
    "reply_to_message_id": 0,
}
consent_status = "disabled"
consent_reason = (
    "Repo-side Telegram follow-up отключён по официальному контракту Moltis: "
    "Telegram channel сейчас не заявляет interactive components; MessageReceived уже умеет modify/block inbound text, но Command остаётся read-only и безопасного callback UX всё ещё нет."
)
consent_expires_at = ""

decision_status = "investigate"
decision_reason = "Официальная лента изменений сейчас недоступна."
decision_changed = False
alert_action = {"action": "skip", "kind": delivery_mode, "reason": "Отправка не требуется.", "text": "", "delivered_fingerprints": [], "consent_requested": False}

if primary_status == "investigate":
    decision_status = "investigate"
    decision_reason = "Официальная лента изменений вернула неполные или некорректные данные."
    state["last_status"] = "investigate"
elif primary_status == "unavailable":
    decision_status = "investigate"
    decision_reason = "Официальная лента изменений сейчас недоступна."
    state["last_status"] = "investigate"
else:
    decision_changed = not seen_matches
    state["last_seen_fingerprint"] = fingerprint

    current_digest_entry = {
        "fingerprint": fingerprint,
        "version": latest_version,
        "checked_at": checked_at,
        "headline": highlight_explanations[0] if highlight_explanations else f"Вышла версия {latest_version}.",
        "severity": severity["level"] if severity["level"] in {"info", "important", "critical"} else "info",
        "explanations": highlight_explanations,
    }

    if mode == "scheduler" and telegram_enabled:
        if delivery_mode == "digest" and severity["level"] != "critical":
            digest_pending = list(state.get("digest_pending", []))
            pending_fingerprints = {item["fingerprint"] for item in digest_pending}
            if not delivered_matches and fingerprint not in pending_fingerprints:
                digest_pending.append(current_digest_entry)
            state["digest_pending"] = digest_pending

            oldest = parse_datetime(digest_pending[0]["checked_at"]) if digest_pending else None
            digest_due = False
            next_send_after = ""
            if digest_pending and oldest is not None:
                due_dt = oldest + dt.timedelta(hours=digest_window_hours)
                next_send_after = due_dt.isoformat().replace("+00:00", "Z")
                if checked_dt >= due_dt:
                    digest_due = True
            if len(digest_pending) >= digest_max_items:
                digest_due = True

            if digest_due and digest_pending:
                decision_status = "deliver"
                decision_reason = "Накопленный дайджест готов к отправке и не будет спамить отдельными сообщениями."
                state["last_status"] = "queued"
                alert_action = {
                    "action": "send",
                    "kind": "digest",
                    "reason": decision_reason,
                    "text": build_alert_message(
                        latest_version,
                        severity,
                        highlight_explanations,
                        decision_reason,
                        "digest",
                        digest_pending,
                        advisor_bridge,
                    ),
                    "delivered_fingerprints": [item["fingerprint"] for item in digest_pending],
                    "consent_requested": False,
                    "reply_markup_json": "",
                }
            elif delivered_matches and not digest_pending:
                decision_status = "suppress"
                decision_reason = "Это состояние уже было доставлено раньше."
                state["last_status"] = "suppressed"
            else:
                decision_status = "queued"
                decision_reason = "Новое upstream-событие добавлено в очередь дайджеста; отдельное сообщение сейчас не отправляется."
                state["last_status"] = "queued"
        else:
            if not telegram_chat_id:
                decision_status = "investigate"
                decision_reason = "Telegram включён, но chat id определить не удалось."
                state["last_status"] = "investigate"
            elif delivered_matches:
                decision_status = "suppress"
                decision_reason = "Это состояние уже было отправлено в Telegram."
                state["last_status"] = "suppressed"
            else:
                decision_status = "deliver"
                decision_reason = "Найдено новое upstream-состояние; его нужно отправить в Telegram."
                state["last_status"] = "queued"
                alert_action = {
                    "action": "send",
                    "kind": "immediate",
                    "reason": decision_reason,
                    "text": build_alert_message(
                        latest_version,
                        severity,
                        highlight_explanations,
                        decision_reason,
                        "immediate",
                        [current_digest_entry],
                        advisor_bridge,
                    ),
                    "delivered_fingerprints": [fingerprint],
                    "consent_requested": False,
                    "reply_markup_json": "",
                }
    else:
        if seen_matches:
            decision_status = "suppress"
            decision_reason = "Это состояние уже встречалось раньше."
            state["last_status"] = "suppressed"
        else:
            decision_status = "deliver"
            decision_reason = "Найдено новое upstream-состояние."
            state["last_status"] = "delivered"

run_note = f"{checked_at}: {decision_status} ({decision_reason})"
state["notes"] = compact_notes(previous_state.get("notes", []) + [run_note])

feature_explanation = [
    "Уровень важности показывает, это обычное обновление, важное изменение рабочего процесса или потенциально рискованный релиз.",
    "Режим дайджеста собирает несколько upstream-событий в одно сообщение и уменьшает шум в Telegram.",
    "Repo-side watcher остаётся producer/notifier: для Telegram он отправляет только one-way alert и не обещает интерактивный follow-up.",
]

followup_digest = {
    "mode": delivery_mode,
    "pending_count": len(state.get("digest_pending", [])),
    "last_sent_at": str(state.get("last_digest_sent_at", "")).strip(),
    "pending_items": state.get("digest_pending", []),
}
if delivery_mode == "digest" and state.get("digest_pending"):
    oldest_pending = parse_datetime(state["digest_pending"][0]["checked_at"])
    if oldest_pending is not None:
        followup_digest["next_send_after"] = (oldest_pending + dt.timedelta(hours=digest_window_hours)).isoformat().replace("+00:00", "Z")

pending_consent_state = None

report = {
    "checked_at": checked_at,
    "feature_explanation": feature_explanation,
    "snapshot": {
        "latest_version": latest_version,
        "release_status": release_status,
        "primary_source": {
            "name": "codex-changelog",
            "status": primary_status,
            "url": release_source_url,
            "notes": primary_notes,
        },
        "advisory_sources": advisory_sources,
        "advisory_items": advisory_items,
        "highlights": highlights,
        "highlight_explanations": highlight_explanations,
        "recent_releases": recent_releases,
    },
    "fingerprint": fingerprint,
    "severity": severity,
    "decision": {
        "status": decision_status,
        "reason": decision_reason,
        "changed": decision_changed,
        "delivery_mode": delivery_mode,
    },
    "advisor_bridge": advisor_bridge,
    "telegram_target": {
        "enabled": telegram_enabled,
        "consent_enabled": telegram_consent_enabled,
        "consent_router_enabled": telegram_consent_router_enabled,
        "consent_router_ready": telegram_consent_router_ready,
    },
    "followup": {
        "digest": followup_digest,
        "consent": {
            "status": consent_status,
            "reason": consent_reason,
            "expires_at": consent_expires_at,
            "question": advisor_bridge["question"],
            "router_mode": "one_way_only",
            "pending_state": pending_consent_state,
        },
    },
    "automation": {
        "alert": alert_action,
        "recommendations": recommendations_action,
    },
    "state": state,
    "notes": compact_notes(
        notes
        + [f"Режим: {'ручной' if mode == 'manual' else 'по расписанию'}."]
        + [f"Режим доставки: {'сразу' if delivery_mode == 'immediate' else 'дайджест'}."]
        + ([f"Определён идентификатор чата Telegram: {telegram_chat_id}."] if telegram_chat_id else [])
        + ([f"Использован файл окружения Telegram: {telegram_env_file}."] if telegram_env_file else [])
    ),
}

if telegram_chat_id:
    report["telegram_target"]["chat_id"] = telegram_chat_id
if telegram_silent:
    report["telegram_target"]["silent"] = True
if telegram_env_file:
    report["telegram_target"]["env_file"] = telegram_env_file

print(json.dumps(report, indent=2))
