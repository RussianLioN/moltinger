# Telegram Learner: Official And Community Guidance

Last reviewed: 2026-04-02

## Зачем этот документ

Это companion-артефакт к:

- [docs/moltis-skill-agent-authoring.md](../moltis-skill-agent-authoring.md)
- [docs/knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md](../knowledge/MOLTIS-SELF-LEARNING-INSTRUCTION.md)

Он фиксирует, какие именно upstream и community сигналы нужно учитывать при создании learner-skills для Moltis/OpenClaw, чтобы не повторять класс проблем с `Activity log`, hallucinated tool-work и Telegram-safe leakage.

## Канонический порядок источников

Для learner-skills используем жёсткий `official-first` порядок:

1. Official docs
2. Official releases / changelog
3. Official issues / discussions / repo evidence
4. Community or Telegram signals only as дополнительный входящий сигнал

Правило: Telegram-пост или community-комментарий не становятся инструкцией по умолчанию, пока важная часть не подтверждена официальным источником.

## Что подтверждает upstream

### 1. Telegram delivery paths реально ломаются на гонках между reply и tool paths

Официальные issue-сигналы из `openclaw/openclaw`:

- `#10848` — Telegram message-tool sends могут приходить вне очереди относительно обычных reply.
- `#25267` — tool-result media может обгонять предыдущий текст из-за не-дожидающегося flush.

Практический вывод для learner-skills:

- нельзя полагаться на “модель сама аккуратно сходила в tools и всё красиво доставила в Telegram”;
- learner-skill должен иметь deterministic text-first behavior для Telegram-safe surface.

### 2. Skill/tool boundary может деградировать в hallucinated action вместо реального tool call

Официальный issue `#54909` показывает, что Telegram callback может привести не к фактическому действию, а к hallucinated подтверждению.

Практический вывод:

- если skill описывает реальное действие, оно должно иметь canonical runtime path;
- если Telegram-safe surface не поддерживает такой path, skill должен честно деградировать в краткое описание или instruction note.

### 3. Skill integration может давать blank/fragile behavior

Официальный issue `#7158` документирует blank skill integration и workaround через более явный runtime path.

Практический вывод:

- giant prompt-style skill с implicit integration assumptions хрупок;
- тонкий skill-контракт и явный canonical runtime path безопаснее, чем скрытая магия.

## Что это значит для learner-skills

### Нельзя

- смешивать Telegram-safe explainer и operator workflow в одном user-facing описании;
- описывать пользователю file paths, `mkdir`, `cat`, `SKILL.md`, tool names и служебные шаги;
- обещать “сейчас изучу канал и вернусь”, если Telegram-safe surface не должен запускать длинное исследование;
- создавать новый skill по одному неподтверждённому посту.

### Нужно

- держать learner-skill тонким;
- иметь value-first summary для Telegram-safe detail path;
- фиксировать `official-first` sourcing прямо в skill contract;
- иметь degraded mode для случаев без официального подтверждения;
- разделять outputs на digest, instruction note и candidate skill proposal.

## Ranked Improvements

### Top 5 to implement first

1. Переписать `telegram-learner` как thin contract с `telegram_summary`, `value_statement`, `source_priority`, `telegram_safe_note`.
2. Генерировать user-facing skill-detail reply из этих тонких полей, а не из `Workflow`/`Phase` структуры.
3. Убрать из Telegram-safe output любые meta-фразы про описание навыка, file paths, `SKILL.md`, internal steps и operator markup.
4. Добавить похожий learner-skill для regression coverage generic reply path, а не special-case только `telegram-learner`.
5. Явно документировать, что community/Telegram — это сигнал, а не окончательная инструкция без official verification.

### Next 5

6. Ввести state model (`last_seen_message_id`, `content_fingerprint`, `verification_status`, `verified_at`).
7. Добавить duplicate suppression/update policy для knowledge notes.
8. Разделить outputs на short digest / instruction note / candidate skill proposal.
9. Добавить ranked severity rubric для learner findings.
10. Добавить отдельный live UAT контракт для learner-skill detail и typo resolution.

## Применение к `telegram-learner`

`telegram-learner` должен:

- использовать @tsingular как ранний сигнал;
- проверять важное по official docs/releases/issues;
- возвращать в Telegram-safe DM только краткое описание или краткий digest;
- выполнять полный learner-run только в web UI, operator session или scheduler path.
