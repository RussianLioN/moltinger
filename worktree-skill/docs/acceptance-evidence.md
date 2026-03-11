# Acceptance Evidence

This file records evidence for the state `portable repo ready`.

Current baseline:

- standalone skeleton created
- install scripts added
- adapter docs added
- Speckit bridge docs added
- initial portable core assets copied for generalization
- `install/bootstrap.sh` succeeded for a temporary host target with `--adapter claude-code --with-speckit`
- `install/verify.sh` succeeded for the same temporary host target
- `worktree-skill/tests/unit/test_worktree_ready.sh` passed
- `worktree-skill/tests/unit/test_worktree_phase_a.sh` passed
- `worktree-skill/tests/unit/test_git_topology_registry.sh` passed
- `worktree-skill/tests/integration/test_codex_adapter.sh` passed
- `worktree-skill/tests/integration/test_opencode_adapter.sh` passed
- `worktree-skill/tests/integration/test_speckit_bridge.sh` passed
- remaining gaps are broader contract coverage inside the copied portable core scripts, not the first-release scaffold itself
