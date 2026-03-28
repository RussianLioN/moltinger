# Consilium: Moltis browser stale session, Telegram Activity log leak, and OpenClaw sandbox/Pair implications

Date: 2026-03-28
Scope: `033-moltis-browser-session-logbook-fix`
Mode: evidence-first

## Question

Что из текущего инцидента repo действительно может исправить сам, что уже относится к
upstream Moltis/OpenClaw runtime, и как официальные docs влияют на operational decision
между `Pair`, sandbox recreate, и Telegram degraded-mode?

## Experts

- Runtime / architecture expert
- OpenClaw sandbox expert
- SRE / user-facing containment expert

## Consolidated Answer

1. `Pair` не является доказанным root-cause fix для текущего browser/session incident.
2. Official docs ведут к sandbox/runtime recreate/revalidation, а не к pair-click.
3. Repo должен внедрить временное containment и точную диагностику.
4. Окончательное закрытие user-facing issue потребует upstream/runtime fix.

## Findings

### Moltis runtime angle

- Наиболее вероятный remaining root cause:
  - stale browser session survives browser death / timeout path;
  - Telegram outbound path leaks internal status logbook.
- Repo-side приемлемые меры:
  - blocking UAT on any `Activity log`;
  - fail-closed browser taxonomy;
  - explicit degraded-mode for Telegram browser-heavy paths;
  - upstream issue with concrete evidence.

### OpenClaw sandbox / Pair angle

- Official Pair docs описывают:
  - DM pairing
  - node/device pairing
- Они не описывают browser-session cleanup.
- Official sandbox docs imply:
  - sandbox/browser behavior follows sandbox/runtime config;
  - config/runtime drift требует recreate/reset, а не Pair by default.

### SRE angle

- User-facing Telegram path нужно временно защитить:
  - classic final-only delivery;
  - no tool-heavy browser path by default in Telegram;
  - fail closed on `Activity log`, timeout suffix, browser contamination.
- Repo-owned closure:
  - diagnostics
  - UAT
  - runbook/rules
  - containment
- Upstream-owned closure:
  - browser cache invalidation after failure
  - Telegram suffix/logbook delivery behavior

## Recommendation

### Immediate

1. Ship repo-side containment and taxonomy in `033`.
2. Treat `Pair` as non-default action.
3. Use official sandbox/browser docs as the operational baseline.

### Closure criteria

Do not close the incident until all of the following are true:

1. `t.me/...` browser canary starts with a clean session and stays healthy.
2. A repeated browser run does not reuse a stale `browser-*` session after failure.
3. Telegram receives only final user-facing replies with no `Activity log`.
4. Browser death does not degrade into `PoolExhausted` on the next run.

## Decision

The correct strategy is:

- repo-side containment now;
- upstream issue next;
- no false claim that prompt/config alone fully solved the problem.
