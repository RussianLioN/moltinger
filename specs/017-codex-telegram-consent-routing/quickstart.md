# Quickstart: Codex Telegram Consent Routing

## Status

Этот Speckit-пакет сохраняется как исторический инженерный контекст для feature `017`.
Он зафиксировал, почему reply routing нельзя оставлять внутри repo-side watcher.

Текущий production/runtime contract уже другой:

- repo-side watcher больше не владеет interactive consent UX;
- repo-side helper `codex-consent-e2e` теперь доказывает только честный one-way baseline;
- живой сценарий `alert -> accept -> recommendations` перенесён в Moltis-native flow из `specs/021-moltis-native-codex-update-advisory/`.

## What To Validate Now

### 1. Prove the current repo-side baseline

```bash
make codex-consent-e2e
```

Expected result:

- watcher остаётся в `one_way_only`, даже если legacy consent flags принудительно включены;
- alert не содержит `/codex_da` и не задаёт сломанный вопрос про практические рекомендации;
- degraded one-way path остаётся честным и не обещает несуществующий follow-up.

Primary artifact:

```bash
.tmp/current/codex-telegram-consent-e2e-report.json
```

### 2. Validate the current Moltis-native interactive path

```bash
make codex-advisory-e2e
```

Expected result:

- Moltis принимает advisory event;
- Moltis-native router обрабатывает `accept`;
- follow-up рекомендации доставляются сразу;
- degraded path сохраняет причину safe-fallback.

Primary artifact:

```bash
.tmp/current/codex-advisory-e2e-report.json
```

Detailed runtime quickstart:

```bash
specs/021-moltis-native-codex-update-advisory/quickstart.md
```

## Operator Guidance

- Не использовать этот пакет как source of truth для текущего production UX.
- Использовать его как объяснение architectural boundary: почему интерактивный reply path должен принадлежать Moltis ingress.
- Для текущего runtime acceptance ориентироваться на `021` и на `docs/codex-cli-upstream-watcher.md`.
