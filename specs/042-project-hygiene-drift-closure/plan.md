# Implementation Plan: Project Hygiene Drift Closure

**Branch**: `[fix/project-remediation-blockers]` | **Date**: 2026-04-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/042-project-hygiene-drift-closure/spec.md`

## Summary

После блокирующих fixes закрываем planning/documentation drift: обновляем active summaries, классифицируем stale spec packages и делаем явным current source of truth для provider/runtime/deploy behavior.

## Technical Context

**Language/Version**: Markdown, shell checks
**Primary Dependencies**: `SESSION_SUMMARY.md`, `specs/*`, active docs/rules
**Testing**: doc/spec consistency review, targeted static checks where available
**Target Platform**: repository planning and operator docs
**Constraints**: не переписывать incident history; менять только active/current-authority surfaces
**Scale/Scope**: planning hygiene, session summary, spec classification

## Constitution Check

- Artifact-first clarification: pass. Hygiene changes themselves are spec-driven.
- Historical evidence preservation: pass. RCA remain historical, active docs receive the update.
- Shared-contract rule: pass. Hygiene is handled in same dedicated remediation lane because it follows directly from the blocker review and changes current shared contracts/docs.

## Phase 0: Inventory

1. Reconfirm which packages/docs are active, stale, malformed, or historical.
2. Pick the minimum authoritative set for future work.

## Phase 1: Active Surface Refresh

1. Refresh `SESSION_SUMMARY.md` away from stale March-era provider/runtime truth.
2. Add explicit classification/supersession notes where broken packages could mislead work.

## Phase 2: Verification

1. Reconcile `tasks.md`.
2. Ensure active docs/specs point to current blocker-remediation packages and runtime truth.
