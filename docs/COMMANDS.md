# Aura — Command Reference

Direct commands for running, testing, and building the app. Run all from the
project root (`snakeladder/`).

---

## 1. Prerequisites (one-time)
- Flutter SDK 3.47.4+ (Dart ^3.13.3) — `flutter --version`
- **JDK 17** (Gradle needs a Java runtime) — `java -version`
- **Android SDK 36** + Build-Tools + platform-tools (via Android Studio or `sdkmanager`)
- Verify everything: `flutter doctor` → must show **[✓] Android toolchain**.

### This machine — already set up ✅
JDK 17 + the Android toolchain are installed and wired to Flutter, so
`flutter build apk` works directly. What was done:
- `brew install openjdk@17` → JDK at `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`
- `flutter config --jdk-dir="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"`
- `flutter config --android-sdk "$HOME/Library/Android/sdk"`
- `flutter doctor --android-licenses` (accepted); Gradle auto-installed SDK Platform 36/35 + CMake.
- Optional — make `java` available in new terminals:
  `echo 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' >> ~/.zshrc`
  (Flutter already knows the JDK via `--jdk-dir`, so this is only for using `java`/`gradle` directly.)
- Last successful build: `build/app/outputs/flutter-apk/app-release.apk` (~51 MB).

---

## 2. Project setup
- Install dependencies: `flutter pub get`
- Upgrade dependencies: `flutter pub upgrade`
- Clean build artifacts: `flutter clean` (then `flutter pub get`)

---

## 3. Quality gates (run before every build)
- Static analysis: `flutter analyze`
- Full test suite (46 tests): `flutter test`
- Single test file: `flutter test test/screens_smoke_test.dart`
- Update golden images: `flutter test --update-goldens`

---

## 4. Run the app (dev)
- List devices: `flutter devices`
- Run on the connected device/emulator: `flutter run`
- Run in release mode: `flutter run --release`
- Pick a device: `flutter run -d <deviceId>`
- With the API base URL injected: `flutter run --dart-define=API_BASE_URL=https://api.example.com`

---

## 5. Build Android APK
- Release APK (single, universal):
  `flutter build apk --release`
  → output: `build/app/outputs/flutter-apk/app-release.apk`
- Split per ABI (smaller installs):
  `flutter build apk --release --split-per-abi`
  → `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, `app-x86_64-release.apk`
- Debug APK (quick install, not for release):
  `flutter build apk --debug`
- With API base URL baked in:
  `flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com`

## 6. Build Android App Bundle (Play Store)
- `flutter build appbundle --release`
  → output: `build/app/outputs/bundle/release/app-release.aab`

> Release signing: configure `android/key.properties` + a keystore and reference it in
> `android/app/build.gradle` before shipping to the Play Store. Unsigned/debug-signed
> builds install for testing but can't be published.

---

## 7. Install / share the APK
- Install to a plugged-in device: `adb install -r build/app/outputs/flutter-apk/app-release.apk`
- List devices for adb: `adb devices`

---

## 8. Other targets (optional)
- iOS (needs Xcode + CocoaPods): `flutter build ios --release`
- Web: `flutter build web`
- Web run: `flutter run -d chrome`

---

## 9. Connecting to the dev API
The live dev API is `http://169.58.184.121:30080/api/v1` (see `docs/INTEGRATION_PLAN.md`
§7b). It's injected at build/run time — nothing is hardcoded:
- Run against it: `flutter run --dart-define=API_BASE_URL=http://169.58.184.121:30080/api/v1`
- Build APK against it: `flutter build apk --release --dart-define=API_BASE_URL=http://169.58.184.121:30080/api/v1`
- **Cleartext HTTP** to that IP is already whitelisted for Android in
  `android/app/src/main/res/xml/network_security_config.xml` (all other hosts stay
  HTTPS-only). `INTERNET` permission is declared in the manifest.
- **Not wired on yet:** the app still uses static data (`useRemoteSourcesProvider = false`).
  Turning it on additionally needs the API's JSON field names mapped into each
  `Remote*Source` (backend is snake_case) — pending a test token / schema.

## 10. Notes for this project
- App is presentation-only today; the real API is injected via `--dart-define=API_BASE_URL=…`.
- Tests can't fetch Google Fonts offline — that's expected and harmless; goldens render
  with a fallback font in CI.
