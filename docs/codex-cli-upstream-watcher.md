# Codex CLI Upstream Watcher

`codex-cli-upstream-watcher.sh` watches official Codex upstream sources without requiring a local `codex` binary on the watcher host.

It answers a simple question:

- is there a fresh upstream Codex state?
- is it already known?
- should Telegram deliver one new alert or suppress it?

The watcher stays upstream-only. It does not try to decide whether this repository should change locally.

## Manual operator run

```bash
mkdir -p .tmp/current

./scripts/codex-cli-upstream-watcher.sh \
  --mode manual \
  --json-out .tmp/current/codex-upstream-watcher-report.json \
  --summary-out .tmp/current/codex-upstream-watcher-summary.md \
  --stdout summary
```

What the operator gets:

- short plain-language summary in the terminal
- deterministic JSON report
- persisted watcher state in `.tmp/current/codex-cli-upstream-watcher-state.json`

Plain-language outcomes:

- `deliver`: a fresh upstream fingerprint was found
- `suppress`: this fingerprint was already seen before
- `investigate`: the primary changelog source was unavailable or malformed
- `retry`: Telegram failed after a schedulable upstream state was found

## Advisory issue signals

Optional issue signals add extra awareness without replacing the official changelog as release truth.

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode manual \
  --include-issue-signals \
  --issue-signals-url "https://api.github.com/repos/openai/codex/issues?state=open&per_page=20"
```

Issue signals affect source notes and operator context, but they do not override the release decision on their own.

## Scheduler and Telegram

Scheduler mode is intended for the Moltinger host.

```bash
./scripts/codex-cli-upstream-watcher.sh \
  --mode scheduler \
  --include-issue-signals \
  --telegram-enabled \
  --telegram-env-file /opt/moltinger/.env \
  --json-out /opt/moltinger/.tmp/current/codex-upstream-watcher-report.json \
  --summary-out /opt/moltinger/.tmp/current/codex-upstream-watcher-summary.md \
  --stdout none
```

Telegram behavior:

- a fresh upstream fingerprint sends one alert
- the same fingerprint is suppressed on repeat runs
- a Telegram failure becomes `retry` and stays retryable

If `--telegram-chat-id` is not passed, the watcher resolves the target in this order:

1. `CODEX_UPSTREAM_WATCHER_TELEGRAM_CHAT_ID` from the env file
2. first id from `TELEGRAM_ALLOWED_USERS` in the env file

This keeps the feature compatible with the existing Moltinger bot runtime.

## Cron installation

The repository-managed cron artifact is:

- `scripts/cron.d/moltis-codex-upstream-watcher`

It is installed by `.github/workflows/deploy.yml` together with the rest of `scripts/cron.d/`.

The cron job:

- writes logs to `/var/log/moltis/codex-upstream-watcher.log`
- keeps state under `/opt/moltinger/.tmp/current/`
- reads Telegram credentials from `/opt/moltinger/.env`

## Output contract

Top-level report fields:

- `checked_at`
- `snapshot`
- `fingerprint`
- `decision`
- `state`
- `telegram_target`
- `notes`

Important semantics:

- `snapshot.release_status` tells whether upstream looks `new`, `known`, `investigate`, or `unavailable`
- `decision.status` tells what the watcher should do now: `deliver`, `suppress`, `retry`, or `investigate`
- `state.last_delivered_fingerprint` is only updated after a successful Telegram delivery path

## UX examples

Example 1: fresh upstream release during a manual check

- summary says a fresh upstream Codex version exists
- decision is `deliver`
- no Telegram is sent because the run is manual

Example 2: scheduled run sees the same already-delivered release

- summary/report say the fingerprint is already known
- decision is `suppress`
- Telegram is not called again

Example 3: changelog source breaks temporarily

- summary/report say `investigate`
- previous delivered fingerprint stays intact
- recovery to the same fingerprint later suppresses instead of resending
