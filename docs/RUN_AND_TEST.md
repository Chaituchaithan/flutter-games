# How to Run, Test & Build

How to run the Chess app on **Web (Chrome)** and the **Android emulator**, with
or without the dev proxy, how to debug the realtime socket, and how to test and
build release APKs. Settings live in `lib/configs` (§11).

_Last updated: 2026-10-10_

---

## 1. Overview

The app talks to one host, `169.58.184.121`: the **API gateway** on `:31294` (login, register, profile …) and **one service per game** on its own port (REST + socket on the same port):

- **REST API** — login, profile, data (`/api/v1/...`). ✅ Working.
- **WebSocket** — one service per game on ports 31281–31292 (chess `:31283/ws`).
  **ON:** after the API login the app signs in to the socket and opens Home
  only on `auth.login_success` (see §3, §9).

You can run the app in two modes, chosen by one switch:

| Mode | API goes to | Socket goes to | Use it for |
|---|---|---|---|
| **Proxy ON** (current default) | `http://localhost:8899/api/v1` → proxy → server | `ws://localhost:8899/svc/31283/ws` → proxy → chess service | Web (Chrome); emulator when you want proxy logs |
| **Proxy OFF** (original) | `http://169.58.184.121:31294/api/v1` directly | `ws://169.58.184.121:31283/ws` directly (chess) | Android emulator / real phone |

The proxy is `tools/cors_proxy.dart`. Chrome **needs** it because the server
sends no CORS headers, so the browser blocks direct calls. The proxy also
prints every API call and socket message, which makes it the easiest place to
debug.

---

## 2. Prerequisites

All commands run from the project folder:

```
cd /Applications/Workspace/Flutter/snakeladder
```

- **Flutter** 3.47.4+ (Dart ^3.13) — `flutter doctor` clean for Chrome and Android.
- **JDK 17** for Android builds. On this machine it's already wired to Flutter:
  `flutter config --jdk-dir="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"`
  and `flutter config --android-sdk "$HOME/Library/Android/sdk"`.
- Dependencies: `flutter pub get` (after changing `pubspec.yaml`; `flutter clean`
  first if a build acts stale).
- **Android emulators**: `Samsung_Galaxy_S23`, `Moto_G_5G`.
  List with `flutter emulators`; see running devices with `flutter devices`.
- **A test account** on the server. Log in with the account's **email**
  (the server rejects a bare username) and its password.
- **Android plain-HTTP access** to `169.58.184.121` is already allowed in
  `android/app/src/main/res/xml/network_security_config.xml` — nothing to set up.

---

## 3. Proxy switch (ON / OFF)

One setting decides the mode — `proxyEnabledByDefault` in `lib/configs/proxy_config.dart`.
It is currently **`true` (proxy ON)**.

```dart
/// MASTER SWITCH: true = proxy testing, false = direct (original) HTTP/WS.
const bool proxyEnabledByDefault = true;
```

Three ways to choose the mode:

1. **Change the default** — set `proxyEnabledByDefault` to `true` / `false`
   (or ask Claude: "turn on proxy" / "turn off proxy").
2. **Override for one run, no code change** — add
   `--dart-define=USE_PROXY=true` or `--dart-define=USE_PROXY=false`.
3. **Force exact URLs** — `--dart-define=API_BASE_URL=…` and
   `--dart-define=CHESS_WS_URL=…` win over both of the above.

When the proxy is ON the app picks the proxy address automatically:
`localhost:8899` on Chrome/iOS, `10.0.2.2:8899` on the Android emulator
(the emulator's name for your Mac).

### Socket switch

The socket is **ON** — `socketEnabledByDefault = true` in
`lib/configs/feature_flags.dart`:

1. API login (`POST /auth/login`, then `/users/me` + profile).
2. Open the active game's socket (chess `ws://…:31283/ws`) → server sends
   `connection.established`.
3. Send `{"id", "event": "auth.login", "data": {"token", "username"}}`.
4. **Only on `auth.login_success`** → Home. On `auth.login_error` or no
   connection you stay on Login with a message, and the half-open socket is closed.

Log out sends `auth.logout` and closes the socket.

To bypass it (login → Home with the API only; Online Play opens the practice
board): `socketEnabledByDefault = false`, or one run with
`--dart-define=SOCKET_ENABLED=false` (or ask Claude: "turn off socket").

---

## 4. Run on Web (Chrome) — proxy ON

Web **only works with the proxy**.

1. Terminal 1 — start the proxy (leave it running):
   ```
   dart run tools/cors_proxy.dart
   ```
   You should see: `CORS proxy: http://localhost:8899  ->  http://169.58.184.121:31294`
2. Terminal 2 — run the app:
   ```
   flutter run -d chrome
   ```
3. Log in with your email + password.
4. Watch Terminal 1 for `[proxy]` lines and the browser DevTools console
   (F12 → Console) for `[SOCKET]` lines (see §7).

If you changed the proxy code, restart it:
```
pkill -f tools/cors_proxy.dart; dart run tools/cors_proxy.dart
```

> Tip: Flutter web caches aggressively. If a change doesn't show up, hard
> refresh (Cmd+Shift+R).

---

## 5. Run on Android emulator

Start an emulator first:

```
flutter emulators --launch Samsung_Galaxy_S23
flutter devices            # note the id, usually emulator-5554
```

### 5a. Without proxy (direct, original HTTP)

No proxy needed — the app calls the server directly.

```
flutter run -d emulator-5554 --dart-define=USE_PROXY=false
```

(Or set `proxyEnabledByDefault = false` and just run `flutter run -d emulator-5554`.)

On native, the app sends the login token as an `Authorization: Bearer <token>`
header when it opens the socket.

### 5b. With proxy

1. Start the proxy: `dart run tools/cors_proxy.dart`
2. Run:
   ```
   flutter run -d emulator-5554 --dart-define=USE_PROXY=true
   ```
   The emulator reaches the proxy at `10.0.2.2:8899` automatically.

### Two players (two emulators)

Launch both emulators, then run one `flutter run` per device id
(e.g. `emulator-5554` and `emulator-5556`) and log in with **two different
accounts**. Both must pick the same currency + stake to be matched, or use
Play With Friends → create / join by room code.

---

## 6. Build-time overrides (`--dart-define`)

| Define | What it does | Example |
|---|---|---|
| `USE_PROXY` | Proxy ON/OFF for this run | `--dart-define=USE_PROXY=false` |
| `API_BASE_URL` | Exact REST base URL (wins over proxy switch) | `--dart-define=API_BASE_URL=http://169.58.184.121:31294/api/v1` |
| `CHESS_WS_URL` | Exact socket URL (wins over proxy switch) | `--dart-define=CHESS_WS_URL=ws://169.58.184.121:31283/ws` |
| `PROXY_HOST` | Where the proxy listens, if not the default | `--dart-define=PROXY_HOST=192.168.1.10:8899` |
| `SOCKET_ENABLED` | Socket ON/OFF for this run (OFF = bypass) | `--dart-define=SOCKET_ENABLED=true` |
| `SOCKET_USERNAME` | Fallback socket username when the account has none | `--dart-define=SOCKET_USERNAME=test2` |

Use `CHESS_WS_URL` to try a new socket path as soon as the server team gives
one — no code change needed.

---

## 7. Reading the logs

### `[SOCKET]` — from the app

Shown in the `flutter run` console (emulator) or browser DevTools console (web).

**Success looks like:**
```
[SOCKET] opening WS → ws://169.58.184.121:31283/ws
[SOCKET] recv connection.established {...}
[SOCKET] send auth.login { token: eyJ0eX…, username: <name> }
[SOCKET] recv auth.login_success {...}
```

**Failure looks like:**
```
[SOCKET] WS stream error (upgrade/transport): ... HTTP status code: 404
```
- `404` → wrong socket path (nothing at that address).
- `401` → token missing or not accepted.
- `auth.login_error` → socket opened but login was refused (check token/username).

### `[proxy]` — from the proxy terminal (proxy ON only)

```
[proxy] POST /api/v1/auth/login -> 200 body: {"access_token":"eyJ0eX…",...}   (tokens masked)
[proxy] ws open  /svc/31283/ws  <->  ws://169.58.184.121:31283/ws                 socket connected
[proxy] ws >> {...}        message app → server
[proxy] ws << {...}        message server → app
[proxy] ws upstream REFUSED ... -> 404 ...                                      server rejected the socket
```

Tokens and passwords are masked in all proxy logs, so they are safe to share.

### Socket message order (for reference)

```
1. App opens  ws://host:port/<path>      → server answers 101 (accepted)
2. Server  →  connection.established     (sent automatically by the server)
3. App     →  auth.login {token, username}
4. Server  →  auth.login_success
5. App     →  match.find / room.create / room.join → player.ready → game.action ...
```

---

## 8. Quick service checks (no account needed)

```
curl http://169.58.184.121:31294/health          # API gateway  → "api-gateway" ok
curl http://169.58.184.121:31283/health          # chess        → "chess-service" ok
curl http://169.58.184.121:31283/health/deep     # chess DB + cache → postgres/redis ok
curl http://localhost:8899/health                # through the proxy (if running)
curl http://localhost:8899/svc/31283/health      # a game through the proxy
```
Any game: swap `31283` for its port (§9). For the full chess flow with two
real accounts, run `tools/chess_flow_test.dart` (§9).

---

## 9. Game socket services

**Status (2026-10-10):** every game service runs on its own port on
`169.58.184.121`, socket path `/ws`. All 12 return `health: ok`, accept the
WebSocket, and send `connection.established` first.

| Port | Service | Port | Service |
|---|---|---|---|
| 31281 | Bingo | 31287 | Poker |
| 31282 | Checkers | 31288 | Racing |
| 31283 | **Chess** | 31289 | Roulette |
| 31284 | Crash | 31290 | Rummy |
| 31285 | Ludo | 31291 | Scrabble |
| 31286 | Othello | 31292 | Snakes & Ladders |

Health / metrics: `http://169.58.184.121:<port>/health` and `/metrics`.
These live in `lib/configs/games/<game>/<game>_config.dart`.

**Through the proxy** the app dials `ws://localhost:8899/svc/<port>/ws`; the
proxy forwards it to `169.58.184.121:<port>/ws`. Restart the proxy after
pulling these changes.

**The socket is ON by default.** Run normally and watch the console:
```
flutter run -d emulator-5554 --dart-define=USE_PROXY=false
```
Watch for `[SOCKET] recv auth.login_success`.

**Full chess check from the terminal** (two real accounts, a free game, no
wallet change): logs both in through the gateway, then plays create → join →
ready → e2-e4 → e7-e5 → resign → completed, printing ✅/❌ per step.
Passwords are asked at a hidden prompt.
```
dart run tools/chess_flow_test.dart <emailA> <emailB>
```
Verified without an account (2026-10-10): chess `/health`, `/health/deep`
(Postgres + Redis ok) and `/metrics`; the socket sends `connection.established`;
`auth.login` uses the **token** (a username alone is rejected outside debug mode,
and when both are sent the token wins).

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Login fails on Chrome with a network/CORS error | Proxy OFF or not running | Start `dart run tools/cors_proxy.dart`; make sure proxy is ON |
| Login fails on emulator with proxy ON | Proxy not running | Start the proxy, or run with `USE_PROXY=false` |
| `400 VALIDATION_ERROR: email` | Logged in with a username | Use the account's email address |
| `429 RATE_LIMITED` on login | More than 5 login attempts in a minute | Wait one minute |
| `[SOCKET] ... 404` | Wrong socket path on the server | See §9 — need the real URL from the server team |
| `[SOCKET] ... 401` | Token not sent / expired | Log in again (token lasts 15 min) |
| `auth.login_error` | Socket open but login refused | Check token and username in the `[SOCKET] send auth.login` line |
| Code change not visible on web | Browser cache | Hard refresh (Cmd+Shift+R) |
| Proxy changes not taking effect | Old proxy still running | `pkill -f tools/cors_proxy.dart; dart run tools/cors_proxy.dart` |

---

## 11. Configuration (`lib/configs`)

All configuration lives in `lib/configs` — no IPs, ports or `--dart-define`
reads anywhere else. Import `package:snakeladder/configs/configs.dart`.

| File | What to change there |
|---|---|
| `environment.dart` | Server host + gateway port per environment (`APP_ENV=dev/staging/prod`) |
| `server_config.dart` | How REST/socket URLs are built (http/https, ws/wss) |
| `proxy_config.dart` | Proxy on/off (`proxyEnabledByDefault`), proxy port |
| `feature_flags.dart` | Socket on/off (`socketEnabledByDefault`), remote data/auth |
| `network_config.dart` | Timeouts, socket ping/backoff |
| `build_overrides.dart` | Every `--dart-define` the app reads |
| `endpoints/api_endpoints.dart` | Shared REST paths |
| `games/<game>/<game>_config.dart` | A game's port (REST + socket), socket path, players, turn time, `<GAME>_WS_URL` override |
| `games/core/` | `GameId`, `GameConfig`, `GameRegistry` (the list of games), active game |

**Switch game (all-games build):** tap a game chip on Home, or start on one
with `--dart-define=GAME=chess`. Only games in the running app can be selected.

### Apps — one game per app

Each game is a self-contained module; each app is an entry point listing the
modules it ships (`AppProfile`). A single-game app contains only its own
game's code, shows no game picker, and uses the game's name as its brand.

| App | Entry point | Run |
|---|---|---|
| All games (development) | `lib/main.dart` | `flutter run` |
| Chess | `lib/main_chess.dart` | `flutter run -t lib/main_chess.dart` |
| Ludo | `lib/main_ludo.dart` | `flutter run -t lib/main_ludo.dart` |
| Snakes & Ladders | `lib/main_snakes.dart` | `flutter run -t lib/main_snakes.dart` |
| Othello | `lib/main_othello.dart` | `flutter run -t lib/main_othello.dart` |
| Checkers | `lib/main_checkers.dart` | `flutter run -t lib/main_checkers.dart` |
| Scrabble | `lib/main_scrabble.dart` | `flutter run -t lib/main_scrabble.dart` |
| Crash (Aviator style) | `lib/main_crash.dart` | `flutter run -t lib/main_crash.dart` |
| Bingo | `lib/main_bingo.dart` | `flutter run -t lib/main_bingo.dart` |
| Roulette | `lib/main_roulette.dart` | `flutter run -t lib/main_roulette.dart` |
| Poker (Texas Hold'em) | `lib/main_poker.dart` | `flutter run -t lib/main_poker.dart` |
| Racing | `lib/main_racing.dart` | `flutter run -t lib/main_racing.dart` |
| Rummy (13-card points) | `lib/main_rummy.dart` | `flutter run -t lib/main_rummy.dart` |

Any combination is one more entry file, e.g. a "Ludo + Snakes" app:
`AppProfile(appName: '…', modules: [ludoModule, snakesModule])`.

**Rules (enforced by `test/game_isolation_test.dart`):**
- A game's code lives in `lib/game/<game>/` (rules, board, screens, its
  `<game>_module.dart`). Code shared by several games lives in `lib/game/common/`
  (dice, pawn, player strip, setup screen, pause/forfeit/result flow, and the
  playing-card kit used by Poker and Rummy).
- Games never import each other; shared app code never imports a game — it
  asks the active module through `GameArea` / `AppProfile`.
- Each `main_<game>.dart` imports only its own game.

**Add a game:** its config in `lib/configs/games/<game>/`, its code in
`lib/game/<game>/` with a `GameModule` (routes, Quick Play / online routes,
online sides), then list the module in the apps that should ship it.

---

## 12. Tests & quality checks

Run before every commit/build:

```
flutter analyze          # static analysis — must be "No issues found!"
flutter test             # full suite
flutter test test/configs_test.dart      # one file
flutter test --plain-name "Game history" # one test by name
```

Tests can't download Google Fonts, so you'll see font-fetch errors in the
output — expected and harmless (tests filter them).

---

## 13. Build & install

| Build | Command | Output |
|---|---|---|
| Release APK (universal) | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Smaller per-ABI APKs | `flutter build apk --release --split-per-abi` | `app-arm64-v8a-release.apk`, … |
| Debug APK | `flutter build apk --debug` | quick install for testing |
| Play Store bundle | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` |
| Web | `flutter build web` | `build/web/` |
| iOS (needs Xcode) | `flutter build ios --release` | — |

Build a single-game app with `-t`, e.g. `flutter build apk --release -t lib/main_ludo.dart`.

> **Separate store listings (later):** to install the apps side by side they
> also need their own application id, name and icon — add Android
> `productFlavors` / iOS schemes per app (e.g. `--flavor ludo -t
> lib/main_ludo.dart`). Not set up yet; to be done once the app list is final.

Any `--dart-define` from §6 works on builds too, e.g.
`flutter build apk --release --dart-define=USE_PROXY=false`.

Install on a plugged-in device: `adb install -r build/app/outputs/flutter-apk/app-release.apk`
(`adb devices` to list them).

> **Release signing:** before publishing, add `android/key.properties` + a
> keystore and reference it in `android/app/build.gradle`. Debug-signed builds
> install for testing but can't go to the Play Store. Also switch the
> environment to an HTTPS host (`APP_ENV=prod` in `lib/configs/environment.dart`)
> and remove the Android cleartext exception.
