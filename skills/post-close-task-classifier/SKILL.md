---
name: post-close-task-classifier
description: Классифицирует новую задачу после формального завершения branch/worktree
  и рекомендует, продолжать ли работу в текущем lane, вернуться в существующий
  authoritative worktree, или создать новый branch/worktree от main.
---

# Post-Close Task Classifier

## Когда использовать

Используй этот skill, когда пользователь пишет что-то вроде:

- `эта новая задача ещё в рамках текущей ветки или уже нужен новый worktree?`
- `после завершения ветки можно ли продолжать здесь?`
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
3. Если shared-contract surface затронут в уже закрытом или merged slice, новый lane обязателен.
4. Узкий review-fix внутри того же активного unmerged slice не форсирует новый lane автоматически.
5. Проверь, не закрыт ли текущий lane логически.
6. Выдай ровно один verdict:
   - `continue-current-lane`
   - `reuse-existing-worktree`
   - `new-branch-new-worktree-from-main`
   - `consilium-required`
7. Если нужен новый lane или lane-reuse handoff, подготовь его по шаблону из rule artifact.
8. Если критерии конфликтуют, не угадывай. Используй `consilium` skill/workflow.

## Формат ответа

Отвечай по-русски и в таком порядке:

1. `Verdict`
2. `Why`
3. `Matched criteria`
4. `Recommended lane`
5. `Prepared prompt`
6. `Need consilium`

Для `Prepared prompt`:

- `continue-current-lane` => `n/a`
- `reuse-existing-worktree` => short lane-reuse handoff
- `new-branch-new-worktree-from-main` => full new-lane prompt
- `consilium-required` => `defer until consilium verdict`

## Что делать нельзя

- Не продолжай автоматически в текущем lane только потому, что это дешевле по токенам.
- Не открывай новый branch/worktree на каждый микроскопический follow-up без классификации.
- Не превращай skill в большой policy blob. Подробности должны жить в `docs/rules/`.

## Простое правило

Если нужно коротко:

`same root cause + same slice + same owning lane + no scope expansion => можно продолжать`

`shared-contract work in a closed or merged slice => новый lane обязателен`

`если нужно только вернуться в authoritative worktree того же активного slice => reuse-existing-worktree`
