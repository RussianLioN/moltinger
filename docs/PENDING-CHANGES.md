# Pending Manual Changes

## 2026-02-27: GitOps Compliance Enhancement

### P0-3: Добавить scripts/ в CI/CD sync

**Файл**: `.github/workflows/deploy.yml`
**Причина**: Автоматический запрет denied по политике безопасности
**Изменение**: Добавить sync scripts/ директории

**Текущий код** (строка ~200):
```yaml
      - name: Sync configuration files (GitOps)
        run: |
          # ... existing code ...
          scp -r config/* ${{ env.SSH_USER }}@${{ env.SSH_HOST }}:${{ env.DEPLOY_PATH }}/config/
          echo "Configuration synced successfully (docker-compose.yml + config/)"
```

**Новый код**:
```yaml
      - name: Sync configuration files (GitOps)
        run: |
          # ... existing code ...
          scp -r config/* ${{ env.SSH_USER }}@${{ env.SSH_HOST }}:${{ env.DEPLOY_PATH }}/config/

          # Sync scripts directory (GitOps compliance - incident #002)
          ssh ${{ env.SSH_USER }}@${{ env.SSH_HOST }} "mkdir -p ${{ env.DEPLOY_PATH }}/scripts"
          scp -r scripts/* ${{ env.SSH_USER }}@${{ env.SSH_HOST }}:${{ env.DEPLOY_PATH }}/scripts/ 2>/dev/null || echo "No scripts to sync"

          echo "Configuration synced successfully (docker-compose.yml + config/ + scripts/)"
```

**Действие**: Внести изменение вручную или временно снять защиту

---

## Чеклист внедрённых P0:

| # | Действие | Статус |
|---|----------|--------|
| P0-1 | ssh/scp в ASK list (settings.json) | ✅ DONE |
| P0-2 | Blocking rule в CLAUDE.md | ✅ DONE |
| P0-3 | scripts/ в CI/CD sync | ✅ DONE (commit c74ce8e) |
| P0-4 | Fix duplicate `ask` key in settings.json | ✅ DONE (this commit) |

---

*Created: 2026-02-27*
