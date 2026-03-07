# Quickstart: On-Demand Telegram E2E Harness

## Local CLI

```bash
export MOLTIS_PASSWORD='***'
./scripts/telegram-e2e-on-demand.sh \
  --mode synthetic \
  --message '/status' \
  --timeout-sec 30 \
  --output /tmp/telegram-e2e-result.json \
  --moltis-url http://localhost:13131 \
  --verbose
```

Expected: JSON artifact exists with `status` and `observed_response`.

## GitHub Workflow (from chat/CLI)

```bash
gh workflow run telegram-e2e-on-demand.yml \
  -f mode=synthetic \
  -f message='/status' \
  -f timeout_sec=30 \
  -f moltis_url='https://moltis.ainetic.tech' \
  -f artifact_name='telegram-e2e-result' \
  -f verbose=true
```

Then watch run:

```bash
gh run watch
```

## Deferred Real User Mode (MVP)

```bash
./scripts/telegram-e2e-on-demand.sh --mode real_user --message '/status'
```

Expected in MVP: structured deferred/precondition diagnostic (`deferred_real_user` or `precondition_failed`).
