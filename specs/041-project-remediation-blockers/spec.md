# Feature Specification: Project Remediation Blockers

**Feature Branch**: `[fix/project-remediation-blockers]`  
**Created**: 2026-04-21  
**Status**: Draft  
**Input**: User description: "Сделай полное ревью проекта и запланируй speckit совместимые шаги по исправлению всех ошибок и реализуй их. В затруднительных случаях собирай консилиум релевантных экспертов для анализа и принятия решения по ситуации"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Telegram-safe surface never leaks maintenance/runtime internals (Priority: P1)

Пользователь пишет в Telegram про `codex-update`, skill maintenance или root-cause/logs, а бот не показывает `Activity log`, tool traces, host paths и raw runtime errors.

**Why this priority**: Это прямой user-facing blocker, который уже воспроизводился на live surface.

**Independent Test**: `tests/component/test_telegram_safe_llm_guard.sh` и `tests/component/test_telegram_remote_uat_contract.sh`.

**Acceptance Scenarios**:

1. **Given** Telegram-safe maintenance/debug turn по `codex-update` или repo skill, **When** runtime пытается утечь в tool/debug chatter, **Then** delivery переписывается в deterministic boundary reply без внутренних логов.
2. **Given** `/status` или другой safe-text turn в Telegram, **When** live/UAT проверяет ответ, **Then** итоговый ответ остаётся deterministic и без tool fallback.

---

### User Story 2 - Active runtime/deploy surface uses GPT-5.4 OAuth primary with Ollama-only fallback (Priority: P1)

Как оператор, я хочу, чтобы активный runtime/deploy contract не зависел от Z.ai/GLM и не предполагал Anthropic fallback, а держал только `openai-codex::gpt-5.4` как primary и Ollama cloud model как fallback.

**Why this priority**: Пользователь явно запретил Z.ai API-key path и Anthropic fallback в активной поверхности.

**Independent Test**: `tests/static/test_config_validation.sh`, `tests/live_external/test_provider_live.sh`, deploy/preflight checks.

**Acceptance Scenarios**:

1. **Given** tracked config and deploy surface, **When** static validation runs, **Then** active provider/failover contract shows only GPT-5.4 OAuth primary plus Ollama fallback and no active GLM secret requirement.
2. **Given** operator runs provider/live checks, **When** primary and fallback paths are attested, **Then** proof covers both OAuth-backed primary contract and Ollama fallback availability.

---

### User Story 3 - Preflight and GitHub workflows validate the real runtime contract without false negatives or noisy legacy drift (Priority: P1)

Как maintainer, я хочу, чтобы `preflight` и GitHub workflows проверяли текущий runtime contract корректно на macOS/Linux и не шумели stale GLM drift или brittle parsing.

**Why this priority**: Именно эти слои формируют ложные красные сигналы и мешают безопасной посадке изменений.

**Independent Test**: targeted shell tests, `scripts/preflight-check.sh --ci --json`, workflow/static checks.

**Acceptance Scenarios**:

1. **Given** `[providers.ollama] enabled = true` в TOML, **When** `preflight` читает конфиг на macOS/Linux, **Then** он не сообщает ложное `Ollama provider not enabled`.
2. **Given** active deploy/test surface после удаления Z.ai contract, **When** GitHub/static checks run, **Then** они не требуют `GLM_API_KEY` и не ссылаются на retired GLM helpers в active path.

## Edge Cases

- Legacy historical docs/RCA могут упоминать GLM/Z.ai; их нельзя переписывать как историю, но active contracts не должны на них опираться.
- Telegram-safe lane не должен ломать explicit skill CRUD flow (`create_skill/update_skill/delete_skill`) при ужесточении maintenance/debug containment.
- Provider verification не должна доказывать только fallback и игнорировать primary OAuth contract.
- macOS/BSD shell и Linux/GNU shell должны одинаково проходить config parsing checks.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Telegram-safe runtime MUST fail-close for maintenance/debug/log/root-cause turns and MUST not expose `Activity log`, raw tool names, missing-parameter errors, `SKILL.md` paths, or host paths.
- **FR-002**: `/status` and other Telegram-safe deterministic turns MUST remain tool-free and UAT MUST reject malformed provider/model fallback replies.
- **FR-003**: Active runtime/deploy/test surface MUST use `openai-codex::gpt-5.4` as primary contract and MUST keep only Ollama cloud models in failover.
- **FR-004**: Active deploy/test surface MUST NOT require `GLM_API_KEY`, `glm_api_key`, or retired GLM helper scripts.
- **FR-005**: `scripts/preflight-check.sh` MUST parse TOML booleans/strings robustly across macOS/Linux shells without brittle `sed` assumptions.
- **FR-006**: Live/provider verification MUST attest both primary OAuth-backed runtime contract and fallback availability instead of checking only fallback.
- **FR-007**: Blocking remediation MUST be captured in a dedicated Speckit package before runtime code changes and `tasks.md` MUST reflect actual progress.

### Key Entities

- **Telegram-safe Maintenance Turn**: user-facing Telegram turn about repair/debug/log inspection that must be converted into a boundary-safe reply.
- **Active Provider Contract**: current runtime/deploy/test source of truth for primary model/provider and fallback chain.
- **Cross-platform TOML Parse Contract**: shared expectation that config validation behaves identically on macOS/Linux shells.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Targeted Telegram guard/component tests pass for maintenance/debug leak regressions.
- **SC-002**: `scripts/preflight-check.sh --ci --json` no longer reports false-negative Ollama-disabled status when `[providers.ollama].enabled = true`.
- **SC-003**: Active surface static checks pass without `GLM_API_KEY`/retired GLM helper references.
- **SC-004**: Provider/live proof covers both primary OAuth contract and Ollama fallback contract.
