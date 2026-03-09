# Codex Update Delivery UX

`009-codex-update-delivery-ux` turns the existing monitor and advisor into user-facing delivery surfaces.

## What The User Gets

There are now three supported surfaces:

1. On-demand report inside Codex.
2. Launch-time alert when starting Codex through the repo launcher.
3. Optional Telegram delivery through the existing bot sender.

The delivery layer does not compute recommendations on its own.  
It reuses `scripts/codex-cli-update-advisor.sh` as the single source of truth and decides only how and where to present that result.

## On-Demand Usage

Direct script entrypoint:

```bash
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout summary
```

Machine-readable mode:

```bash
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout json
```

Repo-facing command surface:

- [.claude/commands/codex-update.md](/Users/rl/coding/moltinger-009-codex-update-delivery-ux/.claude/commands/codex-update.md)

Optional skill surface:

- [.claude/skills/codex-update-delivery/SKILL.md](/Users/rl/coding/moltinger-009-codex-update-delivery-ux/.claude/skills/codex-update-delivery/SKILL.md)

## Automatic Startup Delivery

When Codex is launched through [codex-profile-launch.sh](/Users/rl/coding/moltinger-009-codex-update-delivery-ux/scripts/codex-profile-launch.sh), the launcher performs a non-blocking pre-session delivery check.

Behavior:

- fresh actionable update -> short banner before Codex starts
- duplicate known state -> no repeated banner
- delivery failure -> launch continues without blocking
- optional Telegram hook -> launcher can also trigger the Telegram surface in the background for the same delivery state

Opt-out:

```bash
CODEX_UPDATE_LAUNCH_ALERT=0 bash scripts/codex-profile-launch.sh runtime
```

Enable launcher-triggered Telegram delivery:

```bash
CODEX_UPDATE_LAUNCH_TELEGRAM=1 \
CODEX_UPDATE_DELIVERY_TELEGRAM_CHAT_ID=262872984 \
bash scripts/codex-profile-launch.sh runtime
```

This path is intentionally fail-open:

- the banner check runs inline but never blocks Codex startup on failure
- the Telegram send runs in the background and never blocks Codex startup
- duplicate Telegram sends are still suppressed by the shared delivery state

## Why Startup, Not Server Cron

The primary automation path is the local Codex launcher, not a Moltinger host cron job.

Reason:

- the monitored Codex CLI is the user's local CLI, not the server runtime
- the Moltinger server currently does not have `codex` installed
- a server-side scheduler would monitor the wrong environment unless local Codex state were exported there first

Future schedulers are still possible, but the reliable v1 automation point is startup through the repo launcher.

## Telegram Delivery

Telegram delivery is explicit and opt-in.

Example:

```bash
bash scripts/codex-cli-update-delivery.sh \
  --surface telegram \
  --telegram-enabled \
  --telegram-chat-id 123456 \
  --stdout summary
```

Optional env file for bot token loading:

```bash
bash scripts/codex-cli-update-delivery.sh \
  --surface telegram \
  --telegram-enabled \
  --telegram-chat-id 123456 \
  --telegram-env-file .env \
  --stdout summary
```

The transport is delegated to [telegram-bot-send.sh](/Users/rl/coding/moltinger-009-codex-update-delivery-ux/scripts/telegram-bot-send.sh). Duplicate Telegram sends are suppressed per fingerprint.

For startup-triggered Telegram delivery without a local bot token, the launcher defaults to [telegram-bot-send-remote.sh](/Users/rl/coding/moltinger-009-codex-update-delivery-ux/scripts/telegram-bot-send-remote.sh). That wrapper delegates the send over SSH to the Moltinger server runtime, which already has the configured bot token in `/opt/moltinger/.env`.

Relevant launcher env vars:

- `CODEX_UPDATE_LAUNCH_TELEGRAM=1`
- `CODEX_UPDATE_DELIVERY_TELEGRAM_CHAT_ID=<chat-id>`
- `CODEX_UPDATE_LAUNCH_TELEGRAM_SEND_SCRIPT=/path/to/custom-sender.sh` if you want to override the default remote sender

Relevant remote sender env vars:

- `MOLTINGER_TELEGRAM_SSH_TARGET` default `root@ainetic.tech`
- `MOLTINGER_TELEGRAM_REMOTE_ROOT` default `/opt/moltinger`
- `MOLTINGER_TELEGRAM_REMOTE_ENV_FILE` default `/opt/moltinger/.env`
- `MOLTINGER_TELEGRAM_SSH_CONNECT_TIMEOUT` default `20`

## State Files

- advisor state: `.tmp/current/codex-cli-update-advisor-state.json`
- delivery state: `.tmp/current/codex-cli-update-delivery-state.json`

The delivery state is per-surface, so an on-demand report does not prevent a later launcher alert or Telegram send for the same fresh fingerprint.

## Make Target

```bash
make codex-update-delivery
```

## Validation

```bash
bash -n scripts/codex-cli-update-delivery.sh
bash -n scripts/codex-profile-launch.sh
bash -n scripts/telegram-bot-send-remote.sh
bash -n tests/component/test_codex_cli_update_delivery.sh
bash -n tests/component/test_codex_profile_launch.sh
bash -n tests/component/test_telegram_bot_send_remote.sh
./tests/component/test_codex_cli_update_delivery.sh
./tests/component/test_codex_profile_launch.sh
./tests/component/test_telegram_bot_send_remote.sh
./tests/run.sh --lane component --filter 'codex_cli_update_delivery|codex_profile_launch|telegram_bot_send_remote'
```
