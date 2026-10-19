# Build guide — one app per game

How to build an installable app for a single game (or all games), where the
files land, and what to check before a release. Run every command from the
project root.

> **Keep this file current.** When a game is added, removed or renamed, update
> the [game table](#2-games-and-entry-points) and the
> [build log](#8-build-log). When signing, app ids or flavors change, update
> [§6](#6-before-a-store-release).

---

## 1. How single-game apps work

Each game has its own entry file, `lib/main_<game>.dart`. It starts the app
with an `AppProfile` that lists only that game's module, so:

- only that game's code is compiled in (other games are left out of the build);
- Home shows no game picker;
- the game's name is the in-app brand (splash, login, titles).

`lib/main.dart` is the development build with **every** game and the picker.

A test (`test/game_isolation_test.dart`) fails if one game imports another, so
every entry file stays buildable on its own.

---

## 2. Games and entry points

| Game | Entry file | Play modes today |
|---|---|---|
| All games (dev) | `lib/main.dart` | All of the below |
| Chess | `lib/main_chess.dart` | Online + Quick Play |
| Snakes & Ladders | `lib/main_snakes.dart` | Quick Play |
| Ludo | `lib/main_ludo.dart` | Quick Play |
| Othello | `lib/main_othello.dart` | Quick Play |
| Checkers | `lib/main_checkers.dart` | Quick Play |
| Scrabble | `lib/main_scrabble.dart` | Quick Play |
| Crash | `lib/main_crash.dart` | Practice chips |
| Bingo | `lib/main_bingo.dart` | Quick Play |
| Roulette | `lib/main_roulette.dart` | Practice chips (European / French / American) |
| Poker | `lib/main_poker.dart` | Quick Play |
| Racing | `lib/main_racing.dart` | Practice chips |
| Rummy | `lib/main_rummy.dart` | Quick Play |
| Uno | `lib/main_uno.dart` | Quick Play |
| Carrom | `lib/main_carrom.dart` | Quick Play |

> **Judging animations:** `flutter run` is debug mode, where animations
> stutter on a phone. Use `flutter run --release -t lib/main_<game>.dart` (or
> install the release APK) to see real smoothness.

In the commands below, replace `<game>` with the part after `main_`
(e.g. `chess`, `snakes`, `uno`).

---

## 3. Android

| What | Command | Output (`build/app/outputs/…`) |
|---|---|---|
| Release APKs, one per CPU (recommended) | `flutter build apk --release --split-per-abi -t lib/main_<game>.dart --obfuscate --split-debug-info=build/symbols/<game>` | `flutter-apk/app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk` |
| One universal release APK (bigger) | `flutter build apk --release -t lib/main_<game>.dart` | `flutter-apk/app-release.apk` |
| Debug APK (quick install) | `flutter build apk --debug -t lib/main_<game>.dart` | `flutter-apk/app-debug.apk` |
| Play Store bundle | `flutter build appbundle --release -t lib/main_<game>.dart --obfuscate --split-debug-info=build/symbols/<game>` | `bundle/release/app-release.aab` |

`--obfuscate --split-debug-info` makes the app code smaller and harder to
reverse-engineer. It writes the symbols needed to read crash stack traces to
`build/symbols/<game>/`: **keep that folder for every build you hand out**
(copy it next to the APK). `flutter clean` deletes it. To read a crash:
`flutter symbolize -i <stack.txt> -d build/symbols/<game>/app.android-arm64.symbols`.

Which APK to give a tester:

| APK | For |
|---|---|
| `app-arm64-v8a-release.apk` | Almost every phone from the last ~7 years |
| `app-armeabi-v7a-release.apk` | Older 32-bit phones |
| `app-x86_64-release.apk` | Emulators |

Install on a phone plugged in by USB (USB debugging on):

```sh
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

> **Each build overwrites the previous one.** All games build into the same
> file names. Copy or rename the APK before building the next game, e.g.
> `cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ~/Desktop/chess-1.0.0-arm64.apk`.

### App size

The Flutter engine (~11.7 MB unpacked) is in every app and can't be
removed; each game adds only its own code. Already done to keep apps small:

| Saving | How |
|---|---|
| ~12 MB (21.6 → 9.6 MB for Chess) | Engine and app code stored **compressed** in the APK (`useLegacyPackaging = true` in `android/app/build.gradle.kts`). They're unpacked once at install, so the installed size is close to the old 21 MB |
| ~260 KB | Removed the unused `cupertino_icons` font |
| ~130 KB | Splash images are no longer bundled (only used to generate the native launch screen) |
| ~100 KB | Removed unused font weights (Manrope ExtraLight / Light, Space Grotesk Light) |
| A little (not measured separately) | `--obfuscate --split-debug-info` |
| ~0.4 MB in every app except Scrabble | Scrabble's word list is compiled into Scrabble's code (`lib/game/scrabble/scrabble_words.g.dart`) instead of being an asset, so other apps don't carry it. After editing `assets/scrabble/words.txt`, run `dart run tools/gen_scrabble_words.dart` (a test fails if they differ) |

Still possible later:
- Launcher icon and splash images (~0.5 MB at 5 screen densities) as WebP,
  or fewer densities.
- **Play Store download size** is smaller than the APK: Play sends each
  phone only its own CPU's code.

> **Only one game app on a phone at a time.** Every game currently uses the
> same application id, so installing Ludo replaces Chess. See §6.

---

## 4. iOS (needs full Xcode on a Mac)

```sh
flutter build ipa --release -t lib/main_<game>.dart
```

Output: `build/ios/ipa/`. It needs an Apple developer account and signing set
up in Xcode (`ios/Runner.xcworkspace`). Not set up on this machine yet: only
the command-line tools are installed, not Xcode.

---

## 5. Web

```sh
flutter build web --release -t lib/main_<game>.dart
```

Output: `build/web/` (static files for any web host). Browsers allow the
game sockets cross-origin, but the REST API needs CORS from the server or the
dev proxy (see RUN_AND_TEST §3).

---

## 6. Before a store release

| Item | Status | What to do |
|---|---|---|
| Signing key | ❌ Release builds are signed with the **debug** key (`android/app/build.gradle.kts`, `signingConfig = debug`) | Create an upload keystore, add `android/key.properties` (never commit it), point the `release` signing config at it |
| Application id | ❌ `com.example.snakeladder` for every game | One id per game, e.g. `com.<company>.chess`, via Android `productFlavors` and iOS schemes (`--flavor chess -t lib/main_chess.dart`) |
| Launcher name | ⚠️ Android `android:label` and iOS `CFBundleDisplayName` are hard-coded to **"Chess"**, so every game shows "Chess" under its icon | Set per flavor once flavors exist (until then, edit both before building another game) |
| App icon | ⚠️ One icon for all games | Per-flavor icons (`flutter_launcher_icons`) |
| Version | `version: 1.0.0+1` in `pubspec.yaml` | Raise the build number (`+N`) for every store upload; or pass `--build-name 1.0.1 --build-number 2` |
| Server | ✅ Release builds go **direct** to the servers: the dev proxy is always off in release | Override only if needed: `--dart-define=API_BASE_URL=…` (RUN_AND_TEST §6) |
| Environment | ⚠️ Builds use the **dev** server (plain HTTP / `ws://` on 169.58.184.121) unless told otherwise | `--dart-define=APP_ENV=prod` selects production, but **prod (and staging) still point at the dev server**: add the real HTTPS host in `lib/configs/environment.dart` first |
| Cleartext traffic | ⚠️ Android allows plain HTTP for the dev server (`android:networkSecurityConfig`) | Remove the exception once production is HTTPS |
| Uno name | ⚠️ "UNO" is a Mattel trademark | Rename `unoConfig.displayName` and the `unoCall` string before a store release |
| Real-money games | ⚠️ Crash, Roulette and Racing use practice chips only | Real-money play needs store and legal approval |

---

## 7. Checks before handing out a build

```sh
flutter analyze          # must report no issues
flutter test             # all tests must pass
```

Then on a real phone: open the app → sign in → Quick Play a game → finish it
(result screen) → Play again. For Chess also start an online match. Use
docs/TEST_CASES.md for the full list.

---

## 8. Build log

Add a line for each build handed to someone (newest first). Sizes are what
`flutter build` printed.

| Date | Game | Version | Build | Size (arm64) | Signed with | Notes |
|---|---|---|---|---|---|---|
| 2026-10-19 | Scrabble | 1.0.0+1 | `apk --release --split-per-abi --obfuscate` | 9.5 MB | debug key | Word list compiled in. Symbols: `build/symbols/scrabble`. Test build only |
| 2026-10-19 | Chess | 1.0.0+1 | `apk --release --split-per-abi --obfuscate` | 9.2 MB | debug key | Without the Scrabble word list. Symbols: `build/symbols/chess`. Test build only |
| 2026-10-19 | Chess | 1.0.0+1 | `apk --release --split-per-abi --obfuscate` | 9.6 MB (v7a 9.1 MB, x86_64 9.8 MB) | debug key | After size work. Symbols: `build/symbols/chess`. Test build only |
| 2026-10-19 | Chess | 1.0.0+1 | `apk --release --split-per-abi` | 21.6 MB (v7a 19.3 MB, x86_64 23.1 MB) | debug key | Before size work. Test build only, not for the store |
