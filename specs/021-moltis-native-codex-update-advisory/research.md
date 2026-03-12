# Research: Moltis-Native Codex Update Advisory Flow

## Inputs Reviewed

- `specs/009-codex-update-delivery-ux/spec.md`
- `specs/012-codex-upstream-watcher/spec.md`
- `specs/017-codex-telegram-consent-routing/spec.md`
- `docs/codex-update-delivery.md`
- `docs/codex-cli-upstream-watcher.md`
- `config/moltis.toml`
- live Moltis logs showing `/codex_da` reaching generic chat instead of consent routing
- consilium evidence collected on 2026-03-12

## Key Findings

1. Repo-side delivery scripts are good producers of normalized Codex update evidence, but poor owners of the live Telegram dialogue.
2. Telegram reply-keyboard buttons are structurally wrong for this flow because they emit plain chat text, which generic Moltis chat will consume first.
3. Moltis already owns Telegram ingress operationally, so the user-facing advisory flow should move there as a first-class feature.
4. The safe current production state is `one-way alert`; interactive follow-up must not be advertised until the Moltis-native path exists.
5. The existing watcher/advisor work should be preserved as producer-side logic instead of being reimplemented from scratch inside Moltis.

## Decisions

### Decision 1: Keep watcher/advisor as producer-side logic

- **Why**: Reusing existing Codex-specific parsing and recommendation preparation avoids duplicating upstream logic in the Telegram runtime.
- **Alternative rejected**: Move all parsing and recommendation generation into Moltis immediately.

### Decision 2: Move Telegram alert/callback/follow-up ownership into Moltis

- **Why**: One consumer of Telegram updates is safer and simpler than split ownership.
- **Alternative rejected**: Keep patching repo-side hooks and text-command reply flows.

### Decision 3: Prefer inline callbacks as the primary interaction

- **Why**: This is the standard Telegram pattern for short accept/decline flows.
- **Fallback**: deep-link or tokenized recovery path when callback mode is unavailable.

### Decision 4: Keep production degraded to one-way until Moltis-native path lands

- **Why**: Live UX must never promise a broken interactive follow-up.
- **Alternative rejected**: Continue showing `/codex_da` or similar text-command affordances.

### Decision 5: Retire the old Codex bridge immediately

- **Why**: Users should not be routed into a path that is known to be structurally broken.
- **Consequence**: Skill sync and docs must reflect that the current bridge is disabled pending replacement.
