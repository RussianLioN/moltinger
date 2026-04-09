# Operator-Facing Task Report Contract

Use this rule when the user asks for a task report, summary, "простыми словами", "кратко", or an executive update after implementation/review work.

## Goal

Keep operator-facing reports short, predictable, and immediately useful.

The default simple report shape is:

1. `Что сделано`
2. `Что это дает`
3. `Что дальше`

## Required behavior

- If the user explicitly asks for a simple summary, answer in the three-section shape above unless the user requested a different format.
- Each section should stay short:
  - 1 short paragraph, or
  - 1-3 flat bullets if the content is inherently list-shaped.
- Prefer user impact and operational meaning over file-by-file changelog.
- Do not front-load branch names, commit SHAs, or path inventories unless the user explicitly asked for technical status.
- If work is incomplete, say so directly in `Что дальше` instead of burying the blocker in implementation detail.
- If the user asks for even shorter wording, compress the same contract into 3-5 sentences while preserving the same three ideas.

## Forbidden defaults

- Do not dump a changelog when the user asked for "простыми словами".
- Do not answer with long technical inventory before the simple summary.
- Do not force architecture/process narration when the user asked for a practical report.
- Do not replace the report with motivational or conversational filler.

## Rationale

The user should not need to decode implementation detail to understand task outcome, value, and next action.
