# Signal Desk — Design Tree (locked)

Captured from the grilling session. Implement against this document.

## Product

| Item | Value |
|------|--------|
| Display name | Signal Desk |
| applicationId | `top.qiusyan.signaldesk` |
| Dart package | `signal_desk` |
| V1 modules | Iwara + Qinav |
| Update checks | Whole-app GitHub Release; source remains `QSlotus/iwara-flutter` for now |
| Cold start | Shared CF edge resolve (skip probe if IP locked) → **always** project picker |
| Module switch | Exit to picker; **hard unload** module state/servers |
| Shell UI | Neutral dark hub (projects + about tabs); modules keep own look |

## Architecture

```text
lib/
  shell/           # bootstrap, edge gate, project picker, unload
  core/
    edge/          # shared CF forced-IP probe + store (SNI same as Iwara)
    update/        # GitHub release update check
    theme/         # shell theme tokens only
  features/
    iwara/         # existing app, black-box behavior preserved
    qinav/         # Flutter rewrite (P2: list/search/detail/HLS play)
```

### Shared
- Cloudflare forced resolve / edge IP / SNI behavior aligned with current Iwara
- Shell hub routing; update check on software-info tab only

### Not shared
- Business APIs, shelf route tables, auth sessions
- Prefs prefixes, cache dirs, per-module local servers/ports

### Isolation rules
1. Prefs: `shell.*` / `iwara.*` / `qinav.*` (legacy `iwara-edge-*` migrated into `shell.edge.*`)
2. Cache directories per module
3. Iwara keeps its existing port strategy; Qinav uses a separate fixed loopback port (P2)
4. Single APK / single Release channel

## Lifecycle

1. App start → load locked edge IP; probe only if missing
2. Project picker (every cold start)
3. Enter module → start only that module's servers/state
4. Exit module → dispose everything → picker
5. Process death → back to step 1

## Phases

| Phase | Scope | Done when |
|-------|--------|-----------|
| **P1** | Rename Signal Desk; `core/edge`; picker; Iwara migrated & runnable; Qinav placeholder | Iwara main paths regress OK |
| **P2** | Qinav list/search/detail + local HLS proxy play | Watch loop works; hard unload no cross-talk |
| **P3** | Optional: Qinav download, more sources, repo rename | Out of default scope |

## Iwara red line
- Black-box behavior unchanged
- Allowed: move under `features/iwara/`, import path changes, read shared edge IP from shell

## Explicit non-goals (V1)
- WebView / Node sidecar for qinav-web
- Hot-switch keep-alive of both modules
- Wide shared media pipeline rewriting Iwara
- Qinav full-file download
- Third content source

## Grilling answers (audit)

- Q1=A neutral shell brand
- Q2=A Iwara+Qinav only
- Q3=A code isolation
- Q4=A always pick on cold start
- Q5=A Flutter rewrite Qinav
- Q6=A new applicationId
- Q7=A Qinav watch loop, no download
- Q8=B exit to picker, no shared stack
- Q9=A narrow kernel + **shared CF forced resolve** (Qinav uses CF/SNI same as Iwara)
- Q10=A single-app monorepo layout
- Q11=1..4 isolation rules
- Q12=A edge before picker
- Q13=A hard unload
- Q14=A naming table above
- Q15=A black-box Iwara
- Q16=A local HLS proxy for Qinav
- Q17=A neutral shell UI
- Q18=A skip re-probe when IP locked
- Q19=A phased P1 then P2
- Q20=A Iwara ports unchanged; Qinav separate port

## Shell hub tabs
- Projects: module entry
- Software info: version + GitHub Release update check (removed from Iwara account page)
