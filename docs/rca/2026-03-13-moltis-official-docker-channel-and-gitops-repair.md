---
title: "Moltis deploy rollback to 0.9.10 after non-official image pin and missing GitOps checkout repair"
date: 2026-03-13
severity: P1
category: cicd
tags: [moltis, docker, gitops, github-actions, drift-repair]
root_cause: "Repo deploy logic diverged from Moltis official Docker channel and had no auditable pre-gate reconcile path for a dirty server checkout after failed deploys"
---

# RCA: Moltis deploy rollback to 0.9.10 after non-official image pin and missing GitOps checkout repair

**Дата:** 2026-03-13
**Статус:** Resolved
**Влияние:** Высокое; production Moltis остался на `0.9.10`, web UI ловил `WebSocket disconnected` / `handshake failed`, а автоматический deploy из `main` блокировался dirty checkout на сервере
**Контекст:** Разбор failed production runs `23027820626` и `23028082844`

## Ошибка

Production обновление Moltis не дошло до рабочего `latest`-канала по официальной Docker-инструкции:

1. deploy был временно переведён на `ghcr.io/moltis-org/moltis:v0.10.18`, но pull такого image reference провалился;
2. после возврата на официальный `latest` workflow всё равно не мог дойти до deploy, потому что `/opt/moltinger` оставался dirty на feature-ветке и compliance gate валил job до backup/deploy steps.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему production не обновился на актуальный Moltis? | Потому что deploy path сначала попытался тянуть `ghcr.io/moltis-org/moltis:v0.10.18`, а затем blocked-by-dirty не смог вернуться к нормальному rollout | Failed run `23027820626` на шаге `Pull new image`; failed run `23028082844` на шаге `Block deployment on GitOps drift` |
| 2 | Почему workflow вообще ушёл на pin `v0.10.18`? | Потому что release tag был ошибочно принят за гарантированно pullable GHCR image tag | Реальный production log: `Image not found locally or remotely` для `ghcr.io/moltis-org/moltis:v0.10.18` |
| 3 | Почему это допущение оказалось ложным для официального Docker path? | Потому что официальный Moltis Docker install документирован через `ghcr.io/moltis-org/moltis:latest`, а не через release-tag pin | `docs.moltis.org/docker.html` и `github.com/moltis-org/moltis` используют `:latest` |
| 4 | Почему после возврата на `latest` deploy всё равно не починился? | Потому что серверный checkout был dirty и стоял на feature-ветке, а workflow умел выравнивать git checkout только после успешного deploy | `/opt/moltinger` показывал dirty `feat/moltinger-z8m-4-moltis-post-update-error-remediation`; `deploy.yml` делал `git fetch/checkout/reset` только в success-path |
| 5 | Почему это стало системной проблемой, а не единичным сбоем? | Потому что в GitOps pipeline не было auditable pre-gate self-heal path для deploy-managed dirty state, а PR gate отдельно пропустил drift между `config/moltis.toml` и test fixture до падения CI | До фикса не было `repair_server_checkout`; failed PR artifact показал `Fixture moltis.toml must mirror handoff env metadata from config/moltis.toml` |

## Корневая причина

Repo одновременно имел две уязвимости процесса:

1. локальный deploy contract отошёл от официального Moltis Docker distribution channel;
2. GitOps workflow не умел безопасно и аудируемо восстанавливать dirty server checkout до начала production deploy, даже когда drift был только в deploy-managed surface.

## Принятые меры

1. **Немедленное исправление:** возвращён официальный Docker channel `ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-latest}`.
2. **Немедленное исправление:** добавлен `repair_server_checkout` в `Deploy Moltis`; workflow теперь умеет снять drift snapshot и выровнять checkout до текущего `main`, если dirty state ограничен `docker-compose*.yml`, `config/`, `scripts/`, `systemd/`.
3. **Немедленное исправление:** GitOps compliance теперь отдельно сравнивает `docker-compose.prod.yml`, а не только dev compose.
4. **Немедленное исправление:** test fixture `tests/fixtures/config/moltis.toml` синхронизирован с handoff env metadata из `config/moltis.toml`.
5. **Документация:** clean deploy runbook обновлён под managed drift repair path.

## Связанные обновления

- [X] RCA-отчёт создан в `docs/rca/`
- [X] Static guard усилен в `tests/static/test_config_validation.sh`
- [X] Lessons пересобраны
- [ ] Новый отдельный policy file не потребовался

## Уроки

1. **Не приравнивать GitHub release tag к published container tag** без прямой проверки registry/source-of-truth для конкретного install method.
2. **Официальный install path важнее локальной привычки pinning-by-release**, если upstream docs для Docker явно ведут через `latest`.
3. **GitOps gate должен иметь узкий auditable reconcile path** для deploy-managed drift после failed deploy, иначе чистый `main` не может сам восстановить production.
4. **Fixture config обязан зеркалить handoff metadata из основного runtime config**, иначе PR может упасть уже после того, как продовый incident начался.

---

*Создано по протоколу RCA (5 Why) для incident chain вокруг Moltis update runs `23027820626` и `23028082844`.*
