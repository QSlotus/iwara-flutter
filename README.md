# Signal Desk

Multi-source Android shell with **shared Cloudflare forced-IP edge resolve**.

| Module | Status |
|--------|--------|
| **Iwara** | Full client (migrated, behavior preserved) |
| **Qinav** | List / search / detail / local HLS proxy playback |

## Architecture

See [docs/DESIGN.md](docs/DESIGN.md) for the locked design tree.

```text
lib/
  shell/           # edge gate + hub (projects / software info)
  core/edge/       # shared CF probe + IP store
  core/update/     # GitHub release updates (shell software-info tab)
  features/iwara/  # Iwara module
  features/qinav/  # Qinav module
```

## Cold start

1. Shared CF edge probe (skipped if IP already locked)
2. **Always** show shell hub (project picker + software info tabs)
3. Enter module (hard-unloaded on exit)

## Build

Use the E: toolchain wrapper so caches stay off C:

```powershell
E:\ccworks\iwara\.flutter-tools\flutter-env.ps1 pub get
E:\ccworks\iwara\.flutter-tools\flutter-env.ps1 run
E:\ccworks\iwara\.flutter-tools\flutter-env.ps1 build apk --release
```

- `applicationId`: `top.qiusyan.signaldesk`
- Dart package: `signal_desk`
- Release APK: `build/app/outputs/flutter-apk/app-release.apk`

Android Gradle repositories prefer Aliyun mirrors, with Google/Maven Central as fallback.

## CI / Updates

- GitHub Actions builds APK on `main` and publishes on `v*` tags.
- In-app update check lives on the shell **软件信息** tab (not inside modules).
- Update source: `QSlotus/iwara-flutter` GitHub Releases.