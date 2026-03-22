# Plan: Moltis Immutable Release Roots And Runtime Attestation

## Goal

Eliminate silent runtime provenance drift for production Moltis, while keeping OAuth, provider keys, session state, and runtime memory outside git.

## Current Safe Baseline

- Git-managed checkout root: `/opt/moltinger`
- Active automation root: `/opt/moltinger-active`
- Writable runtime config: `/opt/moltinger-state/config-runtime`
- Durable runtime home: `/home/moltis/.moltis` host-backed mount
- Canonical deploy proof: tracked deploy + canonical smoke/UAT

This baseline is already much safer than before, but `/opt/moltinger` is still a mutable checkout. That means runtime provenance must be attested explicitly until a future immutable release-root topology is introduced.

## Phase 1: Attestation-First Hardening

Land now:

1. Shared runtime attestation contract
   - script: `scripts/moltis-runtime-attestation.sh`
   - proves live `/server` mount source equals resolved active root
   - proves runtime config source equals canonical runtime-config dir and is writable
   - proves durable runtime-home mount exists
   - proves recorded deploy SHA/ref/version match live git and runtime version

2. Shared remote entrypoint
   - script: `scripts/ssh-run-moltis-runtime-attestation.sh`
   - keeps workflow SSH transport constant and versioned

3. Blocking deploy gate
   - `scripts/run-tracked-moltis-deploy.sh` records deploy markers, aligns checkout, then blocks success unless attestation passes

4. Periodic provenance drift detection
   - `gitops-drift-detection.yml` calls the shared attestation wrapper
   - scheduled attestation stays marker-driven and reads deployed SHA/ref/version from the active root instead of comparing production to repo HEAD
   - file-hash drift remains secondary evidence

## Phase 2: Immutable Release Roots

Design target:

- staging checkout remains at `/opt/moltinger`
- immutable live roots move under `/opt/moltinger/releases/<git-sha>`
- `/opt/moltinger-active` becomes a symlink to one immutable release root
- runtime config and runtime home stay outside those release roots

### Intended Properties

- live container bind-mounts `/server` from the resolved active release root, not from a mutable staging checkout
- deploy metadata lives inside the active release root under `data/`
- rollback becomes “flip active symlink to previous attested release root” rather than “repair mutable checkout and recreate”

### Migration Constraints

- do not copy OAuth or provider-key state into release roots
- do not move `~/.moltis` into git-managed paths
- do not mix topology migration with emergency reliability fixes on shared production
- keep `update-active-deploy-root.sh` as the only writer of the active-root symlink

## Recommended Future Rollout

1. Materialize a release root from the tracked staging checkout into `/opt/moltinger/releases/<git-sha>`.
2. Sync only git-managed files into that release root.
3. Write deploy markers inside the release root.
4. Point `/opt/moltinger-active` to that release root.
5. Recreate Moltis from the active root.
6. Run runtime attestation, canonical smoke, and authoritative Telegram UAT.

## Non-Goals For This Slice

- No live production cutover to immutable release roots in this branch.
- No migration of OAuth state, provider keys, or session/runtime-home state.
- No destructive cleanup of historical server roots.

## Success Criteria

- Production can no longer report a successful tracked deploy unless live runtime provenance matches tracked intent.
- Periodic drift detection can detect “healthy but wrong runtime” failures.
- The future immutable release-root topology is documented clearly enough to execute as a separate controlled slice.
