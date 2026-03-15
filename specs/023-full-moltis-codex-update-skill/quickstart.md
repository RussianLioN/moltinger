# Quickstart: Full Moltis-Native Codex Update Skill

## Goal

Validate the new ownership model:

1. Moltis answers Codex update requests directly.
2. Moltis scheduler detects fresh upstream fingerprints.
3. Moltis optionally applies a project profile.
4. Operators can inspect one audit record per manual or scheduler run.

## Proposed Manual Flow

1. Ask Moltis in plain language:

```text
Проверь обновления Codex CLI
```

Expected:

- Russian answer from the Moltis-native skill
- current version status
- concise explanation
- optional recommendation section

2. Run the scheduler path in a hermetic test mode:

```bash
bash scripts/moltis-codex-update-run.sh --mode scheduler --stdout json
```

Expected:

- machine-readable run record
- stable fingerprint
- duplicate-safe delivery decision

3. Validate optional profile:

```bash
bash scripts/moltis-codex-update-profile.sh validate \
  --file tests/fixtures/codex-update-skill/project-profile-basic.json
```

Expected:

- valid profile result
- project applicability available to the skill

4. Validate project-specific fallback semantics:

```bash
bash scripts/moltis-codex-update-run.sh \
  --mode manual \
  --release-file tests/fixtures/codex-update-skill/releases-0.114.0.html \
  --profile-file tests/fixtures/codex-update-skill/project-profile-fallback.json \
  --stdout json
```

Expected:

- `profile.status = loaded`
- `decision.project_specific = true`
- recommendation comes from profile fallback even without direct keyword match

5. Validate the full hermetic path:

```bash
make codex-update-e2e
```

Expected:

- manual path loads the project profile
- first scheduler run sends one alert
- second scheduler run suppresses the duplicate
- both paths leave audit record files

## Minimum Verification

```bash
bash tests/component/test_moltis_codex_update_run.sh
bash tests/component/test_moltis_codex_update_state.sh
bash tests/component/test_moltis_codex_update_profile.sh
bash tests/component/test_moltis_codex_update_e2e.sh
```
