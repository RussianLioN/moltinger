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
- Refuse to run if the plan topology fingerprint no longer matches live topology
- Localize redirected safe targets before recovery
- Recover only `confidence=high` items with `blockers=[]`
- Write one journal plus per-worktree backups
- Never delete canonical root tracker entries

#### Inputs

- `--plan <path>`: required plan artifact
- `--journal-dir <path>`: optional output directory for journals and backups

## Exit Codes

- `0`: command succeeded; blocked items may still exist
- `2`: usage or required-input error
- `3`: plan is stale or incompatible with live topology
- `4`: one or more safe actions failed during apply

## Output Guarantees

- `audit` always produces one JSON plan at the requested path
- `apply` always produces one JSON journal if it starts execution
- Human-readable summary is printed to stdout in both modes
