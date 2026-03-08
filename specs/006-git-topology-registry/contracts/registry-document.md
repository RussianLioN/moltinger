# Contract: Git Topology Registry Document

## Required Sections

1. Header with status/scope/purpose
2. Current worktrees section
3. Active local branches section
4. Remote branches not merged into canonical main section
5. Operating rules / policy section
6. Source commands or provenance section

## Format Rules

- Deterministic section order
- Deterministic row sort order
- Sanitized committed values only
- No absolute workstation paths in rendered topology tables
- No volatile per-commit worktree `HEAD` column in the committed document

## Intent Merge Rules

- Generated topology facts come from live git
- Reviewed intent comes from the sidecar file
- Missing sidecar entries default to `needs-decision`
- Orphaned sidecar entries must be preserved or surfaced explicitly until reviewed
