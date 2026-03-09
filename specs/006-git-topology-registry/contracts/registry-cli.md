# Contract: Git Topology Registry Script Interface

## Commands

### `refresh --write-doc`

Reconcile current live git topology and update the committed registry document if normalized topology changed.

**Expected behavior**:
- exits `0` on success
- writes no diff when topology is unchanged
- preserves reviewed intent from sidecar data
- does not mutate git topology itself

### `check`

Compare current live git topology with the committed registry.

**Expected behavior**:
- exits `0` when registry matches normalized live topology
- exits non-zero when registry is stale or invalid
- prints actionable remediation text

### `status`

Report registry health state.

**Expected behavior**:
- returns one of `ok`, `stale`, or `error`
- includes current topology hash and rendered hash when available
- does not write tracked files

### `doctor --prune --write-doc`

Recover from stale or missed topology changes.

**Expected behavior**:
- rebuilds registry state from live git
- can prune stale worktree metadata before rendering when explicitly requested
- preserves last good committed registry if recovery fails

## Non-Goals

- No branch deletion
- No worktree deletion
- No auto-merge or rebase behavior
- No hidden commit or push behavior
