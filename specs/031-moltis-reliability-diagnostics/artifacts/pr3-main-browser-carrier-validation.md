# PR3 Main Browser Carrier Validation

## Carrier Scope

- `config/moltis.toml`
- `docker-compose.prod.yml`
- `scripts/deploy.sh`
- `docker/moltis-browser-sandbox/Dockerfile`
- `docker/moltis-browser-sandbox/start-browserless-no-preboot.sh`
- `docker/moltis-browser-sandbox/cdp-proxy.mjs`
- `scripts/telegram-web-user-probe.mjs`
- `tests/component/test_telegram_web_probe_correlation.sh`
- `tests/static/test_config_validation.sh`
- `tests/unit/test_deploy_workflow_guards.sh`

## Repository Validation On `031`

Executed on the current branch before carrier publication:

- `node --check scripts/telegram-web-user-probe.mjs`
- `bash tests/component/test_telegram_web_probe_correlation.sh`
- `bash tests/static/test_config_validation.sh`
- `bash tests/unit/test_deploy_workflow_guards.sh`
- `git diff --check`

Observed results:

- `tests/component/test_telegram_web_probe_correlation.sh` -> `14/14 PASS`
- `tests/static/test_config_validation.sh` -> `113/113 PASS`
- `tests/unit/test_deploy_workflow_guards.sh` -> `34/34 PASS`
- `git diff --check` -> clean

## Carrier Apply Check Against `origin/main`

Carrier patch:

- [pr3-main-browser-carrier.patch](./pr3-main-browser-carrier.patch)

Dry-run proof:

```bash
tmp_before=$(mktemp -d /tmp/pr3-main-before-XXXXXX)
git archive origin/main | tar -x -C "$tmp_before"
git -C "$tmp_before" init -q
git -C "$tmp_before" apply --check "$PWD/specs/031-moltis-reliability-diagnostics/artifacts/pr3-main-browser-carrier.patch"
```

Observed result:

- `before=/tmp/pr3-main-before-ftrrXU`
- `status=ok`

## Live Evidence That Motivates This Carrier

- Live production still runs the stock browser baseline from `main`:
  - `sandbox_image = "browserless/chrome"`
  - `container_host = "host.docker.internal"`
  - no `profile_dir`
  - no `persist_profile`
- Manual `docker pull browserless/chrome` from inside `moltis` succeeds now, so the current incident is not best explained by an active image-pull permission failure.
- An isolated stock `browserless/chrome` container on the same host becomes healthy, but `/json/version` exposes a websocket root URL instead of the concrete `/devtools/browser/*` path expected by the tracked local proxy shim.
- Authoritative Telegram validation from this branch now fails closed instead of passing on contaminated/pre-final replies.

## Verdict

The carrier is ready for a `main`-based runtime landing path:

- it applies cleanly to fresh `origin/main`
- it stays runtime/UAT-scoped
- it matches the audited live browser root cause better than the current stock `main` baseline

Remaining proof still required after merge:

1. canonical deploy from `main`
2. live runtime config/mount verification
3. real `browser` canary on the `t.me/...` class of path
4. authoritative Telegram confirmation with no timeout and no leaked activity
