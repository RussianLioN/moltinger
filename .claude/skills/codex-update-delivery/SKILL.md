# Codex Update Delivery

Use this skill when the user asks in plain language to check Codex CLI updates for the current repository, wants a short repository-specific report, or asks to send the result to Telegram.

## What This Skill Does

It uses the delivery layer on top of the completed advisor:

- `on-demand` for a plain-language report
- `launcher` for pre-session alerts
- `telegram` for explicit Telegram delivery

The skill should prefer:

```bash
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout summary
```

If the user explicitly wants machine-readable output:

```bash
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout json
```

If the user explicitly wants Telegram delivery and a chat target is configured:

```bash
bash scripts/codex-cli-update-delivery.sh --surface telegram --telegram-enabled --stdout summary
```

## Output Expectations

Explain simply:
- whether a fresh actionable update exists
- whether the state is already known
- which repository surfaces likely need follow-up

Do not dump raw JSON unless the user asked for it.
