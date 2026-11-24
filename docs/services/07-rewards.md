# Flutter hand-off 7: rewards

Welcome bonus, daily bonus, quests, achievements and bonus games (wheels, scratch cards,
chests, pick-a-card).

This file is the contract between the Flutter app and the **api-gateway** for rewards. It is
written so a Claude agent can implement it directly. Read `00-conventions.md` first (errors,
lists, money, times, the `/sensitive/` device check) and `01-auth.md` (sign-up fields that
feed the welcome bonus). This file links to them instead of repeating them.

**Where the samples come from.** Replies marked **(live)** were captured from the running
gateway on 24 Nov 2026 with fresh test players, tokens blanked. Replies marked **(from code)**
are built from the Rust structs, for states a new player can't reach in one day (a spin day,
an achievement tier). Long arrays are trimmed to one or two items; each trim is noted.

---

## For the Claude agent: what to build

1. A `RewardsApi` client with one method per route below, on the shared `ApiClient` from
   `00-conventions.md`. Every method returns a typed result or the shared `ApiError`.
2. Models that parse money both as numbers and as numeric strings (see "Money" in
   `00-conventions.md`). In this file, quest and daily bonus amounts are **strings**
   (`"50"`), achievement and bonus game amounts are **numbers** (`50`).
3. Screens:
   - **Welcome bonus** sheet, shown once after sign-up or guest create, with a Claim button
     and the free Welcome-wheel spin.
   - **Daily bonus** calendar: the reward days, today's card, the streak and a countdown to
     the next claim.
   - **Quests** tab: daily, weekly and onboarding lists, each quest with a progress bar and a
     Claim button.
   - **Achievements** tab: badges, tiers (bronze, silver, gold, royal) and Claim buttons.
   - **Bonus game** screens: a wheel, a scratch card, a chest and a pick-a-card, all driven by
     the same play route; the server picks the prize, the app only animates it.
4. A `RewardsBadge` state (a red dot on the Rewards tab) that is on when anything can be
   claimed (see "Red dot rules").
5. After every claim or play, update the wallet balance shown in the header (see "How a
   reward reaches the wallet").
6. Tests: unit tests for each model's parser (with the samples here), the red dot rules, the
   "merge quests with progress" logic, and each error case's mapping to a message.

---

## Endpoints at a glance

All routes need `Authorization: Bearer <access_token>`. Paths are under
`http://<host>:1280/api/v1`.

| What | Method and path | Device check | Success |
|---|---|---|---|
| My welcome bonus | `GET /welcome-bonus/me` | no | `200` |
| Claim the welcome bonus | `POST /welcome-bonus/claim` | **yes** | `200` |
| Daily bonus status | `GET /sensitive/daily-bonus/status` | **yes** | `200` |
| Claim the daily bonus | `POST /sensitive/daily-bonus/claim` | **yes** | `200` |
| Active quests | `GET /sensitive/quests/active` | **yes** | `200` |
| My quest progress | `GET /sensitive/quests/my-progress` | **yes** | `200` |
| Claim a quest | `POST /sensitive/quests/{quest_id}/claim` | **yes** | `200` |
| All achievements | `GET /achievements[?game_id=<id>]` | no | `200` |
| My achievements | `GET /achievements/my` | no | `200` |
| Claim an achievement | `POST /achievements/{id}/claim[?tier=<tier>]` | no | `200` |
| Bonus games I can see | `GET /bonus-games[?trigger=<trigger>]` | no | `200` |
| One bonus game | `GET /bonus-games/{id or code}` | no | `200` |
| Play a bonus game | `POST /bonus-games/{id or code}/play` | **yes** | `201` |
| My bonus game plays | `GET /bonus-games/plays/me[?per=&after=]` | no | `200` |

"Device check" means the `/sensitive/` check from `00-conventions.md`: a changed
`User-Agent` or network answers `401 FINGERPRINT_MISMATCH`; sign the player in again. The
welcome claim and the bonus game play have the same check although their paths have no
`/sensitive/`. Development servers skip the check.

Path ids are numbers (`/sensitive/quests/1/claim`, `/achievements/15/claim`); a word there is
a `400 BAD_REQUEST` ("can not parse to a i64"). Only bonus games also accept their `code`
(`/bonus-games/welcome_wheel`).

---

## How a reward reaches the wallet

Every claim or play that pays tokens or gold writes rows to the player's wallet ledger in the
same database transaction, so the money is there when the reply arrives. The ledger route
(`GET /wallet/ledger`, described in `03-wallet.md`) then shows one row per currency:

| Reward | Ledger `kind` | `direction` | `counterparty` |
|---|---|---|---|
| Welcome bonus claim | `welcome_bonus` | `credit` | `promo_budget` |
| Daily bonus claim | `daily_bonus` | `credit` | `promo_budget` |
| Quest claim | `quest_reward` | `credit` | `promo_budget` |
| Achievement claim (tokens or gold) | `achievement_reward` | `credit` | `promo_budget` |
| Bonus game prize | `minigame_prize` | `credit` | `promo_budget` |
| Bonus game cost (paid plays) | `minigame_stake` | `debit` | `house_revenue` |
| Sign-up gift (not a reward route; on every full sign-up) | `signup_grant` | `credit` | `store_mint` |

Real ledger rows after a welcome claim, a free spin, a paid scratch card and a quest claim
**(live)** (trimmed to the reward rows):

```json
{"items": [
  {"entry_id": "ledger:42043", "created_at": "2026-11-24T09:22:43.105645Z", "currency": "token", "direction": "credit", "amount": 50, "kind": "quest_reward", "counterparty": "promo_budget", "counterparty_user_id": null, "tournament_id": null, "match_id": null, "item_kind": null, "item_name": null, "game_code": null, "variant_code": null},
  {"entry_id": "ledger:42036", "created_at": "2026-11-24T09:21:12.229614Z", "currency": "token", "direction": "credit", "amount": 400, "kind": "minigame_prize", "counterparty": "promo_budget", "...": "..."},
  {"entry_id": "ledger:42035", "created_at": "2026-11-24T09:21:12.229614Z", "currency": "token", "direction": "debit", "amount": 200, "kind": "minigame_stake", "counterparty": "house_revenue", "...": "..."},
  {"entry_id": "ledger:42033", "created_at": "2026-11-24T09:21:03.851021Z", "currency": "token", "direction": "credit", "amount": 500, "kind": "welcome_bonus", "counterparty": "promo_budget", "...": "..."}
], "page": 1, "pages": 2, "total": 7, "next_cursor": "<opaque>"}
```

- Rewards with **no money** write no ledger row: power-ups (they go to the player's power-up
  stock), avatars and titles (achievement tiers), rubies (shown only; no ruby balance exists
  yet) and the `mult` prize (a multiplier stored for the next daily bonus).
- The welcome claim and the bonus game play return the new `balances` (numbers) in their
  reply: show them at once. Quest, achievement and daily bonus claims don't: re-read
  `GET /wallet/balance` after them.
- `game_code` is `null` on reward rows, also on a welcome bonus that came from a game.

---

## Red dot rules

Show a red dot on the Rewards tab (and on the matching sub-tab) when any of these is true:

| Section | Claimable when |
|---|---|
| Welcome bonus | `claimable_now.tokens + claimable_now.gold + claimable_now.power_up_qty > 0`, or `free_spin.available` is `true`. |
| Daily bonus | `can_claim` is `true`. |
| Quests | Any row of `my-progress` has `status` `"completed"`. |
| Achievements | A flat badge with `completed: true` and `claimed_at: null`, or a tiered badge whose `tier_reached` is at or above a tier that is not in `claimed_tiers`. |
| Bonus games | Only for games the player is entitled to (see 5d); the list alone doesn't tell. |

**When to refetch.** Nothing is pushed: no socket event or notification announces a completed
quest or an unlocked badge. Refetch:

- on app start and when the app returns to the foreground;
- when the Rewards tab opens;
- after every game ends (a game's `game.state_update` with `game_over: true`, or the game's
  own end event): wait about 2 seconds for the game server to settle the match, then read
  `my-progress` and `/achievements/my`;
- after every claim or play (the reply changes the section's state);
- when a countdown (`next_claim_available_at`, `cooldown_until`, `next_due_at`) reaches zero.

Never poll faster than once every 10 seconds (`00-conventions.md`, "Limits").

---

## 1. Welcome bonus

A new account gets one welcome grant at sign-up (or guest create). Its size depends on what
the app sent at sign-up (`entry_game`, `entry_source`, `device_id`; see `01-auth.md`), the
player's plan and whether the account is a guest. The player must **claim** it, within 72
hours on today's settings.

### 1a. My welcome bonus

`GET /welcome-bonus/me`

Real reply, a new full account that came in through Ludo **(live)**:

```json
{
  "grant": {
    "id": 634,
    "status": "pending",
    "blocked_reason": null,
    "entry_game": "ludo",
    "source": "direct",
    "tier_at_signup": "free",
    "was_guest": false,
    "source_multiplier": "1.00",
    "tier_multiplier": "1.00",
    "tokens_total": 500,
    "gold_total": 0,
    "power_up_id": null,
    "power_up_qty": 0,
    "delivery": "once",
    "expires_at": "2026-11-27T09:21:02.321238Z",
    "claimed_at": null,
    "completed_at": null,
    "created_at": "2026-11-24T09:21:02.294869Z"
  },
  "installments": [
    {"id": 633, "seq": 1, "due_at": "2026-11-24T09:21:02.321238Z", "tokens": 500, "gold": 0, "power_up_qty": 0, "credited_at": null, "token_ledger_id": null, "gold_ledger_id": null}
  ],
  "claimable_now": {"tokens": 500, "gold": 0, "power_up_qty": 0},
  "gold_held_for_kyc": 0,
  "next_due_at": null,
  "waiting_for_first_match": false,
  "free_spin": {
    "bonus_game_id": 1,
    "code": "welcome_wheel",
    "play_id": null,
    "available": true,
    "block_reason": null,
    "trigger": "welcome_bonus",
    "trigger_ref": "634"
  }
}
```

| Field | Meaning |
|---|---|
| `grant.status` | `pending` (not claimed), `partial` (claimed, more installments to come), `completed` (all paid), `expired` (not claimed before `expires_at`), `blocked` (refused; see `blocked_reason`). |
| `grant.blocked_reason` | `device_dupe` (this device already had a welcome bonus), `guest_policy` (guests get none), `disabled` (switched off). |
| `grant.source` | `direct`, `deeplink`, `store`, `invite` or `ad`, from sign-up. An `invite` sign-up got `source_multiplier` `"1.50"` (750 tokens instead of 500) in the capture. |
| `grant.tier_multiplier` | The plan's multiplier; a guest's half is folded in here (`"0.50"`). Multipliers are decimal strings. |
| `grant.delivery` | `once` (all now), `split_3d` or `split_7d` (installments on later days), `after_first_match` (paid after the first finished match). Today's setting is `once`. |
| `grant.expires_at` | Claim before this time. Show a countdown on the sheet while `status` is `pending`. |
| `installments[]` | The payment plan. `due_at` is `null` for an after-first-match installment; `credited_at` is set once paid. |
| `claimable_now` | What a claim would pay now. |
| `gold_held_for_kyc` | Gold that waits for an identity check. Always `0` today (no check exists). |
| `next_due_at` | When the next installment falls due, if one is scheduled. Show "Next part in <countdown>". |
| `waiting_for_first_match` | An installment waits for the player's first finished match. Show "Play a match to unlock the rest". |
| `free_spin` | The free Welcome-wheel spin, or `null` if the grant has none. `available` says whether it can be played now; otherwise `block_reason` says why: `used`, `grant_blocked`, `grant_expired`, or a bonus game block code (see 5). `trigger` and `trigger_ref` are exactly what to send to the play route. |

A blocked grant, from a second account signed up with the same `device_id` **(live)**:

```json
{"grant": {"id": 636, "status": "blocked", "blocked_reason": "device_dupe", "entry_game": null, "source": "direct", "tier_at_signup": "free", "was_guest": false, "source_multiplier": "1.00", "tier_multiplier": "1.00", "tokens_total": 500, "gold_total": 0, "...": "..."}, "installments": [], "claimable_now": {"tokens": 0, "gold": 0, "power_up_qty": 0}, "gold_held_for_kyc": 0, "next_due_at": null, "waiting_for_first_match": false, "free_spin": {"bonus_game_id": 1, "code": "welcome_wheel", "play_id": null, "available": false, "block_reason": "grant_blocked", "trigger": "welcome_bonus", "trigger_ref": "636"}}
```

A guest's grant is half (`was_guest: true`, `tier_multiplier: "0.50"`, `tokens_total: 250`)
**(live)**.

**Errors:**

| Status | `error` | When | What the app does |
|---|---|---|---|
| 404 | `NOT_FOUND` | The account has no grant (accounts made before the feature). | Never show the welcome sheet. |

**What the app does with it:**

- After sign-up or guest create, call it. If `status` is `pending` or `partial` and
  something is claimable, or `free_spin.available`, show the welcome sheet.
- `blocked` or `expired`: don't show the sheet. For `device_dupe`, if the player opens it
  from elsewhere, say "This device already received a welcome bonus."
- `completed` and the spin `used`: hide the welcome entry for good.

### 1b. Claim the welcome bonus

`POST /welcome-bonus/claim`, no body. Device check applies.

Real reply **(live)**:

```json
{
  "grant_id": 634,
  "status": "completed",
  "credited": {"tokens": 500, "gold": 0, "power_up_qty": 0},
  "power_up_id": null,
  "gold_held_for_kyc": 0,
  "next_due_at": null,
  "waiting_for_first_match": false,
  "balances": {"tokens": 600, "gold": 500}
}
```

- `credited` is what this claim paid. Animate it into the wallet and set the header balance
  from `balances` (numbers).
- The first claim always succeeds for a live grant, even if nothing is due yet (it starts a
  split plan). Later claims pay every installment that is due.
- `power_up_id` names the power-up the `credited.power_up_qty` went to.
- After the claim, if `free_spin.available` was `true`, go straight to the Welcome wheel
  (see 5c).

**Errors** (each `409` message starts with a stable code; match on the start of `message`
only for these, and keep a generic fallback):

| Status | `error` | `message` starts with | When | Show the user |
|---|---|---|---|---|
| 409 | `CONFLICT` | `conflict: completed` | Everything is already paid (the second claim). | Close the sheet; refetch `me`. |
| 409 | `CONFLICT` | `conflict: nothing_due` | Claimed before, the next installment isn't due yet. | "The next part unlocks in <next_due_at countdown>." |
| 409 | `CONFLICT` | `conflict: expired` | Not claimed in time. | "This welcome bonus has expired." |
| 409 | `CONFLICT` | `conflict: blocked: device_dupe` | This device already had a welcome bonus (found now or at sign-up). | "This device already received a welcome bonus." |
| 409 | `CONFLICT` | `conflict: blocked: guest_policy` / `blocked: disabled` | Not eligible. | "The welcome bonus isn't available for this account." |
| 409 | `CONFLICT` | `conflict: device_required` | The account was made without a `device_id` and no device is registered. | Register the device (`POST /devices/register`), then claim again automatically, once. |
| 404 | `NOT_FOUND` | | No grant. | Hide the welcome entry. |
| 401 | `FINGERPRINT_MISMATCH` | | Device check. | Sign in again. |
| 503 | `KILL_SWITCH_ENGAGED` | | An operator paused the platform. | Show the operator's `message`. |

```json
// 409, second claim (live)
{"error": "CONFLICT", "message": "conflict: completed: the welcome bonus is fully paid"}

// 409, sign-up without device_id, no device registered (live)
{"error": "CONFLICT", "message": "conflict: device_required: register this device (POST /api/v1/devices/register) first"}

// 409, second account on the same device (live)
{"error": "CONFLICT", "message": "conflict: blocked: device_dupe"}
```

To avoid `device_required`, always send `device_id` at sign-up (`01-auth.md`). The fallback,
`POST /devices/register` **(live)**:

```json
// request
{"device_id": "<the install's device id>", "device_name": "Pixel 8", "platform": "android"}
// 201 reply
{"id": 1, "user_id": "3e627624-8325-40ef-af8b-6b2428ffb131", "device_id": "w07-dev-1795512120-b", "device_name": "Pixel 8", "platform": "android", "push_token": null, "last_active_at": "2026-11-24T09:22:02.607026Z", "created_at": "2026-11-24T09:22:02.607026Z"}
```

`platform` is `ios`, `android` or `web`. Use the same `device_id` as at sign-up.

---

## 2. Daily bonus

One claim a day. Each claim moves the streak one day forward and pays that day's reward. The
cycle has 30 days today and starts again after the last one.

### 2a. Status

`GET /sensitive/daily-bonus/status`. Device check applies.

Real reply for a player who never claimed **(live)** (`rewards` trimmed to 3 of 30 days):

```json
{
  "current_streak": 0,
  "can_claim": true,
  "next_reward": {"day_number": 1, "reward_tokens": "0", "reward_gold": "100", "power_up_id": null, "power_up_quantity": 0, "ruby_amount": 0, "next_bonus_multiplier": null, "bonus_game_id": null, "label": null, "is_milestone": false, "is_enabled": true},
  "last_claimed_at": null,
  "next_claim_available_at": null,
  "total_claims": 0,
  "rewards": [
    {"day_number": 1, "reward_tokens": "0", "reward_gold": "100", "power_up_id": null, "power_up_quantity": 0, "ruby_amount": 0, "next_bonus_multiplier": null, "bonus_game_id": null, "label": null, "is_milestone": false, "is_enabled": true},
    {"day_number": 3, "reward_tokens": "0", "reward_gold": "200", "power_up_id": 1, "power_up_quantity": 1, "ruby_amount": 0, "next_bonus_multiplier": null, "bonus_game_id": null, "label": null, "is_milestone": false, "is_enabled": true},
    {"day_number": 15, "reward_tokens": "0", "reward_gold": "125", "power_up_id": null, "power_up_quantity": 0, "ruby_amount": 0, "next_bonus_multiplier": null, "bonus_game_id": null, "label": null, "is_milestone": false, "is_enabled": false}
  ],
  "tier_multiplier": "1"
}
```

Day 28 today is a spin day with a milestone card **(live, from the same list)**:

```json
{"day_number": 28, "reward_tokens": "0", "reward_gold": "0", "power_up_id": null, "power_up_quantity": 0, "ruby_amount": 0, "next_bonus_multiplier": null, "bonus_game_id": 2, "label": "Week 4 reward", "is_milestone": true, "is_enabled": true}
```

The same player right after claiming **(live)** (`rewards` left out; unchanged):

```json
{"current_streak": 1, "can_claim": false, "next_reward": {"day_number": 2, "reward_tokens": "0", "reward_gold": "150", "power_up_id": null, "power_up_quantity": 0, "ruby_amount": 0, "next_bonus_multiplier": null, "bonus_game_id": null, "label": null, "is_milestone": false, "is_enabled": true}, "last_claimed_at": "2026-11-24T09:27:34.150005Z", "next_claim_available_at": "2026-11-25T09:27:34.150005Z", "total_claims": 1, "rewards": ["..."], "tier_multiplier": "1"}
```

| Field | Meaning |
|---|---|
| `current_streak` | Days already counted. The next claim pays day `current_streak + 1`. A broken streak reads `0` here (today's rule: start again at day 1). |
| `can_claim` | Show the Claim button enabled. |
| `next_reward` | The card to highlight. |
| `next_claim_available_at` | When the next claim opens (24 hours after the last claim today). Show a countdown while `can_claim` is `false`. |
| `rewards[]` | Every day of the cycle, for the calendar. Amounts are decimal **strings**, already multiplied by the plan (`tier_multiplier`). |
| `rewards[].is_enabled` | `false`: the day stays in the calendar but pays nothing. Grey it out. |
| `rewards[].is_milestone` | Draw a bigger card. |
| `rewards[].bonus_game_id` | A spin day: the claim unlocks a play of that bonus game (see 5). |
| `rewards[].next_bonus_multiplier` | A multiplier day: the next claim is multiplied by it. |
| `rewards[].ruby_amount` | Shown only; not credited (no ruby balance yet). |

Streak rules (today's settings; the server applies them, the app only shows the result): the
next claim opens 24 hours after the last one; missing a whole day (more than 48 hours since
the last claim) breaks the streak and the next claim is day 1 again.

### 2b. Claim

`POST /sensitive/daily-bonus/claim`, no body. Device check applies.

Real reply on day 1 **(live)**:

```json
{
  "granted": true,
  "tokens_awarded": "0",
  "gold_awarded": "100",
  "power_up_id": null,
  "power_up_quantity": 0,
  "new_streak": 1,
  "total_claims": 1,
  "multiplier_applied": "1",
  "tier_multiplier": "1",
  "ruby_amount": 0,
  "next_bonus_multiplier": null,
  "bonus_game_id": null,
  "label": null,
  "is_milestone": false,
  "bonus_game": null
}
```

Reply on a spin day (day 28 today) **(from code)**: the same shape with `"bonus_game_id": 2`,
`"label": "Week 4 reward"`, `"is_milestone": true` and:

```json
"bonus_game": {"bonus_game_id": 2, "code": "daily_spin", "trigger": "daily_bonus_day", "trigger_ref": "28"}
```

- `granted: false` means the day paid nothing (a switched-off day) but the streak still moved
  on. Show "Day <new_streak> checked in" without an amount.
- `multiplier_applied` is a pending multiplier this claim used up (from a multiplier day or a
  `mult` prize of the daily spin); show "x2!" when it is above 1.
- `bonus_game` present: open the daily spin at once with exactly that `trigger` and
  `trigger_ref` (see 5c). Only the **latest** claim's spin can be played, so the app should
  offer it right away and keep offering it until it is played.
- Re-read `GET /wallet/balance` and the status after the claim. The claim writes one
  `daily_bonus` ledger row per currency paid **(live)**:
  `{"entry_id": "ledger:42057", "currency": "gold", "direction": "credit", "amount": 100, "kind": "daily_bonus", "counterparty": "promo_budget", "...": "..."}`.
- A guest claims the same way and got the full 100 gold in the capture (today's setting is
  `guests: full`).

**Errors:**

| Status | `error` | When | Show the user |
|---|---|---|---|
| 409 | `CONFLICT` | Already claimed in this window (`daily bonus already claimed`). | Disable the button; show the countdown from `status`. |
| 403 | `FORBIDDEN` | A guest, when guests may not claim (`guest accounts cannot claim the daily bonus`). Guests may claim today. | "Create an account to collect daily rewards." Offer "Save your progress". |
| 404 | `NOT_FOUND` | No reward is set up for the day. | "Daily bonus isn't available right now." |
| 401 | `FINGERPRINT_MISMATCH` | Device check. | Sign in again. |

```json
// 409, second claim (live)
{"error": "CONFLICT", "message": "conflict: daily bonus already claimed"}

// 409, the daily spin after a claim whose day is not a spin day (live)
{"error": "CONFLICT", "message": "conflict: no_entitlement: the claimed day does not offer this game"}
```

---

## 3. Quests

Quests are small goals ("Win 1 match today") with a reward. They are **daily** (reset at
00:00 UTC), **weekly** (reset on Monday 00:00 UTC), **onboarding** (once per account) or
**event** (during a time window).

### How progress moves

- Progress is counted **by the game servers when a match is settled**, not by the app. There
  is no route to report progress.
- Most quests count finished matches: any match (`match_started`, `match_end`), won matches
  (`match_won`, or `"result": "win"`), matches of one game (`"game"`) or of a list
  (`"games"`), or matches in different games (`distinct_games`).
- Some quests count game events (for example `powerup_used`, `queen_covered`,
  `tournament_ended`). They move only when that game server reports the event; a few may not
  move yet. Show them normally; they simply stay at no progress.
- A player has **no progress row** for a quest until the first match that counts. So the
  list to show is `active` merged with `my-progress`, by quest id.
- Free games count as well as paid ones, and so does a game the opponent forfeited (the
  capture used a free Ludo friends game; the loser forfeited, and both players' "play a
  match" quest moved, the winner's "win a match" quest too).

### 3a. Active quests

`GET /sensitive/quests/active`. Device check applies. A plain array, ordered by scope, then
id.

Real reply **(live)** (58 quests; trimmed to 3):

```json
[
  {"id": 1, "code": "daily_play_any", "title": "Warm-up", "description": "Play 1 match in any game", "scope": "daily", "criteria": {"count": 1, "event": "match_started"}, "reward_tokens": "50", "reward_gold": "0", "reward_powerup_id": null, "reward_powerup_qty": 0, "min_user_level": 1, "is_active": true, "starts_at": null, "ends_at": null},
  {"id": 4, "code": "weekly_win_streak", "title": "On a roll", "description": "Win 10 matches this week", "scope": "weekly", "criteria": {"count": 10, "event": "match_won"}, "reward_tokens": "500", "reward_gold": "0", "reward_powerup_id": null, "reward_powerup_qty": 0, "min_user_level": 1, "is_active": true, "starts_at": null, "ends_at": null},
  {"id": 5, "code": "onboarding_first_5", "title": "Getting started", "description": "Play your first 5 matches", "scope": "onboarding", "criteria": {"count": 5, "event": "match_started", "lifetime": true}, "reward_tokens": "200", "reward_gold": "0", "reward_powerup_id": null, "reward_powerup_qty": 0, "min_user_level": 1, "is_active": true, "starts_at": null, "ends_at": null}
]
```

| Field | Use |
|---|---|
| `title`, `description` | Show as is. |
| `scope` | Group into tabs: `daily`, `weekly`, `onboarding`, `event`. |
| `criteria` | For the target only: `count` or `distinct_games` is the goal number. Don't evaluate it on the device. |
| `criteria.game` / `criteria.games` | Show the game's icon; a "Play" button can open that game. |
| `reward_tokens`, `reward_gold` | Decimal **strings**. Show the non-zero ones. |
| `reward_powerup_id`, `reward_powerup_qty` | A power-up reward, when `qty > 0`. |
| `starts_at`, `ends_at` | Event quests: show "Ends in <countdown>". |
| `min_user_level` | Not enforced by the server today. Ignore it. |

### 3b. My quest progress

`GET /sensitive/quests/my-progress`. Device check applies. A plain array: one row per quest
**and period**, newest period first. Empty (`[]`) for a new player.

Real reply after one won Ludo match **(live)** (5 rows; trimmed to 2, `quest` objects
shortened):

```json
[
  {
    "quest": {"id": 1, "code": "daily_play_any", "title": "Warm-up", "scope": "daily", "criteria": {"count": 1, "event": "match_started"}, "reward_tokens": "50", "reward_gold": "0", "...": "..."},
    "period_start": "2026-11-24",
    "progress": {"count": 1, "target": 1},
    "status": "completed",
    "completed": true,
    "completed_at": "2026-11-24T09:22:30.927267Z",
    "claimed_at": null
  },
  {
    "quest": {"id": 3, "code": "daily_two_games", "title": "Sampler", "scope": "daily", "criteria": {"distinct_games": 2, "event": "match_started"}, "reward_tokens": "150", "reward_gold": "0", "...": "..."},
    "period_start": "2026-11-24",
    "progress": {"games": ["ludo"], "target": 2},
    "status": "in_progress",
    "completed": false,
    "completed_at": null,
    "claimed_at": null
  }
]
```

| Field | Meaning |
|---|---|
| `quest` | The quest, nested under `quest` (unlike achievements, which are flat). |
| `period_start` | The period's first day: today for daily, the Monday for weekly, `2000-01-01` for onboarding and lifetime quests. |
| `progress` | `{"count": n, "target": t}`, or `{"games": [...], "target": t}` for a "different games" quest. Draw the bar as `count / target` or `games.length / target`. |
| `status` | `in_progress`, `completed` (claimable), `claimed`, or `expired`. |

**Merging:** for each active quest, take the row with the same `quest.id` and the current
period (the newest `period_start`). No row: show `0 / target` (the target from
`criteria.count`, or `criteria.distinct_games`, default 1). A row from an older period with
`status: "completed"` can still be claimed (see "Known issues"); show it as claimable.

### 3c. Claim a quest

`POST /sensitive/quests/{quest_id}/claim`, no body. Device check applies. It claims the
newest completed, unclaimed period of that quest.

Real reply **(live)**:

```json
{"quest_id": 1, "period_start": "2026-11-24", "tokens_awarded": "50", "gold_awarded": "0", "powerup_id": null, "powerup_quantity": 0}
```

Then mark the row claimed (or refetch `my-progress`) and re-read `GET /wallet/balance`.

**Errors:**

| Status | `error` | `message` | When | Show the user |
|---|---|---|---|---|
| 409 | `CONFLICT` | `conflict: quest reward already claimed` | The second claim. | Mark the row claimed; no error message needed. |
| 400 | `BAD_REQUEST` | `bad request: quest not yet completed` | Progress below the target. | "Finish the quest first." Refetch progress. |
| 400 | `BAD_REQUEST` | `bad request: quest period expired` | The period is marked expired. | "This quest has ended." |
| 404 | `NOT_FOUND` | `not found: quest progress not found` | No progress at all yet. | "Finish the quest first." |
| 404 | `NOT_FOUND` | `not found: quest not found` | Unknown quest id. | Refetch the list. |
| 401 | `FINGERPRINT_MISMATCH` | | Device check. | Sign in again. |

```json
// 409, second claim (live)
{"error": "CONFLICT", "message": "conflict: quest reward already claimed"}
// 400, in progress (live)
{"error": "BAD_REQUEST", "message": "bad request: quest not yet completed"}
// 404, no progress yet (live)
{"error": "NOT_FOUND", "message": "not found: quest progress not found"}
```

Show Claim only for `status: "completed"`, so these are rare.

---

## 4. Achievements

Badges a player earns for life. Two kinds:

- **Flat**: `tiers` is `[]`. One unlock, one claim, paying `reward_tokens` and `reward_gold`
  (often `0`: then the badge is the reward, and `exp_reward` is shown as XP).
- **Tiered**: `tiers` lists bronze, silver, gold and royal thresholds. A measured value
  (matches played, wins, a streak, a game stat) keeps growing; each tier reached is claimed
  separately and pays its own reward: tokens, gold, an avatar or a title.

Progress is counted by the game servers when a match is settled, like quests. A flat badge
shows **no partial progress** (`progress` is `{}` until it unlocks); a tiered badge shows
`progress_value` once its first tier is reached.

**Secret badges** (`is_secret: true`) come back as `"name": "Secret achievement"`, with no
description and an empty `criteria`, until reached. Show them as a locked mystery badge.

### 4a. All achievements

`GET /achievements` or `GET /achievements?game_id=<numeric game id>` (that game's badges plus
the platform-wide ones). A plain array, ordered by `sort_order`, then id.

Real reply **(live)** (150 items; trimmed to 2):

```json
[
  {"id": 15, "game_id": 1, "code": "ludo_first_win", "name": "First Win", "description": "Win your first Ludo match.", "criteria": {"count": 1, "event": "match_end", "result": "win"}, "reward_tokens": 0, "reward_gold": 0, "exp_reward": 10, "icon_url": "/assets/achievements/ludo/first_win.svg", "sort_order": 0, "tiers": [], "trigger": null, "is_secret": false},
  {"id": 230, "game_id": 25, "code": "sl_dice_roller", "name": "Dice Roller", "description": "Matches played", "criteria": {"event": "match_end", "game": "snake-and-ladder", "measure": "count"}, "reward_tokens": 0, "reward_gold": 0, "exp_reward": 0, "icon_url": null, "sort_order": 2, "tiers": [
    {"tier": "bronze", "threshold": 10, "reward": {"kind": "tokens", "amount": 50}},
    {"tier": "silver", "threshold": 100, "reward": {"kind": "tokens", "amount": 250}},
    {"tier": "gold", "threshold": 1000, "reward": {"kind": "gold", "amount": 500}},
    {"tier": "royal", "threshold": 10000, "reward": {"kind": "title", "name": "Dice Roller"}}
  ], "trigger": "matches_played", "is_secret": false}
]
```

- `icon_url` is a path on the server or `null`; draw a default badge for `null`.
- `tiers[].reward.kind` is `tokens` or `gold` (`amount`), `avatar` (`avatar_id`) or `title`
  (`name`).
- Use this route for a "browse" view without player state; the Achievements tab uses 4b.

### 4b. My achievements

`GET /achievements/my`. The same items, flat (no nested object), plus the player's state.
Every active achievement is listed, reached or not.

Real reply after one won Ludo match **(live)** (150 items; trimmed to 2):

```json
[
  {"id": 15, "game_id": 1, "code": "ludo_first_win", "name": "First Win", "description": "Win your first Ludo match.", "criteria": {"count": 1, "event": "match_end", "result": "win"}, "reward_tokens": 0, "reward_gold": 0, "exp_reward": 10, "icon_url": "/assets/achievements/ludo/first_win.svg", "sort_order": 0, "tiers": [], "trigger": null, "is_secret": false,
   "progress": {"count": 1}, "completed": true, "completed_at": "2026-11-24T09:22:30.927267Z", "claimed_at": null, "progress_value": null, "tier_reached": null, "claimed_tiers": [], "titles": []},
  {"id": 234, "game_id": 25, "code": "sl_phoenix", "name": "Secret achievement", "description": null, "criteria": {}, "reward_tokens": 0, "reward_gold": 0, "exp_reward": 0, "icon_url": null, "sort_order": 8, "tiers": [
    {"tier": "bronze", "threshold": 1, "reward": {"kind": "tokens", "amount": 200}},
    {"tier": "royal", "threshold": 500, "reward": {"kind": "title", "name": "Secret achievement"}}
  ], "trigger": "game_event", "is_secret": true,
   "progress": {}, "completed": false, "completed_at": null, "claimed_at": null, "progress_value": null, "tier_reached": null, "claimed_tiers": [], "titles": []}
]
```

(The second item's `tiers` is trimmed to 2 of 4.)

| Field | Meaning |
|---|---|
| `completed` | Unlocked (flat), or the first tier reached (tiered). |
| `claimed_at` | Flat: when the reward was claimed. Tiered: the latest tier claim. |
| `progress_value` | Tiered: the measured value. Draw the bar towards the next tier's `threshold`. |
| `tier_reached` | Tiered: the highest tier reached (`bronze` ... `royal`), or `null`. |
| `claimed_tiers` | Tiers already claimed, for example `["bronze"]`. |
| `titles` | Titles the player holds from this badge. Show them on the profile. |

A tiered badge's claimable tiers are every tier from bronze up to `tier_reached` that is not
in `claimed_tiers`.

### 4c. Claim an achievement

`POST /achievements/{id}/claim` for a flat badge.
`POST /achievements/{id}/claim?tier=bronze` (or `silver`, `gold`, `royal`) for one tier of a
tiered badge. No body. No device check.

Real reply, a flat badge with no money reward **(live)**:

```json
{"achievement_id": 15, "tokens_awarded": 0, "gold_awarded": 0, "tier": null, "avatar_id": null, "title": null}
```

A tier reply **(from code)**: `{"achievement_id": 230, "tokens_awarded": 50, "gold_awarded": 0,
"tier": "bronze", "avatar_id": null, "title": null}`. An avatar tier fills `avatar_id` (the
avatar is added to the player's owned avatars); a title tier fills `title`.

Show a "Claimed" animation with what was paid, then refetch `/achievements/my`; re-read the
wallet when `tokens_awarded` or `gold_awarded` is above 0.

**Errors:**

| Status | `error` | `message` | When | Show the user |
|---|---|---|---|---|
| 409 | `CONFLICT` | `conflict: achievement already claimed` / `conflict: <tier> tier already claimed` | The second claim. | Mark it claimed. |
| 400 | `BAD_REQUEST` | `bad request: achievement not unlocked yet` | Flat badge not reached. | "Not unlocked yet." |
| 400 | `BAD_REQUEST` | `bad request: <tier> tier not reached yet` | Tier not reached. | "Not unlocked yet." |
| 400 | `BAD_REQUEST` | `bad request: tier is required for a tiered achievement` (`field`: `tier`) | Tiered badge claimed without `?tier=`. | An app bug. |
| 400 | `BAD_REQUEST` | `bad request: achievement has no <tier> tier` | A tier on a flat badge, or a tier the badge lacks. | An app bug. |
| 400 | `BAD_REQUEST` | `bad request: Query deserialize error: unknown variant ...` | `?tier=` is not one of the four. | An app bug. |
| 404 | `NOT_FOUND` | `not found: achievement <id>` | Unknown id. | Refetch the list. |

```json
// 409, second claim (live)
{"error": "CONFLICT", "message": "conflict: achievement already claimed"}
// 400 (live)
{"error": "BAD_REQUEST", "field": "tier", "message": "bad request: tier is required for a tiered achievement"}
// 400 (live)
{"error": "BAD_REQUEST", "message": "bad request: bronze tier not reached yet"}
```

---

## 5. Bonus games

Small prize games: a **wheel**, a **scratch** card, a **chest**, a **flip** (double or
nothing) and a **pick** (pick a card). The server draws the prize when the player plays; the
reply says which slot to land on. The app **never** decides the outcome; it only animates
`slot_index` and shows `prize`.

Each game belongs to one **trigger**, the moment it is offered:

| `trigger` | Offered | `trigger_ref` to send | Today |
|---|---|---|---|
| `welcome_bonus` | The welcome free spin. | The grant id (`free_spin.trigger_ref`), or leave it out. | `welcome_wheel` |
| `daily_bonus_day` | After a spin-day daily claim. | The claim number (`bonus_game.trigger_ref`), or leave it out for the latest. | `daily_spin` |
| `post_match` | After a finished match, within 24 hours. | The match id (UUID). | `chest_post` is not published yet. |
| `level_up` | When the player reaches a level in a game. | `"<game_id>:<level>"`, for example `"1:2"`. | `pick3` |
| `store` | Any time, for a token or gold cost. | Leave it out. | `scratch_gold`, 200 tokens |
| `rewarded_ad`, `streak_milestone` | | | Refused by the server: no way to verify them yet. Don't offer. |

Free plays need an entitlement the server can check (one play per welcome grant, per daily
claim, per match or per level). Store plays need the cost in the wallet.

### 5a. List

`GET /bonus-games` or `GET /bonus-games?trigger=store`. A plain array of published games,
with the player's limits.

Real reply **(live)** (4 games; trimmed to 1, `prizes` trimmed to 2 of 7):

```json
[
  {
    "id": 3,
    "code": "scratch_gold",
    "name": "Gold scratch card",
    "game_type": "scratch",
    "trigger": "store",
    "cost": {"kind": "tokens", "amount": 200},
    "cooldown_hours": 0,
    "max_plays_per_day": 5,
    "slot_count": 9,
    "show_odds": true,
    "me": {
      "block_reason": null,
      "plays_today": 0,
      "plays_left_today": 5,
      "payout_today_tokens": 0,
      "daily_payout_cap_tokens": 10000,
      "cooldown_until": null,
      "pity": null
    },
    "prizes": [
      {"id": 25, "label": "No match", "prize_type": "none", "amount": 0, "rarity": "common", "odds_pct": "55"},
      {"id": 19, "label": "5,000 gold", "prize_type": "gold", "amount": 5000, "rarity": "legendary", "odds_pct": "0.20"}
    ]
  }
]
```

| Field | Meaning |
|---|---|
| `game_type` | `wheel`, `scratch`, `chest`, `flip` or `pick`. Pick the screen by it. |
| `cost.kind` | `free`, `tokens`, `gold` or `rewarded_ad` (not playable today). `cost.amount` is the price. |
| `slot_count` | Wheel slices, scratch cells or cards. |
| `prizes[]` | In slot order. `odds_pct` is a decimal string, or `null` when `show_odds` is `false`; show the odds table only when it is not `null` (some stores require it). |
| `prizes[].prize_type` | `tokens`, `gold`, `powerup`, `mult` (next daily bonus multiplier; `amount` is x100, so `200` = x2), `ruby`, `cosmetic`, `none`. |
| `prizes[].rarity` | `common`, `rare`, `epic`, `legendary`. Colour the slice. |
| `me.block_reason` | `null` = may play. Otherwise: `cooldown`, `max_per_day`, `payout_cap`, `global_cap`, `guest` (guests may not play), `paused`, `not_available`. |
| `me.plays_left_today` | Plays left; the day resets at 00:00 UTC. |
| `me.cooldown_until` | While a cooldown runs: show "Next play in <countdown>". |
| `me.pity` | Chests only: `{"opens_after": n, "opens_since_rare": m}`; a rare-or-better prize is guaranteed on open `n`. Show "Rare guaranteed in <n - m> opens". |

`block_reason` is about limits only. It does **not** say whether the player has the free
play's entitlement: for example a player whose welcome grant is blocked still sees
`welcome_wheel` with `block_reason: null`. Offer free games only through their trigger (the
welcome `free_spin`, the daily claim's `bonus_game`, a finished match, a level up).

### 5b. One game

`GET /bonus-games/{id or code}`, for example `/bonus-games/welcome_wheel`. Same object as one
list item. Use it to open a game screen from a trigger.

```json
// 404, unknown or unpublished game (live)
{"error": "NOT_FOUND", "message": "not found: bonus game not found"}
```

### 5c. Play

`POST /bonus-games/{id or code}/play`. Device check applies.

```json
{"trigger": "welcome_bonus", "trigger_ref": "634"}
```

`trigger` must be the game's own trigger. `trigger_ref` is up to 80 characters; leave it out
where the table above allows.

Real reply, the welcome spin **(live)**:

```json
{
  "play_id": 1,
  "bonus_game_id": 1,
  "code": "welcome_wheel",
  "prize": {
    "id": 8,
    "label": "50 tokens",
    "prize_type": "tokens",
    "rarity": "common",
    "base_amount": 50,
    "amount": 50,
    "currency": "token",
    "power_up_id": null,
    "avatar_id": null,
    "next_bonus_multiplier": null
  },
  "slot_index": 0,
  "multiplier_applied": "1",
  "prize_token_value": 50,
  "pity_triggered": false,
  "cost": {"kind": "free", "amount": 0},
  "balances": {"tokens": 650, "gold": 500},
  "server_seed_hash": "2798837fd7b62bc70b0d4121216a1ea4d6969b058edaec597d7f7dfa24b59946",
  "server_seed": "431e4b5fd8329e3d28ee92505b0230a289b41700bf5ecba2f1d61265fe57ddf6",
  "roll": "0.2541756",
  "plays_left_today": 0,
  "played_at": "2026-11-24T09:21:10.698406Z"
}
```

A paid scratch card (`{"trigger": "store"}`) answered the same shape with
`"cost": {"kind": "tokens", "amount": 200}` and a `"400 tokens"` prize **(live)**.

| Field | Use |
|---|---|
| `slot_index` | The slice, cell or card to land on (0-based). |
| `prize.amount` | What was paid: tokens or gold after multipliers, the power-up quantity, `1` for a cosmetic, the x100 multiplier for `mult`. Show this, not `base_amount`. |
| `prize.currency` | `token` or `gold` for money prizes. A **guest's** gold prize is paid as tokens at half value. |
| `prize.next_bonus_multiplier` | A `mult` prize: "Your next daily bonus is x2". |
| `pity_triggered` | The chest's guarantee paid out. |
| `balances` | New wallet balances (numbers). Update the header after the animation. |
| `plays_left_today` | Update the button. |
| `server_seed_hash`, `server_seed`, `roll` | Fairness proof: `sha256(server_seed) == server_seed_hash`. Optional "Verify" screen; not needed for play. |

**Errors:**

| Status | `error` | `message` starts with | When | Show the user |
|---|---|---|---|---|
| 409 | `CONFLICT` | `conflict: blocked: <code>` | A limit (codes as in 5a). The second welcome spin answers `blocked: max_per_day`. | Per code: "Come back in <countdown>" (`cooldown`), "No plays left today" (`max_per_day`, `payout_cap`, `global_cap`), "Create an account to play" (`guest`), "Not available right now" (others). |
| 409 | `CONFLICT` | `conflict: no_entitlement: ...` | The free play's source is missing or used (`no daily bonus claim`, `this claim's spin was used`, `the free spin was used`, `not your welcome grant`, `that is not the level you just reached`, `this match's play was used`, `the match ended too long ago`). | "This free play isn't available." Close the game. |
| 409 | `CONFLICT` | `conflict: unsupported: ...` | `rewarded_ad` trigger or cost, `streak_milestone`. | Don't offer these games. |
| 409 | `CONFLICT` | `conflict: no_prizes` | No prize can be drawn for this player. | "Not available right now." |
| 409 | `INSUFFICIENT_FUNDS` | | The cost can't be paid. | "Not enough tokens." Offer the shop. |
| 400 | `BAD_REQUEST` | `bad request: trigger: this game is offered on '<trigger>'` (`field`: `trigger`) | Wrong trigger. | An app bug. |
| 400 | `BAD_REQUEST` | `bad request: trigger_ref: ...` (`field`: `trigger_ref`) | Missing or malformed reference. | An app bug. |
| 404 | `NOT_FOUND` | | Unknown or unpublished game. | Refetch the list. |
| 401 | `FINGERPRINT_MISMATCH` | | Device check. | Sign in again. |
| 503 | `KILL_SWITCH_ENGAGED` | | The platform (or, for paid plays, the store) is paused. | Show the operator's `message`. |

```json
// 409, second welcome spin (live)
{"error": "CONFLICT", "message": "conflict: blocked: max_per_day"}
// 409, daily spin without a spin-day claim (live)
{"error": "CONFLICT", "message": "conflict: no_entitlement: no daily bonus claim"}
// 409, a level the player has not just reached (live)
{"error": "CONFLICT", "message": "conflict: no_entitlement: that is not the level you just reached"}
// 409, a trigger_ref that is not the player's grant (live)
{"error": "CONFLICT", "message": "conflict: no_entitlement: not your welcome grant"}
// 400 (live)
{"error": "BAD_REQUEST", "field": "trigger", "message": "bad request: trigger: this game is offered on 'welcome_bonus'"}
// 400 (live)
{"error": "BAD_REQUEST", "field": "trigger_ref", "message": "bad request: trigger_ref: must be 'game_id:level'"}
// 400, unknown ?trigger= on the list (live)
{"error": "BAD_REQUEST", "message": "bad request: Query deserialize error: unknown variant, expected one of `daily_bonus_day`, `post_match`, `level_up`, `store`, `rewarded_ad`, `welcome_bonus`, `streak_milestone`"}
```

Disable the Play button while the request runs: a double tap on a paid game pays twice.

### 5d. My plays

`GET /bonus-games/plays/me`. Item list with a cursor (shape 3 in `00-conventions.md`): page
size `per` (default 20), next page `?after=<next_cursor>`. Newest first.

Real reply **(live)** (2 items; trimmed to 1):

```json
{
  "items": [
    {"id": 2, "bonus_game_id": 3, "code": "scratch_gold", "name": "Gold scratch card", "trigger": "store", "trigger_ref_table": null, "trigger_ref_id": null, "cost_currency": "token", "cost_amount": 200, "prize_id": 23, "prize_label": "400 tokens", "prize_type": "tokens", "prize_amount": 400, "prize_token_value": 400, "rarity": "common", "multiplier_applied": "1.00", "pity_triggered": false, "server_seed_hash": "248ad789088648e440be43dafafee24e9087667d045a33828fd6531ee4b51ba7", "roll": "0.77881988", "cost_ledger_id": 42035, "prize_ledger_id": 42036, "played_at": "2026-11-24T09:21:12.229614Z"}
  ],
  "page": 1, "pages": 1, "total": 2, "next_cursor": null
}
```

Use it for a "Prize history" list. `prize_ledger_id` and `cost_ledger_id` match the ledger
rows' `entry_id` (`"ledger:<id>"`).

---

## Errors

Every error has the shared body from `00-conventions.md`. Decide on the status and `error`.
For the `409 CONFLICT` replies of the welcome claim and the bonus game play, the start of
`message` (`completed`, `nothing_due`, `blocked: <code>`, `no_entitlement`, ...) is a
stable code the server documents for branching; read it only there, and keep a generic
fallback. Never show `message` to the user.

Common to every route here:

| Status | `error` | Meaning |
|---|---|---|
| 401 | `UNAUTHORIZED` | No or expired token; the interceptor from `01-auth.md` refreshes once. |
| 401 | `FINGERPRINT_MISMATCH` | Device check on the routes marked above. Sign in again. |
| 429 | `RATE_LIMITED` | About 100 requests a minute per player. Wait and retry once. |
| 500 | `DATABASE_ERROR`, `INTERNAL_ERROR` | "Something went wrong. Try again." |

```json
// 401, no token (live)
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}
```

---

## Known issues the app must cope with

1. **Older completed quests stay claimable.** Nothing marks a past period `expired`, so a
   daily quest completed yesterday and not claimed can still be claimed today. Show such rows
   as claimable under their quest; don't hide them.
2. **Quests that count game events may not move.** Some active quests count events
   (`powerup_used`, `tournament_ended`, `word_placed`, ...) that not every game reports yet.
3. **`min_user_level`** is in every quest but not checked by the server.
4. **The bonus game list doesn't know entitlements** (see 5a). Offer free games only from
   their trigger.
5. **The second welcome spin** answers `blocked: max_per_day` on the same day and
   `no_entitlement: the free spin was used` later. Treat both as "already used" and rely on
   `free_spin.available` from 1a.
6. Reward ledger rows have `game_code: null`, also for a welcome bonus from a game.

---

## Done when

- [ ] After sign-up, the welcome sheet shows the amount and the expiry countdown; Claim pays
      it, updates the header balance from `balances`, and the sheet closes.
- [ ] A second claim (or reopening) does not show the sheet again; the `completed` reply is
      handled silently.
- [ ] Sign-up without `device_id` still claims: the app registers the device on
      `device_required` and retries once.
- [ ] A second account on the same device sees "This device already received a welcome
      bonus" and no sheet.
- [ ] The Welcome wheel lands on `slot_index`, shows the prize and updates the balance; a
      second spin is not offered.
- [ ] The daily bonus calendar shows all days, today's card, the streak and a countdown;
      Claim pays and the button turns into the countdown; a second tap is handled quietly.
- [ ] A spin-day claim opens the daily spin with the claim's `trigger_ref`.
- [ ] Quests show daily, weekly and onboarding tabs with progress bars, including quests
      with no progress row yet.
- [ ] After a finished game, the app refetches and the completed quest shows Claim and a red
      dot; Claim pays it and a second tap does nothing harmful.
- [ ] Achievements show flat and tiered badges, secret ones as mystery badges, and each
      reachable tier can be claimed once.
- [ ] A store scratch card charges the cost, shows the prize, and "Not enough tokens" when
      the wallet is short; the Play button can't be tapped twice.
- [ ] Every claim or play leaves the header balance equal to `GET /wallet/balance`.
- [ ] No reward amount is computed on the device; all come from the server.

---

## Test accounts

Create your own players on the development server with `POST /auth/register` (any
`@example.com` email) or "Play as guest", as in `01-auth.md`. Each new player has a fresh
welcome grant. To move quests and achievements, play a free Ludo game between two of your
own players (`games/ludo.md`). Don't use other people's accounts.

The samples here came from players `w07doc1795512062a`, `w07doc1795512120b`,
`w07doc1795512120c` and `w07doc1795512452d`, and two guests, made for this file on 24 Nov 2026.
