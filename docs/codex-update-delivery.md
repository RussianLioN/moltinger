# Codex Update Delivery UX

## Статус

На `2026-03-12` пользовательский Codex bridge для `codex-update` намеренно отключён.

Что именно отключено:

- source asset `.claude/commands/codex-update.md`
- source asset `.claude/skills/codex-update-delivery/SKILL.md`

Почему это сделано:

- старый bridge обещал интерактивный Telegram advisory flow, который на практике попадал в generic Moltis chat;
- этот UX признан архитектурно неверным;
- дальнейший пользовательский Telegram flow должен жить в Moltis как у единственного владельца Telegram ingress.

Что это значит простыми словами:

- в Codex больше не должно быть отдельного skill/command entrypoint для этого старого delivery path;
- текущий production-safe режим для Telegram: только `one-way alert`;
- новый интерактивный advisory flow теперь реализуется как `Moltis-native` решение в feature `021`, но production-safe default пока остаётся `one-way alert` до live rollout.
- producer contract и Moltis-facing runtime surface зафиксированы в [docs/codex-moltis-native-advisory.md](/Users/rl/coding/moltinger-molt-2-codex-update-monitor-new/docs/codex-moltis-native-advisory.md).

## Что остаётся рабочим

Исторический feature `009-codex-update-delivery-ux` не удалён как runtime полностью.  
Остаются полезны только операторские entrypoint-ы:

```bash
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout summary
bash scripts/codex-cli-update-delivery.sh --surface on-demand --stdout json
```

Этот слой по-прежнему:

- использует `scripts/codex-cli-update-advisor.sh` как источник рекомендаций;
- умеет отдавать summary/JSON;
- может использоваться как низкоуровневый operator/runtime helper.

Но он больше не считается активным пользовательским skill UX внутри Codex.

## Что больше не считается допустимым UX

Следующие сценарии больше не должны продвигаться как пользовательский путь:

- “просто спросить в Codex и получить старый delivery bridge”
- “ответить в Telegram текстовой командой `/codex_*` и получить follow-up”
- любые обещания, что repo-side delivery layer сам владеет Telegram-диалогом

## Текущий безопасный путь

Сейчас безопасная модель такая:

1. upstream watcher сообщает о новом состоянии Codex CLI;
2. Telegram в production работает как `one-way alert`;
3. hermetic Moltis-native callback/follow-up path уже есть в runtime и тестах;
4. в production рекомендации вернутся в Telegram только после live rollout этого Moltis-native flow.

## Техническая заметка

После удаления source assets нужно синхронизировать bridge в Codex:

```bash
./scripts/sync-claude-skills-to-codex.sh --install
./scripts/sync-claude-skills-to-codex.sh --check
```

После синхронизации нужен перезапуск Codex, чтобы discovery обновился.

## Исторический контекст

`009-codex-update-delivery-ux` остаётся в репозитории как уже выполненный engineering slice, но его старый Codex-facing bridge теперь считается устаревшим и выведенным из эксплуатации.
