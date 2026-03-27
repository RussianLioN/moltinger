---
title: "Tracked Moltis deploy failed because auto-rollback reused an unsafe recreate path while health-monitor mutated Docker state during the same incident"
date: 2026-03-28
severity: P1
category: cicd
tags: [cicd, deploy, rollback, health-monitor, docker-compose, moltis, production, timeout, notifications]
root_cause: "The first rollout hotfix covered only the primary Moltis recreate path; when post-start verification failed, deploy.sh auto-triggered rollback() through the old unsafe recreate contract, while the crash-looping health-monitor simultaneously exited on disk warnings and ran background Docker cleanup during the same deploy window"
---

# RCA: Tracked Moltis deploy failed because auto-rollback reused an unsafe recreate path while health-monitor mutated Docker state during the same incident

**Дата:** 2026-03-28  
**Статус:** Resolved  
**Влияние:** production workflow `Deploy Moltis` run `23667501546` завершился `failure`. При этом live production остался доступным (`moltis` running healthy, `/health` = `200`), но CI/CD контракт оставался сломанным, а фоновый `moltis-health-monitor` создавал дополнительный mutating noise в Docker-среде.

## Ошибка

Падение произошло в workflow `Deploy Moltis`, job `Deploy to Production`, step `Run tracked Moltis deploy control plane`.

Ключевая последовательность из failed log:

- `Stopping existing Moltis container 'moltis' with 45s grace before rollout`
- `Removing existing Moltis container 'moltis' before rollout`
- `Container moltis Created`
- `Container moltis Started`
- затем:
  - `Container moltis Recreate`
  - `Container moltis Error response from daemon: No such container: 354af4aef7f1_moltis`

Проверка production после failure показала:

- image: `ghcr.io/moltis-org/moltis:0.10.18`
- container: `running healthy`
- `/health` => `200`
- checkout: `a39f1710d6308b4f2c302fd7ba5e91e7f6aaee11`

Отдельная проверка host-level automation показала дополнительный шумящий фактор:

- `moltis-health-monitor.service` находился в endless auto-restart loop;
- при каждом цикле он фиксировал disk warning `93%`;
- затем выполнял background cleanup и завершался `status=1/FAILURE`.

## Что было доказано

1. Второй `Container moltis Recreate` шёл не из второго запуска workflow и не из SSH wrapper.
2. Он запускался из `rollback()` внутри `scripts/deploy.sh` после того, как `cmd_deploy()` получил failure из `verify_deployment()`.
3. Значит проблема была не в повторном external trigger, а в том, что rollback path остался на старом небезопасном recreate-контракте.
4. Параллельно `scripts/health-monitor.sh` находился под `set -euo pipefail`, и `check_disk_space()` возвращал `1` на warning. Это аварийно завершало сервис, а systemd с `Restart=always` поднимал его снова.
5. В старом monitor path disk warning сопровождался background Docker cleanup, то есть хост в окне deploy получал дополнительное нежелательное мутационное воздействие.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему deploy workflow завершился `failure`, хотя новый контейнер успел стартовать? | После старта нового `moltis` post-start verification провалился, и `cmd_deploy()` вызвал auto-rollback | `scripts/deploy.sh`, failed run `23667501546` |
| 2 | Почему во время rollback появился второй `Container moltis Recreate`? | `rollback()` для Moltis всё ещё использовал старый `compose up -d --force-recreate` без pre-stop/remove и без `--no-deps` | `scripts/deploy.sh` до исправления |
| 3 | Почему первый hotfix не закрыл инцидент полностью? | Он сериализовал только основной rollout path, но не сделал rollback симметричным и безопасным | diff между rollout/rollback paths |
| 4 | Почему инцидент был более рискованным, чем просто красный pipeline? | В это же время `moltis-health-monitor.service` crash-loop'ился и выполнял background Docker cleanup во время deploy window | `journalctl -u moltis-health-monitor.service`, `systemctl status` |
| 5 | Почему health-monitor превращался в crash-loop вместо warning-only сигнала? | `check_disk_space()` возвращал `1`, а `main()` вызывал его под `set -e`; service падал, systemd перезапускал его, и цикл повторялся | `scripts/health-monitor.sh` до исправления |

## Корневая причина

Инцидент состоял из двух связанных дефектов.

### Primary root cause

`deploy.sh` после неуспешного `verify_deployment()` вызывал `rollback()` через старый recreate-контракт.  
То есть:

- основной rollout path уже был частично сериализован;
- но rollback path для Moltis оставался на `compose up -d --force-recreate`;
- при auto-rollback появлялся второй unsafe recreate уже после успешного старта нового контейнера.

### Contributing root cause

`moltis-health-monitor.service` находился в crash-loop и вмешивался в Docker-среду во время deploy:

- disk warning => `check_disk_space()` возвращал `1`;
- `set -e` аварийно завершал процесс;
- systemd с `Restart=always` перезапускал сервис;
- monitor снова доходил до warning и background cleanup.

Это не было единственным источником второго `Recreate`, но создавало опасный фоновый mutating layer в том же production окне.

## Принятые меры

1. В `scripts/deploy.sh` rollback path для Moltis переведён на тот же безопасный контракт, что и основной rollout:
   - `prepare_moltis_container_for_rollout`
   - `compose up -d --no-deps --force-recreate "$TARGET_SERVICE"`
2. В `scripts/deploy.sh` зафиксировано явное логирование `Auto rollback trigger reason: ...`, а failing verify reason теперь сохраняется в JSON output как `verify_failure_reason`.
3. В rollback evidence JSON `rollback_reason` переведён на безопасное JSON-экранирование, чтобы не терять реальную причину при сообщениях с пробелами/спецсимволами.
4. В `scripts/health-monitor.sh` disk warnings больше не убивают сервисный цикл:
   - `check_disk_space 90 || true`
   - `check_memory 90 || true`
5. В `scripts/health-monitor.sh` добавлена awareness к deploy mutex:
   - mutating actions suppress during active deploy lock;
   - restart/full recovery path не вмешиваются в active rollout.
6. Background cleanup сужен:
   - удалён global `docker system prune` path;
   - оставлен только `docker image prune -af`;
   - добавлен cooldown для repeated cleanup.
7. В systemd unit добавлены tracked env для deploy mutex и cleanup cooldown.
8. В GitHub Actions добавлены:
   - timeout'ы на весь критический хвост `deploy.yml`;
   - hardened `deploy-status-notify.yml` без checkout `workflow_run.head_sha`;
   - отдельный read-only stalled-run watchdog workflow.
9. На production временно выполнен containment:
   - `systemctl stop moltis-health-monitor.service`
   - `systemctl reset-failed moltis-health-monitor.service`

## Проверка после исправления

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash -n scripts/deploy.sh` | pass | local |
| `bash -n scripts/health-monitor.sh` | pass | local |
| `bash -n scripts/deploy-stall-watchdog.sh` | pass | local |
| `bash tests/static/test_config_validation.sh` | pass | 115/115 |
| `bash tests/unit/test_deploy_workflow_guards.sh` | pass | 28/28 |
| `bash tests/unit/test_deploy_stall_watchdog.sh` | pass | 3/3 |
| `bash tests/component/test_health_monitor_runtime_guards.sh` | pass | 4/4 |
| `systemctl is-active moltis-health-monitor.service` on production after containment | `inactive` | remote |
| production deploy rerun on fixed branch | pending at RCA capture point | to be validated after merge |

## Уроки

1. Если rollout path сериализован, rollback path обязан быть симметричным. Half-fix для primary path не закрывает incident.
2. Post-start verification failures нужно логировать как first-class cause, а не оставлять operator только с symptom вроде `Container ... Recreate`.
3. Health monitors не должны аварийно завершать systemd service на warning-only сигналах вроде disk pressure; warning path и mutating recovery path должны быть разделены.
4. Background cleanup в production должен быть минимальным по охвату и aware к deploy mutex, иначе self-heal становится источником drift и шумовых сбоев.
5. Для GitHub Actions terminal notifications должны быть event-driven и bounded по времени, а watchdog должен быть только secondary alert layer, не primary deploy proof.
