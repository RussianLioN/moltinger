# Plan: Moltis Skill Discovery And Telegram Leak Regressions

## Design Summary

Этот slice идёт по official-first маршруту:

1. official Moltis/OpenClaw docs;
2. official issues/repository signals;
3. community/forums;
4. только затем вторичные источники.

Authoritative live evidence уже показало:

- `/api/skills` подтверждает, что `codex-update` реально discover-ится и enabled;
- `channels.list` подтверждает, что Telegram runtime видит `stream_mode = "off"`;
- `chat.history` показывает чистый финальный assistant reply, но user всё равно видит `Activity log`;
- `chat.raw_prompt` говорит модели читать `SKILL.md` по host-style paths;
- sandbox container не содержит `/home/moltis/.moltis/skills` и `/server`, поэтому такие probes дают ложный negative.

Это значит, что нам нужен split design:

- repo-owned mitigation: prompt/identity/uat hardening;
- upstream-owned handoff: prompt/runtime/sandbox mismatch и transport leakage.

## Workstreams

### 1. Official-First Evidence And RCA

- Сверить observed behavior с official docs Moltis/OpenClaw по skills, channels, sandbox, Docker, prompt/runtime behavior.
- Отдельно сверить official GitHub issues, затем community/forum evidence.
- Зафиксировать RCA по двум направлениям:
  - `codex-update` false-negative / skill discovery mismatch;
  - Telegram `Activity log` leakage despite `stream_mode = "off"`.

### 2. Repo-Owned Mitigation

- Обновить `config/moltis.toml` так, чтобы Telegram user-facing capability/update questions:
  - не пытались доказывать наличие skills через sandbox file probes;
  - не делали ложный вывод “skill path не существует”;
  - при недоступности canonical local runtime path честно деградировали в advisory/web-source mode.
- Укрепить user-facing contract вокруг `codex-update`:
  - если навык объявлен в Available Skills, считать его доступной capability;
  - не обещать удалённое выполнение локальных Codex update actions;
  - трактовать `codex-update` как advisory capability для remote Moltis surfaces.

### 3. UAT And Regression Gates

- Расширить Telegram UAT/probe scripts так, чтобы они fail-closed на:
  - `Activity log`;
  - host path leakage (`/home/moltis/.moltis/skills`, `/server/scripts/...`);
  - ложные skill-missing claims по `codex-update`.
- Добавить targeted component/static tests.

### 4. Documentation And Backlog

- Записать правило, что remote Moltis surfaces не должны симулировать локальный Codex self-update.
- Обновить runbook и lessons.
- Подготовить upstream issue artifact.
- Отдельно занести в backlog follow-up redesign:
  - `codex-update` becomes notification-only/advisory for remote Moltis;
  - local Codex update/install UX remains local-machine responsibility.

## Verification Strategy

- `bash tests/component/test_telegram_remote_uat_contract.sh`
- `bash tests/component/test_telegram_web_probe_correlation.sh`
- `bash tests/static/test_config_validation.sh`
- `./scripts/build-lessons-index.sh`
- live authoritative re-check only after repo-owned carrier lands via canonical path

