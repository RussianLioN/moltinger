# Tests Instructions

This directory contains the shell-based test framework for Moltinger.

## Source of Truth

Read `tests/README.md` before changing runners or test helpers.

Key contracts:
- runner scripts in `tests/run_*.sh`
- shared helper API in `tests/lib/test_helpers.sh`
- JSON output behavior for CI-facing usage

## Rules

1. Do not bypass the runner structure casually.
   Keep the existing split:
   - unit
   - integration
   - e2e
   - security
2. Treat `tests/lib/test_helpers.sh` as a shared contract.
   Changes there can break many suites at once.
3. Preserve output semantics.
   If tests are consumed by CI or automation, do not silently break JSON output, exit codes, or filtering behavior.
4. Keep tests bounded and purpose-driven.
   Prefer targeted checks over broad brittle scripts.
5. E2E and security tests are higher risk.
   Be careful with anything that:
   - talks to real services
   - mutates state
   - depends on credentials
   - assumes production-like endpoints

## Validation

After changing tests:
- run the narrowest relevant runner
- validate helper compatibility if `tests/lib/` changed
- state clearly what was actually executed

If a full suite was not run, say so explicitly.

## Naming and Structure

- reusable utilities belong in `tests/lib/`
- test-specific logic belongs in the nearest suite directory
- do not duplicate helper logic across many test files if it should live in the shared helper layer
