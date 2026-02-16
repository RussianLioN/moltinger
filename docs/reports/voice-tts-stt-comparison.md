# Voice TTS/STT Research Report for Russian Language

**Date**: 2026-02-16
**Purpose**: Find best TTS/STT tools for Russian language support

---

## TTS (Text-to-Speech) Comparison Table

| Tool | Free? | Russian Quality | Naturalness | Pricing | Self-hosted? |
|------|-------|-----------------|-------------|---------|--------------|
| **Silero** | ✅ **FREE (CC-BY-NC)** | ⭐⭐⭐⭐⭐ Excellent | Very High | Free (MIT for base CIS models) | ✅ Yes |
| **Piper** | ✅ **FREE (MIT)** | ⭐⭐⭐⭐ Good | High | Free | ✅ Yes |
| **Coqui TTS** | ✅ **FREE (MPL-2.0)** | ⭐⭐⭐⭐ Very Good | Very High | Free | ✅ Yes |
| **OpenAI TTS** | ❌ Paid | ⭐⭐⭐⭐ Very Good | High | $15/1M characters | ❌ No |
| **Yandex SpeechKit** | ❌ Paid | ⭐⭐⭐⭐⭐ Excellent | Very High | ~$1-2/1M chars | ❌ No |
| **ElevenLabs** | ❌ Paid | ⭐⭐⭐⭐⭐ Excellent | Exceptional | ~$22/1M characters | ❌ No |

---

## STT (Speech-to-Text) Comparison Table

| Tool | Free? | Russian Accuracy | Speed | Pricing | Self-hosted? |
|------|-------|------------------|-------|---------|--------------|
| **Whisper.cpp** | ✅ **FREE (MIT)** | ⭐⭐⭐⭐⭐ Excellent | Fast (GPU) | Free | ✅ Yes |
| **Silero STT** | ✅ **FREE (CC-BY-NC)** | ⭐⭐⭐⭐ Very Good | Very Fast | Free | ✅ Yes |
| **Vosk** | ✅ **FREE (GPL/Apache)** | ⭐⭐⭐ Good | Fast | Free | ✅ Yes |
| **OpenAI Whisper** | ❌ Paid | ⭐⭐⭐⭐⭐ Excellent | Fast | $0.36/minute | ❌ No |
| **Groq Whisper** | ❌ Paid | ⭐⭐⭐⭐⭐ Excellent | ⚡ Very Fast | ~$0.20-0.40/min | ❌ No |
| **Yandex SpeechKit** | ❌ Paid | ⭐⭐⭐⭐⭐ Excellent | Fast | ~$0.01-0.02/sec | ❌ No |

---

## TOP 3 Recommendations

### TTS Top 3:

**🥇 1. SILERO** (FREE) - Best Overall for Russian
- Exceptional Russian quality with native stress/homograph handling
- 5 different Russian speakers (aidar, baya, kseniya, xenia, eugene)
- SSML support
- MIT license for CIS base models
- Perfect for production use in Russian applications

**🥈 2. PIPER** (FREE) - Best for Resource-Constrained Environments
- Very lightweight and fast
- Good Russian quality
- MIT licensed (fully open source)
- Easy to integrate
- Best for embedded/edge deployments

**🥉 3. YANDEX SPEECHKIT** (Paid) - Best Commercial Quality
- Best-in-class Russian voice quality (Russian company)
- Optimized specifically for Russian language
- Competitive pricing for Russian usage
- Reliable API with good SLA

---

### STT Top 3:

**🥇 1. WHISPER.CPP** (FREE) - Best Overall
- State-of-the-art accuracy for Russian
- Fast with GPU support (Metal/Vulkan/CUDA)
- Multiple model sizes (tiny to large-v3-turbo)
- MIT licensed
- Can run fully offline
- Community-maintained and actively developed

**🥈 2. SILERO STT** (FREE) - Best for Production Speed
- Blazing fast inference
- Excellent Russian accuracy
- Russian-team development
- Lightweight models
- Perfect for real-time applications

**🥉 3. GROQ WHISPER** (Paid) - Best for Speed/Convenience
- Ultra-fast inference (~1 second for most audio)
- State-of-the-art Whisper models
- Simple API integration
- Pay-as-you-go pricing

---

## Cost Comparison Summary

**TTS (1M characters ≈ 23 hours of audio):**
- Silero/Piper/Coqui: **$0** (self-hosted, server costs only)
- OpenAI: **$15** (tts-1) or **$30** (tts-1-hd)
- Yandex: **$1-2**

**STT (1 hour of audio):**
- Whisper.cpp/Silero/Vosk: **$0** (self-hosted, server costs only)
- OpenAI: **$21.60** ($0.36/min × 60 min)
- Groq: **$12-24**

---

## Implementation Recommendations for Moltis

**TTS Stack:**
1. **Primary**: Silero (v5_ru model) - Free, excellent Russian quality
2. **Fallback**: OpenAI TTS - For when you need absolute best quality

**STT Stack:**
1. **Primary**: Whisper.cpp (base or small model) - Free, excellent Russian accuracy, fast with GPU
2. **Fallback**: Groq Whisper API - For speed-critical applications

**Estimated Monthly Savings**: Using Silero + Whisper.cpp instead of commercial APIs could save **$300-500/month** for moderate usage (100 hours TTS + 100 hours STT).

---

## Moltis Configuration

Moltis supports these voice providers:
- TTS: ElevenLabs, OpenAI, Google, Piper, Coqui
- STT: Whisper, Groq, Deepgram, Google, Mistral, ElevenLabs

**Recommended config:**
```toml
[voice.tts]
enabled = true
provider = "silero"  # Or "piper" - both work locally

[voice.stt]
enabled = true
provider = "whisper"  # Moltis can use local Whisper
```

---

## Sources

- [Silero Models GitHub](https://github.com/snakers4/silero-models)
- [Piper GitHub](https://github.com/rhasspy/piper)
- [Coqui TTS GitHub](https://github.com/coqui-ai/TTS)
- [Whisper.cpp GitHub](https://github.com/ggerganov/whisper.cpp)
- [OpenAI TTS Documentation](https://platform.openai.com/docs/guides/text-to-speech)
