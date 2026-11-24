# Flutter hand-off 12: safety

Reporting a player, my reports, flagging a match, how the app learns that a player is banned,
muted or restricted, responsible-gaming limits, and region and age gates.

This file is the contract between the Flutter app and the **api-gateway** for player safety.
It is written so a Claude agent can implement it directly. Read `00-conventions.md` first: the
error body, list shapes, ids and times are defined there and not repeated here. Sessions, the
auth interceptor and the sign-in ban message come from `01-auth.md`. Blocks are in
`09-social.md` (section 6), match history in `08-progress-and-history.md`, tournament
refusals in `06-tournaments.md`.

**Where the samples come from.** Replies marked **(live)** were captured from the running
gateway and the Ludo socket on 24 Nov 2026, with three fresh test players (A, B and C). A and B
played one free Ludo game (A forfeited), then A reported B, C reported A, and A and B flagged
the game. Replies marked **(from code)** were not captured; their shape is read from the
gateway source. **No ban reply is live:** test players can't ban anyone, and admin routes were
not used. Every ban, mute, geo and limit reply below is from code.

**Read this first: what the backend does and does not have.**

| Wanted | State today |
|---|---|
| Report a player, with a chat line as evidence | Yes: `POST /moderation/report`. |
| Report with a match id as evidence | **No.** A `match_id` field is ignored (live). Flag the match instead, or put it in `description`. |
| Report an in-game (socket) chat line | **No.** Socket chat lines have no id the report can name. Quote it in `description`. |
| Duplicate-report protection | **None.** The same report twice makes two reports (live). The app must stop repeats. |
| My reports and their status | Yes: `GET /moderation/my-reports` (plain array, no paging). |
| "Your report was reviewed" notice | **None** (from code). Re-read the list when the screen opens. |
| Am I banned? | `GET /moderation/bans/check`, plus `403 ACCOUNT_BANNED` at sign-in. |
| Am I muted? | **No route.** A mute shows only as `403 FORBIDDEN` when sending chat. |
| Flag a match | Yes: `POST /matches/{id}/flag`, participants only. No list of my flags. |
| Responsible-gaming limits set by the player | **No player route** (live: every guess answered 404). Staff set them in the console. |
| Age gate | **None enforced.** `date_of_birth` is an optional profile field. |
| Region gate | Yes: `403 GEO_BLOCKED` on any gateway route and on the socket handshake. |

---

## For the Claude agent: what to build

1. A `SafetyApi` on the shared `ApiClient` with: `report(...)`, `myReports()`,
   `checkBan()`, `flagMatch(matchId, reason)`.
2. Models: `Report` (+ `ChatEvidence`), `ReportReason` and `ReportStatus` enums with an
   `unknown` fallback, `BanCheck`, `Ban` (+ `BanScope` enum with `unknown`), `MatchFlag`.
3. An `AccountStanding` service that holds the current `BanCheck`. It reads
   `GET /moderation/bans/check` after sign-in, on app resume (at most once a minute), and
   after any `403 FORBIDDEN` from chat or tournaments. Screens read it to show banners and
   to disable buttons (see "Restrictions" below).
4. A global handler in the auth interceptor: `403 ACCOUNT_BANNED` and `403 GEO_BLOCKED` from
   **any** route go to a full-screen state (see section 4 and 6). Never retry them.
5. A `ReportedTracker` (local, per account, kept on the device): which players and which chat
   lines this account has already reported, and which matches it flagged. The server does
   not stop repeats.
6. Screens:
   - **Report player** sheet, opened from a player card, a chat line (long-press), the match
     result screen and the match detail screen. Reason chips, an optional text box (up to
     2000 characters), a "Include this message" line when opened from a chat line, Send.
   - **My reports** in Settings > Safety: newest first, each with the player, reason, date
     and a status chip.
   - **Report a problem with this match** on the match result and match detail screens
     (participants only): a text box (5 to 500 characters) and Send.
   - **Account restricted** full screen (ban at sign-in or during a session), and a smaller
     **restriction banner** for chat, tournament and play restrictions.
   - **Not available in your region** full screen.
   - **Responsible gaming** info page in Settings: what the limits are and "Contact support
     to set or change a limit" (no self-service yet).
7. Tests: parsing every real reply here; the error mapping for each route; that a second
   report of the same player in the same session is blocked on the device; that
   `ACCOUNT_BANNED` from any route signs the player out and shows `until` in local time; that
   unknown `scope`, `reason` and `status` values don't crash.

Never log report bodies or descriptions (they can hold other players' words), even in debug
builds.

---

## Endpoints at a glance

All paths are under `http://<host>:1280/api/v1`. All need `Authorization: Bearer
<access_token>`; without it every route answers `401 UNAUTHORIZED` (live). None is under
`/sensitive/`.

| Area | Method and path | Success |
|---|---|---|
| Report | `POST /moderation/report` | `201` + report |
| | `GET /moderation/my-reports` | `200` + plain array, newest first |
| Ban check | `GET /moderation/bans/check` | `200` `{"is_banned": bool, "ban": {...} or null}` |
| Match flag | `POST /matches/{id}/flag` | `201` + flag |

Related: `POST /blocks/{user_id}` (`09-social.md`) hides a player for the reporter; offer
"Also block this player" after a report. `GET /matches/my-history` and `GET /matches/{id}`
(`08-progress-and-history.md`) give the match ids to flag.

**What staff do that the app sees.** From the admin console, staff review reports (the
report's `status` changes), issue bans (whole account, chat, matchmaking or tournaments,
timed or permanent), mute chat for a time, set a player's responsible-gaming limits, and set
region rules. The app never calls the admin routes; it sees only the effects described here.

---

## 1. Report a player

`POST /moderation/report`

```json
{
  "reported_user_id": "42dcdefc-d372-4668-be6d-ac16c96284a2",
  "reason": "abuse",
  "description": "Insult in match chat",
  "chat_message": {
    "room_type": "match",
    "room_id": "82e6509c-1bc9-43c6-8941-e2f3b4fc1c51",
    "message_id": "1795514318726-0"
  }
}
```

| Field | Required | Rule |
|---|---|---|
| `reported_user_id` | yes | The player's UUID. Not yourself. |
| `reason` | yes | One of `cheating`, `abuse`, `spam`, `inappropriate_content`, `harassment`, `other`. |
| `description` | no | Up to 2000 characters. An empty string is accepted and stored as `""` (live); leave it out instead. |
| `chat_message` | no | A gateway chat line (`09-social.md`, section 3) sent **by the reported player**. `room_type` is `match`, `lobby` or `global`; `room_id` 1 to 64 characters; `message_id` is the line's `id` from chat history (`1795514318726-0`). |

Suggested reason labels: Cheating, Abusive language (`abuse`), Spam, Inappropriate name or
picture (`inappropriate_content`), Harassment, Something else (`other`).

**Success:** `201`. Live, with a chat line (A reports B for a line in their match chat):

```json
{
  "id": 5,
  "reporter_id": "b327ea3e-b571-487d-9967-431e7e19df5b",
  "reported_user_id": "42dcdefc-d372-4668-be6d-ac16c96284a2",
  "reason": "abuse",
  "description": "Insult in match chat",
  "status": "pending",
  "reviewed_by": null,
  "chat_message_ref": "1795514318726-0",
  "evidence": {
    "chat_message": {
      "body": "you are bad at this",
      "created_at": "2026-11-24T09:58:38.727Z",
      "id": "1795514318726-0",
      "room_id": "82e6509c-1bc9-43c6-8941-e2f3b4fc1c51",
      "room_type": "match",
      "sender_user_id": "42dcdefc-d372-4668-be6d-ac16c96284a2"
    }
  },
  "created_at": "2026-11-24T09:58:40.883420Z",
  "reported_username": "w12docb1795514294",
  "reported_avatar_url": null
}
```

Live, without a chat line (`evidence` is `{}`):

```json
{"id": 3, "reporter_id": "b327ea3e-b571-487d-9967-431e7e19df5b",
 "reported_user_id": "42dcdefc-d372-4668-be6d-ac16c96284a2", "reason": "cheating",
 "description": null, "status": "pending", "reviewed_by": null, "chat_message_ref": null,
 "evidence": {}, "created_at": "2026-11-24T09:58:37.288831Z",
 "reported_username": "w12docb1795514294", "reported_avatar_url": null}
```

| Field | Meaning |
|---|---|
| `id` | The report id (a number). |
| `reporter_id` | You. |
| `reported_user_id` | The reported player; `null` if that account was later removed. |
| `reason`, `description` | As sent. |
| `status` | `pending` (new), `reviewed` (staff looked), `actiontaken` (staff acted), `dismissed` (no action). See section 2. |
| `reviewed_by` | A staff number, or `null`. Don't show it. |
| `chat_message_ref`, `evidence.chat_message` | The reported line, copied when the report was made, so it survives chat trimming. |
| `reported_username`, `reported_avatar_url` | The reported player's name and avatar (avatar may be `null`). |

**Evidence: what can be attached**

| Evidence | How |
|---|---|
| A gateway chat line (lobby, global, match chat over HTTP) | `chat_message` as above. The server checks it (live): the line must be in that room, sent by the reported player, and the reporter must be allowed to read the room (match chat: participants only). |
| A match | **Not attachable.** A `match_id` field is accepted and silently dropped (live: `evidence` stayed `{}`). Use the match flag (section 3) for the game itself, and put "Match <id>" at the start of `description`. |
| An in-game socket chat line | **Not attachable.** Socket chat lines (`chat.message` frames) have no id and are stored apart from gateway chat. In Ludo they are fixed quick-chat lines only (live: free text answered `chat.send_error` `invalid_request` "only predefined chat messages are allowed"). Quote the line in `description`. |
| Screenshots or files | **Not supported.** |

**What the app does with it**

- On `201`: close the sheet, show "Thanks. Our team will review your report." Add the player
  (and the chat line, if any) to `ReportedTracker`. Then offer "Also block <name>?"
  (`POST /blocks/{user_id}`, `09-social.md`). Optionally hide that chat line locally at once.
- Before sending: if `ReportedTracker` already has this player for this account in the last
  24 hours, or already has this chat line, show "You've already reported this" and don't
  send. The server would accept it again (see "Known issues").
- Never offer Report on the player's own card or own chat lines.
- The reported player is not told (from code: nothing is sent to them).

**Errors** (all live unless marked)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `BAD_REQUEST` | Reporting yourself. | Never offer it. |
| 404 | `NOT_FOUND` | No such player. | "Player not found." |
| 400 | `BAD_REQUEST` | `reason` missing or not in the list; `reported_user_id` missing or not a UUID; `room_type` not `match`/`lobby`/`global`. | App bug; log the code, not the body. |
| 400 | `VALIDATION_ERROR` | `description` over 2000 characters (`field: description`); empty `room_id` (`field: chat_message.room_id`). | Limit the text box to 2000; app bug otherwise. |
| 400 | `BAD_REQUEST` (with `field: chat_message.message_id`) | `message_id` not shaped like `1700000000000-0`. | App bug. |
| 400 | `BAD_REQUEST` | The line isn't in that room any more (chat keeps a limited history), or it was sent by someone else. | Send the report again without `chat_message`, with the line's text quoted in `description`. Tell the player nothing extra. |
| 403 | `FORBIDDEN` | The line is in match chat of a match the reporter didn't play. | App bug (only offer lines the player can see). |
| 401 | `UNAUTHORIZED` | No token. | The interceptor. |
| 429 | `RATE_LIMITED` | Over the general limit, about 100 requests a minute (from code; no report-specific limit). | "Too many attempts. Try again in a minute." |

```json
{"error": "BAD_REQUEST", "message": "bad request: cannot report yourself"}
{"error": "NOT_FOUND", "message": "not found: player not found"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected one of `cheating`, `abuse`, `spam`, `inappropriate_content`, `harassment`, `other` at line 1 column 74"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: missing field `reason` at line 1 column 59"}
{"error": "VALIDATION_ERROR", "field": "description", "message": "validation error: description: must be at most 2000 characters"}
{"error": "BAD_REQUEST", "field": "chat_message.message_id", "message": "bad request: chat_message.message_id must be a stream entry id like 1700000000000-0"}
{"error": "BAD_REQUEST", "message": "bad request: chat message not found in that room"}
{"error": "BAD_REQUEST", "message": "bad request: chat message was not sent by the reported user"}
{"error": "FORBIDDEN", "message": "forbidden: only match participants can use this chat"}
{"error": "VALIDATION_ERROR", "field": "chat_message.room_id", "message": "validation error: chat_message.room_id: must be 1 to 64 characters"}
```

The two `400 BAD_REQUEST` chat cases share a code; tell them apart only if you must, by
`message` ("not found in that room" vs "not sent by the reported user"). The safe handling is
the same for both: resend without `chat_message`.

**Duplicates (live):** the same body sent twice answered `201` twice (report ids 1 and 2).
There is no `409`. The app's `ReportedTracker` is the only guard.

---

## 2. My reports

`GET /moderation/my-reports`

Reports **this account sent**, newest first, as a **plain array** with no paging (live:
`?page=2&per_page=1` was ignored and all 8 came back). Each item is the same object as the
report reply in section 1. Live (A, first two of 8; the long `description` is trimmed here):

```json
[
  {"id": 9, "reporter_id": "b327ea3e-b571-487d-9967-431e7e19df5b",
   "reported_user_id": "42dcdefc-d372-4668-be6d-ac16c96284a2", "reason": "other",
   "description": "", "status": "pending", "reviewed_by": null, "chat_message_ref": null,
   "evidence": {}, "created_at": "2026-11-24T09:58:52.257319Z",
   "reported_username": "w12docb1795514294", "reported_avatar_url": null},
  {"id": 6, "reporter_id": "b327ea3e-b571-487d-9967-431e7e19df5b",
   "reported_user_id": "42dcdefc-d372-4668-be6d-ac16c96284a2", "reason": "spam",
   "description": null, "status": "pending", "reviewed_by": null,
   "chat_message_ref": "1795514319444-0",
   "evidence": {"chat_message": {"body": "spam spam spam", "created_at": "2026-11-24T09:58:39.445Z",
     "id": "1795514319444-0", "room_id": "ludo-w12-1795514294", "room_type": "lobby",
     "sender_user_id": "42dcdefc-d372-4668-be6d-ac16c96284a2"}},
   "created_at": "2026-11-24T09:58:41.600507Z",
   "reported_username": "w12docb1795514294", "reported_avatar_url": null}
]
```

A player with no reports, and a player who was reported but reported nobody, both get `[]`
(live: B, who was reported 8 times, read `[]`). **Reports against you are never shown.**

**Status chips**

| `status` | Chip | Text |
|---|---|---|
| `pending` | Grey "Received" | "We've received your report." |
| `reviewed` | Blue "In review" | "Our team is looking at it." |
| `actiontaken` | Green "Action taken" | "Thanks. We took action on this report." Don't say what action. |
| `dismissed` | Grey "Closed" | "We reviewed this and took no action." |
| anything else | Grey "Received" | Keep the row; never crash. |

What the app does: show name, avatar, reason label, local date, chip, and the quoted chat
line when `evidence.chat_message` is present. Pull to refresh; re-read when the screen opens.
The list is not paged, so render it lazily (a `ListView.builder`).

---

## 3. Flag a match

`POST /matches/{id}/flag`, where `{id}` is the match UUID (`match_id` from
`game.started` / history). Only players who played in that match may flag it.

```json
{"reason": "Opponent seemed to use a bot."}
```

`reason`: required, 5 to 500 characters.

**Success:** `201`. Live (A flags the game A and B just played):

```json
{
  "id": 1,
  "match_id": "82e6509c-1bc9-43c6-8941-e2f3b4fc1c51",
  "flagged_by": "b327ea3e-b571-487d-9967-431e7e19df5b",
  "reason": "Opponent seemed to use a bot.",
  "status": "pending",
  "reviewed_by": null,
  "reviewed_at": null
}
```

`status` is `pending`, `reviewed` or `dismissed`, but **no route reads a flag back**, so the
app only ever sees `pending` in this reply. Both players may flag the same match (live: B's
flag got id 3), and the same player may flag it again (live: A's second flag got id 2).

**What the app does with it:** show "Thanks. We'll look into this match." Store the match id
in `ReportedTracker` and replace the button with "Reported" for that match. Offer it on the
match result screen and on the match detail screen; hide it for matches the player wasn't in.
If the complaint is about a person (abuse, chat), use "Report player" (section 1) instead;
the flag is for the game itself (cheating, a bot, a bug, an unfair result).

**Errors** (all live)

| Status | `error` | When | What the app does |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | `reason` under 5 or over 500 characters. | Enforce 5-500 in the text box. |
| 400 | `BAD_REQUEST` | `reason` missing; `{id}` not a UUID. | App bug. |
| 403 | `FORBIDDEN` | The player didn't play in that match. | Hide the button; "You can only report matches you played." |
| 404 | `MATCH_NOT_FOUND` | No such match. | "Match not found." |

```json
{"error": "VALIDATION_ERROR", "field": "reason", "message": "validation error: reason: must be 5 to 500 characters"}
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: missing field `reason` at line 1 column 2"}
{"error": "FORBIDDEN", "message": "forbidden: only match participants can flag a match"}
{"error": "MATCH_NOT_FOUND", "message": "match not found: 00000000-0000-4000-8000-000000000001"}
{"error": "BAD_REQUEST", "message": "bad request: Path deserialize error: UUID parsing failed: invalid length: found 3"}
```

A match can be flagged while it is still being played and after it ends (from code: no
status check). Offer it after the game ends only.

---

## 4. Bans, suspensions and restrictions

### Kinds of restriction

| Kind | Set by | What it blocks (from code) | How the app learns it |
|---|---|---|---|
| **Full ban** (`scope: full`), timed or permanent | Staff | Everything. All sessions are signed out at once. | `401 TOKEN_BLACKLISTED` on the next call, then `403 ACCOUNT_BANNED` at sign-in. |
| **Suspended or banned account** (`users.status`) | Staff | Sign-in, refresh, tournaments. Never timed. (Gateway chat checks bans and mutes, not this status.) | `403 ACCOUNT_BANNED` with no `until` at sign-in or refresh. |
| **Chat ban** (`scope: chat`) | Staff | Sending gateway chat. Not sign-in, not play. | `bans/check`, and `403 FORBIDDEN` on chat send. |
| **Mute** (always timed) | Staff | Sending gateway chat. | **Only** `403 FORBIDDEN` on chat send. Not in `bans/check`. |
| **Tournament ban** (`scope: tournaments`) | Staff | Joining tournaments. | `bans/check`, and `403 FORBIDDEN` on tournament join. |
| **Matchmaking ban** (`scope: matchmaking`) | Staff | **Nothing today** (no code checks it). | `bans/check` only. |

Game servers (Ludo and the rest) don't read bans or mutes: a chat-banned or muted player can
still use in-game quick chat, and a matchmaking-banned player can still find and play games
(from code). The app should still respect `bans/check` itself (see "Restrictions" below).

### 4a. Ban check

`GET /moderation/bans/check`

Not banned. Live:

```json
{"is_banned": false, "ban": null}
```

Banned (from code; the shape is the `Ban` record):

```json
{
  "is_banned": true,
  "ban": {
    "id": 12,
    "user_id": "b327ea3e-b571-487d-9967-431e7e19df5b",
    "scope": "chat",
    "reason": "Repeated abuse in lobby chat",
    "banned_by": 1,
    "expires_at": "2026-11-25T10:00:00Z",
    "created_at": "2026-11-24T10:00:00Z"
  }
}
```

| Field | Meaning |
|---|---|
| `is_banned` | `true` when **any** active ban exists, **of any scope**. A chat ban alone gives `true`. Always read `ban.scope`. |
| `ban.scope` | `full`, `chat`, `matchmaking` or `tournaments`. Unknown values: treat as a banner with no button changes. |
| `ban.expires_at` | When it ends; `null` = until staff lift it. Show in local time. |
| `ban.reason` | Staff text. **Don't show it** (the sign-in error deliberately leaves it out; this route leaks it, see "Known issues"). |
| `ban.banned_by`, `ban.id`, `ban.user_id` | Internal; don't show. |
| `ban.created_at` | When it was issued. |

Only **one** ban comes back: the newest active one. A player with a chat ban and a
tournament ban sees only the newer. Mutes and an account `status` of `suspended`/`banned` are
not reported here. A full-banned player can't call this route at all (signed out).

### 4b. What happens when staff ban during a session (from code)

1. **Full ban:** every session's access token is blacklisted and every refresh token revoked.
   - Next gateway call: `401 TOKEN_BLACKLISTED` (`{"error": "TOKEN_BLACKLISTED", "message": "token blacklisted"}`).
     Per `00-conventions.md` the app doesn't refresh; it goes to sign-in.
   - If the app does try to refresh: `401 UNAUTHORIZED` ("refresh token revoked").
   - Sign-in (password or email code): `403 ACCOUNT_BANNED`, with `until` for a timed ban:

     ```json
     {"error": "ACCOUNT_BANNED", "message": "account is banned until 2026-11-25T10:00:00Z", "until": "2026-11-25T10:00:00Z"}
     {"error": "ACCOUNT_BANNED", "message": "account is banned"}
     ```
   - **An open game socket is not closed at once.** It keeps working until the access token
     expires (up to 15 minutes), then gets `auth.session_expired` and closes. Reconnecting
     with the old token answers `auth.login_error` code `token_revoked` ("this session has
     logged out"), and the app can't get a new token, so after the 30-second grace the player
     forfeits. `auth.refresh` on the socket answers `auth.token_refresh_error` `token_revoked`.
2. **Status `suspended` or `banned`** set on the account: refresh and sign-in answer
   `403 ACCOUNT_BANNED` with no `until`. Access tokens already issued keep working until they
   expire (up to 15 minutes) unless staff also sign the player out.
3. **Chat, tournament or matchmaking ban, or a mute:** the player stays signed in. Nothing is
   pushed; the app finds out from `bans/check` or from a refused call.
4. A timed ban ends by itself at `until`; sign-in works again then. No notice is sent.

### 4c. Restrictions on single features

| Feature | Refusal | Live or code |
|---|---|---|
| Send gateway chat (`POST /chat/{type}/{id}/send`) while muted, chat-banned or full-banned | `403 FORBIDDEN` `"forbidden: you are muted or banned from chat"` | code |
| Join a tournament with a tournament or full ban, or a suspended account | `403 FORBIDDEN` `"forbidden: you are banned from tournaments"` | code |
| Read chat, play games, send gifts, add friends | Not restricted by chat, tournament or matchmaking bans | code |

### What the app does (restrictions)

| Case | Show | Buttons |
|---|---|---|
| `ACCOUNT_BANNED` with `until` (from any route, usually sign-in) | Full screen: "Your account is suspended until <local date, time>." Contact support link. | Only "Sign out" / back to sign-in. Clear tokens. |
| `ACCOUNT_BANNED` without `until` | Full screen: "Your account is suspended. Contact support." | As above. |
| `401 TOKEN_BLACKLISTED` mid-session | Go to sign-in as for any ended session (`01-auth.md`). If sign-in then answers `ACCOUNT_BANNED`, show the screen above. | |
| `bans/check` scope `chat`, or `403` on chat send | Banner in chat: "You can't send messages until <time>" (or "for now" if `expires_at` is `null`, or for a mute where no time is known). | Disable the chat input. Socket quick chat may stay on. |
| `bans/check` scope `tournaments`, or the tournament `403` above | Banner on Tournaments: "You can't join tournaments until <time>." | Disable Join. |
| `bans/check` scope `matchmaking` | Banner on Play: "You can't join games until <time>." | Disable Play buttons yourself; the server won't stop it. |
| `bans/check` scope `full` (rare: only between the ban and the token ending) | As `ACCOUNT_BANNED`. | |

Re-read `bans/check` when a shown `expires_at` passes, and clear the banner if it answers
`false`.

---

## 5. Responsible gaming

**No player route exists** to read or set limits, self-exclude or cool off (live:
`/users/me/limits`, `/users/me/gaming-limits`, `/users/me/self-exclusion` and
`/responsible-gaming` all answered `404 NOT_FOUND`). Staff set them per player in the admin
console. The app can't show the current limits.

What the server enforces (from code):

| Limit (set by staff) | Enforced in | Player sees |
|---|---|---|
| Self-exclusion until a time | Tournament join only | `403 FORBIDDEN` `"forbidden: you are self-excluded until <time>"` |
| Cooling off until a time | Tournament join only | `403 FORBIDDEN` `"forbidden: you are cooling off until <time>"` |
| Daily, weekly, monthly loss limit | Tournament join (rolling 24 h, 7 d, 30 d) | `403 FORBIDDEN` `"forbidden: buy-in would exceed your daily loss limit (<lost> lost of <limit>)"` |
| Daily tournament spend limit | Tournament join | `403 FORBIDDEN` `"forbidden: buy-in would exceed your daily tournament spend limit (<spent> spent of <limit>)"` |
| Daily loss limit (default 50,000 when none is set) and a session limit (12 hours in Poker, 8 in Teen Patti) | Poker and Teen Patti tables | Socket frames: a private `game.limit_exceeded` `{"user_id", "message"}` and a broadcast `game.player_sat_out` `{"user_id", "reason": "limit_exceeded"}`; a refused rebuy answers error code `limit_exceeded`. Their game files (not written yet) will give details. |

Self-exclusion and cooling off do **not** stop sign-in, other games, the store or gifts
today. The console's compliance settings (spend caps, session reminders, binge detection,
minimum age) are not read by any player route.

**What the app does:** the tournament `403` texts all share `FORBIDDEN` (see
`06-tournaments.md`); show "You can't join right now." and, when `message` contains "loss
limit" or "spend limit", "This would pass your spending limit." For "self-excluded" or
"cooling off", show "You've taken a break from tournaments until <time>." Add a Settings
page "Responsible gaming" with plain help text and a support contact. Don't build limit
editors until a route exists.

---

## 6. Region and age gates

### Region (geo gate)

Every gateway route (not only sign-in) and every game socket handshake pass through the
region check (from code). The server finds the country from the client's IP address. Staff
rules can:

| Rule | Refuses |
|---|---|
| Block | Every request. |
| Read-only | Requests that change something (`POST`, `PATCH`, `PUT`, `DELETE`). Reads still work. |
| Store off | Only `/sensitive/shop`, `/sensitive/iap` and `/sensitive/subscriptions`. |

All three answer the same body (from code):

```json
{"error": "GEO_BLOCKED", "message": "not available in your region"}
```

On a game socket the refusal is an HTTP `403` on the WebSocket upgrade, so the connect call
fails before `connection.established` (Dart `WebSocket.connect` throws).

**What the app does:**

- `GEO_BLOCKED` on sign-in, or on any `GET`: full screen "Royale Arcade isn't available in
  your region." Offer Retry (the player may have moved or switched network). Don't retry
  automatically.
- `GEO_BLOCKED` on a write while reads work: "This action isn't available in your region."
  Keep the app usable for reading.
- `GEO_BLOCKED` on a store route only: hide the store and purchases; keep play.
- A socket that fails at connect with `403`: "Games aren't available in your region."
- Development: the local gateway has region checks on (MaxMind), but requests from the LAN
  have no country and pass (live: every capture in this file passed).

### Age

There is no age gate today (from code). `date_of_birth` is an optional profile field
(`PATCH /users/me/profile`, `02-profile-and-sessions.md`); sign-up doesn't ask for it, and no
route refuses a player for age. Tournaments have a minimum-age setting that nothing checks.
If the product needs an age prompt, the app may ask at sign-up and save it to the profile,
but must not claim the server enforces it.

---

## Errors

The error body and the shared codes are in `00-conventions.md`, "Errors". Safety codes in one
place:

| Status | `error` | Routes |
|---|---|---|
| 400 | `BAD_REQUEST` | Report yourself; bad or missing `reason`, ids, `room_type`; chat line not found or not sent by that player; bad `message_id`; flag with no `reason`; bad match id. |
| 400 | `VALIDATION_ERROR` | `description` over 2000; empty `room_id`; flag `reason` outside 5-500. |
| 401 | `UNAUTHORIZED` | No token; refresh after a full ban ("refresh token revoked"). |
| 401 | `TOKEN_BLACKLISTED` | Any route after a full ban. |
| 403 | `ACCOUNT_BANNED` | Sign-in, refresh, email-code sign-in, guest convert while banned or suspended. |
| 403 | `FORBIDDEN` | Chat line in another match's chat; flag a match you didn't play; chat send while muted or chat-banned; tournament join while banned, self-excluded, cooling off or over a limit. |
| 403 | `GEO_BLOCKED` | Any route, and the socket handshake, from a refused region. |
| 404 | `NOT_FOUND` | Report an unknown player. |
| 404 | `MATCH_NOT_FOUND` | Flag an unknown match. |
| 429 | `RATE_LIMITED` | Over about 100 requests a minute. |

---

## Limits

| What | Limit |
|---|---|
| All routes here | The general limit, about 100 requests a minute per player (`429 RATE_LIMITED`). No report- or flag-specific limit. |
| Report `description` | 0 to 2000 characters. |
| Flag `reason` | 5 to 500 characters. |
| Chat evidence | Only lines still in the room's chat history; older lines are trimmed. Report soon. |
| Ban check | After sign-in, on resume (at most once a minute), after a chat or tournament `403`, and when a shown ban end passes. Never on a timer. |
| Repeat reports | Not limited by the server; the app allows one report per player per 24 hours and one per chat line. |

---

## Known issues (the app must cope)

1. **No duplicate protection.** The same report or match flag can be sent any number of
   times (live). Guard on the device with `ReportedTracker`.
2. **`match_id` on a report is silently dropped** (live), although the database has a
   column for it. Put the match id in `description` and use the match flag.
3. **In-game socket chat can't be attached as evidence** (no message id; separate store).
   Quote the line in `description`.
4. **`bans/check` says `is_banned: true` for any scope**, returns only the newest ban, and
   doesn't report mutes or a suspended account status. Decide on `ban.scope`.
5. **`bans/check` returns the staff `reason` and `banned_by`.** The sign-in error hides the
   reason on purpose. Never show these fields.
6. **Matchmaking bans are not enforced** anywhere: a matchmaking-banned player can still
   find and play games (from code). The app disables Play itself.
7. **Game servers ignore bans and mutes.** A chat-banned or muted player keeps socket quick
   chat; a fully banned player keeps an open game socket until the token expires (up to 15
   minutes), then forfeits after the reconnect grace.
8. **No mute route.** A mute shows only as `403 FORBIDDEN` on chat send, with no end time.
9. **No player responsible-gaming routes**, and self-exclusion and cooling off only stop
   tournament joins. Tournament refusals all share `403 FORBIDDEN` (see `06-tournaments.md`).
10. **No age gate** despite the console's age settings.
11. **No notice** to the reporter when a report is reviewed, and none to a player when a
    feature ban starts or ends. Re-read on screen open and on resume.
12. **Match flags can't be read back**; there is no "my flags" list.
13. **`my-reports` is not paged** and ignores `page` / `per_page`.
14. **An empty `description` is stored as `""`**, not `null`. Leave the field out when empty,
    and treat `""` and `null` the same when showing.

---

## Done when

- [ ] "Report" on a player card opens the sheet with the six reasons; Send shows the thank-you
      text and offers "Also block".
- [ ] Long-press on a gateway chat line offers "Report message"; the report carries
      `chat_message`, and `my-reports` shows the quoted line.
- [ ] A `400` for a chat line that's gone resends without `chat_message`, with the text in
      `description`, and the player sees one thank-you.
- [ ] Reporting the same player twice within 24 hours shows "You've already reported this"
      without a network call.
- [ ] Report is never offered on the player's own card or lines; `404` shows "Player not
      found".
- [ ] My reports lists newest first with the four status chips and copes with an unknown
      status and an empty list.
- [ ] "Report a problem with this match" shows on the result and detail screens of matches the
      player played, enforces 5-500 characters, and turns into "Reported" after `201`.
- [ ] `403 ACCOUNT_BANNED` from sign-in shows the suspended screen with `until` in local
      time, or the no-end text; tokens are cleared.
- [ ] `401 TOKEN_BLACKLISTED` mid-session goes to sign-in without a refresh attempt.
- [ ] `bans/check` runs after sign-in and on resume; scopes `chat`, `tournaments` and
      `matchmaking` show their banners and disable their buttons; the banner clears after
      `expires_at`.
- [ ] Chat send `403` disables the input with "You can't send messages for now".
- [ ] `ban.reason` and `ban.banned_by` appear nowhere in the UI or logs.
- [ ] `GEO_BLOCKED` shows the region screen (full block), the read-only message (writes), or
      hides the store (store routes); a socket `403` at connect shows "Games aren't available
      in your region".
- [ ] Settings has a Responsible gaming help page; no limit editor is shown.
- [ ] No report body or description appears in any log.

---

## Test accounts

Create your own players on the development server with `POST /auth/register` (any
`@example.com` email), as in `01-auth.md`. Reporting needs two players; flagging needs a
match both played (a free Ludo `friends_room` game, `games/ludo.md`; a forfeit ends it at
once). Test players can't ban, mute or set limits, so the ban, mute, limit and region screens
need a staff member to set them on a test account in the admin console, or a mocked
`ApiClient`. Don't use other people's accounts.

The samples here came from three players made for this file on 24 Nov 2026:

| | Username | User id |
|---|---|---|
| A | `w12doca1795514294` | `b327ea3e-b571-487d-9967-431e7e19df5b` |
| B | `w12docb1795514294` | `42dcdefc-d372-4668-be6d-ac16c96284a2` |
| C | `w12docc1795514294` | `9a7c0e7f-abc9-4402-b383-0c87a260dce6` |

Match: `82e6509c-1bc9-43c6-8941-e2f3b4fc1c51` (friends room, A forfeited to B). State they were
left in: A sent 8 pending reports about B (reports 1-6, 8, 9) and has 2 flags on the match; B
has 1 flag on it; C reported A (report 10). Nobody is banned.
