# Validation: UX-Safe Beads Local Ownership

Date: 2026-03-12
Worktree: `/Users/rl/coding/moltinger-016-beads-local-db-ux`

## Runtime Checks

### Plain `bd` resolves to the worktree-local DB

Command:

```bash
PATH="/Users/rl/coding/moltinger-016-beads-local-db-ux/bin:$PATH" bin/bd info
```

Result:
- Passed
- Database resolved to `/Users/rl/coding/moltinger-016-beads-local-db-ux/.beads/beads.db`
- Mode reported `direct`

### Resolver reports the dedicated-worktree local decision

Command:

```bash
scripts/beads-resolve-db.sh --format human info
```

Result:
- Passed
- Decision: `execute_local`
- Context: `dedicated_worktree`
- Canonical root remained `/Users/rl/coding/moltinger`

## Targeted Automated Checks

### Shell syntax

Command:

```bash
bash -n bin/bd scripts/beads-resolve-db.sh scripts/beads-worktree-localize.sh scripts/codex-profile-launch.sh scripts/worktree-ready.sh scripts/worktree-phase-a.sh tests/unit/test_bd_dispatch.sh tests/static/test_beads_worktree_ownership.sh
```

Result:
- Passed

### Dispatch unit coverage

Command:

```bash
./tests/unit/test_bd_dispatch.sh
```

Result:
- Passed
- 5 / 5 tests green
- Covered local dispatch, legacy redirect block, root-fallback block, explicit troubleshooting pass-through, and managed localization

### Worktree Phase A regression coverage

Command:

```bash
./tests/unit/test_worktree_phase_a.sh
```

Result:
- Passed
- 2 / 2 tests green

### Worktree readiness regression coverage

Command:

```bash
./tests/unit/test_worktree_ready.sh
```

Result:
- Passed
- 20 / 20 tests green
- Includes doctor regression for managed Beads localization and no raw `bd worktree create` fallback

### Static ownership guardrails

Command:

```bash
./tests/static/test_beads_worktree_ownership.sh
./tests/run.sh --lane static --filter beads_worktree_ownership
```

Result:
- Passed
- 7 / 7 static cases green
- Runner integration confirmed through `tests/run.sh`

### Codex governance validation

Command:

```bash
make codex-check
```

Result:
- Passed
- Required governance files, generated instructions, and bridge integrity checks all passed

## Quickstart Scenario Coverage

The quickstart scenarios in `quickstart.md` are covered by the runtime and regression checks above:

- Scenario 1-3: validated by `bin/bd info`, resolver output, and `test_bd_dispatch.sh`
- Scenario 4-5: validated by `test_bd_dispatch.sh`
- Scenario 6: validated by resolver behavior and the explicit separate root-cleanup notice path
- Scenario 7: validated by `test_beads_worktree_ownership.sh`
- Scenario 8: validated by the explicit troubleshooting pass-through case in `test_bd_dispatch.sh`
