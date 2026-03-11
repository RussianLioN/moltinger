# CLI Contract: `scripts/beads-recovery-batch.sh`

## Modes

### `audit`

Build a deterministic recovery plan without modifying tracker state.

#### Required behavior

- Read leaked issues from the canonical root tracker or an explicit source JSONL path
- Read live worktree topology
- Read optional ownership overrides
- Emit one JSON plan artifact
- Exit non-zero only for command/setup errors, not for blocked candidates

#### Inputs

- `--output <path>`: required plan artifact path
- `--source-jsonl <path>`: optional source snapshot override
- `--ownership-map <path>`: optional explicit ownership override file

### `apply`

Apply only the safe items already declared in a plan artifact.

#### Required behavior

- Refuse to run without `--plan`
- For legacy `plan/v1`, refuse to run if the global topology fingerprint no longer matches live topology
- For `plan/v2`, revalidate only the candidate-scoped write set before each recovery action
- Treat unrelated topology drift as advisory only; record it in the journal instead of aborting the whole run
- Localize redirected safe targets before recovery
- Recover only `confidence=high` items with `blockers=[]`
- Block only the affected candidate when owner branch/worktree, source issue identity, or redirect contract drifts
- Write one journal plus per-worktree backups
- Never delete canonical root tracker entries

#### Inputs

- `--plan <path>`: required plan artifact
- `--journal-dir <path>`: optional output directory for journals and backups

## Exit Codes

- `0`: command succeeded; blocked items may still exist
- `2`: usage or required-input error
- `3`: legacy plan is stale or incompatible with live topology
- `4`: one or more safe actions failed during apply

## Output Guarantees

- `audit` always produces one JSON plan at the requested path
- `apply` always produces one JSON journal if it starts execution
- `plan/v2` journals include candidate validation results and advisory full-topology drift status
- Human-readable summary is printed to stdout in both modes
