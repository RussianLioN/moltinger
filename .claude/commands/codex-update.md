---
description: Check Codex CLI updates for this repository and return a short plain-language report
argument-hint: "[now|telegram|json|why] [optional extra context]"
---

# Codex Update Command

Use this command when the user wants a human-readable Codex CLI update report for the current repository.

## Intent

- Run the delivery layer in `on-demand` mode by default.
- Return a short plain-language summary, not raw script output noise.
- If the user explicitly asks for JSON, return the machine-readable delivery report.
- If the user explicitly asks to send a Telegram notification, run the `telegram` surface with the configured chat target.

## Default Flow

```bash
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout summary
```

## JSON Flow

```bash
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout json
```

## Telegram Flow

Only when the user explicitly asks for Telegram delivery and the chat target is configured:

```bash
bash scripts/codex-cli-update-delivery.sh --surface telegram --telegram-enabled --stdout summary
```

## Response Style

Answer in plain language:
- whether there is a fresh actionable Codex CLI update
- whether this state is new or already known
- what this repository likely needs to review next

If the result is `investigate`, say that clearly and do not overstate certainty.
