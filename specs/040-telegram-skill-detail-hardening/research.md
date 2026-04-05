# Research: Telegram Skill Detail Hardening

## Official Sources

### Decision

Use OpenClaw official docs as the primary contract for skill structure and keep repo-side Telegram-safe frontmatter as a Moltinger-owned extension.

Primary sources:

- `https://docs.openclaw.ai/skills`
- `https://docs.openclaw.ai/tools/creating-skills`
- local project guide `docs/moltis-skill-agent-authoring.md`

### Rationale

OpenClaw official docs define `SKILL.md` as the canonical skill artifact with `name` and `description` in frontmatter and emphasize small focused skills. That supports our direction: keep the base skill contract thin and add repo-owned Telegram-safe summary metadata instead of extracting user replies from long operator sections.

### Alternatives considered

- Rely on community-only recipes: rejected as primary truth.
- Treat current `SKILL.md` body as the only summary source: rejected because operator-heavy bodies already produced poor Telegram replies.

## Upstream Issues

### Decision

Treat Telegram delivery/tool-ordering issues and skill regressions in the official OpenClaw repo as confirmation that user-facing Telegram paths need deterministic, terminalized handling.

Relevant evidence:

1. Official repo issue search shows Telegram delivery ordering regressions and message routing anomalies in OpenClaw.
2. Official repo issue search also shows skill/runtime regressions where the skill path can fail or behave inconsistently compared with explicit exec/manual fallback.
3. These issues align with our local RCA trail: mixed delivery/tool modes are fragile in Telegram, especially when a deterministic answer should have ended the turn earlier.

### Rationale

We should not assume that “allowlisted tool + safe wording” is enough in Telegram once the intent is actually deterministic skill detail. Upstream issues support the stricter contract: classify -> answer -> terminate.

## Community Signals

### Decision

Use community guidance only as a secondary signal for authoring style: keep skill instructions concise, use progressive disclosure, and avoid giant monolithic operator blobs in `SKILL.md`.

### Rationale

Community materials consistently reinforce the same pattern:

- short skills are easier to route correctly;
- large skill files create ambiguity and token bloat;
- progressive disclosure beats one giant all-purpose prompt.

This is consistent with our own repo lessons.

## Consilium Synthesis

Across runtime, authoring, and test audits the following improvements emerged:

1. Make `skill_detail` terminal and no-tool once the turn is classified.
2. Suppress even allowlisted Tavily inside persisted/current `skill_detail` turns.
3. Keep Tavily allowlist only for non-skill-detail research/advisory turns.
4. Require explicit Telegram-safe frontmatter for repo-managed user-facing skills.
5. Use frontmatter as the user-facing summary contract instead of parsing operator-heavy body sections.
6. Add component coverage for more than one skill family (`learner`, `advisory`, `classifier`).
7. Add static validation so missing frontmatter fails before live/UAT.
8. Keep typo resolution silent and canonicalize the reply to the real skill name only.
9. Preserve RCA/lessons separation: learner-only fixes and general skill-detail hardening are different incidents.

## First Five Improvements To Implement Now

1. Suppress all tool dispatch in `BeforeToolCall` when `skill_detail` intent is active.
2. Add Telegram-safe frontmatter contract to `codex-update`.
3. Add Telegram-safe frontmatter contract to `post-close-task-classifier`.
4. Add static contract validation for all current repo-managed user-facing skills.
5. Add component coverage for `codex-update`, `post-close-task-classifier`, and persisted `skill_detail` + Tavily suppression.
