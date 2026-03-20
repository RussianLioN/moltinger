# Contract: RCA Evidence

## Purpose

Зафиксировать минимальный reproducible evidence set для drift/шума `.beads/issues.jsonl`.

## Minimum Scenario Coverage

1. Dedicated worktree leakage attempt toward canonical root
2. Noise-only rewrite without semantic issue change
3. Ambiguous ownership scenario
4. Safe semantic rewrite with byte-stable rerun

## Required Inputs Per Run

- scenario identifier
- fixture or operator context description
- current topology/worktree summary
- current ownership state
- attempted operation
- expected verdict

## Required Outputs Per Run

- stable run identifier
- machine-readable verdict
- authority decision code
- target path that would be touched or was touched
- before/after hashes
- human-readable step log
- references to produced evidence files

## Reproducibility Rules

1. Running the same scenario on the same fixture must preserve verdict and core decision codes.
2. Logs must be sufficient for review without manual reconstruction from unrelated shell history.
3. RCA output must distinguish semantic mutation from noise-only rewrite.
4. RCA output must never imply that canonical-root cleanup happened unless it actually belongs to the explicit scenario.
