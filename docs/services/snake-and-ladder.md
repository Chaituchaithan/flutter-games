# Flutter hand-off G01: Snake & Ladder (game socket)

How the Flutter app plays Snake & Ladder: quick match, private rooms with friends, the game
itself, power-ups, chat, gifts, reconnecting, rematch and tournament tables. Everything here
goes over Snake & Ladder's WebSocket. The envelope, sign-in, heartbeat and reconnect rules are
in `00-conventions.md`; read that first, along with `01-auth.md`.

Snake & Ladder uses the same room protocol as Ludo (`ludo.md`), so the two apps can share most
of their socket code. The differences are listed in "Differences from Ludo" at the end, and
marked **(not like Ludo)** where they come up.

Checked on 24 Nov 2026 against the running Snake & Ladder server. Four new test players played
nine games over the socket: free private rooms on Quick 50, Classic 100 and Venom played to a
real finish, a quick match a bot filled (played to the finish), a second bot game ended by a
forfeit, a 100-gold staked 1v1 Duel played to the finish with its payout and a rematch, two
reconnects, a 30-second drop and a player leaving mid-game. Frames marked **real** were
captured then. Frames marked **from code** follow the server code
(`crates/snake-and-ladder-service/src/`) and were not seen live.

---

## For the Claude agent: what to build

1. A `SnakeLadderSocket` on top of the shared `GameSocket` (`00-conventions.md`), with one typed
   method per send below and a stream of typed events. Share the room and lobby code with Ludo.
2. A `SnakeLadderController` (state machine) with the socket's states: `lobby` (signed in),
   `room` (seated, waiting), `game`, `result`. It keeps the latest **game state** and redraws
   from it. Never move a token from a local guess; only from server frames.
3. Screens: **Snake & Ladder home** (Quick match, Play with friends, Join with code, open rooms
   list), **Waiting room** (seats, ready buttons, room code to share, the board preview),
   **Board**, **Result**.
4. A board painter driven only by the board the server sends (`board` in `room.created`, or
   `board_size`, `snakes`, `ladders`, `venom_tiles` in the game state; see "The board"), with
   animations driven by `last_action`.
5. A turn timer from `turn_deadline_ms`, using the server clock offset.
6. A power-up bar: the player's owned power-ups (inventory, `11-store.md`), usable before rolling.
7. Reconnect within 30 seconds after a drop, and app-resume handling.
8. Tests: parsing each event below from the samples; the controller's moves through lobby,
   room, game, result; a reconnect that ends in `game.state_sync`, and one that ends in
   `game.final_state`; a game that ends by `game.player_forfeited` (no final `game.state_update`).

---

## Server

```
ws://<host>:1292/ws
```

The gateway gives the catalogue (modes, variants, stakes, power-ups) and the wallet over HTTP;
the socket does the play. A Snake & Ladder match uses these gateway calls (see
`04-game-catalogue.md`, `03-wallet.md` and `11-store.md`):

| Call | Use |
|---|---|
| `GET /games` | Find Snake & Ladder's numeric `id` (code `snake-and-ladder`; `25` on the development server). |
| `GET /games/{id}/modes` | The modes (table below) and each mode's `mode_config` (turn timer, rule options, host choices). |
| `GET /games/{id}/variants` | The boards: `quick_50`, `classic_100`, `venom_100`, `duel`, `team`. |
| `GET /games/{id}/stakes` | The stake tiers per mode and currency, for the quick-match stake picker. |
| `GET /games/{id}/power-ups` | The power-ups, their prices and `max_per_match`. |
| `GET /users/me/inventory` | How many of each power-up the player owns (for the power-up bar). |
| `GET /wallet/balance` | Before a staked game, and again after it ends. |

---

## Modes

From `GET /games/25/modes` on 24 Nov 2026 (10 modes). Seats are the most a mode seats
(`player_count`); the fewest is 2, except Team 2v2 (4).

**Quick match** (`match.find`; no `host_can_choose` in `mode_config`):

| `mode_code` | Name | Board | Seats | Turn timer | Timeouts before out | Ranked |
|---|---|---|---|---|---|---|
| `quick_50` | Quick 50 | `quick_50` | 2 to 4 | 30 s | 3 | no |
| `classic_2` | Classic 1v1 | `classic_100` | 2 | 20 s | 5 | yes |
| `classic_4` | Classic 4 Players | `classic_100` | 2 to 4 | 20 s | 5 | yes |
| `venom` | Venom | `venom_100` | 2 to 4 | 20 s | 5 | yes |
| `duel_ranked` | 1v1 Duel ranked | `classic_100` | 2 | 8 s | 5 | yes |

**With friends** (`room.create`; `mode_config.host_can_choose` present):

| `mode_code` | Name | Board | Seats | Turn timer (host picks) | Host may also set |
|---|---|---|---|---|---|
| `casual` | Casual with Friends | `classic_100` | 2 to 4 | 30 s (20, 30, 45) | `exact_finish`, `extra_turn_on_six`, `capture_sends_home`, `powerups_enabled` |
| `quick_friends` | Quick 50 with Friends | `quick_50` | 2 to 4 | 30 s (20, 30, 45) | as `casual` |
| `venom_friends` | Venom with Friends | `venom_100` | 2 to 4 | 30 s (20, 30, 45) | as `casual`, plus `pu_anti_venom`, `pu_ladder_boost`, `pu_reroll` |
| `duel_casual` | 1v1 Duel casual | `classic_100` | 2 | 8 s (8, 20, 30) | as `casual`, plus `rematch_allowed` |
| `team_2v2` | Team 2v2 | `classic_100` | 4 | 30 s (20, 30, 45) | as `casual`, plus `partners_cannot_capture`, `team_chat`, `shared_ladders` |

Every friends mode allows 5 timed-out turns in a row before the player is out.

- `match.find` with no `mode_code` plays `quick_50`; `room.create` with none plays `casual`
  **(not like Ludo)**.
- Read the list from the gateway rather than hard-coding it: an operator can switch modes off,
  and `match.find` / `room.create` then answer `invalid_mode`.
- The server does not check which list a mode belongs to; keep quick modes on Quick match and
  friends modes on Play with friends (as `05-matchmaking-and-rooms.md` says).
- **Always send `player_count`** on `match.find` (the mode's `player_count`): it defaults to 2.
- Each mode's `mode_config.timer` holds `turn_ms`, `max_timeouts` and, for friends modes,
  `allowed_turn_seconds`.
- Bots: a quick-match lobby no human joins within 5 seconds gets a bot. **Every** mode has bot
  seats switched on today, even those whose `mode_config.bots_fill` is `false` (real: a bot
  joined a `classic_2` lobby after 5 s). Don't use `bots_fill` to tell the player "no bots".

---

## The flow

```
open socket -> connection.established -> auth.login -> auth.login_success      (lobby)

Quick match:   match.find -> match.found -> player.ready ...                   (room)
With friends:  room.create -> room.created (share room_code) -> player.ready ...
Join a friend: room.join {room_code} -> room.joined -> player.ready ...

every seat filled and ready -> game.started                                    (game)

my turn:  (optional) game.action use_powerup -> game.action_ack + game.powerup_used
          game.action roll_dice -> game.action_ack (the server moves the token)
everyone: game.state_update after every roll (also a roll the server makes when a turn runs out)

game.state_update with last_action.game_over: true                             (result)
  or game.player_forfeited with game_over: true (a forfeit, leave or drop ended it)
staked games: game.wallet_update a moment later
then: game.rematch, or room.leave back to the lobby
```

The socket's state names (from `00-conventions.md`) map to these: `Authenticated` = lobby,
`InRoom` = room and result, `InGame` = game.

**There is no pawn choice (not like Ludo).** Each player has one token. A roll moves it at once:
the app sends `roll_dice` and nothing else.

---

## 1. Connect and sign in

As in `00-conventions.md`, with Snake & Ladder's real frames:

```json
// pushed when the socket opens (real)
{"event": "connection.established", "data": {"capabilities": ["auth", "rooms", "chat", "game"], "server_version": "0.1.0", "timestamp": 1795514345832}}

// send
{"id": "A-1", "event": "auth.login", "data": {"token": "<access_token>"}}

// reply (real)
{"id": "A-1", "event": "auth.login_success", "data": {"expires_at": 1795515245, "role": "user", "token": "<access_token>", "user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "username": "wsnldoca1795514218"}}
```

`auth.login_error` codes:

| `code` | Meaning | Do |
|---|---|---|
| `invalid_credentials` | The token is expired or not valid (real: `unauthorized: invalid token: InvalidToken`). | Refresh at the gateway, then retry once. |
| `token_revoked` | The session logged out. | Go to log in. |
| `duplicate` | This player already has a signed-in Snake & Ladder socket (real: `already connected on another socket`). | Close the other socket (another device, or a leaked one), or retry after a few seconds. |
| `invalid_request` | No token. | App bug. |
| `internal_error` | Server trouble. | Retry. |

Before signing in, anything else is refused (real):

```json
{"id": "X-3", "event": "connection.error", "error": {"code": "invalid_state", "message": "event 'room.list' not allowed in Unauthenticated state"}}
```

`auth.refresh` `{token}` -> `auth.token_refreshed` `{user_id, expires_at}` keeps the socket
going with a new token (errors on `auth.token_refresh_error`: `invalid_credentials`,
`user_mismatch`, `token_revoked`). `auth.logout` -> `auth.logged_out` `{revoked}`, then the
server closes the socket; log out only after a game. (From code; same as Ludo.)

If the player was in a running game, the server follows `auth.login_success` with
`game.state_sync` or `game.final_state` (see 7).

---

## 2. Lobby and rooms (signed in, not in a room)

### `room.list` -> `room.list_result`

Open rooms for a lobby list: quick-match lobbies and private rooms whose host listed them.

| Send field | |
|---|---|
| `variant` | Optional: only rooms on this board (`quick_50`, `classic_100`, `venom_100`). |
| `include_in_play` | Optional, default `false`: also games in progress. |

```json
// real: one listed private room
{"id": "B-2", "event": "room.list_result", "data": {"rooms": [
  {"room_id": "06c537b3-3d79-40f2-ae40-3f6337e8578d", "room_code": "06c537b3", "game_type": "snake_and_ladder",
   "board_layout": "quick_50", "variant": "quick_50", "mode_code": "quick_friends", "matchmaking": "private_room",
   "players": 1, "max_players": 2, "status": "waiting", "currency": null, "bet_amount": null, "created_at": 1795514350480}],
  "total": 1}}
```

`board_layout` and `variant` are the same (the board). `matchmaking` is `random` (quick match)
or `private_room`; `status` is `waiting` or `in_progress`.

### `wallet.bet_options` -> `wallet.bet_options` (stake picker for a private room)

**Not in Ludo.** The bets the console's bet ladder offers at the player's balance, for one
currency. Use it for the private-room stake picker: show `bets`, the `locked` ones disabled,
with `default` picked. Allowed in any signed-in state.

```json
// send (real)
{"id": "A-4", "event": "wallet.bet_options", "data": {"currency": "gold"}}

// reply (real), a new player with 500 gold
{"id": "A-4", "event": "wallet.bet_options", "data": {"offer": {
  "currency": "gold", "balance": 500, "band_from": 100, "band_to": 1000,
  "bets": [{"amount": 100, "locked": false}, {"amount": 200, "locked": false}, {"amount": 300, "locked": true},
           {"amount": 500, "locked": true}, {"amount": 750, "locked": true}],
  "default": 200, "custom_step": null, "max_bet": 250}}}
```

- `offer` is `null` when no bet ladder is set: then any stake the wallet covers is taken.
- `max_bet`: the largest bet the balance rules allow now.
- Errors on `wallet.error`: `invalid_request` (currency not `token`/`gold`), `internal_error`.

### `match.find` -> `match.found` (quick match)

| Send field | |
|---|---|
| `mode_code` | Optional; default `quick_50`. A quick-match mode. |
| `player_count` | Optional, 2 to 4 (default 2). Send the mode's `player_count`. |
| `currency` | Optional: `token` (default) or `gold`. |
| `bet_amount` | Optional, default 0 (free). A stake tier from `GET /games/{id}/stakes`. Checked against the wallet now; taken when the game starts. The bet ladder is **not** checked here (only on `room.create`). |

```json
// send (real)
{"id": "A-3", "event": "match.find", "data": {}}

// reply (real): a new lobby, the player alone in it
{"id": "A-3", "event": "match.found", "data": {
  "room_id": "b941f91c-c3b9-41b3-8d41-05ec7630dd8a", "room_code": "b941f91c", "seat": 0,
  "board_layout": "quick_50", "mode_code": "quick_50", "max_players": 2, "currency": "token", "bet_amount": 0,
  "players": [{"seat": 0, "user_id": "927e8d50-80a9-44ba-883d-0ebd693da815", "username": "wsnldocc1795514218"}],
  "rules": {"capture_sends_home": true, "exact_finish": true, "extra_turn_on_six": true, "partners_cannot_capture": true,
            "powerups_enabled": true, "pu_anti_venom": true, "pu_ladder_boost": true, "pu_reroll": true, "ranked": false,
            "rematch_allowed": false, "shared_ladders": false, "team_chat": false, "teams": false, "three_sixes_lose_turn": true}}}
```

`match.found` has no `board` **(not like `room.created`)**: draw the board from
`board_layout` with the tables in "The board", or wait for `game.started`, whose state carries
the snakes and ladders. Then send `player.ready`. Others arrive as `room.user_joined`; a bot
fills an empty seat after about 5 seconds and readies at once (real):

```json
{"event": "room.user_joined", "data": {"countdown_seconds": 5, "room_full": true, "seat": 1, "user_id": "7fc064ae-eaf2-4edd-ae2a-2d465321e4d6", "username": "ShadowChamp"}}
{"event": "player.ready_update", "data": {"ready": true, "user_id": "7fc064ae-eaf2-4edd-ae2a-2d465321e4d6"}}
```

Nothing marks a bot as a bot on the socket: show it like any other player.

`match.cancel` -> `match.cancelled` `{}` stops searching and leaves the lobby (real). It is
refused on `match.cancel_error` with `invalid_state` once the game has started, or in a private
room (use `room.leave`).

`match.find_error` codes (real where marked):

| `code` | Example message |
|---|---|
| `invalid_request` | `player_count must be between 2 and 4` |
| `invalid_mode` | `validation error: mode 'classic_2' supports 2-2 players, not 4` (real) |
| `insufficient_funds` | `insufficient balance for a stake of 99999 gold` (real) |
| `internal_error` | Retry. |

### `room.create` -> `room.created` (private room)

| Send field | |
|---|---|
| `mode_code` | Optional, default `casual`. One of the "with friends" modes. |
| `max_players` | Optional, 2 to 4 (default 2); Team 2v2 needs 4. |
| `turn_timer_sec` | Optional: one of the mode's `allowed_turn_seconds`. **Named `turn_timer_sec`, not Ludo's `turn_seconds`.** |
| `variant` | Optional: another board, only where the mode's `host_can_choose` lists `board_layout` or `variant` (no mode does today). |
| `currency`, `bet_amount` | Optional, for a staked room. A bet above 0 must be one `wallet.bet_options` offers unlocked. |
| `listed` | Optional, default `false`: show the room in `room.list`. Otherwise it is joined by code only. |
| Rule picks | Optional booleans, only the keys the mode's `host_can_choose` lists (see "Modes"). |

There is no `color` (not like Ludo): seats are numbered, and the host is seat 0.

```json
// send (real)
{"id": "A-5", "event": "room.create", "data": {"mode_code": "duel_casual", "max_players": 2, "currency": "gold", "bet_amount": 100,
  "turn_timer_sec": 20, "rematch_allowed": true}}

// reply (real)
{"id": "A-5", "event": "room.created", "data": {
  "room_id": "333a8320-dd44-476d-89cc-0281b7bf7d4f", "room_code": "333a8320", "seat": 0,
  "board_layout": "classic_100", "variant": "classic_100", "mode_code": "duel_casual", "mode_name": "1v1 Duel casual",
  "max_players": 2, "currency": "gold", "bet_amount": 100, "turn_timer_sec": 20, "listed": false,
  "rules": {"capture_sends_home": true, "exact_finish": true, "extra_turn_on_six": true, "partners_cannot_capture": true,
            "powerups_enabled": true, "pu_anti_venom": true, "pu_ladder_boost": true, "pu_reroll": true, "ranked": false,
            "rematch_allowed": true, "shared_ladders": false, "team_chat": false, "teams": false, "three_sixes_lose_turn": true},
  "board": {"size": 100,
            "snakes": {"17": 7, "54": 34, "62": 19, "64": 60, "87": 36, "93": 73, "95": 75, "99": 78},
            "ladders": {"4": 14, "9": 31, "20": 38, "28": 84, "40": 59, "51": 67, "63": 81, "71": 91}}}}
```

- Share `room_code` (8 characters): show it large, with a copy and a share button. `room_id`
  is also the match id once the game starts.
- `board` is the board to draw in the waiting room: `snakes` `{head: tail}`, `ladders`
  `{bottom: top}` (keys are strings), plus `venom_tiles` on a venom board (real:
  `"venom_tiles": [23, 44, 66, 88]`) and `ladder_multipliers` on a Royale board.
- `room.created` has no `players` list (not like Ludo): the host is alone on seat 0.
- `turn_timer_sec` is `null` for an untimed room.

`room.create_error` codes:

| `code` | Example message |
|---|---|
| `invalid_settings` | `validation error: turn_timer_sec must be one of [20, 30, 45] in mode 'quick_friends'` (real); `validation error: mode does not let the host choose 'teams' in mode 'quick_friends'` (real); `max_players must be between 2 and 4` |
| `invalid_mode` | `validation error: unknown snake-and-ladder mode "nope"` (real); also a switched-off mode or the wrong seat count |
| `insufficient_funds` | `insufficient balance for a stake of 1000 gold` (real) |
| `bet_not_offered` | `the bet ladder does not offer 7 gold at a balance of 500` (real). Pick from `wallet.bet_options`. |
| `invalid_request` | `bet_amount` negative or not whole, or `currency` not `token`/`gold`. |
| `kill_switch_engaged`, `internal_error` | See 10. |

### `room.join` -> `room.joined`

| Send field | |
|---|---|
| `room_code` | Required; case doesn't matter (real: `06C537B3` joined `06c537b3`). |

```json
// real
{"id": "B-2", "event": "room.joined", "data": {
  "room_id": "333a8320-dd44-476d-89cc-0281b7bf7d4f", "room_code": "333a8320", "seat": 1,
  "board_layout": "classic_100", "mode_code": "duel_casual", "max_players": 2, "currency": "gold", "bet_amount": 100,
  "players": [{"ready": false, "seat": 0, "user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "username": "wsnldoca1795514218"},
              {"ready": false, "seat": 1, "user_id": "010e63de-39c6-4f67-a43b-1bf339396edb", "username": "wsnldocb1795514218"}],
  "rules": {"...": "as in room.created"},
  "tournament": null}}
```

- Players carry `ready`, but no balances, avatar, colour or `is_bot` (not like Ludo).
- `room.joined` has no `board`: draw it from `board_layout` (see "The board") until
  `game.started` arrives.
- `rules` can be `null` if the server could not read them; the game state carries them again.
- `tournament` (`{tournament_id, round, table_number}` or `null`): see 9.
- A player who dropped out of a running game and joins it again gets `room.joined` with
  `match_id` and `rejoined: true` (and no `mode_code` or `rules`), then `game.state_sync`
  (from code). Joining a finished game answers `game.final_state` instead (real, see 7).

`room.join_error` codes:

| `code` | Show |
|---|---|
| `not_found` | "No room with that code." (real: `no room found for code 'zzzzzzzz'`; also a closed room) |
| `room_full` | "That room is full." |
| `game_in_progress` | "That game has already started." |
| `already_in_room` | Already seated there: go to the waiting room. |
| `not_your_table` | "This tournament table has no seat for you." |
| `invalid_request` | No code sent: app bug. |
| `kill_switch_engaged` | The operator's message. |
| `busy`, `internal_error` | Retry. |

### `room.leave` -> `room.left`

Leaves the room (back to lobby). In a waiting room the seat frees. **During a game, leaving is
a forfeit**: ask "Leave the game? You'll lose." first.

```json
// real
{"id": "B-4", "event": "room.left", "data": {"room_id": "0e946ced-2f09-4879-8a9c-489f65e80b9d"}}
```

`room.leave_error`: `busy` (a move held the match; retry).

### Room broadcasts

```json
// someone took a seat with room.join (real; the joiner gets it too)
{"event": "room.user_joined", "data": {"countdown_seconds": 5, "room_full": true, "seat": 1,
  "user_id": "010e63de-39c6-4f67-a43b-1bf339396edb", "username": "wsnldocb1795514218"}}

// someone left, or their socket dropped (real)
{"event": "room.user_left", "data": {"reason": "disconnected", "user_id": "927e8d50-80a9-44ba-883d-0ebd693da815"}}
```

- `room_full` and `countdown_seconds` (5 when full, else 0) come with `room.join` and bot
  seats; a seat taken by `match.find` sends only `user_id`, `username` and `seat`. Treat both
  as optional. The countdown is a hint only: the game starts when every seat is ready.
- `reason` is `left` or `disconnected`. Mid-game, show "Reconnecting..." on that seat for 30
  seconds.
- A player back after a drop: `room.user_joined` with only `{user_id, reconnected: true}`
  (real). Keep the name and seat you already have.

### Stake errors (`match.find`, `room.create`, `game.rematch`)

| `code` | Meaning | Show |
|---|---|---|
| `insufficient_funds` | The wallet can't cover the stake. | "Not enough tokens/gold for this table." Offer the shop or a lower stake. |
| `bet_not_offered` | `room.create` only: the bet ladder does not offer that bet. | Refresh `wallet.bet_options` and let the player pick again. |
| `invalid_request` | `bet_amount` negative or not whole, or `currency` not `token`/`gold`. | App bug. |
| `internal_error` | The wallet couldn't be read. | Retry. |

---

## 3. Ready and start (in a room)

`player.ready` and `player.unready` both answer `player.ready_update`. The sender gets it
twice: once as the reply (with `id`) and once as the room broadcast (no `id`). Treat them the
same.

```json
// real
{"id": "A-12", "event": "player.ready_update", "data": {"ready": true, "user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18"}}
{"event": "player.ready_update", "data": {"ready": true, "user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18"}}
```

When every seat is filled and ready, the stakes are taken and everyone gets `game.started`
(real, a free Quick 50 room):

```json
{"event": "game.started", "data": {
  "match_id": "c98923ad-fa56-4841-8699-72d34efeec2f",
  "turn_order": ["3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "010e63de-39c6-4f67-a43b-1bf339396edb"],
  "current_turn": 0,
  "tournament": null,
  "state": {
    "match_id": "c98923ad-fa56-4841-8699-72d34efeec2f", "status": "in_progress",
    "board_size": 50,
    "snakes": [[25, 5], [34, 12], [42, 23]],
    "ladders": [[3, 16], [9, 31], [18, 37], [29, 44]],
    "current_turn_user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18",
    "turn_number": 0, "turn_deadline_ms": 1795514399333, "turn_time_ms": 20000, "max_timeouts": 5,
    "winner": null, "royal_stakes": false,
    "dice_seed_hash": "d7dcdbe65ac41aefedb84899ead3472cff3d7dd93c21e9f49177bf87afed3c0b", "dice_seed": null,
    "players": [
      {"user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "seat": 0, "position": 0, "has_started": true,
       "forfeited": false, "timeouts": 0, "skip_turns": 0, "best_multiplier": 0},
      {"user_id": "010e63de-39c6-4f67-a43b-1bf339396edb", "seat": 1, "position": 0, "has_started": true,
       "forfeited": false, "timeouts": 0, "skip_turns": 0, "best_multiplier": 0}],
    "rules": {"...": "as in room.created"}}}}
```

If the stakes can't be taken, the room gets `game.start_error` instead (from code): any stake
taken is refunded, ready flags clear and the room waits again. The reason is in `data`.

```json
{"event": "game.start_error", "data": {"error": "insufficient_funds", "message": "One or more players have insufficient funds to cover the bet"}}
```

`error` is `insufficient_funds`, `bet_deduction_failed` or `start_failed`.

`player.ready_error` codes: `not_found` (room expired), `invalid_state` (already started),
`not_in_room`, `kill_switch_engaged`, `internal_error`.

---

## 4. The game state

Every game frame carries the whole `state`. **Always redraw from the latest `state`.**

| Field | Meaning |
|---|---|
| `status` | `waiting_for_players`, `in_progress` or `completed`. |
| `board_size` | The finish square: 50 or 100. |
| `snakes` | `[[head, tail], ...]`. |
| `ladders` | `[[bottom, top], ...]`. |
| `venom_tiles` | Venom boards only: squares that cost the next turn. Absent otherwise. |
| `ladder_multipliers` | Royale boards only: `[[bottom, multiplier], ...]`. Absent otherwise. |
| `players[]` | In turn order: `user_id`, `seat`, `position` (0 = not on the board yet), `has_started`, `forfeited`, `active_powerups` (absent when none), `timeouts` (timed-out turns in a row), `skip_turns` (turns still to sit out after venom), `best_multiplier`, `team` (0 or 1 in a team game, absent otherwise). |
| `current_turn_user_id` | Whose turn. |
| `turn_number` | Rolls so far in the match. |
| `turn_deadline_ms` | When this turn runs out (epoch ms, server clock); `null` when untimed or over. **Named `turn_deadline_ms`, not Ludo's `turn_deadline`.** |
| `turn_time_ms`, `max_timeouts` | The room's turn length and the timed-out turns allowed in a row. |
| `skipped_turns` | Present after a roll that passed over venom-hit players: their user ids. |
| `winner`, `winners` | The winner (and partner, in a team game), once over. |
| `places` | Once over: every player's user id, 1st place first. |
| `royal_stakes` | The pot is shared by place (Royale modes; none in the catalogue today). |
| `dice_seed_hash`, `dice_seed` | Provably fair dice (see below). `dice_seed` is `null` until the game is over. |
| `rules` | The room's rules, as in `room.created`. |

There is **no `player_names`** in the state (not like Ludo), even after a reconnect. Keep the
names from `room.joined` / `match.found` / `room.user_joined`. After a cold start the app has
none: show "Player" plus the seat, or read the public profiles at the gateway
(`02-profile-and-sessions.md`).

### The board

Squares are numbered 1 to `board_size`. Position 0 is off the board, before the first roll;
every token starts there (`has_started` is always `true` on today's modes: a token moves on any
roll, no six is needed). The first token to reach `board_size` wins.

The server only numbers squares. Draw the grid the classic way: 10 squares a row, the first row
left to right from the bottom-left, the next right to left, and so on (a 50-square board has 5
rows). Draw snakes from head down to tail and ladders from bottom up to top. Build the board
from the server's data, never from a copy in the app; the tables below are for tests and for
drawing a preview before `game.started` (from `engine/layouts.rs`, matching what the server sent
on 24 Nov 2026).

| Board (variant) | Size | Snakes (head to tail) | Ladders (bottom to top) | Venom tiles |
|---|---|---|---|---|
| `quick_50` | 50 | 25-5, 34-12, 42-23 | 3-16, 9-31, 18-37, 29-44 | none |
| `classic_100` (also `duel` and `team`) | 100 | 17-7, 54-34, 62-19, 64-60, 87-36, 93-73, 95-75, 99-78 | 4-14, 9-31, 20-38, 28-84, 40-59, 51-67, 63-81, 71-91 | none |
| `venom_100` | 100 | the 8 classic snakes plus 26-10, 33-12, 46-25, 49-30, 57-41, 69-47, 83-58, 98-79 | the 8 classic ladders | 23, 44, 66, 88 |

Other boards exist in the code but are not offered today (their variants are switched off):
`easy_100`, `medium_100`, `hard_100`, `sprint_50` and `royale_100` (the classic board with ladder
multipliers 20: x2, 28: x3, 51: x2, 71: x2 and venom tiles 23, 46, 69, 88). An operator can
also add boards from the console, so always draw from the server's data.

### How a roll moves the token

From `engine/rules.rs`, with the room's `rules`:

1. **One six-sided die** (two with the Double Dice power-up). The token moves forward by the
   roll from `position`.
2. **Six:** with `extra_turn_on_six`, the same player rolls again. With `three_sixes_lose_turn`,
   the third six in a row is not moved and the turn passes (`lost_turn_consecutive_max`).
3. **Past the finish:** with `exact_finish`, the token stays where it was (`overshot`; a six
   still gives the extra roll). Without it, the token stops on the finish and wins.
4. **Snake head:** slide down to the tail. **Ladder bottom:** climb to the top.
5. **Venom tile** (where it lands after any snake or ladder): the player sits out their next
   turn(s) (1 on today's boards). A six that lands on venom still gives the extra roll first.
6. **Capture** (`capture_sends_home`, on in every mode today): another token on the square
   where the move ends (after any snake or ladder) goes back to 0. No extra turn for it (not
   like Ludo). Partners are spared when `partners_cannot_capture`.
7. **Team games** (`teams`): seats 0 and 2 play seats 1 and 3, turns alternate between the
   teams, and the first partner to finish wins for both. With `shared_ladders`, a partner on the
   same ladder bottom climbs too (`carried`).
8. **Finish** on `board_size`: the game ends at once. With three or four players the others are
   placed by how far they got (`places`).

### Provably fair dice

`dice_seed_hash` (SHA-256 of the seed, hex) is fixed when the game starts; `dice_seed` is shown
once it is over. A "Verify" screen can check every roll: roll k of the match (k from 1) is
`HMAC-SHA256(key = the seed's UTF-8 bytes, message = (k - 1) as a 4-byte big-endian number)`,
first 4 bytes as a big-endian number, `% 6 + 1`. A Double Dice second die uses
`k - 1 + 1000000`; a Reroll uses `k - 1 + 2000000`. Optional for the first release.

---

## 5. Playing a turn (in a game)

All moves are `game.action` with an `action_type`: `roll_dice`, `use_powerup` or `forfeit`
(not like Ludo: no `move_pawn`, `pick_die` or `undo`). Each answers `game.action_ack` (with the
request `id`) or `game.action_error`. The result for **everyone**, the sender included, arrives
as `game.state_update` (or `game.powerup_used`, or `game.player_forfeited`).

Only the player whose turn it is can roll or use a power-up. Disable the dice otherwise.

### `roll_dice`

```json
// send (real)
{"id": "A-22", "event": "game.action", "data": {"action_type": "roll_dice"}}

// reply (real): a 5 from square 13 lands on the ladder at 18 and climbs to 37
{"id": "A-22", "event": "game.action_ack", "data": {"action_type": "roll_dice", "result": {
  "dice_value": 5, "move_type": "climbed_ladder", "from_position": 13, "to_position": 37, "extra_turn": false,
  "landing": {"kind": "ladder", "square": 18},
  "next_turn_user_id": "010e63de-39c6-4f67-a43b-1bf339396edb", "game_over": false, "winner": null}}}
```

| `result` field | Meaning |
|---|---|
| `dice_value` | The roll (with Double Dice: the sum of both dice). |
| `move_type` | What happened (table below). |
| `from_position`, `to_position` | Where the token started and where it ended (after any snake or ladder). |
| `extra_turn` | The same player rolls again. |
| `landing` | `{kind: "snake" or "ladder", square}`: the snake head or ladder bottom it hit. Absent (`null` in `last_action`) for a plain move. |
| `next_turn_user_id` | Who rolls next; `null` once the game is over. |
| `game_over`, `winner` | The game ended on this roll. |
| `overshot` | With `exact_finish`, the square the roll would have reached past the finish. |
| `venom` | `true`: it ended on a venom tile (the player sits out next turn). |
| `captured` | User ids sent back to 0 by this move. |
| `carried` | Partners who climbed the same ladder (team games). |
| `multiplier` | Royale: the ladder's multiplier when above 1. |
| `snake_charm` | `{code, head, tail}` when Anti-Snake or Snake Charmer acted on a snake. |
| `rerolled_from` | Reroll: the first roll, which was replaced. |
| `second_dice_value` | Double Dice: the second die. **Only in the ack**, not in the room's `last_action`. |
| `active_powerups` | The power-ups that acted on this roll. **Only in the ack.** |

The ack leaves out fields that don't apply; `game.state_update`'s `last_action` always has them
(as `null`, `false` or `[]`).

`move_type` values:

| `move_type` | Meaning | Show |
|---|---|---|
| `moved` | A plain move. | Hop the token square by square. |
| `climbed_ladder` | Climbed a ladder. | Hop to `landing.square`, then climb to `to_position`. |
| `bit_by_snake` | Bitten by a snake. | Hop to `landing.square`, then slide to `to_position`. |
| `extra_turn` | Rolled a six (or used Extra Turn): the same player rolls again. **The token may also have hit a snake or ladder**: check `landing` (real: a 6 from 23 hit the ladder at 29 and ended on 44, with `move_type` `extra_turn`). | Animate by `landing`, then "Roll again!". |
| `overshot` | Too far past the finish with `exact_finish`; the token did not move. | Shake the token, "Need exactly N". |
| `lost_turn_consecutive_max` | The third six in a row: no move, the turn passes. | "Three sixes: turn lost." |
| `won` | Reached the finish. | The win animation. |
| `waiting_to_start` | A room that needs a six to start (no mode today): no move yet. | "Roll a six to start." |

### `game.state_update` (to everyone)

Sent after every roll, including one the server played because a turn ran out. Real, a snake
bite (state shortened):

```json
{"event": "game.state_update", "data": {
  "last_action": {"action_type": "roll_dice", "user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "auto_roll": false,
                  "dice_value": 5, "move_type": "bit_by_snake", "from_position": 37, "to_position": 23, "extra_turn": false,
                  "landing": {"kind": "snake", "square": 42}, "venom": false, "multiplier": null, "rerolled_from": null,
                  "captured": [], "carried": [], "overshot": null, "snake_charm": null,
                  "game_over": false, "winner": null, "next_turn_user_id": "010e63de-39c6-4f67-a43b-1bf339396edb"},
  "state": {"current_turn_user_id": "010e63de-39c6-4f67-a43b-1bf339396edb", "turn_number": 10,
            "turn_deadline_ms": 1795514422737, "status": "in_progress", "...": "the whole state",
            "players": [{"user_id": "3d0ee3f1-...", "position": 23, "...": "..."},
                        {"user_id": "010e63de-...", "position": 15, "...": "..."}]}}}
```

More real `last_action` samples (other fields as above):

```json
// a capture: the roller ended on 7, where the other token stood; it goes back to 0
{"user_id": "010e63de-...", "dice_value": 1, "move_type": "moved", "from_position": 6, "to_position": 7,
 "captured": ["3d0ee3f1-7dfd-4195-befd-6d16fa83dc18"], "next_turn_user_id": "3d0ee3f1-..."}

// a capture at a snake's tail: bitten from 33 down to 12, where the other token stood
{"user_id": "547cb599-...", "dice_value": 3, "move_type": "bit_by_snake", "from_position": 30, "to_position": 12,
 "landing": {"kind": "snake", "square": 33}, "captured": ["927e8d50-80a9-44ba-883d-0ebd693da815"]}

// overshoot with exact_finish: 47 + 4 would be 51 on a 50 board
{"user_id": "3d0ee3f1-...", "dice_value": 4, "move_type": "overshot", "from_position": 47, "to_position": 47, "overshot": 51}

// a six onto venom (66): the extra roll comes first, then the player sits out one turn
{"user_id": "547cb599-...", "dice_value": 6, "move_type": "extra_turn", "from_position": 60, "to_position": 66,
 "extra_turn": true, "venom": true, "next_turn_user_id": "547cb599-..."}
// ... and in that state: {"user_id": "547cb599-...", "position": 66, "skip_turns": 1}

// the third six in a row: no move, the turn passes
{"user_id": "547cb599-...", "dice_value": 6, "move_type": "lost_turn_consecutive_max", "from_position": 66, "to_position": 66,
 "next_turn_user_id": "927e8d50-..."}

// the next roll passed over the venom-hit player, so the roller goes again
{"user_id": "927e8d50-...", "dice_value": 4, "move_type": "moved", "from_position": 12, "to_position": 16,
 "next_turn_user_id": "927e8d50-..."}
// ... with state.skipped_turns: ["547cb599-3f15-4c88-9fe0-eeb8487e58fd"]: show "skipped (venom)" on that seat
```

- Animate from `last_action`: the die from `dice_value`, the token hop from `from_position`
  to `landing.square` (if any), then the snake or ladder to `to_position`; then captured
  tokens back to 0. Then set the board to `state`.
- `auto_roll: true`: the turn ran out and the server rolled. Show "Time's up" on that seat.
- **There is no top-level `game_over` (not like Ludo):** read `last_action.game_over`.

### Power-ups: `use_powerup`

Power-ups are bought at the gateway (`11-store.md`; `GET /users/me/inventory` for counts) and
switched on over the socket on the player's own turn, **before** rolling. They act on the next
roll, then are used up (except the two "armed" ones). Real:

```json
{"id": "A-4", "event": "game.action", "data": {"action_type": "use_powerup", "powerup_code": "shield"}}
{"id": "A-4", "event": "game.action_ack", "data": {"action_type": "use_powerup", "powerup_code": "shield", "remaining_quantity": 0}}
// to everyone
{"event": "game.powerup_used", "data": {"active_powerups": ["shield"], "powerup_code": "shield", "user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18"}}
```

| `powerup_code` | Effect (from `engine/power_up.rs`) | Lasts | Price, max per match (24 Nov) | Room rule needed |
|---|---|---|---|---|
| `shield` | A snake landed on is ignored: the token stays on its head. | next roll | 50 tokens, 2 | `powerups_enabled` |
| `double_dice` | Two dice, summed; only a double six counts as a six. | next roll | 75 tokens, 2 | `powerups_enabled` |
| `extra_turn` | Roll again after this roll (not after a win or a third six). | next roll | 100 tokens, 1 | `powerups_enabled` |
| `ladder_boost` | 3 squares further past a ladder's top (if still on the board). | next roll | 60 tokens, 2 | `pu_ladder_boost` |
| `sl_antivenom` | As `shield`, and immune to venom. | next roll | 80 tokens, 2 | `pu_anti_venom` |
| `sl_reroll` | A setback roll (snake, venom or overshoot) is rolled again once; the new roll stands (`rerolled_from`). | next roll | 120 tokens, 1 | `pu_reroll` |
| `sl_grease` | As `ladder_boost`, 5 squares. | next roll | 70 tokens, 2 | `pu_ladder_boost` |
| `sl_anti_snake` | The next snake landed on is ignored (`snake_charm` shows it). | until a snake uses it | 160 gold, 2 | `powerups_enabled` |
| `sl_snake_charmer` | The next snake landed on lifts the token up by the snake's length instead. Refused in ranked rooms. | until a snake uses it | 260 gold, 1 | `powerups_enabled`, not `ranked` |

Real: Anti-Snake armed on the first turn, used 6 rolls later on the snake at 42:

```json
{"action_type": "roll_dice", "user_id": "3d0ee3f1-...", "dice_value": 2, "move_type": "moved", "from_position": 40, "to_position": 42,
 "landing": null, "snake_charm": {"code": "sl_anti_snake", "head": 42, "tail": 23}, "...": "..."}
```

- At most 2 one-roll power-ups can be on at once; armed ones don't count.
- A `shield` save shows as a plain `moved` onto a snake head, with no flag in `last_action`;
  only the roller's ack lists `active_powerups`. To show "Shield!" to everyone, compare
  `to_position` with the snake heads while `shield` or `sl_antivenom` was in that player's
  `active_powerups` before the roll.
- `state.players[].active_powerups` shows what is on now; draw it on the seat.
- Errors (`game.action_error`, `invalid_state`, real messages): `bad request: no 'shield'
  power-ups remaining`, `bad request: 'shield' is already active`, `bad request: unknown
  power-up code: 'magic'`; also `maximum 2 power-ups per turn`, `'x' is switched off in this
  room`, a per-match limit, `not your turn`, `game is not in progress`.

### `forfeit`

`{"action_type": "forfeit"}` gives up. Ask first. With two players the other wins; with more,
the game goes on without the player. See 6.

### `game.action_error`

| `code` | Typical message | Do |
|---|---|---|
| `not_your_turn` | `not your turn` (real) | Resync the UI from the latest state; usually a double tap. |
| `turn_expired` | `turn time is over` | The server rolls for the player; wait for the state update. |
| `game_over` | `game is over` (real) | Show the result. Every action after the end gets this. |
| `game_not_started` | `game has not started yet` | Wait for `game.started`. |
| `not_in_match`, `already_forfeited` | `player not in match`, `player already forfeited` | Back to the lobby or result. |
| `invalid_request` | `unknown action_type: 'jump'` (real) | App bug. |
| `invalid_state` | A refused power-up (see above). | Show the message. |
| `not_found` | `match not found: ...` | The game is gone: back to the lobby. |
| `busy` | lock timeout | Retry once. |

These codes differ from Ludo's, which uses `invalid_state` for most of them.

### Timers

- Show a ring on the current player's seat counting down to `turn_deadline_ms` (server clock,
  see "Times" in `00-conventions.md`). Bots' turns have a deadline too.
- When a turn runs out the server rolls for the player (`auto_roll: true`) and adds 1 to that
  player's `timeouts` (real: the 20-second turn ran out after 20.2 s). Rolling by hand resets
  it to 0. After `max_timeouts` timed-out turns in a row the player is out
  (`game.player_forfeited`, reason `timeout`). Warn when `timeouts` reaches `max_timeouts - 1`:
  "Play your turn or you'll be removed."
- There is no match clock (no Rush mode).

---

## 6. The end of a game

A game ends in one of two ways. Handle both. Either way the socket returns to the room state.

**A real finish** (real): the winning roll's `game.state_update` has `last_action.game_over:
true` and the final state.

```json
{"event": "game.state_update", "data": {
  "last_action": {"action_type": "roll_dice", "user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "auto_roll": false,
                  "dice_value": 3, "move_type": "won", "from_position": 47, "to_position": 50, "landing": null,
                  "game_over": true, "winner": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "next_turn_user_id": null, "...": "..."},
  "state": {"status": "completed", "winner": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18",
            "winners": ["3d0ee3f1-7dfd-4195-befd-6d16fa83dc18"],
            "places": ["3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "010e63de-39c6-4f67-a43b-1bf339396edb"],
            "dice_seed": "91400fea-7494-4536-988d-360ab706479c", "turn_deadline_ms": null, "turn_number": 19, "...": "..."}}}
```

**A forfeit** (gave up, left, dropped, timed out): only `game.player_forfeited` arrives, **with
no `game.state_update` after it (not like Ludo)**. Real, the last opponent gave up:

```json
{"id": "A-4", "event": "game.action_ack", "data": {"action_type": "forfeit"}}
{"event": "game.player_forfeited", "data": {"user_id": "547cb599-3f15-4c88-9fe0-eeb8487e58fd", "reason": "manual",
  "game_over": true, "winner_id": "927e8d50-80a9-44ba-883d-0ebd693da815",
  "current_turn_user_id": "927e8d50-80a9-44ba-883d-0ebd693da815", "turn_deadline_ms": null}}
```

When `game_over` is `true`, show the result from `winner_id`; places are the winner first, then
the others by `position` in the last state you have. With three or four players and
`game_over: false`, mark that seat out and carry on: `current_turn_user_id` and
`turn_deadline_ms` say whose turn it is now.

`reason`: `manual` (gave up), `left` (`room.leave` mid-game, real), `disconnected` (not back
within 30 s, real), `timeout` (too many timed-out turns; **`timeout`, not Ludo's `timeouts`**),
`no_show` (tournament), `bot_forfeit` (a bot gave up).

**Result screen:** for a staked game, wait for `game.wallet_update` (a moment after the end;
free games send none). Real, a 100-gold 1v1 Duel, about 0.1 s after the win:

```json
{"event": "game.wallet_update", "data": {"match_id": "333a8320-dd44-476d-89cc-0281b7bf7d4f",
  "pot_amount": 200, "rake_amount": 10, "royal_stakes": false,
  "payouts": [{"user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "amount": 190, "result": "win", "place": 1},
              {"user_id": "010e63de-39c6-4f67-a43b-1bf339396edb", "amount": 0, "result": "loss", "place": 2}]}}
```

- The winner takes the pot less 5% (partners split it in a team game). Each payout has a
  `place` (not in Ludo). `result` is `win`, `loss`, `forfeit` (a player who forfeited) or
  `draw`. With `royal_stakes: true` the pot is shared by place and ladder multipliers instead.
- Show the player's own `amount`, then re-read `GET /wallet/balance` (real: the winner went
  from 500 to 590 gold, the loser to 400). The ledger rows are in `03-wallet.md`.

### Rematch

With `rules.rematch_allowed` on (**not Ludo's `rules.rematch`**; host option in `duel_casual`,
on in `duel_ranked`), `game.rematch` (no fields) opens a new private room with the same mode,
board, seats, stake and rules, with the sender on seat 0, and answers `room.created`. The old
room gets the offer (real):

```json
{"id": "A-28", "event": "room.created", "data": {"room_code": "091f250f", "room_id": "091f250f-f47c-426f-a142-76544c7cccd9", "...": "as room.created"}}
{"event": "game.rematch_offered", "data": {"from_user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "room_code": "091f250f",
  "room_id": "091f250f-f47c-426f-a142-76544c7cccd9"}}
```

- The sender gets the offer too: ignore an offer whose `from_user_id` is the player.
- Show "<name> wants a rematch" with a Join button: send `room.leave`, then `room.join` with
  that `room_code` (real: `room.join` is refused while still in the old room).
- `game.rematch_error`: `not_found` (the old game expired), `invalid_state` (real: `a rematch
  needs a finished game you played, with Rematch on`), `invalid_mode`, stake codes.

Otherwise `room.leave` returns to the lobby. Until then, `room.create` and `room.join` are
refused (`room.error`, `invalid_state`, real).

---

## 7. Reconnect

When the socket drops mid-game, the others get `room.user_left` (`disconnected`) and the
player has **30 seconds**:

1. Open a new socket, wait for `connection.established`, send `auth.login`.
2. The server sends one of:
   - `game.state_sync` `{match_id, state}`: the game is still on and the player is back in
     it. Redraw everything. Others get `room.user_joined` `{user_id, reconnected: true}`.
   - `game.final_state` `{match_id, room_id, read_only: true, state}`: the game ended while
     away. Show the result, read-only. Others get `room.user_joined` (reconnected), then
     `room.user_left` (`left`) at once.
   - Nothing more: no game to go back to. Go to the lobby.
3. Load missed chat with `chat.history` if needed.

Real (state shortened):

```json
{"id": "A-1", "event": "auth.login_success", "data": {"user_id": "927e8d50-80a9-44ba-883d-0ebd693da815", "...": "..."}}
{"event": "game.state_sync", "data": {"match_id": "23defa50-a780-41f8-b7c6-4b33c642b2b0", "state": {
  "status": "in_progress", "current_turn_user_id": "927e8d50-80a9-44ba-883d-0ebd693da815", "turn_number": 6,
  "turn_deadline_ms": 1795514585085, "turn_time_ms": 45000, "...": "the whole state"}}}

// another drop, and the opponent gave up meanwhile
{"event": "game.final_state", "data": {"match_id": "23defa50-a780-41f8-b7c6-4b33c642b2b0", "room_id": "23defa50-a780-41f8-b7c6-4b33c642b2b0",
  "read_only": true, "state": {"status": "completed", "winner": "927e8d50-80a9-44ba-883d-0ebd693da815",
  "places": ["927e8d50-...", "547cb599-..."], "dice_seed": "7600dfa2-f761-458c-a42d-75f701705a0c", "...": "..."}}}
```

`state` in `game.final_state` is `null` once the finished game has expired.

After 30 seconds the player is out (real, about 30 s after the drop):

```json
{"event": "game.player_forfeited", "data": {"user_id": "547cb599-3f15-4c88-9fe0-eeb8487e58fd", "reason": "disconnected",
  "game_over": true, "winner_id": "927e8d50-80a9-44ba-883d-0ebd693da815",
  "current_turn_user_id": "927e8d50-80a9-44ba-883d-0ebd693da815", "turn_deadline_ms": null}}
```

On a cold start with a stored game (the app was killed), do the same: sign in on a new socket
and wait a moment for `game.state_sync` before showing the lobby. `room.join` with the stored
room code also works (from code): it answers `room.joined` (`rejoined: true`) and
`game.state_sync`, or `game.final_state` for a finished game (real).

---

## 8. Chat and gifts (in a room or game)

### Quick chat

Only 12 preset lines are accepted, exactly: `Good game!`, `Nice move!`, `Hurry up!`,
`Well played!`, `Good luck!`, `Oops!`, `Wow!`, `Thanks!`, `Sorry!`, `Ha ha!`, `Oh no!`,
`Let's go!`. Show them as buttons and translate on screen; send the English text.

```json
// send (real): no reply of its own
{"id": "A-10", "event": "chat.send", "data": {"message": "Good luck!"}}

// everyone, the sender too (real)
{"event": "chat.message", "data": {"from_user_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "message": "Good luck!",
  "timestamp": 1795514377540, "username": "wsnldoca1795514218"}}
```

- `team: true` sends to the partner only (team games with `rules.team_chat`); the line then
  carries `team: true`.
- `chat.history` `{limit}` (1 to 200, default 50) -> `chat.history_result` `{messages}`,
  oldest first (real).
- `chat.send_error` (real): `invalid_request` (`only predefined chat messages are allowed`),
  `invalid_state` (`team chat is not on in this room`; also "you have no partner yet").

### Gifts

`gift.send` pays tokens or gold to another player in the same room, from the sender's wallet
at once. Same as Ludo.

| Field | |
|---|---|
| `receiver_id` | Required: another player in the room. |
| `amount` | Required: a whole number above 0. |
| `currency` | Optional: `token` (default) or `gold`. |
| `item_type` | Optional label to show, for example `rose` (default `gift`). |
| `message` | Optional, up to 200 characters. |

```json
// send (real)
{"id": "B-8", "event": "gift.send", "data": {"receiver_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "amount": 1, "currency": "token",
  "item_type": "rose", "message": "gl"}}
// reply (real)
{"id": "B-8", "event": "gift.send_ack", "data": {"amount": 1, "currency": "token", "gift_id": "bc7a4ce0-a9ed-4a20-a12b-85859335116a", "status": "ok"}}
// everyone (real)
{"event": "gift.received", "data": {"gift_id": "bc7a4ce0-a9ed-4a20-a12b-85859335116a", "sender_id": "010e63de-39c6-4f67-a43b-1bf339396edb",
  "sender_name": "wsnldocb1795514218", "receiver_id": "3d0ee3f1-7dfd-4195-befd-6d16fa83dc18", "item_type": "rose",
  "amount": 1, "currency": "token", "message": "gl", "timestamp": 1795514382358}}
```

Errors on `gift.send_error`: `invalid_request`, `not_in_room` (real: `receiver is not another
player in your room`, also for a gift to oneself), `insufficient_funds`, `gift_quota_exceeded`
(10 a day, 50 a week, shared with the gateway's gifts), `internal_error`. Ask to confirm before
sending; it can't be undone.

---

## 9. Tournament tables

From code; same as Ludo. A tournament gives the player a `room_code` for their table (see
`06-tournaments.md`). Join it with `room.join`; the seat is reserved. `room.joined` and
`game.started` carry `tournament` `{tournament_id, round, table_number}`: show "Round N,
Table T". Tournament tables have no stake and no rematch. At the table's seat deadline the game
starts with whoever came; each no-show gets `game.player_forfeited` with reason `no_show`
(one player left wins by walkover).

If the table is cancelled, the room gets `game.cancelled` `{match_id, reason}`: the game ends
with no result, nothing is paid, and the room closes. `reason` is `no_players` (nobody came),
`start_failed` (the table could not start after about a minute of tries) or the reason the
tournament engine gave. Show "This table was cancelled" and go back to the tournament screen.

---

## 10. Errors summary

| Event | When |
|---|---|
| `<request>_error` (for example `room.join_error`) | The request was refused; `error.code` as listed per request. |
| `<domain>.error` (`room.error`, `match.error`, `player.error`, `game.error`, `chat.error`, `gift.error`, `auth.error`) | The request isn't allowed in the socket's current state. |
| `wallet.error` | `wallet.bet_options` refused. |
| `connection.error` | `unknown_event` (real: `unknown event 'room.dance'`), `invalid_request` (not a JSON envelope), `rate_limited` (over 30 frames a second), `invalid_state` (not signed in). |
| `connection.kicked` | The app read too slowly; the socket closes. Reconnect. |
| `auth.session_expired` | The token expired on the socket; it closes. Refresh and reconnect. |

Real wrong-state replies:

```json
{"id": "A-2", "event": "game.error", "error": {"code": "invalid_state", "message": "event 'game.action' not allowed in Authenticated state"}}
{"id": "A-18", "event": "room.error", "error": {"code": "invalid_state", "message": "event 'room.create' not allowed in InGame state"}}
```

`kill_switch_engaged` on `room.create`, `room.join`, `match.find`, `player.ready` or
`game.rematch`: an operator paused new Snake & Ladder games. Show `error.message` and disable
the play buttons; running games carry on.

---

## Differences from Ludo

For an app that already speaks Ludo's socket (`ludo.md`):

| Topic | Ludo | Snake & Ladder |
|---|---|---|
| Port | 1285 | 1292 |
| Moves | `roll_dice`, `move_pawn`, `pick_die`, `undo`, `use_powerup`, `forfeit` | `roll_dice`, `use_powerup`, `forfeit` (the server moves the one token) |
| Default modes | `casual_2p` / `friends_room` | `quick_50` / `casual` |
| Private room timer field | `turn_seconds` | `turn_timer_sec` |
| Seat pick | `color` | none (seat order) |
| Stake picker | `GET /games/{id}/stakes` | also `wallet.bet_options`; `room.create` refuses `bet_not_offered` |
| `room.created` | `players`, `color` | `board`, `turn_timer_sec`; no `players` |
| Room player entries | balances, avatar, `is_bot`, colour | `user_id`, `username`, `seat`, `ready` only |
| Deadline field | `turn_deadline` | `turn_deadline_ms` |
| `game.state_update` end flag | top-level `game_over` | `last_action.game_over` |
| Game ended by forfeit | `game.player_forfeited`, then a final `game.state_update` | `game.player_forfeited` only |
| Timeout forfeit reason | `timeouts` | `timeout` |
| `game.action_error` codes | mostly `invalid_state` | `not_your_turn`, `turn_expired`, `game_over`, `game_not_started`, ... |
| Names after reconnect | `state.player_names` | none |
| Capture | extra turn | no extra turn |
| Rematch rule | `rules.rematch` | `rules.rematch_allowed` |
| Payouts | `user_id`, `amount`, `result` | also `place`; `royal_stakes` flag |

---

## Done when

- [ ] Quick match `quick_50` finds a game (a bot joins when no one else does) and plays to the
      end.
- [ ] Play with friends: create a room, share the code, a second phone joins with it, both
      ready, and the game starts. The waiting room shows the board from `room.created`.
- [ ] A staked room offers the bets from `wallet.bet_options`, shows `insufficient_funds` and
      `bet_not_offered`, and after the game shows the payout and the new balance.
- [ ] Rolls animate the die, the hop, ladders, snakes, captures, overshoots and extra rolls on
      both phones, from `last_action` only.
- [ ] A venom board shows the venom tiles, the "sits out" mark and the skipped turn.
- [ ] A turn left to run out is rolled by the server and shows "Time's up"; the warning shows
      before the last allowed timeout.
- [ ] A power-up bought at the store can be switched on before rolling and shows on both phones.
- [ ] Turning Wi-Fi off for 10 seconds mid-game and back on returns to the same game.
- [ ] Killing the app mid-game and reopening it within 30 seconds returns to the game, with
      names shown.
- [ ] Forfeit and leave both ask first, and a 2-player game ending by forfeit shows the result
      from `game.player_forfeited` alone.
- [ ] Rematch: one player asks, the other sees the offer and joins; the asker sees no offer.
- [ ] Quick chat lines appear on both phones; a gift moves the amount between wallets.
- [ ] Every error code above shows a message, not a crash.
- [ ] No token appears in any log.

---

## Testing on the development server

- Two phones (or a phone and an emulator) with two different accounts; one account can't hold
  two Snake & Ladder sockets (`duplicate`).
- The Snake & Ladder debug page at `http://<host>:1292/debug/ui` can be the second player, and
  shows this same protocol reference (and the gateway's HTTP API) after signing in.
- Quick 50 games end in under a minute of rolling; Classic 100 in a few minutes.
- Bots fill quick-match lobbies only while the bot service runs on the server; ask the server
  owner.
- Debug servers also take `game.action` `debug_set_square` `{square}` to move a token for a
  test. Apps must never send it: live servers answer `unknown action_type`.
