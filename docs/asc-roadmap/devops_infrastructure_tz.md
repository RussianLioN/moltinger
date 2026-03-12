[🏠 Главная](../README.md) | [📑 Навигация](./INDEX.md) | [📖 Глоссарий](./GLOSSARY.md)

---

# ТЗ для DevOps: Настройка GPU-сервера для GLM-4.7 Inference

**Версия**: v1.0
**Дата**: 2026-01-19
**Статус**: Утверждено
**Ответственный**: DevOps команда

---

## Обзор

Данный документ представляет собой техническое задание для команды DevOps по настройке сервера с 8× GPU для запуска инференса модели **GLM-4.7** (355B MoE, 200K контекст) в рамках проекта ASC AI Fabrique.

**Связь с дорожной картой**: Данный ТЗ охватывает [Веху 0.1.3: Настройка среды разработки](./strategic_roadmap.md#веха-013-настройка-среды-разработки) из [Фазы 0: MVP0](./strategic_roadmap.md#фаза-0-быстрое-прототипирование-mvp0-4-недель).

---

## Исполнительное резюме

### Цель
Обеспечить рабочую инфраструктуру для запуска GLM-4.7 на сервере с 8× GPU для поддержки разработки мультиагентной системы ASC AI Fabrique.

### Критические требования
- **Модель**: GLM-4.7 (355B MoE, 32B активных параметров)
- **Контекст**: 200,000 токенов (официально)
- **Inference Engine**: vLLM с OpenAI-совместимым API
- **Доступ**: 1-5 пользователей в фазе 0

### Сроки
- Подготовка сервера: по согласованию (запрос минимальных сроков)
- Настройка и тестирование: 4 недели

---

## Часть 1: Запрос к подразделению, предоставляющему ЦОД

### Формальное ТЗ на подготовку сервера

**Кому**: Подразделению, предоставляющему ЦОД
**От**: Команды разработки ASC AI Fabrique
**Дата**: Январь 2026
**Цель**: Подготовка сервера для запуска инференса модели GLM-4.7

#### Требования к серверу

```
┌─────────────────────────────────────────────────────────────┐
│  GPU Сервер для инференса GLM-4.7 (355B MoE)               │
├─────────────────────────────────────────────────────────────┤
│  CPU:     2× AMD EPYC 9554 (128 ядер) или аналогичный       │
│  RAM:     2 ТБ DDR5 ECC                                     │
│  GPU:     8× NVIDIA A100 80GB SXM (минимум)                 │
│           или 8× NVIDIA H100 80GB SXM (предпочтительно)     │
│  NVLink:  3.0 (A100) или 4.0 (H100) - критично!            │
│  NVMe:    20 ТБ PCIe 4.0+                                   │
│  Сеть:    2× 100 Гбит/с с изоляцией VLAN                    │
│  Доступ:  SSH root + 3-5 user accounts                      │
└─────────────────────────────────────────────────────────────┘
```

#### Требования к ПО (предустановка)

| Компонент | Версия | Примечание |
|-----------|--------|------------|
| **ОС** | Ubuntu 22.04 LTS или Rocky Linux 9 | Стабильная версия |
| **NVIDIA Driver** | 525+ (A100) или 535+ (H100) | Последняя стабильная |
| **CUDA** | 12.1+ | Для поддержки H100 |
| **Docker** | 24.0+ | С nvidia-container-toolkit |
| **SSH** | OpenSSH 8.9+ | Для 1-5 пользователей |

#### Сетевые требования

- Выделенная VLAN или изолированная подсеть
- Белый список IP для SSH доступа (корпоративная сеть)
- Открытый порт 8000 для vLLM API (внутренний)
- Опционально: VPN доступ извне

#### Сроки
- Подготовка сервера: по согласованию (запрос минимально возможных сроков)
- Установка ПО: по согласованию
- Тестовый доступ: после готовности

---

## Часть 2: Технические спецификации GLM-4.7

### Характеристики модели

```
Модель: GLM-4.7 (355B MoE, 32B активных на инференс)
Архитектура: Mixture-of-Experts (MoE)
Контекст: 200,000 токенов (официально)
Макс. вывод: 128,000 токенов
Провайдер: Zhipu AI (Z.AI)
Репозиторий: zai-org/GLM-4.7 на HuggingFace
```

### Рекомендуемые конфигурации

#### Вариант 1: FP8 (рекомендуется) — 4 GPU

| Параметр | Значение |
|----------|----------|
| Формат | FP8 (потеря точности <1%) |
| Память | ~140-160 ГБ |
| GPU | ~4× H100 80GB или ~2× A100 80GB |
| Tensor Parallelism | 2-4 GPU |
| Производительность | Максимальная |

#### Вариант 2: BF16 — 8 GPU

| Параметр | Значение |
|----------|----------|
| Формат | BF16 (полная точность) |
| Память | ~280-320 ГБ |
| GPU | ~4× H100 80GB или ~4× A100 80GB |
| Tensor Parallelism | 4-8 GPU |
| Производительность | Высокая |

#### Вариант 3: AWQ 4bit — 2-3 GPU

| Параметр | Значение |
|----------|----------|
| Формат | AWQ 4bit (потеря точности 7-10%) |
| Память | ~70-90 ГБ |
| GPU | ~1-2× H100 80GB или ~2× A100 80GB |
| Tensor Parallelism | 2 GPU |
| Производительность | Хорошая |
| Примечание | Для FP8/BF16 предпочтительнее |

### Важные примечания по GLM-4.7

1. **Контекст 200K**: GLM-4.7 официально поддерживает 200,000 токенов контекста
2. **MoE архитектура**: Только 32B из 355B параметров активны на инференс
3. **FP8 поддержка**: Официально поддерживается vLLM с минимальной потерей точности
4. **Tool Calling**: Нативная поддержка function calling и MCP
5. **Мультиязычность**: Полная поддержка русского и английского языков

---

## Часть 3: Настройка vLLM для GLM-4.7

### Вариант 1: FP8 (рекомендуется)

```bash
vllm serve zai-org/GLM-4.7 \
  --tensor-parallel-size 4 \
  --gpu-memory-utilization 0.95 \
  --max-model-len 200000 \
  --dtype float16 \
  --max-context-len-to-capture 200000 \
  --enable-prefix-caching \
  --enforce-eager
```

### Вариант 2: BF16

```bash
vllm serve zai-org/GLM-4.7 \
  --tensor-parallel-size 8 \
  --gpu-memory-utilization 0.90 \
  --max-model-len 200000 \
  --dtype bfloat16 \
  --max-context-len-to-capture 200000 \
  --enable-prefix-caching
```

### Вариант 3: AWQ 4bit

```bash
vllm serve zai-org/GLM-4.7-AWQ \
  --tensor-parallel-size 2 \
  --gpu-memory-utilization 0.95 \
  --max-model-len 200000 \
  --quantization awq \
  --dtype auto \
  --max-context-len-to-capture 200000
```

---

## Часть 4: Docker Compose конфигурации

### Вариант 1: FP8 с 4 GPU (рекомендуется)

```yaml
services:
  vllm-glm47:
    image: vllm/vllm-openai:latest
    runtime: nvidia
    ports:
      - "8000:8000"
    environment:
      - CUDA_VISIBLE_DEVICES=0,1,2,3
    command: >
      --model zai-org/GLM-4.7
      --tensor-parallel-size 4
      --gpu-memory-utilization 0.95
      --max-model-len 200000
      --dtype float16
      --enable-prefix-caching
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 4
              capabilities: [gpu]

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  langfuse:
    image: langfuse/langfuse:latest
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/langfuse
    depends_on:
      - postgres

  postgres:
    image: postgres:14
    environment:
      - POSTGRES_DB=langfuse
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
  redis_data:
```

### Вариант 2: BF16 с 8 GPU

```yaml
services:
  vllm-glm47:
    image: vllm/vllm-openai:latest
    runtime: nvidia
    ports:
      - "8000:8000"
    environment:
      - CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
    command: >
      --model zai-org/GLM-4.7
      --tensor-parallel-size 8
      --gpu-memory-utilization 0.90
      --max-model-len 200000
      --dtype bfloat16
      --enable-prefix-caching
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 8
              capabilities: [gpu]
```

---

## Часть 5: Интеграция с Claude Code CLI

### 5.1. Базовая настройка

```bash
# 1. Установка Claude Code CLI
npm install -g @anthropic-ai/claude-code

# 2. Инициализация конфигурации
claude-code init

# 3. Настройка провайдера моделей для GLM-4.7
cat > ~/.claude-code/config.yaml <<EOF
models:
  primary:
    provider: openai-compatible
    base_url: http://gpu-server:8000/v1
    model_name: zai-org/GLM-4.7
    api_key: dummy-key
    temperature: 0.7
    max_tokens: 4096
    context_length: 200000

  coder:
    provider: openai-compatible
    base_url: http://gpu-server:8000/v1
    model_name: zai-org/GLM-4.7
    api_key: dummy-key
    temperature: 0.2
    max_tokens: 16384
    context_length: 200000

  tester:
    provider: openai-compatible
    base_url: http://gpu-server:8000/v1
    model_name: zai-org/GLM-4.7
    api_key: dummy-key
    temperature: 0.3
    max_tokens: 8192
    context_length: 200000
EOF
```

### 5.2. MCP конфигурация

```bash
mkdir -p ~/.claude-code/mcp

cat > ~/.claude-code/mcp/glm47-server.json <<EOF
{
  "name": "glm47-local",
  "description": "Local GLM-4.7 (355B MoE, 200K context) via vLLM",
  "version": "1.0.0",
  "endpoint": "http://gpu-server:8000/v1",
  "authentication": {
    "type": "none",
    "api_key": "dummy-key"
  },
  "capabilities": {
    "max_tokens": 128000,
    "max_context": 200000,
    "supports_tool_calling": true,
    "supports_json_mode": true,
    "supports_function_calling": true,
    "supports_vision": false,
    "architecture": "moe",
    "active_parameters": "32B"
  }
}
EOF
```

---

## Часть 6: Безопасность и соответствие

### Контекст развертывания

- **Локация**: Собственный ЦОД (аренда у другого подразделения корпорации)
- **Доступ**: SSH root-доступ к серверу
- **Пользователи**: 1-5 пользователей в фазе 0

### Меры безопасности

```yaml
network:
  - Фаервол между GPU сервером и корпоративной сетью
  - VPN доступ из корпоративной сети (или SSH через jump-host)
  - Изолированная VLAN для GPU-сервера

access_control:
  - SSH key-based аутентификация (1-5 пользователей)
  - Разделение прав: sudo для администратора, user для разработчиков
  - Опционально: LDAP интеграция для фазы 1

data_protection:
  - Шифрование при хранении (LUKS для NVMe)
  - Шифрование при передаче (TLS 1.3 для API endpoints)
  - Соответствие 152-ФЗ (логирование действий)

backup:
  - Резервные копии конфигураций в репозитории
  - Snapshot NVMe с моделями (еженедельно)
```

---

## Часть 7: Мониторинг

### Stack для мониторинга

```yaml
monitoring:
  metrics: Prometheus + Grafana
  logs: Loki + Promtail
  traces: Tempo (опционально)
  gpu_metrics: DCGM Exporter

# Grafana Dashboard метрики
- GPU Utilization per device
- GPU Memory usage
- vLLM request latency (p50, p95, p99)
- Tokens per second
- Request throughput (RPS)
```

---

## Часть 8: Порядок выполнения работ

### Неделя 1: Базовая настройка

- [ ] Подготовить сервер с 8× GPU (A100/H100)
- [ ] Установить NVIDIA драйверы и CUDA 12.1+
- [ ] Установить Docker 24.0+ с nvidia-container-toolkit
- [ ] Настроить сеть и фаервол

### Неделя 2: Inference setup

- [ ] Развернуть vLLM с GLM-4.7 в Docker контейнере
- [ ] Настроить tensor parallelism на 4 GPU
- [ ] Протестировать инференс (benchmarks)
- [ ] Настроить OpenAI-совместимый API endpoint

### Неделя 3: Интеграция и мониторинг

- [ ] Настроить Prometheus + Grafana для GPU метрик
- [ ] Интегрировать с Claude Code CLI
- [ ] Настроить Langfuse для трассировки LLM
- [ ] Создать дашборды мониторинга

### Неделя 4: Оптимизация и документация

- [ ] Оптимизировать производительность vLLM
- [ ] Настроить auto-scaling (если используется Kubernetes)
- [ ] Создать документацию для команды
- [ ] Провести load testing

---

## Часть 9: Критерии приемки

### Definition of Done

- [ ] vLLM успешно запущен на 4 GPU с GLM-4.7
- [ ] OpenAI-совместимый API отвечает на запросы
- [ ] Latency p95 < 10 секунд для типичных запросов
- [ ] Мониторинг GPU работает в Grafana
- [ ] Claude Code CLI может подключаться к локальному GLM-4.7
- [ ] Документация создана и передана команде

---

## Часть 10: Связанные документы

### Документация проекта

- [🗺️ Стратегическая дорожная карта](./strategic_roadmap.md) — Фаза 0, Веха 0.1.3
- [🧩 Реестр метаблоков](./meta_block_registry.md) — ENVIRONMENT_SETUP_PATTERN
- [🔧 Стратегия ИИ-инструментов](./ai_tools_strategy.md) — Категория задач
- [📖 Глоссарий](./GLOSSARY.md) — Термины: GPU, Inference, Tensor Parallelism

### Концептуальные документы

- [📋 Запрос железа и организации инфраструктуры](../concept/Запрос%20железа%20и%20организации%20инфраструктуры.md) — Детальные требования
- [👥 Подготовительный этап дек25-фев26](../concept/Подготовительный%20этап%20дек25-фев26.md) — Состав команды

---

## Источники и ссылки

### Официальная документация GLM-4.7
- [GLM-4.7 - Z.AI DEVELOPER DOCUMENT](https://docs.z.ai/guides/llm/glm-4.7)
- [GLM-4.7 Overview - Z.AI](https://open.bigmodel.cn/)

### Техническая документация vLLM
- [GLM-4.X LLM Usage Guide - vLLM Recipes](https://docs.vllm.ai/projects/recipes/en/latest/GLM/GLM.html)
- [GLM-4.5/4.6/4.7 — vllm-ascend](https://docs.vllm.ai/projects/ascend/en/latest/tutorials/GLM4.x.html)
- [Supported Models - vLLM](https://docs.vllm.ai/en/latest/models/supported_models.html)

### Технические спецификации
- [GLM-4.7: Pricing, Benchmarks, and Full Model Analysis](https://llm-stats.com/blog/research/glm-4.7-launch)
- [GLM-4.7 Guide: Z.ai's Open-Source AI Coding Model](https://www.digitalapplied.com/blog/glm-4-7-zai-coding-model-guide)
- [How to Install and Use GLM-4.7 - Setup Guide](https://codersera.com/blog/how-to-install-and-use-glm-47)

### Модель на HuggingFace
- [zai-org/GLM-4.7](https://huggingface.co/zai-org/GLM-4.7)

---

**Версия документа**: v1.0
**Последнее обновление**: 2026-01-19
**Статус**: Утверждено
**Ответственный**: DevOps команда
