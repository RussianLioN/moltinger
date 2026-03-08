# Clean Deploy Runbook: Telegram Web User Monitor

Этот runbook фиксирует GitOps-путь деплоя для мониторинга Telegram Web user-mode без ручного `scp`.

## Цель

- Единый источник истины: git + CI/CD.
- Блокировка деплоя при drift (`git status --porcelain` на сервере не пустой).
- Primary scheduler: systemd timer.

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
   - **заблокирует** деплой при drift.

4. После успешного deploy:

```bash
ssh root@ainetic.tech "systemctl status moltis-telegram-web-user-monitor.timer --no-pager"
ssh root@ainetic.tech "tail -n 50 /var/log/moltis/telegram-web-user-monitor.log"
```

## Drift remediation

Если деплой заблокирован:

1. Зафиксируйте серверный drift (snapshot `git status`, diff нужных файлов).
2. Перенесите релевантные изменения в git-репозиторий.
3. Очистите серверное состояние до управляемого (через CI sync, не ручными patch-изменениями поверх).
4. Повторите deploy.

## Политика

- Ручной `scp` разрешён только для аварийной диагностики.
- Любая постоянная настройка должна попадать в git (scripts/config/systemd/cron).
