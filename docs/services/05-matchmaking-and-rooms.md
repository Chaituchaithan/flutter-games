# Flutter hand-off 5: matchmaking and rooms

How a player gets from the game's home screen into a seat at a table: quick match, private
rooms with a code, the list of open tables, Bingo's live rooms, and bots that fill empty
seats. This is the cross-game picture. Each game's own file (for example
`games/ludo.md`) gives the exact event fields for that game.

Read `00-conventions.md` (socket envelope, reconnect, errors) and `01-auth.md` (tokens)
first. This file links to them instead of repeating them.

Checked on 24 Nov 2026 against the running gateway and the Ludo server, with two new test
players and the bot service running. Samples marked **real** were captured then (tokens
blanked, long game states cut). Samples marked **from code** follow the server code.

---

## For the Claude agent: what to build

1. A `GameLobby` interface, one implementation per game, on top of the shared `GameSocket`
   (`00-conventions.md`). Methods: `listOpenRooms`, `quickMatch`, `cancelSearch`,
   `createRoom`, `joinByCode`, `leaveRoom`. Ludo is the first implementation.
2. A `LobbyController` (state machine) that every game's screens share:
   `idle` (signed in on the socket) -> `searching` (quick match, alone in a lobby) or
   `waitingRoom` (seated, others arriving) -> `inGame` -> `result` -> back to `idle`.
3. A `ModePicker` that splits the modes from `GET /games/{id}/modes` into **Quick match**
   modes and **Play with friends** modes (see "Choosing a mode").
4. Screens, shared by every game that uses rooms: **Searching** (timer, Cancel),
   **Waiting room** (seats, room code with Copy and Share, Ready), **Join with code**
   (an 8-character field), **Open tables** (a list with Join).
5. For Bingo only: a **Live rooms** list from `GET /live-rooms` (see 3).
6. Tests: the controller's moves for each of the three flows below; parsing every sample
   in this file; the errors in "Errors"; "no opponent found" after the search timeout.

Do not call `/matchmaking/...` on the gateway. Those routes are retired (see 4).

---

## Where each step happens

The gateway does **not** match players and does **not** hand out room tickets. Matching,
rooms, seats and bots all live on each game's own WebSocket. The gateway gives the
catalogue, the wallet and, for Bingo, the live-room setup.

| Step | Where | How |
|---|---|---|
| Find the game's numeric id | Gateway HTTP | `GET /games`, by `code` (`04-game-catalogue.md`) |
| Modes, seats, stakes | Gateway HTTP | `GET /games/{id}/modes`, `GET /games/{id}/stakes` (`04-game-catalogue.md`) |
| Can the wallet cover the stake | Gateway HTTP, then the socket | `GET /wallet/balance` to grey out tiers; the socket checks again on `match.find` / `room.create` |
| Open the game connection | Game socket | `ws://<host>:<port>/ws`, then `auth.login` with the **same access token** the gateway uses |
| Quick match | Game socket | `match.find` -> `match.found`; `match.cancel` |
| Private room | Game socket | `room.create` -> `room.created` (gives `room_code`); friends send `room.join` |
| Open tables list | Game socket | `room.list` -> `room.list_result`, then `room.join` |
| Bot fills a seat | Server side | The game server asks the bot service; the app only sees `room.user_joined` with `is_bot: true` |
| Ready and start | Game socket | `player.ready` until `game.started` (each game's file) |
| Bingo live rooms (setup) | Gateway HTTP | `GET /live-rooms`, `GET /live-rooms/{id}` |
| Bingo live rooms (play) | Bingo socket | `live.list_rooms`, `live.join` with the room's `id` (Bingo's file) |
| Tournament tables | Gateway, then socket | The tournament gives a `room_code`; join with `room.join` (`06-tournaments.md`) |
| Result and history after the game | Gateway HTTP | `GET /wallet/balance`, `GET /matches/{id}` (`03-wallet.md`, `08-progress-and-history.md`) |

**Room tokens:** there are none. A room is reached by its `room_code` on the game socket,
and the player's access token signs them in. Nothing from the gateway is needed to join.

**Invites:** there is no player route that sends a room invite yet. Share the `room_code`
through the phone's share sheet or a chat message. (The game servers' `/debug/invites`
routes are for the debug page only; don't use them.)

---

## Endpoints at a glance (gateway)

All need `Authorization: Bearer <access_token>`. Base URL and headers as in
`00-conventions.md`.

| Use | Method and path | Success |
|---|---|---|
| Games list (find the id) | `GET /games` | `200`, plain array (`04-game-catalogue.md`) |
| Modes of a game | `GET /games/{id}/modes` | `200`, plain array (`04-game-catalogue.md`) |
| Bingo live rooms | `GET /live-rooms` | `200`, plain array |
| One Bingo live room | `GET /live-rooms/{id}` | `200`, one object |
| Retired matchmaking queue | `POST /matchmaking/queue`, `DELETE /matchmaking/queue`, `GET /matchmaking/status` | always `410` |

There is no `bonus_tables` route. That module is the bonus-games catalogue (wheel, scratch
card, chest) and belongs to `07-rewards.md`. It has nothing to do with game tables.

---

## 1. Choosing a mode

From `GET /games/1/modes` (Ludo), **real**, one mode cut down:

```json
{"id": 1, "game_id": 1, "code": "casual_4p", "name": "Casual 4 Players", "variant_code": "classic",
 "player_count": 4, "min_players": 2, "is_ranked": false, "is_active": true, "turn_timer_seconds": 10,
 "limit_label": "Standard", "mode_config": {"rule_options": {}, "timer": {}}}
```

| Field | Use |
|---|---|
| `code` | Sent as `mode_code` on `match.find` and `room.create`. |
| `player_count` | The seats at the table. **Send it as `player_count` on `match.find`** (see below). |
| `min_players` | Fewest seats a host may pick on `room.create`. |
| `mode_config.host_can_choose` | Present only on "with friends" modes: the options the host may set. |

**Quick match or with friends.** The catalogue has no field that says which list a mode
belongs in, and the servers accept either kind on either path (see "Known gaps"). Use this
rule in the app:

- `mode_config.host_can_choose` present: a **Play with friends** mode, for `room.create`.
- Otherwise: a **Quick match** mode, for `match.find`.

**Always send `player_count`.** `match.find` defaults to 2 seats, whatever the mode says.
Real: `match.find {"mode_code": "casual_4p"}` with no `player_count` opened a lobby with
`"max_players": 2`. Send `player_count` = the mode's `player_count`.

---

## 2. Opening the game socket (the hand-off)

The step from the gateway to a game is only this:

1. Build the URL from the same host and the game's port (`ws://<host>:<port>/ws`; Ludo
   1285). The gateway does not send it; keep the ports in the app's config by game `code`.
2. Open the socket, wait for `connection.established`, send `auth.login` with the
   current access token (`00-conventions.md`, "Lifecycle").
3. On `auth.login_success` the socket is in the lobby state and every request below
   works.

Open the socket when the player enters the game's home screen, and keep it open while they
stay in that game. One socket per player per game server. When the player leaves the game
area (and is not in a room), close it.

If the player was in a running game when the app died, `auth.login` puts them back in it
and the server sends the full state (`00-conventions.md`, "Reconnect"). So: always open the
socket and sign in **before** showing the lobby buttons, and go straight to the board if a
game state arrives.

---

## 3. Bingo live rooms (gateway)

Bingo's live rooms are always-on rooms that play round after round (buy cards, countdown,
calling, results, repeat). The gateway gives their fixed setup; the Bingo socket gives the
live phase and plays the rounds. No other game uses these routes.

### `GET /live-rooms`

| Query | |
|---|---|
| `is_active` | Optional, `true` or `false`. Send `true`: show only rooms that are on. |
| `variant` | Optional, `75ball` or `90ball`. Any other value just returns `[]`. |

**Success:** `200`, a plain array sorted for display. **Real** (one of 7 rows):

```json
[{"id": "c3ac2140-6187-476b-8de3-5b240ef39e5c", "name": "Low Stakes 75-Ball", "variant": "75ball",
  "currency": "token", "is_active": true, "sort_order": 1,
  "ticket_price": 10, "min_tickets": 1, "max_tickets": 4,
  "buying_duration_ms": 20000, "countdown_duration_ms": 5000, "results_duration_ms": 3000,
  "call_interval_ms": 1000, "min_players": 2, "max_players": 500,
  "rake_pct": 10, "guaranteed_pool": 0,
  "prize_config": {"prizes": [
    {"code": "line", "display_name": "Line", "max_winners": 1, "share_pct": 20},
    {"code": "four_corners", "display_name": "Four Corners", "max_winners": 1, "share_pct": 15},
    {"code": "x_pattern", "display_name": "X Pattern", "max_winners": 1, "share_pct": 25},
    {"code": "full_house", "display_name": "Full House", "max_winners": 1, "share_pct": 40}]},
  "created_at": "2026-11-14T08:35:16.461863Z", "updated_at": "2026-11-14T08:35:16.461863Z"}]
```

| Field | Show or use |
|---|---|
| `id` | Sent as `room_id` in Bingo's `live.join`. |
| `name`, `variant` | The room card's title and "75-ball" / "90-ball". |
| `currency`, `ticket_price` | "10 tokens a card". Grey out the room if the wallet can't pay `ticket_price`. |
| `min_tickets`, `max_tickets` | Cards one player may buy per round. |
| `*_duration_ms`, `call_interval_ms` | Phase lengths, for the room card and timers. The live phase itself comes from the socket. |
| `min_players` | A round is skipped when fewer players bought cards. |
| `max_players` | Room capacity. |
| `prize_config.prizes` | Prize names and the share of the pool each one pays. |
| `rake_pct`, `guaranteed_pool` | House cut and a floor on the pool (`0` = none). Show the pool the socket sends, not your own sum. |

Numbers here are plain JSON numbers, not strings.

**What the app does:** load the list when the Bingo home screen opens, draw a card per room,
and on tap open the Bingo socket and send `live.join` with that `id`. Live player counts and
the current phase come from the socket (`live.list_rooms`, `live.room_status`), so don't
poll this route.

### `GET /live-rooms/{id}`

One room, the same object. Use it for a deep link to one room.

### Errors

| Status | `error` | When | Do |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `{id}` is not a UUID, or `is_active` is not `true`/`false`. | App bug. |
| 401 | `UNAUTHORIZED` | No token or an expired one. | The interceptor refreshes (`01-auth.md`). |
| 404 | `NOT_FOUND` | No room with that id (deleted). | Reload the list. |

Real replies:

```json
// 404
{"error": "NOT_FOUND", "message": "not found: live room 00000000-0000-4000-8000-000000000000"}
// 400
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: UUID parsing failed: invalid character: found `n` at 0"}
{"error": "BAD_REQUEST", "message": "bad request: Query deserialize error: provided string was not `true` or `false`"}
```

An inactive room is still returned by `GET /live-rooms/{id}` (and by the list without
`is_active`); check `is_active` before joining.

---

## 4. Retired: the gateway matchmaking queue

`POST /matchmaking/queue`, `DELETE /matchmaking/queue` and `GET /matchmaking/status` are
kept only to tell old clients they are gone. Every call answers, **real**:

```json
// 410 Gone
{"error": "MATCHMAKING_RETIRED", "message": "the gateway matchmaking queue is retired; use the game's WebSocket match.find"}
```

Never call them. Treat `410 MATCHMAKING_RETIRED` like any other app bug if it shows up.

---

## 5. Room families: which socket events a game uses

Every game server shares the same envelope and the same lobby states. The lobby events
come in four families. The game's own file is the authority for its exact fields.

| Family | Games | Lobby events |
|---|---|---|
| Rooms (most games) | Snake & Ladder, Ludo, Chess, Carrom, Checkers, Othello, Scrabble, Snooker, Combat Royale, Hill Climb, Racing, the word games (Spelling Bee, Word Rush, Guess Royale, Word Duel), and the shooter games (Arena Shooter, Battle Royale, Zombie Survival) | `match.find` / `match.cancel`, `room.create`, `room.join`, `room.list`, `room.leave` |
| Rooms plus fixed tables | Poker, Rummy, Uno, Teen Patti | The same, plus `table.list` for the always-open cash tables |
| Rooms plus live rooms | Bingo (Tombola runs on the same server; see its file) | The same, plus `live.list_rooms`, `live.join`, `live.leave`, `live.buy_card` (room ids from `GET /live-rooms`) |
| Shared rounds, no seats | Crash, Roulette | `crash.list_rooms` / `crash.join` and `roulette.list_rooms` / `roulette.join`: everyone in the room bets on the same round. No matching, no private rooms, no bots in seats. |

The common fields on the rooms family (from code; Ludo real):

| `match.find` field | |
|---|---|
| `mode_code` | The mode (see 1). |
| `player_count` | Seats; send the mode's `player_count`. |
| `currency` | `token` (default) or `gold`. |
| `bet_amount` | A stake tier from `GET /games/{id}/stakes`; `0` (default) is free. |

Some games add their own (for example a time control). Build `GameLobby` per game so those
extras live in that game's code, while the screens stay shared.

---

## Flow A: quick match

```
App                         Game socket                         Bot service
 |-- match.find ------------->|  no open lobby: make one
 |<- match.found (alone) -----|  (state: searching)
 |                            |-- after 5 s, still empty? ------->|
 |                            |<- bot takes the seat, is ready ---|
 |<- room.user_joined --------|  (is_bot true, or a human)
 |<- player.ready_update -----|
 |-- player.ready ----------->|
 |<- player.ready_update -----|
 |<- game.started ------------|  (state: inGame)
```

If an open lobby already matches (same mode, seats, currency and stake), `match.found`
seats the player there at once and the others get `room.user_joined`.

**1. Search.** Real (two humans, free table):

```json
// A sends
{"id": "A-2", "event": "match.find", "data": {"mode_code": "casual_2p", "currency": "token", "bet_amount": 0}}
// A, alone in a new lobby
{"id": "A-2", "event": "match.found", "data": {"bet_amount": 0, "currency": "token", "max_players": 2, "mode_code": "casual_2p",
  "players": [{"seat": 0, "user_id": "6d7ca0a3-9c83-4fde-aee1-5e1d9290f9d8", "username": "w05doca11951"}],
  "room_code": "c58a7c7b", "room_id": "c58a7c7b-a5ca-42fa-93ec-78ea28b03b81", "seat": 0}}

// B sends the same match.find 1 second later and is seated in A's lobby
{"id": "B-4", "event": "match.found", "data": {"bet_amount": 0, "currency": "token", "max_players": 2, "mode_code": "casual_2p",
  "players": [{"seat": 0, "user_id": "6d7ca0a3-9c83-4fde-aee1-5e1d9290f9d8", "username": "w05doca11951"},
              {"seat": 2, "user_id": "92ac29f6-61d3-4a2d-aad9-41e62c2b06cc", "username": "w05docb11951"}],
  "room_code": "c58a7c7b", "room_id": "c58a7c7b-a5ca-42fa-93ec-78ea28b03b81", "seat": 2}}
// both get
{"event": "room.user_joined", "data": {"avatar_url": null, "color": "yellow", "is_bot": false, "room_full": true, "seat": 2,
  "user_id": "92ac29f6-61d3-4a2d-aad9-41e62c2b06cc", "username": "w05docb11951"}}
```

What the app does with `match.found`:

- `players.length < max_players`: show **Searching** ("Finding players... 0:03") with
  Cancel. Keep `room_id`; it becomes the match id.
- Full: go to the waiting room and send `player.ready` (or show a Ready button, as the
  design says).
- `seat` is the player's own seat. Seat numbers are not packed: in a 2-seat Ludo game the
  second player sits at seat 2 (opposite).

**2. Cancel.** Only while searching. Real:

```json
{"id": "A-9", "event": "match.cancel"}
{"id": "A-9", "event": "match.cancelled", "data": {}}
```

After `game.started` the reply is an error (real):
`{"id": "A-5", "event": "match.error", "error": {"code": "invalid_state", "message": "event 'match.cancel' not allowed in InGame state"}}`.
Hide Cancel once the game starts; leaving then is a forfeit (each game's file).

**3. Ready and start.** As in the game's file. Real, the order the server sends:
`player.ready_update` for each player, then `game.started` with the full state.

**No opponent found.** The server has no search timeout and sends nothing while a lobby
waits. When no bot comes (see "Bots"), the lobby waits until the player cancels. The app
must time out on its own: after **60 seconds** of searching, show "No players found right
now." with **Keep waiting** and **Cancel** (Cancel sends `match.cancel`).

**Stakes.** A staked quick match checks the wallet on `match.find` and takes the entry fee
when the game starts. Real refusal:

```json
{"id": "A-11", "event": "match.find_error", "error": {"code": "insufficient_funds", "message": "insufficient balance for a stake of 99999999 token"}}
```

---

## Flow B: private room (with friends)

```
Host app                    Game socket                    Friend's app
 |-- room.create ------------->|
 |<- room.created (room_code) -|   host shares the code (share sheet, chat)
 |                             |<-- room.join {room_code} ---|
 |                             |--- room.joined ------------>|
 |<- room.user_joined ---------|--- room.user_joined ------->|
 |-- player.ready ------------>|<-- player.ready ------------|
 |<- game.started -------------|--- game.started ----------->|
```

Bots never fill a private room. It starts only when every seat is filled by a person and
everyone is ready.

**Create.** Real (the reply's `rules` and `players` are shown in full in `games/ludo.md`):

```json
{"id": "A-20", "event": "room.create", "data": {"mode_code": "friends_room", "max_players": 2, "listed": true}}
{"id": "A-20", "event": "room.created", "data": {"bet_amount": null, "board_layout": "standard", "color": "red", "currency": null,
  "listed": true, "max_players": 2, "mode_code": "friends_room", "mode_name": "Play with Friends",
  "players": [{"avatar_url": null, "balance_gold": 500, "balance_tokens": 100, "color": "red", "is_bot": false, "seat": 0,
               "user_id": "6d7ca0a3-9c83-4fde-aee1-5e1d9290f9d8", "username": "w05doca11951"}],
  "room_code": "c30321b1", "room_id": "c30321b1-a356-4c80-ad6b-d8078ca8f5c7", "rules": {"...": "..."}}}
```

- `room_code` is 8 characters (the first 8 of `room_id`). Show it large with **Copy** and
  **Share**. A share text such as "Join my Ludo table: code C30321B1" works; codes are not
  case sensitive.
- `listed: true` also shows the room in other players' open tables list (Flow C). The
  default `false` means code only.
- `max_players` is the host's choice between the mode's `min_players` and `player_count`.

**Join with a code.** Real (typed in upper case; it still matches):

```json
{"id": "B-8", "event": "room.join", "data": {"room_code": "C30321B1"}}
{"id": "B-8", "event": "room.joined", "data": {"bet_amount": null, "board_layout": "standard", "color": "yellow", "currency": null,
  "max_players": 2, "mode_code": "friends_room",
  "players": [{"avatar_url": null, "balance_gold": null, "balance_tokens": null, "color": "red", "is_bot": false, "ready": false, "seat": 0,
               "user_id": "6d7ca0a3-9c83-4fde-aee1-5e1d9290f9d8", "username": "w05doca11951"},
              {"avatar_url": null, "balance_gold": 500, "balance_tokens": 100, "color": "yellow", "is_bot": false, "ready": false, "seat": 2,
               "user_id": "92ac29f6-61d3-4a2d-aad9-41e62c2b06cc", "username": "w05docb11951"}],
  "room_code": "c30321b1", "room_id": "c30321b1-a356-4c80-ad6b-d8078ca8f5c7", "seat": 2, "tournament": null, "variant": "classic"}}
```

Real refusal:
`{"id": "A-13", "event": "room.join_error", "error": {"code": "not_found", "message": "no room found for code 'zzzzzzzz'"}}`.
The full list of `room.join_error` codes is in the game's file (for Ludo: `not_found`,
`room_full`, `game_in_progress`, `already_in_room`, `not_your_table`,
`kill_switch_engaged`, `busy`, `internal_error`).

**Leave.** In a waiting room `room.leave` frees the seat; the others get
`room.user_left` with `reason: "left"`. `match.cancel` does not work here (real):

```json
{"id": "A-21", "event": "match.cancel_error", "error": {"code": "invalid_state", "message": "not searching: this is a private room, use room.leave"}}
```

**Deep link (suggested).** Let `royalearcade://join/<game_code>/<room_code>` open the game,
open its socket, sign in and send `room.join`. The server has no link format of its own;
this is app-side only.

---

## Flow C: open tables list (browse and join)

```
App                         Game socket
 |-- room.list {variant?} ---->|
 |<- room.list_result ---------|  quick-match lobbies waiting for players
 |                             |  + private rooms the host listed
 |-- room.join {room_code} --->|
 |<- room.joined --------------|  then ready and start, as in Flow B
```

Real, while A was searching in a quick-match lobby:

```json
{"id": "B-2", "event": "room.list", "data": {"variant": "classic"}}
{"id": "B-2", "event": "room.list_result", "data": {"rooms": [
  {"bet_amount": 0, "created_at": 1795512122054, "currency": "token", "game_type": "ludo", "matchmaking": "random",
   "max_players": 2, "mode_code": "casual_2p", "players": 1, "room_code": "4408f0e2",
   "room_id": "4408f0e2-bb93-4aed-83f0-1294b924e07c", "status": "waiting", "variant": "classic"}], "total": 1}}

// a listed private room shows "matchmaking": "private_room", with "currency": null and "bet_amount": null when free
// nothing open
{"id": "B-3", "event": "room.list_result", "data": {"rooms": [], "total": 0}}
```

B then sent `room.join` with `"room_code": "4408f0e2"`, got `room.joined`, both readied and
the game started (real). Joining a quick-match lobby this way works like being matched to it.

What the app does:

- Show each room as a row: mode name (from the catalogue by `mode_code`), stake
  (`bet_amount` and `currency`; `null` or `0` is "Free"), `players`/`max_players`, and a
  Join button. Hide rows the wallet can't cover.
- Ask for the list when the screen opens and on pull-to-refresh. **Don't poll faster than
  every 10 seconds**; there is no push for list changes. A room can fill between the list
  and the tap: handle `room_full` and `game_in_progress` by refreshing the list.
- `room.list` works only in the lobby state. In a room or game it answers
  `room.error invalid_state` (real). Read the list before joining, not after.
- `include_in_play: true` adds games in progress (for watching, where the game supports it).

---

## Bots

From code (`crates/bot-manager`, `crates/ludo-service/src/services/bot_notifier.rs`),
confirmed live for Ludo.

**When a bot joins:** only in a **quick-match** lobby (`match.find`), never in a private room
(`room.create`) or a tournament table. Some games narrow this per mode (the shooter games'
`mode_config.bot_fill`). When `match.find` creates a new lobby, the game server
waits **5 seconds** (`BOT_WAIT_SECONDS` on the game server, default 5). If seats are still
empty, it asks the bot service, which seats one bot per empty seat. The bot readies itself
at once.

Real (Ludo, bot service running), 5.1 seconds after `match.found`:

```json
{"event": "room.user_joined", "data": {"avatar_url": null, "color": "yellow", "is_bot": true, "room_full": true, "seat": 2,
  "user_id": "3fb889f3-b6c9-4768-866e-1f6ba6af8e35", "username": "SolarWizard"}}
{"event": "player.ready_update", "data": {"ready": true, "user_id": "3fb889f3-b6c9-4768-866e-1f6ba6af8e35"}}
```

The player then sent `player.ready` and got `game.started` at once.

**When no bot comes:** the bot service skips a lobby when bots are switched off (for all
games or this game), the stake is outside the game's bot range (Ludo on the development
server: 0 to 10,000) or above the house bot cap, the game already has its most bots
playing (Ludo: 50), or no bot account is free. It asks only once per lobby. Nothing tells
the app; the lobby simply waits for people. This is why the app needs its own search
timeout (Flow A).

**What the app does:**

- A bot is a normal seat. `is_bot` is sent on `room.user_joined` and in `players`; whether to
  show a bot badge is a design decision. Never treat a bot seat differently in the game.
- Bots play by the same rules and timers, and a staked bot game pays out like any other.
- Don't send anything to "request" a bot. There is no such event.

---

## Leaving, cancelling and coming back

| Situation | Send | Get |
|---|---|---|
| Searching, alone or not full | `match.cancel` | `match.cancelled` |
| In a private or listed room, before the start | `room.leave` | `room.left`; others get `room.user_left` |
| In a game | `room.leave` (or the game's forfeit) | A forfeit. Ask first. |
| After the game ends | `room.leave` | `room.left`; back to the lobby state |
| Socket drops in a game | (reconnect, `auth.login`) | Back in the game with the full state, within 30 s (`00-conventions.md`) |

Rules the server enforces (real replies):

- One room at a time. `match.find`, `room.create` or `room.join` while seated answers
  `<domain>.error invalid_state`, for example
  `{"id": "A-3", "event": "match.error", "error": {"code": "invalid_state", "message": "event 'match.find' not allowed in InRoom state"}}`.
  Leave first, or don't show those buttons while seated.
- After a game, `room.leave` before searching again.

---

## How to structure the app

One set of screens and one controller for every game; only `GameLobby` differs.

```dart
abstract class GameLobby {
  String get gameCode;                       // "ludo"
  Stream<LobbyEvent> get events;             // seat changes, ready, game.started, errors
  Future<List<OpenRoom>> listOpenRooms({String? variant});
  Future<RoomSeat> quickMatch(GameMode mode, {String currency = 'token', int stake = 0});
  Future<void> cancelSearch();
  Future<RoomSeat> createRoom(GameMode mode, RoomOptions options);
  Future<RoomSeat> joinByCode(String roomCode);
  Future<void> leaveRoom();
}

class RoomSeat {                              // from match.found, room.created, room.joined
  final String roomId;                        // also the match id
  final String roomCode;
  final int seat;
  final int maxPlayers;
  final String modeCode;
  final String? currency;                     // null on a free private room
  final int? stake;                           // bet_amount; null or 0 = free
  final List<SeatPlayer> players;             // userId, username, seat, isBot, ready
}
```

- `quickMatch` sends `player_count: mode.playerCount` every time.
- Map each game's error codes to one `LobbyError` enum (`notFound`, `roomFull`,
  `gameInProgress`, `alreadyInRoom`, `insufficientFunds`, `invalidMode`, `invalidSettings`,
  `killSwitch`, `invalidState`, `busy`, `internal`), with the server's message kept only for
  `killSwitch`.
- Ludo is the reference implementation (`games/ludo.md`). Add a game by writing its
  `GameLobby` and its board; the lobby screens are reused.

---

## Errors

**Gateway (HTTP):** only the routes in 3 and 4. Shapes as in `00-conventions.md`.

| Status | `error` | Route | Do |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `/live-rooms` with a bad query or id | App bug. |
| 401 | `UNAUTHORIZED` | any | Refresh once (`01-auth.md`). |
| 404 | `NOT_FOUND` | `GET /live-rooms/{id}` | Reload the list. |
| 410 | `MATCHMAKING_RETIRED` | `/matchmaking/...` | App bug; use the socket. |

**Game socket:** the lobby refusals every rooms-family game shares (Ludo real or from
`games/ludo.md`):

| Event | `code` | Show |
|---|---|---|
| `match.find_error` | `invalid_mode` | "This mode isn't available right now." Reload the modes. |
| `match.find_error`, `room.create_error` | `insufficient_funds` | "Not enough tokens/gold for this table." Offer a lower stake or the shop. |
| `match.find_error`, `room.create_error` | `invalid_request` | App bug (bad stake or seat count). |
| `room.create_error` | `invalid_settings` | App bug (a host option the mode doesn't offer). |
| `room.join_error` | `not_found` | "No room with that code." |
| `room.join_error` | `room_full` | "That room is full." Refresh the open tables list. |
| `room.join_error` | `game_in_progress` | "That game has already started." |
| `match.cancel_error` | `invalid_state` | It is a private room: use `room.leave`. |
| `match.error`, `room.error` | `invalid_state` | The socket is in the wrong state (already seated, or in a game). |
| any start request | `kill_switch_engaged` | The operator's message; disable the play buttons (`00-conventions.md`). |
| any | `busy`, `internal_error` | "Something went wrong. Try again." One retry. |

Real `invalid_mode` replies:

```json
{"id": "A-10", "event": "match.find_error", "error": {"code": "invalid_mode", "message": "validation error: unknown ludo mode \"nope_mode\""}}
{"id": "A-12", "event": "match.find_error", "error": {"code": "invalid_mode", "message": "validation error: mode 'casual_2p' supports 2-2 players, not 4"}}
```

---

## Known gaps (the app must cope)

Found while writing this file; reported to the server team, not fixed yet.

1. **`match.find` ignores the mode's seat count.** Without `player_count` it opens a
   2-seat lobby even for a 4-seat mode (real: `casual_4p` gave `max_players: 2`). Always
   send `player_count`.
2. **Mode kinds are not enforced.** `match.find` accepted `friends_room` (real), and
   `room.create` accepted `casual_2p` (real). A friends mode in quick match can then get a
   bot. Only offer each list's own modes (rule in 1).
3. **No search timeout and no "no bot" signal.** A quick-match lobby with no bot waits
   until the player cancels. Use the app-side 60-second prompt.
4. **Bot support is not shown the same way for every game.** Ludo's modes carry no bot
   flag, so the app can't say "a bot will join" in advance; don't promise it. The shooter
   games put `bot_fill` in `mode_config` (ranked Battle Royale says `false`). Follow each
   game's file.
5. **The bot wait time is set on the game server, not in the console.** The console's
   per-game "wait seconds" for bots is not what the game server uses (it uses
   `BOT_WAIT_SECONDS`, 5 s). Don't hard-code 5 seconds in the UI.
6. **No player invite route.** Share the room code outside the game for now.

---

## Done when

- [ ] The game home screen opens the game socket, signs in, and only then shows Quick match,
      Play with friends, Join with code and Open tables.
- [ ] A player who was in a running game and reopens the app lands on the board, not the
      lobby.
- [ ] Quick match on a 2-seat free mode with two phones seats both at one table and starts.
- [ ] Quick match alone gets a bot after about 5 seconds (bot service running), and the game
      starts after the player is ready.
- [ ] Quick match with no bot and no other player shows the 60-second "No players found"
      prompt; Cancel sends `match.cancel` and returns to the lobby.
- [ ] `match.find` always sends `player_count` equal to the mode's `player_count`.
- [ ] The mode picker shows only quick-match modes under Quick match and only friends modes
      under Play with friends.
- [ ] Play with friends: the host sees the code with Copy and Share; a second phone joins with
      it in lower or upper case; both ready; the game starts. No bot ever joins.
- [ ] Join with a wrong code shows "No room with that code."
- [ ] The open tables list shows waiting quick-match lobbies and listed private rooms, and
      Join seats the player; a room that filled meanwhile shows "That room is full" and the
      list refreshes.
- [ ] Cancel is hidden once the game starts; leaving a running game asks first.
- [ ] A staked table the wallet can't cover shows the insufficient funds message.
- [ ] Bingo shows its live rooms from `GET /live-rooms?is_active=true` and joins one over the
      Bingo socket with its `id`.
- [ ] No call goes to `/matchmaking/...`.
- [ ] Every error code above shows a message, not a crash.

---

## Test accounts

Create your own players with Sign up (`01-auth.md`) on the development server, one per phone
(one account can't hold two sockets on one game server). Use free (zero-stake) modes unless
the test is about stakes. Don't use other people's accounts. Bots fill quick-match lobbies
only while the bot service runs on the server; ask the server owner.
