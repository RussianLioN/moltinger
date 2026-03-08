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

## Final Sidecar Contract

- **Filename**: `docs/GIT-TOPOLOGY-INTENT.yaml`
- **Encoding**: UTF-8 YAML with deterministic key order
- **Top-level keys**:
  - `version` (integer, required)
  - `defaults.missing_intent` (enum, required)
  - `records` (array, required)
- **Record shape**:
  - `subject_type` (`branch` | `worktree` | `remote`)
  - `subject_key` (stable sanitized identifier or remote ref)
  - `intent` (`active` | `historical` | `extract-only` | `cleanup-candidate` | `protected` | `needs-decision`)
  - `note` (short reviewed note, optional)
  - `pr` (integer, optional)

## Sidecar Determinism Rules

- Records sort by `subject_type`, then `subject_key`
- `subject_key` must match the rendered row key used in the registry
- Notes must stay short and safe to commit
- Unknown or missing records must not block rendering; they fall back to `needs-decision`
