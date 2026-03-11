# Telegram Web Remote UAT Fixtures

В этой папке лежат review-safe before/after artifacts для production-aware authoritative remote UAT.

Снимки из этой ветки:

- `2026-03-11-before-send-failure-review-safe.json`
  - run: `22976837805`
  - sha: `d08dbb1`
  - verdict: `failed`
  - stage/failure: `send/send_failure`
  - review-safe artifact id: `5880467782`
  - restricted debug artifact id: `5880467947`
- `2026-03-11-after-pass-review-safe.json`
  - run: `22977239309`
  - sha: `2924b12`
  - verdict: `passed`
  - stage: `wait_reply`
  - review-safe artifact id: `5880633329`
  - restricted debug artifact id: `5880633566`

Restricted debug bundles в репозиторий не коммитятся, потому что содержат production chat evidence. Они доступны в GitHub Actions artifacts для соответствующих run.
