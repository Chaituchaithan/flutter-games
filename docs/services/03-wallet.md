# Flutter hand-off 3: wallet

The player's balance, their wallet history (the ledger), entry fees and payouts as the player
sees them, and sending money to another player.

This file is the contract between the Flutter app and the **api-gateway** wallet routes. It is
written so a Claude agent can implement it directly. Read `00-conventions.md` first: the error
body, list shapes, money parsing and times are defined there and not repeated here. Sessions
and the auth interceptor come from `01-auth.md`.

**Where the samples come from.** Every reply marked "real" was captured from the running
gateway and the Ludo socket on 24 Nov 2026, with two fresh test players who played one staked
Ludo game (10 gold each) and sent each other money. Replies marked "from the code" were not
captured; their shape is read from the gateway source.

---

## For the Claude agent: what to build

1. A `WalletApi` with three methods: `balance()`, `ledger({currency, per, after})` and
   `transfer({recipientId, amount, currency, idempotencyKey})`, on the shared `ApiClient`.
2. Models `WalletBalance`, `LedgerEntry`, `LedgerPage` and `TransferResult`. Every money field
   accepts **both** a number and a numeric string (`00-conventions.md`, "Money"); this module
   uses both (see "Strings and numbers").
3. A `WalletStore` (one per signed-in user) that holds the latest balance and lets any screen
   ask for a re-read. It re-reads on app start, on resume, after a game ends, after a transfer,
   and after any purchase, bonus or gift (other hand-off files). Never more than once every
   10 seconds unless one of those events happened.
4. Screens:
   - A **balance chip** (tokens and gold) in the app bar or lobby header.
   - A **Wallet / History** screen: the ledger, newest first, with a token/gold/all filter and
     "load more" at the end of the list.
   - A **Send** sheet (only if the product shows transfers; see section 4).
   - The **result screen** of a staked game shows the player's own payout from the game socket,
     then the new balance from the gateway (section 5).
5. Tests: model parsing for each real reply in this file (string and number money, `null`
   fields), the ledger "load more" loop until `next_cursor` is `null`, transfer error mapping,
   and that a retried transfer reuses its `Idempotency-Key`.

Never log wallet request or reply bodies, even in debug builds.

---

## Endpoints at a glance

All paths are under `http://<host>:1280/api/v1`. All need `Authorization: Bearer
<access_token>`.

| Step | Method and path | Device check | Success |
|---|---|---|---|
| Balance | `GET /wallet/balance` | no | `200` + balance |
| History | `GET /wallet/ledger` | no | `200` + item list (shape 3) |
| Send money to a player | `POST /wallet/transfer` | **yes** (like `/sensitive/` routes) | `200` + result |

There are no other player wallet routes. Admin wallet routes exist under `/admin/...` (console
only); the app never calls them.

Money moves on other routes too, each in its own file: gifts (`09-social.md`), shop and
purchases (`11-store.md`), daily bonus, quests and welcome bonus (`07-rewards.md`), tournament
entries (`06-tournaments.md`). Every one of them shows up in the ledger below.

---

## 1. Balance

`GET /wallet/balance`. No body, no query.

Real reply (a new player right after sign-up):

```json
{
  "user_id": "97d5bce4-0b63-4d30-8492-bbfba48cf83a",
  "balance_tokens": "100",
  "balance_gold": "500",
  "updated_at": "2026-11-24T09:18:24.050121Z"
}
```

| Field | Meaning |
|---|---|
| `user_id` | The signed-in player. |
| `balance_tokens` | Tokens, a whole number sent as a **string**. |
| `balance_gold` | Gold, a whole number sent as a **string**. |
| `updated_at` | When the wallet last changed (UTC). Not when it was read. |

- A new account starts with **100 tokens and 500 gold** on the development server (the
  `signup_grant` rows in the ledger). Don't hard-code it; read the balance.
- The gateway caches the balance for up to 60 seconds, but every money movement (games,
  transfers, purchases) is meant to clear it, so a re-read right after an event is up to date.
  Real: after the staked game below, the winner's balance read `"509"` 2 seconds after
  `game.wallet_update`.
- Show the balance with thousands separators. Never add or subtract on the device; show what
  the server sends.

**Errors**

| Status | `error` | When | What the app does |
|---|---|---|---|
| 401 | `UNAUTHORIZED` | No token or an expired one. | The interceptor refreshes (`01-auth.md`). |
| 404 | `NOT_FOUND` | The account has no wallet (should not happen; from the code). | Show "Wallet unavailable", offer Retry. |
| 503 | `DATABASE_BUSY` | Busy for a moment. | Retry once after a second. |

Real:

```json
// 401, no token
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}
```

---

## 2. History (ledger)

`GET /wallet/ledger?currency=&per=&page=&after=`

Every movement of the player's wallet, **newest first**: sign-up grant, entry fees, payouts,
refunds, transfers, gifts, purchases, bonuses, tournament entries and prizes.

| Query | Rule |
|---|---|
| `currency` | Optional: `token` or `gold`. Leave it out for both. Anything else is `400`. |
| `per` | Optional page size, 1 to 100, default **20**. |
| `after` | Optional: the `next_cursor` of the previous page. Use this to load more. |
| `page` | Optional, starts at 1. Only for jumping to a page; prefer `after`. |

The reply is list shape 3 from `00-conventions.md`: `{items, page, pages, total,
next_cursor}`.

Real reply (player B, `?per=2`, after the game and two transfers from player A):

```json
{
  "items": [
    {"entry_id": "ledger:42029", "created_at": "2026-11-24T09:19:48.358890Z", "currency": "token",
     "direction": "credit", "amount": 3, "kind": "transfer", "counterparty": "user",
     "counterparty_user_id": "97d5bce4-0b63-4d30-8492-bbfba48cf83a", "tournament_id": null,
     "match_id": null, "item_kind": null, "item_name": null, "game_code": null, "variant_code": null},
    {"entry_id": "ledger:42028", "created_at": "2026-11-24T09:19:46.053139Z", "currency": "gold",
     "direction": "credit", "amount": 5, "kind": "transfer", "counterparty": "user",
     "counterparty_user_id": "97d5bce4-0b63-4d30-8492-bbfba48cf83a", "tournament_id": null,
     "match_id": null, "item_kind": null, "item_name": null, "game_code": null, "variant_code": null}
  ],
  "page": 1,
  "pages": 3,
  "total": 5,
  "next_cursor": "7b226b223a5b22323032362d31312d32345430393a31393a34362e3035333133395a222c226c65646765723a3432303238225d2c2270223a327d"
}
```

Next page, real (`?per=2&after=<next_cursor>`):

```json
{
  "items": [
    {"entry_id": "ledger:42021", "created_at": "2026-11-24T09:19:01.062177Z", "currency": "gold",
     "direction": "debit", "amount": 10, "kind": "entry_fee", "counterparty": "house_revenue",
     "counterparty_user_id": null, "tournament_id": null,
     "match_id": "4452d182-de43-4d79-9905-31a0be00c564", "item_kind": null, "item_name": null,
     "game_code": "ludo", "variant_code": "classic"},
    {"entry_id": "ledger:42020", "created_at": "2026-11-24T09:18:25.007053Z", "currency": "gold",
     "direction": "credit", "amount": 500, "kind": "signup_grant", "counterparty": "store_mint",
     "counterparty_user_id": null, "tournament_id": null, "match_id": null, "item_kind": null,
     "item_name": null, "game_code": null, "variant_code": null}
  ],
  "page": 2,
  "pages": 3,
  "total": 5,
  "next_cursor": "7b226b223a5b22323032362d31312d32345430393a31383a32352e3030373035335a222c226c65646765723a3432303230225d2c2270223a337d"
}
```

An empty or past-the-end page, real (`?page=99`):

```json
{"items": [], "page": 99, "pages": 1, "total": 5, "next_cursor": null}
```

### Entry fields

| Field | Type | Meaning |
|---|---|---|
| `entry_id` | string | Unique and stable. Use it as the list key. `ledger:<n>` or `match:<n>:<kind>`; don't parse it. |
| `created_at` | ISO 8601 UTC | When the money moved. |
| `currency` | string | `token` or `gold`. |
| `direction` | string | `credit` (into the wallet, show `+`) or `debit` (out of it, show `-`). |
| `amount` | **number** | Always positive. The sign comes from `direction`. |
| `kind` | string | Why the money moved (table below). |
| `counterparty` | string | The other side: `user` (another player), `house_revenue`, `house_float`, `promo_budget`, `tournament_escrow`, `store_mint` or `sink`. For display hints only. |
| `counterparty_user_id` | UUID or `null` | The other player, for a transfer or gift. Look up the name with the profile routes (`02-profile-and-sessions.md`), or show "a player". |
| `tournament_id` | UUID or `null` | The tournament, for a tournament entry, prize or refund. |
| `match_id` | UUID or `null` | The match, for an entry fee, payout or refund. The same id as the game socket's `room_id` and `game.wallet_update.match_id`. |
| `item_kind`, `item_name` | string or `null` | For a `purchase`: what was bought (`avatar`, `power_up`, `token_pack`, `gold_pack`, ...) and its name. |
| `game_code`, `variant_code` | string or `null` | For a match row: the game (`ludo`) and variant (`classic`). Name them from the catalogue (`04-game-catalogue.md`). |

### Kinds

Show a label and an icon per `kind`. **Unknown kinds will appear**: show them with a generic
"Wallet update" label and the amount, never hide or fail on them.

| `kind` | Label | Seen | Notes |
|---|---|---|---|
| `signup_grant` | Welcome credit | real | The starting balance of a new account. |
| `opening_balance` | Opening balance | code | Older accounts' first row. |
| `entry_fee` | Entry fee | real (Ludo) | A match stake, taken when the game starts. Has `match_id`, `game_code`. |
| `payout` | Winnings | real (Ludo) | A match payout, after the game ends. Has `match_id`, `game_code`. |
| `refund` | Refund | code | A stake given back (a drawn Ludo game, a cancelled or abandoned match, a withdrawn tournament entry, a refunded purchase). |
| `match_stake` | Entry fee | code | **Same meaning as `entry_fee`**, written by other games (Carrom, Snooker, Crash, Roulette, Bingo and others). See "Open issues". |
| `match_payout` | Winnings | code | **Same meaning as `payout`**, other games. |
| `match_refund` | Refund | code | **Same meaning as `refund`**, other games. |
| `buyin` | Tournament buy-in | code | Has `tournament_id`. |
| `fee` | Tournament fee | code | Has `tournament_id`. |
| `prize` | Tournament prize | code | Has `tournament_id`. |
| `transfer` | Sent / Received | real | `direction` says which; `counterparty_user_id` is the other player. |
| `gift` | Gift sent / received | code | A gift (`09-social.md` or in a game room). |
| `purchase` | Purchase | code | `item_kind`, `item_name` say what. |
| `iap_token_pack`, `iap_gold_pack` | Bought tokens / gold | code | Real-money packs (`11-store.md`). |
| `daily_bonus`, `welcome_bonus`, `quest_reward`, `achievement_reward`, `inbox_reward`, `referral_reward` | Bonus | code | Rewards (`07-rewards.md`). |
| `minigame_stake`, `minigame_prize` | Bonus game | code | Bonus games (`07-rewards.md`). |
| `adjustment` | Adjustment | code | A support correction. |

### What the app does with it

- Group rows by day (local time zone). Each row: icon by `kind`, label, game name for match
  rows, `+19` / `-10` with the currency icon, and the time.
- Tapping a match row may open that match (`08-progress-and-history.md`) by `match_id`.
- **Load more:** call again with `after=<next_cursor>` (same `currency` and `per`) until
  `next_cursor` is `null`. Don't use `page` for scrolling: new rows arriving at the top shift
  pages, `after` does not.
- The query name is **`after`**. A `cursor=` parameter is silently ignored and returns page 1
  again (real; see "Open issues").
- Pull to refresh reloads from the top without `after`.
- `total` and `pages` count every row for the filter. Use `total` for "No history yet" when it
  is 0.
- One movement never appears twice. A losing player has no payout row (a zero payout is left
  out); real: player B's history above has the entry fee and no payout.

**Errors** (all real)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` | `currency` not `token`/`gold`; `per` outside 1-100 (`field: "per"`); `page=0`; a cursor that is not one of this list's. | App bug. Reload from the top without `after`. |
| 401 | `UNAUTHORIZED` | As everywhere. | Interceptor. |

```json
{"error": "BAD_REQUEST", "message": "bad request: Query deserialize error: unknown variant, expected `token` or `gold`"}
{"error": "BAD_REQUEST", "field": "per", "message": "bad request: per must be between 1 and 100"}
{"error": "BAD_REQUEST", "message": "bad request: invalid cursor"}
{"error": "BAD_REQUEST", "message": "bad request: page starts at 1"}
```

---

## 3. Strings and numbers

The wallet routes are not consistent, so parse every money field leniently:

| Where | Money is sent as |
|---|---|
| `GET /wallet/balance` | strings: `"balance_tokens": "100"` |
| `POST /wallet/transfer` reply | strings: `"sender_balance": "504"`, `"transferred": "5"` |
| `GET /wallet/ledger` | numbers: `"amount": 10` |
| Game sockets (`room.created` players, `game.wallet_update`) | numbers |

Suggested Dart helper (store money as `int`; amounts are always whole):

```dart
int parseMoney(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => num.parse(s).toInt(),
      _ => 0,
    };
```

---

## 4. Send money to a player (transfer)

`POST /wallet/transfer`

Moves tokens or gold from the signed-in player to another player at once. It can't be undone:
always ask to confirm ("Send 5 gold to <name>?").

This route has the **device check** (`00-conventions.md`, "HTTP requests"): a changed
`User-Agent` or network since login answers `401 FINGERPRINT_MISMATCH`; log in again.
Development servers skip the check.

| Header | |
|---|---|
| `Idempotency-Key` | Optional but **send it**: a new UUID per send attempt, reused on a retry of the same attempt. 1 to 100 printable ASCII characters. |

```json
{
  "recipient_id": "9722e763-2178-46f3-a02e-f380400d3ff3",
  "amount": 5,
  "currency": "gold"
}
```

| Field | Rule |
|---|---|
| `recipient_id` | Required. Another player's user id (from a friend list, profile or game room). Not yourself. |
| `amount` | Required. A whole number above 0. A number or a numeric string both work (real: `"3"` was accepted). |
| `currency` | Required. `token` or `gold`. |

**Success:** `200`. Real:

```json
{"sender_balance": "504", "transferred": "5", "currency": "gold"}
```

| Field | Meaning |
|---|---|
| `sender_balance` | The sender's new balance in that currency (string). Update the balance chip from it. |
| `transferred` | The amount moved (string). |
| `currency` | `token` or `gold`. |

**Retry with the same key:** `200`, the first reply again, and header
`Idempotent-Replayed: true`. Nothing moves twice. Real:

```json
{"currency": "gold", "sender_balance": "504", "transferred": "5"}
```

(The field order can differ in a replay; parse by name.)

Both players see a `transfer` row in their ledger: the sender as `debit`, the receiver as
`credit`, each with the other's `counterparty_user_id`.

**Quota.** Transfers share the gift send quota: **10 a day and 50 a week** per sender on the
development defaults (an operator can change them). Over it: `429 GIFT_QUOTA_EXCEEDED`. A
failed transfer does not use up the quota.

**Errors**

| Status | `error` | When | Show | Seen |
|---|---|---|---|---|
| 400 | `VALIDATION_ERROR` (`field: "amount"`) | `amount` is 0, negative or has a fraction. | "Enter a whole amount above 0." | real |
| 400 | `BAD_REQUEST` | Sending to yourself; a missing field; `currency` not `token`/`gold`; a bad `Idempotency-Key`. | App bug (the app should prevent these). | real |
| 401 | `FINGERPRINT_MISMATCH` | Network or app identity changed since login (production). | Log in again. | code |
| 404 | `NOT_FOUND` | No such player (message `wallet not found`). | "That player can't receive money." | real |
| 409 | `INSUFFICIENT_FUNDS` | Not enough of that currency. | "Not enough gold." Offer the shop. | real |
| 409 | `CONFLICT` | The same `Idempotency-Key` was used for a different transfer. | App bug: make a new key per attempt. | real |
| 429 | `GIFT_QUOTA_EXCEEDED` | Daily or weekly send quota used up. | "You've reached today's sending limit." | code |
| 429 | `RATE_LIMITED` | The general limit. | Wait and retry once. | code |
| 503 | `KILL_SWITCH_ENGAGED` | An operator paused transfers. | Show the `message`; disable Send. | code |

Real error bodies:

```json
{"error": "VALIDATION_ERROR", "field": "amount", "message": "validation error: amount must be a whole number greater than zero"}
{"error": "BAD_REQUEST", "message": "bad request: cannot transfer to yourself"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected `token` or `gold` at line 1 column 85"}
{"error": "NOT_FOUND", "message": "not found: wallet not found"}
{"error": "INSUFFICIENT_FUNDS", "message": "insufficient funds"}
{"error": "CONFLICT", "message": "conflict: idempotency key was already used for another purchase"}
{"error": "BAD_REQUEST", "message": "bad request: idempotency key must be 1 to 100 printable ASCII characters"}
```

No network or a timeout on a transfer: don't assume it failed. Retry **once with the same
`Idempotency-Key`**; the reply tells you whether it went through.

---

## 5. Entry fees and payouts (staked games)

A staked game moves money in three places. The app shows each at the right moment.

| When | Where it comes from | What the app shows |
|---|---|---|
| Choosing a table | `GET /games/{id}/stakes` (`04-game-catalogue.md`) and `GET /wallet/balance` | Grey out stakes above the balance. |
| Creating or joining | The game socket checks the wallet; it may refuse with `insufficient_funds`. | "Not enough gold for this table." Offer a lower stake or the shop. |
| The game starts | The stake is taken: an `entry_fee` **debit** row appears in the ledger. | Re-read the balance (optional). |
| The game ends | The socket sends `game.wallet_update`; a `payout` **credit** row appears for each paid player. | The player's own payout, then the re-read balance. |
| A draw or a cancelled game | `refund` credit rows instead of a payout. | "Stake returned." |

### Real example: one Ludo game at 10 gold

Two new players (500 gold each) played `friends_room` with `currency: "gold"`,
`bet_amount: 10`. Player B forfeited.

Stake checks on `room.create` (game socket, real):

```json
{"id": "A-2", "event": "room.create_error", "error": {"code": "insufficient_funds", "message": "insufficient balance for a stake of 100000 gold"}}
{"id": "A-3", "event": "room.create_error", "error": {"code": "invalid_request", "message": "invalid bet_amount: 10.5 is not an integer"}}
```

After `player.ready` from both, the game started. Player A's balance and history mid-game
(real):

```json
{"user_id": "97d5bce4-0b63-4d30-8492-bbfba48cf83a", "balance_tokens": "100", "balance_gold": "490", "updated_at": "2026-11-24T09:19:01.062177Z"}

{"entry_id": "ledger:42022", "created_at": "2026-11-24T09:19:01.062177Z", "currency": "gold",
 "direction": "debit", "amount": 10, "kind": "entry_fee", "counterparty": "house_revenue",
 "counterparty_user_id": null, "tournament_id": null,
 "match_id": "4452d182-de43-4d79-9905-31a0be00c564", "item_kind": null, "item_name": null,
 "game_code": "ludo", "variant_code": "classic"}
```

The end, on both sockets (real):

```json
{"event": "game.wallet_update", "data": {"match_id": "4452d182-de43-4d79-9905-31a0be00c564",
  "payouts": [{"amount": 19, "result": "win", "user_id": "97d5bce4-0b63-4d30-8492-bbfba48cf83a"},
              {"amount": 0, "result": "forfeit", "user_id": "9722e763-2178-46f3-a02e-f380400d3ff3"}],
  "pot_amount": 20, "rake_amount": 1}}
```

Player A two seconds later (real):

```json
{"user_id": "97d5bce4-0b63-4d30-8492-bbfba48cf83a", "balance_tokens": "100", "balance_gold": "509", "updated_at": "2026-11-24T09:19:04.034949Z"}

{"entry_id": "ledger:42023", "created_at": "2026-11-24T09:19:04.034949Z", "currency": "gold",
 "direction": "credit", "amount": 19, "kind": "payout", "counterparty": "house_revenue",
 "counterparty_user_id": null, "tournament_id": null,
 "match_id": "4452d182-de43-4d79-9905-31a0be00c564", "item_kind": null, "item_name": null,
 "game_code": "ludo", "variant_code": "classic"}
```

Player B ended at 490 gold with only the `entry_fee` row for that match.

### How the socket event maps to the ledger

| `game.wallet_update` | Ledger |
|---|---|
| `match_id` | The same `match_id` on the `entry_fee` and `payout` rows. |
| `payouts[].amount` for the player, above 0 | One `payout` credit row of that amount (a `refund` row on a draw). |
| `payouts[].amount` = 0 | No row. |
| `pot_amount` | The sum of every player's `entry_fee` (20 = 2 x 10). Not in the player's ledger. |
| `rake_amount` | The house's cut (5% here: 20 - 19 = 1). Not in the player's ledger. |
| `payouts[].result` | `win`, `loss`, `forfeit` or `draw` (Ludo). For the result screen only. |

What the app does:

- On `game.wallet_update`, show the player's own `amount` ("You won 19 gold"), then call
  `GET /wallet/balance` and update the chip. The socket event comes first; the ledger rows and
  the new balance were already written when it arrived (real, Ludo).
- If the socket dropped before `game.wallet_update`, the balance and the ledger are the truth:
  re-read them when the app comes back.
- Net result for a match = the sum of its rows by `match_id` (`+19 - 10 = +9` for player A).
  Show it on the match row in history if you like; never use it to change the balance.
- Free games (`bet_amount` 0) write no rows and send no `game.wallet_update`.

---

## Errors

The error body and the shared codes are in `00-conventions.md`, "Errors". Each section above
lists what its route returns. The interceptor handles only `401 UNAUTHORIZED` and
`401 TOKEN_BLACKLISTED`; everything else is handled per call.

---

## Limits

| What | Limit |
|---|---|
| All wallet routes | The general limit, about 100 requests a minute per player (`429 RATE_LIMITED`). |
| Balance polling | Don't poll. Re-read on the events in "what to build", at most once every 10 seconds otherwise. |
| Ledger page size | `per` 1 to 100, default 20. |
| Transfers | 10 a day and 50 a week per sender, shared with gifts (development defaults). |
| `Idempotency-Key` | 1 to 100 printable ASCII characters. |

---

## Open issues (the app must cope)

1. **Money as strings and numbers.** Balance and transfer replies send strings; the ledger and
   game sockets send numbers. Parse both (section 3).
2. **Two kind names for the same thing.** Ludo's match rows read `entry_fee` / `payout` /
   `refund`; other games' rows (Carrom, Snooker, Crash, Roulette, Bingo, Arena Shooter, Battle
   Royale, Tombola, Word Rush, Spelling Bee, Hill Climb and others, from the database on
   24 Nov 2026) read `match_stake` / `match_payout` / `match_refund`. Map both pairs to the
   same labels. Reported to the lead (24 Nov 2026).
3. **`cursor=` is ignored.** The handler's own comment names the query `cursor`, but the
   parameter that works is `after`. `cursor=...` silently returns page 1. Always use `after`.
4. **The transfer conflict message says "purchase"** (`idempotency key was already used for
   another purchase`). Harmless; decide on `error`, never on `message`.
5. **Payout rows name `house_revenue` as the counterparty**, though the money comes from the
   pot. Don't show the counterparty for match rows.

---

## Done when

- [ ] The balance chip shows tokens and gold from `GET /wallet/balance`, parsed from strings.
- [ ] A new account shows 100 tokens and 500 gold and two `signup_grant` rows in history.
- [ ] History lists rows newest first, filters by token/gold/all, and "load more" uses
      `after=<next_cursor>` until it is `null`; pull to refresh starts again from the top.
- [ ] Every `kind` in the table has a label; an unknown `kind` shows as "Wallet update".
- [ ] `match_stake` / `match_payout` / `match_refund` show the same labels as `entry_fee` /
      `payout` / `refund`.
- [ ] A staked game: the `entry_fee` row appears when it starts; at the end the result screen
      shows the player's own payout from `game.wallet_update`, the balance updates, and the
      winner has a `payout` row with the same `match_id`. The loser has no payout row.
- [ ] A stake above the balance shows "Not enough gold for this table" from the socket's
      `insufficient_funds`.
- [ ] Send: a confirm step, a new `Idempotency-Key` per attempt, the same key on a retry, and
      the sender's balance updated from `sender_balance`. Both players see a `transfer` row.
- [ ] Send errors map as in section 4 (`VALIDATION_ERROR`, `INSUFFICIENT_FUNDS`, `NOT_FOUND`,
      `GIFT_QUOTA_EXCEEDED`, `KILL_SWITCH_ENGAGED`, `FINGERPRINT_MISMATCH`).
- [ ] No wallet body appears in any log.

---

## Test accounts

Create your own accounts with Sign up on the development server (any `@example.com` email);
each starts with 100 tokens and 500 gold, enough for the cheapest stakes (10 gold for Ludo).
For a staked game you need two accounts on two devices (or the Ludo debug page as the second
player, see `games/ludo.md`). Don't use other people's accounts.

The samples in this file came from two accounts made for it on 24 Nov 2026:
`w03doca1795511903` (`97d5bce4-0b63-4d30-8492-bbfba48cf83a`) and `w03docb1795511903`
(`9722e763-2178-46f3-a02e-f380400d3ff3`).
