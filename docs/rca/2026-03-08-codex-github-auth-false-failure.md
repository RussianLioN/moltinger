---
title: "False GitHub Auth Failure During Codex Push"
date: 2026-03-08
severity: P3
category: process
tags: [codex, github, ssh, sandbox, auth, debugging]
root_cause: "Sandbox-specific auth and network failures were misreported as a host-level GitHub credential problem"
---

# RCA: False GitHub Auth Failure During Codex Push

**Date:** 2026-03-08  
**Status:** Resolved  
**Impact:** False incident signal. I reported that GitHub SSH auth looked broken, even though the host SSH path was healthy and the branch push was recoverable.
**Context:** Landing rollout branch `codex/gpt54-agents-split` from a Codex tool session

## Context

| Field | Value |
|-------|-------|
| Timestamp | 2026-03-08 |
| PWD | /tmp/moltinger-codex-gpt54-agents-split |
| Shell | /bin/zsh |
| Git Branch | codex/gpt54-agents-split |
| Git Commit | 8087ae8 |
| Git Status | clean before RCA docs |
| Error Type | process/auth-debugging |

## Error Classification (Chain-of-Thought)

| Field | Value |
|-------|-------|
| Error Type | process/tool-runtime |
| Confidence | high |
| Context Quality | sufficient |

### Hypotheses

| # | Hypothesis | Confidence |
|---|------------|------------|
| H1 | Host GitHub SSH credentials were actually broken | 15% |
| H2 | Codex sandbox and non-sandbox contexts were being conflated | 80% |
| H3 | Remote URL or git transport config had drifted | 5% |

## Error

While landing `codex/gpt54-agents-split`, `git push` initially failed from a Codex tool run and I concluded that GitHub auth on the machine was broken.

That conclusion was wrong.

## Evidence

- Sandbox diagnostics showed a restricted environment:
  - `env | rg '^(SSH|GIT|GH)_'` returned only `GH_PAGER` and `GIT_PAGER`
  - `ssh-add -l` returned `Could not open a connection to your authentication agent.`
  - `ssh -vvv -o BatchMode=yes -T git@github.com` failed inside sandbox with `Could not resolve hostname github.com: -65563`
- Non-sandbox diagnostics showed host auth was healthy:
  - `gh auth status` reported `Logged in to github.com account RussianLioN (keyring)` with SSH as the git protocol
  - `ssh -vvv -o BatchMode=yes -T git@github.com` authenticated successfully using `/Users/rl/.ssh/id_rsa`
  - OpenSSH loaded the passphrase from the macOS Keychain and completed publickey auth
  - `GIT_TRACE=1 GIT_SSH_COMMAND='ssh -vvv -o BatchMode=yes' git push --dry-run ...` reached `git-receive-pack`
- Final outcome:
  - `git push` succeeded
  - branch updated: `f4e1c68..8087ae8`

## Анализ 5 Почему (with Evidence)

| Уровень | Вопрос | Ответ | Evidence |
|---|---|---|---|
| 1 | Почему push выглядел как сбой GitHub auth? | Потому что первые failing diagnostics пришли из ограниченного Codex execution context и были интерпретированы как host-level проблема | sandbox `ssh-add -l` и sandbox `ssh -T` |
| 2 | Почему sandbox diagnostics были интерпретированы как host-level проблема? | Потому что sandbox failures и non-sandbox checks были смешаны в один вывод до повторной проверки вне sandbox | первоначальное сообщение пользователю и последующий re-run |
| 3 | Почему контексты были смешаны? | Потому что workflow не требовал явного sandbox-vs-host split перед выводом о сломанных credentials | отсутствовало правило в Codex operating model |
| 4 | Почему такого шага не было в workflow? | Потому что operating model покрывал worktrees и governance, но не transport/auth diagnostics для GitHub операций | содержимое `docs/CODEX-OPERATING-MODEL.md` до правки |
| 5 | Почему transport/auth diagnostics не были документированы? | Потому что различия tool runtime считались implicit knowledge, а не фиксированным runbook | отсутствие отдельного правила в `docs/rules/` до инцидента |

## Root Cause

I misdiagnosed a sandbox-specific networking and auth-agent limitation as a real machine-level GitHub credential failure.

The actual problem was not broken SSH access on the host. The actual problem was missing discipline in separating:

- sandbox evidence
- non-sandbox evidence
- final conclusions reported to the user

### Root Cause Validation

| Check | Result | Notes |
|-------|--------|-------|
| □ Actionable? | yes | Добавлен явный debug rule и обновлен operating model |
| □ Systemic? | yes | Ошибка может повториться при любых GitHub auth incidents из Codex |
| □ Preventable? | yes | Достаточно обязательного split sandbox vs host перед выводом |

## Corrective Actions

1. **Immediate correction:** rerun GitHub auth diagnostics outside the sandbox.
2. **Verification:** confirm direct SSH auth and traced git transport before concluding credentials are broken.
3. **Resolution:** retry `git push` in the verified non-sandbox context.

## Preventive Actions

1. Add a durable rule for GitHub auth debugging in Codex sessions.
2. Update the Codex operating model to explicitly require sandbox-vs-host verification before declaring auth failure.
3. Treat sandbox `gh auth` and sandbox `ssh` failures as provisional evidence only.

## Related Updates

- [x] New rule file created: `docs/rules/codex-github-auth-debugging.md`
- [x] Short reference added in `CLAUDE.md`
- [x] Codex operating model updated with the new rule
- [ ] Tests added

## Уроки

- Sandbox failures are not authoritative evidence of broken host SSH or broken GitHub credentials.
- For GitHub auth incidents in Codex, the minimum reliable sequence is:
  1. inspect sandbox evidence
  2. rerun the same checks outside sandbox
  3. only then conclude whether the problem is transport, credentials, or tool context
- A successful `ssh -T git@github.com` and traced `git push --dry-run` outweigh earlier sandbox-only auth failures.
