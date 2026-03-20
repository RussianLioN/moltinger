---
title: "Moltis update proposal failed on perl replacement ambiguity and GitHub PR permission assumption"
date: 2026-03-20
severity: P2
category: cicd
tags: [cicd, github-actions, moltis-update, perl, github-permissions, smtp]
root_cause: "Workflow relied on implicit assumptions (perl backreference syntax, PR create permission, stale Node20 action major) that were false in production-like CI runs"
---

# RCA: Moltis update proposal failed on perl replacement ambiguity and GitHub PR permission assumption

**Дата:** 2026-03-20  
**Статус:** Resolved  
**Влияние:** Регулярный proposal-flow обновления Moltis не доходил до устойчивого уведомления/подтверждения: сначала падал на подготовке compose-изменения, затем на создании PR, затем давал deprecation warning по mail action.

## Ошибка

Последовательность проявлений:

1. Run `23356165986` падал в `Prepare proposal branch`:
   - `No Moltis image reference found ...`
   - `Tracked Moltis version is empty`
2. После первичного фикса run `23356437552` падал в `Create or update upgrade PR`:
   - `GraphQL: GitHub Actions is not permitted to create or approve pull requests (createPullRequest)`
3. После добавления fallback run `23356521230` стал успешным, но показывал warning:
   - `dawidd6/action-send-mail@v3` на Node 20 (deprecation)

Финальный run `23356632024` прошёл успешно с email-этапом и без Node20 warning.

## Анализ 5 Почему

| Уровень | Вопрос | Ответ | Evidence |
|---------|--------|-------|----------|
| 1 | Почему workflow сначала падал до PR/email? | Шаг замены версии портил compose-строки при `0.x.y` candidate | failed run `23356165986`, step `Prepare proposal branch` |
| 2 | Почему замена портила строку? | В perl replacement использовалось `\\1${CANDIDATE_VERSION}\\2`; при `0.10.18` это интерпретируется как `\\10...` | локальная репродукция: `printf 'x1y' \| perl -pe "s/(x)1(y)/\\10.10\\2/"` |
| 3 | Почему после этого pipeline всё равно не дошёл до PR? | Репозиторий запрещает `createPullRequest` для GitHub Actions token | failed run `23356437552`, GraphQL error `not permitted to create or approve pull requests` |
| 4 | Почему это стало hard-fail вместо recoverable path? | Workflow предполагал, что PR можно создать всегда, и не имел fallback на compare/manual PR path | `.github/workflows/moltis-update-proposal.yml` до фикса |
| 5 | Почему появился дополнительный warning после починки? | Email action был на старом major `@v3` (Node20), хотя upstream уже на Node24 | run `23356521230` annotation + upstream `dawidd6/action-send-mail` |

## Корневая причина

Proposal workflow зависел от трёх незафиксированных допущений:

1. perl backreference можно безопасно собирать как `\1${VERSION}\2` для numeric tags;
2. GitHub Actions token всегда имеет право `createPullRequest`;
3. старый major mail action остаётся совместимым с текущим runtime GitHub Actions.

Эти допущения не были закреплены тестами/guard-проверками, поэтому дефект проявился в живом CI-потоке.

## Принятые меры

1. Исправлен perl replacement на однозначный braced-формат:
   - `#\${1}${CANDIDATE_VERSION}\${2}#g`
2. Добавлен fallback при запрете `createPullRequest`:
   - workflow больше не падает;
   - формируется compare URL (`.../compare/main...<branch>?expand=1`) для ручного создания PR по ссылке;
   - сигнал снижен до `notice`.
3. Обновлён mail action до Node24-совместимого major:
   - `dawidd6/action-send-mail@v16`
4. Добавлены статические guards в `tests/static/test_config_validation.sh`:
   - защита от возврата неоднозначного perl replacement;
   - защита fallback path при запрете PR create;
   - защита от возврата mail action на deprecated Node20 major.

## Проверка после исправлений

| Проверка | Результат | Evidence |
|----------|-----------|----------|
| `bash tests/static/test_config_validation.sh` | pass (77/77) | локальный прогон после каждого изменения |
| Workflow smoke `moltis-update-proposal` | success | run `23356593143` |
| Workflow smoke после перевода warning->notice | success | run `23356632024` |
| Email step | success | `Send approval email (optional)` = success в run `23356593143`, `23356632024` |

## Уроки

1. Для perl replacement с numeric payload всегда использовать braced captures (`${1}`), иначе `\10`-ловушка неизбежна.
2. Proposal workflows должны иметь explicit degraded mode при ограниченных GitHub permissions, а не падать.
3. Третьесторонние GitHub actions для прод-контуров нужно регулярно поднимать до runtime-совместимых major и закреплять это статическими проверками.

