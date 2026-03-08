# Docs Instructions

This directory contains durable project documentation, plans, RCA reports, research, and generated knowledge summaries.

## Core Rule

Do not bloat central files.
If content is substantial, create a new file and link to it instead of enlarging a high-traffic file.

## Structure

Use the existing directory meanings:

- `docs/rca/` for incident RCA reports
- `docs/reports/` for research and analytical reports
- `docs/research/` for reference research and synthesis
- `docs/plans/` for implementation or strategy plans
- `docs/rules/` for reusable operational rules
- top-level `docs/*.md` for stable project docs only

## Rules

1. Put content in the right place.
   Do not mix RCA, research, reports, and plans.
2. Respect generated files.
   If a file says it is auto-generated, do not hand-edit it.
3. Keep handoff-friendly structure.
   Documents should help the next session recover quickly.
4. Prefer concise durable summaries over raw dumps.
   Save noise elsewhere.
5. If you add a new RCA, make sure the lessons flow is completed.
   Rebuild or refresh the lessons index when the workflow requires it.
6. Preserve links and navigation.
   If you move or replace a doc, update references.

## Special Cases

- `docs/LESSONS-LEARNED.md` is generated. Do not manually curate it inline.
- `docs/GIT-TOPOLOGY-REGISTRY.md` is an operational registry and should stay accurate.
- Large ad hoc session narratives belong in a dedicated file, not inside central instruction files.

## Validation

After doc changes, verify:
- the file location is appropriate
- references are still valid
- generated-vs-manual boundaries are respected
- the document is concise enough for repeated reading
