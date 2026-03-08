---
description: Run consilium analysis with adaptive execution mode and produce a full evidence-based report.
argument-hint: "[question]"
---

# Consilium Command

Run a multi-expert consilium analysis for the given question.

## Usage

`/consilium [question]`

Example:

`/consilium Проверь изменения в Telegram-боте, найди корневую причину регресса и предложи минимум 5 решений`

## Execution Contract

1. Always attempt parallel execution first when sub-agents are available.
2. If sub-agents are unavailable, continue in deterministic single-agent expert-matrix mode.
3. Never stop with a short "fallback" note; always produce the complete report.
4. Base conclusions on evidence (git history, diffs, configs, logs) when available.

## Required Output

1. `Consilium Report` with explicit `Execution Mode`.
2. `Evidence` section with concrete facts.
3. `Root Cause Analysis` with confidence.
4. At least `5` solution options with trade-offs.
5. `Recommended Plan`, `Rollback Plan`, and `Verification Checklist`.
