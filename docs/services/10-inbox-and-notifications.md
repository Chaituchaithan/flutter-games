# Flutter hand-off 10: inbox and notifications

The player's inbox (messages, some with tokens or gold to claim), notifications (short
announcements), notification preferences, and what happens with the push token.

This file is the contract between the Flutter app and the **api-gateway** routes for these.
It is written so a Claude agent can implement it directly. Read `00-conventions.md` first:
the error body, list shapes, money parsing and times are defined there and not repeated here.
Sessions and the auth interceptor come from `01-auth.md`. Registering the device and its push
token is in `02-profile-and-sessions.md` section 10; this file does not repeat it.

**Where the samples come from.** Every reply marked "real" was captured from the running
gateway on 24 Nov 2026 with a fresh test player. Replies marked "from the code" were not
captured; their shape is read from the gateway source. Nothing a player can do creates an
inbox message or a notification today (see "What creates an item"), so a new player's lists
are always empty and the item shapes come from the code.

**Read this first: what the backend does not have.** Several things an inbox screen usually
needs are missing today. The app must not invent them; build around what exists and hide the
rest (see "Known issues"):

| Wanted | State today |
|---|---|
| Push notifications to the phone | **None.** The gateway stores push tokens but has no FCM or APNs sender. Nothing is ever pushed. |
| Unread count / badge route | **No route** for the inbox or for notifications. Count on the device (see 1g and 2b). |
| Mark a notification read, or delete one | **No route.** Notifications have no per-player read state. Keep "last seen" on the device. |
| Mark all inbox messages read | **No route.** Mark them one by one. |
| Inbox items from game events (results, refunds, gifts, friend requests, bonuses) | **None.** Only two admin actions write inbox messages; only one admin action writes notifications. |
| Preferences that change what is sent | **Stored only.** No code reads the toggles or quiet hours yet. |
| Deep links or buttons on a message | **Fields exist** (`cta_label`, `cta_action`, `icon_url`) but nothing fills them; always `null` today. |
| Power-up rewards in a message | **Not claimable** (`503 UNAVAILABLE`); nothing attaches them today. |

---

## For the Claude agent: what to build

1. An `InboxApi` on the shared `ApiClient` with one method per route below.
2. Models: `InboxMessage`, `ClaimResult`, `PlayerNotification`, `NotificationPreferences`, and
   the page list shape 2 wrapper (`{data, total, page, per_page, total_pages}`,
   `00-conventions.md`).
3. An `InboxBadge` service that holds two numbers for the app bar and the tab icon:
   - unread inbox messages (from the inbox list, 1g);
   - new notifications (sent after the "last seen" time kept on the device, 2b).
   It refreshes on app start, on resume, after a claim, read or delete, and when the Inbox
   screen opens. Never more than once every 10 seconds.
4. Screens:
   - **Inbox**: a list (newest first) with an unread dot and a reward chip ("+500 tokens")
     on messages with an unclaimed reward; pull to refresh; load more.
   - **Message detail**: title, body, sent time, expiry if any, a **Claim** button when there
     is a reward, a **Delete** action.
   - **Notifications**: a simple list (title, body, time). It can be a second tab of Inbox.
   - **Notification settings** (under Settings): the seven toggles, quiet hours (start, end)
     and a time zone, plus a "Push notifications" switch that turns the device push token on
     or off (2c in `02-profile-and-sessions.md` 10b).
5. Push plumbing, kept minimal (see section 4): ask for permission, get the FCM / APNs token,
   send it with the device registration from `02-profile-and-sessions.md` 10a. A tap on any
   push (none are sent today) opens the Inbox screen.
6. Tests: model parsing for each sample here (both real and from the code); the error mapping
   for each route; that a claim re-reads the wallet; that `409 CONFLICT` on claim is treated
   as "already claimed"; that delete asks to confirm when a reward is unclaimed; that the
   preferences PATCH sends only changed fields, and `null` to clear quiet hours.

Never log claim replies or wallet amounts in release builds.

---

## Endpoints at a glance

All paths are under `http://<host>:1280/api/v1`. All need `Authorization: Bearer
<access_token>`; without it every route answers `401 UNAUTHORIZED` (real). None of these
routes is under `/sensitive/`, so none has the device check.

| Area | Method and path | Success |
|---|---|---|
| Inbox | `GET /inbox` | `200` + page list |
| | `GET /inbox/{id}` | `200` + message |
| | `POST /inbox/{id}/read` | `200` `{"status":"read"}` |
| | `POST /inbox/{id}/claim-reward` | `200` `{"status":"claimed", ...}` |
| | `DELETE /inbox/{id}` | `200` `{"status":"deleted"}` |
| Notifications | `GET /notifications` | `200` + page list |
| Preferences | `GET /notifications/preferences` | `200` + preferences |
| | `PATCH /notifications/preferences` | `200` + preferences |
| Push token | `POST /devices/register`, `PATCH /devices/{id}/push-token` | see `02-profile-and-sessions.md` 10 |

Inbox ids are **numbers** (`/inbox/42`). A word there is a `400 BAD_REQUEST` (real):

```json
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: can not parse to a i64"}
```

Notification ids are UUID strings, but no route takes one.

**Page lists** in this file are shape 2 from `00-conventions.md`: query `?page=1&per_page=20`
(`per_page` 1 to 100, default 20), reply `{data, total, page, per_page, total_pages}`. A
`per_page` outside 1-100 is real:

```json
{"error": "VALIDATION_ERROR", "field": "per_page", "message": "validation error: per_page: must be between 1 and 100"}
```

Routes that do **not** exist (real `404 NOT_FOUND`, "no route for ..."):
`GET /notifications/unread-count`, `POST /notifications/{id}/read`. `GET /inbox/unread-count`
answers `400 BAD_REQUEST` (it is read as `GET /inbox/{id}` with a word id). Admin routes exist
(`/admin/...`, `/notifications/admin/...`); the app never calls them.

---

## What creates an item

Searched in the whole backend (every crate and every migration) for writes to
`inbox_messages` and `sent_notifications`, on 24 Nov 2026. There are exactly three writers,
and all are **admin console actions**:

| Writes | Admin action (console) | What the player gets |
|---|---|---|
| Inbox message | Player page, "Send inbox message" (`POST /admin/users/{id}/inbox`) | One message to one player: title (1-200 chars), body (1-2000 chars), optional `attached_token` and `attached_gold`, optional `expires_at`. The only way a reward message appears. |
| Inbox message | Finance, "Resend dunning reminders" (`POST /admin/finance/subscriptions/dunning/resend`) | A payment reminder to each player whose subscription payment is failing. No reward. Expires after 14 days. |
| Notification | Notifications, "Send" (`POST /notifications/admin/send`) | One notification, to **every** player (`target_type: "all"`) or one player (`"user"`). Title 1-120 chars, body 1-500 chars. In-app only. |

Nothing else creates an inbox message or a notification. In particular, from the code:
sign-up, the welcome bonus, the daily bonus, quests, achievements, level-ups, match results,
entry fees and payouts, tournament starts, results and refunds, friend requests, gifts,
referrals, purchases and subscriptions (other than the dunning reminder above). This matches
`09-social.md` (no notification for friend requests or gifts).

Real check: the test player registered a device, claimed the welcome bonus (`200`, +500
tokens) and the daily bonus (`200`, +100 gold); `GET /inbox` and `GET /notifications` were
still empty afterwards:

```json
{"data": [], "total": 0, "page": 1, "per_page": 20, "total_pages": 0}
```

So the app must **not** wait for an inbox item or a push to learn about a result, a refund or
a reward. Each feature's own file says when to re-read (`03-wallet.md`, `06-tournaments.md`,
`07-rewards.md`).

---

## 1. Inbox

A message belongs to one player. It may carry tokens and gold to claim once. A message with an
`expires_at` in the past is hidden from the list and its reward can no longer be claimed.

### 1a. The message object

From the code (no message exists for a test player; the fields and their order are the
gateway's `InboxMessage`). Two examples: an admin message with a reward, and a dunning
reminder.

```json
{
  "id": 42,
  "user_id": "8c3be682-6b86-482d-964f-c2a25d92b0fe",
  "title": "Sorry for the outage",
  "body": "Here is a little something.",
  "icon_url": null,
  "cta_label": null,
  "cta_action": null,
  "attached_token": 500,
  "attached_gold": 0,
  "attached_power_ups": [],
  "is_read": false,
  "read_at": null,
  "claimed_at": null,
  "expires_at": "2026-12-01T00:00:00Z",
  "created_at": "2026-11-24T10:00:00.123456Z"
}
```

```json
{"id": 43, "user_id": "8c3be682-6b86-482d-964f-c2a25d92b0fe", "title": "Payment failed", "body": "Update your card to keep your subscription.", "icon_url": null, "cta_label": null, "cta_action": null, "attached_token": 0, "attached_gold": 0, "attached_power_ups": [], "is_read": false, "read_at": null, "claimed_at": null, "expires_at": "2026-12-08T10:00:00.5Z", "created_at": "2026-11-24T10:00:00.5Z"}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | number | The message id for the routes below. |
| `user_id` | UUID | Always the signed-in player. |
| `title` | string | Up to 200 characters. |
| `body` | string | Plain text (up to 2000 from the admin form). Not HTML or Markdown; show as text, keep line breaks. |
| `icon_url` | string or null | Always `null` today. If set later, a URL to an icon; fall back to a default icon. |
| `cta_label` | string or null | Always `null` today. A button label (up to 60 chars). |
| `cta_action` | object or null | Always `null` today. A free-form JSON action; no format is defined. Ignore it unless the app knows its shape; never crash on an unknown one. |
| `attached_token` | number | Tokens to claim. `0` = none. |
| `attached_gold` | number | Gold to claim. `0` = none. |
| `attached_power_ups` | array | Always `[]` today. If not empty, the claim answers `503` (see 1d). |
| `is_read` | bool | `read_at != null`. |
| `read_at` | time or null | First time it was marked read (or claimed). |
| `claimed_at` | time or null | When the reward was claimed. |
| `expires_at` | time or null | After this the message leaves the list and the reward is gone. `null` = never. |
| `created_at` | time | Sent time. The list is sorted by this, newest first. |

Money here is a JSON **number** (not a string). Parse both anyway (`00-conventions.md`).

Derived states the app shows:

| State | Rule |
|---|---|
| Has a reward | `attached_token > 0 || attached_gold > 0` |
| Reward waiting | has a reward and `claimed_at == null` and not expired |
| Reward claimed | `claimed_at != null` |
| Expired | `expires_at != null && expires_at <= now` (server time; see `00-conventions.md` "Times") |

### 1b. List

`GET /inbox?page=1&per_page=20`. Page list, newest first, **expired messages left out**.

Real (a new player):

```json
{"data": [], "total": 0, "page": 1, "per_page": 20, "total_pages": 0}
```

```json
// GET /inbox?page=2&per_page=5, real
{"data": [], "total": 0, "page": 2, "per_page": 5, "total_pages": 0}
```

With messages (from the code), `data` holds message objects from 1a.

What the app does: show the list; bold title and a dot when `is_read` is false; a reward chip
when a reward is waiting; the expiry ("Expires in 3 days") when `expires_at` is set. Load
more with `page+1` until `page >= total_pages`. Empty state: "No messages yet."

### 1c. One message

`GET /inbox/{id}`. `200` with one message object (1a).

Unlike the list, this route also returns an **expired** message (from the code). Show it with
"Expired" and no Claim button.

```json
// 404, real: no such message, or another player's
{"error": "NOT_FOUND", "message": "not found: inbox message not found"}
```

What the app does: open the detail from the list item you already have; call this only when
opening from elsewhere (for example a future push). Then mark it read (1d).

### 1d. Mark read

`POST /inbox/{id}/read`, no body. `200`:

```json
{"status": "read"}
```

(From the code; the shape is fixed in the handler.) Marking an already-read message read again
is fine and keeps the first `read_at`. It also works on an expired message.

```json
// 404, real
{"error": "NOT_FOUND", "message": "not found: inbox message not found"}
```

What the app does: call it when the player opens a message. Update the item locally
(`is_read = true`) and lower the badge at once; don't wait for a list reload. On `404`, remove
the item from the list.

### 1e. Claim the reward

`POST /inbox/{id}/claim-reward`, no body, no `Idempotency-Key`. `200` (from the code; the
handler builds this exact shape):

```json
{"status": "claimed", "token_credited": 500, "gold_credited": 0}
```

The credit, the wallet ledger rows and `claimed_at` are written in one database transaction,
so either all of it happened or none of it. Claiming also marks the message read. The wallet
ledger shows one row per currency with kind `inbox_reward` (`03-wallet.md`). A second claim
can never pay twice.

Errors (from the code; the `404` for an unknown id is real):

| Status | `error` | `message` (for logs only) | When | What the app shows |
|---|---|---|---|---|
| 404 | `NOT_FOUND` | `not found: inbox message not found` | Unknown id or another player's. | Remove the item; "This message is no longer available." |
| 404 | `NOT_FOUND` | `not found: no claimable reward on this message` | The message has no tokens or gold. | Hide the Claim button. |
| 409 | `CONFLICT` | `conflict: reward already claimed` | Claimed before (another device, or a retry after a lost reply). | Treat as success: re-read the message and the wallet; "Already claimed." |
| 400 | `BAD_REQUEST` | `bad request: inbox message has expired` | `expires_at` passed. | "This reward has expired." Show the message as expired. |
| 503 | `UNAVAILABLE` | `unavailable: power-up rewards cannot be claimed yet` | `attached_power_ups` not empty (never today). | "This reward can't be claimed yet. Try again later." Keep the button. |

Both `404`s have the same `error`; tell them apart by whether the item you hold has a reward.

What the app does: disable the button while the call runs; on `200`, set `claimed_at` and
`is_read` locally, show "+500 tokens" from `token_credited` / `gold_credited` (not from the
message fields), then re-read the wallet balance (`GET /wallet/balance`, `03-wallet.md`). On a
timeout, re-read the message (1c): if `claimed_at` is set, the claim went through.

### 1f. Delete

`DELETE /inbox/{id}`. `200` (shape from the code):

```json
{"status": "deleted"}
```

```json
// 404, real: unknown id, another player's, or already deleted
{"error": "NOT_FOUND", "message": "not found: inbox message not found"}
```

Deleting works on any message, **including one with an unclaimed reward**: the reward is lost
for good (from the code). What the app does: when a reward is waiting, ask "Delete this
message? The reward inside will be lost." On `404`, treat it as done and remove the item.

### 1g. Unread count (badge)

There is no route. Count on the device:

1. `GET /inbox?per_page=100` (one call covers almost every player).
2. Unread = items with `is_read == false`. Waiting rewards = items with a reward waiting (1a).
3. If `total > 100`, show "99+" rather than loading more pages for the badge.

Expired messages are already left out of the list, so they never count. Refresh as in "For
the Claude agent", item 3.

---

## 2. Notifications

A notification is a short announcement (title and body) sent from the admin console, either
to every player or to one player. There is no read state, no delete, no link and no reward.
They are shown in the app only; nothing is pushed (section 4).

### 2a. List

`GET /notifications?page=1&per_page=20`. Page list, newest first. It contains:

- every "all players" notification sent **after the account was created** (older broadcasts
  never appear for a new player);
- every notification sent to this player.

Real (a new player):

```json
{"data": [], "total": 0, "page": 1, "per_page": 20, "total_pages": 0}
```

With items (from the code, `PlayerNotification`):

```json
{
  "data": [
    {"id": "5b0e6a64-4f9e-4a39-8d0e-2f1f7b3c9a11", "title": "Weekend tournament", "body": "Ludo Sit & Go entries are half price until Sunday.", "target_type": "all", "sent_at": "2026-11-24T10:05:00.123456Z"},
    {"id": "0c4d2f8e-7a61-4b1a-9f3c-6e5d4a3b2c10", "title": "Account check", "body": "Your support ticket was answered.", "target_type": "user", "sent_at": "2026-11-23T18:00:00Z"}
  ],
  "total": 2, "page": 1, "per_page": 20, "total_pages": 1
}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | UUID | Stable id; use it as a list key. |
| `title` | string | Up to 120 characters. |
| `body` | string | Up to 500 characters, plain text. |
| `target_type` | string | `all` (sent to every player) or `user` (sent to me). Optional label: "Announcement" vs "For you". |
| `sent_at` | time | Sorted by this, newest first. |

What the app does: show title, body and time. Load more with `page+1` until `page >=
total_pages`. Empty state: "No notifications yet."

### 2b. "New" badge

No read state exists on the server. Keep `notificationsLastSeenAt` per player in local storage:

1. Badge = number of items on page 1 (`per_page=20`) with `sent_at > notificationsLastSeenAt`
   ("9+" above 9).
2. When the Notifications screen is shown, set `notificationsLastSeenAt` to the newest
   `sent_at` in the list (server time, not the phone's clock).
3. On a fresh install the value is empty: count nothing as new and set it on first load.

---

## 3. Notification preferences

The player's choices of what to be told about. One row per player, created with every toggle
`true` on the first read.

**Stored only.** No backend code reads these toggles or the quiet hours today (from the code):
nothing is sent, so nothing is filtered. Save and show them so the settings are ready when
pushes arrive. Don't promise the player that a toggle changes anything they receive now.

### 3a. Read

`GET /notifications/preferences`. `200`, real (a new player):

```json
{"user_id": "8c3be682-6b86-482d-964f-c2a25d92b0fe", "friend_requests": true, "match_invites": true, "promotions": true, "gift_received": true, "daily_bonus_reminder": true, "tournament_announcement": true, "your_turn": true, "quiet_hours_start": null, "quiet_hours_end": null, "timezone": null, "updated_at": "2026-11-24T09:54:38.187869Z"}
```

| Field | Type | Settings label |
|---|---|---|
| `friend_requests` | bool | Friend requests |
| `match_invites` | bool | Match invites |
| `promotions` | bool | Offers and promotions. **The same stored value as `marketing_push`** in `PATCH /users/me/privacy` (`02-profile-and-sessions.md` 6): changing one changes the other (real, below). |
| `gift_received` | bool | Gifts received |
| `daily_bonus_reminder` | bool | Daily bonus reminder |
| `tournament_announcement` | bool | Tournaments |
| `your_turn` | bool | Your turn |
| `quiet_hours_start` | `"HH:MM:SS"` or null | Do not disturb from. |
| `quiet_hours_end` | `"HH:MM:SS"` or null | Do not disturb until. The window may cross midnight (`22:30` to `07:00`). |
| `timezone` | string or null | IANA name (`Asia/Kolkata`) in which the quiet hours are read. |
| `updated_at` | time | Last change. |

### 3b. Change

`PATCH /notifications/preferences`. Send only the fields that changed. Omitted fields keep
their value. For `quiet_hours_start`, `quiet_hours_end` and `timezone`, an explicit `null`
clears the value. `200` with the whole object (3a).

Real:

```json
// request
{"promotions": false, "your_turn": true, "quiet_hours_start": "22:30:00", "quiet_hours_end": "07:00:00", "timezone": "Asia/Kolkata"}
// 200
{"user_id": "8c3be682-6b86-482d-964f-c2a25d92b0fe", "friend_requests": true, "match_invites": true, "promotions": false, "gift_received": true, "daily_bonus_reminder": true, "tournament_announcement": true, "your_turn": true, "quiet_hours_start": "22:30:00", "quiet_hours_end": "07:00:00", "timezone": "Asia/Kolkata", "updated_at": "2026-11-24T09:54:38.962201Z"}
```

```json
// request: "HH:MM" is accepted; the reply always has seconds
{"quiet_hours_start": "23:00"}
// 200 (trimmed)
{"quiet_hours_start": "23:00:00", "quiet_hours_end": "07:00:00", "timezone": "Asia/Kolkata", "...": "..."}
```

```json
// request: turn quiet hours off
{"quiet_hours_start": null, "quiet_hours_end": null, "timezone": null}
// 200 (trimmed)
{"promotions": false, "quiet_hours_start": null, "quiet_hours_end": null, "timezone": null, "...": "..."}
```

The privacy link, real: after the PATCH above set `promotions` to `false`, `GET
/users/me/privacy` answered `"marketing_push": false`; `PATCH /users/me/privacy
{"marketing_push": true}` then made `GET /notifications/preferences` answer `"promotions":
true`. Show this toggle in one place only, or re-read both screens after a change.

Errors (all real):

| Status | `error` | `field` | When | Real `message` |
|---|---|---|---|---|
| 400 | `BAD_REQUEST` | | A time that is not a time (`"25:00:00"`). | `bad request: Json deserialize error: input is out of range at line 1 column 29` |
| 400 | `VALIDATION_ERROR` | `timezone` | Not an IANA zone name. | `validation error: timezone: must be an IANA timezone name (e.g. Asia/Kolkata)` |
| 400 | `VALIDATION_ERROR` | `timezone` | Longer than 40 characters. | `validation error: timezone: must be 1 to 40 characters` |
| 400 | `BAD_REQUEST` | | An unknown field (for example `push_enabled`). | ``bad request: Json deserialize error: unknown field `push_enabled`, expected one of `friend_requests`, `match_invites`, `promotions`, `gift_received`, `daily_bonus_reminder`, `tournament_announcement`, `your_turn`, `quiet_hours_start`, `quiet_hours_end`, `timezone` at line 1 column 15`` |
| 400 | `BAD_REQUEST` | | A toggle that is not `true` / `false`. | `bad request: Json deserialize error: invalid type: string, expected a boolean at line 1 column 21` |

What the app does:

- Show the toggles from 3a; on each change, PATCH that one field and show the returned
  value (roll the switch back on an error).
- Quiet hours: a switch plus two time pickers. On, send both times as `"HH:MM:SS"` and the
  device's IANA zone (`flutter_timezone`). Off, send all three as `null`.
- Never send `push_enabled` or any field not listed: the server refuses unknown fields. The
  push on/off switch is the device push token, not a preference (section 4).

---

## 4. Push notifications

**State today, from the code:** the gateway stores push tokens (`02-profile-and-sessions.md`
10, table `push_tokens`, provider `fcm` for Android and web, `apns` for iOS) but **nothing
sends a push**. There is no FCM or APNs client, no push payload, and no event that triggers a
push, in any crate. The admin notification send is in-app only (its code says "no device push
yet"). So:

- **Which events send a push:** none.
- **Payload shape:** none is defined. Don't build parsing for a guessed payload.
- **On tap:** nothing to handle yet.

What the app does now, so that pushes can be switched on later without an app update:

1. Ask for notification permission at a sensible moment (after the first finished game, not
   at first launch). iOS needs the APNs token; Android 13+ needs the runtime permission.
2. Send the token with the device registration (`02-profile-and-sessions.md` 10a) after every
   sign-in, and again on each token refresh (10b).
3. The Settings "Push notifications" switch: off sends `{"push_token": null}` (10b); on asks
   for permission if needed and sends the current token. Show "off" when the OS permission
   is denied, with a link to the system settings.
4. Log out clears this device's token first (`02-profile-and-sessions.md` 10c).
5. If a push ever arrives (foreground or tap), ignore its contents and open the **Inbox**
   screen, then refresh the inbox and notification lists. This is safe whatever the payload
   turns out to be.

When a push sender is built, this section gets the payload and the deep links; until then the
app finds out about new items only by re-reading the lists (1b, 2a).

---

## Errors

Every error has the shared body from `00-conventions.md`. Decide on the status, `error` and
`field`, never on `message`. Each route above lists its own errors.

Common to every route here:

| Status | `error` | Meaning |
|---|---|---|
| 400 | `BAD_REQUEST` | A word where an inbox id goes, or a malformed body. |
| 400 | `VALIDATION_ERROR` | `per_page` outside 1-100, or a bad `timezone`. |
| 401 | `UNAUTHORIZED` | No or expired token; the interceptor from `01-auth.md` refreshes once. |
| 401 | `TOKEN_BLACKLISTED` | This session was signed out. Go to `signedOut`. |
| 429 | `RATE_LIMITED` | About 100 requests a minute per player. Wait and retry once. |
| 500 | `DATABASE_ERROR`, `INTERNAL_ERROR`, `CACHE_ERROR` | "Something went wrong. Try again." |

```json
// 401, no token, real
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}
```

---

## Known issues (the app must cope)

1. **No push at all.** Tokens are stored but never used. The app learns about new inbox
   messages and notifications only by re-reading the lists (app start, resume, screen open).
2. **No unread-count route**, and notifications have **no read state**. Count inbox unread
   from the list (1g); keep a local "last seen" for notifications (2b). A player on two phones
   sees the notification badge separately on each.
3. **No events create items.** Only admin console actions write inbox messages and
   notifications. Results, refunds, rewards, gifts and friend requests never appear here; keep
   reading each feature's own routes.
4. **Preferences are stored but unused,** including quiet hours. Present them as settings
   without promising an effect.
5. **`promotions` and privacy `marketing_push` are one value.** Changing either changes both.
6. **Delete forfeits an unclaimed reward** without a server-side warning. The app confirms
   first (1f).
7. **The list hides expired messages, but `GET /inbox/{id}` still returns them.** Check
   `expires_at` in the detail view before showing Claim.
8. **`cta_label`, `cta_action` and `icon_url` are always `null`**; `cta_action` has no
   defined format. Render without them; ignore an action the app doesn't understand.
9. **Power-up attachments can't be claimed** (`503 UNAVAILABLE`); nothing attaches them yet.
10. **Old broadcasts are not shown to new players.** An "all players" notification reaches
    only accounts that existed when it was sent.

---

## Done when

- [ ] The Inbox screen lists messages newest first with unread dots, reward chips and expiry
      text; "load more" pages until `page >= total_pages`; the empty state shows for a new
      player.
- [ ] Opening a message marks it read; the dot and the badge clear at once.
- [ ] Claim credits the reward: the button disables during the call, "+N tokens" shows from
      the reply, the wallet balance is re-read, and the ledger shows an `inbox_reward` row.
- [ ] A second claim (or `409`) shows "Already claimed" and does not look like an error.
- [ ] An expired message shows "Expired" and no Claim button; a claim on one shows "This
      reward has expired".
- [ ] Delete asks to confirm when a reward is waiting; a `404` on delete is treated as done.
- [ ] The Notifications list shows title, body and time; the "new" badge counts items sent
      after the local "last seen" and clears when the screen opens.
- [ ] Notification settings show the seven toggles from the server; each change PATCHes only
      that field and rolls back on an error.
- [ ] Quiet hours on sends both times and the device's IANA zone; off sends three `null`s;
      a bad zone shows "Choose a valid time zone".
- [ ] The offers toggle and the privacy "marketing push" toggle never show different values.
- [ ] The push switch sends or clears the device push token (`02-profile-and-sessions.md`
      10b); a denied OS permission shows the switch off with a link to system settings.
- [ ] A tap on any push opens the Inbox screen and refreshes both lists.
- [ ] The badges refresh on start, on resume and after each inbox action, never more than
      once every 10 seconds.

---

## Test accounts

Create your own accounts with Sign up on the development server (any `@example.com` email);
each starts with 100 tokens and 500 gold. Don't use other people's accounts.

A new player's inbox and notifications are always empty, because only the admin console
creates items. To test the Inbox and Claim screens against real data, ask the backend team to
send your test player an inbox message with a reward (and a notification) from the admin
console; the app itself never calls admin routes. Until then, test the screens with the
"from the code" samples above as fixtures.

The real samples in this file came from one account made for it on 24 Nov 2026:

| Username | Email | User id |
|---|---|---|
| `w10doc1795514065` | `w10doc.1795514065@example.com` | `8c3be682-6b86-482d-964f-c2a25d92b0fe` |

State it was left in: one Android device registered (`id` 7) with a test push token; welcome
bonus and today's daily bonus claimed; `promotions` (`marketing_push`) back to `true`, quiet
hours cleared; inbox and notifications empty.
