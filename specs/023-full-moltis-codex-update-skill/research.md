# Research: Full Moltis-Native Codex Update Skill

## Problem Framing

The current codebase contains a useful but hybrid path:

- repo-side scripts still own upstream polling and decision logic;
- Moltis owns only parts of the Telegram UX;
- the old Codex bridge is retired, but the canonical skill still does not fully live in Moltis.

That is sufficient as a migration bridge, but it does not match the corrected product goal.

## Key Findings

1. `scripts/codex-cli-upstream-watcher.sh` remains the main runtime owner for upstream checking, severity, digesting, and alert decisions.
2. `specs/021-moltis-native-codex-update-advisory/` intentionally chose a hybrid producer/consumer split.
3. `config/moltis.toml` already supports Moltis skills and auto-load, so a first-class Moltis-native skill is a natural fit.
4. Moltis already owns Telegram ingress, making it the correct place for alert and follow-up UX.
5. The repo can still contribute optional project-specific applicability via static profile/manifest contracts.

## Decision

Adopt a new canonical architecture:

- Moltis skill/agent = scheduler + upstream fetch + fingerprint state + on-demand query path + Telegram delivery + optional project profile interpretation.
- Repo-side legacy watcher path = migration fallback only, not product target.

## Reuse Strategy

Temporarily reusable:

- Codex changelog parsing heuristics from `scripts/codex-cli-upstream-watcher.sh`
- Existing Russian explanation patterns
- Existing Telegram send helper
- Existing acceptance fixtures and component-test style

To be retired from canonical ownership:

- repo-side scheduler as the primary runtime
- repo-side advisory bridge as the primary user entrypoint
- any UX that assumes Codex or repo scripts are the user's main interface for this feature

## Open Design Choices

1. Whether project-specific applicability is driven only by a static profile file.
2. Whether state remains shell-managed initially or moves into a more native Moltis persistence surface later.
3. Whether advisory issue signals remain enabled by default or become opt-in enrichment.
