# Официальному мастеру настройки Clawdiy нужен записываемый домашний каталог OpenClaw (RCA-013)

**Статус:** Active  
**Дата вступления:** 2026-03-13  
**Область действия:** `docker-compose.clawdiy.yml`, `scripts/deploy.sh`, `scripts/render-clawdiy-runtime-config.sh`, `scripts/preflight-check.sh`, резервное копирование и runbook’и Clawdiy/OpenClaw

## Какую проблему предотвращает это правило

Официальные мастер-потоки OpenClaw для Docker/headless режима пишут временные файлы, OAuth-артефакты и обновления конфигурации внутри `~/.openclaw`. Если live Clawdiy монтирует только `openclaw.json` как read-only файл, официальный мастер настройки неизбежно падает даже после успешного OAuth.

## Обязательный протокол

1. Следовать официальной инструкции OpenClaw для `onboard` / `models auth login` и считать ее каноническим контрактом рантайма.
2. Монтировать в контейнер **весь** каталог `data/clawdiy/runtime` как `/home/node/.openclaw`, а не только `openclaw.json`.
3. Держать `config/clawdiy/openclaw.json` как отслеживаемый шаблон, а `data/clawdiy/runtime/` как live `runtime home`.
4. Нормализовывать права `data/clawdiy/runtime` на uid/gid рантайма OpenClaw во время рендера и разворачивания.
5. Проверка перед запуском должна падать, если `data/clawdiy/runtime` отсутствует или принадлежит не runtime-пользователю.
6. Резервное копирование, восстановление и smoke-проверки должны считать `data/clawdiy/runtime` обязательной частью инвентаря Clawdiy.

## Жесткое ограничение

Для live Clawdiy запрещено:

- монтировать `./data/clawdiy/runtime/openclaw.json:/home/node/.openclaw/openclaw.json:ro`
- считать read-only file-bind достаточным для official OAuth/wizard потоков
- нормализовывать только `workspace/state/audit`, забывая про `data/clawdiy/runtime`

## Ожидаемое поведение

- Официальный мастер настройки OpenClaw может создать временный файл рядом с `openclaw.json`.
- OAuth-артефакты и служебные файлы могут сохраняться в `~/.openclaw` без ручных правок на сервере.
- Проверки перед запуском ловят несовместимый контракт до live попытки пользователя.
