# Clean Deploy Runbook: Telegram Web User Monitor

Этот runbook фиксирует GitOps-путь деплоя для мониторинга Telegram Web user-mode без ручного `scp`.

## Цель

- Единый источник истины: git + CI/CD.
- Блокировка деплоя при drift (`git status --porcelain` на сервере не пустой).
- Telegram Web monitor доступен как manual/on-demand инструмент, а не как постоянный production scheduler.

## Предусловия

- Все изменения закоммичены и запушены.
- CI workflow `deploy.yml` запускается из `main`.
- На сервере есть `/opt/moltinger`.

## Шаги clean deploy

1. Локально проверьте чистоту репозитория:

```bash
git status --porcelain
```

2. Запушьте изменения в `main` (или запустите `workflow_dispatch`).

3. CI автоматически:
   - сверит `docker-compose`, `config`, `scripts`, `systemd`;
   - проверит `ssh root@ainetic.tech "cd /opt/moltinger && git status --porcelain"`;
   - **заблокирует** деплой при drift, если его нельзя безопасно вылечить через workflow.

4. После успешного deploy authoritative remote UAT запускается вручную:

```bash
gh workflow run telegram-e2e-on-demand.yml \
  -f message='/status' \
  -f timeout_sec='45' \
  -f operator_intent='post_deploy_verification' \
  -f run_secondary_mtproto=false \
  -f upload_restricted_debug=false
```

5. Оператор смотрит:
   - `run.verdict`
   - `run.stage`
   - `failure.code`
   - `recommended_action`

## Drift remediation

Если деплой заблокирован:

1. Зафиксируйте серверный drift (snapshot `git status`, diff нужных файлов).
2. Перенесите релевантные изменения в git-репозиторий.
3. Если drift ограничен deploy-managed surface (`docker-compose*.yml`, `config/`, `scripts/`, `systemd/`), перезапустите `Deploy Moltis` через `workflow_dispatch` с `repair_server_checkout=true`.
4. Workflow сам снимет evidence snapshot в `${BACKUP_PATH}/gitops-drift/`, выровняет checkout до текущего `main`, а затем продолжит обычный deploy.
5. Если dirty state затрагивает что-то вне этого allowlist, workflow останется fail-closed: разберите drift отдельно и только потом повторите deploy.

## Политика

- Ручной `scp` state-файлов не должен быть обычным production workflow.
- Любая постоянная настройка должна попадать в git (scripts/config/systemd/cron).
- Production по умолчанию не включает периодический Telegram Web scheduler.
- Канонический post-deploy verdict path: `Telegram Web`.
