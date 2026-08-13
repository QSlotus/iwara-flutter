# Signal Desk

Multi-source Android shell with **shared Cloudflare forced-IP edge resolve**.

| Module | Status |
|--------|--------|
| **Iwara** | Full client (migrated, behavior preserved) |
| **Qinav** | Placeholder in P1; P2 = list/search/detail/HLS play |

## Architecture

See [docs/DESIGN.md](docs/DESIGN.md) for the locked design tree.

`	ext
lib/
  shell/           # edge gate + project picker
  core/edge/       # shared CF probe + IP store
  core/update/     # GitHub release updates
  features/iwara/  # Iwara module
  features/qinav/  # Qinav module (P2)
`

## Cold start

1. Shared CF edge probe (skipped if IP already locked)
2. **Always** show project picker
3. Enter module (hard-unloaded on exit)

## Build

`ash
flutter pub get
flutter run
flutter build apk --release
`

pplicationId: 	op.qiusyan.signaldesk

## CI / Updates

GitHub Actions builds APK on main and publishes on * tags.
In-app update check uses QSlotus/iwara-flutter releases.
