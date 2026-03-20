# Rule: Quote SSH Heredocs in GitHub Actions

## Problem

In GitHub Actions, `ssh ... << EOF` allows local runner shell expansion inside the heredoc body.  
This can execute command substitutions or variable expansion locally instead of on the remote host and break production deploy steps.

## Mandatory Rule

For remote scripts executed via SSH in workflows, use **quoted heredoc**:

```bash
ssh user@host << 'EOF'
  set -euo pipefail
  # remote-only logic
EOF
```

Do **not** use unquoted heredoc (`<< EOF`) for remote execution blocks containing shell variables or command substitutions.

## If dynamic values must reach the remote shell

Keep the remote command itself constant and send dynamic values as shell-quoted data inside the stdin-delivered script:

```bash
emit_remote_script() {
  printf 'VERSION=%q\n' "$VERSION"
  cat <<'EOF'
docker pull "image:${VERSION}"
EOF
}

emit_remote_script | ssh user@host 'bash -seu'
```

Do **not** assume `ssh user@host bash -s -- "$ARG"` is sufficient for untrusted or user-controlled values. `ssh` still serializes the remote invocation into a shell-parsed command string, so the safe boundary is the quoted script body, not ssh argv assembly.

## Verification

1. Critical deploy steps must include explicit state checks and readable error messages.
2. Add/maintain unit guards for workflow invariants (`tests/unit/test_deploy_workflow_guards.sh`).
3. For high-risk remote mutations, prefer a versioned script entrypoint in `scripts/` over inline workflow heredocs; quoted heredoc is the fallback when remote logic cannot yet be extracted.
4. For Moltis deploy control-plane mutations, the current authoritative entrypoints are `scripts/render-moltis-env.sh`, `scripts/gitops-sync-managed-surface.sh`, `scripts/update-active-deploy-root.sh`, `scripts/apply-moltis-host-automation.sh`, and `scripts/run-tracked-moltis-deploy.sh`.
5. When a workflow passes dynamic values such as git refs, SHAs, or run IDs into a remote shell, keep the remote command constant and inject those values through a quoted stdin script with shell-quoted assignments. Do not interpolate them into a single remote command string, and do not rely on `ssh ... bash -s -- "$arg1" ...` as the safety boundary.
