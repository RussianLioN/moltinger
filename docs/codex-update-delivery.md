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

## Launch-Time Alert

When Codex is launched through [codex-profile-launch.sh](/Users/rl/coding/moltinger-009-codex-update-delivery-ux/scripts/codex-profile-launch.sh), the launcher performs a non-blocking pre-session delivery check.

Behavior:

- fresh actionable update -> short banner before Codex starts
- duplicate known state -> no repeated banner
- delivery failure -> launch continues without blocking

Opt-out:

```bash
CODEX_UPDATE_LAUNCH_ALERT=0 bash scripts/codex-profile-launch.sh runtime
```

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
bash -n tests/component/test_codex_cli_update_delivery.sh
./tests/component/test_codex_cli_update_delivery.sh
./tests/run.sh --lane component --filter codex_cli_update_delivery
```
