# Telegram Web User Monitor Bug Hunting Report

Date: 2026-03-07  
Workflow: `health-bugs` (adapted: detection via E2E + infra/runtime checks)

## Detection Baseline

### Local checks

```bash
node --check scripts/telegram-web-user-login.mjs
node --check scripts/telegram-web-user-probe.mjs
```

Result: pass.

### Runtime/server checks

```bash
ssh root@ainetic.tech "systemctl is-active cron || systemctl is-active crond || true"
ssh root@ainetic.tech "cd /opt/moltinger && git status --short --branch"
ssh root@ainetic.tech "docker logs --tail 400 moltis | grep -E 'channel reply delivery starting|stream-only targets|manual polling loop'"
```

Observed signals:
- `cron` inactive.
- server worktree dirty (`git status --short` contains modified/untracked files).
- Telegram reply delivery logs repeatedly show `target_count=0` and `stream-only targets`.

## Findings

### P1 — Server-side probe instability (composer stage)
- Symptom: `Cannot find message composer in Telegram Web UI`.
- Impact: periodic monitor false negatives.
- Status: fixed in probe by explicit stage model + retries + chat-open verification.

### P1 — Scheduler inactive
- Symptom: `cron` inactive, periodic checks not running.
- Impact: no continuous monitoring.
- Status: fixed by introducing systemd timer as primary scheduler.

### P2 — GitOps drift on server
- Symptom: dirty `/opt/moltinger` state and manual changes.
- Impact: non-deterministic behavior between repo and runtime.
- Status: fixed by deploy-time hard block on drift (`git status --porcelain`) and compliance gate.

### P2 — Probe payload not deterministic for health checks
- Symptom: `/status` is not guaranteed for every policy/profile.
- Impact: false negatives despite functional bot path.
- Status: fixed via `TELEGRAM_WEB_PROBE_PROFILE` (`strict_status` / `echo_ping`).

## Fixed Components

- `scripts/telegram-web-user-probe.mjs`
- `scripts/telegram-web-user-monitor.sh`
- `scripts/setup-telegram-web-user-monitor.sh`
- `scripts/cron.d/moltis-telegram-web-user-monitor` (fallback mode)
- `systemd/moltis-telegram-web-user-monitor.service`
- `systemd/moltis-telegram-web-user-monitor.timer`
- `.github/workflows/deploy.yml`

## Verification Targets

1. `probe` returns stage-aware JSON and no composer-stage flake in 3 runs.
2. `systemctl is-active moltis-telegram-web-user-monitor.timer` returns `active`.
3. Deploy pipeline fails if server drift is present.
4. `echo_ping` profile yields deterministic health responses.

## Verification Results (2026-03-07)

- Local `probe` (`test2`): `status=pass`, `stage=wait_reply`, `chat_open_verified=true`.
- Local `monitor.sh` with `TELEGRAM_WEB_PROBE_PROFILE=echo_ping`: `status=pass`.
- Server timer status: `systemctl is-active moltis-telegram-web-user-monitor.timer` → `active`.
- Server headless sequence: 3 consecutive runs with `echo_ping` profile passed.
- Server monitor log freshness confirmed after `systemctl start moltis-telegram-web-user-monitor.service`.
