# Flutter hand-off 0: conventions

The rules every other hand-off file assumes: servers, headers, errors, limits, lists, money,
times, and the WebSocket envelope that every game socket shares. Build the pieces here once
(an API client, an error type, a socket client) and reuse them for every screen and game.

Checked against the running gateway and the Ludo service on 24 Nov 2026.

---

## For the Claude agent: what to build

1. An `AppConfig` with one setting, the **server host** (IP or name), from which every URL
   is built (see "Servers"). A debug-only settings screen to change it.
2. One `ApiClient` (`dio`) for the gateway, with the auth interceptor from `01-auth.md`, the
   headers below, and every error turned into one `ApiError` type.
3. One `GameSocket` class for game servers: connect, send a request and wait for the reply
   with the same `id`, a stream of everything else, heartbeat, and reconnect (see "Game
   sockets"). Each game's hand-off file adds only its own events.
4. Parsers that accept **both** a number and a numeric string for money (see "Money").
5. Tests: `ApiError` parsing for each body shape below; `GameSocket` request/reply matching,
   an error reply, a broadcast with no `id`, and reconnect after a drop.

---

## Servers

| What | URL | Port |
|---|---|---|
| api-gateway (HTTP) | `http://<host>:1280/api/v1` | 1280 |
| Ludo game server (WebSocket) | `ws://<host>:1285/ws` | 1285 |
| Other games | `ws://<host>:<port>/ws` | Each game's hand-off file gives its port. |

- The gateway does **not** tell the app where a game server is. Build the socket URL from the
  same host plus the game's port, kept in the app's config per game code.
- Local development: `<host>` is the developer machine's Wi-Fi IP, for example
  `192.168.0.235`. The phone must be on the same Wi-Fi. An Android emulator uses `10.0.2.2`.
- Development is plain `http` and `ws`. Allow cleartext in debug builds only (Android
  `usesCleartextTraffic`, iOS `NSAppTransportSecurity` exception). Production will be `https`
  and `wss`.
- Flutter **web** builds: the browser sends an `Origin` header, and the gateway and the game
  servers accept only listed origins. Ask the server owner to add the web app's origin. Mobile
  builds send no `Origin` and need nothing.

---

## HTTP requests

| Header | Value |
|---|---|
| `Content-Type` | `application/json` on every request with a body. |
| `Authorization` | `Bearer <access_token>` on every route except the public ones in `01-auth.md`. |
| `User-Agent` | A stable value per install, for example `RoyaleArcade/1.0.0 (Android 14)`. Keep it the same for the whole session (see below). |
| `Idempotency-Key` | Purchase routes only: a new UUID per purchase attempt, reused on a retry of the same attempt. |

**Device check on `/sensitive/...` routes.** Routes under `/sensitive/` (daily bonus, quests,
shop) compare the `User-Agent` and the network (the IP's /24 block) with the ones used at
login. A change answers `401 FINGERPRINT_MISMATCH`. This happens when the phone moves from
Wi-Fi to mobile data. Handle it like an ended session: log in again. Development servers skip
this check.

**Bodies and parameters**

- JSON everywhere. Field names are `snake_case`.
- Ids: players, matches, rooms and most records are UUID strings. Catalogue rows (games,
  modes, variants, stakes) use **numeric** ids: `GET /games/1`, not `GET /games/ludo`. Get
  the id from `GET /games` by `code`.
- Leave optional fields out rather than sending `null`, unless a file says `null` clears a
  value.
- Parse replies leniently: ignore unknown fields. New fields are added without notice.

---

## Errors (HTTP)

Every error has the same body:

```json
{
  "error": "MACHINE_CODE",
  "message": "developer text, not for users",
  "field": "VALIDATION_ERROR only: the first bad field",
  "until": "ACCOUNT_BANNED only, for a timed ban (ISO 8601 UTC)"
}
```

- Decide on the status and `error`, never on `message`. Map them to your own translated text.
- The same code can mean different things on different routes; each hand-off file lists what
  its routes return.

| Status | `error` | Meaning |
|---|---|---|
| 400 | `VALIDATION_ERROR` | A field breaks a rule; `field` names it. |
| 400 | `BAD_REQUEST` | Bad JSON, a missing field, an unknown enum value, a path or query value that doesn't parse, or a rule the request breaks. |
| 401 | `UNAUTHORIZED` | No token, a bad token, or an **expired** access token. The interceptor refreshes once (see `01-auth.md`). |
| 401 | `TOKEN_EXPIRED` | The refresh token is too old. Log in again. |
| 401 | `TOKEN_BLACKLISTED` | The session ended (logout, password change or reset). Log in again; don't refresh. |
| 401 | `SESSION_NOT_FOUND` | The session is gone. Log in again. |
| 401 | `FINGERPRINT_MISMATCH` | See the device check above. Log in again. |
| 401 | `INVALID_CREDENTIALS` | A wrong password or code. Not a session problem. |
| 403 | `FORBIDDEN` | Not allowed for this account. |
| 403 | `ACCOUNT_BANNED` | Suspended or banned; `until` for a timed ban. |
| 403 | `GEO_BLOCKED` | Not offered in the player's region. |
| 404 | `NOT_FOUND`, `MATCH_NOT_FOUND`, `GAME_NOT_FOUND` | No such record, or no such route. |
| 409 | `CONFLICT` | Already exists, or the record changed. |
| 409 | `INSUFFICIENT_FUNDS` | The wallet can't cover it. |
| 409 | `DUPLICATE_TRANSACTION` | The same transaction was already done. |
| 409 | `USER_BLOCKED`, `DUPLICATE_FRIEND_REQUEST` | Social rules. |
| 409 | `ALREADY_IN_QUEUE`, `TOURNAMENT_FULL` | Matchmaking and tournament rules. |
| 429 | `RATE_LIMITED` | Too many requests (see "Limits"). |
| 429 | `GIFT_QUOTA_EXCEEDED` | The daily gift limit is used up. |
| 503 | `UNAVAILABLE` | A feature isn't switched on, or a dependency is down. |
| 503 | `KILL_SWITCH_ENGAGED` | An operator paused this feature; `message` is their text and may be shown. |
| 503 | `DATABASE_BUSY` | Busy for a moment; the reply has `Retry-After: 1`. Retry once after a second. |
| 503 | `CIRCUIT_OPEN` | A dependency is failing; try later. |
| 500 | `INTERNAL_ERROR`, `DATABASE_ERROR`, `CACHE_ERROR` | A server fault. "Something went wrong. Try again." |

Real replies:

```json
// 404, a path no route matches
{"error": "NOT_FOUND", "message": "not found: no route for GET /api/v1/nope"}

// 400, a game code where the numeric id goes
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: can not parse to a i64"}

// 401, no token
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}
```

No network or a timeout: "Can't reach the server. Check your connection." Offer Retry. Use a
15-second timeout for HTTP calls.

Suggested Dart shape (also used by `01-auth.md`):

```dart
class ApiError implements Exception {
  final int status;       // HTTP status, 0 for no network
  final String code;      // "error" field, e.g. "INSUFFICIENT_FUNDS"
  final String? field;    // VALIDATION_ERROR only
  final DateTime? until;  // ACCOUNT_BANNED only
}
```

---

## Limits

| What | Limit | Over it |
|---|---|---|
| All signed-in gateway routes | About 100 requests a minute per player. | `429 RATE_LIMITED`. Wait and retry. |
| Sign-in routes (login, sign up, refresh, guest, forgot password) | 5 a minute per network address in production. | `429 RATE_LIMITED`. Don't retry automatically. |
| Email codes | See `01-auth.md`. | |
| Socket frames | 30 a second per socket. | `connection.error` `rate_limited`; the frame is dropped. |

- **Never poll** a route faster than once every 10 seconds. Prefer socket updates for live
  data.
- Never retry automatically in a tight loop. One retry after a short wait is the most for any
  call; after that, show the error.

---

## Lists

Three shapes are in use; each route's file says which.

```json
// 1. Plain array (for example GET /games)
[{"id": 1, "code": "ludo", "...": "..."}]

// 2. Page list: query ?page=1&per_page=20 (per_page 1-100)
{"data": [], "total": 0, "page": 1, "per_page": 20, "total_pages": 0}

// 3. Item list with a cursor (for example GET /wallet/ledger)
{"items": [], "page": 1, "pages": 1, "total": 0, "next_cursor": null}
```

For shape 3, the page size is `per` (not `per_page`). Load more by passing `next_cursor` back
as `?after=<next_cursor>` until it is `null`.

---

## Money

- Two currencies: **`token`** and **`gold`**. Amounts are whole numbers; there are no
  fractions.
- The gateway sends some amounts as **numeric strings** and others as numbers. Game sockets
  send numbers. Parse both everywhere:

```json
// GET /wallet/balance (strings)
{"user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "balance_tokens": "0", "balance_gold": "0", "updated_at": "2026-11-24T08:04:07.372032Z"}

// Ludo room.created players[] (numbers)
{"balance_tokens": 100, "balance_gold": 500}
```

- Never compute a payout or a balance on the device. Show what the server sends, and
  re-read the wallet after a game ends.

---

## Times

| Where | Format | Example |
|---|---|---|
| HTTP replies | ISO 8601, UTC | `"2026-11-24T08:04:07.372032Z"` |
| Socket frames (`timestamp`, `turn_deadline`, `match_deadline`) | Epoch **milliseconds**, server clock | `1795507748111` |
| Socket `expires_at` (token expiry) | Epoch **seconds** | `1795508609` |
| HTTP `expires_in` | Seconds from now | `900` |

- Show times in the device's local time zone.
- **Countdowns:** the phone's clock can be wrong. When a socket opens, `connection.established`
  carries the server's `timestamp`: store `offset = serverTimestamp - deviceNow` and draw
  timers from `deadline - (deviceNow + offset)`.

---

## Game sockets

Every game server speaks the same envelope and lifecycle. Each game's hand-off file adds
only its own events.

### The envelope

Every frame, both ways, is one JSON object:

```json
{ "id": "a-17", "event": "domain.action", "data": { }, "error": { "code": "...", "message": "..." } }
```

| Field | Meaning |
|---|---|
| `id` | Optional on sends. Put a unique string on every request; its reply carries the same `id`. Frames the server pushes or broadcasts have no `id`. |
| `event` | `domain.action`, for example `auth.login`, `room.create`, `game.action`. |
| `data` | The payload; leave it out when there is none. |
| `error` | Only on error replies: `{code, message}`. Codes are `snake_case` (`invalid_state`, `not_found`). |

Real frames:

```json
// the app sends
{"id": "A-3", "event": "connection.ping"}
// the reply, same id
{"id": "A-3", "event": "connection.pong", "data": {}}
// an error reply, same id
{"id": "A-4", "event": "connection.error", "error": {"code": "unknown_event", "message": "unknown event 'room.dance'"}}
// a room broadcast, no id
{"event": "chat.message", "data": {"from_user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "message": "Good game!", "timestamp": 1795507713054, "username": "fdoc7419"}}
```

**Matching replies:** keep a map of pending `id`s. A frame with a known `id` completes that
request (success or `error`). Everything else goes to the event stream. Some sends have no
reply of their own (for example a chat line arrives as the room broadcast); each game file
says which.

**Error event names:** a refused request answers with its own error event, named in each
game file (for example `room.create` gets `room.create_error`). A frame sent in the wrong
state answers `<domain>.error` (for example `game.error`). A frame the server can't read at
all answers `connection.error`. All of them carry `error.code` and the request's `id`.

### Lifecycle

1. Open `ws://<host>:<port>/ws`. Don't put the token in the URL.
2. Wait for `connection.established` (store the clock offset from its `timestamp`).
3. Send `auth.login` with `{"token": "<access_token>"}`. Until `auth.login_success`, only
   `auth.login` and `connection.ping` are accepted.
4. Play (each game's file).
5. Before the access token expires (`expires_at` in `auth.login_success`), refresh it at the
   gateway and send `auth.refresh` with the new token. The socket keeps its room and game.
   A token that expires on an open socket gets `auth.session_expired`, then the socket closes.

The socket moves through four states, and each event is accepted only in some of them:
`Unauthenticated` (just opened), `Authenticated` (signed in, no room), `InRoom` (seated,
waiting or after a game) and `InGame`.

### Staying connected

- The server sends WebSocket ping frames every 5 seconds and closes a socket that sends
  nothing for 10 seconds. Dart's `WebSocket` answers pings itself; also set
  `pingInterval` (for example 5 seconds) so a dead network is noticed quickly.
- **One socket per player per game server.** A second signed-in socket for the same player is
  refused (`auth.login_error` `duplicate`). Close the old socket before opening a new one.
- **Reconnect:** when the socket drops mid-game, the player has **30 seconds** to come back.
  Reconnect with a short backoff (0.5 s, 1 s, 2 s, then every 3 s), send `auth.login` again,
  and the server puts the player back in the game and sends the full state. After 30 seconds
  the player is out of the game (a forfeit). Show "Reconnecting..." with a countdown.
- When the app goes to the background mid-game, keep the socket if the platform allows it;
  otherwise reconnect on resume within the 30 seconds.
- `connection.kicked` (`slow_consumer`) means the app read too slowly: reconnect.

### Kill switches

An operator can pause new games. Requests that start something (create, join, find, ready,
rematch) are then refused with code `kill_switch_engaged` and the operator's message. Show
the message and disable the play buttons; games already running carry on.

---

## Environments

| | Development | Production |
|---|---|---|
| Transport | `http` / `ws`, LAN IP | `https` / `wss` |
| Sign-in rate limit | Raised for testing | 5 a minute per network |
| Email | Not connected; `debug_code` in some replies, other codes in the server log | Real email |
| Device check on `/sensitive/` | Off | On |

Never rely on development-only behaviour (`debug_code`, the debug `username` socket login);
production removes it.

---

## Security

- Tokens only in secure storage; never in logs, crash reports or analytics.
- Never log request or reply bodies of auth, wallet or purchase calls, even in debug builds.
- Don't show `message` texts to users; they are developer text.
