# Quickstart: Moltis Live Codex Update Telegram Runtime Gap

## Local Contract Checks

Run the targeted regression suites for the repo-owned carrier:

```bash
bash tests/component/test_telegram_remote_uat_contract.sh
bash tests/static/test_config_validation.sh
```

## Local Skill/Docs Review Targets

Review the contract carrier that must stay aligned:

```text
skills/codex-update/SKILL.md
config/moltis.toml
scripts/telegram-e2e-on-demand.sh
docs/moltis-codex-update-skill.md
docs/telegram-e2e-on-demand.md
```

## Authoritative Live Re-Check

When repo-owned carrier changes are ready, re-check the live Telegram surface through the canonical workflow instead of treating hermetic tests as live proof:

```bash
gh workflow run telegram-e2e-on-demand.yml \
  -f message='Что с новыми версиями codex?' \
  -f timeout_sec='45' \
  -f operator_intent='rerun_after_fix' \
  -f run_secondary_mtproto=false \
  -f upload_restricted_debug=false \
  -f artifact_name='telegram-codex-update-runtime-gap' \
  -f verbose=false
```

If `Activity log` leakage needs a separate check, use an operator message that previously reproduced the leakage and compare the resulting review-safe artifact with the codex-update run.
