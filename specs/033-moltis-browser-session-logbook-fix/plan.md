# Plan: Moltis Browser Session And Telegram Logbook Containment

## Design

### 1. Repo-side containment

- Усилить `identity.soul` так, чтобы Telegram/DM path по умолчанию избегал browser/search/memory-heavy workflows.
- Это временный safety rail, а не доказательство окончательного fix.

### 2. Failure taxonomy

- На уровне `scripts/test-moltis-api.sh` анализировать WS RPC event stream до generic timeout message.
- Выделить отдельные коды:
  - `browser_session_contamination`
  - `browser_pool_exhausted`
  - `browser_navigation_timeout`
  - `browser_failure_detected`

### 3. Canary contract

- `scripts/moltis-browser-canary.sh` должен считать `browser connection dead` и `pool exhausted` такими же blocking signatures, как launch/readiness failures.

### 4. Official-first closure packet

- RCA должен явно различать:
  - что repo владеет диагностикой и containment;
  - что остаётся upstream/runtime issue.
- Runbook должен зафиксировать:
  - что official docs говорят про sandbox mode;
  - что `Pair` не является доказанным root-cause fix для этого инцидента;
  - какие conditions действительно должны считаться closure.

### 5. Upstream handoff

- Подготовить отдельный issue artifact для upstream Moltis/OpenClaw runtime maintainers:
  - stale browser session evidence;
  - Telegram activity logbook suffix leakage;
  - acceptance criteria для closure.

## Verification

- `bash -n scripts/test-moltis-api.sh`
- `bash -n scripts/moltis-browser-canary.sh`
- `bash tests/component/test_moltis_api_smoke.sh`
- `bash tests/component/test_moltis_browser_canary.sh`
- `bash tests/static/test_config_validation.sh`
- `./scripts/build-lessons-index.sh`
