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

## 3. Validate End-to-End Through Telegram

Use the existing E2E harness with a real user or synthetic path, depending on the environment.

```bash
./scripts/telegram-e2e-on-demand.sh \
  --mode real_user \
  --message "/status" \
  --timeout-sec 45 \
  --output /tmp/telegram-e2e-real-user.json \
  --verbose
```

Then run the Codex-specific acceptance path once implemented:

```bash
./scripts/telegram-e2e-on-demand.sh \
  --mode real_user \
  --message "/codex-followup yes <token>" \
  --timeout-sec 45 \
  --output /tmp/telegram-codex-consent-e2e.json \
  --verbose
```

Expected result:

- the main bot handles the consent action contextually
- the second recommendation message is delivered
- no generic “context is unclear” reply appears for the matched action

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
