# Flutter hand-off 6: tournaments

The tournament lobby, entering and leaving, Sit & Go (starts when full), scheduled
tournaments, the player's table, the standings, prizes, and what happens to the money when a
tournament is cancelled. This is the cross-game picture. Ludo is the worked example; each
game's own file (for example `games/ludo.md`, section 9) gives that game's socket events at a
tournament table.

Read `00-conventions.md` (errors, list shapes, money, times, the socket envelope),
`03-wallet.md` (ledger) and `05-matchmaking-and-rooms.md` (opening a game socket, `room.join`)
first. This file links to them instead of repeating them.

**Where the samples come from.** Samples marked **real** were captured on 24 Nov 2026 from the
running gateway and the Ludo server with five new test players: four of them entered the
Ludo Sit & Go "Weekday Ladder Final" (250 + 25 tokens), played it to the end over the Ludo
socket and were paid; then they filled the next copy of it and let its table go unplayed, so
it was cancelled and refunded. Samples marked **from code** were not captured; their shape is
read from `crates/api-gateway/src/modules/tournaments/`.

---

## For the Claude agent: what to build

1. A `TournamentApi` on the shared `ApiClient` with `list({gameId, status, page, perPage})`,
   `get(id)`, `register(id)`, `unregister(id)`, `myTable(id)`, `standings(id)`, `rounds(id)`
   and `bracket(id)`.
2. Models `Tournament`, `TournamentEntry`, `MyTable` (with `TableSeat`), `Standing`, `Round`
   (with `RoundTable`) and `BracketNode`. Every enum (`status`, `tournament_type`,
   `entry_status`, `leave_reason`, table `status`) needs an `unknown` fallback.
3. A `TournamentController` per open tournament screen: it holds the tournament and the
   player's `MyTable`, re-reads them every 10 seconds while the screen is open and the
   tournament is `registering` or `running`, and moves the player to the table (see "Flow").
4. Screens:
   - **Tournaments lobby** with three tabs: Upcoming, Running, Finished (see 1).
   - **Tournament detail**: name, game, format, buy-in + fee, seats taken, prize pool, start,
     the player's entry, and one main button (Join / Leave / Go to table / Results).
   - **Join confirm sheet**: "Join for 250 + 25 tokens?" with the balance.
   - **Table hand-off**: "Your table is ready. Round 1, Table 1" with a countdown to the seat
     deadline and a Go button.
   - **Results**: the final standing with places and prizes.
5. Re-use `GameLobby` / `GameSocket` from `05-matchmaking-and-rooms.md` to join the table:
   the only new call is `room.join` with the table's `room_code`.
6. Tests: parsing every real sample in this file; the controller's moves for the end-to-end
   flow below; each error in "Errors"; a cancelled tournament showing the refund; an unknown
   `status` or `tournament_type` not crashing.

---

## Endpoints at a glance

All paths are under `http://<host>:1280/api/v1`. All need `Authorization: Bearer
<access_token>` (no token: `401 UNAUTHORIZED`, real). None of them has the device check.

| Use | Method and path | Success | Seen |
|---|---|---|---|
| List tournaments | `GET /tournaments` | `200`, page list (shape 2) | real |
| One tournament | `GET /tournaments/{id}` | `200`, one object | real |
| Join (enter) | `POST /tournaments/{id}/register` | `201`, the entry | real |
| Leave (withdraw) | `POST /tournaments/{id}/unregister` | `200`, `{"status": "withdrawn"}` | real |
| My table and entry | `GET /tournaments/{id}/my-table` | `200`, one object | real |
| Standings | `GET /tournaments/{id}/standings` | `200`, plain array | real |
| Rounds and tables | `GET /tournaments/{id}/rounds` | `200`, plain array | real |
| Bracket | `GET /tournaments/{id}/bracket` | `200`, plain array | real (empty) |

`{id}` is the tournament's UUID. A value that is not a UUID answers `400 BAD_REQUEST`, an
unknown UUID `404 NOT_FOUND` (both real, on every route above).

There is no "my tournaments" route and no push when a tournament starts; see "Known issues".
Admin routes (`/admin/tournaments/...`: create, start, pause, cancel) are console only; the
app never calls them.

The `refunds` module (`/sensitive/refunds/...`) is **not** about tournaments. It is for
asking a refund of an in-app purchase and belongs to `11-store.md`; a short note is in 9.
Tournament refunds are automatic and show up in the wallet ledger (section 7).

---

## Formats and statuses

### `tournament_type` (the format)

| Value | Name to show | Runs on its own today |
|---|---|---|
| `single_table_sng` | Sit & Go | **Yes.** Starts the moment every seat is taken. |
| `leaderboard_window` | Score window (for example Crash "Rocket Royale", the word games' "Royale") | **Yes.** Starts at its start time with at least its minimum entries; one table holds everyone; places come from the final scores. |
| `multi_table_mtt` | Multi-table | No (see "Known issues", 1) |
| `bracket_single_elim`, `bracket_double_elim` | Knockout | No |
| `swiss`, `round_robin`, `ladder`, `arena`, `chip_race`, `points_series`, `heats_knockout`, `table_knockout` | (as named) | No |

Only the first two are run by the server's tournament engine. The rest are listed, open for
registration and take buy-ins, but never start by themselves (an operator must start them,
and the engine cannot run their rounds yet). Treat them as described in "Known issues", 1.

### `status`

```
announced -> registering -> running <-> paused -> completed
     \____________\____________\__________\______-> cancelled -> refunded
```

| `status` | Meaning | Tab | Main button |
|---|---|---|---|
| `announced` | Published; registration not open yet. | Upcoming | "Opens soon" (disabled) |
| `registering` | Open for entries. | Upcoming | Join, or Leave if entered |
| `running` | Playing. | Running | Go to table (if the player has one) |
| `paused` | An operator paused it between rounds. Tables already playing finish. | Running | "Paused" |
| `completed` | Finished and paid. | Finished | Results |
| `cancelled` | Cancelled; refunds are being made. | Finished | "Cancelled" |
| `refunded` | Cancelled and every entry refunded. | Finished | "Cancelled, entry refunded" |

The `status` filter on the list also accepts `upcoming` (= `announced`) and `active`
(= `running`) for older clients; replies always use the names above.

---

## 1. List tournaments

`GET /tournaments?game_id=&status=&page=&per_page=`

| Query | Rule |
|---|---|
| `game_id` | Optional. The game's **numeric** id from `GET /games` (`04-game-catalogue.md`); Ludo is `1`. A game code answers `400`. |
| `status` | Optional. **One** status from the table above. Anything else is `400`. |
| `page` | Optional, from 1, default 1. |
| `per_page` | Optional, default 20. Send 1 to 100 (see "Known issues", 4). |

The reply is list shape 2 from `00-conventions.md`: `{data, total, page, per_page,
total_pages}`, sorted by `starts_at`, **oldest first**.

Real (`?game_id=1&status=registering`):

```json
{
  "data": [
    {"id": "93ae50a9-0ac4-376b-0387-996360e1bd8c", "game_id": 1, "mode_id": 58, "name": "Sunday Dice Royale",
     "tournament_type": "single_table_sng", "status": "registering", "max_players": 4, "current_players": 0,
     "entry_fee": 2500, "fee_amount": 250, "currency": "token", "prize_pool": 0, "starts_at": "2026-11-15T01:00:00Z"},
    {"id": "f1a95eea-8468-64da-5d23-667828f2a704", "game_id": 1, "mode_id": 58, "name": "Weekday Ladder Final",
     "tournament_type": "single_table_sng", "status": "registering", "max_players": 4, "current_players": 0,
     "entry_fee": 250, "fee_amount": 25, "currency": "token", "prize_pool": 0, "starts_at": "2026-11-19T22:00:00Z"}
  ],
  "total": 2, "page": 1, "per_page": 20, "total_pages": 1
}
```

A free tournament with a guaranteed pool, real (`?game_id=1&status=upcoming&per_page=2`, one
row):

```json
{"id": "2df67ec2-04d0-4aee-cc1d-feb52dd52fd6", "game_id": 1, "mode_id": 58, "name": "Breakfast Freeroll",
 "tournament_type": "multi_table_mtt", "status": "announced", "max_players": 500, "current_players": 0,
 "entry_fee": 0, "fee_amount": 0, "currency": "token", "prize_pool": 5000, "starts_at": "2026-11-24T18:00:00Z"}
```

### Fields (the same object on the list and the detail route)

| Field | Type | Meaning and use |
|---|---|---|
| `id` | UUID | The tournament. |
| `game_id` | number | The game; name and icon from the catalogue. |
| `mode_id` | number | The game mode the tables use (seats, rules), from `GET /games/{id}/modes`. |
| `name` | string | Display name. Several tournaments can share a name (Sit & Go copies, see 4). |
| `tournament_type` | string | The format (table above). |
| `status` | string | The status (table above). |
| `max_players` | number or `null` | Seats in total. `null` = no limit. |
| `current_players` | number | Entries so far. Show "3 / 4". |
| `entry_fee` | number | The **buy-in**: goes into the prize pool. `0` = free. |
| `fee_amount` | number | The **entry fee** on top, kept by the house. The player pays `entry_fee + fee_amount`. |
| `currency` | string | `token` or `gold` (both fees). |
| `prize_pool` | number | The larger of the guaranteed pool and the pool collected so far. For a Sit & Go it is `0` until it starts (real), then the buy-ins (`1000` = 4 x 250, real). |
| `starts_at` | ISO 8601 UTC | Scheduled start. **For a Sit & Go it is not a start time** (it starts when full); for a Sit & Go copy it is when the copy was made. |

Money here is plain JSON numbers (unlike `GET /wallet/balance`). Parse leniently anyway
(`00-conventions.md`, "Money").

### What the app does with it

- **Tabs.** One status per call, so: Upcoming = `registering` then `announced`; Running =
  `running` and `paused`; Finished = `completed`, `refunded`, `cancelled`. Always pass
  `game_id` when the lobby is inside one game.
- **Finished is oldest first** (no sort parameter). Read its last page first (`page =
  total_pages`) and go backwards, or show only the last few.
- **Sit & Go row:** "Sit & Go, 4 players, 3 / 4 seated", "Starts when full", the price as
  "250 + 25 tokens". Don't show `starts_at` for a Sit & Go.
- **Scheduled row:** the start in local time and a countdown; "Opens soon" while
  `announced`.
- **Prize pool:** show `prize_pool` when above 0 ("Prize pool 5,000 tokens"). For a Sit & Go
  at 0, show "Pool: 1,000 tokens when full" (`entry_fee x max_players`); label it as the full
  pool, not a payout.
- Grey out Join when the wallet can't cover `entry_fee + fee_amount` in `currency`
  (`GET /wallet/balance`), and say why.
- Hide formats the engine doesn't run, or show them as "Coming soon" without Join (see
  "Known issues", 1).
- Pull to refresh; no automatic refresh faster than every 10 seconds.

**Errors** (all real)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `status` not in the list; `game_id` not a number. | App bug. |
| 401 | `UNAUTHORIZED` | No token or an expired one. | The interceptor refreshes (`01-auth.md`). |

```json
{"error": "BAD_REQUEST", "message": "bad request: Query deserialize error: unknown variant, expected one of `announced`, `upcoming`, `registering`, `active`, `running`, `paused`, `completed`, `cancelled`, `refunded`"}
{"error": "BAD_REQUEST", "message": "bad request: Query deserialize error: invalid digit found in string"}
```

---

## 2. One tournament

`GET /tournaments/{id}`. The same object as a list row.

Real, after the fourth player joined (full, the engine had not started it yet):

```json
{"id": "f1a95eea-8468-64da-5d23-667828f2a704", "game_id": 1, "mode_id": 58, "name": "Weekday Ladder Final",
 "tournament_type": "single_table_sng", "status": "registering", "max_players": 4, "current_players": 4,
 "entry_fee": 250, "fee_amount": 25, "currency": "token", "prize_pool": 0, "starts_at": "2026-11-19T22:00:00Z"}
```

Real, two seconds later (started):

```json
{"id": "f1a95eea-8468-64da-5d23-667828f2a704", "game_id": 1, "mode_id": 58, "name": "Weekday Ladder Final",
 "tournament_type": "single_table_sng", "status": "running", "max_players": 4, "current_players": 4,
 "entry_fee": 250, "fee_amount": 25, "currency": "token", "prize_pool": 1000, "starts_at": "2026-11-19T22:00:00Z"}
```

**What the app does:** the detail screen loads this **and** `my-table` (3) together; the
player's own entry and table come only from `my-table`.

**Errors** (real)

```json
// 404
{"error": "NOT_FOUND", "message": "not found: tournament 00000000-0000-4000-8000-000000000000"}
// 400, not a UUID
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: UUID parsing failed: invalid character: found `l` at 0"}
```

A 404 on a tournament the app showed before: it was removed. Go back to the lobby and reload.

---

## 3. My entry and my table

`GET /tournaments/{id}/my-table`

The player's entry status, and their current table once the tournament runs. This is how the
app learns that its table is ready (there is no push).

Real, not entered:

```json
{"tournament_status": "registering", "entry_status": null, "table": null}
```

Real, entered and waiting for the Sit & Go to fill:

```json
{"tournament_status": "registering", "entry_status": "registered", "table": null}
```

Real, the Sit & Go has started and the table is open:

```json
{
  "tournament_status": "running",
  "entry_status": "active",
  "table": {
    "round": 1, "table_number": 1, "status": "playing", "seat": 1,
    "room_code": "1fbbb0ed", "match_id": "1fbbb0ed-5949-4601-add7-d147033c8e4b",
    "seat_deadline_at": "2026-11-24T09:46:14.665Z", "place": null,
    "players": [
      {"player_id": "8fe11c59-fe42-4100-9c34-891b97681130", "username": "w06docb1795513349", "seat": 0, "place": null, "leave_reason": null},
      {"player_id": "3d3ad895-d55d-4e58-b75f-e04e291f358f", "username": "w06doca1795513349", "seat": 1, "place": null, "leave_reason": null},
      {"player_id": "8b4a149e-f880-441e-8660-8e5799616181", "username": "w06docd1795513349", "seat": 2, "place": null, "leave_reason": null},
      {"player_id": "047466bd-3ba0-4f71-862a-fe5222bea86d", "username": "w06docc1795513349", "seat": 3, "place": null, "leave_reason": null}
    ]
  }
}
```

Real, after the game (player D won):

```json
{
  "tournament_status": "completed",
  "entry_status": "winner",
  "table": {
    "round": 1, "table_number": 1, "status": "closed", "seat": 2,
    "room_code": "1fbbb0ed", "match_id": "1fbbb0ed-5949-4601-add7-d147033c8e4b",
    "seat_deadline_at": "2026-11-24T09:46:14.665Z", "place": 1,
    "players": [
      {"player_id": "8fe11c59-fe42-4100-9c34-891b97681130", "username": "w06docb1795513349", "seat": 0, "place": 3, "leave_reason": "busted"},
      {"player_id": "3d3ad895-d55d-4e58-b75f-e04e291f358f", "username": "w06doca1795513349", "seat": 1, "place": 4, "leave_reason": "busted"},
      {"player_id": "8b4a149e-f880-441e-8660-8e5799616181", "username": "w06docd1795513349", "seat": 2, "place": 1, "leave_reason": "finished"},
      {"player_id": "047466bd-3ba0-4f71-862a-fe5222bea86d", "username": "w06docc1795513349", "seat": 3, "place": 2, "leave_reason": "busted"}
    ]
  }
}
```

| Field | Meaning |
|---|---|
| `tournament_status` | The tournament's `status`. |
| `entry_status` | `null` (not entered), `registered`, `active` (playing), `busted` (out), `winner`, `withdrawn` (left, or the tournament was cancelled), `disqualified`. |
| `table` | `null` until the player is seated. Then their **latest** table. |
| `table.round`, `table.table_number` | Show "Round 1, Table 1". |
| `table.status` | `waiting` (being opened on the game server; no `room_code` yet), `playing` (open: go now), `closed` (finished or cancelled). Unknown values: treat as `waiting`. |
| `table.room_code` | Send this in `room.join` on the game socket (4). `null` while `waiting`. |
| `table.match_id` | The game's match id (the room id on the socket, and `match_id` in history). |
| `table.seat_deadline_at` | Join before this time. After it the game starts without the missing players (they lose). |
| `table.seat` | The player's seat **number in the tournament draw**, from 0. Use it only to order the list; the board seat and colour come from the game socket's `room.joined` (they match for a full 4-seat Ludo table, real; a 2-seat Ludo table sits players at Ludo seats 0 and 2, from code). |
| `table.place` | The player's place at this table once it ends, else `null`. |
| `table.players[]` | Everyone at the table: `player_id`, `username`, `seat`, `place`, `leave_reason` (`null` while playing; `finished` = played to the end, `busted` = knocked out, `withdrawn` = cancelled, others possible). |

**What the app does:**

- While `entry_status` is `registered`, show "Waiting for players (3 / 4)". Re-read every 10
  seconds while the screen is open, and on resume.
- When `table.status` is `playing` and `room_code` is set: show the table hand-off ("Your
  table is ready, Round 1, Table 1, join within 1:58") and, if the player is in the app, open
  the game at once (4).
- When `tournament_status` is `completed`, `cancelled` or `refunded`: show results (6) or the
  refund (7).

**Errors:** `404 NOT_FOUND` for an unknown tournament (real, as in 2). A player who never
entered still gets `200` with `entry_status: null` (real).

---

## 4. Join and leave

### Join: `POST /tournaments/{id}/register`

No body. The server checks, in this order: the tournament is `registering`; the
registration window (not for a Sit & Go, which stays open until full); bans; the player's
level in this game; the required membership tier; kill switches; self-exclusion and
cooling-off; the player isn't already in; there is a free seat; and, for a paid entry, the
loss and spend limits and the wallet. Then it takes the money and writes the entry, all at
once.

**Success:** `201`. Real:

```json
{"tournament_id": "f1a95eea-8468-64da-5d23-667828f2a704", "user_id": "3d3ad895-d55d-4e58-b75f-e04e291f358f",
 "status": "registered", "rebuys": 0, "registered_at": "2026-11-24T09:44:02.261239Z"}
```

| Field | Meaning |
|---|---|
| `status` | The entry status, `registered`. |
| `rebuys` | Always 0 today. |
| `registered_at` | When the entry was made. |

What happens to the money (real): two ledger rows at once, `buyin` 250 and `fee` 25 (see 7),
and the balance drops by 275. A free tournament writes no rows.

**What the app does:** confirm first ("Join Weekday Ladder Final for 250 + 25 tokens?"), then
call. On `201`: refresh the wallet chip (`03-wallet.md`), the tournament (2) and `my-table`
(3), and show "You're in". A Sit & Go may start a second later (the fourth entry started ours
within about two seconds, real).

### Leave: `POST /tournaments/{id}/unregister`

No body. Allowed only while the tournament is `announced` or `registering`. The buy-in and the
fee are refunded in full at once.

**Success:** `200`. Real:

```json
{"status": "withdrawn"}
```

Real ledger rows right after (newest first): two `refund` credits, 25 and 250 (see 7). The
balance was back to 600. `my-table` then reads `"entry_status": "withdrawn"`, and the
player may join again (real: `201` again).

**What the app does:** ask first ("Leave the tournament? Your 275 tokens will be refunded."),
then refresh the wallet, the tournament and `my-table`. Hide Leave once the tournament runs.

### Errors (join and leave)

| Status | `error` | Route | When | Show | Seen |
|---|---|---|---|---|---|
| 400 | `BAD_REQUEST` | join | Not `registering` (announced, running, finished, cancelled). | "Registration isn't open." Reload. | real |
| 400 | `BAD_REQUEST` | join | Registration window closed (`registration closed at ...`) or not yet open (`registration opens at ...`). Not for Sit & Go. | "Registration has closed." / "Registration opens soon." | code |
| 400 | `BAD_REQUEST` | leave | The tournament has started or ended. | "You can't leave once it has started." | real |
| 403 | `FORBIDDEN` | join | Level too low: `requires level 5 in this game (you are level 1)`. | "Reach level 5 in Ludo to join." Parse the numbers only for display; decide on the status. | code |
| 403 | `FORBIDDEN` | join | Membership: `requires a gold subscription`. | "Gold members only." Offer the membership screen. | code |
| 403 | `FORBIDDEN` | join | Banned from tournaments; self-excluded or cooling off until a time; the buy-in would pass a daily, weekly or monthly loss limit or the daily tournament spend limit. | "You can't join right now." For limits: "This would pass your spending limit." | code |
| 404 | `NOT_FOUND` | both | No such tournament. | Reload the lobby. | real |
| 404 | `NOT_FOUND` | leave | Not entered (or already left). | Refresh `my-table`; no message. | real |
| 409 | `CONFLICT` | join | Already entered. | Refresh `my-table`; no message. | real |
| 409 | `TOURNAMENT_FULL` | join | Every seat taken. | "This tournament is full." Offer the next copy (see 5). | real |
| 409 | `INSUFFICIENT_FUNDS` | join | The wallet can't cover buy-in + fee. | "Not enough tokens." Offer the shop. | real |
| 503 | `KILL_SWITCH_ENGAGED` | join | An operator paused the store or this game. | Show `message`; disable Join. | code |
| 500 | `INTERNAL_ERROR` | join | Bad tournament data on the server. | "Something went wrong." | code |

Real bodies:

```json
{"error": "BAD_REQUEST", "message": "bad request: tournament is not accepting registrations"}
{"error": "BAD_REQUEST", "message": "bad request: cannot unregister once the tournament has started or ended"}
{"error": "NOT_FOUND", "message": "not found: not registered for this tournament"}
{"error": "CONFLICT", "message": "conflict: already registered"}
{"error": "TOURNAMENT_FULL", "message": "tournament full"}
{"error": "INSUFFICIENT_FUNDS", "message": "insufficient funds"}
```

From code (`forbidden: ` + the text):

```json
{"error": "FORBIDDEN", "message": "forbidden: requires level 5 in this game (you are level 1)"}
{"error": "FORBIDDEN", "message": "forbidden: requires a gold subscription"}
{"error": "FORBIDDEN", "message": "forbidden: you are banned from tournaments"}
{"error": "FORBIDDEN", "message": "forbidden: buy-in would exceed your daily loss limit (90 lost of 100)"}
{"error": "BAD_REQUEST", "message": "bad request: registration closed at 2026-11-24 11:48:00 UTC"}
```

The three 403 kinds all share `FORBIDDEN`. To tell them apart for the message, check the
`message` text for `requires level`, `subscription`, or neither; fall back to the general
"You can't join right now". (This is the one place where the text is needed; see "Known
issues", 5.)

No network or a timeout on join: don't assume it failed. Re-read `my-table`; if
`entry_status` is `registered`, it went through. Never call join twice blindly (it is not
idempotent, but a second call only answers `409 CONFLICT`, no double charge).

---

## 5. Sit & Go and scheduled tournaments

### Sit & Go (`single_table_sng`)

- One table. It starts **the moment the last seat is taken** (the server checks every 5
  seconds; ours started 2 seconds after the fourth entry, real). `starts_at` means nothing for
  it.
- Registration never closes by time; only "full" closes it.
- When one starts, the server makes a **new copy** with the same name, price and seats, open
  at once (real: a new "Weekday Ladder Final" appeared in the list with a new `id`,
  `current_players: 0`, and `starts_at` = the time of the copy). So the lobby always has one
  open Sit & Go per kind. After `TOURNAMENT_FULL`, reload the list and offer that copy.
- The table is opened on the game server with the reserved seats. Each player has until
  `seat_deadline_at` (2 minutes by default) to join it. Then:
  - everyone who came plays; each player who didn't is out (`no_show`) and placed last;
  - one player came: they win by walkover;
  - nobody came: the table is void, the **whole tournament is cancelled and every entry
    refunded** (real, see 7).
- Prizes: paid from the pool (the buy-ins) by a fixed split. Real: 4 x 250 = 1000, 1st 650,
  2nd 350 (the server's "3-6 entrants" split, 65 / 35). The fee (25 each) is not in the pool.

### Score window (`leaderboard_window`)

From code. Starts at `starts_at` when it has its minimum entries (not when full). Every entry
sits at one table; places come from the final scores. Too few entries at the start: cancelled
and refunded. A new copy opens when one starts. The game's own file describes its socket
side (Crash, the word games, and others).

### Scheduled tournaments (every other format)

From code (the server's status sweep runs once a minute):

1. `announced` becomes `registering` when its registration opens.
2. At `starts_at`:
   - a seeded tournament (one that came with the catalogue) with **no** entries moves one or
     more weeks later (its `starts_at` changes; same `id`);
   - any other with fewer entries than its minimum is **cancelled** and every entry refunded;
   - one with enough entries stays `registering` (it does not start; see "Known issues", 1).

**What the app does:** show the start countdown, re-read the detail when it reaches 0, and
accept that `starts_at` can jump a week later for an empty tournament.

---

## 6. Playing the tournament table (the hand-off to the game socket)

The gateway gives the table; the game socket plays it. Nothing else from the gateway is
needed.

1. From `my-table`: `table.status == "playing"`, `room_code`, `seat_deadline_at`.
2. Open the game's socket and sign in (`05-matchmaking-and-rooms.md`, section 2). The port
   comes from the app's config by the tournament's game (Ludo `1285`).
3. Send `room.join` with the `room_code`. The seat is reserved for this player only.
4. Send `player.ready`. The game starts when every reserved player is ready, or at the seat
   deadline with whoever came.
5. Play as in the game's file. Leaving or forfeiting loses the table, like any game.
6. When the game ends: show the place from the game's final state, then go back to the
   tournament screen and read `my-table`, the tournament and the standings (7 and 8).

There is no stake on the table itself: `bet_amount` and `currency` are `null`, there is no
`game.wallet_update`, and no `entry_fee` / `payout` rows. The money is the tournament's
(`buyin`, `fee`, `prize`).

Real Ludo frames at our table (the full events are in `games/ludo.md`):

```json
// A joins with the code from my-table
{"id": "A-2", "event": "room.join", "data": {"room_code": "1fbbb0ed"}}
{"id": "A-2", "event": "room.joined", "data": {"bet_amount": null, "board_layout": "standard", "color": "green", "currency": null,
  "max_players": 4, "mode_code": "casual_4p",
  "players": [{"avatar_url": null, "balance_gold": 500, "balance_tokens": 325, "color": "green", "is_bot": false, "ready": false, "seat": 1,
               "user_id": "3d3ad895-d55d-4e58-b75f-e04e291f358f", "username": "w06doca1795513349"}],
  "room_code": "1fbbb0ed", "room_id": "1fbbb0ed-5949-4601-add7-d147033c8e4b", "seat": 1,
  "tournament": {"round": 1, "table_number": 1, "tournament_id": "f1a95eea-8468-64da-5d23-667828f2a704"},
  "variant": "classic"}}

// all four ready -> game.started (state cut)
{"event": "game.started", "data": {"current_turn": 0, "match_id": "1fbbb0ed-5949-4601-add7-d147033c8e4b", "state": {"...": "..."}}}

// A, B, then C forfeit; the last forfeit ends the game, D wins
{"event": "game.player_forfeited", "data": {"game_over": false, "reason": "manual", "user_id": "3d3ad895-d55d-4e58-b75f-e04e291f358f", "winner_id": null}}
{"event": "game.player_forfeited", "data": {"game_over": true, "reason": "manual", "user_id": "047466bd-3ba0-4f71-862a-fe5222bea86d", "winner_id": "8b4a149e-f880-441e-8660-8e5799616181"}}
```

- `room.joined.tournament` is set on a tournament table and `null` elsewhere: show "Round 1,
  Table 1".
- Ludo refusals on `room.join` that matter here: `not_your_table` ("This tournament table
  has no seat for you": wrong account or an old code), `game_in_progress` (the deadline
  passed and the game started without the player), `not_found` (the table closed). On any of
  them, re-read `my-table`.
- A no-show gets `game.player_forfeited` with `reason: "no_show"`; a cancelled table sends
  `game.cancelled` `{match_id, reason}` (`games/ludo.md`, section 9). After `game.cancelled`,
  go back to the tournament screen; the refund follows (7).
- Settlement is quick: the last forfeit was at 09:44:53 and the tournament was `completed`
  and paid at 09:44:54 (real). Re-read once 2 seconds after the game ends; if it is still
  `running`, show "Results coming" and re-read every 10 seconds (an operator can hold
  payouts with a kill switch; settlement then waits).

---

## 7. Money: entry, prize and refund rows

All tournament money shows up in `GET /wallet/ledger` (`03-wallet.md`). Confirmed live on 24
Nov 2026:

| When | `kind` | `direction` | `counterparty` | `tournament_id` |
|---|---|---|---|---|
| Join (buy-in) | `buyin` | `debit` | `tournament_escrow` | set |
| Join (fee) | `fee` | `debit` | `house_revenue` | **`null`** |
| Leave, or a cancelled tournament (buy-in back) | `refund` | `credit` | `tournament_escrow` | set |
| Leave, or a cancelled tournament (fee back) | `refund` | `credit` | `house_revenue` | **`null`** |
| Prize | `prize` | `credit` | `tournament_escrow` | set |

The fee rows carry no `tournament_id` (see "Known issues", 2). They have the same
`created_at` as the buy-in row they belong to; group them by that.

Real, player A joins (newest first):

```json
{"entry_id": "ledger:42089", "created_at": "2026-11-24T09:44:02.261239Z", "currency": "token", "direction": "debit", "amount": 25,
 "kind": "fee", "counterparty": "house_revenue", "counterparty_user_id": null, "tournament_id": null, "match_id": null,
 "item_kind": null, "item_name": null, "game_code": null, "variant_code": null}
{"entry_id": "ledger:42088", "created_at": "2026-11-24T09:44:02.261239Z", "currency": "token", "direction": "debit", "amount": 250,
 "kind": "buyin", "counterparty": "tournament_escrow", "counterparty_user_id": null,
 "tournament_id": "f1a95eea-8468-64da-5d23-667828f2a704", "match_id": null,
 "item_kind": null, "item_name": null, "game_code": null, "variant_code": null}
```

Real, player A leaves four seconds later:

```json
{"entry_id": "ledger:42091", "created_at": "2026-11-24T09:44:06.753612Z", "currency": "token", "direction": "credit", "amount": 25,
 "kind": "refund", "counterparty": "house_revenue", "counterparty_user_id": null, "tournament_id": null, "match_id": null, "...": "..."}
{"entry_id": "ledger:42090", "created_at": "2026-11-24T09:44:06.753612Z", "currency": "token", "direction": "credit", "amount": 250,
 "kind": "refund", "counterparty": "tournament_escrow", "counterparty_user_id": null,
 "tournament_id": "f1a95eea-8468-64da-5d23-667828f2a704", "match_id": null, "...": "..."}
```

Real, the winner's prize:

```json
{"entry_id": "ledger:42108", "created_at": "2026-11-24T09:44:54.668615Z", "currency": "token", "direction": "credit", "amount": 650,
 "kind": "prize", "counterparty": "tournament_escrow", "counterparty_user_id": null,
 "tournament_id": "f1a95eea-8468-64da-5d23-667828f2a704", "match_id": null,
 "item_kind": null, "item_name": null, "game_code": null, "variant_code": null}
```

Balances, real: each player 600 tokens before; the winner ended at 975 (600 - 275 + 650), 2nd
at 675 (600 - 275 + 350), 3rd and 4th at 325 (600 - 275). A player with no prize gets no
`prize` row.

### Cancelled tournament and refunds

Real: the four players filled the next copy and nobody joined its table. Two minutes later
(seat deadline 09:47:54) the table was void, and at 09:47:59 the tournament was `refunded`
and every entry got its buy-in **and** fee back:

```json
// GET /tournaments/a439b6c4-a868-42e6-ac2d-2cb2a21b9910
{"id": "a439b6c4-a868-42e6-ac2d-2cb2a21b9910", "game_id": 1, "mode_id": 58, "name": "Weekday Ladder Final",
 "tournament_type": "single_table_sng", "status": "refunded", "max_players": 4, "current_players": 4,
 "entry_fee": 250, "fee_amount": 25, "currency": "token", "prize_pool": 1000, "starts_at": "2026-11-24T09:44:14.642114Z"}

// GET .../my-table (players cut to one)
{"tournament_status": "refunded", "entry_status": "withdrawn",
 "table": {"round": 1, "table_number": 1, "status": "closed", "seat": 0, "room_code": "70d189c4",
  "match_id": "70d189c4-d001-4965-85a5-73b3540665da", "seat_deadline_at": "2026-11-24T09:47:54.696Z", "place": null,
  "players": [{"player_id": "3d3ad895-d55d-4e58-b75f-e04e291f358f", "username": "w06doca1795513349", "seat": 0, "place": null, "leave_reason": "withdrawn"}]}}

// GET .../standings
[]

// ledger, newest first
{"entry_id": "ledger:42134", "created_at": "2026-11-24T09:47:59.646213Z", "currency": "token", "direction": "credit", "amount": 25,
 "kind": "refund", "counterparty": "house_revenue", "tournament_id": null, "...": "..."}
{"entry_id": "ledger:42133", "created_at": "2026-11-24T09:47:59.646213Z", "currency": "token", "direction": "credit", "amount": 250,
 "kind": "refund", "counterparty": "tournament_escrow", "tournament_id": "a439b6c4-a868-42e6-ac2d-2cb2a21b9910", "...": "..."}
```

A tournament is cancelled and refunded when: nobody comes to a Sit & Go table (real); a
scheduled tournament or score window has too few entries at its start (code); or an operator
cancels it (code). Refunds are automatic: the player does nothing. They are written once (a
retry on the server never pays twice).

**What the app does:**

- `cancelled` or `refunded`, and the player was entered: "This tournament was cancelled.
  Your 275 tokens have been refunded." Re-read the wallet. The amount is
  `entry_fee + fee_amount`; the ledger rows are the proof.
- `cancelled` (not yet `refunded`): "Cancelled. Your refund is on its way." Refunds normally
  land within seconds.
- The API does not say **why** it was cancelled (see "Known issues", 3); use one neutral
  message.
- Ignore `prize_pool` and `current_players` on a cancelled tournament (they keep their last
  values, real: `1000` and `4` above).
- `my-table` reads `entry_status: "withdrawn"` after a cancel; don't show "You left".

---

## 8. Standings, rounds and bracket

### `GET /tournaments/{id}/standings`

Every entry except withdrawn ones, best place first; entries without a place come last,
sorted by username. Real, after our Sit & Go:

```json
[
  {"place": 1, "player_id": "8b4a149e-f880-441e-8660-8e5799616181", "username": "w06docd1795513349", "entry_status": "winner",
   "matches_won": 1, "matches_lost": 0, "prize_amount": 650, "prize_currency": "token"},
  {"place": 2, "player_id": "047466bd-3ba0-4f71-862a-fe5222bea86d", "username": "w06docc1795513349", "entry_status": "busted",
   "matches_won": 0, "matches_lost": 1, "prize_amount": 350, "prize_currency": "token"},
  {"place": 3, "player_id": "8fe11c59-fe42-4100-9c34-891b97681130", "username": "w06docb1795513349", "entry_status": "busted",
   "matches_won": 0, "matches_lost": 1, "prize_amount": 0, "prize_currency": null},
  {"place": 4, "player_id": "3d3ad895-d55d-4e58-b75f-e04e291f358f", "username": "w06doca1795513349", "entry_status": "busted",
   "matches_won": 0, "matches_lost": 1, "prize_amount": 0, "prize_currency": null}
]
```

While registering or running, real: every row has `"place": null`, `"prize_amount": 0` and
`entry_status` `registered` or `active`. A cancelled tournament: `[]` (real).

| Field | Meaning |
|---|---|
| `place` | Final place (1 = winner), `null` until decided. Tied players share a place. |
| `entry_status` | As in `my-table`. |
| `matches_won`, `matches_lost` | Tables won and lost. |
| `prize_amount`, `prize_currency` | The prize paid (`0` and `null` for none). |

**What the app does:** the Results screen lists place, name, prize; highlight the player's
own row; a trophy for places with a prize. While running, show it as "Players" without
places.

### `GET /tournaments/{id}/rounds`

Rounds with their tables and seats, for a "Tables" view. Real, our Sit & Go after the end
(seats cut to two):

```json
[{"number": 1, "status": "completed", "seed": 777241965933346041,
  "starts_at": "2026-11-24T09:44:14.653061Z", "ends_at": "2026-11-24T09:44:54.666999Z",
  "tables": [{"id": "c0c24d19-a7d8-457a-be16-f421ccf54d0b", "table_number": 1, "status": "closed",
    "match_id": "1fbbb0ed-5949-4601-add7-d147033c8e4b", "opened_at": "2026-11-24T09:44:14.667917Z",
    "seat_deadline_at": "2026-11-24T09:46:14.665Z", "closed_at": "2026-11-24T09:44:54.649138Z", "last_error": null,
    "seats": [
      {"player_id": "8b4a149e-f880-441e-8660-8e5799616181", "username": "w06docd1795513349", "seat": 2, "place": 1, "leave_reason": "finished"},
      {"player_id": "047466bd-3ba0-4f71-862a-fe5222bea86d", "username": "w06docc1795513349", "seat": 3, "place": 2, "leave_reason": "busted"}]}]}]
```

`[]` before the first round (real). Round `status` is `active` while playing, `completed`
after. Ignore `seed` and `last_error` (server diagnostics). A Sit & Go has one round with one
table, so the app can skip this screen for Sit & Go and use `my-table` and `standings`.

### `GET /tournaments/{id}/bracket`

Pairings of a knockout format, from code:

```json
[{"id": "…", "tournament_id": "…", "bracket_type": "winners", "round": 1, "position": 1,
  "player_a_id": "…", "player_b_id": "…", "winner_id": null, "match_id": null,
  "parent_bracket_id": "…", "status": "pending"}]
```

`bracket_type`: `winners`, `losers`, `grand_final`; `status`: `pending`, `ready`, `active`,
`completed`, `walkover`. Today it is always `[]` (real, and no knockout format runs yet).
Build the screen only when knockout tournaments run; until then, don't link to it.

---

## End-to-end flow: from the list to the prize (real, Ludo)

```
App (player)                     Gateway                         Ludo socket
 |-- GET /tournaments?game_id=1&status=registering ->|
 |<- list: "Weekday Ladder Final" 0/4, 250+25 -------|
 |-- GET /wallet/balance --------------------------->|  600 tokens: Join enabled
 |-- POST /tournaments/{id}/register --------------->|  201; buyin + fee rows
 |-- GET /tournaments/{id}/my-table (every 10 s) --->|  registered, table null
 |        ... three more players join; the 4th fills it; it starts ...
 |-- GET /tournaments/{id}/my-table ---------------->|  running, table playing, room_code
 |-- open ws, auth.login ------------------------------------------------------->|
 |-- room.join {room_code} ----------------------------------------------------->|
 |<- room.joined {tournament: {round 1, table 1}} -------------------------------|
 |-- player.ready -------------------------------------------------------------->|
 |<- game.started ---------------------------------------------------------------|
 |        ... play; game ends ...
 |-- GET /tournaments/{id}/my-table ---------------->|  completed, entry winner, place 1
 |-- GET /tournaments/{id}/standings --------------->|  place 1, prize 650
 |-- GET /wallet/balance --------------------------->|  975 tokens; prize row in ledger
```

Timings seen (real, 24 Nov 2026): register at 09:44:10-09:44:12; started and table opened
at 09:44:14 (seat deadline 09:46:14); all four joined and readied by 09:44:21; game over
09:44:53; completed and paid 09:44:54.

Controller states:

| State | Enter when | Show |
|---|---|---|
| `notEntered` | `entry_status` null or `withdrawn`, status `registering` | Join |
| `entered` | `entry_status` `registered` | "Waiting for players 3 / 4", Leave |
| `tableReady` | `table.status` `playing` and `room_code` set | Table hand-off, Go, deadline countdown |
| `atTable` | the socket's `room.joined` | The game |
| `waitingResult` | the game ended, status still `running` | "Results coming" |
| `finished` | status `completed` | Results (place, prize) |
| `cancelled` | status `cancelled` or `refunded` | Cancelled, refund note |

---

## 9. Purchase refunds (the `refunds` module)

Not part of tournaments; documented in full in `11-store.md`. In short (real, 24 Nov 2026):
`GET /sensitive/refunds/my` returns the player's purchase refund requests (`[]` for a new
player), and `POST /sensitive/refunds/request` `{"transaction_id": <purchase id>, "reason":
"10 to 1000 characters"}` asks for one. A short reason answers `400 VALIDATION_ERROR`
(`field: "reason"`); an unknown purchase `404 NOT_FOUND` (`transaction not found`). Both are
under `/sensitive/` (device check). Never use them for tournament money.

---

## Errors

The error body and the shared codes are in `00-conventions.md`. Summary for this file:

| Status | `error` | Route | Meaning |
|---|---|---|---|
| 400 | `BAD_REQUEST` | list | Bad `status` or `game_id`. |
| 400 | `BAD_REQUEST` | any `{id}` | Not a UUID. |
| 400 | `BAD_REQUEST` | join | Not open, or the registration window is closed or not open yet. |
| 400 | `BAD_REQUEST` | leave | Already started or ended. |
| 401 | `UNAUTHORIZED` | all | Interceptor (`01-auth.md`). |
| 403 | `FORBIDDEN` | join | Level, membership, ban, self-exclusion, cooling off, loss or spend limit. |
| 404 | `NOT_FOUND` | all `{id}` | No such tournament; on leave also "not registered". |
| 409 | `CONFLICT` | join | Already entered. |
| 409 | `TOURNAMENT_FULL` | join | No free seat. |
| 409 | `INSUFFICIENT_FUNDS` | join | Can't cover buy-in + fee. |
| 503 | `KILL_SWITCH_ENGAGED` | join | Store or game paused; show `message`. |

---

## Known issues (the app must cope)

Found while writing this file (24 Nov 2026); reported to the lead, not fixed.

1. **Most formats never start.** Only Sit & Go and score windows are run by the server.
   Multi-table, knockout, swiss, ladder and the rest are listed, take entries and buy-ins,
   and then either roll forward a week (no entries), get cancelled and refunded (too few), or
   stay `registering` past their start (enough entries). Until they run, show them as "Coming
   soon" without Join, or hide them. If the product wants them joinable, warn the player.
2. **Fee rows have no `tournament_id`.** The `fee` debit and the fee's `refund` credit carry
   `tournament_id: null` (only the buy-in and prize rows have it). `03-wallet.md` assumed both
   had it. Pair a fee row with the buy-in row of the same `created_at`, or label it "Tournament
   fee" without a link.
3. **No cancellation reason, and stale numbers.** The API has no field for why a tournament
   was cancelled (the server stores one, for example "void board: the match was cancelled or
   abandoned"). A cancelled tournament keeps its `prize_pool` and `current_players`, and its
   round still reads `active` in `rounds`. Show one neutral message and ignore those fields.
4. **Paging is not checked on this list.** `per_page=0` makes the gateway drop the connection
   with no reply (real: `curl: (52) Empty reply from server`); `per_page=500` and `page=0`
   are accepted (`page=0` returns page 1's rows with `"page": 0`). Always send `page` >= 1
   and `per_page` 1 to 100.
5. **One code for three refusals.** Level too low, membership required and responsible-gaming
   blocks are all `403 FORBIDDEN`; the app has to read `message` to pick the text.
6. **The list doesn't say what is required or how prizes split.** No minimum level, required
   membership, registration window, minimum entries or payout split is in the reply. Show the
   level or membership requirement only from the join error; show the split only on the
   Results screen (from `standings`).
7. **No "my tournaments" and no push.** There is no route listing the tournaments a player
   entered, and nothing tells the app when a Sit & Go starts. Keep the ids the player joined
   on the device (and recover them from `buyin` rows in the ledger after a reinstall), and
   re-read `my-table` every 10 seconds while a tournament screen is open; the 2-minute seat
   deadline leaves time for that. A local notification is not possible without a push; say
   "Stay on this screen, your table opens when it's full."
8. **Finished is oldest first.** The list has no sort order parameter (see 1).
9. **`starts_at` of a Sit & Go is meaningless** (an old date for the seeded one, the copy time
   for copies). Never show it for a Sit & Go.

---

## Done when

- [ ] The lobby shows Upcoming, Running and Finished from `GET /tournaments` with `game_id`,
      one status per call, and Finished newest first.
- [ ] A Sit & Go row shows "3 / 4", "Starts when full" and "250 + 25 tokens", and no start
      time.
- [ ] Join is greyed out when the wallet can't cover `entry_fee + fee_amount`.
- [ ] Join asks to confirm, then shows "You're in"; the wallet chip drops by 275; history shows
      a `buyin` and a `fee` row.
- [ ] Leave asks to confirm, returns the full 275, and shows two `refund` rows; Join works
      again after it.
- [ ] Each join error in 4 shows its message (`TOURNAMENT_FULL` offers the new copy,
      `INSUFFICIENT_FUNDS` offers the shop, `CONFLICT` just refreshes).
- [ ] With four test players on four devices, the Sit & Go starts when the fourth joins; within
      10 seconds every device shows "Your table is ready" with the seat deadline countdown.
- [ ] Go joins the Ludo table with `room.join` and the `room_code`; the board shows
      "Round 1, Table 1"; the game starts when all are ready.
- [ ] After the game, the Results screen shows places and prizes from `standings`, and the
      winners' balances and `prize` rows match.
- [ ] A Sit & Go whose table nobody joins shows "Cancelled, your 275 tokens have been refunded"
      about two minutes later, and two `refund` rows appear.
- [ ] Unknown `status`, `tournament_type`, `entry_status` or `leave_reason` values show a
      neutral label, not a crash.
- [ ] Formats the server doesn't run are hidden or shown as "Coming soon" without Join.
- [ ] No list call sends `per_page` outside 1-100 or `page` 0.

---

## Test accounts

Create your own players with Sign up (`01-auth.md`) on the development server, one per
device, each with its own `device_id`. A new player has 100 tokens and 500 gold; the welcome
bonus (`07-rewards.md`) adds 500 tokens, enough for the 250 + 25 Ludo Sit & Go. A 4-seat Sit
& Go needs four accounts on four devices (or the Ludo debug page as extra players, see
`games/ludo.md`). Don't use other people's accounts, and never use admin accounts: the app
cannot create or start tournaments, so test with what the lobby lists.

The samples in this file came from five accounts made for it on 24 Nov 2026 (password not
recorded here):

| Account | User id | Role in the samples |
|---|---|---|
| `w06doca1795513349` | `3d3ad895-d55d-4e58-b75f-e04e291f358f` | Joined, left, joined again; 4th place |
| `w06docb1795513349` | `8fe11c59-fe42-4100-9c34-891b97681130` | 3rd place |
| `w06docc1795513349` | `047466bd-3ba0-4f71-862a-fe5222bea86d` | 2nd place, prize 350 |
| `w06docd1795513349` | `8b4a149e-f880-441e-8660-8e5799616181` | Winner, prize 650 |
| `w06doce1795513349` | `7d3dcb1b-ea03-4748-8d3a-ad9a7e18566b` | No welcome bonus: `INSUFFICIENT_FUNDS`, then `TOURNAMENT_FULL` |

Tournaments used: "Weekday Ladder Final" `f1a95eea-8468-64da-5d23-667828f2a704` (played,
`completed`) and its copy `a439b6c4-a868-42e6-ac2d-2cb2a21b9910` (table not joined,
`refunded`).
