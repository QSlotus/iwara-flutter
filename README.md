# Iwara Signal Desk (Flutter)

Android client for browsing Iwara with a local loopback API proxy that forces Cloudflare edge IPs + SNI.

## Features

- Local loopback API proxy (forced Cloudflare IP + SNI)
- Edge latency probe and node selection
- Home / Explore / Library / Account / Video detail
- Media proxy for thumbnails and playback

## Requirements

- Flutter **3.44.9+** (Dart **3.12.2+**)
- Android SDK / JDK 17 for local Android builds

## Getting started

```bash
flutter pub get
flutter run
```

Release APK:

```bash
flutter build apk --release
```

Output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## CI

GitHub Actions (`.github/workflows/build-android.yml`) on every push/PR to `main`:

1. `flutter pub get`
2. `flutter analyze`
3. `flutter build apk --release`
4. Upload `app-release.apk` as a workflow artifact

Pushing a tag like `v0.1.0` also creates a GitHub Release with the APK attached.

## Project layout

```text
lib/
  main.dart
  app.dart
  models/
  screens/
  services/
  widgets/
assets/
  IWARA_API_INDEX.json
  cloudflare-ip-ranges.txt
android/
```

## License

Private use / as-is unless a license file is added later.
