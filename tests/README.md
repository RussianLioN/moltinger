# Moltis Test Architecture

Канонический entrypoint для тестов: `./tests/run.sh --lane <lane-or-group>`.

Legacy-скрипты `./tests/run_unit.sh`, `./tests/run_integration.sh`, `./tests/run_security.sh`, `./tests/run_e2e.sh` сохранены как compatibility shims на один переходный цикл, но вся новая документация, CI и локальные команды должны идти через `./tests/run.sh`.

## Lane Model

| Lane | Назначение | Blocking | Runtime | Secrets |
| --- | --- | --- | --- | --- |
| `static` | Статические проверки конфигов и dev-MCP smoke | PR | local | не нужны |
| `component` | Component-level проверки production shell logic | PR | local | не нужны |
| `integration_local` | Hermetic API integration на локальном stack | PR | `compose.test.yml` | не нужны |
| `security_api` | Auth/input/rate-limit API security на локальном stack | PR | `compose.test.yml` | не нужны |
| `mcp_fake` | MCP lifecycle через fake JSON-RPC harness | PR | local/node | не нужны |
| `e2e_browser` | Настоящий browser flow через Playwright | `push main` | `compose.test.yml` | не нужны |
| `resilience` | Destructive failover/recovery сценарии | nightly/manual | explicit live | opt-in |
| `live_external` | Telegram, real providers, real MCP backends | nightly/manual | explicit live | opt-in |

## Lane Groups

| Group | Состав |
| --- | --- |
| `pr` | `static`, `component`, `integration_local`, `security_api`, `mcp_fake` |
| `main` | `pr` + `e2e_browser` |
| `nightly` | `resilience`, `live_external`, `security_runtime_smoke` |
| `all` | `main` + `nightly` |
| `unit_legacy` | `static`, `component` |
| `integration_legacy` | `integration_local`, `provider_live`, `telegram_live`, `mcp_real` |
| `security_legacy` | `security_api`, `security_runtime_smoke` |
| `e2e_legacy` | `e2e_browser`, `resilience` |

## CLI Contract

```bash
./tests/run.sh --lane pr --json --junit
./tests/run.sh --lane component --filter circuit_breaker --verbose
./tests/run.sh --lane nightly --live --compose-project nightly-$(date +%s)
```

Поддерживаемые флаги:

- `--lane <name>`: lane или group
- `--json`: печатает aggregate `summary.json` в stdout
- `--junit`: пишет aggregate `junit.xml`
- `--filter <pattern>`: фильтрация по `suite_id` или пути
- `--verbose`: verbose mode для suite-раннеров
- `--live`: разрешает live-only lanes
- `--compose-project <name>`: явное имя Docker Compose project
- `--keep-stack`: не разбирать hermetic stack после прогона

Общие env vars:

- `TEST_REPORT_DIR`: каталог артефактов, по умолчанию `./test-results`
- `TEST_ENV_FILE`: env-файл для explicit live mode
- `TEST_BASE_URL`: base URL для HTTP/browser suites
- `TEST_TIMEOUT`: timeout suite/runtime
- `TEST_LIVE=1`: альтернативный способ включить live mode
- `COMPOSE_PROJECT_NAME`: имя compose project

Exit contract:

- `0`: pass
- `1`: fail
- `2`: skipped/unrunnable
- `3`: harness error

## Hermetic Stack

`compose.test.yml` — выделенный test stack для blocking suites.

Свойства стека:

- внутренняя test network без `traefik-net`
- service DNS вместо зависимости от host `localhost`
- ephemeral test volumes
- отдельный `test-runner` container с pinned toolchain (`bash`, `curl`, `jq`, `coreutils`, Playwright base image)
- отсутствие зависимости от `/opt/moltinger/.env` и production bind-mounts

Все suites, требующие hermetic stack, поднимаются через `./tests/run.sh`; не вызывайте `docker compose -f compose.test.yml` напрямую как новый public interface.

## Live Mode

Blocking lanes не должны неявно читать `/opt/moltinger/.env`.

Live-only lanes (`resilience`, `live_external`, `security_runtime_smoke`, `telegram_live`, `provider_live`, `mcp_real`) запускаются только с `--live` или `TEST_LIVE=1`.

Источники секретов для live mode:

1. GitHub Secrets
2. `/opt/moltinger/.env` на сервере как runtime-копия, сгенерированная CI/CD
3. `TEST_ENV_FILE`, если live-прогон явно направлен на другой env-файл

Если live mode не включён, полный skip обязан репортиться как `skipped`, а не как `passed`.

## Reports And Diagnostics

После каждого прогона runner пишет:

- `summary.json`: единый source of truth для gate job и CI summary
- `junit.xml`: aggregate JUnit при флаге `--junit`
- `suites/*.json`: per-suite JSON отчёты
- `logs/*.log`: suite stderr/stdout логи
- `diagnostics/*`: compose и container diagnostics при infra failures

Минимальный aggregate contract:

```json
{
  "lane": "pr",
  "status": "passed",
  "summary": {
    "total_suites": 5,
    "total_cases": 17,
    "passed": 17,
    "failed": 0,
    "skipped": 0
  },
  "suites": [],
  "cases": []
}
```

`summary.total_cases` считается по test cases, а не по test files. `skipped` учитывается явно и не маскируется под success.

## Local Usage

Через `npm`:

```bash
npm test
npm run test:pr
npm run test:main
npm run test:nightly
npm run test:all
npm run test:lane -- --lane component --filter prometheus
```

Через `make`:

```bash
make test
make test-main TEST_FLAGS="--json --junit"
make test-live-external TEST_FLAGS="--json"
```

## Contracts

Тестовые contracts лежат в `specs/001-docker-deploy-improvements/contracts/`:

- `test-lanes.md`: canonical lane/group contract
- `test-integration.md`: compatibility contract для integration-family suites
- `test-e2e.md`: compatibility contract для browser/resilience suites
- `scripts.md`: script-level contracts для deploy/backup/health tooling

Если test file ссылается на старый `test-integration.md` или `test-e2e.md`, это compatibility doc, а не разрешение возвращаться к старой directory taxonomy.
