---
title: "Moltis runtime cleanup dry-run failed because the script assumed Perl JSON::PP inside a minimal container"
date: 2026-03-22
severity: P3
category: shell
tags: [moltis, shell, runtime, container, rca]
root_cause: "The cleanup script relied on a hidden Perl module dependency that was not part of the actual Moltis container contract."
---

# RCA: Moltis runtime cleanup dry-run failed because the script assumed Perl JSON::PP inside a minimal container

## Summary

While closing `T036`, the new `scripts/moltis-runtime-context-cleanup.sh` passed locally but failed on the live Moltis container during the first dry-run. The script assumed that `perl -MJSON::PP` would work because `perl` existed in the image. In reality, the container had only a minimal userspace with `awk` and `sed`, so the dry-run aborted before cleanup.

## Error

Live command:

```bash
docker exec moltis bash /server/scripts/moltis-runtime-context-cleanup.sh --runtime-home /home/moltis/.moltis
```

failed with:

```text
Can't locate JSON/PP.pm in @INC ...
BEGIN failed--compilation aborted.
```

## 5 Whys

1. Why did the live dry-run fail?
   Because the script called `perl -MJSON::PP`, and that module was unavailable inside the running Moltis container.
2. Why did the script rely on `JSON::PP`?
   Because the JSON output helper was implemented with Perl instead of plain shell primitives.
3. Why was that implementation chosen?
   Because local validation checked repo-side execution, not the actual minimal userspace of the live Moltis image.
4. Why did local validation miss it?
   Because we verified `perl` availability conceptually, but not the presence of the specific Perl module set inside the container.
5. Why could that happen again?
   Because the script contract was not reduced to the real lowest-common-denominator runtime tools, and the manifest still advertised the wrong dependency.

## Root Cause

The script had a hidden runtime dependency on `JSON::PP` that was not part of the actual Moltis container contract. This was an implementation-assumption error, not a Moltis product failure.

## Evidence

- Live container capability check showed:
  - present: `/usr/bin/awk`, `/usr/bin/sed`
  - absent: `jq`, `python3`, `node`
- First live dry-run failed with:
  - `Can't locate JSON/PP.pm in @INC`
- After rewriting the JSON emitter to `bash + awk`, the same live dry-run succeeded and reported exactly three stale candidates.
- Live apply then removed only:
  - `/home/moltis/.moltis/oauth-config/moltis.toml.runtime-test.bak`
  - `/home/moltis/.moltis/oauth-runtime-test-config-v1`
  - `/home/moltis/.moltis/oauth-runtime-test-data-v1`
- Post-check confirmed:
  - `oauth_tokens.json` still present
  - `sessions/main.jsonl` still present
  - smoke reply still returned `OK` on `openai-codex::gpt-5.4`

## Fix

- Replaced Perl-based JSON rendering in `scripts/moltis-runtime-context-cleanup.sh` with a shell-safe `awk` emitter.
- Updated `scripts/manifest.json` so the script now declares `awk` instead of `perl`.
- Re-ran local checks:
  - `bash -n scripts/moltis-runtime-context-cleanup.sh`
  - `bash tests/component/test_moltis_runtime_context_cleanup.sh`
  - manifest JSON parse
- Re-ran live dry-run, live apply, and post-cleanup smoke.

## Verification

- Local:
  - `bash tests/component/test_moltis_runtime_context_cleanup.sh` -> `2/2 PASS`
- Live dry-run:
  - `candidate_count: 3`
  - `removed_count: 0`
- Live apply:
  - `removed_count: 3`
- Live post-check:
  - no remaining `oauth-runtime-test-*`
  - `RUNTIME_TEST_BAK_REMOVED`
  - `TOKENS_OK`
  - `MAIN_SESSION_OK`
- Live smoke:
  - final response `OK`
  - model `openai-codex::gpt-5.4`

## Уроки

1. Для скриптов, которые запускаются внутри Moltis-контейнера, надо проектировать контракт под минимальный runtime, а не под локальную машину разработчика.
2. Наличие бинарника не означает наличие его модулей или стандартной библиотеки в ожидаемом составе.
3. Для operational cleanup-скриптов правильнее сначала опираться на `bash`/`awk`/`sed`, а уже потом добавлять более тяжёлые зависимости.
