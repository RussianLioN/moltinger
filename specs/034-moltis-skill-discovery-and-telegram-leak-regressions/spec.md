# Spec: Moltis Skill Discovery And Telegram Leak Regressions

## Summary

После новых merge/deploy на `main` в live Moltis проявились две связанные регрессии:

1. В Telegram пользователь всё ещё может видеть внутренний `Activity log`, хотя финальный assistant reply в истории уже чистый и live channel config показывает `stream_mode = "off"`.
2. Навык `codex-update` реально discover-ится live runtime через `/api/skills`, но в Telegram/sandboxed session модель ошибочно делает filesystem-проверки по `/home/moltis/.moltis/skills/...` и заявляет, что skill path не существует.

Текущие live-доказательства показывают split корня:

- repo-owned проблема в guardrails и UAT-контрактах, которые не блокируют ложные skill-path probes и не режут соответствующие user-facing ответы;
- upstream/runtime проблема в несовпадении между raw prompt, skill activation contract, sandbox-visible filesystem и transport-level delivery of internal status events.

Дополнительно зафиксирована архитектурная коррекция для `codex-update`:

- исторически навык мигрировался из локального Codex-контекста;
- но Moltis работает на удалённом сервере в контейнере и не должен обещать пользователю удалённое выполнение локальных Codex update actions;
- для remote Moltis surfaces `codex-update` должен быть переосмыслен как уведомительно-рекомендательный/advisory capability;
- локальная auto-update/upgrade UX Codex CLI на машине пользователя остаётся отдельной responsibility и не должна симулироваться на сервере Moltis.

Этот slice не обещает полностью переписать upstream Moltis/OpenClaw runtime. Он должен:

- зафиксировать инцидент как отдельную tracked проблему;
- реализовать безопасные repo-owned mitigation для Telegram/capability answers;
- усилить authoritative UAT, чтобы regression больше не проходила незамеченной;
- оформить official-first RCA, runbook, rule и upstream handoff;
- занести redesign `codex-update` в явный backlog как отдельную follow-up архитектурную задачу.

## Goals

- Доказать authoritative live truth для `codex-update`: skill существует в runtime discovery, даже если sandboxed `exec` не видит host paths.
- Перестать отвечать пользователю ложным “skill/path не существует” только потому, что sandboxed `exec` не видит host filesystem.
- Не давать Telegram UAT пропускать `Activity log` leakage и codex-update false-negative replies.
- Зафиксировать official-first operational guidance: сначала docs Moltis/OpenClaw, затем official issues, затем community sources.
- Занести в backlog redesign `codex-update` как advisory-only remote-safe capability.

## Non-Goals

- Не переписывать upstream transport или sandbox implementation Moltis/OpenClaw внутри этого репозитория.
- Не считать этот slice полной реализацией нового advisory-only `codex-update`.
- Не возвращать старую модель, где Moltis обещает обновить локальный Codex CLI на удалённом сервере.

## Acceptance Criteria

1. Создан отдельный Speckit package `034-moltis-skill-discovery-and-telegram-leak-regressions` с tracked `spec.md`, `plan.md`, `tasks.md`.
2. В package явно зафиксировано, что `codex-update` для remote Moltis surfaces должен стать advisory-only capability, а не remote executor локальных Codex actions.
3. Repo-owned mitigation обновляет Telegram/capability contract так, чтобы отсутствие sandbox-visible host path не трактовалось как отсутствие skill.
4. Authoritative Telegram UAT/probe fail-closed на:
   - `Activity log` leakage;
   - ответы про несуществующий skill/path, если live runtime discovery подтверждает наличие `codex-update`.
5. Оформлены RCA, rule, runbook update и upstream issue artifact с разделением repo-owned и upstream-owned корней.

