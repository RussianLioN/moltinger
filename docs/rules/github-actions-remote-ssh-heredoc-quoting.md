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

## If local interpolation is required

Pass values explicitly as command arguments or environment variables, and still keep remote body quoted:

```bash
ssh user@host "VERSION=$VERSION bash -se" << 'EOF'
  docker pull "image:${VERSION}"
EOF
```

## Verification

1. Critical deploy steps must include explicit state checks and readable error messages.
2. Add/maintain unit guards for workflow invariants (`tests/unit/test_deploy_workflow_guards.sh`).
3. For high-risk remote mutations, prefer a versioned script entrypoint in `scripts/` over inline workflow heredocs; quoted heredoc is the fallback when remote logic cannot yet be extracted.
4. For Moltis deploy control-plane mutations, the current authoritative entrypoints are `scripts/render-moltis-env.sh`, `scripts/gitops-sync-managed-surface.sh`, `scripts/update-active-deploy-root.sh`, `scripts/apply-moltis-host-automation.sh`, and `scripts/run-tracked-moltis-deploy.sh`.
