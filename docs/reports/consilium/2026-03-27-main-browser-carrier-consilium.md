---
title: "Consilium: browser runtime carrier from 031 to main"
date: 2026-03-27
tags: [consilium, moltis, browser, sandbox, main, carrier]
---

# Consilium: browser runtime carrier from `031` to `main`

## Question

Is the audited browser/runtime fix in `031-moltis-reliability-diagnostics` ready to move into `main` as a narrow carrier, and what exact checklist should govern the canonical landing and deploy?

## Evidence Reviewed

- official Moltis browser/sandbox/cloud docs
- live production runtime facts from `ainetic.tech`
- live `moltis` config and logs
- isolated stock `browserless/chrome` behavior on the same host
- branch diff `origin/main..031-moltis-reliability-diagnostics`
- carrier dry-run proof against clean `origin/main`

## Expert Views

### Moltis/OpenClaw docs view

- Current production matches the official baseline at a coarse level:
  - Docker socket available
  - `container_host = "host.docker.internal"`
  - stock `sandbox_image = "browserless/chrome"`
- Official docs do not fail-close repo-specific browser invariants such as:
  - host-visible `profile_dir`
  - explicit `persist_profile`
  - websocket endpoint shape compatibility for this deployment
- Verdict:
  - current production is **official-compliant but operationally fragile**

### Docker/browserless view

- Current evidence does **not** support treating image-pull permissions as the dominant live root cause:
  - `docker pull browserless/chrome` now succeeds from inside `moltis`
  - stock `browserless/chrome` starts on the same host
- Stronger explanation:
  - live production is still on the stock browserless baseline from `main`
  - stock browserless behavior on this host exposes a websocket root URL that does not match the tracked local proxy contract expected by the `031` shim
- Verdict:
  - dominant live risk is **browser websocket/readiness incompatibility plus production drift back to stock baseline**

### Repo diff / landing view

- The narrow runtime/UAT carrier is available and applies cleanly to fresh `origin/main`
- The carrier does not require dragging RCA/rules/lessons/spec closure into the production path
- The selected surface is sufficient to move production from stock browserless baseline to the tracked shim contract plus fail-closed Telegram/browser UAT semantics

## Consolidated Verdict

`merge with proof`

Meaning:

- the browser carrier is ready for a `main` landing path
- it should be treated as a runtime/UAT carrier, not as a full branch merge
- production rollout must still go only through canonical deploy from `main`

## Exact Canonical Landing Checklist

1. Materialize the carrier on top of clean `origin/main`.
2. Keep scope limited to:
   - `config/moltis.toml`
   - `docker-compose.prod.yml`
   - `scripts/deploy.sh`
   - `docker/moltis-browser-sandbox/*`
   - `scripts/telegram-web-user-probe.mjs`
   - `tests/component/test_telegram_web_probe_correlation.sh`
   - `tests/static/test_config_validation.sh`
   - `tests/unit/test_deploy_workflow_guards.sh`
3. Re-run blocking repo checks on the carrier branch:
   - `node --check scripts/telegram-web-user-probe.mjs`
   - `bash tests/component/test_telegram_web_probe_correlation.sh`
   - `bash tests/static/test_config_validation.sh`
   - `bash tests/unit/test_deploy_workflow_guards.sh`
4. Merge into `main`.
5. Run the canonical production deploy from `main`.
6. After deploy, prove live runtime contract:
   - live `moltis.toml` now shows tracked browser values
   - live container mounts the shared browser profile path
   - tracked browser shim image is available on the host
7. Re-run a real browser canary on the same `t.me/...` class of path.
8. Re-run authoritative Telegram validation and require:
   - no timeout
   - no `Activity log`
   - no false pass on progress-preface-only replies

## Non-Recommendations

Do not:

- treat the existing `031` branch alone as incident closure
- deploy the browser fix from a feature branch
- merge the full docs/process layer before live browser verification on `main`
- treat stock browserless HTTP health as proof that Moltis browser sessions are healthy

## Final Recommendation

Proceed to `main` through the narrow browser carrier, then deploy and prove the real `t.me/...` browser path. Only after that should the remaining docs/process closure be reconciled against verified `main` state.
