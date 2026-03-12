# Quickstart: Codex Telegram Consent Routing

## Goal

Validate that a Codex watcher alert can open a consent interaction, the main Moltis Telegram ingress can resolve the user action authoritatively, and the practical recommendations are delivered without the generic bot path consuming the answer.

## 1. Prepare a Consent-Capable Alert

Run the watcher in fixture-backed mode so it produces a fresh alert and a prepared recommendation payload.

```bash
mkdir -p .tmp/current

./scripts/codex-cli-upstream-watcher.sh \
  --mode scheduler \
  --release-file tests/fixtures/codex-upstream-watcher/releases-0.114.0.html \
  --include-issue-signals \
  --issue-signals-file tests/fixtures/codex-upstream-watcher/issue-signals.json \
  --json-out .tmp/current/codex-upstream-alert.json \
  --summary-out .tmp/current/codex-upstream-alert.md \
  --stdout summary
```

Expected result:

- alert output is fresh
- consent capability is enabled only if the authoritative router is healthy
- the report contains a request id / action token contract

## 2. Validate Authoritative Routing Locally

Run the consent router component tests.

```bash
./tests/component/test_moltis_codex_consent_router.sh
```

Expected result:

- callback action is matched to the correct request
- duplicate actions are suppressed
- expired requests return a contextual failure
- generic free-text `да` is not treated as the primary production contract

## 3. Validate End-to-End Through The Codex Acceptance Helper

Use the Codex-specific helper to prove the main scenario without relying on a live operator click.

```bash
make codex-consent-e2e
```

Or call the helper directly:

```bash
./scripts/codex-telegram-consent-e2e.sh \
  --mode hermetic \
  --output .tmp/current/codex-telegram-consent-e2e-report.json
```

Expected result:

- the watcher opens a consent-capable alert
- the authoritative router accepts the tokenized action
- the second recommendation message is delivered immediately
- the degraded one-way alert does not ask a broken question

If you want an additional live user probe after deployment, keep using:

```bash
./scripts/telegram-e2e-on-demand.sh \
  --mode real_user \
  --message '/status' \
  --timeout-sec 45 \
  --output /tmp/telegram-e2e-real-user.json \
  --verbose
```

That live probe is still useful for transport verification, but the hermetic Codex helper is now the authoritative acceptance contract for `alert -> consent -> recommendations`.

## 4. Validate Degraded Fallback

Temporarily disable the authoritative consent router and rerun the watcher alert.

Expected result:

- the alert remains a one-way notification
- the Telegram message does not promise a broken `да/нет` follow-up

## 5. Audit One Interaction

Inspect the authoritative consent record.

Expected result:

- request id
- chat id
- decision
- timestamps
- delivery status
- duplicate/expiry notes if applicable

## 6. Capture Operator Evidence

After the acceptance run, inspect:

- `.tmp/current/codex-telegram-consent-e2e-report.json`
- `.tmp/current/codex-upstream-watcher-report.json` when running the watcher directly
- the consent record under `.tmp/current/codex-telegram-consent-store/` or the helper temp artifacts

This gives one compact artifact showing:

- alert text
- request id and action token
- immediate recommendation follow-up text
- degraded one-way alert evidence
