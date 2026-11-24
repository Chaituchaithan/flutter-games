# Flutter hand-off G02: Ludo (game socket)

How the Flutter app plays Ludo: quick match, private rooms with friends, the game itself,
chat, gifts, reconnecting, rematch and tournament tables. Everything here goes over Ludo's
WebSocket. The envelope, sign-in, heartbeat and reconnect rules are in `00-conventions.md`;
read that first, along with `01-auth.md`.

Checked on 24 Nov 2026: two test players played free private-room games against the running
Ludo server (login, create, join, ready, start, rolls, chat, forfeit). Frames marked
**real** were captured then. The other samples follow the server's own protocol reference
(served by its debug page), which is generated from the server code.

---

## For the Claude agent: what to build

1. A `LudoSocket` on top of the shared `GameSocket` (`00-conventions.md`), with one typed
   method per send below and a stream of typed events.
2. A `LudoController` (state machine) with the socket's states: `lobby` (signed in),
   `room` (seated, waiting), `game`, `result`. It keeps the latest **game state** and redraws
   from it. Never move pieces from local guesses; only from server frames.
3. Screens: **Ludo home** (Quick match, Play with friends, Join with code, open rooms list),
   **Waiting room** (seats, ready buttons, room code to share), **Board**, **Result**.
4. A board painter driven only by `state` (see "The board"), with animations driven by
   `last_action`.
5. Turn timer and Rush clock from `turn_deadline` / `match_deadline`, using the server clock
   offset.
6. Reconnect within 30 seconds after a drop, and app-resume handling.
7. Tests: parsing each event below from the samples; the controller's moves through
   lobby, room, game, result; a reconnect that ends in `game.state_sync`, and one that ends in
   `game.final_state`.

---

## Server

```
ws://<host>:1285/ws
```

The gateway gives the catalogue (modes, variants, stakes) and the wallet over HTTP; the
socket does the play. A Ludo match uses these gateway calls (see `04-game-catalogue.md` and
`03-wallet.md`):

| Call | Use |
|---|---|
| `GET /games` | Find Ludo's numeric `id` (code `ludo`; `1` on the development server). |
| `GET /games/{id}/modes` | The modes (table below) and each mode's `mode_config` (turn timer, rule options). |
| `GET /games/{id}/variants` | `classic`, `quick`, `teams`, `rush`, `duel`, `magic`. |
| `GET /games/{id}/stakes` | The stake tiers per mode and currency, for the stake picker. |
| `GET /wallet/balance` | Before a staked game, and again after it ends. |

---

## Modes

From `GET /games/1/modes` on 24 Nov 2026. Seats are the most a mode seats.

**Quick match** (`match.find`; a bot joins a lobby no human joins within 5 seconds):

| `mode_code` | Name | Variant | Seats | Turn timer | Ranked |
|---|---|---|---|---|---|
| `casual_2p` | Casual 2 Players | classic | 2 | 10 s | no |
| `casual_4p` | Casual 4 Players | classic | 4 | 10 s | no |
| `ranked_2p` | Ranked 2 Players | classic | 2 | 10 s | yes |
| `ranked_4p` | Ranked 4 Players | classic | 4 | 10 s | yes |
| `quick_2p` | Quick 2 Players | quick | 2 | 10 s | no |
| `quick_4p` | Quick 4 Players | quick | 4 | 10 s | no |
| `teams_2v2` | Teams 2 vs 2 | teams | 4 | 10 s | no |
| `classic_no_safe` | Classic, no safe squares | classic | 4 | 10 s | no |
| `duel_casual` | 1v1 Duel casual | duel | 2 | 10 s | no |
| `duel_ranked` | 1v1 Duel ranked | duel | 2 | 10 s | yes |
| `magic_4p` | Magic Ludo | magic | 4 | 10 s | no |
| `rush_4p` | Rush | rush | 4 | 10 s | no |

**With friends** (`room.create`; bots never join):

| `mode_code` | Name | Variant | Seats | Default turn timer |
|---|---|---|---|---|
| `friends_room` | Play with Friends | classic | 2 to 4 | 15 s (host picks 10, 15 or 20) |
| `quick_friends` | Quick with friends | quick | 2 to 4 | 15 s |
| `rush_friends` | Rush with friends | rush | 2 to 4 | 15 s |
| `duel_friends` | 1v1 Duel with friends | duel | 2 | 15 s |
| `magic_friends` | Magic Ludo with friends | magic | 2 to 4 | 15 s |
| `team_friends` | Team 2v2 with friends | teams | 4 | 15 s |

Read the list from the gateway rather than hard-coding it: an operator can switch modes off,
and `match.find` / `room.create` then answer `invalid_mode`.

Each mode's `mode_config.timer` holds `turn_ms` and `max_timeouts` (3 on the development
server): a player whose turn runs out that many times in a row is out of the game.

---

## The flow

```
open socket -> connection.established -> auth.login -> auth.login_success      (lobby)

Quick match:   match.find -> match.found -> player.ready ...                   (room)
With friends:  room.create -> room.created (share room_code) -> player.ready ...
Join a friend: room.join {room_code} -> room.joined -> player.ready ...

every seat filled and ready -> game.started                                    (game)

my turn:  game.action roll_dice -> game.action_ack
          (if must_select_pawn) game.action move_pawn -> game.action_ack
everyone: game.state_update after every roll, move, undo, forfeit and timed-out turn

game.state_update with game_over: true                                         (result)
staked games: game.wallet_update a moment later
then: game.rematch, or room.leave back to the lobby
```

The socket's state names (from `00-conventions.md`) map to these: `Authenticated` = lobby,
`InRoom` = room and result, `InGame` = game.

---

## 1. Connect and sign in

As in `00-conventions.md`, with Ludo's real frames:

```json
// pushed when the socket opens (real)
{"event": "connection.established", "data": {"capabilities": ["auth", "rooms", "chat", "game"], "server_version": "0.1.0", "timestamp": 1795507710040}}

// send
{"id": "A-2", "event": "auth.login", "data": {"token": "<access_token>"}}

// reply (real)
{"id": "A-2", "event": "auth.login_success", "data": {"expires_at": 1795508609, "role": "user", "token": "<access_token>", "user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "username": "fdoc7419"}}
```

`auth.login_error` codes:

| `code` | Meaning | Do |
|---|---|---|
| `invalid_credentials` | The token is expired or not valid. | Refresh at the gateway, then retry once. |
| `token_revoked` | The session logged out. | Go to log in. |
| `duplicate` | This player already has a signed-in Ludo socket. | Close the other socket (another device, or a leaked one), or retry after a few seconds. |
| `invalid_request` | No token. | App bug. |
| `internal_error` | Server trouble. | Retry. |

Before signing in, anything else is refused (real):

```json
{"id": "A-1", "event": "connection.error", "error": {"code": "invalid_state", "message": "event 'room.list' not allowed in Unauthenticated state"}}
```

`auth.refresh` `{token}` -> `auth.token_refreshed` `{user_id, expires_at}` keeps the socket
going with a new token (errors on `auth.token_refresh_error`: `invalid_credentials`,
`user_mismatch`, `token_revoked`). `auth.logout` -> `auth.logged_out` `{revoked}`, then the
server closes the socket; log out only after a game.

---

## 2. Lobby and rooms (signed in, not in a room)

### `room.list` -> `room.list_result`

Open rooms for a lobby list: quick-match lobbies and private rooms whose host listed them.

| Send field | |
|---|---|
| `variant` | Optional: only this variant. |
| `include_in_play` | Optional, default `false`: also games in progress. |

```json
// real
{"id": "A-6", "event": "room.list_result", "data": {"rooms": [], "total": 0}}
```

Each room: `room_id`, `room_code`, `game_type`, `variant`, `mode_code`, `matchmaking`
(`random` or `private_room`), `players`, `max_players`, `status` (`waiting` or
`in_progress`), `currency`, `bet_amount`, `created_at` (epoch ms).

### `match.find` -> `match.found` (quick match)

| Send field | |
|---|---|
| `mode_code` | Optional; default `casual_2p` (2 seats) or `casual_4p`. |
| `player_count` | Optional, 2 to 4 (default 2); must fit the mode. |
| `currency` | Optional: `token` (default) or `gold`. |
| `bet_amount` | Optional, default 0 (free). A stake tier from `GET /games/{id}/stakes`. Checked against the wallet now; taken when the game starts. |

`match.found` seats the player in a lobby (alone if new): `room_id`, `room_code`,
`mode_code`, `max_players`, `bet_amount`, `currency`, `seat`, `players` [`user_id`,
`username`, `seat`]. Then send `player.ready`. Others arrive as `room.user_joined`; a bot
fills an empty lobby after about 5 seconds (development: only while the bot service runs).

`match.cancel` -> `match.cancelled` stops searching and leaves the lobby (refused with
`invalid_state` once the game has started, or in a private room: use `room.leave`).

`match.find_error` codes: `invalid_request` (player_count), `invalid_mode`, and the stake
codes below.

### `room.create` -> `room.created` (private room)

| Send field | |
|---|---|
| `mode_code` | Optional, default `friends_room`. One of the "with friends" modes. |
| `max_players` | Optional, 2 to 4 (default 2); a team game needs 4. |
| `color` | Optional: the host's seat, `0` red, `1` green, `2` yellow, `3` blue (default 0). |
| `turn_seconds` | Optional: one of the mode's allowed times (10, 15 or 20). |
| `currency`, `bet_amount` | Optional, for a staked room. |
| `listed` | Optional, default `false`: show the room in `room.list`. Otherwise it is joined by code only. |
| Rule picks | Optional booleans, only the keys the mode's `mode_config.host_can_choose` lists (for `friends_room`: `extra_turn_on_six`, `capture_extra_turn`, `three_sixes_lose_turn`, `safe_squares`, `powerups_allowed`). |

```json
// send (real)
{"id": "A-7", "event": "room.create", "data": {"mode_code": "friends_room", "max_players": 2, "turn_seconds": 15}}

// reply (real)
{"id": "A-7", "event": "room.created", "data": {
  "room_id": "1865dd5d-a808-430f-8bf0-a070fe833b1b", "room_code": "1865dd5d",
  "seat": 0, "color": "red", "max_players": 2, "board_layout": "standard",
  "mode_code": "friends_room", "mode_name": "Play with Friends", "variant": "classic",
  "listed": false, "currency": null, "bet_amount": null,
  "rules": {"auto_roll": false, "auto_roll_ms": 5000, "capture_extra_turn": true, "capture_sends_home": true,
            "double_dice": false, "extra_turn_on_six": true, "finished_partner_rolls": false, "match_clock_ms": null,
            "partners_cant_capture": false, "powerups_allowed": true, "progress_scoring": true, "rematch": true,
            "safe_squares": true, "shield": false, "six_to_start": true, "start_on_board": 0, "team_chat": false,
            "teams": false, "three_sixes_lose_turn": true, "undo": false, "win_by": "all_home"},
  "players": [{"user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "username": "fdoc7419", "seat": 0, "color": "red",
               "balance_tokens": 100, "balance_gold": 500, "avatar_url": null, "is_bot": false}]}}
```

Share `room_code` (8 characters) with friends: show it large, with a copy and a share button.
`room_id` is also the match id once the game starts.

`room.create_error` codes: `invalid_settings` (seats, colour, turn time or a rule pick the
mode doesn't offer), `invalid_mode`, the stake codes below, `kill_switch_engaged`,
`internal_error`.

### `room.join` -> `room.joined`

| Send field | |
|---|---|
| `room_code` | Required; case doesn't matter. |
| `color` | Optional: the seat wanted, 0 to 3, in a 3- or 4-seat room. |

```json
// real
{"id": "B-2", "event": "room.joined", "data": {
  "room_id": "1865dd5d-a808-430f-8bf0-a070fe833b1b", "room_code": "1865dd5d",
  "seat": 2, "color": "yellow", "max_players": 2, "board_layout": "standard",
  "mode_code": "friends_room", "currency": null, "bet_amount": null,
  "players": [
    {"user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "username": "fdoc7419", "seat": 0, "color": "red", "ready": false,
     "balance_tokens": null, "balance_gold": null, "avatar_url": null, "is_bot": false},
    {"user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "username": "gfdoc7419", "seat": 2, "color": "yellow", "ready": false,
     "balance_tokens": 0, "balance_gold": 0, "avatar_url": null, "is_bot": false}]}}
```

- Balances are filled in for the joining player only; others are `null`.
- `tournament` (`{tournament_id, round, table_number}` or `null`): show "Round N, Table T" on
  a tournament table.
- A player who dropped out of a running game and joins it again gets `room.joined` with
  `match_id` and `rejoined: true`, then `game.state_sync` (see 6). Joining a finished game
  answers `game.final_state` instead.

`room.join_error` codes:

| `code` | Show |
|---|---|
| `not_found` | "No room with that code." (also: closed, or the game is over) |
| `room_full` | "That room is full." |
| `game_in_progress` | "That game has already started." |
| `already_in_room` | Already seated there: go to the waiting room. |
| `not_your_table` | "This tournament table has no seat for you." |
| `kill_switch_engaged` | The operator's message. |
| `busy`, `internal_error` | Retry. |

### `room.leave` -> `room.left`

Leaves the room (back to lobby). In a waiting room the seat frees. **During a game, leaving is
a forfeit**: ask "Leave the game? You'll lose." first.

### Room broadcasts

```json
// someone took a seat (real; the joiner gets it too)
{"event": "room.user_joined", "data": {"avatar_url": null, "color": "yellow", "is_bot": false, "room_full": true, "seat": 2,
  "user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "username": "gfdoc7419"}}

// someone left, or their socket dropped
{"event": "room.user_left", "data": {"user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "reason": "disconnected"}}
```

`reason` is `left` or `disconnected`. Mid-game, show "Reconnecting..." on that seat for 30
seconds.

### Stake errors (`match.find`, `room.create`, `game.rematch`)

| `code` | Meaning | Show |
|---|---|---|
| `insufficient_funds` | The wallet can't cover the stake. | "Not enough tokens/gold for this table." Offer the shop or a lower stake. |
| `invalid_request` | `bet_amount` negative or not whole, or `currency` not `token`/`gold`. | App bug. |
| `internal_error` | The wallet couldn't be read. | Retry. |

---

## 3. Ready and start (in a room)

`player.ready` and `player.unready` both answer `player.ready_update`. The sender gets it
twice: once as the reply (with `id`) and once as the room broadcast (no `id`). Treat them the
same.

```json
// real
{"id": "A-8", "event": "player.ready_update", "data": {"ready": true, "user_id": "a397bea2-550b-4702-bfe3-5a336b68831b"}}
{"event": "player.ready_update", "data": {"ready": true, "user_id": "a397bea2-550b-4702-bfe3-5a336b68831b"}}
```

When every seat is filled and ready, the stakes are taken and everyone gets `game.started`
(real, pawns shortened to one per player):

```json
{"event": "game.started", "data": {
  "match_id": "6b646db4-762d-4e8d-8d04-3cde9f97975b",
  "turn_order": ["a397bea2-550b-4702-bfe3-5a336b68831b", "a1164ecb-e4ff-4db2-8125-b29b4691146c"],
  "current_turn": 0,
  "tournament": null,
  "state": {
    "match_id": "6b646db4-762d-4e8d-8d04-3cde9f97975b", "status": "in_progress",
    "track_size": 52, "home_stretch_size": 6,
    "current_turn_user_id": "a397bea2-550b-4702-bfe3-5a336b68831b",
    "turn_number": 0, "turn_deadline": 1795507748111, "match_deadline": null,
    "pending_pawn_selection": false, "last_dice_value": null, "dice_choice": null, "undo_user_id": null,
    "winner": null,
    "players": [
      {"user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "seat": 0, "team": null, "score": 0, "place": null, "forfeited": false,
       "magic_used": {"double_dice": false, "shield": false, "undo": false},
       "pawns": [{"id": 0, "position_type": "at_base", "position_value": 0}]},
      {"user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "seat": 2, "team": null, "score": 0, "place": null, "forfeited": false,
       "magic_used": {"double_dice": false, "shield": false, "undo": false},
       "pawns": [{"id": 0, "position_type": "at_base", "position_value": 0}]}],
    "rules": {"...": "as in room.created"}}}}
```

If the stakes can't be taken, the room gets `game.start_error` instead: any stake taken is
refunded, ready flags clear and the room waits again.

```json
{"event": "game.start_error", "data": {"error": "insufficient_funds", "message": "One or more players have insufficient funds to cover the bet"}}
```

`player.ready_error` codes: `not_found` (room expired), `invalid_state` (already started),
`not_in_room`, `kill_switch_engaged`.

---

## 4. The game state

Every game frame carries the whole `state`. **Always redraw from the latest `state`.**

| Field | Meaning |
|---|---|
| `status` | `waiting_for_players`, `in_progress` or `completed`. |
| `players[]` | In turn order: `user_id`, `seat` (0 red, 1 green, 2 yellow, 3 blue), `pawns[4]`, `forfeited`, `place` (1 = winner; `null` while racing), `score` (Rush), `team` (0 or 1 in a team game, else `null`), `magic_used` {`shield`, `double_dice`, `undo`}. |
| `current_turn_user_id` | Whose turn. |
| `pending_pawn_selection` | `true`: the roller must send `move_pawn`. |
| `last_dice_value` | The last roll. |
| `turn_deadline` | When this turn runs out (epoch ms, server clock); `null` when no timer runs (for example a bot's turn). |
| `match_deadline` | Rush only: when the match clock ends (epoch ms). |
| `dice_choice` | Magic double roll: the two dice waiting for `pick_die`. |
| `undo_user_id` | Magic: who may undo now. |
| `turn_number`, `winner`, `rules`, `track_size` (52), `home_stretch_size` (6) | |

After an `auth.login` reconnect, `state` also has `player_names` {`user_id`: `username`}.

### The board

A pawn is `{id 0-3, position_type, position_value}`:

| `position_type` | `position_value` |
|---|---|
| `at_base` | 0 |
| `on_board` | The square on the shared main track, **0 to 51, the same numbering for every colour**. |
| `home_stretch` | 0 to 5 in the pawn's own colour's home lane. |
| `home` | 0 (finished). |

| Colour (seat) | Start square | Last track square before its home lane | Safe squares |
|---|---|---|---|
| Red (0) | 0 | 51 | 0, 8 |
| Green (1) | 13 | 12 | 13, 21 |
| Yellow (2) | 26 | 25 | 26, 34 |
| Blue (3) | 39 | 38 | 39, 47 |

Safe squares apply only when `rules.safe_squares` is on. Rotate the drawn board so the
player's own colour sits bottom-left, but keep the server's numbering in the data.

---

## 5. Playing a turn (in a game)

All moves are `game.action` with an `action_type`. Each answers `game.action_ack` (with the
request `id`) or `game.action_error`. The result for **everyone**, the sender included,
arrives as `game.state_update`.

Only the player whose turn it is can act. Disable the dice and pawns otherwise.

### `roll_dice`

```json
// send (real)
{"id": "A-9", "event": "game.action", "data": {"action_type": "roll_dice"}}

// reply (real): a 5 with no pawn out, so nothing can move and the turn passes
{"id": "A-9", "event": "game.action_ack", "data": {"action_type": "roll_dice", "result": {
  "dice_value": 5, "must_select_pawn": false, "moveable_pawns": [], "auto_move": null,
  "turn_forfeited": false, "next_turn_user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c",
  "game_over": false, "winner": null, "turn_deadline": 1795507725596, "dice_choice": null}}}
```

| `result` field | Meaning |
|---|---|
| `must_select_pawn` | `true`: highlight `moveable_pawns` and wait for a tap, then send `move_pawn`. |
| `moveable_pawns` | Pawn ids that can move. |
| `auto_move` | When only one move was possible, the server made it: a move result (below). |
| `turn_forfeited` | The third six in a row: the turn is lost. |
| `next_turn_user_id`, `turn_deadline` | Who plays next and their deadline. |
| `game_over`, `winner` | The game ended on this action. |
| `dice_choice` | Magic double roll only. |

Magic rooms with `rules.double_dice`: send `{"action_type": "roll_dice", "double": true}` once
a match to roll two dice, then `pick_die` with `index` 0 or 1.

### `move_pawn`

```json
{"id": "A-10", "event": "game.action", "data": {"action_type": "move_pawn", "pawn_id": 0}}
```

The ack's `result` is a move result:

```json
{"pawn_id": 0, "dice_value": 6, "move_type": "entered", "place": null,
 "from_position": "at_base", "to_position": "on_board:start",
 "captured_player_seat": null, "captured_pawn_id": null,
 "next_turn_user_id": "7b449132-41df-4807-a388-0245b759f11c", "game_over": false, "winner": null,
 "turn_deadline": 1762650015000}
```

| Field | Meaning |
|---|---|
| `move_type` | `moved`, `entered`, `captured`, `shielded`, `reached_home`, `won` (1st place), `finished` (a later place), `extra_turn:rolled_six`, `extra_turn:captured`, `no_pawn_moveable`, `lost_turn_consecutive_sixes`. |
| `from_position`, `to_position` | For animation: `at_base`, `on_board:N`, `on_board:start`, `home_stretch:N`, `home_stretch`, `home`. |
| `captured_player_seat`, `captured_pawn_id` | Which pawn was sent home, on a capture. |
| `place` | Set when this move finished the player. |

An extra turn (a six, or a capture) shows as `next_turn_user_id` being the same player.

### Other actions

| `action_type` | Fields | When |
|---|---|---|
| `use_powerup` | `powerup_code`: `shield`, `force_six`, `extra_turn` or `home_rush` | Before rolling, on your turn, when `rules.powerups_allowed`. At most 2 a turn. The ack adds `powerup_code` and `remaining_quantity`; the room gets `game.powerup_used` {`user_id`, `powerup_code`, `active_powerups`}. Power-ups come from the player's inventory (see the store hand-off). |
| `undo` | none | Magic rooms with `rules.undo`, once a match, while `state.undo_user_id` is this player: takes back the last chosen move. |
| `pick_die` | `index`: 0 or 1 | After a Magic double roll. |
| `forfeit` | none | Gives up. Ask first. With two players the other wins; with more, the game goes on. |

### `game.action_error`

| `code` | Typical message | Do |
|---|---|---|
| `invalid_state` | `bad request: not your turn`, `must select a pawn to move`, `selected pawn cannot move with the current dice value`, `game is over` | Resync the UI from the latest state; this is usually a double tap. |
| `invalid_request` | `pawn_id must be an integer 0-3`, `unknown action_type: 'x'` | App bug. |
| `busy` | `match ... is busy: lock not acquired within 5s` | Retry once. |
| `game_over` | `the turn ran out and the game ended before this action` | Show the result. |
| `not_found` | `match not found: ...` | The game is gone: back to the lobby. |

### `game.state_update` (to everyone)

Sent after every roll, move, undo and forfeit, and after a turn the server played because
it ran out. Real, shortened:

```json
{"event": "game.state_update", "data": {
  "game_over": false,
  "last_action": {"action_type": "roll_dice", "user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "auto_play": false,
                  "dice_value": 5, "move_type": "no_move", "pawn_id": null, "captured": false,
                  "roll_result": {"dice_value": 5, "must_select_pawn": false, "moveable_pawns": [], "...": "..."},
                  "move_result": null},
  "state": {"current_turn_user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "...": "the whole state"}}}
```

- Animate from `last_action`: the dice from `dice_value`, the pawn from
  `move_result.from_position` to `to_position`, a capture from `captured`, then set the
  board to `state`.
- `move_type` `no_move`: the roll had no legal move; show the dice, then pass the turn.
- `auto_play: true`: the turn ran out and the server played it. Show "Time's up" on that
  seat. Its `action_type` is then `roll_dice`, `move_pawn`, `pick_die` or `roll_and_move`;
  `clock_expired` ends a Rush match.

### Timers

- Show a ring on the current player's seat counting down to `turn_deadline` (server clock,
  see "Times" in `00-conventions.md`).
- When a turn runs out the server plays it (`auto_play`). After the mode's `max_timeouts`
  timed-out turns in a row the player is out (`game.player_forfeited`, reason `timeouts`).
  Warn on the second one: "Play your turn or you'll be removed."
- Rush: show the match clock to `match_deadline`. When it ends, the highest `score` wins.

---

## 6. The end of a game

A `game.state_update` with `"game_over": true` ends the game (a pawn home, the last forfeit,
or the Rush clock). The socket returns to the room state.

A real forfeit ending (2 players):

```json
{"id": "B-6", "event": "game.action_ack", "data": {"action_type": "forfeit"}}
{"event": "game.player_forfeited", "data": {"game_over": true, "reason": "manual",
  "user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "winner_id": "a397bea2-550b-4702-bfe3-5a336b68831b"}}
{"event": "game.state_update", "data": {"game_over": true,
  "last_action": {"action_type": "forfeit", "auto_play": false, "reason": "manual", "user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c"},
  "state": {"status": "completed", "winner": "a397bea2-550b-4702-bfe3-5a336b68831b", "turn_deadline": null, "...": "...",
            "players": [{"user_id": "a397bea2-...", "place": 1, "forfeited": false, "...": "..."},
                        {"user_id": "a1164ecb-...", "place": 2, "forfeited": true, "...": "..."}]}}}
```

`game.player_forfeited` `reason`: `manual` (gave up), `left` (`room.leave` mid-game),
`disconnected` (not back within 30 s), `timeouts`, `no_show` (tournament). With three or four
players the game goes on without them (`game_over: false`).

**Result screen:** places from `state.players[].place`. For a staked game, wait for
`game.wallet_update` (a moment after the end; free games send none):

```json
{"event": "game.wallet_update", "data": {"match_id": "c0a8012e-5b7d-4f3e-a1c2-9d8e7f6a5b4c",
  "pot_amount": 20, "rake_amount": 1,
  "payouts": [{"user_id": "7b449132-41df-4807-a388-0245b759f11c", "amount": 19, "result": "win"},
              {"user_id": "3f2a9c14-8d6e-4b1a-9e07-5c4d2b1a0f93", "amount": 0, "result": "loss"}]}}
```

Only 1st place is paid (partners share it in a team game); the house keeps 5% (none on a
draw). Show the player's own `amount`, then re-read `GET /wallet/balance`.

### Rematch

With `rules.rematch` on, `game.rematch` (no fields) opens a new private room with the same
settings and answers `room.created`. The old room gets:

```json
{"event": "game.rematch_offered", "data": {"from_user_id": "7b449132-...", "room_id": "...", "room_code": "c0a8012e"}}
```

Show "<name> wants a rematch" with a Join button: send `room.leave`, then `room.join` with
that `room_code`. `game.rematch_error`: `not_found` (the old game expired), `invalid_state`
(not finished, or rematch off), stake codes.

Otherwise `room.leave` returns to the lobby.

---

## 7. Reconnect

When the socket drops mid-game, the others get `room.user_left` (`disconnected`) and the
player has **30 seconds**:

1. Open a new socket, wait for `connection.established`, send `auth.login`.
2. The server sends one of:
   - `game.state_sync` `{match_id, state}` (with `state.player_names`): the game is still on
     and the player is back in it. Redraw everything. Others get `room.user_joined` with
     `reconnected: true`.
   - `game.final_state` `{match_id, room_id, read_only: true, state}`: the game ended while
     away. Show the result, read-only.
   - Nothing more: no game to go back to (also after forfeiting). Go to the lobby.
3. Load missed chat with `chat.history` if needed.

After 30 seconds the player is out (`game.player_forfeited`, reason `disconnected`).

On a cold start with a stored game (the app was killed), do the same: sign in on a new socket
and wait a moment for `game.state_sync` before showing the lobby.

---

## 8. Chat and gifts (in a room or game)

### Quick chat

Only 12 preset lines are accepted, exactly: `Good game!`, `Nice move!`, `Hurry up!`,
`Well played!`, `Good luck!`, `Oops!`, `Wow!`, `Thanks!`, `Sorry!`, `Ha ha!`, `Oh no!`,
`Let's go!`. Show them as buttons and translate on screen; send the English text.

```json
// send (real): no reply of its own
{"id": "A-11", "event": "chat.send", "data": {"message": "Good game!"}}

// everyone, the sender too (real)
{"event": "chat.message", "data": {"from_user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "message": "Good game!",
  "timestamp": 1795507713054, "username": "fdoc7419"}}
```

- `team: true` sends to the partner only (team games with `rules.team_chat`).
- `chat.history` `{limit}` (1 to 200, default 50) -> `chat.history_result` `{messages}`,
  oldest first.
- `chat.send_error`: `invalid_request` (not a preset line), `invalid_state` (team chat off).

### Gifts

`gift.send` pays tokens or gold to another player in the same room, from the sender's
wallet at once.

| Field | |
|---|---|
| `receiver_id` | Required: another player in the room. |
| `amount` | Required: a whole number above 0. |
| `currency` | Optional: `token` (default) or `gold`. |
| `item_type` | Optional label to show, for example `rose` (default `gift`). |
| `message` | Optional, up to 200 characters. |

Reply `gift.send_ack` `{status, gift_id, amount, currency}`; the room gets `gift.received`
`{gift_id, sender_id, sender_name, receiver_id, item_type, amount, currency, message,
timestamp}` (show it on the receiver's seat). Errors on `gift.send_error`:
`invalid_request`, `not_in_room`, `insufficient_funds`, `internal_error`. Ask to confirm
before sending; it can't be undone.

---

## 9. Tournament tables

A tournament gives the player a `room_code` for their table (see the tournaments hand-off).
Join it with `room.join`; the seat and colour are reserved. `room.joined` and `game.started`
carry `tournament` {`tournament_id`, `round`, `table_number`}: show "Round N, Table T". At
the table's seat deadline the game starts with whoever came; each no-show gets
`game.player_forfeited` with reason `no_show`.

If the engine cancels a table, the room gets `game.cancelled` `{match_id, reason}`: the game
ends with no result, nothing is paid, and the room closes. Show "This table was cancelled"
and go back to the tournament screen.

---

## 10. Errors summary

| Event | When |
|---|---|
| `<request>_error` (for example `room.join_error`) | The request was refused; `error.code` as listed per request. |
| `<domain>.error` (`room.error`, `match.error`, `player.error`, `game.error`, `chat.error`, `gift.error`, `auth.error`) | The request isn't allowed in the socket's current state. |
| `connection.error` | `unknown_event`, `invalid_request` (not a JSON envelope), `rate_limited` (over 30 frames a second), `invalid_state` (not signed in). |
| `connection.kicked` | The app read too slowly; the socket closes. Reconnect. |
| `auth.session_expired` | The token expired on the socket; it closes. Refresh and reconnect. |

Real wrong-state reply:

```json
{"id": "A-5", "event": "game.error", "error": {"code": "invalid_state", "message": "event 'game.action' not allowed in Authenticated state"}}
```

`kill_switch_engaged` on `room.create`, `room.join`, `match.find`, `player.ready` or
`game.rematch`: an operator paused new Ludo games. Show `error.message` and disable the play
buttons; running games carry on.

---

## Done when

- [ ] Quick match `casual_2p` finds a game (a bot joins when no one else does) and plays to
      the end.
- [ ] Play with friends: create a room, share the code, a second phone joins with it, both
      ready, and the game starts.
- [ ] A staked room checks the stake, shows `insufficient_funds` when the wallet is short,
      and after the game shows the payout and the new balance.
- [ ] Rolling with several moveable pawns highlights them and moves the tapped one; with one,
      the server's `auto_move` animates without a tap.
- [ ] Captures, extra turns, reaching home and the turn timer show correctly on both phones.
- [ ] A turn left to run out is played by the server and shows "Time's up".
- [ ] Turning Wi-Fi off for 10 seconds mid-game and back on returns to the same game.
- [ ] Killing the app mid-game and reopening it within 30 seconds returns to the game.
- [ ] Forfeit and leave both ask first and end the game for a 2-player room.
- [ ] Rematch: one player asks, the other sees the offer and joins.
- [ ] Quick chat lines appear on both phones; a gift moves the amount between wallets.
- [ ] Every error code above shows a message, not a crash.
- [ ] No token appears in any log.

---

## Testing on the development server

- Two phones (or a phone and an emulator) with two different accounts; one account can't
  hold two Ludo sockets.
- The Ludo debug page at `http://<host>:1285/debug/ui` can be the second player, and shows
  this same protocol reference after signing in.
- Bots fill quick-match lobbies only while the bot service runs on the server; ask the server
  owner.
