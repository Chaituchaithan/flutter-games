# Services & Realtime Flow

How the app talks to the backend: the **REST API** and the **realtime WebSocket**,
and the exact call sequence for the two flows that matter most — **Login → Home**
and **Online Play**. Grounded in the current code (file paths cited inline).

## The two services

| Service | Class | Transport | Default endpoint | Auth |
|---|---|---|---|---|
| REST API | `ApiClient` (`lib/services/api_client.dart`) | HTTP (Dio) | `http://169.58.184.121:30080/api/v1` | `Authorization: Bearer <jwt>` |
| Realtime | `AppSocket` → `SocketClient` (`lib/services/socket/`) | WebSocket | `ws://169.58.184.121:30080/api/v1/ws` | `auth.login {token, username}` first frame |

Both are overridable at build time:

```
--dart-define=API_BASE_URL=http://host:port/api/v1
--dart-define=CHESS_WS_URL=ws://host:port/api/v1/ws
```

- There is **one** app-wide socket (`appSocketProvider`), opened right after login
  and **reused** everywhere (the Online Play screen attaches to it rather than
  opening a second connection).
- Envelope protocol: every frame is `{ id?, event, data, error? }`. A request
  carries an `id` and gets a correlated reply with the same `id`; broadcasts have
  no `id`. Keepalive is `connection.ping` / `connection.pong` (~20 s).

---

## Flow 1 — Login → Home

Code path: `login_screen._signIn → session.login → RemoteAuthService.login →
_finish`, then `_connectSocketThenHome → appSocket.connect`, then navigate.

### Phase A — REST (ApiClient)
1. **`POST /auth/login`** `{ email, password }` → `access_token` + `refresh_token`
   (and sometimes an embedded user).
2. **Store tokens** — access token set as the Bearer on `ApiClient` **and**
   persisted to secure storage (`tokenStore.save`).
3. **`GET /users/me`** (Bearer) → the authoritative profile: **`username`**,
   level, tier, etc. The username from here becomes the socket identity.
4. Session state = that `User`.

### Phase B — WebSocket (AppSocket)
5. Read the access token back from `tokenStore`.
6. **Open WS** → `GET …/api/v1/ws` (no auth at the upgrade itself).
7. Server pushes **`connection.established`** → `connect()` resolves; keepalive
   ping starts.
8. Client sends **`auth.login`** `{ token, username }` — `username` is the real
   one from `/users/me`.
9. Server replies **`auth.login_success`** → socket status = *authenticated*.

### Phase C — Navigate
10. **Only if the socket authenticated** → `Navigator.pushReplacement` to **Home**
    (strict gating: a WS failure shows a toast and keeps you on login). The
    demo/OAuth path has no token, so it skips Phase B.

**On Home:** no further API or socket calls fire on load — the HUD/profile use the
`User` fetched in step 3. The socket stays open and idle (ping/pong only) until you
open Online Play.

Compact list:

```
POST /auth/login          (REST)
GET  /users/me            (REST)
WS   connect → connection.established   (socket)
WS   auth.login → auth.login_success    (socket)
```

**Variants** (same `_finish` pipeline, so each also calls `/users/me`):
- **Guest:** `POST /guest/create` instead of `/auth/login`.
- **Register:** `POST /auth/register` `{ username, email, password }` →
  **no auto-sign-in** → navigates to Login.
- **Token refresh:** `POST /auth/refresh` `{ refresh_token }`.

---

## Flow 2 — Online Play

Entirely over the one shared WebSocket — **no REST** during a match. Code path:
`ChessOnlineScreen._connect → _matchmake → ChessSession.* → _onBroadcast`.

### 1. Connect
Reuses the authenticated app socket (`attachAuthenticated`); only opens its own and
re-runs `auth.login` if not already connected.

### 2. Matchmaking (by how you entered)

| Mode | Client → (request) | ← Server |
|---|---|---|
| Quick match | `match.find` `{ game_type:"chess", currency, bet_amount }` | `match.searching`, then broadcast `match.found` `{ room_code, seat, color }` |
| Create room | `room.create` `{ currency, bet_amount }` | `room.created` `{ room_code, seat:0, color:"white" }` |
| Join by code | `room.join` `{ room_code }` | `room.joined` `{ room_code, seat:1, color:"black" }` |

→ phase = **inRoom**; your `seat`/`color` are stored.

### 3. Ready-up (automatic)
- Server pushes **`room.user_joined`** `{ room_full:true, countdown_seconds }`.
- Screen auto-sends **`player.ready`**. When both are ready, server pushes
  **`game.started`** `{ state:{ match_id, players[] } }` → phase = **inGame**.

### 4. In-game loop
- **Turn clock:** server pushes **`game.turn_start`**
  `{ color, user_id, time_limit_ms, deadline_ms }` each turn — drives the UI timer.
- **Your move:** **`game.action`** `{ action_type:"move", from, to, promotion? }` →
  reply **`game.action_ack`**.
- **Opponent move:** broadcast **`game.state_update`**
  `{ last_action:{ from, to, algebraic, user_id } }` → mirrored into the engine
  (your own echo ignored via `user_id`).
- **Chat (optional):** `chat.send` `{ message }` ↔ `chat.message`.
- **Draws (optional):** `game.action` `{ action_type:"offer_draw"|"accept_draw"|"decline_draw" }`
  ↔ `game.draw_offered` / `game.draw_declined`.

### 5. Game end
- **Resign:** `game.action` `{ action_type:"resign" }`.
- **Timeout:** server pushes **`game.turn_timeout`** `{ color, user_id }`.
- Either way → broadcast **`game.completed`** `{ result, winner_id }` →
  phase = **completed**, result shown in place on the board.

### Compact event list (quick match, happy path)
```
→ match.find            ← match.searching
                        ← match.found        {room_code, seat, color}
                        ← room.user_joined   {room_full, countdown_seconds}
→ player.ready
                        ← game.started       {state:{match_id, players}}
                        ← game.turn_start    {color, time_limit_ms, ...}
→ game.action (move)    ← game.action_ack
                        ← game.state_update  {last_action}   (opponent move)
                        ← game.turn_start    {color:..., turn:n+1}
   … repeat …
                        ← game.completed     {result, winner_id}
```
`→` client request · `←` server push/response.

---

## Reference

### REST endpoints used
| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/login` | Email + password sign-in |
| POST | `/auth/register` | Create account `{ username, email, password }` |
| POST | `/auth/refresh` | Rotate tokens with the refresh token |
| POST | `/auth/logout` | Invalidate the session |
| POST | `/guest/create` | Anonymous guest session |
| GET  | `/users/me` | Current user profile (username, level, …) |

### Socket events (catalog in `lib/services/socket/socket_events.dart`)
- **Connection:** `connection.established`, `connection.ping`, `connection.pong`, `connection.kicked`
- **Auth:** `auth.login` → `auth.login_success` / `auth.login_error`; `auth.token_refreshed`; `auth.session_expired`
- **Room:** `room.create`/`room.created`, `room.join`/`room.joined`, `room.leave`/`room.left`, `room.user_joined`, `room.full`
- **Match:** `match.find`, `match.searching`, `match.found`, `match.timeout`, `match.cancel`
- **Game:** `player.ready`, `game.started`, `game.turn_start`, `game.action` / `game.action_ack` / `game.action_error`, `game.state_update`, `game.turn_timeout`, `game.completed`
- **Chat:** `chat.send`, `chat.message`

### Key files
- `lib/services/api_client.dart` — REST client, Bearer, base URL.
- `lib/services/auth_service.dart` — `login/register/refresh`; `_finish` fetches `/users/me`.
- `lib/services/session.dart` — `SessionController` (holds `User`, token persistence).
- `lib/services/socket/socket_client.dart` — envelope protocol, request/broadcast, keepalive, reconnect.
- `lib/services/socket/app_socket.dart` — the single shared socket; `auth.login` identity.
- `lib/services/socket/chess_session.dart` — bridges socket events ↔ the chess engine/UI.
- `lib/screens/auth/login_screen.dart` — login → socket → Home (strict gating).
- `lib/screens/games/chess_online_screen.dart` — the Online Play screen.

### Notes / current state
- `game.turn_start` / `game.turn_timeout` are the **server-driven per-move clock**
  (30 s). `socket_client.dart` has a temporary `kLogClockFrames` flag that prints
  `[CLOCK-CAPTURE] <event> :: <raw>` so the live gateway's payload can be confirmed
  against the field names the client reads (`color`, `time_limit_ms`).
- For local two-player testing without the gateway, see
  `tools/chess_relay_server.dart` (implements this same protocol subset, including
  the turn clock).
