---
title: "Deploy stall watchdog self-failed on oversized GitHub Actions payloads"
date: 2026-03-28
severity: P2
category: cicd
tags: [cicd, watchdog, github-actions, jq, bash, timeout, notifications, moltis]
root_cause: "The watchdog fetched large workflow-run payloads from GitHub and passed them through jq via --argjson shell arguments twice, so the scheduled job failed with 'Argument list too long' before it could classify stalled runs"
---

# RCA: Deploy stall watchdog self-failed on oversized GitHub Actions payloads

**Дата:** 2026-03-28  
**Статус:** Resolved  
**Влияние:** scheduled timeout monitoring for `Deploy Moltis` on `main` produced a failing watchdog run even though no stalled deploy existed. Alerting signal was degraded and operators could no longer trust watchdog failures without log inspection.

## Ошибка

Scheduled workflow `Deploy Moltis Stall Watchdog` failed in `main` with:

- `deploy-stall-watchdog.sh: line 72: /usr/bin/jq: Argument list too long`
- `jq: invalid JSON text passed to --argjson`

The failure happened inside the watchdog itself, not in a deploy run.

## Что было доказано

1. The failing run `23673793088` crashed before classification/notification and exited from `Detect stalled deploy runs`.
2. Failed logs showed the precise shell path:
   - GitHub API response was captured into shell variables;
   - `jq -cn --argjson current "$payload" --argjson page_payload "$page_payload"` overflowed argv;
   - later `jq -cn --argjson payload "$RUNS_JSON"` repeated the same anti-pattern.
3. The failure was reproducible locally by generating a large mocked GitHub API payload in `tests/unit/test_deploy_stall_watchdog.sh`.
4. After replacing both `--argjson <large-json-string>` paths with file-backed `--slurpfile`, the same oversized fixture and live API invocation both succeeded.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему watchdog failed when no deploy was stalled? | The watchdog helper itself crashed before producing a result | scheduled run `23673793088` |
| 2 | Почему helper crashed? | It passed a large GitHub Actions JSON payload to `jq` through shell argv via `--argjson` | failed log lines + script review |
| 3 | Почему argv overflow occurred? | Actions workflow-run payload for `per_page=100` is large enough to exceed OS argument limits when serialized into a single command invocation | reproduced with oversized fixture |
| 4 | Почему bug survived the first implementation? | Tests covered stall semantics, but not large GitHub API payload transport mechanics | pre-fix `tests/unit/test_deploy_stall_watchdog.sh` |
| 5 | Почему monitoring path degraded in `main`? | The watchdog was shipped without a regression test for oversized API responses and without a CI proof of the scheduled execution path | missing oversized-payload guard before this fix |

## Корневая причина

Корень проблемы был в неверном data-passing contract внутри watchdog helper: large JSON from GitHub Actions was transported through shell arguments instead of files/stdin-safe jq inputs.

### Primary root cause

`scripts/deploy-stall-watchdog.sh` used `jq --argjson` with full workflow-run payload strings in two places.

### Contributing root causes

- no unit test for oversized GitHub API pages;
- happy-path semantics tests did not exercise shell/argv limits;
- the scheduled workflow depended on the helper without a branch-level preflight that mimicked large payload conditions.

## Принятые меры

1. Reworked payload aggregation in `scripts/deploy-stall-watchdog.sh` to use temp files plus `jq --slurpfile` instead of shell-argument JSON injection.
2. Reworked the final result builder to read the aggregated payload from file-backed jq input as well.
3. Added an oversized GitHub API payload unit test that mocks `gh api` with a multi-megabyte workflow-runs fixture.
4. Re-ran live watchdog helper against the real GitHub API after the fix.

## Проверка после исправления

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash -n scripts/deploy-stall-watchdog.sh` | pass | local |
| `bash tests/unit/test_deploy_stall_watchdog.sh` | pass | 4/4 |
| `bash tests/unit/test_deploy_workflow_guards.sh` | pass | 28/28 |
| `bash tests/static/test_config_validation.sh` | pass | 116/116 |
| `bash ./scripts/deploy-stall-watchdog.sh --repo RussianLioN/moltinger --workflow-file deploy.yml --workflow-name "Deploy Moltis" --threshold-minutes 45 --max-runs 100 --json` | pass | local live GitHub API proof |

## Уроки

1. Large GitHub API payloads must not be piped into `jq` through `--argjson` shell arguments.
2. Watchdog/alerting code needs payload-size regression tests, not only classification logic tests.
3. A monitoring workflow that fails before classification is itself a production signal regression and should get the same RCA discipline as deploy-path failures.
