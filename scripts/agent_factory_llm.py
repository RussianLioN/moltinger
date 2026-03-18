#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Any
from urllib import error, request

from agent_factory_common import normalize_text


DEFAULT_BASE_URL = "https://api.fireworks.ai/inference/v1"
DEFAULT_MODEL = "accounts/fireworks/models/glm-5"


class LLMError(RuntimeError):
    """Base error for web-demo LLM orchestration."""


class LLMConfigError(LLMError):
    """Raised when runtime LLM configuration is incomplete."""


class LLMRequestError(LLMError):
    """Raised when the provider request fails."""


class LLMResponseError(LLMError):
    """Raised when provider response cannot be parsed."""


@dataclass(frozen=True)
class LLMSettings:
    enabled: bool
    api_key: str
    base_url: str
    model_name: str
    timeout_seconds: float
    temperature: float
    max_tokens: int

    @property
    def configured(self) -> bool:
        return bool(self.api_key and self.base_url and self.model_name)


def _env_bool(*names: str, default: bool = False) -> bool:
    truthy = {"1", "true", "yes", "y", "on", "enable", "enabled"}
    falsy = {"0", "false", "no", "n", "off", "disable", "disabled"}
    for name in names:
        raw = normalize_text(os.environ.get(name))
        if not raw:
            continue
        value = raw.lower()
        if value in truthy:
            return True
        if value in falsy:
            return False
    return default


def _env_float(*names: str, default: float) -> float:
    for name in names:
        raw = normalize_text(os.environ.get(name))
        if not raw:
            continue
        try:
            parsed = float(raw)
        except ValueError:
            continue
        if parsed > 0:
            return parsed
    return default


def _env_int(*names: str, default: int) -> int:
    for name in names:
        raw = normalize_text(os.environ.get(name))
        if not raw:
            continue
        try:
            parsed = int(raw)
        except ValueError:
            continue
        if parsed > 0:
            return parsed
    return default


def llm_settings_from_env() -> LLMSettings:
    return LLMSettings(
        enabled=_env_bool("ASC_DEMO_LLM_ENABLED", "LLM_ENABLED", default=False),
        api_key=normalize_text(os.environ.get("OPENAI_API_KEY"))
        or normalize_text(os.environ.get("ASC_DEMO_OPENAI_API_KEY"))
        or normalize_text(os.environ.get("FIREWORKS_API_KEY"))
        or normalize_text(os.environ.get("GLM_API_KEY")),
        base_url=normalize_text(os.environ.get("OPENAI_BASE_URL"))
        or normalize_text(os.environ.get("ASC_DEMO_OPENAI_BASE_URL"))
        or DEFAULT_BASE_URL,
        model_name=normalize_text(os.environ.get("MODEL_NAME"))
        or normalize_text(os.environ.get("ASC_DEMO_MODEL_NAME"))
        or DEFAULT_MODEL,
        timeout_seconds=_env_float("ASC_DEMO_LLM_TIMEOUT_SECONDS", "LLM_TIMEOUT_SECONDS", default=18.0),
        temperature=_env_float("ASC_DEMO_LLM_TEMPERATURE", "LLM_TEMPERATURE", default=0.1),
        max_tokens=_env_int("ASC_DEMO_LLM_MAX_TOKENS", "LLM_MAX_TOKENS", default=350),
    )


def _chat_completions_url(base_url: str) -> str:
    normalized = normalize_text(base_url).rstrip("/")
    if normalized.endswith("/chat/completions"):
        return normalized
    if normalized.endswith("/completions"):
        return normalized
    if normalized.endswith("/v1"):
        return f"{normalized}/chat/completions"
    return f"{normalized}/v1/chat/completions"


def _normalize_message_content(value: Any) -> str:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        chunks: list[str] = []
        for item in value:
            if isinstance(item, dict):
                text = normalize_text(item.get("text"))
                if text:
                    chunks.append(text)
        return "\n".join(chunks).strip()
    return ""


def _extract_choice_text(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    message = first.get("message")
    if isinstance(message, dict):
        return _normalize_message_content(message.get("content"))
    text = first.get("text")
    if isinstance(text, str):
        return text.strip()
    return ""


def _strip_code_fence(text: str) -> str:
    value = normalize_text(text)
    if not value.startswith("```"):
        return value
    return re.sub(r"^```[a-zA-Z0-9_-]*\s*", "", value).rstrip("`").strip()


def _parse_json_object(raw_text: str) -> dict[str, Any]:
    text = _strip_code_fence(raw_text)
    if not text:
        raise LLMResponseError("llm empty response text")
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    first = text.find("{")
    last = text.rfind("}")
    if first < 0 or last <= first:
        raise LLMResponseError("llm response is not a json object")
    try:
        parsed = json.loads(text[first : last + 1])
    except json.JSONDecodeError as exc:
        raise LLMResponseError(f"llm json parse failed: {exc}") from exc
    if not isinstance(parsed, dict):
        raise LLMResponseError("llm response parsed but object expected")
    return parsed


def chat_completion_json(
    *,
    system_prompt: str,
    user_prompt: str,
    settings: LLMSettings,
) -> dict[str, Any]:
    if not settings.enabled:
        raise LLMConfigError("llm disabled by environment")
    if not settings.configured:
        raise LLMConfigError("llm is enabled but OPENAI_API_KEY/OPENAI_BASE_URL/MODEL_NAME is incomplete")

    endpoint = _chat_completions_url(settings.base_url)
    payload = {
        "model": settings.model_name,
        "messages": [
            {"role": "system", "content": normalize_text(system_prompt)},
            {"role": "user", "content": normalize_text(user_prompt)},
        ],
        "temperature": settings.temperature,
        "max_tokens": settings.max_tokens,
    }
    raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        endpoint,
        data=raw,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {settings.api_key}",
        },
    )
    try:
        with request.urlopen(req, timeout=settings.timeout_seconds) as resp:  # noqa: S310
            response_bytes = resp.read()
    except error.HTTPError as exc:  # pragma: no cover - hard to trigger hermetically
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="ignore")
        except Exception:  # noqa: BLE001
            detail = ""
        short = normalize_text(detail)[:300]
        raise LLMRequestError(f"llm provider http {exc.code}: {short or exc.reason}") from exc
    except error.URLError as exc:  # pragma: no cover - network dependent
        raise LLMRequestError(f"llm provider request failed: {normalize_text(exc.reason) or exc}") from exc
    except TimeoutError as exc:  # pragma: no cover - network dependent
        raise LLMRequestError("llm provider request timed out") from exc

    try:
        decoded = json.loads(response_bytes.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise LLMResponseError("llm provider returned non-json payload") from exc
    if not isinstance(decoded, dict):
        raise LLMResponseError("llm provider returned unexpected payload type")

    content = _extract_choice_text(decoded)
    if not content:
        raise LLMResponseError("llm provider returned empty choice content")
    return _parse_json_object(content)
