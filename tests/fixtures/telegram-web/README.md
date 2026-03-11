# Telegram Web Remote UAT Fixtures

Эта папка зарезервирована для before/after artifacts authoritative remote UAT.

Что сюда должно попадать после post-deploy запуска:

- failing review-safe artifact до исправления;
- passing review-safe artifact после исправления или root-cause narrowing;
- при необходимости restricted debug bundle, если его можно хранить в репозитории безопасно.

В этой ветке implementation и component contract уже готовы, но реальные production-aware before/after artifacts появляются только после ручного post-deploy запуска через:

```bash
gh workflow run telegram-e2e-on-demand.yml \
  -f message='/status' \
  -f timeout_sec='45' \
  -f operator_intent='post_deploy_verification'
```
