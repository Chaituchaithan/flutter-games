# Flutter hand-off 8: progress and history

A player's levels and XP, ratings, per-game stats, leaderboards and match history (the list
and one past match).

This file is the contract between the Flutter app and the **api-gateway** for progress and
history. It is written so a Claude agent can implement it directly. Read `00-conventions.md`
first: the error body, list shapes, ids, money and times are defined there and not repeated
here. Sessions and the auth interceptor come from `01-auth.md`. Achievements are in
`07-rewards.md`; the wallet side of a match (entry fees and payouts) is in `03-wallet.md`.

**Where the samples come from.** Replies marked **(live)** were captured from the running
gateway and the Ludo socket on 24 Nov 2026, with three fresh test players. They read their
progress, played two free Ludo games (one `friends_room`, one `ranked_2p` quick match, each
ended by a forfeit) and read it again. Replies marked **(from code)** were not captured; their
shape is read from the gateway source. Long arrays are trimmed; each trim is noted.

---

## For the Claude agent: what to build

1. A `ProgressApi` on the shared `ApiClient` with one method per route below:
   `levels()`, `ratings()`, `gameStats(gameId)`, `leaderboard(gameId, metric, {limit,
   offset})`, `myRank(gameId, metric)`, `history({page, perPage})` and `match(matchId)`.
2. Models `GameLevel`, `GameRating`, `GameMmr`, `GameStats`, `LeaderboardEntry`, `MyRank`,
   `HistoryEntry`, `RoundBet`, `MatchDetail` and `MatchParticipant`. Parse leniently: most
   fields can be `null` (see each table).
3. A `ProgressStore` (one per signed-in user) that holds levels and ratings and re-reads them
   after a game ends (see "After a game").
4. Screens:
   - **Profile / Progress**: one card per game played, with the level, an XP bar and the
     rating (if the player has played a ranked mode).
   - **Game page header**: the player's level and rating for that game (`gameStats`).
   - **Leaderboards**: one screen per game with three tabs (Wins, Rating, Tokens won), the
     top of the list and a pinned "You" row from `myRank`.
   - **History**: the player's matches, newest first, with "load more".
   - **Match detail**: the players, places, results, stakes and payouts, rating change.
   - The **result screen** after a game shows XP gained and the rating change from a re-read
     (see "After a game").
5. Tests: model parsing for each live reply here (including the all-`null` stats reply and
   the empty lists), the XP bar maths, the history "load more" loop, the "You" row when
   `rank` is `null`, and the error mapping.

---

## Endpoints at a glance

All paths are under `http://<host>:1280/api/v1`. All need `Authorization: Bearer
<access_token>`. None has the device check. All are reads (`GET`).

| What | Method and path | Success | List shape |
|---|---|---|---|
| My levels, every game | `GET /progression/levels` | `200` | plain array |
| My ratings, every game | `GET /progression/ratings` | `200` | plain array |
| My level, rating and MMR in one game | `GET /progression/{game_id}/stats` | `200` | object |
| A leaderboard | `GET /leaderboards/{game_id}/{metric}?limit=&offset=` | `200` | plain array |
| My place on a leaderboard | `GET /leaderboards/{game_id}/{metric}/my-rank` | `200` | object |
| My match history | `GET /matches/my-history?page=&per_page=` | `200` | page list (shape 2) |
| One match | `GET /matches/{match_id}` | `200` | object |

- `game_id` is the **numeric** game id from `GET /games` (`04-game-catalogue.md`); Ludo is
  `1` on the development server. Look it up by `code`; don't hard-code it. A game code in the
  path is a `400` (see "Errors").
- `match_id` is a UUID: the same id as the game socket's `room_id` / `match_id` and the
  ledger's `match_id` (`03-wallet.md`).
- **What does not exist:** no overall (all-games) account level, no global leaderboard across
  games, no daily, weekly or monthly leaderboards, no friends leaderboard, and no route for
  another player's levels, ratings or history. Don't build screens for them. Tournament
  standings are in `06-tournaments.md`.
- `POST /matches/{id}/flag` (report a match) belongs to `12-safety.md`. `GET /matches`
  (all matches) is admin only; the app never calls it.

---

## How progress works

Every game service settles a finished match in one database transaction: it writes each
player's result, the wallet rows (`03-wallet.md`), the stats, the rating, the level, and the
achievement and quest progress (`07-rewards.md`). So everything in this file changes **at the
same moment**, and only once per match. Bots get none of it.

### XP and levels (per game)

Levels are **per game**: a player has a Ludo level, a Chess level, and so on. A game appears
in `GET /progression/levels` only after the player finishes a match of it.

XP per finished match (from code, `portal-common/src/services/match_stats.rs`; seen live for
`win` and `forfeit`):

| Result | XP |
|---|---|
| `win` | 100 |
| `draw` | 50 |
| `loss` | 25 |
| `forfeit` | 10 |

- Every mode gives XP: free or staked, ranked or not, tournament or not. The stake makes no
  difference.
- A player starts at level 1 with 0 XP. Going from level `n` to `n + 1` costs `100 × n` XP
  (level 1 to 2: 100, 2 to 3: 200, 3 to 4: 300). Leftover XP carries over.
- `xp` in the replies is the XP **toward the next level**, not the lifetime total. It resets
  on each level-up.
- The reply does not include the XP needed for the next level. Until it does, the XP bar uses
  `next = 100 × level` (see "Known issues", 1).

Live: player A won (100 XP) and went from no row to level 2 with 0 XP; won again and was at
level 2 with 100 of 200 XP. Player B forfeited and was at level 1 with 10 XP.

### Ratings (per game, ranked modes only)

- The rating is an Elo **MMR** per game. It starts at **1000** and moves only in **ranked**
  modes (`is_ranked: true` in `GET /games/{id}/modes`; for Ludo: `ranked_2p`, `ranked_4p`,
  `duel_ranked`). Free friends rooms, casual modes and tournament tables never move it.
- The most a rating moves in one match is 32 (K = 32). Two new players at 1000: the winner
  gets +16, the loser -16 (live).
- A game appears in `GET /progression/ratings` only after the player's **first ranked**
  match of it. A player who only played casual games has an empty ratings list (live), even
  with wins.
- Bots don't count: the rating is scored only against the other humans in the match. A
  ranked game with one human and only bots moves it by 0 (from code), though it still
  creates the rating row.

### Stats (wins, losses, draws)

Each finished match adds one to the player's `wins`, `losses` or `draws` for that game, across
**every mode** (ranked or not) and both currencies. A **forfeit is counted apart** and is in
none of the three: player C forfeited a ranked game and read `wins 0, losses 0, draws 0`
(live). The forfeit count, streaks, play time and earnings are stored but no player route
returns them yet (see "Known issues", 2 and 3).

---

## 1. My levels

`GET /progression/levels`. No query.

Every game the player has finished at least one match of, highest level first.

Live, player A before any game:

```json
[]
```

Live, player A 0.7 seconds after winning the first game (a free `friends_room` Ludo game):

```json
[{"user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "game_id": 1, "level": 2, "xp": 0,
  "updated_at": "2026-11-24T09:44:09.592033Z"}]
```

Live, player B (who forfeited that game):

```json
[{"user_id": "9ee1b34f-0fd6-44de-b4f9-2b8b52bdf0cf", "game_id": 1, "level": 1, "xp": 10,
  "updated_at": "2026-11-24T09:44:09.592033Z"}]
```

| Field | Type | Meaning |
|---|---|---|
| `user_id` | UUID | The signed-in player. |
| `game_id` | number | The game (`GET /games`). Name it from the catalogue. |
| `level` | number | The level in this game, 1 and up. |
| `xp` | number | XP toward the next level (resets on each level-up). |
| `updated_at` | ISO 8601 UTC | When the level last changed (the end of the last match). |

**What the app does with it**

- Profile / Progress screen: one card per row, with the game's icon and name from the
  catalogue, "Level 2", and an XP bar `xp / (100 × level)`.
- Games the player has never finished are not in the list. Show them as "Level 1" with an
  empty bar, or leave them out; don't treat a missing game as an error.
- Re-read after a game ends (see "After a game"), on pull to refresh and on app resume. Don't
  poll.

**Errors**: only the shared ones: `401 UNAUTHORIZED` (interceptor), `429 RATE_LIMITED`,
`503 DATABASE_BUSY`.

---

## 2. My ratings

`GET /progression/ratings`. No query.

Every game the player has a rating in (at least one **ranked** match), highest rating first.

Live, player A after one casual win (still empty):

```json
[]
```

Live, player A after also winning a `ranked_2p` game:

```json
[{"user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "game_id": 1, "rating": 1016.0,
  "wins": 2, "losses": 0, "draws": 0, "updated_at": "2026-11-24T09:44:19.002106Z"}]
```

Live, player C, who forfeited that ranked game:

```json
[{"user_id": "7120bc7c-ae1d-4f47-8ac8-96346f93cccd", "game_id": 1, "rating": 984.0,
  "wins": 0, "losses": 0, "draws": 0, "updated_at": "2026-11-24T09:44:19.002106Z"}]
```

| Field | Type | Meaning |
|---|---|---|
| `user_id` | UUID | The signed-in player. |
| `game_id` | number | The game. |
| `rating` | number with a fraction part (`1016.0`) | The MMR. Always a whole value; show it without decimals. |
| `wins`, `losses`, `draws` | number | The record in this game over **every** mode, not only ranked (player A's `wins: 2` counts the casual win too). Forfeits are in none of them. |
| `updated_at` | ISO 8601 UTC | The later of the last rating change and the last match. |

**What the app does with it**

- Show the rating on the Profile card of each game in the list, as a whole number.
- Show "Unranked" for a game that has a level but no rating row. Offer the ranked mode.
- Label the record "W / L / D" and don't add them up to a "games played" count (forfeits are
  missing). For the number of ranked games, use `mmr.games_played` from section 3.

**Errors**: the shared ones only.

---

## 3. One game: level, rating and MMR

`GET /progression/{game_id}/stats`

The three progress records of one game in one call. Use it on a game's page.

Live, player A before playing (and for any game the player hasn't played, including an
unknown `game_id`):

```json
{"level": null, "rating": null, "mmr": null}
```

Live, player A after the casual win only:

```json
{"level": {"user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "game_id": 1, "level": 2, "xp": 0,
           "updated_at": "2026-11-24T09:44:09.592033Z"},
 "rating": null,
 "mmr": null}
```

Live, player A after the ranked win as well:

```json
{
  "level": {"user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "game_id": 1, "level": 2, "xp": 100,
            "updated_at": "2026-11-24T09:44:19.002106Z"},
  "rating": {"user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "game_id": 1, "rating": 1016.0,
             "wins": 2, "losses": 0, "draws": 0, "updated_at": "2026-11-24T09:44:19.002106Z"},
  "mmr": {"user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "game_id": 1, "mmr": 1016,
          "peak_mmr": 1016, "games_played": 1, "updated_at": "2026-11-24T09:44:19.002106Z"}
}
```

| Field | Meaning |
|---|---|
| `level` | Same object as one row of section 1, or `null` before the first finished match. |
| `rating` | Same object as one row of section 2, or `null` before the first ranked match. |
| `mmr` | `null` before the first ranked match; otherwise `mmr` (the same value as `rating.rating`, as an integer), `peak_mmr` (the highest it has been), `games_played` (**ranked** matches only) and `updated_at`. |

`rating` and `mmr` are always both `null` or both set.

**What the app does with it**

- Game page header: "Level 2", the XP bar, and "Rating 1016 (best 1016)" or "Unranked".
- Each of the three can be `null` on its own terms; never fail on a `null`.
- A game id that doesn't exist is **not** an error: the reply is all `null` (live,
  `game_id` 99999).

**Errors** (live)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `game_id` is not a number (`/progression/ludo/stats`). | App bug: use the numeric id. |
| 401 | `UNAUTHORIZED` | As everywhere. | Interceptor. |

```json
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: can not parse to a i64"}
```

---

## 4. Leaderboards

One board per **game** and **metric**, all time. Each board lists every player who has a
score for it, best first.

| `metric` | Tab label | Score | Who is on it |
|---|---|---|---|
| `wins` | Wins | Wins in this game, all modes, both currencies. | Every player who finished a match of the game, **including 0 wins** (live: player B was 15th with `0.0`). |
| `rating` | Rating | The MMR (section 2). | Players with at least one ranked match. |
| `tokens_earned` | Tokens won | Total **token** payouts in this game. Gold is not counted. | Players with token winnings above 0. Free games never put anyone here. |

Players who turned off "Show me on leaderboards" (`show_on_leaderboards` in the privacy
settings, `02-profile-and-sessions.md`) are left out of every board and their own `my-rank`
is `null`.

### 4a. A leaderboard

`GET /leaderboards/{game_id}/{metric}?limit=&offset=`

| Query | Rule |
|---|---|
| `limit` | Optional, 1 to 100, default **20**. |
| `offset` | Optional, from 0, default 0, at most 1,000,000. Rows to skip. |

The reply is a **plain array** (no total, no cursor). Load more with `offset` = rows already
shown, until a page comes back shorter than `limit`.

Live (`/leaderboards/1/wins?limit=3`):

```json
[
  {"rank": 1, "user_id": "92ac29f6-61d3-4a2d-aad9-41e62c2b06cc", "score": 4.0, "username": "w05docb11951", "avatar_url": null},
  {"rank": 2, "user_id": "a397bea2-550b-4702-bfe3-5a336b68831b", "score": 2.0, "username": "fdoc7419", "avatar_url": null},
  {"rank": 3, "user_id": "2b48a770-e1c1-4eb5-9669-84e013e6c8cb", "score": 1.0, "username": "w07doc1795512062a", "avatar_url": null}
]
```

Live (`/leaderboards/1/rating?limit=2&offset=1`, the second page of a two-player board):

```json
[{"rank": 2, "user_id": "7120bc7c-ae1d-4f47-8ac8-96346f93cccd", "score": 984.0, "username": "w08doc1795513435c", "avatar_url": null}]
```

Live, a board with nobody on it yet (`/leaderboards/1/tokens_earned`), and an unknown game
(`/leaderboards/99999/wins`):

```json
[]
```

| Field | Type | Meaning |
|---|---|---|
| `rank` | number | 1 = best. Counted from the whole board, so page 2 starts at `offset + 1`. Ties get different ranks. |
| `user_id` | UUID | The player. Open their public profile (`02-profile-and-sessions.md`). |
| `score` | number with a fraction part (`4.0`) | The metric. Always whole for these three metrics; show it without decimals. |
| `username` | string or `null` | The player's username. `null` if the account is gone: show "Player". |
| `avatar_url` | string or `null` | The equipped avatar image. `null`: show the default avatar. |

### 4b. My place

`GET /leaderboards/{game_id}/{metric}/my-rank`

Live, before playing, and for a metric the player has no score on:

```json
{"rank": null, "score": null}
```

Live, player A after two wins (`/leaderboards/1/wins/my-rank`), then on the rating board:

```json
{"rank": 2, "score": 2.0}
{"rank": 1, "score": 1016.0}
```

| Field | Meaning |
|---|---|
| `rank` | The player's place, or `null` when they are not on this board. |
| `score` | Their score, or `null` with `rank`. |

### What the app does with it

- Leaderboard screen per game: tabs Wins / Rating / Tokens won. Each tab shows the first
  20 rows; "load more" adds `offset` += 20.
- Pin a **"You"** row at the bottom with `my-rank`. If `rank` is `null`, show "Play a match to
  get on the board" (Rating tab: "Play a ranked match ..."). If the player is in the visible
  rows, highlight that row instead.
- Show the top three with medals. Show `score` as a whole number.
- **The board can be up to an hour old** (it is cached; see "Known issues", 4). After a game,
  `my-rank` may already show the new place while the list still shows the old one. Show
  "Updated hourly" under the tabs and don't treat a mismatch as an error.
- Re-read when the screen opens and on pull to refresh. Never poll.
- When an operator freezes the leaderboards (a kill switch), the routes still answer `200`
  with the frozen standings. Nothing to handle.

**Errors** (live)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` (`field: "metric"`) | `metric` not `wins`, `rating` or `tokens_earned`. | App bug. |
| 400 | `VALIDATION_ERROR` (`field: "limit"`) | `limit` 0 or above 100. | App bug. |
| 400 | `BAD_REQUEST` | `game_id` not a number; `limit` or `offset` not a number. | App bug. |
| 401 | `UNAUTHORIZED` | No token or an expired one. The boards are not public. | Interceptor. |

```json
{"error": "BAD_REQUEST", "field": "metric", "message": "bad request: metric must be one of wins, rating, tokens_earned"}
{"error": "VALIDATION_ERROR", "field": "limit", "message": "validation error: limit: must be between 1 and 100"}
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: can not parse to a i64"}
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}
```

An unknown `game_id` is not an error: `[]` and `{"rank": null, "score": null}` (live).

---

## 5. Match history

`GET /matches/my-history?page=&per_page=`

Every match the player sat in, **newest first** (by when the match was created), every game
and every status, including the one being played right now.

| Query | Rule |
|---|---|
| `page` | Optional, starts at 1, default 1. |
| `per_page` | Optional, default **20**. Send 1 to 100 (see "Known issues", 5). |

The reply is list shape 2 from `00-conventions.md`: `{data, total, page, per_page,
total_pages}`. This route has no cursor; page with `page`.

Live, before any game:

```json
{"data": [], "total": 0, "page": 1, "per_page": 20, "total_pages": 0}
```

Live, player A while the first game was being played:

```json
{"data": [{"match_id": "2816e39e-61f6-44e1-8485-5d7483447f1c", "game_id": 1, "mode_id": 61,
           "status": "in_progress", "result": null, "stake_amount": 0, "payout_amount": 0,
           "created_at": "2026-11-24T09:44:08.131695Z", "ended_at": null,
           "game_code": "ludo", "game_name": "Ludo Royale",
           "mode_code": "friends_room", "mode_name": "Play with Friends", "bets": []}],
 "total": 1, "page": 1, "per_page": 20, "total_pages": 1}
```

Live, player A after both games, `?per_page=1` (page 1, then page 2):

```json
{"data": [{"match_id": "e3b14b75-1a6c-4093-acce-28d1a44a4028", "game_id": 1, "mode_id": 59,
           "status": "completed", "result": "win", "stake_amount": 0, "payout_amount": 0,
           "created_at": "2026-11-24T09:44:18.978802Z", "ended_at": "2026-11-24T09:44:19.002106Z",
           "game_code": "ludo", "game_name": "Ludo Royale",
           "mode_code": "ranked_2p", "mode_name": "Ranked 2 Players", "bets": []}],
 "total": 2, "page": 1, "per_page": 1, "total_pages": 2}

{"data": [{"match_id": "2816e39e-61f6-44e1-8485-5d7483447f1c", "game_id": 1, "mode_id": 61,
           "status": "completed", "result": "win", "stake_amount": 0, "payout_amount": 0,
           "created_at": "2026-11-24T09:44:08.131695Z", "ended_at": "2026-11-24T09:44:09.592033Z",
           "game_code": "ludo", "game_name": "Ludo Royale",
           "mode_code": "friends_room", "mode_name": "Play with Friends", "bets": []}],
 "total": 2, "page": 2, "per_page": 1, "total_pages": 2}
```

Player B's row for the first game is the same with `"result": "forfeit"` (live).

A Crash round with the player's bets (from code; the shape of `bets` items):

```json
{"match_id": "5b0d1c2e-7f3a-4e8b-9c6d-2a1b3c4d5e6f", "game_id": 8, "mode_id": 120,
 "status": "completed", "result": "win", "stake_amount": 200, "payout_amount": 150,
 "created_at": "2026-11-24T10:00:00Z", "ended_at": "2026-11-24T10:00:12Z",
 "game_code": "crash", "game_name": "Crash", "mode_code": "classic", "mode_name": "Classic",
 "bets": [
   {"bet_index": 0, "amount": 100, "auto_cashout_at": 2.0, "cashout_multiplier": 1.5, "payout_amount": 150, "outcome": "won"},
   {"bet_index": 1, "amount": 100, "auto_cashout_at": null, "cashout_multiplier": null, "payout_amount": 0, "outcome": "lost"}
 ]}
```

(The ids and the Crash game and mode ids in this sample are illustrative.)

### Entry fields

| Field | Type | Meaning |
|---|---|---|
| `match_id` | UUID | The match. Open it with section 6. The same id as the ledger's `match_id`. |
| `game_id`, `mode_id` | number | Catalogue ids. |
| `game_code`, `game_name` | string or `null` | The game, already named (`"ludo"`, `"Ludo Royale"`). |
| `mode_code`, `mode_name` | string or `null` | The mode, already named (`"ranked_2p"`, `"Ranked 2 Players"`). |
| `status` | string | `waiting`, `in_progress`, `completed`, `abandoned` or `cancelled`. Unknown values may appear: show them as "Finished". |
| `result` | string or `null` | The player's result: `win`, `loss`, `draw` or `forfeit`. `null` while the match runs, and for a cancelled or abandoned match. |
| `stake_amount` | number | What the player paid to enter (0 for a free game). |
| `payout_amount` | number | What the player was paid (0 for a loss or a free game). |
| `created_at` | ISO 8601 UTC | When the match was created. The list is sorted by it. |
| `ended_at` | ISO 8601 UTC or `null` | When it ended; `null` while it runs. |
| `bets` | array | Live-round games only (Crash and similar): the player's own bets in that round, in order. Empty for every other game. |

`bets` items: `bet_index` (0-based order), `amount`, `auto_cashout_at` (number or `null`),
`cashout_multiplier` (number or `null` if it did not cash out), `payout_amount`, `outcome`
(`won` or `lost`).

The history row has **no currency**. Take it from the match's ledger rows
(`GET /wallet/ledger`, rows with the same `match_id`, `03-wallet.md`) if the screen needs it,
or show the amounts without a currency icon.

### What the app does with it

- History screen: rows grouped by day (local time zone). Each row: the game icon,
  `game_name`, `mode_name`, a result chip (Won / Lost / Draw / Forfeit; "Playing" for
  `in_progress`; "Cancelled" for `cancelled` or `abandoned`), and for a staked match the net
  `payout_amount - stake_amount` (`+9`, `-10`).
- A row with `status: "in_progress"` can offer "Back to game" (reconnect, see the game's
  socket file) instead of opening the detail.
- **Load more:** `page` + 1 with the same `per_page`, until `page >= total_pages`. New
  matches arriving at the top shift the pages: drop rows whose `match_id` you already show.
- Pull to refresh reloads page 1.
- `total` = 0: "No matches yet. Play your first game."
- A game filter is not available on this route; filter on the device by `game_code` if you
  need one, or leave it out.

**Errors** (live)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `page` or `per_page` not a number. | App bug. |
| 401 | `UNAUTHORIZED` | As everywhere. | Interceptor. |

```json
{"error": "BAD_REQUEST", "message": "bad request: Query deserialize error: invalid digit found in string"}
```

`page=0` and `per_page` above 100 are **not** refused (see "Known issues", 5). Unknown query
names are ignored: `?per=1` (the wallet's name) returns the default 20.

---

## 6. One match

`GET /matches/{match_id}`

A match and every seat in it, players and bots. Open it from a history row, a ledger row or
the result screen.

Live, the ranked game, read by the winner after it ended:

```json
{
  "id": "e3b14b75-1a6c-4093-acce-28d1a44a4028",
  "game_id": 1,
  "mode_id": 59,
  "status": "completed",
  "server_seed": null,
  "server_seed_hash": null,
  "created_at": "2026-11-24T09:44:18.978802Z",
  "started_at": "2026-11-24T09:44:18.978802Z",
  "ended_at": "2026-11-24T09:44:19.002106Z",
  "participants": [
    {"id": 19802, "match_id": "e3b14b75-1a6c-4093-acce-28d1a44a4028",
     "user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "is_bot": false, "seat": 0,
     "stake_amount": 0, "payout_amount": 0, "result": "win",
     "rating_before": 1000, "rating_after": 1016, "final_rank": 1, "score": null,
     "custom_stats": {"all_pawns_homed": false, "captures": 0, "consecutive_sixes": 0, "finished": false,
                      "forfeited": false, "pawns_lost": 0, "place": 1, "safe_square_landings": 0,
                      "sixes": 0, "total_turns": 0}},
    {"id": 19803, "match_id": "e3b14b75-1a6c-4093-acce-28d1a44a4028",
     "user_id": "7120bc7c-ae1d-4f47-8ac8-96346f93cccd", "is_bot": false, "seat": 2,
     "stake_amount": 0, "payout_amount": 0, "result": "forfeit",
     "rating_before": 1000, "rating_after": 984, "final_rank": 2, "score": null,
     "custom_stats": {"all_pawns_homed": false, "captures": 0, "consecutive_sixes": 0, "finished": false,
                      "forfeited": true, "pawns_lost": 0, "place": 2, "safe_square_landings": 0,
                      "sixes": 0, "total_turns": 0}}
  ]
}
```

Live, the casual game while it was still being played (trimmed to the first seat):

```json
{"id": "2816e39e-61f6-44e1-8485-5d7483447f1c", "game_id": 1, "mode_id": 61, "status": "in_progress",
 "server_seed": null, "server_seed_hash": null,
 "created_at": "2026-11-24T09:44:08.131695Z", "started_at": "2026-11-24T09:44:08.131695Z", "ended_at": null,
 "participants": [{"id": 19800, "match_id": "2816e39e-61f6-44e1-8485-5d7483447f1c",
   "user_id": "107a8edf-6a2d-415e-b292-f756bc04cd4a", "is_bot": false, "seat": 0,
   "stake_amount": 0, "payout_amount": 0, "result": null, "rating_before": null, "rating_after": null,
   "final_rank": null, "score": null, "custom_stats": null}]}
```

After that casual game ended, each seat read `"rating_before": 1000, "rating_after": 1000`
(live): an unranked match records the rating without moving it.

### Match fields

| Field | Meaning |
|---|---|
| `id` | The match id. |
| `game_id`, `mode_id` | Catalogue ids. This reply has **no** game or mode names: take them from the history row you came from, or from the catalogue (`04-game-catalogue.md`). |
| `status` | As in history. |
| `server_seed_hash` | For provably fair games: the hash of the random seed, published before play. `null` for games that don't use one (Ludo: `null`, live). |
| `server_seed` | The seed itself, shown only once the match is `completed`, `abandoned` or `cancelled`; always `null` while it runs. With both, the player can check the hash. |
| `created_at`, `started_at`, `ended_at` | ISO 8601 UTC; `started_at` and `ended_at` can be `null`. |
| `participants` | Every seat, ordered by seat. |

### Participant fields

| Field | Meaning |
|---|---|
| `id` | The seat row id (a number). Use it as a list key only. |
| `user_id` | The player, or `null` for a bot seat. |
| `is_bot` | `true` for a bot. Show "Bot" (or the bot's name from the game socket if you kept it). |
| `seat` | The seat index (Ludo: 0 red, 1 green, 2 yellow, 3 blue), or `null` for seatless games. |
| `stake_amount`, `payout_amount` | What this seat paid and was paid. |
| `result` | `win`, `loss`, `draw`, `forfeit`, or `null` while the match runs. |
| `rating_before`, `rating_after` | The MMR before and after; `null` until the match is settled. Equal in an unranked match. The change is `rating_after - rating_before`. |
| `final_rank` | The place, 1 = first; `null` until settled. |
| `score` | The game's score (points, chips, ...), or `null` when the game keeps none (Ludo: `null`). |
| `custom_stats` | A game-specific object, or `null`. Ludo (live): `place`, `finished`, `forfeited`, `all_pawns_homed`, `captures`, `pawns_lost`, `sixes`, `consecutive_sixes`, `safe_square_landings`, `total_turns`. Other games put their own keys here (for example a racing finish time); each game's socket file names them. Show the keys you know and ignore the rest. |

**The reply has no usernames or avatars.** Get each player's name and avatar from the public
profile route (`02-profile-and-sessions.md`), by `user_id`, once per player, and cache them.
If the game socket is still open, the names from `room.created` / `room.joined` are enough.

### What the app does with it

- Match detail screen: the game and mode (from the history row), the date and length
  (`ended_at - started_at`), then one row per seat in `final_rank` order: place, avatar,
  name, result chip, `+16` / `-16` rating change for a ranked match, and the payout for a
  staked match. Highlight the signed-in player's row.
- For Ludo, a few lines from `custom_stats` (captures, sixes) make a good summary.
- For a provably fair game, a "Verify" section with `server_seed_hash` and, once ended,
  `server_seed`.
- `status: "in_progress"`: show "This match is still being played" and offer to rejoin
  instead.

**Errors** (live)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` | The id is not a UUID. | App bug. |
| 404 | `MATCH_NOT_FOUND` | No match with that id. | "This match is no longer available." Back to history. |
| 401 | `UNAUTHORIZED` | As everywhere. | Interceptor. |

```json
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: UUID parsing failed: invalid character: found `n` at 0"}
{"error": "MATCH_NOT_FOUND", "message": "match not found: 00000000-0000-4000-8000-000000000000"}
```

---

## After a game: how a finished Ludo game shows up here

The game socket says nothing about XP, levels or ratings. The app reads them from the gateway
after the end. Everything is written in the same transaction as the result and the wallet
rows, so it is there when the socket says the game is over.

What happened in the live run (timings from the end frame):

| Time | Where | What the app sees |
|---|---|---|
| 0 s | Ludo socket | `game.player_forfeited` (`game_over: true`, `winner_id`), then `game.state_update` with `game_over: true` and the places (`games/ludo.md`, section 6). Staked games then send `game.wallet_update`. |
| +0.7 s | `GET /progression/levels` | Winner: level 2, 0 XP (was no row). Loser (forfeit): level 1, 10 XP. |
| +1.4 s | `GET /progression/1/stats` | `level` set; `rating` and `mmr` still `null` (casual game). |
| +3.5 s | `GET /matches/my-history` | The row changed from `in_progress` / `null` to `completed` / `win` (`forfeit` for the loser), with `ended_at`. |
| +4.9 s | `GET /matches/{id}` | `final_rank`, `result`, `rating_before` = `rating_after` = 1000, `custom_stats`. |
| +6.4 s | `GET /leaderboards/1/wins/my-rank` | Winner `{"rank": 3, "score": 1.0}`; loser `{"rank": 15, "score": 0.0}`. |

After the second game (`ranked_2p`), 0.7 s after the end: the winner's
`GET /progression/ratings` read `1016.0`, the loser's `984.0`; the winner's level read
level 2 with 100 XP; `rating/my-rank` read 1 and 2.

**What the app does at the end of a game**

1. On `game_over: true`, show the result screen from the socket (places, payout).
2. Then, in parallel: `GET /progression/{game_id}/stats` and (staked games)
   `GET /wallet/balance`. Compare with the values held before the game to show "+100 XP",
   a level-up animation if `level` went up, and "+16 rating" for a ranked game. Read the
   "before" values when the game starts (or from `ProgressStore`), not after.
3. If the stats look unchanged (same `level` and `xp`), wait 2 seconds and read once more,
   then show what you have. Don't loop.
4. Mark the history and leaderboard screens stale; they re-read when next opened.
5. A finished match also moves quests and achievements (`07-rewards.md`); refresh the
   Rewards red dot at the same time.

The XP gained is not sent anywhere. For "+N XP", show the value from the XP table for the
player's `result` (win 100, draw 50, loss 25, forfeit 10). Draw the bar from the new
`level` and `xp`; a level-up is `new level > old level`.

---

## Errors

The error body and the shared codes are in `00-conventions.md`, "Errors". Each section above
lists what its route returns. All of these routes are reads: a `500` or `503` is shown as
"Couldn't load. Pull to refresh." with the cached data kept on screen.

---

## Limits

| What | Limit |
|---|---|
| All routes here | The general limit, about 100 requests a minute per player (`429 RATE_LIMITED`). |
| Polling | Never. Re-read on the events above, at most once every 10 seconds otherwise. |
| Leaderboard page | `limit` 1 to 100 (default 20); `offset` 0 to 1,000,000. |
| History page | `per_page` 1 to 100 (default 20); the server doesn't check it, the app must. |
| Leaderboard freshness | Up to 1 hour behind (cache). |

---

## Known issues (the app must cope)

1. **No "XP for next level" in the reply.** The level object has `level` and `xp` only. The
   server stores the next-level figure (`100 × level`) but doesn't send it. The app uses
   `100 × level` for the XP bar. If the server starts sending `exp_to_next_level`, prefer it.
2. **Forfeits are not losses.** The `wins`/`losses`/`draws` record in the ratings counts a
   forfeit as none of them, and no player route returns the forfeit count. A player who only
   forfeited reads 0-0-0.
3. **Most stats are not exposed to players.** Streaks, forfeits, best score, play time, money
   staked and won, the per-pool rating (`player_game_ratings`, starting at 1200, with
   `is_provisional`) and tournament records are stored, but only the admin console reads
   them. The app can't show "win streak" or "time played" yet.
4. **The leaderboard list is cached for up to an hour; `my-rank` is not, for new players.**
   The list comes from a cache built at the first read and kept for an hour. `my-rank` reads
   the same cache, but falls back to the live data when the player isn't in it. Live: after
   player A's second win, `wins/my-rank` read `{"rank": 2, "score": 2.0}` while the top-3
   list still had another player at rank 2 and didn't show A. Ties can also come back in a
   different order between the cached and live reads. Show "Updated hourly"; never compute
   ranks on the device.
5. **History paging is not checked.** `page=0` answers `200` with `"page": 0` and the first
   page's rows; `per_page=500` answers 500 rows. `per_page=0` answers `200` for a player with
   no matches, but for a player with matches it divides by zero on the server (from code):
   **never send `per_page=0`**. Always send `page` ≥ 1 and `per_page` 1 to 100.
6. **Any signed-in player can open any match** by id (live: player C read the detail of a
   match between A and B). The reply holds only ids, results and amounts, but don't rely on
   it being private, and don't build features on reading other people's matches.
7. **The history row has no currency**, and the match detail has no names (game, mode or
   players). See sections 5 and 6.
8. **`rating` and `score` are sent as `1016.0` / `4.0`** (numbers with a fraction part)
   while `mmr` is `1016`. Parse all as `num` and show whole numbers.
9. **`rating` in the match detail is the MMR**, also for unranked matches, where it doesn't
   move.

---

## Done when

- [ ] The Profile shows one card per game in `GET /progression/levels`, with "Level n" and an
      XP bar `xp / (100 × level)`; an empty list shows no cards and no error.
- [ ] A game with a level but no rating shows "Unranked"; a game with a rating shows it as a
      whole number.
- [ ] The game page header reads `GET /progression/{game_id}/stats` and copes with each of
      `level`, `rating`, `mmr` being `null`.
- [ ] Leaderboards: Wins / Rating / Tokens won tabs per game, 20 rows, "load more" with
      `offset`, a pinned "You" row from `my-rank` with the `null` case worded, and "Updated
      hourly".
- [ ] History: newest first, result chips for all four results and the in-progress and
      cancelled states, "load more" by `page` until `total_pages`, duplicates dropped, pull
      to refresh, and the empty state.
- [ ] `per_page` is always 1 to 100 and `page` always 1 or more.
- [ ] Match detail: seats in place order with names from the profile route, rating change
      for ranked matches, payouts for staked ones, Ludo `custom_stats` summary, and the
      `MATCH_NOT_FOUND` message.
- [ ] After a game: the result screen shows "+N XP", a level-up when it happens, and the
      rating change for a ranked game, from one re-read (and at most one retry after 2 s).
- [ ] Unknown `status`, `result`, `metric` values and unknown `custom_stats` keys never crash
      a screen.
- [ ] No route here is polled.

---

## Test accounts

Create your own players on the development server with `POST /auth/register` (any
`@example.com` email), as in `01-auth.md`. A new player has no levels, ratings, history or
leaderboard place. To fill them, play a free Ludo game between two of your own players
(`games/ludo.md`): a `friends_room` game moves levels, stats, history and the Wins board;
a quick match in `ranked_2p` with both players searching at the same time also moves the
rating. A forfeit ends a game at once. Don't use other people's accounts.

The samples here came from three players made for this file on 24 Nov 2026:
`w08doc1795513435a` (`107a8edf-6a2d-415e-b292-f756bc04cd4a`), `w08doc1795513435b`
(`9ee1b34f-0fd6-44de-b4f9-2b8b52bdf0cf`) and `w08doc1795513435c`
(`7120bc7c-ae1d-4f47-8ac8-96346f93cccd`). Matches: `2816e39e-61f6-44e1-8485-5d7483447f1c`
(friends room, A beat B) and `e3b14b75-1a6c-4093-acce-28d1a44a4028` (ranked, A beat C).
