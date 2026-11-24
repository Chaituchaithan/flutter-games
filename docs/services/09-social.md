# Flutter hand-off 9: social

Friends, presence (who is online), chat, gifts, referrals and blocks.

This file is the contract between the Flutter app and the **api-gateway** social routes. It is
written so a Claude agent can implement it directly. Read `00-conventions.md` first: the error
body, list shapes, money parsing and times are defined there and not repeated here. Sessions
and the auth interceptor come from `01-auth.md`. Gifts move money, so read `03-wallet.md` too.

**Where the samples come from.** Every reply marked "real" was captured from the running
gateway on 24 Nov 2026 with three fresh test players (A, B and C; C signed up with A's
referral code). Replies marked "from the code" were not captured; their shape is read from the
gateway source.

**Read this first: what the backend does not have.** Several things a social screen usually
needs are missing today. The app must not invent them; build the screens around what exists
and hide the rest (see "Known issues"):

| Wanted | State today |
|---|---|
| Search players by name | **No player route.** Add friends from places that already show a user id: a game room, a match result, a leaderboard, a gift or a chat line. |
| Cancel my sent friend request | **No route.** A sent request stays pending until the other player answers or one side blocks. |
| List my sent (outgoing) requests | **No route.** Only incoming requests are listed. |
| Direct messages (one player to one player) | **None.** Chat is room-based (`lobby`, `global`, `match`). The privacy field `dm_from` is stored but unused. |
| Real-time chat or presence | **No socket or push on the gateway.** Chat and presence are HTTP only. Poll gently (see each section). |
| "In game" and "last seen" for a friend | **Not readable.** Presence answers only "online now" (a heartbeat in the last 120 seconds). |
| Gift an item (avatar, power-up) | **Not supported.** A gift is always tokens or gold; `item_type` / `item_id` are labels only. |
| "Who I referred" list and a share link | **No route.** Only counts (`/referrals/stats`) and the code. Build the share link on the device. |

---

## For the Claude agent: what to build

1. A `SocialApi` on the shared `ApiClient` with one method per route below.
2. Models: `FriendRequest`, `Friend`, `FriendsOnline` (+ `UserCard`), `ChatMessage`, `Gift`,
   `ReferralCode`, `ReferralStats`, `BlockedUser`, and the page list shape 2 wrapper
   (`{data, total, page, per_page, total_pages}`, `00-conventions.md`).
3. A `PlayerNameCache` (user id -> display name and avatar). The friend list and the request
   list return **ids only**; fill names from `GET /users/{id}/profile` (`02-profile-and-sessions.md`)
   or from cards you already have (`/presence/friends-online`, `/blocks`). Cache per session.
4. A `PresenceService` that sends `POST /presence/heartbeat` every **60 seconds** while the app
   is in the foreground (with `game_id` while in a game) and stops in the background.
5. A `BlockList` held in memory (from `GET /blocks`) that the app uses to **hide** blocked
   players everywhere: chat lines, gift sheets, friend suggestions, room seats. The server
   enforces blocks only on friend requests (see section 6).
6. Screens:
   - **Friends**: tabs "Friends" (online first, then the rest), "Requests" (incoming), and an
     "Add friend" action on other players' cards across the app.
   - **Friend card / player sheet**: Add friend, Remove friend, Send gift, Block / Unblock.
   - **Lobby chat** (optional): a room's message list with polling and "load older".
   - **Gifts**: Send gift sheet, and "Received" / "Sent" history.
   - **Invite friends**: my code, Copy, Share (system share sheet), and the counts.
   - **Blocked players** in settings, with Unblock.
   - **Sign up**: a "Referral code" field (`01-auth.md`), and a deep link that pre-fills it.
7. Tests: model parsing for each real reply here; the error mapping for each route; that a
   gift retry reuses its `Idempotency-Key`; that the heartbeat stops in the background; that
   blocked players are hidden in chat and in the gift sheet.

Never log gift request or reply bodies, even in debug builds (they move money).

---

## Endpoints at a glance

All paths are under `http://<host>:1280/api/v1`. All need `Authorization: Bearer
<access_token>`; without it every route answers `401 UNAUTHORIZED` (real). None of these
routes is under `/sensitive/`; only `POST /gifts/send` has the device check.

| Area | Method and path | Success |
|---|---|---|
| Friends | `POST /friends/request` | `201` + request |
| | `GET /friends/requests/pending` | `200` + page list (incoming only) |
| | `POST /friends/request/{id}/accept` | `200` `{"status":"accepted"}` |
| | `POST /friends/request/{id}/reject` | `200` `{"status":"rejected"}` |
| | `GET /friends` | `200` + page list (ids only) |
| | `DELETE /friends/{user_id}` | `200` `{"status":"removed"}` |
| Presence | `POST /presence/heartbeat` | `200` `{"status":"ok"}` |
| | `GET /presence/friends-online` | `200` + ids and cards |
| | `GET /presence/online-count` | `200` `{"global_count": n}` |
| Chat | `POST /chat/{room_type}/{room_id}/send` | `201` + message |
| | `GET /chat/{room_type}/{room_id}/history` | `200` + plain array, newest first |
| Gifts | `POST /gifts/send` (device check) | `201` + gift |
| | `GET /gifts/received` | `200` + page list |
| | `GET /gifts/sent` | `200` + page list |
| Referrals | `GET /referrals/my-code` | `200` + code |
| | `GET /referrals/stats` | `200` + counts |
| | `POST /referrals/apply` | `204` no body |
| Blocks | `POST /blocks/{user_id}` | `201` `{"status":"blocked"}` |
| | `DELETE /blocks/{user_id}` | `200` `{"status":"unblocked"}` |
| | `GET /blocks` | `200` + page list (with names) |

Related routes in other files: `PATCH /users/me/privacy` (`allow_friend_requests`, `dm_from`)
and `GET /users/{id}/profile` are in `02-profile-and-sessions.md`; `POST /wallet/transfer`
is in `03-wallet.md`; notification preferences (`friend_requests`, `gift_received`) are in
`10-inbox-and-notifications.md`. Admin routes exist (`/admin/...`); the app never calls them.

**Page lists** in this file are shape 2 from `00-conventions.md`: query `?page=1&per_page=20`
(`per_page` 1 to 100, default 20), reply `{data, total, page, per_page, total_pages}`. A
`per_page` outside 1-100 is real:

```json
{"error": "VALIDATION_ERROR", "field": "per_page", "message": "validation error: per_page: must be between 1 and 100"}
```

---

## 1. Friends

A friendship is made in two steps: one player sends a request, the other accepts it. Ids:
players are UUIDs; a friend **request** id is a **number** (`"id": 1`).

### 1a. Send a friend request

`POST /friends/request`

```json
{"to_user_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303"}
```

**Success:** `201`. Real (A to B):

```json
{
  "id": 1,
  "from_user_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
  "to_user_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303",
  "status": "pending",
  "created_at": "2026-11-24T09:44:42.021757Z",
  "responded_at": null
}
```

| Field | Meaning |
|---|---|
| `id` | The request id (a number). Used to accept or reject. |
| `from_user_id`, `to_user_id` | Sender and addressee. |
| `status` | `pending`, `accepted`, `declined` or `cancelled`. Lists show only `pending`. |
| `created_at` | When it was sent. |
| `responded_at` | When it was answered; `null` while pending. |

What the app does: change the button on that player's card to "Request sent" (disabled) and
remember it locally for this session. There is no route to read sent requests back, so after
a restart the button shows "Add friend" again; a second tap then answers
`409 DUPLICATE_FRIEND_REQUEST`, which the app shows as "Request already sent".

**Errors** (all real)

| Status | `error` | When | Show |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | Sending to yourself. | Never offer it (hide the button on your own card). |
| 400 | `BAD_REQUEST` | `to_user_id` missing or not a UUID. | App bug. |
| 403 | `FORBIDDEN` | The player turned friend requests off (privacy `allow_friend_requests: false`). | "This player isn't accepting friend requests." |
| 404 | `NOT_FOUND` | No such player, or a deleted account. | "Player not found." |
| 409 | `USER_BLOCKED` | Either player has blocked the other. | "You can't add this player." Don't say who blocked whom. |
| 409 | `CONFLICT` | Already friends. | Switch the button to "Friends". |
| 409 | `DUPLICATE_FRIEND_REQUEST` | A pending request already exists **in either direction** (also when the other player already sent you one). | "Request already sent". If you have an incoming request from them, offer Accept instead (see below). |

```json
{"error": "VALIDATION_ERROR", "message": "validation error: cannot send friend request to self"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: UUID parsing failed: invalid length: found 3 at line 1 column 20"}
{"error": "FORBIDDEN", "message": "forbidden: this player does not accept friend requests"}
{"error": "NOT_FOUND", "message": "not found: player not found"}
{"error": "USER_BLOCKED", "message": "user is blocked"}
{"error": "CONFLICT", "message": "conflict: already friends"}
{"error": "DUPLICATE_FRIEND_REQUEST", "message": "duplicate friend request"}
```

Real order of checks (the first that fails answers): self, player exists, accepts requests,
block, already friends, pending request. So a blocked player sees `USER_BLOCKED` even if they
were friends before.

**Mutual requests:** when B taps "Add friend" on A while A's request to B is pending, B gets
`DUPLICATE_FRIEND_REQUEST` (real). Before sending, check the incoming list
(`GET /friends/requests/pending`): if that player is in it, show "Accept" instead of "Add".

### 1b. Incoming requests

`GET /friends/requests/pending?page=1&per_page=20`

Only requests **sent to** the signed-in player, newest first. Real (B):

```json
{
  "data": [
    {"id": 1, "from_user_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
     "to_user_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303", "status": "pending",
     "created_at": "2026-11-24T09:44:42.021757Z", "responded_at": null}
  ],
  "total": 1, "page": 1, "per_page": 20, "total_pages": 1
}
```

The sender (A) reading the same route gets an empty list (real): sent requests are not shown.

```json
{"data": [], "total": 0, "page": 1, "per_page": 20, "total_pages": 0}
```

What the app does: show each row with the sender's name and avatar (`PlayerNameCache`, by
`from_user_id`) and two buttons, Accept and Decline. Show `total` as a badge on the Requests
tab. Re-read on opening the Friends screen and on app resume; there is no push (no
notification is created for a friend request today, from the code).

### 1c. Accept or decline

`POST /friends/request/{id}/accept` and `POST /friends/request/{id}/reject`. No body. `{id}`
is the request's number.

Real replies:

```json
{"status": "accepted"}
{"status": "rejected"}
```

- Accept makes the friendship at once; both players see each other in `GET /friends`.
- Decline stores the request as `declined`. The sender is not told. The sender may send a new
  request later (real: A sent C a second request after C declined the first).
- Only the addressee may answer.

**Errors** (all real)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `{id}` is not a number. | App bug. |
| 403 | `FORBIDDEN` | The caller sent the request (not the addressee). | App bug; never show these buttons on a sent request. |
| 404 | `NOT_FOUND` | No such request, or it is no longer pending (already answered, or cancelled by a block). | Remove the row and reload the list. |

```json
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: can not parse to a i64"}
{"error": "FORBIDDEN", "message": "forbidden: only the recipient can accept a friend request"}
{"error": "FORBIDDEN", "message": "forbidden: only the recipient can reject a friend request"}
{"error": "NOT_FOUND", "message": "not found: friend request not found"}
```

### 1d. Friend list

`GET /friends?page=1&per_page=20`

Newest friendship first. **Ids only**, no names. Real (A, after B accepted):

```json
{
  "data": [{"user_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303", "created_at": "2026-11-24T09:44:48.829078Z"}],
  "total": 1, "page": 1, "per_page": 20, "total_pages": 1
}
```

| Field | Meaning |
|---|---|
| `user_id` | The friend (always the other player). |
| `created_at` | When they became friends. |

What the app does:

- Load all pages (`per_page=100`) into memory; friend lists are small.
- Names and avatars: use the cards from `GET /presence/friends-online` for online friends, and
  `GET /users/{id}/profile` (`display_name`, `avatar_url`) for the rest, through the
  `PlayerNameCache`. Fetch names lazily as rows scroll into view, a few at a time, to stay
  well under the rate limit (about 100 requests a minute).
- Sort: online first (section 2), then by name.

Real profile reply used for the name (A reading B):

```json
{"user_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303", "display_name": "w09docb1795513466",
 "avatar_id": null, "avatar_url": null, "bio": null, "country": null, "date_of_birth": null,
 "preferred_language": null, "updated_at": "2026-11-24T09:44:28.164835Z"}
```

### 1e. Remove a friend

`DELETE /friends/{user_id}`. No body. Either side may remove. The other player is not told.

Real:

```json
{"status": "removed"}
```

Errors (real): `404 NOT_FOUND` `"not found: friendship not found"` when not friends (also on
a second tap). Treat a 404 as done. `400 BAD_REQUEST` if `{user_id}` is not a UUID.

Ask to confirm ("Remove <name> from friends?"). Afterwards either player may send a new
request (real: B sent A a new request after A removed B, and A accepted it).

### 1f. Cancel a sent request

**Not available** (no route). Don't show a Cancel button. A pending request ends only when
the addressee answers it, or when either player blocks the other (the block declines it).

---

## 2. Presence (online now)

Presence is a heartbeat: a player counts as online for **120 seconds** after their last
heartbeat. The gateway keeps it in memory (Redis) only; nothing is pushed to anyone, and game
servers don't set it. The app must send the heartbeat itself.

### 2a. Heartbeat

`POST /presence/heartbeat`

```json
{}
```

or, while in a game:

```json
{"game_id": "ludo"}
```

| Field | Rule |
|---|---|
| `game_id` | Optional. 1 to 32 letters, digits, `-` or `_`. Send the game `code` (`ludo`, `snake-and-ladder`). It is stored but **no player route reads it back** today, so friends can't see "in game". |

The body must be JSON: send `{}` when there is nothing else. Real:

```json
{"status": "ok"}
```

Errors (real):

```json
// no body at all
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: EOF while parsing a value at line 1 column 0"}
// a game_id with other characters
{"error": "VALIDATION_ERROR", "field": "game_id", "message": "validation error: game_id: is invalid (invalid_game_id)"}
```

What the app does: send one heartbeat on sign-in and on resume, then every **60 seconds**
while the app is in the foreground. Stop the timer in the background; the player then drops
out of "online" within 2 minutes. There is no "go offline" route. Ignore heartbeat errors
except `401` (the interceptor handles it); never retry a failed heartbeat.

### 2b. Which friends are online

`GET /presence/friends-online`

Real (A, with B online):

```json
{
  "online_friends": ["0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303"],
  "friends": [{"user_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303", "username": "w09docb1795513466", "avatar_url": null}]
}
```

A player with no friends online (real):

```json
{"online_friends": [], "friends": []}
```

| Field | Meaning |
|---|---|
| `online_friends` | Ids of friends with a heartbeat in the last 120 seconds. |
| `friends` | The same players in the same order, with `username` and `avatar_url` (both may be `null`). Use these cards; `online_friends` is kept for older clients. |

What the app does: read it when the Friends screen opens and every **30 seconds** while it is
open (not in the background). Show a green dot on those friends; everyone else is
"offline" with no time (there is no last-seen; don't show "last seen").

### 2c. Players online (whole platform)

`GET /presence/online-count`. Real:

```json
{"global_count": 2}
```

Counts every player with a heartbeat in the last 120 seconds. Optional lobby decoration
("2 players online"); read it at most once a minute.

---

## 3. Chat (rooms)

Chat on the gateway is a **room message board over HTTP**: send a line, read the history.
There are no direct messages, no unread counts, no read receipts and no real-time delivery.

| `room_type` | `room_id` | Who may read | Who may post |
|---|---|---|---|
| `lobby` | Any text you choose, for example a game code `ludo`. | Any signed-in player. | Any signed-in player not muted or chat-banned. |
| `global` | Any text; use `main`. | Any signed-in player. | Same. |
| `match` | A match UUID (the game socket's `room_id`). | Players of that match only. | Same, if not muted. |

Anything else in `{room_type}` (for example `direct`) is `400`.

**How this differs from in-game chat.** Inside a game room, quick chat (`chat.send`, only the
12 preset lines) and gifts (`gift.send`) go over the **game socket** and reach everyone in the
room instantly (`games/ludo.md`, section 8). Use the socket for table talk. The gateway chat
here is free text, outside a game, and has to be polled. The two are separate: lines sent on
one never appear on the other.

Product advice: if the app shows gateway chat at all, show one lobby room per game
(`/chat/lobby/<game code>`) and keep it optional. Free text is not filtered by the server.

### 3a. Send

`POST /chat/{room_type}/{room_id}/send`

```json
{"body": "hello from A"}
```

`body`: 1 to 2000 characters. Real (`/chat/lobby/w09doc-1795513466/send`):

```json
{
  "id": "1795513509258-0",
  "room_type": "lobby",
  "room_id": "w09doc-1795513466",
  "sender_user_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
  "body": "hello from A",
  "created_at": "2026-11-24T09:45:09.259236Z"
}
```

| Field | Meaning |
|---|---|
| `id` | The message id: `<epoch ms>-<n>`. Unique within the room; use it as the list key and for paging. Don't parse it. |
| `sender_user_id` | The author. No name: use the `PlayerNameCache`. |
| `created_at` | Server time. |

What the app does: add the returned message to the list at once (don't wait for the next
poll), and drop the duplicate when the poll brings it back (same `id`).

### 3b. History

`GET /chat/{room_type}/{room_id}/history?count=50&before=<id>`

| Query | Rule |
|---|---|
| `count` | 1 to 200, default 50. |
| `before` | Optional. Return only messages **older** than this message `id` (exclusive). Leave it out for the newest. |

The reply is a **plain array, newest first**. Real (`?count=2`):

```json
[
  {"id": "1795513510773-0", "room_type": "lobby", "room_id": "w09doc-1795513466",
   "sender_user_id": "2195e313-e807-4a69-b562-afc27625821f", "body": "C joins",
   "created_at": "2026-11-24T09:45:10.774Z"},
  {"id": "1795513510004-0", "room_type": "lobby", "room_id": "w09doc-1795513466",
   "sender_user_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303", "body": "hi A, B here",
   "created_at": "2026-11-24T09:45:10.005Z"}
]
```

Older, real (`?before=1795513510004-0`):

```json
[{"id": "1795513509258-0", "room_type": "lobby", "room_id": "w09doc-1795513466",
  "sender_user_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d", "body": "hello from A",
  "created_at": "2026-11-24T09:45:09.259Z"}]
```

An empty room is `[]`. Note `created_at` here has millisecond precision, while the send reply
has microseconds; parse both.

What the app does:

- Open: read the newest 50, show them oldest at the top.
- "Load older": `before=<the oldest id you hold>`; stop when the reply has fewer than `count`
  items.
- New messages: while the chat is on screen, poll the newest page every **10 seconds** (the
  floor in `00-conventions.md`) and merge by `id`. Stop when the screen closes.
- Hide lines from blocked players (`BlockList`): the server still returns them (section 6).
- A room keeps about the last 10,000 messages.

**Errors** (all real)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` (`field: "body"`) | Empty body or over 2000 characters. | Block Send on the device. |
| 400 | `VALIDATION_ERROR` (`field: "count"`) | `count` outside 1-200. | App bug. |
| 400 | `BAD_REQUEST` | Unknown `room_type`; a `match` room id that is not a UUID; a bad `before`. | App bug. |
| 403 | `FORBIDDEN` | `match` room of a match the player wasn't in. | Hide match chat for other players' matches. |
| 403 | `FORBIDDEN` | The player is muted or chat-banned (from the code: `"you are muted or banned from chat"`). | "You can't chat right now." Disable the input. |

```json
{"error": "VALIDATION_ERROR", "field": "body", "message": "validation error: body: must be 1 to 2000 characters"}
{"error": "VALIDATION_ERROR", "field": "count", "message": "validation error: count: must be between 1 and 200"}
{"error": "BAD_REQUEST", "message": "bad request: room type must be one of match, lobby, global"}
{"error": "BAD_REQUEST", "message": "bad request: match room id must be a match UUID"}
{"error": "BAD_REQUEST", "field": "before", "message": "bad request: before must be +, a stream entry id like 1700000000000-0, or ( and an entry id"}
{"error": "FORBIDDEN", "message": "forbidden: only match participants can use this chat"}
```

The two `FORBIDDEN` cases share a code; tell them apart by the room type (a `match` room vs
any room).

---

## 4. Gifts

A gift moves tokens or gold from the sender's wallet to another player's at once, with an
optional message and a label. It is the same money movement as a wallet transfer
(`03-wallet.md`, section 4), recorded as a gift. It can't be undone: always confirm ("Send 5
gold to <name>?").

The receiver does **not** have to be a friend (real: B sent C a gift while C had blocked B;
see section 6). The app should offer "Send gift" only on friends' cards.

### 4a. Send a gift

`POST /gifts/send`

This route has the **device check** (`00-conventions.md`): a changed `User-Agent` or network
since login answers `401 FINGERPRINT_MISMATCH`; log in again. Development skips it.

| Header | |
|---|---|
| `Idempotency-Key` | Optional but **send it**: a new UUID per send attempt, reused on a retry of the same attempt. 1 to 100 printable ASCII characters. |

```json
{
  "receiver_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303",
  "item_type": "rose",
  "item_id": "rose",
  "amount": 5,
  "currency": "gold",
  "message": "for you"
}
```

| Field | Rule |
|---|---|
| `receiver_id` | Required. Another player. Not yourself. |
| `item_type` | **Required**, 1 to 64 characters. A label for the gift's look (`rose`, `currency`). Not checked against any catalogue. |
| `item_id` | **Required**, 1 to 128 characters. A second label; send the same as `item_type` or `gold` / `token`. |
| `amount` | Required. A whole number, at least 1. This is the money moved. |
| `currency` | Required. `token` (also `tokens`) or `gold`. The reply always says `token` or `gold`. |
| `message` | Optional, up to 500 characters (the in-game socket gift allows only 200; keep it to 200). |

Suggested app use: a small fixed set of gift looks (rose, cake, trophy), each with a label
and an amount the player picks; send the look as `item_type` and `item_id`.

**Success:** `201`. Real:

```json
{
  "id": "5e3933a0-d5e3-4282-a1ab-28a54a8bbbd2",
  "sender_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
  "receiver_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303",
  "item_type": "rose",
  "item_id": "rose",
  "amount": 5,
  "currency": "gold",
  "message": "for you",
  "created_at": "2026-11-24T09:45:17.564106Z"
}
```

`amount` is a **number** here (the wallet routes send strings; parse both, `03-wallet.md`).
The reply has no new balance: re-read `GET /wallet/balance` after a gift.

**Retry with the same key:** `201`, the first gift again, header `Idempotent-Replayed: true`;
nothing moves twice. The field order differs; parse by name. Real:

```json
{"amount": 5, "created_at": "2026-11-24T09:45:17.564106Z", "currency": "gold",
 "id": "5e3933a0-d5e3-4282-a1ab-28a54a8bbbd2", "item_id": "rose", "item_type": "rose",
 "message": "for you", "receiver_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303",
 "sender_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d"}
```

The key covers receiver, amount, currency, `item_type` and `item_id` (not `message`). The same
key with a different amount is `409 CONFLICT` (real).

**Ledger.** Each gift writes one `gift` row on both sides (`03-wallet.md`, "Kinds"): the
sender a `debit`, the receiver a `credit`, each with the other's `counterparty_user_id`. The
ledger row has no message or label. Real (receiver B):

```json
{"entry_id": "ledger:42110", "created_at": "2026-11-24T09:45:17.564106Z", "currency": "gold",
 "direction": "credit", "amount": 5, "kind": "gift", "counterparty": "user",
 "counterparty_user_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d", "tournament_id": null,
 "match_id": null, "item_kind": null, "item_name": null, "game_code": null, "variant_code": null}
```

**Quota.** Gifts share one send quota with wallet transfers and in-game socket gifts: **10 a
day and 50 a week** per sender on the development defaults (an operator can change them).
The day is the **UTC** date; the week is the ISO week. A failed or replayed send doesn't use
it up. Real: A's 11th send of the day was refused, and so was a wallet transfer right after:

```json
{"error": "GIFT_QUOTA_EXCEEDED", "message": "daily gift limit of 10 reached"}
```

The weekly refusal says `weekly gift limit of 50 reached` (from the code). There is no route
that reads how many sends are left; count locally for a hint only, and trust the `429`.

**Errors**

| Status | `error` | When | Show | Seen |
|---|---|---|---|---|
| 400 | `VALIDATION_ERROR` (`field: "amount"`) | `amount` below 1. | "Enter an amount of 1 or more." | real |
| 400 | `VALIDATION_ERROR` | Gift to yourself; a label or message too long. | App bug. | real |
| 400 | `BAD_REQUEST` | `currency` not token/gold; a missing field (`item_type`, `item_id`); a fraction in `amount`; a bad `Idempotency-Key`. | App bug. | real (fraction and key: code) |
| 401 | `FINGERPRINT_MISMATCH` | Network or app identity changed since login (production). | Log in again. | code |
| 404 | `NOT_FOUND` | No such player (`player not found`), or no wallet (`wallet not found`). | "That player can't receive gifts." | real |
| 409 | `INSUFFICIENT_FUNDS` | Not enough of that currency. | "Not enough gold." Offer the shop. | real |
| 409 | `CONFLICT` | The same `Idempotency-Key` with a different gift. | App bug: a new key per attempt. | real |
| 429 | `GIFT_QUOTA_EXCEEDED` | Daily or weekly quota used up. | "You've reached today's gift limit." | real |
| 503 | `KILL_SWITCH_ENGAGED` | An operator paused transfers (gifts use the same switch). | Show the `message`; disable Send. | code |

```json
{"error": "VALIDATION_ERROR", "field": "amount", "message": "validation error: amount: must be at least 1"}
{"error": "VALIDATION_ERROR", "message": "validation error: cannot send a gift to yourself"}
{"error": "BAD_REQUEST", "message": "bad request: unsupported currency: 'gems'"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: missing field `item_type` at line 1 column 84"}
{"error": "NOT_FOUND", "message": "not found: player not found"}
{"error": "INSUFFICIENT_FUNDS", "message": "insufficient funds"}
{"error": "CONFLICT", "message": "conflict: idempotency key was already used for another purchase"}
```

No network or a timeout: don't assume it failed. Retry **once with the same key**.

### 4b. Gift history

`GET /gifts/received?page=1&per_page=20` and `GET /gifts/sent?page=1&per_page=20`

Page lists of the gift object above, newest first. Real (B received, `per_page=2`):

```json
{
  "data": [
    {"id": "04321e6d-0e64-4820-815a-3f899205e1f6", "sender_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
     "receiver_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303", "item_type": "currency", "item_id": "token",
     "amount": 1, "currency": "token", "message": null, "created_at": "2026-11-24T09:45:22.098277Z"},
    {"id": "5e3933a0-d5e3-4282-a1ab-28a54a8bbbd2", "sender_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
     "receiver_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303", "item_type": "rose", "item_id": "rose",
     "amount": 5, "currency": "gold", "message": "for you", "created_at": "2026-11-24T09:45:17.564106Z"}
  ],
  "total": 2, "page": 1, "per_page": 2, "total_pages": 1
}
```

`/gifts/sent` for A returned the same two rows (real). Both lists include gifts sent over a
game socket (they are stored in the same table, from the code).

What the app does: two tabs, "Received" and "Sent". Each row: the other player's name
(`PlayerNameCache`), the gift look from `item_type`, `+5 gold` / `-5 gold`, the message, and
the time. Load more with `page=page+1` until `page == total_pages`. There is no push when a
gift arrives outside a game: re-read "Received" when the screen opens and on resume.

---

## 5. Referrals

Each player has one referral code. A new player enters a friend's code at sign-up (or later,
once); both are paid when the new player makes their **first real-money purchase**.

### 5a. My code

`GET /referrals/my-code`. Creates the code on the first call; the same code every time after.
Real (A):

```json
{"code": "39UVKDVP", "uses": 0, "max_uses": null, "expires_at": null}
```

After two players used it (real):

```json
{"code": "39UVKDVP", "uses": 2, "max_uses": null, "expires_at": null}
```

| Field | Meaning |
|---|---|
| `code` | 8 characters, upper-case letters and digits. |
| `uses` | How many players have used it. |
| `max_uses` | `null` = no limit. |
| `expires_at` | `null` = never. |

**Share link:** there is no server link. Build one on the device, for example
`https://<app-domain>/invite?code=39UVKDVP` or the store link with the code, and share it
with the system share sheet plus the code as text. When the app opens from such a link,
pre-fill the sign-up form's `referral_code` and send `entry_source: "invite"`
(`01-auth.md`).

### 5b. Using a code

**At sign-up** (preferred): `POST /auth/register` with `"referral_code": "39UVKDVP"`
(`01-auth.md`). A wrong or used-up code never fails the sign-up; it is just not applied, and
the reply doesn't say. Real: C signed up with A's code and A's stats went to 1.

**After sign-up**, once per account: `POST /referrals/apply`

```json
{"code": "39UVKDVP"}
```

**Success:** `204`, no body (real: B applied A's code after signing up).

**Errors** (all real)

| Status | `error` | When | Show |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` (`field: "code"`) | Empty or over 16 characters. | "Enter a code." |
| 400 | `BAD_REQUEST` | Your own code; or the code is inactive, expired or used up. | "You can't use this code." |
| 404 | `NOT_FOUND` | No such code. **Codes are case-sensitive**: `39uvkdvp` is not found. | "Code not found." |
| 409 | `CONFLICT` | This account already used a referral code (also one from sign-up). | "You've already used a referral code." Hide the field from then on. |

```json
{"error": "VALIDATION_ERROR", "field": "code", "message": "validation error: code: must be 1 to 16 characters"}
{"error": "BAD_REQUEST", "message": "bad request: cannot use your own referral code"}
{"error": "NOT_FOUND", "message": "not found: referral code not found"}
{"error": "CONFLICT", "message": "conflict: referral code already applied"}
```

What the app does: upper-case and trim the input before sending (at sign-up too), since a
lower-case code fails silently at sign-up. Show an "Enter a friend's code" field in the
invite screen only until it succeeds or answers `409`.

### 5c. My stats

`GET /referrals/stats`. Real (A after C and B used the code):

```json
{"total_referrals": 2, "rewards_granted": 0}
```

| Field | Meaning |
|---|---|
| `total_referrals` | Players who used my code. |
| `rewards_granted` | Of those, how many have been paid out. |

There is no list of who they are. Show "2 friends joined, 0 rewards earned".

### 5d. The reward

From the code and the development settings (`referral.reward`, an operator setting):

- **500 gold to each side** (the referrer and the new player).
- Paid when the new player makes their **first real-money pack purchase** (tokens or gold,
  `11-store.md`), within **30 days** of using the code. Sign-up alone pays nothing (real: C's
  ledger after sign-up has only the two `signup_grant` rows).
- Each payment is a ledger row with `kind: "referral_reward"`, `direction: "credit"`,
  `counterparty: "promo_budget"` (`03-wallet.md`). Not captured: no real-money purchase was
  made for this file.
- No push or inbox message is sent (from the code). Re-read the balance and stats on resume.

Read the amount for the invite screen's text from your own config, not hard-coded in a
string; the operator can change it.

---

## 6. Blocks

### 6a. Block

`POST /blocks/{user_id}`. No body. Real:

```json
{"status": "blocked"}
```

What a block does at once (real, unless marked):

- Removes the friendship, if any (A's friend list became empty when B blocked A).
- Declines every pending friend request between the two, both ways (C's incoming request
  from A disappeared when C blocked A).
- Stops friend requests **both ways**: `409 USER_BLOCKED` for the blocker and the blocked.
- The blocked player is not told and can't see it (A's own `GET /blocks` stayed empty).

What a block does **not** stop (real; the app must hide these itself, see "Known issues"):

| Still allowed after a block | Seen |
|---|---|
| Gifts and wallet transfers from the blocked player to the blocker | real (B sent C 1 gold as a gift and 1 gold as a transfer while C had blocked B) |
| Chat lines in shared rooms; the blocker still reads them in history | real |
| Viewing the blocker's profile | real |
| Sitting at the same game table, in-game chat and socket gifts | code (game servers don't read blocks) |

**Errors** (all real)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | Blocking yourself. | Never offer it. |
| 400 | `BAD_REQUEST` | `{user_id}` not a UUID. | App bug. |
| 409 | `CONFLICT` | Already blocked. | Treat as done. |
| 500 | `DATABASE_ERROR` | No such player (a bug: should be 404). | "Player not found." Don't retry. |

```json
{"error": "VALIDATION_ERROR", "message": "validation error: cannot block yourself"}
{"error": "CONFLICT", "message": "conflict: user is already blocked"}
```

Ask to confirm ("Block <name>? You won't see their messages, and you'll stop being friends.").

### 6b. Unblock

`DELETE /blocks/{user_id}`. Real:

```json
{"status": "unblocked"}
```

`404 NOT_FOUND` `"not found: block not found"` when not blocked (real); treat as done. An
unblock does not bring back the friendship or old requests; either player may send a new
request (real: A's request to B went through after B unblocked A).

### 6c. My blocked players

`GET /blocks?page=1&per_page=20`. Only players **I** blocked, newest first, **with names**.
Real (B):

```json
{
  "data": [
    {"blocker_id": "0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303",
     "blocked_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
     "user_id": "21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d",
     "created_at": "2026-11-24T09:45:35.816963Z",
     "username": "w09doca1795513466", "avatar_url": null}
  ],
  "total": 1, "page": 1, "per_page": 20, "total_pages": 1
}
```

| Field | Meaning |
|---|---|
| `user_id` | The blocked player (same as `blocked_id`). Use this one. |
| `username`, `avatar_url` | The blocked player's name and avatar (may be `null`). |
| `created_at` | When the block was made. |

What the app does: load every page into the `BlockList` on sign-in, and update it locally on
block and unblock. Use it to hide those players' chat lines, gift and add-friend buttons, and
to warn before joining a room with them.

---

## Errors

The error body and the shared codes are in `00-conventions.md`, "Errors". Each section above
lists what its route returns. Social codes in one place:

| Status | `error` | Routes |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Self friend request, self gift, self block; empty chat body; gift `amount` below 1; empty referral code; `per_page`, `count` out of range; bad `game_id`. |
| 400 | `BAD_REQUEST` | Bad ids in body or path; unknown chat room type; bad `before`; unknown gift currency; own or unusable referral code. |
| 403 | `FORBIDDEN` | Friend requests turned off; answering your own request; match chat of another match; muted or chat-banned. |
| 404 | `NOT_FOUND` | Unknown player, request, friendship, block or referral code. |
| 409 | `USER_BLOCKED` | Friend request between blocked players. |
| 409 | `DUPLICATE_FRIEND_REQUEST` | A pending request already exists, either direction. |
| 409 | `CONFLICT` | Already friends; already blocked; referral already applied; gift key reused. |
| 409 | `INSUFFICIENT_FUNDS` | Gift above the balance. |
| 429 | `GIFT_QUOTA_EXCEEDED` | Gift or transfer over the daily or weekly quota. |
| 500 | `DATABASE_ERROR` | Blocking an unknown player (bug). |

---

## Limits

| What | Limit |
|---|---|
| All routes here | The general limit, about 100 requests a minute per player (`429 RATE_LIMITED`). |
| Heartbeat | Every 60 seconds in the foreground; online lasts 120 seconds. |
| Friends online | Every 30 seconds while the Friends screen is open. |
| Chat polling | Every 10 seconds while a chat is on screen. |
| Chat message | 1 to 2000 characters; history `count` 1 to 200. |
| Gifts and transfers | 10 a day (UTC) and 50 a week per sender, shared (development defaults). |
| Gift labels | `item_type` 1-64, `item_id` 1-128, `message` up to 500 (keep 200). |
| Referral code | 1 to 16 characters on input; codes are 8. One code applied per account. |
| Page lists | `per_page` 1 to 100, default 20. |

---

## Known issues (the app must cope)

1. **No player search.** The only list of users is an admin route. Add friends from ids the
   app already has (rooms, results, leaderboards, chat, gifts).
2. **No cancel and no outgoing list for friend requests.** A sent request can't be withdrawn
   and isn't listed; it stays pending until answered or a block declines it. Track "Request
   sent" locally; handle `DUPLICATE_FRIEND_REQUEST` as "already sent".
3. **Friend and request lists have ids only.** Names need `GET /users/{id}/profile` per
   player (or the cards from friends-online and blocks). Cache, fetch lazily, mind the rate
   limit.
4. **Blocks are enforced only on friend requests.** Gifts, wallet transfers, room chat,
   profile views and game tables ignore them (real for the first four). The app hides
   blocked players itself; it can't stop a blocked player from sending the blocker money.
5. **Blocking an unknown player answers `500 DATABASE_ERROR`** with a database message, not
   `404`. Show "Player not found".
6. **No direct messages and no real-time chat or presence on the gateway.** Chat is room-based
   and polled; `dm_from` in privacy settings does nothing yet. Presence has no "in game" and
   no "last seen" for others, and game servers don't send heartbeats, so a player counts as
   online only while the app sends them.
7. **Lobby and global rooms are open to every player**, with any `room_id` and unfiltered free
   text; history is readable by anyone who knows the room name.
8. **Gifts are money only.** `item_type` and `item_id` are free labels; no item leaves an
   inventory. The gift doesn't require friendship. The gift reply has no balance; re-read it.
9. **Referral codes are case-sensitive**, and a bad code at sign-up is dropped silently. Upper-
   case the input. A player can apply a code after sign-up at any time (no age limit), once.
10. **No list of referred players and no share link** from the server; counts only.
11. **The gift key conflict message says "purchase"** (`idempotency key was already used for
    another purchase`). Decide on `error`, never `message`.
12. **No notification** is created for a friend request, an accepted request or a gift
    received outside a game (from the code). Re-read on screen open and on resume.

---

## Done when

- [ ] "Add friend" on another player's card sends a request; the button becomes "Request
      sent"; a second tap shows "Request already sent" from `DUPLICATE_FRIEND_REQUEST`.
- [ ] A player with friend requests off shows "This player isn't accepting friend requests".
- [ ] The Requests tab lists incoming requests with names; Accept moves the player to Friends
      on both phones (after a refresh); Decline removes the row.
- [ ] When the other player already sent me a request, their card shows "Accept", not "Add".
- [ ] The friend list loads every page, shows names and avatars, online friends first with a
      green dot, and updates every 30 seconds while open.
- [ ] Remove friend asks to confirm and removes the row; a 404 is treated as done.
- [ ] The heartbeat runs every 60 seconds in the foreground (with `game_id` in a game) and
      stops in the background; the player drops off friends' online list within 2 minutes.
- [ ] Lobby chat (if shown): send shows the line at once, the poll brings others' lines every
      10 seconds, "load older" pages with `before`, blocked players' lines are hidden.
- [ ] Send gift: a confirm step, a new `Idempotency-Key` per attempt, the same key on retry,
      the balance re-read after; both players see a `gift` row in history; "Received" and
      "Sent" tabs list it with the message.
- [ ] The 11th gift or transfer of the UTC day shows "You've reached today's gift limit".
- [ ] Invite screen shows my code, Copy and Share; the counts from `/referrals/stats`.
- [ ] Sign-up from an invite link pre-fills the code (upper-cased) and sends
      `entry_source: "invite"`; the referrer's `total_referrals` goes up by one.
- [ ] "Enter a friend's code" maps `404`, `400` and `409` to their messages and hides itself
      after success or `409`.
- [ ] Block asks to confirm, removes the friend, and the player appears in Blocked players;
      friend requests both ways then show "You can't add this player"; Unblock removes them.
- [ ] Blocked players are hidden in chat, the gift sheet and friend suggestions.
- [ ] No gift body appears in any log.

---

## Test accounts

Create your own accounts with Sign up on the development server (any `@example.com` email);
each starts with 100 tokens and 500 gold. Social features need at least two accounts on two
devices (or one device and `curl`). Don't use other people's accounts.

The samples in this file came from three accounts made for it on 24 Nov 2026:

| | Username | User id |
|---|---|---|
| A | `w09doca1795513466` | `21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d` |
| B | `w09docb1795513466` | `0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303` |
| C | `w09docc1795513466` (signed up with A's code `39UVKDVP`) | `2195e313-e807-4a69-b562-afc27625821f` |

State they were left in: A has used today's gift quota; A has a pending request to B; C has
blocked A and B; A's code has 2 uses (C at sign-up, B by `/referrals/apply`), no rewards.
