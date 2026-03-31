---
title: "Runtime-only Beads repair still pointed at raw bootstrap after the CLI contract drifted"
date: 2026-03-29
severity: P1
category: process
tags: [beads, dolt, worktree, topology-publish, bootstrap, runtime, rca]
root_cause: "Repo-local runtime repair guidance still routed `runtime_bootstrap_required` to raw `bd bootstrap`, but current `/usr/local/bin/bd` treats a stale `.beads/dolt` shell as already initialized and can no-op without materializing the named `beads` DB."
---

# RCA: Runtime-only Beads repair still pointed at raw bootstrap after the CLI contract drifted

Date: 2026-03-29
Context: dedicated topology publish lane `moltinger-chore-topology-registry-publish`

## Lessons Pre-check

Before writing this RCA, the lessons index and existing RCA set were queried for related incidents:

```bash
./scripts/query-lessons.sh --all | rg -n "topology publish|runtime_bootstrap_required|database \"beads\" not found|worktree|bootstrap-source"
rg -n "topology publish|runtime_bootstrap_required|database \"beads\" not found|worktree|bootstrap-source" docs/rca docs/LESSONS-LEARNED.md
```

Relevant prior lessons:

1. [2026-03-24: Half-initialized Beads Dolt runtime was misclassified as healthy](./2026-03-24-beads-half-initialized-dolt-runtime-misclassified-as-healthy.md)
2. [2026-03-26: Beads worktree localize used a stale bootstrap contract](./2026-03-26-beads-worktree-localize-used-stale-bootstrap-contract.md)
3. [2026-03-28: Managed worktree creation mixed up the create executor and hook bootstrap-source contract](./2026-03-28-worktree-create-helper-and-hook-bootstrap-source-drift.md)

Those lessons already covered incomplete runtime shells, stale helper contracts, and worktree bootstrap drift. They did **not** yet close one remaining gap:

1. Active repo-local repair surfaces still told operators that raw `bd bootstrap` was the sanctioned repair for `runtime_bootstrap_required`, even when the current CLI no longer repaired a stale `.beads/dolt` shell that way.

## Error

The dedicated publish worktree was in the expected post-migration ownership state (`publish_lane=dedicated`, `publish_allowed=true`, no tracked `.beads/issues.jsonl`), but `./scripts/beads-worktree-localize.sh --check` still reported:

```text
State: runtime_bootstrap_required
```

and `/usr/local/bin/bd doctor --json` reported:

```text
database "beads" not found
```

The sanctioned repo guidance still routed this state to raw `bd bootstrap`, but the live CLI contract on `/usr/local/bin/bd` 0.61.0 behaved like this:

```json
{
  "action": "none",
  "reason": "Database already exists at .../.beads/dolt"
}
```

So the publish lane stayed broken even when the documented repair path was followed.

## 5 Whys

| Level | Question | Answer |
|---|---|---|
| 1 | Why did the dedicated publish lane stay in `runtime_bootstrap_required`? | Because the local runtime had only a stale `.beads/dolt` shell and no named `beads` DB, so plain `bd` could not open the backlog. |
| 2 | Why did the sanctioned repair path not fix that state? | Because repo-local guidance still sent operators to raw `bd bootstrap`, and current CLI behavior can no-op when the stale data directory already exists. |
| 3 | Why could raw `bd bootstrap` no-op on a broken runtime shell? | Because the current CLI contract appears to key off the Dolt data-dir presence, not the existence of the named `beads` database inside that runtime. |
| 4 | Why did the repo still trust raw bootstrap for runtime-only repair? | Because previous fixes updated classification and helper internals, but high-traffic worktree rules, audit output, Phase A guidance, and readiness surfaces were not fully revalidated against the live CLI contract. |
| 5 | Why was this caught on the topology publish lane specifically? | Because that lane is a preserved dedicated worktree with local-only runtime artifacts after JSONL retirement, so it hit the exact stale-shell case that raw bootstrap no longer repairs. |

## Root Cause

The root cause was a **source-of-truth contract drift in repo-local Beads repair tooling and instructions**, not just a single broken worktree.

`runtime_bootstrap_required` was still documented and surfaced as:

1. run `/usr/local/bin/bd doctor --json`
2. run raw `bd bootstrap`

That contract was stale. With the current installed Beads CLI, raw `bd bootstrap` can leave a stale `.beads/dolt` shell untouched and never materialize the named `beads` DB. The correct deterministic repair path for runtime-only drift is:

1. quarantine the stale runtime shell
2. rerun bootstrap against a clean runtime dir
3. import the newest tracked-or-compatibility JSONL backup when available

## Fixes Applied

1. Hardened `scripts/beads-worktree-localize.sh`:
   - detects runtime-only stale-shell drift
   - quarantines stale runtime artifacts under `.beads/recovery/`
   - reruns `bd bootstrap` against the cleaned runtime
   - imports the newest compatibility issues backup found across `.beads/backup/` and `.beads/legacy-jsonl-backup/`
2. Re-routed repo-local repair surfaces away from raw `bd bootstrap`:
   - `scripts/beads-resolve-db.sh`
   - `scripts/beads-worktree-audit.sh`
   - `scripts/worktree-phase-a.sh`
   - `scripts/worktree-ready.sh`
   - `.ai/instructions/shared-core.md`
   - `docs/CODEX-OPERATING-MODEL.md`
   - active Beads runtime rules
3. Added regression coverage for the live CLI behavior where raw bootstrap no-ops on a stale shell:
   - `tests/unit/test_bd_dispatch.sh`
   - `tests/unit/test_bd_local.sh`
   - `tests/unit/test_beads_worktree_audit.sh`
   - `tests/unit/test_worktree_phase_a.sh`
   - `tests/unit/test_worktree_ready.sh`
   - `tests/static/test_beads_worktree_ownership.sh`
4. Repaired the target dedicated publish worktree with the managed helper and manually verified, via sequential probes, that `bd status` now reads the backlog there.

## Verification Notes

Two additional observations mattered during verification:

1. Running multiple `bd` probes in parallel against the same worktree can create misleading `dial tcp ... connect: connection refused` races during auto-start. Verification must be sequential.
2. The target worktree is still ahead of its remote branch, but manual sequential verification showed its local Beads runtime was readable and classified as `post_migration_runtime_only`.

## Prevention

1. Treat runtime-only Beads repair as a managed helper contract, not as a bare CLI recipe.
2. Revalidate every active operator-facing repair path against the installed official CLI, not just helper-local mocks.
3. Model stale-shell no-op behavior in regression tests, not only the happy bootstrap path.
4. Keep verification sequential when probing Beads auto-start behavior inside one worktree.

## Related Updates

- [x] Runtime-only stale-shell repair hardened in [beads-worktree-localize.sh](/Users/rl/coding/moltinger/moltinger-main-037-topology-publish-beads-runtime-repair/scripts/beads-worktree-localize.sh)
- [x] Runtime repair routing fixed in [beads-resolve-db.sh](/Users/rl/coding/moltinger/moltinger-main-037-topology-publish-beads-runtime-repair/scripts/beads-resolve-db.sh)
- [x] Audit guidance fixed in [beads-worktree-audit.sh](/Users/rl/coding/moltinger/moltinger-main-037-topology-publish-beads-runtime-repair/scripts/beads-worktree-audit.sh)
- [x] Phase A runtime repair routing fixed in [worktree-phase-a.sh](/Users/rl/coding/moltinger/moltinger-main-037-topology-publish-beads-runtime-repair/scripts/worktree-phase-a.sh)
- [x] Readiness guidance fixed in [worktree-ready.sh](/Users/rl/coding/moltinger/moltinger-main-037-topology-publish-beads-runtime-repair/scripts/worktree-ready.sh)
- [x] Runtime rule drift closed in [beads-runtime-first-jsonl-compatibility-only.md](/Users/rl/coding/moltinger/moltinger-main-037-topology-publish-beads-runtime-repair/docs/rules/beads-runtime-first-jsonl-compatibility-only.md)
- [x] Localize contract drift closed in [beads-worktree-localize-must-bootstrap-and-import-without-moving-head.md](/Users/rl/coding/moltinger/moltinger-main-037-topology-publish-beads-runtime-repair/docs/rules/beads-worktree-localize-must-bootstrap-and-import-without-moving-head.md)

## Уроки

- **Raw `bd bootstrap` больше нельзя считать runtime-only repair recipe**: для stale `.beads/dolt` shell он может честно ничего не сделать.
- **`runtime_bootstrap_required` должен вести в managed helper, а не в bare CLI шаг**: иначе оператор следует “правильной” инструкции и всё равно остаётся в broken state.
- **Regression tests должны моделировать live CLI no-op behavior**: helper mocks без этого снова создадут ложное чувство безопасности.
- **Проверки Beads внутри одного worktree надо делать последовательно**: параллельные auto-start probes дают шумные ложные симптомы.
