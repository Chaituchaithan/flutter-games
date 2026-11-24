# Flutter hand-off 2: profile and sessions

The player's own account: the full user object, profile edit, avatar pick, account fields
(username, email, phone), addresses, privacy, game preferences, other players' profiles,
devices and push tokens, signed-in sessions, and deleting the account.

This file is the contract between the Flutter app and the **api-gateway** for these screens.
It is written so a Claude agent can implement it directly. Read `00-conventions.md` first
(errors, lists, times, headers) and `01-auth.md` (sign-in, refresh, log out, change
password). This file links to them instead of repeating them.

**Where the samples come from.** Every reply here was captured from the running gateway on
24 Nov 2026 with fresh test players (see "Test accounts"), tokens blanked, unless it is
marked **(from code)**. Those few are built from the Rust code because a new player can't
reach the state.

---

## For the Claude agent: what to build

1. An `AccountApi` client with one method per route below, on the shared `ApiClient` from
   `00-conventions.md`. Every method returns a typed result or the shared `ApiError`.
2. A `Me` model for `GET /users/me` (see 1) and an `AccountStore` that holds it. Every
   screen in this file reads from it. After any successful write, replace the matching part
   of `Me` with the reply (or re-read `GET /users/me`).
3. Screens:
   - **Profile** (edit): display name, avatar, bio, country, birthday, language, full name,
     gender, timezone, contact channel.
   - **Avatar picker**: the free and owned avatars (see 3).
   - **Account**: username, email, phone. Email and phone ask for the current password.
   - **Addresses**: home and billing, with "Billing same as home".
   - **Privacy**: profile visibility, leaderboards, friend requests, messages, alerts and
     marketing switches.
   - **Game settings**: favourite game, default stake currency, sound, haptics, table chat,
     colour-blind palette, reduced motion.
   - **Player card**: another player's profile (see 8).
   - **Devices**: this install registered on every sign-in, with its push token (see 10).
   - **Signed-in devices** (sessions): the list, "Sign out" per row, "Sign out everywhere"
     (see 11).
   - **Delete account**, behind a password prompt (see 12).
4. Client checks that match the server rules in each table below, so most users never see a
   `400`.
5. Tests: unit tests for the `Me` parser (with the samples here), each error case's mapping
   to a message, the "this device" session match (see 11), and the device registration on
   sign-in and on a new push token.

---

## Endpoints at a glance

All routes need `Authorization: Bearer <access_token>`. Paths are under
`http://<host>:1280/api/v1`. None of them are under `/sensitive/`, so the device check from
`00-conventions.md` doesn't apply.

| What | Method and path | Success |
|---|---|---|
| Current user (full) | `GET /users/me` | `200` |
| Edit profile | `PATCH /users/me/profile` | `200` |
| Edit username, email, phone | `PATCH /users/me` | `200` |
| Delete account | `DELETE /users/me` | `204` |
| What I own (avatars, power-ups) | `GET /users/me/inventory` | `200` |
| One address | `GET /users/me/addresses/{home\|billing}` | `200` |
| Save an address | `PUT /users/me/addresses/{home\|billing}` | `200` |
| Remove an address | `DELETE /users/me/addresses/{home\|billing}` | `204` |
| Privacy | `GET` / `PATCH /users/me/privacy` | `200` |
| Game preferences | `GET` / `PATCH /users/me/preferences` | `200` |
| Another player's profile | `GET /users/{user_id}/profile` | `200` |
| Avatar catalogue | `GET /cosmetics/avatars` | `200` (see `11-store.md`) |
| My devices | `GET /devices` | `200` |
| Register this device | `POST /devices/register` | `201` |
| Set or clear a push token | `PATCH /devices/{id}/push-token` | `200` |
| Remove a device | `DELETE /devices/{id}` | `204` |
| My signed-in sessions | `GET /sessions` | `200` |
| Sign out one session | `DELETE /sessions/{session_id}` | `204` |
| Sign out every session (this one too) | `DELETE /sessions` | `200` |

Covered elsewhere: log out this device and change password (`01-auth.md` 5 and 6a), verify
email (`01-auth.md` 9), buying avatars (`11-store.md`).

There is **no avatar upload**, **no "sign out all other sessions"** route and **no phone
verification** route. See 3, 11 and 4.

---

## 1. The user object

`GET /users/me`. `01-auth.md` 3 covers when to call it and the fields that sign-in needs.
This is the full reply for a player who filled in everything in this file:

```json
{
  "id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c",
  "username": "w02doc1795513371",
  "email": "w02doc.1795513371@example.com",
  "phone": "+919876513371",
  "email_verified_at": "2026-11-24T09:43:26.107865Z",
  "phone_verified_at": null,
  "role": "user",
  "status": "active",
  "created_at": "2026-11-24T09:42:52.077062Z",
  "updated_at": "2026-11-24T09:43:33.141160Z",
  "profile": {
    "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c",
    "display_name": "Wren Doc",
    "avatar_id": 3,
    "avatar_url": "/assets/avatars/default/red.svg",
    "bio": "",
    "country": "IN",
    "date_of_birth": "1998-04-12",
    "preferred_language": "en",
    "updated_at": "2026-11-24T09:43:34.625821Z"
  },
  "full_name": "Wren Doc",
  "avatar_glyph": "W",
  "gender": null,
  "timezone": "Asia/Kolkata",
  "preferred_channel": "push",
  "addresses": {
    "home": {"line1": "12 MG Road", "line2": "Flat 3B", "city": "Bengaluru", "region": "Karnataka", "postal_code": "560001", "country": "IN", "updated_at": "2026-11-24T09:43:34.625821Z"},
    "billing": null,
    "billing_same_as_home": true
  },
  "privacy": {
    "profile_visibility": "friends",
    "show_on_leaderboards": true,
    "allow_friend_requests": true,
    "dm_from": "friends",
    "login_alerts": true,
    "marketing_email": true,
    "marketing_push": true,
    "marketing_sms": true
  },
  "preferences": {
    "favourite_game": null,
    "default_stake_currency": "token",
    "remember_last_stake": false,
    "sound": false,
    "haptics": true,
    "table_chat": true,
    "colour_blind": false,
    "reduce_motion": true
  }
}
```

A brand-new player has `null` in every optional field, `display_name` equal to the
username, `preferred_channel` `"email"`, both addresses `null`, and the defaults below for
privacy and preferences.

| Field | Type | Meaning, and what the app does |
|---|---|---|
| `id` | UUID | The player. |
| `username` | string or `null` | The unique handle (login is by email). Show it as "@handle" on the Account screen. Guests have `guest_xxxxxxxx`. |
| `email` | string or `null` | `null` means a guest (`01-auth.md` 7). |
| `phone` | string or `null` | E.164, for example `+919876543210`. |
| `email_verified_at`, `phone_verified_at` | time or `null` | `null` means not verified. See Known issues 2 and 3. |
| `role` | string | `"user"` for players. Ignore it in the app. |
| `status` | string | `active`, `suspended`, `banned` or `deleted`. A signed-in player is always `active` in practice; a ban shows up as `403 ACCOUNT_BANNED` on sign-in or refresh. |
| `created_at`, `updated_at` | time | "Member since" uses `created_at`. |
| `profile` | object or `null` | The public profile (2). `null` is possible for very old accounts with no profile row; treat it as all fields `null` and the display name equal to the username. |
| `profile.display_name` | string | **The name other players see** at tables, on leaderboards and in chat. Unique across players. |
| `profile.avatar_id`, `profile.avatar_url` | number, string, or `null` | The picked avatar (3). |
| `profile.bio` | string or `null` | Up to 140 characters. |
| `profile.country` | string or `null` | ISO 3166-1 alpha-2, upper case (`IN`, `GB`). |
| `profile.date_of_birth` | `YYYY-MM-DD` or `null` | A date, no time zone. |
| `profile.preferred_language` | string or `null` | A language tag (`en`, `hi`, `pt-BR`). |
| `full_name` | string or `null` | Legal or full name. Private. |
| `avatar_glyph` | string or `null` | 1 or 2 characters drawn in a circle when there is no avatar image. `null`: use the first letter of `display_name`. |
| `gender` | string or `null` | `female`, `male`, `non_binary` or `prefer_not_to_say`. |
| `timezone` | string or `null` | IANA name (`Asia/Kolkata`). |
| `preferred_channel` | string | `email`, `push` or `sms`: where receipts, security alerts and support replies go. |
| `addresses` | object | See 5. |
| `privacy` | object | See 6. |
| `preferences` | object | See 7. |

Only `profile.*` fields are ever shown to other players (see 8). Everything else is private
to the player.

---

## 2. Edit profile

`PATCH /users/me/profile`. Send only the fields that change. A field left out keeps its
value.

```json
{
  "display_name": "Wren Doc",
  "avatar_id": 2,
  "bio": "Ludo on Sundays.",
  "country": "IN",
  "date_of_birth": "1998-04-12",
  "preferred_language": "en",
  "full_name": "Wren Doc",
  "avatar_glyph": "W",
  "timezone": "Asia/Kolkata",
  "gender": "female",
  "preferred_channel": "push"
}
```

**Success:** `200 OK` with the profile and the private profile fields, flat:

```json
{"user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "display_name": "Wren Doc", "avatar_id": 2, "avatar_url": "/assets/avatars/default/green.svg", "bio": "Ludo on Sundays.", "country": "IN", "date_of_birth": "1998-04-12", "preferred_language": "en", "updated_at": "2026-11-24T09:42:58.204876Z", "full_name": "Wren Doc", "avatar_glyph": "W", "gender": "female", "timezone": "Asia/Kolkata", "preferred_channel": "push"}
```

Copy the first nine fields into `Me.profile` and the last five into `Me`. An empty body
`{}` is allowed and changes nothing.

| Field | Rule (server) | Client check |
|---|---|---|
| `display_name` | 1 to 64 characters, unique across players. | Trim; 3 to 20 characters reads best at tables. |
| `avatar_id` | A number of at least 1; a free avatar or one the player owns (3). | Offer only selectable avatars. |
| `bio` | Up to 140 characters. | Counter "n/140". |
| `country` | An ISO 3166-1 alpha-2 code in **upper case**. `in` and `UK` are refused (`GB` is right). Setting it also sets the home address country (5). | Pick from a country list; send the code. |
| `date_of_birth` | `YYYY-MM-DD`. Any other shape is a `400 BAD_REQUEST`. The server accepts future dates (Known issues 4). | A date picker; no future dates. |
| `preferred_language` | 2 to 10 characters. | Pick from the app's languages. |
| `full_name` | 1 to 100 characters; trimmed. | |
| `avatar_glyph` | 1 or 2 characters. | |
| `timezone` | A real IANA zone name. | Send the device's zone (`flutter_timezone`). |
| `gender` | One of the four values. `null` or `""` clears it. | A picker with "Not set". |
| `preferred_channel` | `email`, `push` or `sms`. Anything else is a `400 BAD_REQUEST`. | |

**Clearing a value.** Only `gender` can be cleared (send `null`). For the other fields,
`null` means "leave it". `bio` can be emptied with `""` (it then reads `""`, not `null`);
treat `""` and `null` the same when drawing.

**Errors:**

| Status | `error` | When | Show the user |
|---|---|---|---|
| 409 | `CONFLICT` | The display name is taken. | "That name is taken. Try another." |
| 403 | `FORBIDDEN` | `avatar_id` is premium, locked by level, for sale, or doesn't exist. | "That avatar isn't unlocked yet." Refresh the picker. |
| 400 | `VALIDATION_ERROR` | A field breaks a rule; `field` names it. | The rule, next to that field. |
| 400 | `BAD_REQUEST` | A date in another shape, an unknown `preferred_channel`, a wrong type. | A bug in the app; generic error. |

```json
// 409
{"error": "CONFLICT", "message": "conflict: display name already taken"}

// 403, a premium or missing avatar
{"error": "FORBIDDEN", "message": "forbidden: avatar is not available to this user"}

// 400, field rules
{"error": "VALIDATION_ERROR", "field": "country", "message": "validation error: country: must be an ISO 3166-1 alpha-2 code (e.g. IN)"}
{"error": "VALIDATION_ERROR", "field": "gender", "message": "validation error: gender: must be one of female, male, non_binary, prefer_not_to_say (or empty to clear)"}
{"error": "VALIDATION_ERROR", "field": "timezone", "message": "validation error: timezone: must be an IANA timezone name (e.g. Asia/Kolkata)"}
{"error": "VALIDATION_ERROR", "field": "bio", "message": "validation error: bio: at most 140 characters"}
{"error": "VALIDATION_ERROR", "field": "display_name", "message": "validation error: display_name: must be 1-64 characters"}
{"error": "VALIDATION_ERROR", "field": "preferred_language", "message": "validation error: preferred_language: must be 2-10 characters"}
{"error": "VALIDATION_ERROR", "field": "avatar_glyph", "message": "validation error: avatar_glyph: must be 1-2 characters"}
{"error": "VALIDATION_ERROR", "field": "avatar_id", "message": "validation error: avatar_id: must be at least 1"}

// 400, date not YYYY-MM-DD
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: input contains invalid characters at line 1 column 29"}

// 400, unknown channel
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected one of `email`, `push`, `sms` at line 1 column 26"}
```

The server checks one field at a time and reports the first bad one. Save the whole form in
one request; on a `VALIDATION_ERROR`, mark `field` and keep the user's input.

---

## 3. Avatar

**There is no photo upload.** A player picks an avatar from the catalogue. No route accepts
a file, so there is no "file too big" or "wrong type" case.

**The catalogue:** `GET /cosmetics/avatars` lists every active avatar with `id`, `code`,
`name`, `image_url`, `is_premium`, `is_purchasable`, `required_level` and its price.
`11-store.md` documents that route and buying. **What I own:** `GET /users/me/inventory`
(9).

**Which avatars the player may pick** (the server's rule): an avatar in the player's
inventory, or an active avatar with `is_premium: false`, `is_purchasable: false` and
`required_level: null` (the free ones, for example ids 1 to 8, `default_blue` to
`default_pink`, and one starter per game such as `ludo_red_pawn`). Show the rest locked,
with "Buy" or "Reach level N".

**Pick it:** `PATCH /users/me/profile` with `{"avatar_id": 2}` (see 2). The reply's
`avatar_url` is the new image.

`POST /cosmetics/avatars/{id}/equip` does the same for an avatar the player owns or a free
one:

```json
// 200
{"avatar_id": 3, "equipped": true}

// 400, a premium avatar the player doesn't own
{"error": "BAD_REQUEST", "message": "bad request: you do not own this avatar"}
```

Use the profile route in the picker; it returns the whole profile. Use equip right after a
purchase in the store, if that flow needs it.

**Drawing an avatar.** `avatar_url` is a **relative path** such as
`/assets/avatars/default/red.svg`, and **nothing serves it today**: the gateway answers
`404` for `http://<host>:1280/assets/avatars/default/red.svg` and the files are not in the
repository (Known issues 1). Until a host exists:

1. Ship the avatar images in the app, keyed by the catalogue `code` (`default_red`,
   `ludo_red_pawn`, ...). Map `avatar_id` to `code` from `GET /cosmetics/avatars` (cache
   it).
2. If the code isn't bundled, draw a circle with `avatar_glyph`, or the first letter of
   `display_name`.
3. Keep a setting for an asset base URL; when one exists, load `<base><avatar_url>` with
   the glyph as the placeholder and fallback.

---

## 4. Edit username, email, phone

`PATCH /users/me`. Send only the fields that change.

```json
{ "username": "wren_doc" }
```

```json
{ "email": "new.address@example.com", "current_password": "Passw0rd!x" }
```

```json
{ "phone": "+919876543210", "current_password": "Passw0rd!x" }
```

| Field | Rule |
|---|---|
| `username` | 3 to 32 characters, unique. The server checks only the length today (Known issues 5); the app must allow only letters, digits and `_`, as at sign-up. |
| `email` | A valid email, unique. Needs `current_password`. Letter case alone is not a change. |
| `phone` | E.164: `+`, then 2 to 15 digits, not starting with 0, no spaces. Unique. Needs `current_password`. A new number clears `phone_verified_at`. |
| `current_password` | Required when `email` or `phone` changes. |

**Success:** `200 OK` with the account part of the user object (no `profile` and no
settings). Merge it into `Me`.

```json
{"id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "username": "w02doc1795513371", "email": "nw02doc.1795513371@example.com", "phone": null, "email_verified_at": "2026-11-24T09:43:26.107865Z", "phone_verified_at": null, "role": "user", "status": "active", "created_at": "2026-11-24T09:42:52.077062Z", "updated_at": "2026-11-24T09:43:30.474324Z"}
```

- A new email is the new login email at once. Sessions stay signed in.
- The username is not the display name: changing one doesn't change the other.
- **Guests** have no password, so they can't set an email or phone here; use "Save your
  progress" (`01-auth.md` 7b).
- There is no route to verify a phone number yet. Show the phone as "Not verified" while
  `phone_verified_at` is `null`, and don't offer a Verify button.

**Errors:**

| Status | `error` | When | Show the user |
|---|---|---|---|
| 409 | `CONFLICT` | The username, email or phone is taken (the reply doesn't say which; it is the one you changed). | "That username is taken." / "That email is already registered." / "That number is already in use." |
| 401 | `INVALID_CREDENTIALS` | Wrong `current_password`. **Not** a session problem: don't refresh or sign out. | "Your password is incorrect." |
| 400 | `BAD_REQUEST` | No `current_password` with a new email or phone (`field` is `current_password`); or the account has no password (a guest). | Ask for the password. |
| 400 | `VALIDATION_ERROR` | `username` length, an invalid `email`, a `phone` not in E.164. | Field error. |

```json
// 400, no password sent
{"error": "BAD_REQUEST", "field": "current_password", "message": "bad request: current_password is required"}

// 401
{"error": "INVALID_CREDENTIALS", "message": "invalid credentials"}

// 409
{"error": "CONFLICT", "message": "conflict: username, email or phone already taken"}

// 400
{"error": "VALIDATION_ERROR", "field": "username", "message": "validation error: username: must be 3-32 characters"}
{"error": "VALIDATION_ERROR", "field": "email", "message": "validation error: email: must be a valid email address"}
{"error": "VALIDATION_ERROR", "field": "phone", "message": "validation error: phone: must be in E.164 form, e.g. +919876543210"}

// 400, a guest (from code)
{"error": "BAD_REQUEST", "message": "bad request: this account has no password; set one first"}
```

The interceptor must not treat this `401 INVALID_CREDENTIALS` as an ended session (see
`01-auth.md` 4).

---

## 5. Addresses

Two addresses: `home` and `billing`. No billing address means "same as home". The app needs
them only where a payment or prize flow asks for one; keep the screen simple.

**Read one:** `GET /users/me/addresses/home` (or `billing`).

```json
{"line1": "1 Main St", "line2": null, "city": "Pune", "region": null, "postal_code": "411001", "country": "IN", "updated_at": "2026-11-24T09:43:37.624810Z"}
```

- `404 NOT_FOUND` (`not found: no billing address`) when none is stored.
- A home address can hold **only a country**: setting `country` on the profile (2) creates
  the home row with every other field `null`:

```json
{"line1": null, "line2": null, "city": null, "region": null, "postal_code": null, "country": "IN", "updated_at": "2026-11-24T09:42:58.204876Z"}
```

Treat a home address with `line1: null` as "not filled in".

`GET /users/me` already carries both (`addresses.home`, `addresses.billing`,
`addresses.billing_same_as_home`), so the screen usually needs no separate read.

**Save:** `PUT /users/me/addresses/home` (or `billing`). The whole address each time:

```json
{"line1": "12 MG Road", "line2": "Flat 3B", "city": "Bengaluru", "region": "Karnataka", "postal_code": "560001", "country": "IN"}
```

**Success:** `200 OK` with the saved address (same shape as the read).

| Field | Rule |
|---|---|
| `line1` | Required, 1 to 200 characters. |
| `line2` | Optional, up to 200. |
| `city` | Required, 1 to 100. |
| `region` | Optional, up to 100 (state or region). |
| `postal_code` | Required, 3 to 10 letters, digits, spaces or hyphens. |
| `country` | Required, ISO alpha-2 upper case. A **home** address also sets the profile country. |

**Remove:** `DELETE /users/me/addresses/billing` answers `204`, then billing is "same as
home". A second delete is `404`.

**Errors:**

```json
// 400
{"error": "VALIDATION_ERROR", "field": "postal_code", "message": "validation error: postal_code: must be 3-10 letters, digits, spaces or hyphens"}
{"error": "VALIDATION_ERROR", "field": "country", "message": "validation error: country: must be an ISO 3166-1 alpha-2 code (e.g. IN)"}

// 400, a required field missing
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: missing field `city` at line 1 column 59"}

// 400, a kind other than home or billing
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: unknown variant, expected `home` or `billing`"}

// 404
{"error": "NOT_FOUND", "message": "not found: no billing address"}
```

---

## 6. Privacy

`GET /users/me/privacy`, and `PATCH /users/me/privacy` with only the fields that change.

```json
{"profile_visibility": "friends", "marketing_sms": true, "dm_from": "friends"}
```

**Success** (both): `200 OK` with all eight fields:

```json
{"profile_visibility": "friends", "show_on_leaderboards": true, "allow_friend_requests": true, "dm_from": "friends", "login_alerts": true, "marketing_email": true, "marketing_push": true, "marketing_sms": true}
```

| Field | Values (default first) | What it does today |
|---|---|---|
| `profile_visibility` | `public`, `friends`, `private` | **Enforced.** Who sees the full profile (8). |
| `show_on_leaderboards` | `true`, `false` | **Enforced.** `false` hides the player from leaderboards. |
| `allow_friend_requests` | `true`, `false` | Stored only. Friend requests still arrive (Known issues 6). |
| `dm_from` | `everyone`, `friends`, `nobody` | Stored only (decision D-59). |
| `login_alerts` | `true`, `false` | Stored only; no alert is sent yet. |
| `marketing_email` | `true`, `false` | Read by marketing sends. |
| `marketing_push` | `true`, `false` | Read by marketing sends. |
| `marketing_sms` | `false`, `true` | Read by marketing sends. |

Show each switch, and save each change at once (optimistic, roll back on error). For the
"stored only" rows, don't promise more than "We'll use this setting".

An unknown value is a `400 BAD_REQUEST`:

```json
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected one of `public`, `friends`, `private` at line 1 column 30"}
```

---

## 7. Game preferences

`GET /users/me/preferences`, and `PATCH /users/me/preferences` with only the fields that
change.

```json
{"favourite_game": "ludo", "default_stake_currency": "tokens", "sound": false, "reduce_motion": true}
```

**Success** (both): `200 OK` with all eight fields:

```json
{"favourite_game": "ludo", "default_stake_currency": "token", "remember_last_stake": false, "sound": false, "haptics": true, "table_chat": true, "colour_blind": false, "reduce_motion": true}
```

| Field | Values (default) | Use in the app |
|---|---|---|
| `favourite_game` | A game `code` from `GET /games` (`04-game-catalogue.md`), or `null` (default). Send `null` to clear. | Put that game first in the lobby. |
| `default_stake_currency` | `gold` (default) or `token`. `tokens` is accepted on input; the reply always says `token`. | Pre-select it on stake pickers. |
| `remember_last_stake` | `false` | Pre-select the last stake in Create room. |
| `sound` | `true` | Table and win sounds. |
| `haptics` | `true` | Vibration on moves. |
| `table_chat` | `true` | Show table chat and emotes. |
| `colour_blind` | `false` | High-contrast palette. |
| `reduce_motion` | `false` | Shorter animations. Default it from the OS setting on first run, then save. |

These are applied **on the device**; the server only stores them so they follow the player
to a new phone. Read them after sign-in and apply them before the first game.

```json
// 400, not an active game code
{"error": "VALIDATION_ERROR", "field": "favourite_game", "message": "validation error: favourite_game: must be the code of an active game"}

// 400, wrong type
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: invalid type: string, expected a boolean at line 1 column 14"}
```

---

## 8. Another player's profile

`GET /users/{user_id}/profile`. Use it for the player card opened from a table, a
leaderboard or the friends list.

```json
{"user_id": "f72cb92d-7a0e-4361-9d78-d377d8103351", "display_name": "w02docb1795513371", "avatar_id": null, "avatar_url": null, "bio": "Snakes only.", "country": "GB", "date_of_birth": null, "preferred_language": "en", "updated_at": "2026-11-24T09:44:46.169882Z"}
```

What the viewer gets depends on the owner's `profile_visibility`:

| Owner's setting | Viewer | Gets |
|---|---|---|
| `public` | anyone | Everything except `date_of_birth` (always `null` for others). |
| `friends` | a friend | Same as public. |
| `friends` | not a friend | Name and avatar only: `bio`, `country`, `date_of_birth`, `preferred_language` are `null`. |
| `private` | anyone else | Name and avatar only. |
| any | the owner | Everything, birthday included. |

The same player, set to `private`, seen by another player:

```json
{"user_id": "f72cb92d-7a0e-4361-9d78-d377d8103351", "display_name": "w02docb1795513371", "avatar_id": null, "avatar_url": null, "bio": null, "country": null, "date_of_birth": null, "preferred_language": null, "updated_at": "2026-11-24T09:44:46.169882Z"}
```

The reply doesn't say it was trimmed. Draw missing fields as hidden, not as errors.

```json
// 404, no such player
{"error": "NOT_FOUND", "message": "not found: profile not found"}
```

A deleted account still answers, with a display name like `deleted-2e173b92a9bb4bbcb5d8f621`
and no avatar **(from code)**. Show it as "Deleted player".

---

## 9. What I own

`GET /users/me/inventory`

```json
{"power_ups": [], "avatars": []}
```

With items **(from code)**:

```json
{
  "power_ups": [{"power_up_id": 4, "code": "shield", "name": "Shield", "game_id": 1, "quantity": 2}],
  "avatars": [{"avatar_id": 15, "code": "ludo_golden_crown", "image_url": "/assets/avatars/ludo/golden_crown.svg", "unlocked_at": "2026-11-24T09:50:00Z", "source": "purchase"}]
}
```

`avatars` are newest first; `source` is how it was unlocked (`purchase`, `level`, `grant`,
...). Only power-ups with `quantity` above 0 are listed. Use `avatars` to mark owned items
in the avatar picker (3). The store hand-off covers power-ups.

---

## 10. Devices and push tokens

A **device** is one install of the app on one phone. The gateway keeps a list per player,
uses it for push notifications, and the welcome bonus uses it to stop one phone claiming
twice (`07-rewards.md` 1b).

### 10a. Register this device

`POST /devices/register`

```json
{"device_id": "3f6c2a9e-8d1b-4c55-9a77-0b2e5d4f1a10", "device_name": "Pixel 8", "platform": "android", "push_token": "<FCM token>"}
```

| Field | Rule |
|---|---|
| `device_id` | Required, 1 to 120 characters. The install's stable id: the **same UUID** the app sends as `device_id` at sign-up (`01-auth.md` 1), generated once and kept in secure storage. |
| `device_name` | Required, 1 to 80 characters. The model the user recognises ("Pixel 8", "iPhone 15"), from `device_info_plus`. |
| `platform` | Required: `ios`, `android` or `web`. |
| `push_token` | Optional, 1 to 255 characters. The FCM token (Android, web) or APNs token (iOS). |

**Success:** `201 Created`, also when the device was already registered (it is updated,
not duplicated):

```json
{"id": 2, "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "device_id": "w02-dev-1795513371-a", "device_name": "Pixel 8", "platform": "android", "push_token": "fcm-w02-1795513371-a1", "last_active_at": "2026-11-24T09:43:48.883567Z", "created_at": "2026-11-24T09:43:48.883567Z"}
```

Store `id` (a number): the push-token and remove routes use it, not `device_id`.

**When to call it:** after every sign-in, sign-up, guest create and guest convert, once
the push permission is settled. Signing up with `device_id` does **not** register the
device; this call does.

**Always send the current push token.** Registering again **without** `push_token` clears
the stored token:

```json
// the same device registered again with no push_token
{"id": 2, "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "device_id": "w02-dev-1795513371-a", "device_name": "Pixel 8", "platform": "android", "push_token": null, "last_active_at": "2026-11-24T09:43:49.650379Z", "created_at": "2026-11-24T09:43:48.883567Z"}
```

Leave `push_token` out only when the user denied notifications.

**Errors:**

```json
// 400, unknown platform
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected one of `ios`, `android`, `web` at line 1 column 78"}

// 400, empty name or empty push token
{"error": "VALIDATION_ERROR", "field": "device_name", "message": "validation error: device_name: must be 1 to 80 characters"}
{"error": "VALIDATION_ERROR", "field": "push_token", "message": "validation error: push_token: must be 1 to 255 characters"}
```

Missing required fields are a `400 BAD_REQUEST`. All of these are app bugs: log them (without
the token) and go on; never block sign-in on a failed device registration.

### 10b. Set or clear the push token

`PATCH /devices/{id}/push-token` with the `id` from 10a.

```json
{ "push_token": "<new FCM or APNs token>" }
```

Send `{"push_token": null}` to stop pushes to this device (the user turned notifications
off in the app).

**Success:** `200 OK` with the device (same shape as 10a):

```json
{"id": 2, "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "device_id": "w02-dev-1795513371-a", "device_name": "Pixel 8", "platform": "android", "push_token": "fcm-w02-1795513371-a2", "last_active_at": "2026-11-24T09:43:53.403914Z", "created_at": "2026-11-24T09:43:48.883567Z"}
```

Call it from Firebase Messaging's `onTokenRefresh`. If the stored `id` is unknown (`404`),
register again with 10a.

```json
// 404, not this player's device, or removed
{"error": "NOT_FOUND", "message": "not found: device not found"}
```

A push token is unique across all players: if the same phone signs in as another player, the
token moves to that player's device. Receiving and showing pushes is in
`10-inbox-and-notifications.md`.

### 10c. List and remove

`GET /devices`: a plain array, most recently seen first.

```json
[
  {"id": 2, "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "device_id": "w02-dev-1795513371-a", "device_name": "Pixel 8", "platform": "android", "push_token": null, "last_active_at": "2026-11-24T09:43:54.164246Z", "created_at": "2026-11-24T09:43:48.883567Z"},
  {"id": 4, "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "device_id": "w02-dev-1795513371-b", "device_name": "iPhone 15", "platform": "ios", "push_token": "apns-w02-1795513371-b1", "last_active_at": "2026-11-24T09:43:50.400246Z", "created_at": "2026-11-24T09:43:50.400246Z"}
]
```

`last_active_at` moves only on register and push-token calls, not on every request.

`DELETE /devices/{id}`: `204`, empty body. Its push token goes with it. Another player's
device, or one already removed, is `404 NOT_FOUND`. A word for the id is
`400 BAD_REQUEST` (`can not parse to a i64`).

Removing a device **does not sign it out**. To sign a phone out, use sessions (11). On log
out (`01-auth.md` 5), first clear this device's push token (10b with `null`) so the next
player on the phone doesn't get pushes; if that call fails, log out anyway.

Show the device list only if the design asks for it; the sessions list (11) is the "where
am I signed in" screen.

---

## 11. Sessions (signed-in devices)

A **session** starts at each sign-in (password, email code, sign-up, guest create) and lasts
until log out, a sign-out from this screen, a password change, or 7 days without a refresh.
Refreshing tokens keeps the same session.

### 11a. List

`GET /sessions`: a plain array, most recently **refreshed** first.

```json
[
  {"session_id": "10a121c5-d359-42db-9649-a6c5d5035a6b", "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "ip_address": "127.0.0.1", "user_agent": "RoyaleArcade/1.0.0 (iOS 18.1)", "created_at": 1795513375, "last_active_at": 1795513375},
  {"session_id": "d69c6a5b-6b41-46c7-b6d5-89cd78dcf115", "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "ip_address": "127.0.0.1", "user_agent": "RoyaleArcade/1.0.0 (Android 14)", "created_at": 1795513374, "last_active_at": 1795513374},
  {"session_id": "08eaff6b-7269-4d3d-bc75-815b39d8c147", "user_id": "2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c", "ip_address": "127.0.0.1", "user_agent": "RoyaleArcade/1.0.0 (Android 14)", "created_at": 1795513372, "last_active_at": 1795513372}
]
```

| Field | Meaning |
|---|---|
| `session_id` | UUID; the id for 11b. |
| `ip_address` | The network address at sign-in. Show it small, or not at all. |
| `user_agent` | The `User-Agent` sent at sign-in. This is why every install must send a readable one (`00-conventions.md`): show it as the device name, for example "Android 14" from `RoyaleArcade/1.0.0 (Android 14)`. |
| `created_at` | **Epoch seconds** (not ISO, unlike the rest of the gateway). "Signed in at". |
| `last_active_at` | **Epoch seconds**. Moves on sign-in and on each token refresh only, so it can be up to 15 minutes old for a phone in use. Show "Active about ..." with that in mind. |

**Which row is this phone.** The list doesn't mark the current session (Known issues 7).
The access token carries it: the JWT payload has a `session_id` claim, and it stays the same
across refreshes. This is the one place the app reads the token: base64url-decode the middle
part of the stored access token, read `session_id`, and mark the row with that id as "This
device". Don't use the payload for anything else. If decoding fails, mark no row.

Two sessions from the same phone are normal (signed in twice without logging out); both
show the same `user_agent`.

### 11b. Sign out one session

`DELETE /sessions/{session_id}`: `204`, empty body. That session's access token gets
`401 TOKEN_BLACKLISTED` at once and its refresh token stops working, so that phone lands on
the sign-in screen at its next request.

```json
// the signed-out phone's next request
{"error": "TOKEN_BLACKLISTED", "message": "token blacklisted"}

// 404, not this player's session, or already gone: drop the row and re-read the list
{"error": "NOT_FOUND", "message": "not found: session not found"}

// 400, not a UUID
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: UUID parsing failed: invalid length: found 3"}
```

Hide "Sign out" on the "This device" row; this phone uses Log out (`01-auth.md` 5). If it is
signed out by id anyway, treat it as a log out.

### 11c. Sign out everywhere

`DELETE /sessions` signs out **every** session of the player, **including this one**:

```json
{"revoked": 2}
```

After it, this phone's token also gets `401 TOKEN_BLACKLISTED`. Clear the `TokenStore` and go
to `signedOut`, as for a log out. Label the button "Sign out everywhere", and confirm first:
"This signs you out on every device, including this one."

**"Sign out all other devices"** has no route. If the design needs it, call 11b for every row
except "This device", one at a time, then re-read the list. Don't do this when "This device"
is unknown (11a); offer "Sign out everywhere" instead.

---

## 12. Delete account

`DELETE /users/me` with a JSON body (most HTTP clients need it set explicitly on a DELETE):

```json
{ "password": "Passw0rd!x" }
```

**Success:** `204 No Content`, empty body. Then:

- every session is signed out (this phone's token now gets `401 TOKEN_BLACKLISTED`);
- signing in with the old email and password answers `401 INVALID_CREDENTIALS`;
- the email and username are freed: a new sign-up with them creates a **new, empty** account;
- the profile is blanked (display name `deleted-...`, no avatar, country, birthday or
  bio), and addresses, devices, push tokens and linked sign-ins are removed **(from code)**;
- wallet, ledger and match history are kept for finance records, under the anonymous
  account. Nothing is refunded or paid out by deleting.

The app: clear the `TokenStore` and every cached player data, and go to the Welcome screen
with "Your account has been deleted."

Before calling it, show a screen that says what is lost (balance, progress, purchases, with
the current balances from `03-wallet.md`), and ask for the password.

**Errors:**

| Status | `error` | When | Show the user |
|---|---|---|---|
| 401 | `INVALID_CREDENTIALS` | Wrong password. Not a session problem. | "Your password is incorrect." |
| 409 | `CONFLICT` | The player is in a match, a game room, or a tournament that hasn't ended. | "Finish or leave your current game or tournament first." |
| 400 | `VALIDATION_ERROR` | Empty password. | Field error. |
| 400 | `BAD_REQUEST` | No body; or a guest (no password). | For guests see below. |

```json
// 401
{"error": "INVALID_CREDENTIALS", "message": "invalid credentials"}

// 400, empty password
{"error": "VALIDATION_ERROR", "field": "password", "message": "validation error: password: cannot be empty"}

// 400, no body
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: EOF while parsing a value at line 1 column 0"}

// 400, a guest
{"error": "BAD_REQUEST", "message": "bad request: this account has no password; set one first"}

// 409 (from code); the message names every open seat
{"error": "CONFLICT", "message": "conflict: finish or leave a match and a tournament before deleting the account"}
```

**Guests can't delete their account** (no password). Hide "Delete account" for guests;
"Log out" already ends a guest's account in practice (`01-auth.md` 5). See Known issues 8.

---

## Errors

Every error has the shared body from `00-conventions.md`. Decide on the status, `error` and
`field`, never on `message`.

Common to every route here:

| Status | `error` | Meaning |
|---|---|---|
| 401 | `UNAUTHORIZED` | No or expired token; the interceptor from `01-auth.md` refreshes once. |
| 401 | `TOKEN_BLACKLISTED` | This session was signed out (11b, 11c, 12, or a password change). Go to `signedOut`. |
| 401 | `INVALID_CREDENTIALS` | Only on 4 and 12: a wrong password. Not a session problem. |
| 429 | `RATE_LIMITED` | About 100 requests a minute per player. Wait and retry once. |
| 500 | `DATABASE_ERROR`, `INTERNAL_ERROR`, `CACHE_ERROR` | "Something went wrong. Try again." |

```json
// 401, no token
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}
```

---

## Known issues the app must cope with

1. **Avatar images aren't served.** `avatar_url` is a relative path (`/assets/avatars/...`)
   that no server answers, and the image files aren't in the repository. Bundle the images by
   `code` and fall back to the glyph (3).
2. **A new email keeps the old verification.** After `PATCH /users/me` changes the email,
   `email_verified_at` still holds the time the **old** email was verified (seen live). Until
   that is fixed, don't treat `email_verified_at` as proof the current email works; after an
   email change, offer "Verify email" (`01-auth.md` 9) anyway.
3. **No phone verification.** A phone can be saved but never verified; `phone_verified_at`
   stays `null`.
4. **Birthdays in the future are accepted.** Check on the device (no future dates; apply any
   minimum age the product sets).
5. **Usernames aren't checked for characters on edit.** `PATCH /users/me` accepted
   `"w02 doc!"` (a space and `!`). Allow only letters, digits and `_` in the app, as at
   sign-up.
6. **`allow_friend_requests`, `dm_from` and `login_alerts` are stored but not acted on.** A
   player who turned off friend requests can still receive them.
7. **The session list doesn't mark the current session,** and there is no "sign out all
   other sessions" route. Use the `session_id` claim (11a) and per-session sign-out (11c).
8. **Guests can't delete their account** (the route needs a password).
9. **Session times are epoch seconds**, while every other time in this file is ISO 8601.
10. **Only `gender` can be cleared** on the profile; the other fields keep their value when
    sent `null`. `bio` can be set to `""`.

---

## Done when

- [ ] After sign-in, `GET /users/me` fills the `Me` model; the profile, account, privacy and
      game settings screens show its values with no extra reads.
- [ ] Editing the profile saves in one request and updates the screen from the reply; a
      taken display name shows "That name is taken"; a bad field shows the rule next to it.
- [ ] The avatar picker shows free and owned avatars as selectable and the rest locked;
      picking one updates the avatar everywhere; a missing image falls back to the glyph.
- [ ] Changing username works; changing email or phone asks for the password, and a wrong
      password shows an error without signing the user out.
- [ ] Home and billing addresses save, "Billing same as home" removes the billing address,
      and a country-only home address shows as not filled in.
- [ ] Privacy switches save one by one; `private` hides bio and country on the player card
      as another player sees it.
- [ ] Game preferences are applied on the device after sign-in and follow the player to a
      second phone.
- [ ] The device is registered with its push token after every sign-in and on token
      refresh; log out clears the push token first.
- [ ] The sessions screen lists every sign-in with a readable device name, marks "This
      device", signs out one other session (that phone is sent to sign-in), and "Sign out
      everywhere" signs this phone out too.
- [ ] Delete account asks for the password, explains what is lost, shows the "finish your
      game first" message on `409`, and after success the old login fails and the app is on
      the Welcome screen. Guests don't see it.
- [ ] No password, token or push token appears in any log.

---

## Test accounts

Create your own players on the development server with `POST /auth/register` (any
`@example.com` email), as in `01-auth.md`. To get two sessions, log the same player in twice
with different `User-Agent` values. Test account deletion only on a player you created. Don't
use other people's accounts.

The samples here came from players `w02doc1795513371` (A, two sessions),
`w02docb1795513371` (B, the other player for profile views) and `w02docc1795513371` (C,
deleted; a new account with the same username and email was then signed up to show both
were freed), and one guest, made for this file on 24 Nov 2026.
