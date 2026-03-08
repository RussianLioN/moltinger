# RCA: Browser Compatibility Investigation (Deploy Gap)

Date: 2026-03-07  
Issue: Browser compatibility diagnosis had conflicting signals between branch config and production behavior.

## 5 Whys

1. Why did Yandex/Arc symptoms remain inconsistent with expected fixes?
   - Because production behavior did not match current branch configuration.
2. Why did production differ from current branch?
   - Because production was deployed from SHA `65c9942`, while branch contains newer proxy-header changes.
3. Why were proxy-header changes not present in production labels?
   - Because the branch changes had not yet been promoted/deployed.
4. Why did this slow root-cause isolation?
   - Because diagnosis mixed two states: "code in branch" vs "config running in prod."
5. Why was this not caught immediately?
   - Because deployment SHA/active labels were not verified as the first diagnostic step.

## Root Cause

Primary process gap: investigation started without first reconciling deployed SHA and active runtime labels against branch state.

## Actions

1. Always start browser/network incident triage with:
   - deployed SHA check;
   - runtime Traefik/Moltis label snapshot.
2. Re-test Yandex only after deploying the intended proxy-header middleware to production.
3. Keep Arc GPU workaround documented separately from server-side auth/proxy hypotheses.
