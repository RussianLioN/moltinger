# Moltis Full Configuration Update Plan

**Date**: 2026-02-17
**Status**: Ready for Approval

---

## Executive Summary

Обновление конфигурации Moltis на основе исследований:
1. **Sandbox**: Включить `mode = "all"` (безопасность)
2. **Web Search**: Настроить API ключ для Brave/Tavily
3. **Voice TTS/STT**: Заменить ElevenLabs на бесплатные альтернативы (Silero + Whisper)
4. **LLM Providers**: Добавить несколько провайдеров

**КРИТИЧЕСКАЯ ПРОБЛЕМА**: 2 захардкоженных API ключа ElevenLabs (строки 558, 581)

---

## Tasks

### Task 1: CRITICAL - Security Fixes (Hardcoded API Keys)

**File**: `config/moltis.toml`
**Lines**: 558, 581

**Changes**:
```diff
# Line 558
- api_key = "REDACTED"  # Was hardcoded key
+ api_key = "${ELEVENLABS_API_KEY}"

# Line 581
- api_key = "REDACTED"  # Was hardcoded key
+ api_key = "${ELEVENLABS_API_KEY}"
```

---

### Task 2: HIGH - Enable Sandbox

**File**: `config/moltis.toml`
**Line**: 219

**Changes**:
```diff
- mode = "off"
+ mode = "all"
```

**Add resource limits** (after line 235):
```toml
[tools.exec.sandbox.resource_limits]
memory_limit = "512M"
cpu_quota = 0.5
pids_max = 100
```

---

### Task 3: MEDIUM - Web Search Configuration

**File**: `config/moltis.toml`
**Line**: 338

**Changes**:
```diff
- # api_key = "..."
+ api_key = "${BRAVE_API_KEY}"
```

**Alternative**: Change provider to Tavily:
```diff
- provider = "brave"
+ provider = "tavily"
+ api_key = "${TAVILY_API_KEY}"
```

---

### Task 4: MEDIUM - Voice TTS/STT Update

**File**: `config/moltis.toml`
**Lines**: 490-509

**Change providers**:
```diff
# TTS
- provider = "elevenlabs"
+ provider = "silero"  # FREE, excellent Russian

# STT
- provider = "elevenlabs-stt"
+ provider = "whisper"  # FREE, excellent Russian
```

**Add Silero config**:
```toml
[voice.tts.silero]
voice_id = "aidar"  # Russian male voice
language = "ru"

[voice.stt.whisper]
model = "large-v3"
language = "ru"
```

---

### Task 5: LOW - Add LLM Providers

**File**: `config/moltis.toml`
**Lines**: 84-166

**Add providers** (disabled by default):
```toml
[providers.anthropic]
enabled = false
api_key = "${ANTHROPIC_API_KEY}"
model = "claude-sonnet-4-20250514"

[providers.openai]
enabled = false
api_key = "${OPENAI_API_KEY}"
model = "gpt-4o"

[providers.groq]
enabled = false
api_key = "${GROQ_API_KEY}"
model = "llama-3.3-70b-versatile"
```

---

### Task 6: Update .env.example

**File**: `.env.example`

**Add**:
```bash
# Voice Configuration
ELEVENLABS_API_KEY=your-key-here

# Web Search
BRAVE_API_KEY=your-key-here
# TAVILY_API_KEY=your-key-here

# LLM Providers (Optional)
# ANTHROPIC_API_KEY=sk-ant-your-key
# OPENAI_API_KEY=sk-your-key
# GROQ_API_KEY=gsk_your-key
```

---

## Execution Order

```
1. Task 1 (Security) ───┐
                        ├──► 6. Update .env.example
2. Task 2 (Sandbox) ────┤
                        │
3. Task 3 (Web Search) ─┤
                        │
4. Task 4 (Voice) ──────┤
                        │
5. Task 5 (LLM) ────────┘
```

---

## Files to Modify

| File | Lines | Priority |
|------|-------|----------|
| `config/moltis.toml` | 219, 235, 338, 490-509, 558, 581 | P0 |
| `.env.example` | All | P1 |

---

## Verification

```bash
# 1. No hardcoded keys
grep -E "[0-9a-f]{64}" config/moltis.toml  # Should return nothing

# 2. Sandbox enabled
grep 'mode = "all"' config/moltis.toml  # Should find line 219

# 3. Config valid
docker compose config --quiet  # Exit 0

# 4. Container healthy
docker compose restart moltis
docker inspect --format='{{.State.Health.Status}}' moltis  # "healthy"
```

---

## Rollback

```bash
# Backup before changes
cp config/moltis.toml config/moltis.toml.backup

# Restore if needed
cp config/moltis.toml.backup config/moltis.toml
docker compose restart moltis
```

---

## Research Sources

- `docs/reports/moltis-sandbox-analysis.md` - Sandbox recommendation
- `docs/reports/web-search-api-comparison.md` - Web Search options
- `docs/reports/voice-tts-stt-comparison.md` - Voice TTS/STT options
