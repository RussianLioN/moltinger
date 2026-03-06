# Agent Instructions

> **⛔ TOKEN LIMIT: ~700 lines max**
> **Новый контент → отдельный файл → только ссылка здесь**
> *Почему: каждый токен читается при каждом запросе*

Shared core instructions (Claude + Codex): @.ai/instructions/shared-core.md

## ⚠️ MANDATORY: Read MEMORY.md First!

**Before ANY planning or implementation**, read the project memory:
```bash
cat MEMORY.md
```

This file contains:
- **Production configuration** (Docker networks, domains, server resources)
- **Project structure** (key files and folders)
- **Debug commands** for troubleshooting
- **Critical pitfalls** from past incidents

**Why?** Prevents repeating mistakes like wrong Docker network or domain.

---

## ⚠️ MANDATORY: Read SESSION_SUMMARY.md at Session Start!

**Before starting ANY work**, read the session summary:
```bash
cat SESSION_SUMMARY.md
```

This file contains:
- Current project status (secrets, deployment, paths)
- What was already done (commits, configurations)
- What is pending (tasks, blockers)
- Session history

**Update it at session end**: Run `/session-summary`

---

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## ⚠️ Pre-Change Checklists

**Before ANY integration or deploy config change**:
1. Read `MEMORY.md` - check current configuration
2. See `docs/LESSONS-LEARNED.md` → Quick Reference Card

**On ERROR**: Check `MEMORY.md` and `docs/LESSONS-LEARNED.md` first for similar patterns.

**When using Speckit workflows**: apply `docs/rules/speckit-artifact-reconcile.md` before runtime code changes and before push.

---

## ⚠️ Pre-Work Checklist (RCA-003)

**Before starting ANY work session**:

```bash
# 1. Check current branch
git branch --show-current
# Must match feature prefix from specs/XXX-feature-name/

# 2. If wrong branch, switch:
git checkout XXX-correct-branch
```

**Why?** See `docs/rca/2026-03-03-git-branch-confusion.md` - commits went to wrong branch.

---

## ⛔ CRITICAL: Branch Deletion Policy (RCA-003)

**НИКОГДА не удалять ветку без явного запроса пользователя!**

### Before ANY `git branch -D` or `git push --delete`:

```bash
# 1. Check if branch exists on remote
git branch -r | grep <branch>

# 2. Check branch content
git log <branch> --oneline -5

# 3. ASK USER before deletion
```

| Action | Requires User Confirmation |
|--------|---------------------------|
| `git branch -D <local>` | ✅ YES |
| `git push origin --delete <remote>` | ✅ YES |
| `git branch -d <merged>` | ⚠️ Verify merged first |

**Why?** See `docs/rca/2026-03-03-git-branch-confusion.md` - branch was deleted incorrectly.

---

## 📚 Past Lessons Learned

**Before making changes**, check relevant lessons from past incidents:

```bash
# View lessons index
cat docs/LESSONS-LEARNED.md

# Search lessons by topic
./scripts/query-lessons.sh --tag docker
./scripts/query-lessons.sh --severity P1
./scripts/query-lessons.sh --all
```

**Why?** Lessons are extracted from RCA reports and organized by severity/tag. Avoid repeating past mistakes.

---

## ⛔ CRITICAL: RCA при ЛЮБОМ exit code != 0

Формальный протокол авто-RCA и саморефлексии:
`docs/rules/auto-rca-self-reflection.md`

**НЕПРЕРЫВНОЕ ПРАВИЛО:**

```
ANY command with exit code != 0
         │
         ▼
    STOP! НЕ продолжать!
         │
         ▼
    Провести RCA "5 Почему"
         │
         ▼
    Зафиксировать в docs/rca/
         │
         ▼
    Только потом продолжить
```

### Примеры триггеров RCA:

| Ситуация | Действие |
|----------|----------|
| `cat: file: No such file` | ❌ STOP → RCA → Почему файл не найден? |
| `npm ERR! missing script` | ❌ STOP → RCA → Почему скрипт отсутствует? |
| `Error: command failed` | ❌ STOP → RCA → Почему команда упала? |
| `Permission denied` | ❌ STOP → RCA → Почему нет прав? |
| `docker: command not found` | ❌ STOP → RCA → Почему docker недоступен? |

### Быстрый шаблон RCA:

```
🤖 RCA АНАЛИЗ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ОШИБКА: [что случилось]

📝 Q1: Почему? → [ответ]
📝 Q2: Почему [Q1]? → [ответ]
📝 Q3: Почему [Q2]? → [ответ]
📝 Q4: Почему [Q3]? → [ответ]
📝 Q5: Почему [Q4]? → [ответ]

🎯 КОРНЕВАЯ ПРИЧИНА: [итог]
📋 ДЕЙСТВИЕ: [что сделать]
📁 ФАЙЛ: docs/rca/YYYY-MM-DD-[topic].md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Полное описание:** `/rca-5-whys` или `.claude/skills/rca-5-whys/SKILL.md`

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds


## GitOps Principles (MANDATORY)

### ⛔ ABSOLUTE PROHIBITIONS (Manual Bypass)

**NEVER do these things - they violate GitOps and break audit trails:**

1. **NEVER use `scp`/`ssh` FROM YOUR LOCAL MACHINE to modify production**
   ```
   ❌ scp file.yml root@server:/path/           # From laptop
   ❌ ssh root@server "sed -i ..."              # Manual command
   ```
   Problem: No audit trail, bypasses CI/CD protections.

2. **NEVER use `sed` to partially update config files in pipelines**
   ```yaml
   ❌ sed -i "s|image: ...:.*|image: ...:$VERSION|" docker-compose.yml
   ```
   This causes **configuration drift** - server state ≠ git state.

3. **NEVER make manual changes on production servers**
   - No direct docker commands
   - No manual file edits
   - No workaround scripts

### ✅ ACCEPTABLE GitOps Patterns

**1. Push-based GitOps-lite (scp/rsync FROM CI/CD):**
```yaml
# In GitHub Actions - ACCEPTABLE ✅
- uses: actions/checkout@v4      # Get file from git
- run: scp docker-compose.yml $SSH_USER@$SSH_HOST:$DEPLOY_PATH/
```
Why OK:
- CI/CD provides audit trail (commit SHA, who triggered, logs)
- File content comes from verified git checkout
- Rollback via git revert

**2. Pull-based GitOps (git pull on server):**
```yaml
# Trigger server to pull - ACCEPTABLE ✅
- run: ssh server "cd /app && git pull && docker compose up -d"
```
Why OK:
- Git is source of truth
- Audit in git history

### 🎯 PREFERRED (Full GitOps 2.0)

For complex production systems:
- Kubernetes + ArgoCD/Flux
- Continuous reconciliation loop
- Automatic drift detection
- Requires infrastructure investment

### ✅ REQUIRED GitOps Patterns

**1. Sync ENTIRE files from git to server:**
```yaml
# In CI/CD pipeline:
- name: Sync configuration files
  run: |
    scp docker-compose.yml $SSH_USER@$SSH_HOST:$DEPLOY_PATH/docker-compose.yml
```

**2. Validate configuration before deploy:**
```yaml
- name: Validate configuration
  run: |
    ssh $SSH_USER@$SSH_HOST "docker compose config --quiet"
```

**3. Verify configuration matches git in smoke tests:**
```yaml
- name: Verify GitOps compliance
  run: |
    ssh $SSH_USER@$SSH_HOST << 'EOF'
      grep -q "expected_label" docker-compose.yml || exit 1
    EOF
```

### GitOps Decision Tree

```
Need to change server config?
         │
         ▼
    Is change in git?
         │
    ┌────┴────┐
    NO        YES
    │         │
    ▼         ▼
Add to git   Push to trigger
first        CI/CD pipeline
    │
    ▼
Push triggers pipeline
    │
    ▼
Pipeline syncs to server
```

### Why GitOps Matters

| Principle | Benefit |
|-----------|---------|
| Git = Single Source of Truth | No configuration drift |
| All changes through pipeline | Audit trail |
| Automated validation | Catch errors early |
| Rollback via git revert | Reliable recovery |

**See MEMORY.md for incident details and lessons learned.**

### Secrets Management

**All secrets must go through GitHub Secrets, never hardcoded or manually copied.**

See `docs/SECRETS-MANAGEMENT.md` for:
- Allowed vs forbidden patterns
- How to add new secrets
- Audit checklist

**Quick reference:**
```bash
# Add secret
gh secret set SECRET_NAME --repo owner/repo

# List secrets
gh secret list --repo owner/repo
```


## Main Pattern: You Are The Orchestrator

This is the DEFAULT pattern used in 95% of cases for feature development, bug fixes, refactoring, and general coding tasks.

### Core Rules

**1. GATHER FULL CONTEXT FIRST (MANDATORY)**

Before delegating or implementing any task:
- Read existing code in related files
- Search codebase for similar patterns
- Review relevant documentation (specs, design docs, ADRs)
- Check recent commits in related areas
- Understand dependencies and integration points

NEVER delegate or implement blindly.

**2. DELEGATE TO SUBAGENTS**

Before delegation:
- Provide complete context (code snippets, file paths, patterns, docs)
- Specify exact expected output and validation criteria

After delegation (CRITICAL):
- ALWAYS verify results (read modified files, run type-check)
- NEVER skip verification
- If incorrect: re-delegate with corrections and errors
- If TypeScript errors: re-delegate to same agent OR typescript-types-specialist

**3. EXECUTE DIRECTLY (MINIMAL ONLY)**

Direct execution only for:
- Single dependency install
- Single-line fixes (typos, obvious bugs)
- Simple imports
- Minimal config changes

Everything else: delegate.

**4. TRACK PROGRESS**

- Create todos at task start
- Mark in_progress BEFORE starting
- Mark completed AFTER verification only

**5. COMMIT STRATEGY**

Run `/push patch` after EACH completed task:
- Mark task [X] in tasks.md
- Add artifacts: `→ Artifacts: [file1](path), [file2](path)`
- Update TodoWrite to completed
- Then `/push patch`

**6. EXECUTION PATTERN**

```
FOR EACH TASK:
1. Read task description
2. GATHER FULL CONTEXT (code + docs + patterns + history)
3. Delegate to subagent OR execute directly (trivial only)
4. VERIFY results (read files + run type-check) - NEVER skip
5. Accept/reject loop (re-delegate if needed)
6. Update TodoWrite to completed
7. Mark task [X] in tasks.md + add artifacts
8. Run /push patch
9. Move to next task
```

**7. HANDLING CONTRADICTIONS**

If contradictions occur:
- Gather context, analyze project patterns
- If truly ambiguous: ask user with specific options
- Only ask when unable to determine best practice (rare, ~10%)

**8. LIBRARY-FIRST APPROACH (MANDATORY)**

Before writing new code (>20 lines), ALWAYS search for existing libraries:
- WebSearch: "npm {functionality} library 2024" or "python {functionality} package"
- Context7: documentation for candidate libraries
- Check: weekly downloads >1000, commits in last 6 months, TypeScript/types support

**Use library when**:
- Covers >70% of required functionality
- Actively maintained, no critical vulnerabilities
- Reasonable bundle size (check bundlephobia.com)

**Write custom code when**:
- <20 lines of simple logic
- All libraries abandoned or insecure
- Core business logic requiring full control

### Planning Phase (ALWAYS First)

Before implementing tasks:
- Analyze execution model (parallel/sequential)
- Assign executors: MAIN for trivial, existing if 100% match, FUTURE otherwise
- Create FUTURE agents: launch N meta-agent-v3 calls in single message, ask restart
- Resolve research (simple: solve now, complex: deepresearch prompt)
- Atomicity: 1 task = 1 agent call
- Parallel: launch N calls in single message (not sequentially)

See speckit.implement.md for details.

---

## Health Workflows Pattern (5% of cases)

Slash commands: `/health-bugs`, `/health-security`, `/health-cleanup`, `/health-deps`

Follow command-specific instructions. See `docs/Agents Ecosystem/AGENT-ORCHESTRATION.md`.

---

## Project Conventions

**File Organization**:
- Agents: `.claude/agents/{domain}/{orchestrators|workers}/`
- Commands: `.claude/commands/`
- Skills: `.claude/skills/{skill-name}/SKILL.md`
- Temporary: `.tmp/current/` (git ignored)
- Reports: `docs/reports/{domain}/{YYYY-MM}/`

**Code Standards**:
- Type-check must pass before commit
- Build must pass before commit
- No hardcoded credentials

**Agent Selection**:
- Worker: Plan file specifies nextAgent (health workflows only)
- Skill: Reusable utility, no state, <100 lines

**Supabase Operations**:
- Use Supabase MCP when `.mcp.json` includes supabase server

**Sandbox & Security (Zero Trust)**:

This project runs with sandbox mode enabled. The sandbox isolates Bash commands while allowing autonomous operation for safe tasks.

*Key Configuration* (`.claude/settings.json`):
- `sandbox.enabled: true` — All Bash commands run in isolated environment
- `autoAllowBashIfSandboxed: true` — Auto-approve safe commands (ls, grep, cat, etc.)
- `excludedCommands: [docker, git]` — These bypass sandbox for compatibility

*Autonomous Permissions*:
- **ALLOW**: `curl`, `wget`, `npm run lint/test`, `bd` commands, `WebFetch`, `Read`
- **ASK**: `git push`, `docker build` (requires explicit Y/n confirmation)
- **DENY**: Reading `.env*`, `secrets/**`, `credentials.json`, `provider_keys.json`, `rm -rf *`, editing `.github/workflows/**`

*Security Rules*:
1. **NEVER** send local file contents or code snippets via `curl`/`WebFetch` to external APIs unless explicitly requested
2. **ALWAYS** check HTTP status and handle errors (timeouts, 404) when fetching external resources
3. **NEVER** attempt to read blocked files (`.env`, `secrets/`, `provider_keys.json`) — they are denied by policy
4. For file deletion, use safe scripts or request confirmation — `rm -rf` is blocked

*File Operation Safety (Incident 2026-02-28)*:
1. **NEVER delete a file without reading it first** — if sandbox blocks reading, ASK USER
2. **NEVER exceed scope of user request** — answer exactly what was asked
3. **ALWAYS check file usage before deletion**: `grep -r "filename" . --include="*.toml"`
4. **ALWAYS ask when uncertain** — sandbox blocking = uncertainty = ASK USER
5. **File Deletion Protocol**: Read → Check usage → Ask user → Backup → Delete

*SSH/SCP Blocking Rule (GitOps Compliance)*:

⛔ **MANDATORY PRE-EXECUTION CHECK** before ANY ssh/scp command:

```
BEFORE ssh/scp → ASK YOURSELF:
│
├── Is this a READ operation?
│   ├── ssh server "cat file" → ✅ ALLOW (read-only)
│   ├── ssh server "docker logs" → ✅ ALLOW (read-only)
│   └── ssh server "ls -la" → ✅ ALLOW (read-only)
│
├── Is this a WRITE operation?
│   ├── scp file server:/path/ → ❌ BLOCK
│   ├── ssh server "echo > file" → ❌ BLOCK
│   ├── ssh server "rm file" → ❌ BLOCK
│   └── rsync file server:/path/ → ❌ BLOCK
│
└── IF WRITE → STOP and use GitOps instead:
    1. Add file to git repo
    2. git commit + push
    3. Let CI/CD deploy to server
```

**Violation Consequence**: Configuration drift, no audit trail, no rollback capability.

*Sandbox Workarounds*:
- **Heredoc blocked**: Shell heredoc (`<<'EOF'`) creates temp files in blocked system directories
- **Solution**: Use file-based approach for multi-line content:
  ```bash
  # Write to allowed temp directory
  echo "commit message" > /tmp/claude/msg.txt
  # Use -F flag to read from file
  git commit -F /tmp/claude/msg.txt
  ```

*Verification*: Run `/config` to confirm sandbox and permission settings are active.

**MCP Configuration**:
- UNIFIED (`.mcp.json`): All servers with auto-optimization
  - Claude Code automatically applies defer_loading when needed
  - Includes: context7, sequential-thinking, supabase, playwright, shadcn, serena
  - 85% context reduction via MCP Tool Search (automatic, >10K tokens threshold)
  - Uses env vars for Supabase (set `SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN` if needed)
- Legacy configs available in `mcp/` for reference

---

## Task Tracking with Beads (Optional)

> **Attribution**: [Beads](https://github.com/steveyegge/beads) methodology by [Steve Yegge](https://github.com/steveyegge)

If project uses Beads (`/beads-init` was run), follow this workflow:

### Session Workflow

```bash
# START
bd prime                    # Restore context
bd ready                    # Find available work

# WORK
bd update ID --status in_progress  # Take task
# ... implement ...
bd close ID --reason "Done"        # Complete task
/push patch                        # Commit

# END (MANDATORY!)
bd sync
git push
```

### When to Use What

| Scenario | Tool |
|----------|------|
| Large feature (>1 day) | `/speckit.specify` → `/speckit.tobeads` |
| Small feature (<1 day) | `bd create -t feature` |
| Bug | `bd create -t bug` |
| Tech debt | `bd create -t chore` |
| Research/spike | `bd mol wisp exploration` |

### Emergent Work

Found something during current task?
```bash
bd create "Found: ..." -t bug --deps discovered-from:PREFIX-current
```

### Initialize Beads

Run `/beads-init` to set up Beads in this project.

See `.claude/docs/beads-quickstart.md` for full reference.

---

## Deployment Operations

### Quick Reference

```bash
# Deploy stack
make deploy                           # Or: ./scripts/deploy.sh deploy

# Pre-flight validation
./scripts/preflight-check.sh          # Human-readable
./scripts/preflight-check.sh --json   # CI/CD parsable

# Health check
./scripts/health-monitor.sh --once --json

# Version check
make version-check
```

### Backup Management

```bash
# Enable automated backups (systemd timer)
make backup-enable
# Or manually:
sudo systemctl enable --now moltis-backup.timer

# Disable automated backups
make backup-disable
# Or manually:
sudo systemctl disable --now moltis-backup.timer

# Check backup timer status
make backup-status
# Or manually:
systemctl status moltis-backup.timer

# Manual backup trigger
make backup
# Or:
./scripts/backup-moltis-enhanced.sh backup --json

# View backup logs
journalctl -u moltis-backup.service -f
```

### JSON Output Mode

All deployment scripts support `--json` flag for CI/CD integration:

```bash
# Deploy with JSON output
./scripts/deploy.sh deploy --json

# Check result
echo $?  # 0 = success

# Parse with jq
./scripts/preflight-check.sh --json | jq '.missing_secrets'
./scripts/health-monitor.sh --once --json | jq '.services[] | select(.status == "unhealthy")'
```

**Common JSON Fields:**
- `status`: `success`, `failure`, `pass`, `fail`, `healthy`, `unhealthy`
- `timestamp`: ISO 8601 timestamp
- `errors[]`: Array of error objects
- `details`: Action-specific information

See `docs/json-output.md` for complete format documentation.

### Pre-flight Validation

Run before any deployment to verify environment:

```bash
# Standard validation (errors only)
./scripts/preflight-check.sh

# Strict mode (fail on warnings too)
./scripts/preflight-check.sh --strict

# JSON output for CI/CD
./scripts/preflight-check.sh --json
```

**Checks performed:**
- `secrets_exist` - All required secrets present
- `docker_available` - Docker daemon running
- `compose_valid` - docker-compose.yml syntax
- `network_exists` - Required networks exist
- `s3_credentials` - S3 credentials configured (warning)
- `disk_space` - Sufficient disk space (warning)

---

## Active Technologies
- Bash scripts, YAML (Docker Compose), TOML (Moltis config) (001-moltis-docker-deploy)
- Docker bind mounts (001-moltis-docker-deploy)

## Recent Changes
- 001-moltis-docker-deploy: Added Bash scripts, YAML (Docker Compose), TOML (Moltis config)
