# Feature Specification: Fallback LLM with Ollama Sidecar

**Feature Branch**: `001-fallback-llm-ollama`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "Добавить Fallback LLM для Moltis с использованием Ollama Sidecar + Circuit Breaker"

## Overview

Реализовать отказоустойчивый fallback механизм для Moltis, который автоматически переключается на Ollama с моделью Gemini-3-flash-preview при недоступности основного провайдера GLM-5 (Z.ai).

**Problem**: При падении GLM API — Moltis полностью неработоспособен (КРИТИЧЕСКАЯ ПРОБЛЕМА).

**Solution**: Ollama Sidecar контейнер + Circuit Breaker pattern для автоматического failover.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Failover on GLM Outage (Priority: P1)

Как пользователь Moltis, я хочу, чтобы система автоматически переключалась на резервный LLM при недоступности основного провайдера, чтобы я мог продолжать работу без прерываний.

**Why this priority**: Это критическая функциональность - без неё система полностью неработоспособна при сбое GLM.

**Independent Test**: Можно протестировать, симулировав недоступность GLM API и проверив, что запросы автоматически направляются в Ollama.

**Acceptance Scenarios**:

1. **Given** GLM API недоступен (timeout/error), **When** пользователь отправляет запрос к Moltis, **Then** запрос автоматически перенаправляется в Ollama с Gemini
2. **Given** GLM API восстановлен после сбоя, **When** circuit breaker переходит в half-open state, **Then** система автоматически возвращается к GLM
3. **Given** оба провайдера недоступны, **When** пользователь отправляет запрос, **Then** система возвращает понятную ошибку с информацией о статусе

---

### User Story 2 - Health Monitoring & Observability (Priority: P2)

Как администратор системы, я хочу видеть метрики и статус LLM провайдеров, чтобы мониторить здоровье системы и реагировать на инциденты.

**Why this priority**: Важно для operations, но не блокирует базовую функциональность failover.

**Independent Test**: Можно протестировать, проверив что метрики корректно отображаются в Prometheus.

**Acceptance Scenarios**:

1. **Given** система работает, **When** запрашиваются метрики, **Then** возвращаются `llm_provider_available{provider="glm"}` и `llm_provider_available{provider="ollama"}`
2. **Given** произошёл failover, **When** запрашивается метрика, **Then** `llm_fallback_triggered_total` увеличивается
3. **Given** GLM недоступен > 5 минут, **When** срабатывает alert, **Then** администратор получает уведомление

---

### User Story 3 - CI/CD Validation (Priority: P3)

Как DevOps инженер, я хочу, чтобы конфигурация failover валидировалась в CI/CD pipeline, чтобы предотвратить деплой некорректной конфигурации.

**Why this priority**: Улучшает качество деплоя, но не влияет на runtime функциональность.

**Independent Test**: Можно протестировать, добавив некорректную конфигурацию и проверив, что CI pipeline падает.

**Acceptance Scenarios**:

1. **Given** Ollama provider enabled в config, **When** запускается preflight check, **Then** валидируется наличие OLLAMA_API_KEY
2. **Given** failover configuration изменена, **When** запускается verify job, **Then** выполняется smoke test failover
3. **Given** некорректная TOML конфигурация, **When** запускается CI, **Then** pipeline падает с понятной ошибкой

---

### Edge Cases

- Что происходит при одновременном отказе GLM и Ollama?
- Как система обрабатывает race conditions при множественных instance?
- Что происходит при cold start Ollama (первая загрузка модели ~30-60s)?
- Как обрабатываются timeout при медленном ответе GLM?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST запускать Ollama как sidecar-контейнер в docker-compose.prod.yml
- **FR-002**: System MUST автоматически переключаться на Ollama при недоступности GLM API
- **FR-003**: System MUST реализовывать Circuit Breaker pattern с состояниями (CLOSED, OPEN, HALF-OPEN)
- **FR-004**: System MUST проверять health обоих провайдеров с интервалом 5 секунд
- **FR-005**: System MUST автоматически возвращаться к GLM при восстановлении (graceful recovery)
- **FR-006**: System MUST сохранять state failover в `/tmp/moltis-llm-state.json`
- **FR-007**: System MUST экспортировать метрики для Prometheus (`llm_fallback_triggered_total`, `llm_provider_available`)
- **FR-008**: System MUST валидировать Ollama конфигурацию в preflight job CI/CD
- **FR-009**: System MUST выполнять smoke tests для failover в verify job CI/CD
- **FR-010**: System MUST управлять OLLAMA_API_KEY через Docker secrets

### Non-Functional Requirements

- **NFR-001**: Resource limits для Ollama: 4 CPUs, 8GB RAM
- **NFR-002**: RTO (Recovery Time Objective) < 5 минут
- **NFR-003**: SLI Availability: 99.5% (включая fallback)
- **NFR-004**: SLI Latency: P95 < 5s для GLM, P95 < 15s для Ollama fallback
- **NFR-005**: GitOps compliant: вся конфигурация в git, secrets через Docker secrets

### Key Entities

- **LLM Provider**: Сущность, представляющая LLM провайдера (GLM или Ollama). Атрибуты: name, status (available/unavailable), latency, error_count
- **Circuit Breaker State**: Текущее состояние circuit breaker. Атрибуты: state (CLOSED/OPEN/HALF-OPEN), failure_count, last_failure_time, last_success_time
- **Failover Event**: Событие переключения между провайдерами. Атрибуты: timestamp, from_provider, to_provider, reason

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: При падении GLM API, система переключается на Ollama за < 30 секунд (3 consecutive failures × 5s interval + processing time)
- **SC-002**: При восстановлении GLM, система возвращается к primary провайдеру за < 5 минут (half-open test cycle)
- **SC-003**: Метрики failover доступны в Prometheus и корректно отображают состояние провайдеров
- **SC-004**: CI/CD pipeline падает при некорректной конфигурации Ollama (validation работает)
- **SC-005**: Smoke tests в verify job проходят успешно при корректной конфигурации

## Assumptions

- OLLAMA_API_KEY будет получен пользователем через подписку на ollama.com
- Сервер имеет достаточно ресурсов (4+ CPUs, 8GB+ RAM) для Ollama контейнера
- Moltis поддерживает множественные LLM providers через конфигурацию
- GLM API имеет health endpoint или можно определить availability по response status

## Out of Scope

- Локальные модели Ollama (только cloud модели)
- Prometheus exporter (Phase 2)
- Grafana dashboard (Phase 2)
- Multi-instance coordination (distributed circuit breaker)
- Rate limiting для LLM API calls

## Dependencies

- Docker Compose v2.0+
- Ollama official image: `ollama/ollama:latest`
- OLLAMA_API_KEY secret
- Moltis failover configuration support

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ollama cold start (~60s) | High | Предзагрузка модели при старте контейнера |
| Memory competition с Moltis | Medium | Resource limits для Ollama (8GB) |
| Race conditions при failover | Medium | File locking для state file |
| GLM API false positives | Low | Настройка timeout и retry logic |

## References

- Consilium Report: `docs/reports/consilium/2026-03-01-fallback-llm-architecture.md`
- Ollama Cloud Documentation: https://ollama.com/library/gemini-3-flash-preview
- Circuit Breaker Pattern: https://martinfowler.com/bliki/CircuitBreaker.html
