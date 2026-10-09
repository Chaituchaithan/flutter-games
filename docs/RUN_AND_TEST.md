# How to Run & Test

How to run the Chess app on **Web (Chrome)** and the **Android emulator**, with
or without the dev proxy, and how to debug the realtime socket.

_Last updated: 2026-10-09_

---

## 1. Overview

The app talks to one server, `169.58.184.121:30080`, in two ways:

- **REST API** — login, profile, data (`/api/v1/...`). ✅ Working.
- **WebSocket** — live chess (match, moves, chat). ❌ Not working yet: the
  server returns **404** for the socket path (see §9).

You can run the app in two modes, chosen by one switch:

| Mode | API goes to | Socket goes to | Use it for |
|---|---|---|---|
| **Proxy ON** (current default) | `http://localhost:8899/api/v1` → proxy → server | `ws://localhost:8899/api/v1/ws` → proxy → server | Web (Chrome); emulator when you want proxy logs |
| **Proxy OFF** (original) | `http://169.58.184.121:30080/api/v1` directly | `ws://169.58.184.121:30080/api/v1/ws` directly | Android emulator / real phone |

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

- **Flutter** installed (`flutter doctor` clean for Chrome and Android).
- **Android emulators**: `Samsung_Galaxy_S23`, `Moto_G_5G`.
  List with `flutter emulators`; see running devices with `flutter devices`.
- **A test account** on the server. Log in with the account's **email**
  (the server rejects a bare username) and its password.
- **Android plain-HTTP access** to `169.58.184.121` is already allowed in
  `android/app/src/main/res/xml/network_security_config.xml` — nothing to set up.

---

## 3. Proxy switch (ON / OFF)

One setting decides the mode — `_proxyEnabled` in `lib/services/dev_proxy.dart`.
It is currently **`true` (proxy ON)**.

```dart
/// MASTER SWITCH: true = proxy testing, false = direct (original) HTTP/WS.
const bool _proxyEnabled = true;
```

Three ways to choose the mode:

1. **Change the default** — set `_proxyEnabled` to `true` / `false`
   (or ask Claude: "turn on proxy" / "turn off proxy").
2. **Override for one run, no code change** — add
   `--dart-define=USE_PROXY=true` or `--dart-define=USE_PROXY=false`.
3. **Force exact URLs** — `--dart-define=API_BASE_URL=…` and
   `--dart-define=CHESS_WS_URL=…` win over both of the above.

When the proxy is ON the app picks the proxy address automatically:
`localhost:8899` on Chrome/iOS, `10.0.2.2:8899` on the Android emulator
(the emulator's name for your Mac).

### Socket switch (bypass)

While the chess socket URL is unknown, the socket is **bypassed** —
`_socketEnabled = false` in `lib/services/socket/app_socket.dart`:

- Login → Home with the API only (no socket connection).
- Online Play / Play With Friends open the **offline practice board** instead
  of matchmaking.

Turn it back on with `_socketEnabled = true`, or for one run with
`--dart-define=SOCKET_ENABLED=true` (or ask Claude: "turn on socket").
The `[SOCKET]` logs in §7 only appear when the socket is ON.

---

## 4. Run on Web (Chrome) — proxy ON

Web **only works with the proxy**.

1. Terminal 1 — start the proxy (leave it running):
   ```
   dart run tools/cors_proxy.dart
   ```
   You should see: `CORS proxy: http://localhost:8899  ->  http://169.58.184.121:30080`
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

(Or set `_proxyEnabled = false` and just run `flutter run -d emulator-5554`.)

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
| `API_BASE_URL` | Exact REST base URL (wins over proxy switch) | `--dart-define=API_BASE_URL=http://169.58.184.121:30080/api/v1` |
| `CHESS_WS_URL` | Exact socket URL (wins over proxy switch) | `--dart-define=CHESS_WS_URL=ws://169.58.184.121:30080/<path>` |
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
[SOCKET] opening WS → ws://169.58.184.121:30080/<path>
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
[proxy] ws open  /api/v1/ws  <->  ws://169.58.184.121:30080/...                 socket connected
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

## 8. Socket diagnostics — `tools/ws_probe.dart`

Tries many socket paths on the server with your token and reports what each
returns. On a **101** it also runs `connection.established → auth.login` and
prints the reply.

Run it in **your own terminal** (so the password isn't shared anywhere):

```
TOKEN=$(curl -s -X POST http://169.58.184.121:30080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"<your email>","password":"<your password>"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
dart run tools/ws_probe.dart "$TOKEN"
```

The token lasts **15 minutes** — run the probe right after getting it.

How to read it:

| Result | Meaning |
|---|---|
| `101` | ✅ That path is the socket — use it in `CHESS_WS_URL` |
| `404` | Nothing at that path |
| `401 ... missing authorization header` | Token sent the wrong way (the gateway only accepts the header, not `?token=`) |

---

## 9. Current socket status & what to ask the server team

**Status (2026-10-09):**

- API login on `:30080` works.
- Socket on `ws://169.58.184.121:30080/api/v1/ws` returns **404** even with a
  valid token. Also 404: `/ws`, `/api/v1/chess/ws`, `/api/v1/games/chess/ws`,
  `/api/v1/realtime`, `/api/v1/socket`, `/chess/ws`.
- Port `3112` (the chess service port in Chess API.pdf, written as
  `ws://localhost:3112/ws`) is not reachable from outside.
- Other games' socket services are reachable directly and do send
  `connection.established`: 30081 bingo, 30082 checkers, 30083 ludo,
  30084 othello, 30085 poker, 30086 snake-and-ladder. Chess has none.
- None of the three documents (Portal Gateway API, Chess API, SOCKET_HOOKS.md)
  give the deployed socket URL.

**Message to send the server team:**

> Login API works on port 30080. But opening the chess WebSocket on 30080
> returns **404** for both `/ws` and `/api/v1/ws` (we send the token as
> `Authorization: Bearer <token>`). Please share the **full WebSocket URL for
> chess**, e.g. `ws://169.58.184.121:30080/????`.

Once you have it, test immediately with:
```
flutter run -d emulator-5554 --dart-define=USE_PROXY=false \
  --dart-define=CHESS_WS_URL=ws://169.58.184.121:<port>/<path>
```

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
