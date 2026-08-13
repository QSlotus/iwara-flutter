# Signal Desk — Design Tree (locked)

Captured from grilling sessions. Implement against this document.

## Product

| Item | Value |
|------|--------|
| Display name | Signal Desk |
| applicationId | `top.qiusyan.signaldesk` |
| Dart package | `signal_desk` |
| V1 modules | Iwara + Qinav + **Xmav** |
| Update checks | Whole-app GitHub Release; source remains `QSlotus/iwara-flutter` for now |
| Cold start | Shared CF edge resolve (skip probe if IP locked) → **always** project picker |
| Module switch | Exit to picker; **hard unload** module state/servers |
| Shell UI | Neutral dark hub (projects + about tabs); modules keep own look |

## Architecture

```text
lib/
  shell/           # bootstrap, edge gate, project picker, unload
  core/
    edge/          # shared CF forced-IP probe + store (SNI same as Iwara/Qinav site hosts)
    update/        # GitHub release update check
    theme/         # shell theme tokens only
    player/        # shared VideoSurface + FullscreenVideoPage
  features/
    iwara/         # existing app, black-box behavior preserved
    qinav/         # Flutter rewrite (list/search/detail + local HLS proxy)
    xmav/          # Flutter rewrite (list/category/search/detail + direct play)
```

### Shared
- Cloudflare forced resolve / edge IP / SNI for **Iwara + Qinav site hosts only**
- Shell hub routing; update check on software-info tab only
- Shared video surface / fullscreen page

### Not shared
- Business APIs, route tables, auth sessions
- Prefs prefixes, cache dirs, per-module local servers/ports
- Xmav does **not** use CF pin or local HLS proxy

### Isolation rules
1. Prefs: `shell.*` / `iwara.*` / `qinav.*` / `xmav.*` (legacy `iwara-edge-*` migrated into `shell.edge.*`)
2. Cache directories per module
3. Iwara keeps its existing port strategy; Qinav uses fixed loopback port `18766`
4. Xmav: **no** module loopback port (direct CDN playback)
5. Single APK / single Release channel

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
| **P3** | Xmav V1 watch loop (list/category/search/detail/play) | Watch loop works; no CF; hard unload |
| **P4+** | Optional: Qinav download, Xmav related-recommend (V2), more sources, repo rename | Out of default scope |

## Iwara red line
- Black-box behavior unchanged
- Allowed: move under `features/iwara/`, import path changes, read shared edge IP from shell

## Xmav (P3 locked)

| Item | Decision |
|------|----------|
| Display name | `Xmav` / hub subtitle `影视聚合浏览` |
| Entry | Permanent `http://xmav.vip` → relay → dynamic content `base` (never hardcode content host) |
| `base` cache | 24h TTL + manual「刷新线路」; full-screen error + retry on fail |
| Site access | **No** CF forced-IP / no site proxy |
| Playback | Shared player; **direct** CDN/m3u8 (no local HLS proxy) |
| Nav | Bottom tabs: **最新 \| 分类 \| 搜索** |
| Category IA | Category **grid** → tid list (not chips-on-home) |
| List paging | Bottom **page numbers** (not infinite scroll) |
| Search | HTML search + ajax suggest |
| Detail | Cover, title, blurb, actor/class/hits metadata, play |
| Play line | Only `{id}-1-1` in V1 |
| Encrypt | `player_aaaa` encrypt 0/1/2; parse fallback only if needed |
| hits API | Do **not** call |
| Related | V1 no; **V2 backlog** |
| Prefs | `xmav.base.url`, `xmav.base.at`, other `xmav.*` only |

## Explicit non-goals (current default)
- WebView / Node sidecar for qinav-web
- Hot-switch keep-alive of modules
- Wide shared media pipeline rewriting Iwara
- Qinav full-file download
- Xmav local HLS proxy / CF pin / multi sid-nid / related-recommend (V1)

## Grilling answers (shell + Qinav audit)

- Q1=A neutral shell brand
- Q2=A then extended: Iwara+Qinav+Xmav
- Q3=A code isolation
- Q4=A always pick on cold start
- Q5=A Flutter rewrite Qinav
- Q6=A new applicationId
- Q7=A Qinav watch loop, no download
- Q8=B exit to picker, no shared stack
- Q9=A narrow kernel + **shared CF forced resolve** (Qinav uses CF/SNI same as Iwara)
- Q10=A single-app monorepo layout
- Q11=1..4 isolation rules (+ xmav prefs)
- Q12=A edge before picker
- Q13=A hard unload
- Q14=A naming table above
- Q15=A black-box Iwara
- Q16=A local HLS proxy for Qinav
- Q17=A neutral shell UI
- Q18=A skip re-probe when IP locked
- Q19=A phased P1 then P2
- Q20=A Iwara ports unchanged; Qinav separate port

## Grilling answers (Xmav)

- Q1=A third hub module
- Q2=A V1 watch loop only
- Q3=A pure Flutter under `features/xmav/`
- Q4=A reuse shared player
- Q5=A resolve `base` on enter; cache with TTL
- Q6=A full isolation + hard unload
- Q7=B direct CDN only (no loopback HLS proxy)
- Q8=A 24h base cache + manual refresh
- Q9=C latest/category split; category grid → list
- Q10=A HTML search + suggest
- Q11=A only `{id}-1-1`
- Q12=A encrypt 0/1/2 + parse if needed
- Q13=A display name Xmav
- Q14=N/A (no proxy port)
- Q15=A tabs 最新\|分类\|搜索
- Q16=B detail metadata rich
- Q17=A no hits API
- Q18=A no related in V1 (V2 later)
- Q19=A fullscreen base error + AppBar 刷新线路
- Q20=B numbered pagination
- Q21=A direct cover images
- Q22=A hub subtitle 影视聚合浏览
- Q23=A phase P3 = Xmav V1

## Shell hub tabs
- Projects: module entry
- Software info: version + GitHub Release update check (removed from Iwara account page)
