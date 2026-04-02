# Research: Telegram Learner Hardening

## Canonical Project Artifacts

### Decision

Use existing project-native guidance as the base for all learner-skill changes:

- [docs/moltis-skill-agent-authoring.md](../../docs/moltis-skill-agent-authoring.md)
- [docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md](../../docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md)

### Rationale

These are already the repository's canonical sources for Moltis skill authoring and self-learning. They explicitly require thin skills, canonical runtime boundaries and runtime visibility proof.

### Alternatives considered

- Treat current `skills/telegram-learner/SKILL.md` as the only source of truth: rejected because it is already part of the problem.
- Invent a new standalone guide without referencing existing docs: rejected because it would duplicate and drift.

## Upstream And Community Signals

### Decision

Use official OpenClaw issues as primary external evidence for Telegram/runtime delivery risks and skill/tool boundary regressions:

1. `openclaw/openclaw#10848` — Telegram message-tool sends can race with normal replies and arrive out of order.
2. `openclaw/openclaw#25267` — tool-result media can outrun preceding text blocks due to missing awaited flush.
3. `openclaw/openclaw#54909` — Telegram callback events can hallucinate confirmations instead of performing the instructed tool action.
4. `openclaw/openclaw#7158` — skill integration can return blank, while an exec-based workaround works.

### Rationale

These issues reinforce the same theme seen locally:

- Telegram delivery paths are fragile when tool execution and normal replies compete.
- Skills that imply real tool work without a deterministic runtime-owned path can degrade into hallucinated or blank behavior.
- Operator-heavy skill authoring increases pressure toward unsafe tool paths.

### Alternatives considered

- Community-only social threads or generic AI forums: useful later, but weaker than official repo issues for this technical slice.

## Consilium Synthesis

Across architecture/runtime/UAT review, the following improvements emerged:

1. Make `telegram-learner` a thin skill contract instead of a mini-handbook.
2. Encode explicit `official-first` sourcing order.
3. Separate Telegram-safe explainer surface from operator/worker ingestion workflow.
4. Build value-first skill-detail replies instead of document-structure summaries.
5. Remove internal workflow markup (`Workflow`, `Phase`, `Когда использовать`, filesystem paths) from Telegram-facing outputs.
6. Keep typo resolution quiet (`telegram-lerner` should simply resolve to `telegram-learner`).
7. Add a similar learner skill for regression coverage, not just one special-cased skill.
8. Add explicit degraded mode when official confirmation is unavailable.
9. Keep Telegram-safe replies to 2-3 short sentences and one clean delivery.

## First Five Improvements To Implement Now

1. Rewrite `skills/telegram-learner/SKILL.md` as a thin learner-skill contract.
2. Update `build_skill_detail_reply_text()` to emit concise value-first learner replies.
3. Remove meta phrases and internal workflow structure from skill-detail tests and outputs.
4. Add a similar learner skill focused on OpenClaw improvements/news.
5. Add component coverage for generic learner-skill detail output and clean typo resolution.
