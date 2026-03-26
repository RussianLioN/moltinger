---
name: post-close-task-classifier
description: Классифицирует новую задачу после формального завершения branch/worktree
  и рекомендует, продолжать ли работу в текущем lane, открыть новый worktree
  на той же ветке, или создать новый branch/worktree от main.
---

# Post-Close Task Classifier

## Когда использовать

Используй этот skill, когда пользователь пишет что-то вроде:

- `эта новая задача ещё в рамках текущей ветки или уже нужен новый worktree?`
- `можно ли продолжать здесь?`
- `задачи ветки завершены, но появились новые ошибки`
- `классифицируй current lane vs new lane`
- `подготовь prompt для нового worktree`

## Канонический источник истины

Полная логика живёт в:

`docs/rules/post-close-task-classification-and-worktree-escalation.md`

Сначала прочитай это правило. Не дублируй его своими словами, если можно сослаться на него точно.

## Что нужно сделать

1. Определи, относится ли новый запрос к тому же root cause и тому же slice.
2. Проверь, не затрагивает ли он shared contracts:
   - `AGENTS.md`
   - `docs/rules/`
   - `skills/`
   - auth, secrets, runtime, deploy, CI, topology, shared config
3. Проверь, не закрыт ли текущий lane логически.
4. Выдай ровно один verdict:
   - `continue-current-lane`
   - `new-worktree-same-branch`
   - `new-branch-new-worktree-from-main`
   - `consilium-required`
5. Если нужен новый lane, подготовь готовый prompt по шаблону из rule artifact.
6. Если критерии конфликтуют, не угадывай. Запускай `/consilium`.

## Формат ответа

Отвечай по-русски и в таком порядке:

1. `Verdict`
2. `Why`
3. `Matched criteria`
4. `Recommended lane`
5. `Prepared prompt`
6. `Need consilium`

## Что делать нельзя

- Не продолжай автоматически в текущем lane только потому, что это дешевле по токенам.
- Не открывай новый branch/worktree на каждый микроскопический follow-up без классификации.
- Не превращай skill в большой policy blob. Подробности должны жить в `docs/rules/`.

## Простое правило

Если нужно коротко:

`same root cause + same slice + same owner + no scope expansion => можно продолжать`

`anything else => новый lane`
