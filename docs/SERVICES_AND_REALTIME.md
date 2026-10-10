# Services & Realtime

How the app talks to the backend: the **REST API** and the **realtime
WebSocket**, where their settings live, and the exact call sequence for
sign-in, profile and online play. Grounded in the current code (file paths
cited inline).

Reference documents: *Portal Gateway API* (REST), *Chess API* and
`SOCKET_HOOKS.md` (socket protocol). The most complete endpoint list is the
API Lab catalog (`api-lab/src/endpoints.json`).

---

## 1. Configuration — `lib/configs`

Every host, port, path and `--dart-define` lives here; services never build a
URL themselves. Import `package:snakeladder/configs/configs.dart`.

| What | Where | Value today |
|---|---|---|
| Server host + gateway port | `environment.dart` (`devServer`) | `169.58.184.121:31294` (api-gateway) |
| REST base | `AppConfig.apiBaseUrl` | `…:31294/api/v1` (or the proxy, or `API_BASE_URL`) |
| A game's REST API | `GameEndpoints.apiBase` / `health` / `metrics` | same port as its socket, e.g. `http://…:31283/health` |
| REST paths | `endpoints/api_endpoints.dart` | `/auth/login`, `/users/me`, … |
| A game's socket | `games/<game>/<game>_config.dart` + `GameEndpoints` | own port per game, `/ws` (chess `:31283`) — via proxy `/svc/<port>/ws` |
| Proxy on/off | `proxy_config.dart` (`proxyEnabledByDefault`) | ON |
| Socket on/off | `feature_flags.dart` (`socketEnabledByDefault`) | **ON** |
| Live auth / live data | `feature_flags.dart` providers | auth live; other data static |
| Timeouts, ping, backoff | `network_config.dart` | 15 s / 20 s REST · 8 s socket requests · 20 s ping |

**Resolution order** for every URL: `--dart-define` override → dev proxy (when
ON) → environment default.

| Service | Class | Transport | Auth |
|---|---|---|---|
| REST API | `ApiClient` (`lib/services/api_client.dart`) | HTTP (Dio) | `Authorization: Bearer <jwt>` |
| Realtime | `AppSocket` → `SocketClient` (`lib/services/socket/`) | WebSocket | Bearer at upgrade (native) or `?token=` (via proxy) + `auth.login {token, username}` |

---

## 2. Sign-in → Home

Code path: `login_screen._signIn → session.login → RemoteAuthService.login → _finish`.

1. **`POST /auth/login`** `{ email, password }` → `access_token` (15 min) + `refresh_token` (7 days).
2. Tokens are set on `ApiClient` and saved to secure storage (`TokenStore`).
3. **`GET /users/me`** → account (`id`, `username`, `email`, `role`, `created_at`).
4. **`GET /users/{id}/profile`** → `display_name`, `bio`, `country`, `avatar_*`, … (a missing profile isn't fatal — the username stands in).
5. `User.fromApi(me, profile)` becomes the session user: Home HUD, Profile, everywhere.
6. **Socket step:** open the active game's socket (chess `:31283/ws`), wait for
   `connection.established`, send `auth.login {token, username}`, and enter
   **Home only after `auth.login_success`**. Any failure keeps the player on
   Login with a plain message (details in the `[SOCKET]` log) and closes the
   half-open socket. Log out sends `auth.logout` and closes it.

Variants through the same `_finish`: **guest** (`POST /guest/create`),
**register** (`POST /auth/register` `{ username, email, password }` → then log in),
**refresh** (`POST /auth/refresh`).

### Expired tokens
The access token lasts 15 minutes. On a **401** (any call except auth paths)
`ApiClient` refreshes once via `POST /auth/refresh` and retries the request;
parallel calls share one refresh. Only a 401 that survives the refresh signs
the player out ("Session expired"). A **403** is a permission error — shown as
a message, never a sign-out.

---

## 3. Profile

| Action | Call | Notes |
|---|---|---|
| Open Profile tab / pull to refresh | `GET /users/me` + `GET /users/{id}/profile` | `session.reloadProfile()`. Login already fetched both, so opening the tab within a minute of a fetch skips the call. Pull-to-refresh always fetches. All tabs are built at Home, so there is no fetch until the tab is opened |
| Edit profile → Save | `PATCH /users/me/profile` | Sends only changed fields: `display_name`, `bio`, `country`, `preferred_language` (ISO code, e.g. `en`), `date_of_birth` (`YYYY-MM-DD`, age 13+). The response updates the screen |
| Settings → Change password | `POST /auth/change-password` `{current_password, new_password}` → 204 | Validation: current password required; new password 8–128 characters, mixing letters and numbers, and different from the current one; the confirmation must match. A 401 means the current password is wrong (shown on that field, never a sign-out). On success the server revokes every session, so the app clears it locally and goes to Log in. Hidden for guests |
| Language | `PATCH … {preferred_language}` | At login, if the profile has no language, the first-launch pick is saved. A Settings → Language change is saved too. A saved profile language becomes the app language |

Not wired yet (endpoints exist in the catalog): `PATCH /users/me`
(username/email), `POST /guest/convert` (guest → account),
`GET /matches/my-history`, `GET /progression/{game_id}/stats`.

---

### Daily rewards
| Action | Call | Notes |
|---|---|---|
| Open Daily Rewards | `GET /sensitive/daily-bonus/status` → `{current_streak, can_claim, next_reward{day_number, reward_tokens, reward_gold, power_up_id, power_up_quantity}, last_claimed_at, next_claim_available_at, total_claims}` | Amounts arrive as strings. `next_reward` is today's reward when `can_claim`, otherwise tomorrow's. Days before it show as claimed. Only that one day's amount is known; the others show a gift icon. Loading skeleton while it loads |
| Claim | `POST /sensitive/daily-bonus/claim` → `{tokens_awarded, gold_awarded, power_up_id, power_up_quantity, new_streak, total_claims}` | The toast shows the actual payout. A 409 means it was already claimed. Status and wallet refresh afterwards |

`/sensitive` routes need the bearer token plus the device fingerprint saved at login. Signed out (demo build), a local demo source is used.

---

## 4. Online play (socket)

One shared WebSocket — **no REST during a match**. Code path:
`ChessOnlineScreen._connect → _matchmake → ChessSession.* → _onBroadcast`.
Every game's session implements the shared `GameSession` contract
(`lib/services/game_session.dart`), so matchmaking, rooms, the lobby,
pause/forfeit and results are game-independent.

### Envelope
`{ id?, event, data, error? }` — requests carry an `id` and get a reply with the
same `id`; broadcasts have none. Keepalive `connection.ping` / `connection.pong`.

### Flow (happy path, quick match)
```
WS open                 ← connection.established        (server sends first)
→ auth.login {token, username}
                        ← auth.login_success
→ match.find {game_type, player_count, currency, bet_amount, seat}
                        ← match.searching / match.found {room_code, seat, color}
                        ← room.user_joined {room_full, countdown_seconds}   (opponent in)
→ player.ready
                        ← game.started {state:{match_id, players}}
                        ← game.turn_start {color, time_limit_ms, …}
→ game.action {action_type:"move", from, to, promotion?}
                        ← game.action_ack
                        ← game.state_update {last_action}     (opponent move)
   … repeat …
                        ← game.completed {result, winner_id}
                        ← game.wallet_update {winner_id, payout, rake}   (wagered)
```
**Quick match (Online Play sheet):** the player picks currency (`token` /
`gold`), side and stake. The side goes out as `seat`: **0 = White, 1 = Black**
(`ChessSeats`). Example:
`{"game_type":"chess","player_count":2,"currency":"token","bet_amount":100,"seat":1}`.
The matchmaking screen then searches for up to **60 s**
(`ChessOnlineScreen.searchTimeout`). When an opponent joins (`room_full` or
`game.started`) it reveals them and the board opens. Otherwise, at 60 s or on
the server's `match.timeout`, it sends `match.cancel`, shows a "No match
found" toast and returns Home. Cancel search also sends `match.cancel`.
The 60 s clock starts once the socket is connected and the search is queued.
After the reveal, a **Leave match** button sends `room.leave`. If the game
hasn't started 20 s after the reveal, the app also sends `room.leave`, shows
"The match didn't start" and returns Home.

Rooms: `room.create {currency, bet_amount}` → `room.created {room_code}`;
`room.join {room_code}` → `room.joined`. The creator gets seat 0 (White) and the joiner seat 1 (Black).
Cancel, or backing out of a room that hasn't started, sends `room.leave`.
`room.create_error` / `room.join_error` (`not_found`, `full`,
`already_in_room`, `insufficient_balance`) show a plain message. A joiner takes
the stake from `bet_amount`/`currency` in `room.joined` or `game.started` when
the server sends them. Draws: `offer_draw` / `accept_draw` /
`decline_draw`. Forfeit: `resign`. Chat: `chat.send` ↔ `chat.message`.

### Status
Each game service has its own socket on `169.58.184.121`, path `/ws`: 31281
bingo · 31282 checkers · **31283 chess** · 31284 crash · 31285 ludo · 31286
othello · 31287 poker · 31288 racing · 31289 roulette · 31290 rummy · 31291
scrabble · 31292 snakes & ladders. All verified (health ok, WebSocket accepted,
`connection.established` received). The socket is **ON** in the app; `auth.login`
uses the gateway token (a username alone is refused outside debug mode).

---

## 5. Switching games

Each app ships the game modules listed in its `AppProfile` (see
docs/RUN_AND_TEST.md §11 "Apps"). The active game (`activeGameProvider`)
is one of them. It decides the socket port and path (from its config), which
screens open (`GameArea`, answered by the module), and which session runs. In
the all-games build, switch it with the Home game chips or
`--dart-define=GAME=<id>`. A single-game app has no picker.

Ludo and Snakes & Ladders are Quick Play only (local rules + computer
players in `lib/game/ludo`, `lib/game/snakes`). Online Play / Friends for
them shows "coming soon", and login keeps signing in to the **chess** socket
while one of them is active (`GameArea.socketGame`).

---

## 6. Key files

| File | Role |
|---|---|
| `lib/configs/` | All configuration (above) |
| `lib/services/api_client.dart` | REST client: Bearer, error mapping, 401 refresh-and-retry |
| `lib/services/auth_service.dart` | Login / register / guest / refresh, `fetchMe`, `updateProfile` |
| `lib/services/session.dart` | `SessionController`: the signed-in `User`, tokens, reload/update profile |
| `lib/services/socket/socket_client.dart` | Envelope protocol, request/reply, keepalive, reconnect |
| `lib/services/socket/app_socket.dart` | The shared app socket and its `auth.login` identity |
| `lib/services/socket/chess_session.dart` | Chess `GameSession`: socket events ↔ chess engine/UI |
| `lib/services/game_session.dart` | The per-game session contract |
| `lib/app/game_area.dart` | GameId → practice / online screens |
| `tools/cors_proxy.dart` | Dev proxy (CORS + WS, logs frames, masks tokens) |
| `tools/chess_flow_test.dart` | End-to-end chess check with two real accounts (free game) |
