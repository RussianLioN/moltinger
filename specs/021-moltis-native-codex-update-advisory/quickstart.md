# Quickstart: Moltis-Native Codex Update Advisory Flow

## Goal

Validate the future ownership model:

1. repo-side tooling produces one normalized Codex advisory event;
2. Moltis sends the Telegram alert;
3. Moltis handles the callback;
4. Moltis sends the practical recommendations immediately;
5. if callback mode is unavailable, Moltis sends only a one-way alert.

## Current Precondition

Before this feature is implemented:

- the old Codex bridge is retired;
- production stays in `one-way alert`;
- interactive Telegram follow-up is intentionally disabled.

## Target Healthy Path

1. Generate a normalized advisory event from the repo-side watcher/advisor flow.
2. Hand that event to Moltis through the agreed contract.
3. Confirm Telegram receives one Russian alert with inline actions.
4. Press `accept`.
5. Confirm recommendations arrive in the same chat within 10 seconds.
6. Press `accept` again and confirm no duplicate recommendations are sent.

## Target Degraded Path

1. Disable or break callback routing in Moltis.
2. Send the same advisory event again with a fresh fingerprint.
3. Confirm Telegram receives only a one-way alert.
4. Confirm the message does not ask the user to type `/codex_*` or any similar text command.
5. Confirm the audit record stores the degraded reason.

## Minimal Validation Commands

Bridge sync after retiring the old Codex entrypoints:

```bash
./scripts/sync-claude-skills-to-codex.sh --install
./scripts/sync-claude-skills-to-codex.sh --check
```

Producer-side checks that should stay valid:

```bash
make codex-upstream-watcher
make codex-update-advisor
```

## Expected User Outcome

- Users get a clean Telegram advisory from Moltis.
- Users no longer see broken reply-keyboard text commands.
- Recommendations arrive only through a real Moltis-native interactive path.
