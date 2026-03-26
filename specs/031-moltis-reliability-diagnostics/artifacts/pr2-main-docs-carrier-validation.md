# PR2 Main Docs Carrier Validation

## Goal

Prove that the docs-only `PR2` carrier can be applied to the current verified `origin/main` state without dragging along runtime-affecting paths.

## Materialized Artifacts

- `specs/031-moltis-reliability-diagnostics/artifacts/pr2-main-docs-carrier.md`
- `specs/031-moltis-reliability-diagnostics/artifacts/pr2-main-docs-carrier.patch`

## Generation Contract

The carrier patch is generated against the real target base:

1. tracked changes use `git diff origin/main -- <allowlist paths>`
2. new docs use `git diff --no-index -- /dev/null <new-file>`

This avoids both known failure modes:

- merge-base drift from `three-dot` diffs
- missing untracked docs in plain `git diff <base>` output

## Validation

Dry-run executed against a clean export of `origin/main`:

```bash
tmpdir=$(mktemp -d)
git archive origin/main | tar -x -C "$tmpdir"
patch -p1 --dry-run -d "$tmpdir" < specs/031-moltis-reliability-diagnostics/artifacts/pr2-main-docs-carrier.patch
```

Result:

- `patch --dry-run` succeeded
- patch touched only docs/process paths from the allowlist
- no `scripts/`, `tests/`, `.github/`, `docker-compose*`, or `config/` paths entered the carrier
