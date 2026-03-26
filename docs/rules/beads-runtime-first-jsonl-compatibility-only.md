# Beads Runtime-First, JSONL Compatibility-Only

## Rule

After the Dolt migration, the authoritative Beads backlog source in this repository is the current worktree's local runtime (`.beads/beads.db` or `.beads/dolt/`), not tracked `.beads/issues.jsonl`.

If `.beads/issues.jsonl` is still present in a branch, treat it only as a temporary compatibility/bootstrap artifact.

## Required Behavior

1. Prefer `bd status`, `bd list`, `bd ready`, `bd show`, `bd doctor --json`, and `bd bootstrap` over any JSONL restoration flow.
2. Do not describe tracked `.beads/issues.jsonl` as the source of truth in active instructions.
3. Do not reintroduce `bd sync` into ordinary workflows.
4. Do not restore `.beads/issues.jsonl` to repair `config + local runtime + missing named beads DB`.
5. If a compatibility flow still requires `.beads/issues.jsonl`, label it explicitly as transitional and plan its removal.

## Why

Dual state (`local Dolt runtime` plus tracked `.beads/issues.jsonl`) already caused stale-export drift, dirty canonical-root diffs, and wrong recovery instincts. The runtime-first contract reduces drift and keeps recovery focused on the real storage surface.

## Migration Note

This rule does not by itself remove `.beads/issues.jsonl` from git. Full untracking must happen only after handoff, bootstrap, and recovery flows stop requiring the file.
