# CRITICAL: GLM-5 LLM Configuration Fix

**Date**: 2026-02-17
**Status**: Ready for Approval
**Priority**: P0 - BLOCKING ALL FUNCTIONALITY
**Model**: glm-5 (Pro subscription via Coding Plan endpoint)

---

## Context

**Проблема**: НИ ОДНА LLM модель не работает в Moltis. Это блокирует:
- ❌ Web UI чат (не отвечает)
- ❌ Telegram бот (не отвечает)

**Корневая причина**: `[providers.glm-coding]` - это НЕ существующий провайдер в Moltis!

**Исследование**:
1. Прочитана официальная документация Z.ai: https://docs.z.ai/api-reference/introduction
2. Прочитана конфигурация Moltis: `config/moltis.toml` (строки 80-220)
3. Проверен список доступных провайдеров Moltis (строки 92-96)

---

## Critical Finding

### ⚠️ Концептуальные ошибки в первоначальном анализе

| Моя ошибка | Правильное понимание |
|------------|---------------------|
| "Endpoint неправильный" | ❌ **НЕВЕРНО!** Coding Plan использует `/api/coding/paas/v4` |
| "Модель glm-4-plus для Coding Plan" | ❌ **НЕВЕРНО!** Pro подписка использует `glm-5` |
| "Надо менять endpoint" | ❌ Endpoint был **ПРАВИЛЬНЫМ** |

### ✅ Что действительно неверно

| Параметр | Текущее | Проблема |
|----------|---------|----------|
| Provider section | `[providers.glm-coding]` | "glm" НЕ в списке провайдеров Moltis! |
| enabled | `true` | Moltis игнорирует несуществующий провайдер |
| model | `glm-4-plus` | Должно быть `glm-5` (Pro подписка) |

### Z.ai Coding Plan (подписка пользователя - Pro):

**Endpoint**: `https://api.z.ai/api/coding/paas/v4` ✅ **БЫЛ ПРАВИЛЬНЫМ!**

```python
from openai import OpenAI

client = OpenAI(
    api_key="your-Z.AI-api-key",
    base_url="https://api.z.ai/api/coding/paas/v4"  # Coding Plan endpoint!
)

completion = client.chat.completions.create(
    model="glm-5",  # ← Pro подписка поддерживает glm-5!
    messages=[...]
)
```

### Moltis поддерживает OpenAI-совместимые провайдеры:

Секция `[providers.openai]` с кастомным `base_url` позволяет использовать любой OpenAI-совместимый API.

---

## Tasks

### Task 1: CRITICAL - Fix GLM Provider Configuration

**File**: `config/moltis.toml`
**Lines**: 106-121

**Current (BROKEN)**:
```toml
# ── OpenAI ────────────────────────────────────────────────────
[providers.openai]
enabled = false                     # Set to true and add API key to enable
api_key = "${OPENAI_API_KEY}"       # Or set OPENAI_API_KEY env var
model = "gpt-4o"                    # Default model
base_url = "https://api.openai.com/v1"
alias = "openai"

# ── GLM (Zhipu AI) - OpenAI-compatible ────────────────────────
# Coding-focused LLM from Zhipu AI
[providers.glm-coding]
enabled = true
api_key = "${GLM_API_KEY}"                    # Set GLM_API_KEY in .env file
model = "glm-4-plus"                          # or glm-4-flash, glm-4-air
base_url = "https://api.z.ai/api/coding/paas/v4"
alias = "glm-coding"
```

**Fixed**:
```toml
# ── OpenAI / GLM-5 via Z.ai Coding Plan ───────────────────────────────────────
# Using Z.ai Coding Plan (Pro subscription) through OpenAI-compatible API
# Docs: https://docs.z.ai/api-reference/introduction
# Coding Plan endpoint: https://api.z.ai/api/coding/paas/v4
[providers.openai]
enabled = true
api_key = "${GLM_API_KEY}"                          # Use GLM_API_KEY from .env
model = "glm-5"                                     # Pro subscription supports glm-5!
base_url = "https://api.z.ai/api/coding/paas/v4"    # Coding Plan endpoint (CORRECT!)
alias = "glm-5-zai"

# ── GLM (Zhipu AI) - DISABLED (invalid provider name) ────────────────────────
# This section is NOT a valid Moltis provider! Use [providers.openai] instead.
[providers.glm-coding]
enabled = false
```

---

### Task 2: Update .env.example

**File**: `.env.example`

**Add comment**:
```bash
# GLM-5 through Z.ai (OpenAI-compatible)
# Get API key at: https://open.bigmodel.cn/
GLM_API_KEY=your-zhipu-api-key-here
```

---

### Task 3: Update docker-compose.yml (if needed)

**File**: `docker-compose.yml`

Ensure `GLM_API_KEY` is passed:
```yaml
environment:
  - GLM_API_KEY=${GLM_API_KEY}
```

---

## Execution Order

```
1. Task 1 (Fix GLM config) ───► 2. Task 2 (Update .env.example)
                                        │
                                        ▼
                               3. Task 3 (Verify docker-compose)
                                        │
                                        ▼
                               4. Deploy & Test
```

---

## Files to Modify

| File | Lines | Priority | Change |
|------|-------|----------|--------|
| `config/moltis.toml` | 106-121 | P0 | Replace GLM config with OpenAI-compatible |
| `.env.example` | All | P1 | Add GLM_API_KEY comment |
| `docker-compose.yml` | 39 | P2 | Verify GLM_API_KEY env var |

---

## Verification

### Local Verification
```bash
# 1. Check config syntax (TOML valid)
cat config/moltis.toml | grep -A5 '\[providers.openai\]'

# 2. Verify glm-coding section is DISABLED
grep -A1 '\[providers.glm-coding\]' config/moltis.toml | grep 'enabled = false'

# 3. Verify OpenAI section has Coding Plan endpoint
grep 'base_url = "https://api.z.ai/api/coding/paas/v4"' config/moltis.toml

# 4. Verify model is glm-5 (Pro subscription)
grep 'model = "glm-5"' config/moltis.toml
```

### Remote Verification (after deploy)
```bash
# SSH to server
ssh root@ainetic.tech

# Check container health
docker logs moltis --tail 50 | grep -i "provider\|llm\|error"

# Test GLM-5 response (inside container)
docker exec moltis curl -s http://localhost:13131/health

# Check UI
curl -I https://moltis.ainetic.tech/health
```

### Functional Test
1. Open https://moltis.ainetic.tech in browser
2. Send test message: "Привет, представься"
3. Verify GLM-5 responds correctly
4. Test Telegram bot

---

## Rollback

```bash
# Backup before changes
cp config/moltis.toml config/moltis.toml.backup-glm-fix

# Restore if needed
cp config/moltis.toml.backup-glm-fix config/moltis.toml
docker compose restart moltis
```

---

## Research Sources

1. **Z.ai Official Documentation**: https://docs.z.ai/api-reference/introduction
   - General endpoint: `https://api.z.ai/api/paas/v4/`
   - **Coding Plan endpoint**: `https://api.z.ai/api/coding/paas/v4` (for user's subscription)
   - **Model**: `glm-5` (ALL examples in docs use glm-5!)
   - Auth: Bearer token

2. **Moltis Configuration**: `config/moltis.toml` lines 80-166
   - Available providers: anthropic, openai, gemini, groq, xai, deepseek, mistral, openrouter, cerebras, minimax, moonshot, venice, ollama, local-llm, openai-codex, github-copilot, kimi-code
   - **GLM is NOT in this list** - must use `[providers.openai]` with custom `base_url`

3. **Previous Session Findings**: `.tmp/current/moltis-runtime-diagnosis.md`
   - Root cause analysis of black screen and Telegram issues

---

## Why This Fix Works

1. **Moltis recognizes `[providers.openai]`** as a valid provider
2. **`base_url` parameter** allows using any OpenAI-compatible API
3. **Z.ai Coding Plan API is OpenAI-compatible** at `https://api.z.ai/api/coding/paas/v4`
4. **Same `api_key`** - just move from `[providers.glm-coding]` to `[providers.openai]`
5. **Correct model** - `glm-5` for Pro subscription (as shown in all Z.ai docs examples)
6. **Same endpoint** - `/api/coding/paas/v4` (Coding Plan specific)

---

## Alternative Approaches (NOT RECOMMENDED)

### Option B: OpenRouter Gateway
Use OpenRouter to access GLM models:
```toml
[providers.openrouter]
enabled = true
api_key = "${OPENROUTER_API_KEY}"
model = "zhipu/glm-4-plus"  # Through OpenRouter
base_url = "https://openrouter.ai/api/v1"
```
**Cons**: Extra latency, another dependency, costs

### Option C: Switch to OpenClaw
Complete rewrite to use OpenClaw instead of Moltis.
**Cons**: Major project rework, lost work
