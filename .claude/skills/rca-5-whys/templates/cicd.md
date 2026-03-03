# CI/CD RCA Template

**Тип ошибки:** CI/CD (workflow, pipeline, github actions)

## Pipeline Analysis (Top-Down)

```
┌─────────────────────────────────────────┐
│  WORKFLOW (trigger, conditions)         │ ← Что запустило pipeline
├─────────────────────────────────────────┤
│  JOB (runner, environment)              │ ← Где выполняется
├─────────────────────────────────────────┤
│  STEP (individual actions)              │ ← Что упало
├─────────────────────────────────────────┤
│  ACTION (reusable components)           │ ← Внутренняя логика
└─────────────────────────────────────────┘
```

## 5 Whys for CI/CD

### Workflow Level
1. **Почему workflow запустился/не запустился?**
   - [ ] Wrong trigger (push, PR, schedule)
   - [ ] Missing condition (branch filter)
   - [ ] Concurrency conflict
   - [ ] Workflow dispatch missing

### Job Level
2. **Почему job failed?**
   - [ ] Runner unavailable
   - [ ] Matrix configuration error
   - [ ] Dependency on failed job
   - [ ] Timeout exceeded

### Step Level
3. **Почему step упал?**
   - [ ] Command exit code != 0
   - [ ] Missing environment variable
   - [ ] File not found
   - [ ] Permission denied

### Action Level
4. **Почему action не сработал?**
   - [ ] Invalid inputs
   - [ ] Version incompatibility
   - [ ] API rate limit
   - [ ] External service down

### Root Level
5. **Почему конфигурация проблемна?**
   - [ ] YAML syntax error
   - [ ] Missing secret
   - [ ] Wrong path/branch reference
   - [ ] Outdated action version

## CI/CD-Specific Checks

```bash
# GitHub Actions
gh run view <run-id>
gh run view <run-id> --log-failed
gh api repos/{owner}/{repo}/actions/runs/{run-id}/jobs

# Environment variables
echo "GITHUB_WORKFLOW: ${GITHUB_WORKFLOW:-N/A}"
echo "GITHUB_JOB: ${GITHUB_JOB:-N/A}"
echo "GITHUB_STEP: ${GITHUB_STEP_SUMMARY:-N/A}"
echo "RUNNER_OS: ${RUNNER_OS:-N/A}"

# Secrets check (without revealing values)
gh secret list --repo owner/repo

# Workflow validation
gh workflow view <workflow-name>
```

## Common Root Causes

| Symptom | Likely Root Cause |
|---------|-------------------|
| Job skipped | if condition false, dependency failed |
| Permission denied | Missing GITHUB_TOKEN scope |
| Secret not found | Typo, not set, environment mismatch |
| Timeout | Slow tests, network issues, resource limits |
| Action not found | Version removed, repo renamed |

## CI/CD RCA Example

```
❌ ОШИБКА: Deploy workflow failed on "Deploy to production" step

📝 Workflow: Почему запустился?
   → Push to main branch (expected trigger)

📝 Job: Почему deploy job failed?
   → Step "SSH to server" exited with code 1

📝 Step: Почему SSH упал?
   → Error: Permission denied (publickey)

📝 Action: Почему аутентификация не прошла?
   → SSH_PRIVATE_KEY secret is empty or invalid

📝 Root: Почему secret пустой?
   → Secret was not migrated to new environment secrets

🎯 КОРНЕВАЯ ПРИЧИНА: Secrets not properly configured for production environment
```

## CI/CD Error Categories

| Category | Examples |
|----------|----------|
| **Configuration** | YAML syntax, wrong branch, missing if |
| **Secrets** | Missing, expired, wrong format |
| **Dependencies** | npm install fail, cache miss |
| **Infrastructure** | Runner offline, resource limits |
| **External** | API down, rate limits, network |

---
*Шаблон для CI/CD-specific RCA анализа*
