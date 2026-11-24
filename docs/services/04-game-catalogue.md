# Flutter hand-off 4: game catalogue

The games list, and for each game its variants (rule sets), modes, stakes (entry fees),
power-ups, settings and achievements. This is what the app reads before it opens a game
socket: the catalogue says what can be played and for how much; the game socket plays it.

This file is the contract between the Flutter app and the **api-gateway**'s `games` routes.
It is written so a Claude agent can implement it directly. Read `00-conventions.md` (errors,
lists, money, ids, kill switches) and `01-auth.md` (tokens) first; this file links to them
instead of repeating them.

**Where the samples come from.** Every route below was called on the running development
gateway on 24 Nov 2026, for all 26 games, with a new test player. Samples marked **real**
are those replies, with long arrays trimmed to one or two items (the trim is noted). Samples
marked **from code** are built from the gateway source (`crates/api-gateway/src/modules/games/`)
because the case can't be produced without changing the database (for example a switched-off
game).

---

## For the Claude agent: what to build

1. A `CatalogueApi` with one method per route below, returning typed models (`Game`,
   `GameVariant`, `GameMode`, `Stake`, `PowerUp`, `GameConfig`, `GameAchievement`) or an
   `ApiError` (`00-conventions.md`).
2. A `CatalogueRepository` that caches replies in memory (see "Caching and refetching") and
   exposes `games()`, `gameByCode(code)` and, per game, `modes`, `variants` and `stakes`.
3. An app-side table **per game code**: the socket port (see "Game servers") and whether
   this app build has a screen for the game. The gateway sends neither.
4. Screens:
   - **Home / game picker**: the games from `GET /games?is_active=true`, in `sort_order`.
     A game the app has no screen for yet shows as "Coming soon".
   - **Game home**: the mode picker (grouped by variant), and for the picked mode the
     stake picker (by currency, in ladder order).
   - **Private room setup** (modes with `host_can_choose`): the host's options.
   - **Rules sheet**: the variant's description and the mode's rule options.
   - **Power-ups** and **Achievements** tabs on the game home, if the game has any.
5. A `PlaySelection` value built from the catalogue and handed to the game's socket code:
   `game_code`, `mode_code`, `currency`, `bet_amount`, and the host's picks (see "From the
   catalogue to the game socket").
6. Tests: parse every sample in this file; the stake shapes (fixed, range, blinds, point
   value); `GAME_NOT_FOUND` on a game's sub-route removes it from the cached list; the
   stake picker hides stakes above the balance; a socket `invalid_mode` refetches modes.

---

## Endpoints at a glance

All routes need `Authorization: Bearer <access_token>` (any signed-in player). None takes
a body. All replies are plain JSON arrays or objects (list shape 1 in `00-conventions.md`);
none is paged.

| Route | Returns | Success |
|---|---|---|
| `GET /games` | Every game, switched-off ones included (filter below). | `200`, array |
| `GET /games/{id}` | One game. | `200`, object |
| `GET /games/{id}/variants` | The game's active variants (rule sets). | `200`, array |
| `GET /games/{id}/modes` | The game's playable modes. | `200`, array |
| `GET /games/{id}/stakes` | The playable stake tiers of every mode. | `200`, array |
| `GET /games/{id}/power-ups` | The game's active power-ups. | `200`, array |
| `GET /games/{id}/config` | The game's settings blob, or `null`. | `200`, object or `null` |
| `GET /games/{id}/achievements` | The game's own achievements. | `200`, array |

`{id}` is the game's **numeric** id. Get it from `GET /games` by `code`. A code in its place
is a `400` (see "Errors").

Admin routes for the catalogue exist under `/admin/games/...` (console only, staff roles).
The app never calls them.

---

## 1. Games list

`GET /games`

| Query | Values | Default |
|---|---|---|
| `is_active` | `true` or `false` | Not sent: every game, on and off. |

**Always send `?is_active=true`.** Without it the list also holds switched-off games
(`is_active: false`), which the app can't open: every sub-route answers `404` for them.

**Success:** `200 OK`, an array in display order (`sort_order`, then `name`). Real, 2 of 26
items shown:

```json
[
  {
    "id": 25,
    "code": "snake-and-ladder",
    "name": "Snake & Ladder",
    "description": "Roll dice, climb ladders, dodge snakes -- race to the finish.",
    "icon_url": "/assets/games/snl/icon.svg",
    "min_players": 2,
    "max_players": 4,
    "supports_bots": true,
    "has_per_player_clock": false,
    "has_hidden_information": false,
    "is_real_time": false,
    "is_house_banked": false,
    "is_active": true,
    "sort_order": 1,
    "created_at": "2026-11-14T08:35:16.461863Z",
    "updated_at": "2026-11-14T08:35:16.461863Z"
  },
  {
    "id": 1,
    "code": "ludo",
    "name": "Ludo Royale",
    "description": "Classic race game with four pawns.",
    "icon_url": null,
    "min_players": 2,
    "max_players": 4,
    "supports_bots": true,
    "has_per_player_clock": false,
    "has_hidden_information": false,
    "is_real_time": false,
    "is_house_banked": false,
    "is_active": true,
    "sort_order": 2,
    "created_at": "2026-11-14T08:35:16.461863Z",
    "updated_at": "2026-11-14T08:35:16.461863Z"
  }
]
```

| Field | Meaning | App use |
|---|---|---|
| `id` | Numeric id for the `/games/{id}/...` routes. **Different per server**: development has Ludo at `1`, another server may not. | Look it up by `code` every session; never hard-code it. |
| `code` | Stable text key (`ludo`, `snake-and-ladder`, `teen_patti`; mixed `-` and `_`, use as is). | The app's key for everything about a game: its screen, socket port, assets, analytics. Sent on sockets that host several games (see below). |
| `name` | Display name, already branded (`Ludo Royale`, `Tile Crown` for code `scrabble`, `Letter Hive` for `spelling_bee`). | Show it. Never derive a name from `code`. |
| `description` | Short line, may be `null`. | Card subtitle. |
| `icon_url` | `null`, or a path such as `/assets/games/snl/icon.svg`. The gateway does **not** serve these paths (`404`). | Ship game icons in the app, keyed by `code`. Ignore `icon_url` for now (see "Open issues"). |
| `min_players`, `max_players` | The game's overall range across all modes (Crash: 1 to 1000). | Card text only ("2-4 players"). A mode's own seats are in the mode. |
| `supports_bots` | Some modes can fill seats with bots. | Optional badge. |
| `has_per_player_clock` | Chess-style clocks (chess, othello, checkers, carrom, snooker). | Informational; timers come from the mode. |
| `has_hidden_information` | Players hold hidden cards or tiles (poker, rummy, UNO...). | Informational. |
| `is_real_time` | Continuous play (racing, shooters, crash) rather than turns. | Informational. |
| `is_house_banked` | Players play against the house (crash, roulette), not each other. | Informational, for the help text. |
| `is_active` | `false`: the game is switched off. | Hide it (or don't ask for it: `?is_active=true`). |
| `sort_order` | Display order, low first. Several games can share a value; the list breaks ties by `name`. | Keep the reply's order. |
| `created_at`, `updated_at` | ISO 8601 UTC. | Not needed. |

**Fields the gateway does not send** (they are in the database but not in the reply):

- `launch_priority`: the team's build order (1 = Snake & Ladder, 2 = Ludo, ..., 26 =
  Tombola). It is a development plan, not a display order. The app never needs it. Use
  `sort_order` for display.
- `category` (`dice`, `board`, `card`, `casino`, `word`, `arcade`, `bingo`): if the home
  screen groups games by category, keep a `code -> category` map in the app for now.
- "Coming soon": there is no such field. Every game in the reply with `is_active: true` is
  switched on at the server. Whether this **app build** can play it is the app's own table
  (step 3 of "What to build"); show the others as "Coming soon".
- The socket host and port (see "Game servers").

**Errors:** `400 BAD_REQUEST` for an `is_active` value other than `true`/`false`; `401` (see
"Errors").

## 2. One game

`GET /games/{id}`

**Success:** `200 OK`, one object with the same fields as a list item. Real:

```json
{"id": 1, "code": "ludo", "name": "Ludo Royale", "description": "Classic race game with four pawns.", "icon_url": null, "min_players": 2, "max_players": 4, "supports_bots": true, "has_per_player_clock": false, "has_hidden_information": false, "is_real_time": false, "is_house_banked": false, "is_active": true, "sort_order": 2, "created_at": "2026-11-14T08:35:16.461863Z", "updated_at": "2026-11-14T08:35:16.461863Z"}
```

This route returns a switched-off game too (with `is_active: false`), unlike the sub-routes,
which answer `404` for it (from code). Check `is_active` in the reply. The app rarely needs
this route: the list already has every field.

**Errors:** `404 GAME_NOT_FOUND` for an unknown id; `400 BAD_REQUEST` for a non-numeric id.

## 3. Variants (rule sets)

`GET /games/{id}/variants`

A variant is a rule set: Ludo `classic`, `quick`, `teams`, `rush`, `duel`, `magic`. Every
mode plays one variant. Only active variants are listed, in lobby order.

**Success:** `200 OK`. Real, Ludo, 2 of 6 items:

```json
[
  {
    "id": 16,
    "code": "classic",
    "name": "Classic",
    "description": "4 tokens home · full board",
    "is_default": true,
    "rules_config": {"capture_extra_turn": true, "exact_roll_home": true, "extra_turn_on_six": true, "home_run_size": 6, "pawns_per_player": 4, "safe_squares": [0, 8, 13, 21, 26, 34, 39, 47], "six_to_start": true, "start_on_board": 0, "three_sixes_lose_turn": true, "track_size": 52},
    "design_key": "classic"
  },
  {
    "id": 88,
    "code": "rush",
    "name": "Rush",
    "description": "6-minute clock · most progress wins",
    "is_default": false,
    "rules_config": {"auto_roll": true, "auto_roll_ms": 5000, "capture_extra_turn": true, "engine_variant": "classic", "exact_roll_home": true, "extra_turn_on_six": true, "home_run_size": 6, "match_clock_ms": 360000, "pawns_per_player": 4, "progress_scoring": true, "safe_squares": [0, 8, 13, 21, 26, 34, 39, 47], "six_to_start": true, "start_on_board": 0, "three_sixes_lose_turn": false, "track_size": 52, "win_by": "progress"},
    "design_key": "rush"
  }
]
```

| Field | Meaning | App use |
|---|---|---|
| `id` | Numeric id; modes point to it with `variant_id`. | Group modes by variant. |
| `code` | Rule set code, unique per game. | Key for variant art and help text in the app. |
| `name`, `description` | Display text. `description` may hold `·` and other non-ASCII characters. | Variant card title and subtitle. |
| `is_default` | The variant to preselect. At most one per game; **some games have none** (Snake & Ladder today). | Preselect it; with none, preselect the first. |
| `rules_config` | The engine's rule values for this rule set. Keys differ per game. | Rules sheet only, and only keys the game's own hand-off file explains. The server applies the rules; never play by them on the device. |
| `rules_config.engine_variant` | When present, the rule set the game server actually runs (Ludo `rush` runs `classic` with the rush settings). | Explains why a socket reply may name a different `variant` (see section 9). |
| `design_key` | The console design card this row belongs to; may be `null`. | Not needed. |

**Errors:** `404 GAME_NOT_FOUND` for an unknown or switched-off game.

## 4. Modes

`GET /games/{id}/modes`

A mode is what the player actually picks: seats, ranked or not, timers and rule options, on
one variant. Only playable modes are listed: the mode **and** its variant are switched on.
Order: the server's `sort_order`, then name.

**Success:** `200 OK`. Real, Ludo, 2 of 18 items (`rule_options` trimmed to 1 item in the
second):

```json
[
  {
    "id": 57,
    "game_id": 1,
    "code": "casual_2p",
    "name": "Casual 2 Players",
    "description": null,
    "player_count": 2,
    "min_players": 2,
    "turn_timer_seconds": 10,
    "is_ranked": false,
    "is_active": true,
    "mode_config": {
      "rule_options": [
        {"default": true, "engine": "has", "key": "extra_turn_on_six", "label": "Bonus roll on six", "type": "bool"},
        {"default": true, "engine": "has", "key": "capture_extra_turn", "label": "Capture bonus roll", "type": "bool"},
        {"default": true, "engine": "has", "key": "three_sixes_lose_turn", "label": "Three sixes forfeit", "type": "bool"},
        {"default": true, "engine": "has", "key": "powerups_allowed", "label": "Power-ups allowed", "type": "bool"},
        {"default": true, "engine": "has", "key": "safe_squares", "label": "Safe squares", "type": "bool"}
      ],
      "timer": {"max_timeouts": 3, "time_bank_ms": 0, "turn_ms": 10000, "type": "turn"}
    },
    "variant_id": 16,
    "variant_code": "classic",
    "limit_label": "Standard"
  },
  {
    "id": 61,
    "game_id": 1,
    "code": "friends_room",
    "name": "Play with Friends",
    "description": null,
    "player_count": 4,
    "min_players": 2,
    "turn_timer_seconds": 15,
    "is_ranked": false,
    "is_active": true,
    "mode_config": {
      "capture_extra_turn": true,
      "extra_turn_on_six": true,
      "host_can_choose": ["turn_seconds", "extra_turn_on_six", "capture_extra_turn", "three_sixes_lose_turn", "safe_squares", "powerups_allowed"],
      "host_options": {
        "capture_extra_turn": {"label": "Capture bonus roll"},
        "extra_turn_on_six": {"label": "Bonus roll on six"},
        "powerups_allowed": {"label": "Power-ups allowed"},
        "safe_squares": {"label": "Safe squares"},
        "three_sixes_lose_turn": {"label": "Three sixes forfeit"},
        "turn_seconds": {"label": "Turn timer"}
      },
      "powerups_allowed": true,
      "rule_options": [
        {"default": true, "engine": "has", "key": "extra_turn_on_six", "label": "Bonus roll on six", "type": "bool"}
      ],
      "safe_squares": true,
      "three_sixes_lose_turn": true,
      "timer": {"allowed_turn_seconds": [10, 15, 20], "max_timeouts": 3, "time_bank_ms": 0, "turn_ms": 15000, "type": "turn"}
    },
    "variant_id": 16,
    "variant_code": "classic",
    "limit_label": "Standard"
  }
]
```

| Field | Meaning | App use |
|---|---|---|
| `id` | Numeric mode id; stakes point to it with `mode_id`. | Join stakes to modes. **Not** sent on the socket. |
| `code` | Mode code, unique per game (`casual_2p`, `friends_room`, `blitz_3_2`). | **The key the game socket takes** (`mode_code`). |
| `name`, `description` | Display text (`description` is often `null`). | Mode card. |
| `player_count` | The most seats the mode has (today always the same as the mode's maximum). | "4 players"; seat count of the waiting room. |
| `min_players` | Fewest players a game starts with. With `min_players < player_count` a room can be made with fewer seats (Ludo `friends_room`: 2 to 4). | Seat picker range for private rooms. |
| `turn_timer_seconds` | Seconds per turn for turn-based modes; `null` for clock, round and real-time modes. Same value as `mode_config.timer.turn_ms` / 1000. | "10 s turns" chip. |
| `is_ranked` | Results change the player's rating. | "Ranked" badge. |
| `is_active` | Always `true` in this reply (inactive modes are left out). | Ignore. |
| `variant_id`, `variant_code` | The variant (section 3) the mode plays: the catalogue's code, not the engine's. | Group the mode picker by variant. |
| `limit_label` | Short chip text from the design (`Standard`, `Casual`, `Ranked`, `Timed`, `Pot-Limit`); may be `null`. | Optional chip on the mode card. |
| `mode_config` | Settings blob; keys differ per game. The keys below are shared. | See the next table. |

### `mode_config` keys the app reads

`mode_config` is open: every game adds its own keys, and each game's hand-off file explains
those. The app should read only these shared keys and ignore the rest.

| Key | Shape | Meaning and app use |
|---|---|---|
| `timer` | object | The mode's clock. Four shapes, by `type` (all values in milliseconds): <br>`"turn"`: `turn_ms` per turn, `time_bank_ms` extra time, `max_timeouts` (timed-out turns in a row before the player is out), and for host-chosen times `allowed_turn_seconds` (e.g. `[10, 15, 20]`). <br>`"clock"`: chess-style, `initial_ms` per player, `increment_ms` per move, `first_move_ms` to make the first move. <br>`"round"`: a timed round; keys differ per game (`duration_ms`, `countdown_ms`, `race_cap_ms`, `call_interval_ms`, or `settings` naming a live room setup). <br>No `type` or no `timer`: the game socket sends its own deadlines. <br>Use it for the mode card ("3+2", "10 s turns", "90 s round"). **In play, always draw timers from the socket's deadlines**, not from these numbers. |
| `rule_options` | array | The rules this mode plays, as `{key, label, type, default, engine}`, sometimes with `cards` (the variants an option belongs to in a friends mode). `type` is `bool`, `choice`, `number` or `seconds`; `default` is the value. **Show only entries with `engine: "has"`**; `"pending"` means the game server doesn't apply that rule yet. For the rules sheet. |
| `host_can_choose` | array of keys | Only on private-room ("with friends") modes: the options the host may set when creating the room. A mode without it takes no host picks. |
| `host_options` | object | Labels for those keys: `{"<key>": {"label": "..."}}`, sometimes with `values`, `min`, `max`, `step` or `type`. The current value of a key is the top-level `mode_config.<key>`, or the matching `rule_options` default. For a timer key (`turn_seconds`) the choices are `timer.allowed_turn_seconds`. |
| `subscription_gate` | object | A daily cap on rated matches per subscription tier, in one of two shapes: `{"free_rated_per_day": 5, "silver_rated_per_day": 50, "gold_rated_per_day": null}` or `{"rated_per_day": {"free": 5, "silver": 50, "gold": null}}`. `null` = no cap. Show "5 free ranked games a day"; the socket refuses the next one. |
| `min_tier` | `"silver"` or `"gold"` | The mode needs that subscription (or higher; Royal counts as Gold). Show a lock and the plan; the socket refuses others with `tier_required`. |

The engine-side checks (quota, tier, seats) happen on the game socket; the app's job is to
explain them before the player taps.

**Errors:** `404 GAME_NOT_FOUND` for an unknown or switched-off game.

## 5. Stakes (entry fees)

`GET /games/{id}/stakes`

The entry fees a player can pick per mode and currency. Only tiers whose row, mode and
variant are all switched on are listed. Order: by `mode_id`; inside a mode, the design
ladder first (`tier_order` 1, 2, 3, ...), then unlabelled tiers by amount, then ranges.

**Success:** `200 OK`. Real, Ludo, 3 of 92 items (two gold ladder tiers and the token range
of `casual_2p`, mode id 57):

```json
[
  {"id": 338, "game_id": 1, "mode_id": 57, "currency": "gold", "stake_amount": 10, "min_stake_amount": null, "max_stake_amount": null, "stake_step": null, "base_payout_multiplier": 2.0, "is_active": true, "stake_label": "Entry", "tier_label": "10", "tier_order": 1, "small_blind": null, "big_blind": null, "point_value": null},
  {"id": 337, "game_id": 1, "mode_id": 57, "currency": "gold", "stake_amount": 25, "min_stake_amount": null, "max_stake_amount": null, "stake_step": null, "base_payout_multiplier": 2.0, "is_active": true, "stake_label": "Entry", "tier_label": "25", "tier_order": 2, "small_blind": null, "big_blind": null, "point_value": null},
  {"id": 57, "game_id": 1, "mode_id": 57, "currency": "token", "stake_amount": null, "min_stake_amount": 50, "max_stake_amount": 5000, "stake_step": 50, "base_payout_multiplier": 1.9, "is_active": true, "stake_label": null, "tier_label": null, "tier_order": null, "small_blind": null, "big_blind": null, "point_value": null}
]
```

Ludo `casual_2p` in full (real): gold Entry 10 / 25 / 50 / 100 / 250 / 500 / 1000, then
token 50 / 100 / 200 / 500 / 1000 / 2000, then a token range 50 to 5000 in steps of 50.

| Field | Meaning | App use |
|---|---|---|
| `id` | Stake row id. | List key only. **Not** sent on the socket. |
| `game_id`, `mode_id` | The game and the mode (`GET /games/{id}/modes` `id`). | Group by mode. A mode with no rows is free-only. |
| `currency` | `"gold"` or `"token"` (`00-conventions.md`, "Money"). | Currency tabs in the stake picker; the coin icon. |
| `stake_amount` | A fixed entry fee per player, whole number. | The amount to send as `bet_amount`. |
| `min_stake_amount`, `max_stake_amount`, `stake_step` | A range row: the player picks any amount from min to max in steps (`stake_amount` is `null`). | A slider or stepper. |
| `stake_label` | The ladder's name in the design: `Entry`, `Ticket`, `Card`, `Boot`, `Bet`, `Chip` (also `Blinds`, `Limits`, `Ante`, `Point value`, none active today). `null` for older tiers. | Picker heading ("Entry", "Boot"). |
| `tier_label` | The tier as printed (`"10"`, `"1/2"`, `"0.25 /pt"`). Set exactly when `stake_label` is. | Chip text, when present. Otherwise format the amount yourself. |
| `tier_order` | 1-based place in the ladder. | Keep the reply's order. |
| `small_blind`, `big_blind` | A blinds tier (poker-style); both `null` otherwise. | "Blinds 1/2". |
| `point_value` | A points tier (rummy, UNO points): currency per point, may be fractional; no amounts on such a row. | "0.25 per point". |
| `base_payout_multiplier` | The catalogue's prize estimate as a multiple of one stake. **Not reliable** (see below). | Don't show it as a prize. |
| `is_active` | Always `true` here. | Ignore. |

**The four row shapes** (from code, enforced by a database check): exactly one of

1. fixed: `stake_amount` set (672 of the 688 rows listed today, all 26 games);
2. range: `min_stake_amount` < `max_stake_amount`, with `stake_step` (16 rows, all token);
3. blinds: a range or fixed row that also has `small_blind` / `big_blind` (none active yet);
4. points: `point_value` set, every amount `null` (none active yet).

Parse all four; show the first two today and treat the others as "not supported in this
version" (hide the row) until the game's hand-off file covers them.

**Labelled and unlabelled tiers.** Most modes carry a gold ladder with a `stake_label` (the
design's table) and, on some games, older token tiers with `stake_label: null`. Both are
real, playable tiers. Show the labelled gold ladder first; whether to also show the token
tiers is a product choice (the console's debug pages show only labelled rows). Poker today
has only unlabelled token ranges.

**Prize.** The gateway sends no exact prize. `base_payout_multiplier` disagrees with what
the server pays: Ludo `casual_2p` at 10 gold says `2.0` (20), and the real payout was 19
(the pot less a 5% cut, `03-wallet.md` section 5); Ludo's 4-seat gold tiers also say `2.0`
although a 4-player pot is 4 stakes. Show the entry fee only, or a text such as "Winner
takes the pot, less a 5% fee". After the game show the real `payouts` from the socket
(`03-wallet.md`).

**Level-gated tiers.** A tier can need a minimum player level (`min_user_level` in the
database; 4 active rows today need level 5, for example Scrabble `ranked_2p` gold 10 and 50).
The reply does not include it, so the app can't grey these out. If the socket refuses one,
show its message (see "Open issues").

**What the app does with stakes:**

- Show the stakes of the picked mode, by currency, and grey out any above the player's
  balance (`GET /wallet/balance`, `03-wallet.md`).
- Free play is always allowed: send `bet_amount` 0 (or leave it out). A mode with no stake
  rows is free only.
- Send only a listed amount (or, for a range row, a value on its steps). Some game servers
  accept any whole amount the wallet covers (Ludo), others refuse an unlisted one (racing,
  the shooters, the word games, bingo); don't rely on the lenient ones.

**Errors:** `404 GAME_NOT_FOUND` for an unknown or switched-off game.

## 6. Power-ups

`GET /games/{id}/power-ups`

The game's active power-ups, in `sort_order`. 14 of 26 games have none (an empty array).

**Success:** `200 OK`. Real, Ludo, 1 of 4 items (the others: `force_six` 100, `extra_turn`
100, `home_rush` 75 tokens):

```json
[
  {
    "id": 28,
    "game_id": 1,
    "code": "shield",
    "name": "Shield",
    "description": "Block the three-consecutive-sixes penalty this turn.",
    "icon_url": "powerups/shield.svg",
    "effect_config": {"effect": "block_consecutive_sixes", "trigger": "pre_roll"},
    "price_currency": "token",
    "price_amount": 50,
    "is_consumable": true,
    "max_per_match": 2,
    "is_active": true,
    "sort_order": 1
  }
]
```

| Field | Meaning | App use |
|---|---|---|
| `code` | Power-up key. | The key the game socket uses for it (see the game's file). |
| `name`, `description` | Display text. | Power-up list and tooltips. |
| `icon_url` | A relative file name (`powerups/shield.svg`), not a URL the gateway serves. | Ship icons in the app by `code`. |
| `effect_config` | What it does, for the engine. | Not needed. |
| `price_currency`, `price_amount` | Price, or both `null` for one earned only in play. | Price tag. Buying goes through the store (`11-store.md`). |
| `is_consumable` | Used up when played. | "x2" counters. |
| `max_per_match` | How many a player can use in one match; `null` = no limit. | Disable the button at the limit. |

A mode can turn power-ups off: check its rule options (`powerups_allowed` or
`powerups_enabled`) before showing the power-up bar.

**Errors:** `404 GAME_NOT_FOUND` for an unknown or switched-off game.

## 7. Game settings

`GET /games/{id}/config`

One settings blob per game for its server, or `null` when the game has none (all 26 have one
today).

**Success:** `200 OK`. Real, Ludo, in full:

```json
{
  "game_id": 1,
  "config": {
    "board": {"player_colors": ["#d92a4a", "#1f8a5b", "#3a4a8a", "#c9a24a"], "theme": {"default": "classic_red_green_blue_yellow"}},
    "capture": {"token_grant": 5},
    "dice": {"roll_animation_ms": 800},
    "home": {"token_grant": 10},
    "turn": {"skip_after_misses": 3}
  },
  "version": 1,
  "updated_at": "2026-11-14T08:35:16.461863Z"
}
```

| Field | Meaning | App use |
|---|---|---|
| `config` | Server settings; keys differ per game. Most are server-side (anti-cheat, random number setup, bot tuning). | Read only keys the game's own hand-off file names (Ludo: `board.player_colors`, `dice.roll_animation_ms`). Ignore the rest. |
| `version` | Raised by one on every change. | Cache key: refetch when it changes (see "Caching"). |

Don't build features on undocumented keys; they change without notice.

**Errors:** `404 GAME_NOT_FOUND` for an unknown or switched-off game.

## 8. Game achievements

`GET /games/{id}/achievements`

The game's own achievements (platform-wide ones are left out), in the same shape as
`GET /achievements`. The player's progress and claiming are in `07-rewards.md`; this route
is for a game's "Achievements" tab.

**Success:** `200 OK`. Real, 2 items: Ludo (1 of 10) and a secret tiered one from Snake &
Ladder (trimmed to that one):

```json
[
  {
    "id": 15,
    "game_id": 1,
    "code": "ludo_first_win",
    "name": "First Win",
    "description": "Win your first Ludo match.",
    "criteria": {"count": 1, "event": "match_end", "result": "win"},
    "reward_tokens": 0,
    "reward_gold": 0,
    "exp_reward": 10,
    "icon_url": "/assets/achievements/ludo/first_win.svg",
    "sort_order": 0,
    "tiers": [],
    "trigger": null,
    "is_secret": false
  },
  {
    "id": 234,
    "game_id": 25,
    "code": "sl_phoenix",
    "name": "Secret achievement",
    "description": null,
    "criteria": {},
    "reward_tokens": 0,
    "reward_gold": 0,
    "exp_reward": 0,
    "icon_url": null,
    "sort_order": 8,
    "tiers": [
      {"tier": "bronze", "threshold": 1, "reward": {"kind": "tokens", "amount": 200}},
      {"tier": "silver", "threshold": 10, "reward": {"kind": "tokens", "amount": 900}},
      {"tier": "gold", "threshold": 100, "reward": {"kind": "gold", "amount": 2500}},
      {"tier": "royal", "threshold": 500, "reward": {"kind": "title", "name": "Secret achievement"}}
    ],
    "trigger": "game_event",
    "is_secret": true
  }
]
```

- `is_secret: true`: the name, description and criteria are hidden by the server. Show a
  locked "Secret achievement" card.
- `tiers` empty: a one-step badge with `reward_tokens`, `reward_gold`, `exp_reward`.
  Otherwise each tier has a `threshold` and a `reward` (`kind` `tokens`, `gold` or `title`).
- `criteria` is for the server; don't build progress from it (use `07-rewards.md`).
- Some games have none (empty array).

**Errors:** `404 GAME_NOT_FOUND` for an unknown or switched-off game.

---

## 9. From the catalogue to the game socket

The catalogue's numeric ids stay on the HTTP side. **A game socket is told what to play by
codes and amounts**, never by `game_id`, `mode_id`, `variant_id` or stake `id`.

| The player picked | The app sends on the socket | From |
|---|---|---|
| A game | Connects to that game's socket (port from the app's table). On a socket that hosts several games, also `game_code` = `games.code`. | `GET /games` `code` |
| A mode | `mode_code` = the mode's `code` | `GET /games/{id}/modes` |
| A stake | `currency` = the row's `currency`; `bet_amount` = `stake_amount` (or the picked range value). Free: `bet_amount` 0 or left out. | `GET /games/{id}/stakes` |
| Host options (private room) | One field per key in `mode_config.host_can_choose`, e.g. Ludo `turn_seconds: 15`, `safe_squares: false`. | `GET /games/{id}/modes` |

Ludo example (real frame from `games/ludo.md`), after picking Ludo, mode `friends_room`, no
stake, 15 s turns:

```json
{"id": "A-7", "event": "room.create", "data": {"mode_code": "friends_room", "max_players": 2, "turn_seconds": 15}}
```

The same with the 10-gold Entry tier: add `"currency": "gold", "bet_amount": 10`.

Notes:

- **Most games use `mode_code`, `currency` and `bet_amount`** (18 of 20 game servers read
  the stake through the shared `bet_amount` / `currency` parser). A few name some fields
  differently (poker and Teen Patti take a `buy_in`, UNO an `entry_fee`; crash and roulette
  join live rooms rather than modes). Each game's hand-off file gives its exact send fields;
  this table is the general rule.
- The socket's replies may name a **different `variant`** from the catalogue's
  `variant_code`, because the server reports the rule set it runs
  (`rules_config.engine_variant`). Match the catalogue to socket replies by `mode_code`,
  which is the same on both sides.
- When a mode was switched off after the app loaded the catalogue, the socket answers
  `invalid_mode`. Refetch modes and stakes, and go back to the mode picker.

### Game servers

The gateway doesn't say where a game's socket is (`00-conventions.md`, "Servers"). Keep a
`code -> port` table in the app's config. The development defaults (from the project's
example environment file; each game's hand-off file confirms its own):

| Port | Game codes |
|---|---|
| 1285 | `ludo` |
| 1292 | `snake-and-ladder` |
| 1283 | `chess` |
| 1295 | `carrom` |
| 1282 | `checkers` |
| 1286 | `othello` |
| 1291 | `scrabble` |
| 1284 | `crash` |
| 1289 | `roulette` |
| 1296 | `snooker` |
| 1293 | `uno` |
| 1287 | `poker` |
| 1290 | `rummy` |
| 1294 | `teen_patti` |
| 1281 | `bingo`, `tombola` (one server; send `game_code`) |
| 1297 | `word_duel`, `word_rush`, `spelling_bee`, `guess_royale` (one server; send `game_code`) |
| 1385 | `fighting` |
| 1395 | `hill_climb` |
| 1386 | `arena_shooter`, `zombie_survival`, `battle_royale` (one server; send `game_code`) |
| 1288 | `racing` |

---

## 10. Switched off: games, variants, modes, stakes, kill switches

Operators can take things out of play in two ways. The app sees them differently.

**1. Switched off in the catalogue** (the console's on/off toggles). The catalogue routes
already hide it:

| What is off | What the gateway does | App |
|---|---|---|
| A game | `GET /games?is_active=true` leaves it out. Its sub-routes answer `404 GAME_NOT_FOUND` (the same as an unknown game). `GET /games/{id}` still returns it with `is_active: false`. | Drop it from the cache and the home screen; if the player is on its game home, go back with "This game isn't available right now." |
| A variant | Left out of `variants`, and **all its modes** and their stakes are left out too. | Nothing extra. |
| A mode | Left out of `modes` and its stakes left out of `stakes`. The socket answers `invalid_mode`. | Refetch, back to the mode picker. |
| A stake tier | Left out of `stakes`. | Nothing extra. |

**2. Kill switches** (an operator's emergency pause, `00-conventions.md` "Kill switches").
A kill switch on a game (`game.<code>`) or the whole platform **does not change the
catalogue**: the game stays in `GET /games` with `is_active: true`, and the app learns of
it only when it tries to start something:

- on the game socket: `room.create`, `room.join`, `match.find`, `player.ready`, rematch and
  the live-room joins and bets are refused with `<event>_error` and code
  `kill_switch_engaged`; the `message` is the operator's banner and may be shown;
- on the gateway: tournament entry answers `503 KILL_SWITCH_ENGAGED` (`06-tournaments.md`).

There is no player route to read the kill switches in advance (see "Open issues"). Show
the banner, disable the game's play buttons for the rest of the visit, and let the player
try again later (after a few minutes, or when they reopen the game). Games already running
carry on.

---

## Caching and refetching

The replies have no `ETag` or `Cache-Control` headers. Sizes today: the games list about
11 KB; Ludo's modes about 21 KB and its stakes about 27 KB.

| Data | Load | Keep | Refetch |
|---|---|---|---|
| Games list | On app start (after login), `?is_active=true`. | In memory, and on disk to draw the home screen at once on the next start. | On app start, on resume after 10 minutes in the background, on pull to refresh, and after any `GAME_NOT_FOUND`. |
| A game's variants, modes, stakes | Together, when the player opens that game's home. Don't preload all 26 games (that is 78 calls). | In memory, per game. | When the game home is opened again more than 10 minutes later, after a socket `invalid_mode`, and on pull to refresh. |
| Power-ups, achievements | When their tab is opened. | In memory. | As above. |
| Config | When the game home opens, if the game's file uses any config key. | In memory with its `version`. | As modes. |

Never poll these routes (`00-conventions.md`, "Limits"). Each call counts against the
player's 100 requests a minute.

---

## Errors

The body and the general codes are in `00-conventions.md`. The catalogue routes return
these (all **real**, captured on 24 Nov 2026):

| Status | `error` | When | App |
|---|---|---|---|
| 401 | `UNAUTHORIZED` | No token, or an expired one. | The interceptor refreshes once (`01-auth.md`). |
| 400 | `BAD_REQUEST` | `{id}` is not a number (a game code was sent), or `is_active` is not `true`/`false`. | An app bug: look the id up by `code`. |
| 404 | `GAME_NOT_FOUND` | No game with that id, or the game is switched off (sub-routes). | Drop the game from the cache, go back, "This game isn't available right now." |
| 404 | `NOT_FOUND` | A path that doesn't exist (for example `/games/1/rooms`). | An app bug. |
| 429 | `RATE_LIMITED` | Too many requests. | Wait and retry once. |
| 500 / 503 | `INTERNAL_ERROR`, `DATABASE_ERROR`, `DATABASE_BUSY` | Server trouble. | "Something went wrong. Try again." Keep showing the cached catalogue if there is one. |

```json
// 401, no token
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}

// 400, GET /games/ludo
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: can not parse to a i64"}

// 400, GET /games?is_active=maybe
{"error": "BAD_REQUEST", "message": "bad request: Query deserialize error: provided string was not `true` or `false`"}

// 404, GET /games/999999 and every /games/999999/... route
{"error": "GAME_NOT_FOUND", "message": "game not found: 999999"}

// 404, GET /games/1/rooms
{"error": "NOT_FOUND", "message": "not found: no route for GET /api/v1/games/1/rooms"}
```

A switched-off game gives the same `404 GAME_NOT_FOUND` on its sub-routes (from code; no
game was switched off on the development server to capture it).

---

## Limits

| What | Limit |
|---|---|
| All routes here | The signed-in limit, about 100 requests a minute per player (`00-conventions.md`). |
| Polling | Never. Refetch only on the events in "Caching and refetching". |

---

## Open issues (the app must cope)

Found while writing this file; none is fixed yet.

1. **`GET /games` lists switched-off games by default.** Always send `?is_active=true`.
   `GET /games/{id}` also returns a switched-off game, while its sub-routes answer `404`.
2. **`icon_url` is not usable.** It is `null`, a site path (`/assets/games/snl/icon.svg`)
   that the gateway answers `404` for, or a bare file name (`powerups/shield.svg`). Ship
   icons in the app, keyed by `code`.
3. **No prize amount.** `base_payout_multiplier` doesn't match real payouts (Ludo `2.0`
   listed, 1.9x paid; 4-seat tiers also `2.0`). Don't show it as a prize.
4. **Level-gated stakes aren't marked.** `min_user_level` is not in the stakes reply, so a
   level-1 player sees tiers that need level 5 (4 rows today).
5. **Kill switches can't be read in advance.** A paused game looks normal in the catalogue;
   the app finds out only from the socket's `kill_switch_engaged` (or a tournament's `503`).
6. **No category, no launch state.** `category` is not sent, and nothing marks a game as
   "coming soon"; both are app-side tables for now.
7. **Variant names differ between the catalogue and the sockets** for some variants (the
   engine's rule set, `rules_config.engine_variant`). Match by `mode_code`.
8. **No default variant for some games** (Snake & Ladder has none with `is_default`).
   Preselect the first.
9. **Send-field names differ by game** for the stake (`bet_amount`, `buy_in`,
   `entry_fee`). The game files give each one.

---

## Done when

- [ ] The home screen shows every game from `GET /games?is_active=true`, in reply order,
      with app-bundled icons; games without a screen in this build show "Coming soon".
- [ ] Game ids are looked up by `code` each session; no numeric id is hard-coded.
- [ ] Opening a game loads its variants, modes and stakes (3 calls) and shows the mode
      picker grouped by variant, with the default variant (or the first) preselected.
- [ ] Each mode card shows seats, ranked, and its timer from `mode_config.timer` ("10 s
      turns", "3+2").
- [ ] The rules sheet lists only `rule_options` with `engine: "has"`.
- [ ] The stake picker shows the picked mode's tiers by currency in reply order, greys out
      stakes above the balance, offers a stepper for range rows, and always allows free play.
- [ ] Unknown stake shapes (blinds, points) are hidden, not shown wrongly.
- [ ] No prize figure is computed from `base_payout_multiplier`.
- [ ] A private-room mode shows the host's options from `host_can_choose`, with the turn
      times from `timer.allowed_turn_seconds`.
- [ ] Starting a game sends `mode_code`, `currency` and `bet_amount` (plus `game_code` on a
      shared socket), never a numeric id.
- [ ] A `GAME_NOT_FOUND` on a game's route removes the game and returns to the home screen.
- [ ] A socket `invalid_mode` refetches modes and stakes and returns to the mode picker.
- [ ] A socket `kill_switch_engaged` shows the operator's banner and disables play for the
      game.
- [ ] Modes with `min_tier` show a lock; modes with `subscription_gate` show the daily
      ranked allowance.
- [ ] The catalogue is cached as in "Caching and refetching"; no route is polled.

---

## Test accounts

Create your own player with Sign up or "Play as guest" on the development server
(`01-auth.md`), any `@example.com` email. Every route here works for any signed-in player.
Don't use other people's accounts.

The samples in this file were captured on 24 Nov 2026 with a new player made for this
purpose (username prefix `w04doc`).
