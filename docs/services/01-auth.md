# Flutter hand-off 1: account access

Sign up, log in, refresh, log out, change password, forgot password, guest play, email codes
(OTP) and social sign-in (OAuth).

This file is the contract between the Flutter app and the **api-gateway** for account access.
It is written so a Claude agent can implement it directly. Every request and reply below was
checked against the running gateway on 24 Nov 2026; the replies are real, with tokens and
codes blanked.

Later hand-off files (profile, wallet, games, sockets) build on the session handling described
here, so implement this one fully first.

---

## For the Claude agent: what to build

1. A configurable **server address** (see "Base URL"). Never hard-code `localhost`.
2. An `AuthApi` client with one method per endpoint below, returning typed results or a typed
   `ApiError` (see "Errors").
3. A `TokenStore` that keeps the access token, refresh token and access expiry in
   **secure storage** (`flutter_secure_storage`), never in `SharedPreferences` or logs.
4. An HTTP **interceptor** that adds `Authorization: Bearer <access_token>` and refreshes the
   token once on a 401, as described in "Keeping the user signed in".
5. Screens and actions:
   - **Welcome**: "Play as guest", "Log in", "Sign up".
   - **Sign up**, **Log in** (password, or "Email me a code"), **Forgot password** (3 steps).
   - **Save your progress** for guests (guest to full account).
   - **Change password** and **Verify email** in account settings.
   - A **Log out** action.
6. An auth state (`signedOut`, `guest`, `signedIn`) that the app's router listens to. Any
   unrecoverable 401 moves the app to `signedOut` and clears the `TokenStore`.
7. Tests: unit tests for `AuthApi` (mock the HTTP client) and the interceptor's refresh logic,
   including "two requests fail at once, only one refresh is sent".

Suggested packages: `dio` (HTTP and interceptors), `flutter_secure_storage`. Use others if the
project already has an equivalent.

Do not log request bodies, passwords, tokens or codes, even in debug builds.

---

## Base URL

```
http://<server-address>:1280/api/v1
```

- Local development: the developer's machine or a teammate's IP, for example
  `http://192.168.0.235:1280/api/v1`. The port is always **1280**. The phone must be on the
  same Wi-Fi as that machine.
- Make the address a setting (a debug-only "Server" field, or a build flavor value).
- Plain `http` on a LAN needs, on Android, `android:usesCleartextTraffic="true"` (debug only),
  and on iOS an `NSAppTransportSecurity` exception (debug only). Production will be `https`.
- An Android emulator reaches the host machine at `10.0.2.2`, not `localhost`.

Every request and reply body is JSON: send `Content-Type: application/json`.
Send a stable `User-Agent`, for example `RoyaleArcade/1.0.0 (Android 14)`. The gateway uses it
to name the device in the player's session list.

---

## Endpoints at a glance

| Step | Method and path | Needs a token | Success |
|---|---|---|---|
| Sign up | `POST /auth/register` | no | `201` + tokens |
| Log in | `POST /auth/login` | no | `200` + tokens |
| Refresh tokens | `POST /auth/refresh` | no (refresh token in body) | `200` + tokens |
| Current user | `GET /users/me` | yes | `200` + profile |
| Log out | `POST /auth/logout` | yes | `204`, empty body |
| Change password | `POST /auth/change-password` | yes | `204`, empty body |
| Forgot password 1: ask for a code | `POST /auth/forgot-password` | no | `202` |
| Forgot password 2: check the code | `POST /auth/forgot-password/verify` | no | `200` + reset token |
| Forgot password 3: new password | `POST /auth/reset-password` | no | `204`, empty body |
| Play as guest | `POST /guest/create` | no | `201` + tokens |
| Guest to full account | `POST /guest/convert` | yes (guest) | `200` + tokens |
| Log in with a code 1: send | `POST /otp/login/send` | no | `200` |
| Log in with a code 2: check | `POST /otp/login/verify` | no | `200` + tokens |
| Verify email 1: send | `POST /otp/send` | yes | `200` |
| Verify email 2: check | `POST /otp/verify` | yes | `200` |
| Social sign-in | `POST /oauth/{provider}/callback` | yes | **not available yet** (see 10) |
| Unlink a social account | `DELETE /oauth/{provider}/unlink` | yes | `204` |

---

## The token reply

Sign up, log in, refresh and log in with a code all reply with the same shape:

```json
{
  "access_token": "<JWT>",
  "refresh_token": "<opaque string>",
  "expires_in": 900
}
```

Guest create and guest convert add the account id:

```json
{
  "user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c",
  "access_token": "<JWT>",
  "refresh_token": "<opaque string>",
  "expires_in": 900
}
```

| Field | Meaning |
|---|---|
| `access_token` | Sent as `Authorization: Bearer <access_token>` on every request that needs a token. |
| `refresh_token` | Used only with `POST /auth/refresh`. Valid for 7 days. **Single use**: each refresh returns a new one and the old one stops working. |
| `expires_in` | Seconds until the access token expires (15 minutes). Store `now + expires_in` as the expiry. |
| `user_id` | Guest replies only. The same id `GET /users/me` returns. |

Treat both tokens as opaque. Do not decode the JWT to make decisions; call `GET /users/me`
to learn who the user is.

---

## 1. Sign up

`POST /auth/register`

```json
{
  "username": "fdoc7419",
  "email": "flutter.doc.1795507419@example.com",
  "password": "Passw0rd!x",
  "referral_code": "FRIEND42",
  "entry_game": "ludo",
  "entry_source": "direct",
  "device_id": "3f6c2a9e-8d1b-4c55-9a77-0b2e5d4f1a10"
}
```

| Field | Rule |
|---|---|
| `username` | 3 to 32 characters, unique. Shown to other players. Use letters, digits and `_` only (the app should enforce this; the server checks only the length today). |
| `email` | A valid email, unique. |
| `password` | 8 to 128 characters. |
| `referral_code` | Optional. A friend's code: the sign-up applies it. A wrong or used-up code never fails the sign-up; it is just not applied. |
| `entry_game` | Optional. The game code the player came in through (for example `ludo`, `snake-and-ladder`), for the welcome bonus. |
| `entry_source` | Optional. How the player arrived: `direct` (the default), `deeplink`, `store`, `invite` or `ad`. Any other value is a `400 BAD_REQUEST`. |
| `device_id` | Optional. A stable id for this install (generate a UUID once and keep it in secure storage). Used to stop one device claiming the welcome bonus twice. |

**Success:** `201 Created` with the token reply. The user is signed in: store the tokens,
then call `GET /users/me`.

**Errors:**

| Status | `error` | When | Show the user |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | A field breaks a rule. `field` names the first bad field. | The rule for that field, next to it. |
| 400 | `BAD_REQUEST` | A required field is missing, the body is not JSON, or `entry_source` is not one of the five values. | A bug in the app; show a generic error. |
| 409 | `CONFLICT` | The username or the email is already taken (the reply doesn't say which). | "That username or email is already registered." Offer Log in and Forgot password. |
| 429 | `RATE_LIMITED` | Too many attempts from this network. | "Too many attempts. Try again in a minute." |

Real replies:

```json
// 409
{"error": "CONFLICT", "message": "conflict: username or email already taken"}

// 400, field rule
{"error": "VALIDATION_ERROR", "field": "password", "message": "validation error: password: must be 8 to 128 characters"}

// 400, unknown entry_source
{"error": "BAD_REQUEST", "message": "bad request: Json deserialize error: unknown variant, expected one of `direct`, `deeplink`, `store`, `invite`, `ad` at line 1 column 115"}
```

Validate on the device first (same rules), so most users never see a `400`.

---

## 2. Log in

`POST /auth/login`

```json
{
  "email": "flutter.doc.1795507419@example.com",
  "password": "Passw0rd!x"
}
```

Login is **by email**, not username. To log in without a password, see 8.

**Success:** `200 OK` with the token reply. Store the tokens, then call `GET /users/me`.

**Errors:**

| Status | `error` | When | Show the user |
|---|---|---|---|
| 401 | `INVALID_CREDENTIALS` | Wrong email or wrong password. The reply is the same for both, on purpose. | "Email or password is incorrect." Offer Forgot password and "Email me a code". |
| 403 | `ACCOUNT_BANNED` | The account is suspended or banned. `until` (ISO 8601, UTC) is present for a timed ban. | "Your account is suspended until <local date and time>." or, with no `until`, "Your account is suspended. Contact support." |
| 403 | `GEO_BLOCKED` | The game isn't offered in the player's region. | "Royale Arcade isn't available in your region." |
| 400 | `VALIDATION_ERROR` | The email isn't a valid email. | Field error under the email. |
| 429 | `RATE_LIMITED` | Too many attempts from this network. | "Too many attempts. Try again in a minute." |

```json
// 401
{"error": "INVALID_CREDENTIALS", "message": "invalid credentials"}

// 403, timed ban
{"error": "ACCOUNT_BANNED", "message": "account is banned until ...", "until": "2026-11-10T08:00:00Z"}
```

---

## 3. Current user

`GET /users/me` with `Authorization: Bearer <access_token>`

Call it right after sign up, log in or guest create, and on app start when tokens are stored.
A shortened real reply (the full reply also has `addresses`, `privacy` and `preferences`
objects, which the profile hand-off covers):

```json
{
  "id": "a397bea2-550b-4702-bfe3-5a336b68831b",
  "username": "fdoc7419",
  "email": "flutter.doc.1795507419@example.com",
  "phone": null,
  "email_verified_at": null,
  "phone_verified_at": null,
  "role": "user",
  "status": "active",
  "created_at": "2026-11-24T08:03:40.102218Z",
  "updated_at": "2026-11-24T08:03:40.126177Z",
  "profile": {
    "user_id": "a397bea2-550b-4702-bfe3-5a336b68831b",
    "display_name": "fdoc7419",
    "avatar_id": null,
    "avatar_url": null,
    "bio": null,
    "country": null,
    "date_of_birth": null,
    "preferred_language": null,
    "updated_at": "2026-11-24T08:03:40.102218Z"
  },
  "full_name": null,
  "avatar_glyph": null,
  "gender": null,
  "timezone": null,
  "preferred_channel": "email",
  "addresses": { "...": "..." },
  "privacy": { "...": "..." },
  "preferences": { "...": "..." }
}
```

For this hand-off the app needs:

| Field | Use |
|---|---|
| `id`, `username`, `profile.display_name` | Who is signed in. |
| `email` | `null` means a **guest** account (see 7). Every full account has an email. |
| `email_verified_at` | `null` means the email isn't verified yet: show "Verify email" in settings (see 9). |

Parse unknown fields leniently. Times are ISO 8601 UTC; show them in local time.

---

## 4. Keeping the user signed in (refresh)

`POST /auth/refresh`, no `Authorization` header:

```json
{ "refresh_token": "<the stored refresh token>" }
```

**Success:** `200 OK` with a **new** token reply. Replace both stored tokens at once. The old
refresh token is now dead.

**When to refresh:**

1. **Before a request**, if the stored access expiry is less than 60 seconds away.
2. **After a `401`** on any request that sent a token, if `error` is `UNAUTHORIZED`. An
   expired access token comes back as `401 UNAUTHORIZED` (message `invalid token: ...`), not
   as `TOKEN_EXPIRED`. Refresh once, then retry the original request once.

**Rules for the interceptor:**

- Only **one** refresh at a time. If several requests get a 401 together, the first starts the
  refresh and the others wait for it, then retry with the new token. Two refreshes with the
  same refresh token make the second fail, because each token works once.
- Never retry more than once per request. Never refresh in response to a 401 from
  `/auth/refresh` itself.
- If the refresh fails (any `401`, or `403 ACCOUNT_BANNED`), clear the `TokenStore` and go to
  `signedOut`. For a ban, show the ban message from the login table.
- On a `401 TOKEN_BLACKLISTED`, do not refresh: the session was ended (logout, a password
  change, or a password reset). Clear tokens and go to `signedOut`.

**Refresh errors:**

| Status | `error` | Message | Meaning |
|---|---|---|---|
| 401 | `UNAUTHORIZED` | `unauthorized: refresh token revoked` | Already used, or the session was logged out. |
| 401 | `UNAUTHORIZED` | `invalid refresh token` | Unknown token. |
| 401 | `TOKEN_EXPIRED` | `token expired` | Older than 7 days. |
| 403 | `ACCOUNT_BANNED` | | Banned since the last login. |

**On app start:** if a refresh token is stored, call `GET /users/me` (the interceptor refreshes
if needed). On `200` go to `signedIn`, or to `guest` when `email` is `null`. Otherwise go to
`signedOut`.

---

## 5. Log out

`POST /auth/logout` with `Authorization: Bearer <access_token>`, no body.

**Success:** `204 No Content`, empty body. From then on, this session's access token gets
`401 TOKEN_BLACKLISTED` and its refresh token gets `401 refresh token revoked`.

```json
// the old access token after logout
{"error": "TOKEN_BLACKLISTED", "message": "token blacklisted"}
```

Only **this device's** session ends. The player stays signed in on their other devices.

In the app:

1. Send the request.
2. Whatever the reply (success, `401`, or no network), clear the `TokenStore` and go to
   `signedOut`. The user asked to leave; never keep them signed in because the call failed.
3. Do not try to refresh before a logout.

**Guests:** a guest account has no email or password, so after logging out it can't be
signed in again and its progress is lost. Before logging out a guest, warn: "You're playing
as a guest. Log out and your progress is lost. Save your progress first?" and offer 7b.

---

## 6. Passwords

### 6a. Change password (signed in)

`POST /auth/change-password` with `Authorization: Bearer <access_token>`

```json
{ "current_password": "Passw0rd!x", "new_password": "NewPassw0rd!" }
```

**Success:** `204 No Content`, empty body.

- **Every session of this account is signed out, including this one.** The access token in
  hand now gets `401 TOKEN_BLACKLISTED`. Clear the `TokenStore`, tell the user "Password
  changed. Log in with your new password.", and show Log in with the email filled in.

| Status | `error` | When | Show the user |
|---|---|---|---|
| 401 | `INVALID_CREDENTIALS` | `current_password` is wrong. **Not** a session problem: don't refresh or sign out. | "Your current password is incorrect." |
| 400 | `VALIDATION_ERROR` | `new_password` is shorter than 8 or longer than 128 (`field` is `new_password`). | Field error. |

```json
// 401, wrong current password
{"error": "INVALID_CREDENTIALS", "message": "invalid credentials"}

// 400
{"error": "VALIDATION_ERROR", "field": "new_password", "message": "validation error: new_password: must be 8 to 128 characters"}
```

The interceptor must not treat this `401 INVALID_CREDENTIALS` as an expired session: refresh
only on `401 UNAUTHORIZED` (see 4).

### 6b. Forgot password (3 steps, signed out)

All three calls are public: no `Authorization` header.

**Step 1: ask for a code.** `POST /auth/forgot-password`

```json
{ "email": "flutter.doc.1795507419@example.com" }
```

**Success:** `202 Accepted`

```json
{ "expires_in": 600 }
```

- The reply is the same whether or not the email has an account, so the app always says:
  "If an account uses this email, we've sent a 6-digit code. It expires in 10 minutes."
- **Development servers only:** the reply also contains `"debug_code": "123456"`, because no
  email provider is connected yet. The app may pre-fill the code in debug builds. Never rely
  on `debug_code`; production never sends it.
- **Production today:** this step answers `503 UNAVAILABLE` ("password reset email is not
  configured") until email sending is connected. Show "Password reset isn't available yet.
  Contact support."

**Step 2: check the code.** `POST /auth/forgot-password/verify`

```json
{ "email": "flutter.doc.1795507419@example.com", "code": "123456" }
```

**Success:** `200 OK`

```json
{ "reset_token": "<opaque string>", "expires_in": 600 }
```

Keep `reset_token` in memory only (not secure storage); it is valid for 10 minutes and works
once.

| Status | `error` | When | Show the user |
|---|---|---|---|
| 400 | `BAD_REQUEST` | Wrong code, expired code, or no code was asked for. | "That code is wrong or has expired." |
| 400 | `VALIDATION_ERROR` | The code isn't 6 characters. | Field error. Use a 6-digit numeric field. |
| 429 | `RATE_LIMITED` | 5 wrong codes for this request. | "Too many tries. Ask for a new code." Go back to step 1. |

**Step 3: set the new password.** `POST /auth/reset-password`

```json
{ "reset_token": "<from step 2>", "new_password": "NewPassw0rd!" }
```

**Success:** `204 No Content`, empty body.

- Every session of this account on every device is signed out, including any session on
  this device. Clear the `TokenStore`.
- Tell the user "Password changed. Log in with your new password.", then show Log in with the
  email filled in. The old password no longer works.

| Status | `error` | When | Show the user |
|---|---|---|---|
| 400 | `VALIDATION_ERROR` | The new password is shorter than 8 or longer than 128. | Field error. |
| 400 | `BAD_REQUEST` | The reset token is wrong, expired or already used. | "This reset link has expired. Start again." Go to step 1. |

---

## 7. Guest play

A guest is a real account with no email or password, so the player can start playing at once.

### 7a. Play as guest

`POST /guest/create`, no `Authorization` header. The body is optional; send the welcome
fields when you have them (same rules as sign up):

```json
{ "entry_game": "ludo", "entry_source": "store", "device_id": "3f6c2a9e-8d1b-4c55-9a77-0b2e5d4f1a10" }
```

**Success:** `201 Created` with the guest token reply:

```json
{"user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "access_token": "<blanked>", "refresh_token": "<blanked>", "expires_in": 900}
```

Store the tokens like any login and go to `guest`. `GET /users/me` then shows:

```json
{"id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "username": "guest_a1164ecb", "email": null, "...": "..."}
```

- The username is `guest_` plus the first 8 characters of the id. Show it as the player's name.
- Refresh works the same as for a full account.
- **Create a guest only once per install.** If a refresh token is stored, use it (see 4).
  Each call makes a new account; a second call loses the first guest's progress.
- Limit: the same as sign-up (see "Limits"). Over it: `429 RATE_LIMITED`.

### 7b. Save progress (guest to full account)

`POST /guest/convert` with the **guest's** `Authorization: Bearer <access_token>`

```json
{ "username": "gfdoc7419", "email": "gflutter.doc.1795507419@example.com", "password": "Passw0rd!x" }
```

Same rules as sign up for the three fields.

**Success:** `200 OK` with the guest token reply. The `user_id` is unchanged, so the
player keeps their wallet, history and progress.

```json
{"user_id": "a1164ecb-e4ff-4db2-8125-b29b4691146c", "access_token": "<blanked>", "refresh_token": "<blanked>", "expires_in": 900}
```

- **Replace both stored tokens** with the new ones and go to `signedIn`. (The old guest
  access token still works until it expires, but don't keep it.)
- From now on the player logs in with this email and password.

| Status | `error` | When | Show the user |
|---|---|---|---|
| 409 | `CONFLICT` | The username or email is taken. | "That username or email is already registered." |
| 400 | `VALIDATION_ERROR` | A field breaks a rule. | Field error. |
| 400 | `BAD_REQUEST` | The account is already a full account (`user is not a guest account`). | Hide "Save your progress"; refresh `GET /users/me`. |
| 429 | `RATE_LIMITED` | More than 5 tries a minute. | "Too many attempts. Try again in a minute." |

```json
// 409
{"error": "CONFLICT", "message": "conflict: username or email already taken"}

// 400, already converted
{"error": "BAD_REQUEST", "message": "bad request: user is not a guest account"}
```

---

## 8. Log in with an email code (OTP)

A password-free login: the player enters their email, gets a 6-digit code, and types it in.
Both calls are public.

**Step 1: send a code.** `POST /otp/login/send`

```json
{ "email": "flutter.doc.1795507419@example.com" }
```

**Success:** `200 OK`

```json
{ "purpose": "login", "expires_in": 600 }
```

- The reply is the same for an unknown email, on purpose. Always say "If an account uses this
  email, we've sent a 6-digit code. It expires in 10 minutes."
- There is **no** `debug_code` in this reply. On development servers the code is written to
  the gateway's log; ask the developer running the server for it.
- **Production:** `503 UNAVAILABLE` ("OTP delivery is not configured") until email sending is
  connected. Show "Code login isn't available yet. Use your password."
- Sending again replaces the earlier code.

**Step 2: check the code.** `POST /otp/login/verify`

```json
{ "email": "flutter.doc.1795507419@example.com", "code": "123456" }
```

**Success:** `200 OK` with the token reply. Store the tokens and call `GET /users/me`, as for
a password login. A correct code also marks the email as verified.

| Status | `error` | When | Show the user |
|---|---|---|---|
| 401 | `INVALID_CREDENTIALS` | Wrong code, expired code, already used, or unknown email. The reply is the same for all. | "That code is wrong or has expired." |
| 400 | `VALIDATION_ERROR` | The email isn't valid or the code isn't 6 characters. | Field error. |
| 403 | `ACCOUNT_BANNED` | As for login. | The ban message. |
| 429 | `RATE_LIMITED` | 5 wrong tries for this code (the code is then deleted), or too many sends. | "Too many tries. Ask for a new code." Go back to step 1. |

```json
// 401
{"error": "INVALID_CREDENTIALS", "message": "invalid credentials"}
```

---

## 9. Verify email (signed in, OTP)

Shown in settings while `email_verified_at` is `null`. Both calls need the token.

**Step 1: send a code.** `POST /otp/send`

```json
{ "purpose": "email_verify" }
```

**Success:** `200 OK`

```json
{ "purpose": "email_verify", "expires_in": 600 }
```

The code goes to the account's own email (no address in the body). Development servers
write it to the gateway's log, as in 8.

**Step 2: check the code.** `POST /otp/verify`

```json
{ "purpose": "email_verify", "code": "123456" }
```

**Success:** `200 OK`. **Check `verified`, not the status:** a wrong code is also `200`.

```json
// right code: the email is now verified
{"verified": true}

// wrong code
{"verified": false}
```

After `true`, call `GET /users/me` again: `email_verified_at` now has a time.

| Status | `error` | When | Show the user |
|---|---|---|---|
| 200 | | `{"verified": false}`: wrong code. | "That code is wrong." |
| 404 | `NOT_FOUND` | No code is pending (expired, used, or never sent). | "That code has expired. Send a new one." |
| 400 | `BAD_REQUEST` | On either step: `purpose` is `login` (use 8 instead). On step 1: the account has no email (a guest). | A bug in the app: hide Verify email for guests. |
| 429 | `RATE_LIMITED` | 5 wrong tries (the code is deleted), or too many sends. | "Too many tries. Send a new code later." |

```json
// 400, purpose login on this route
{"error": "BAD_REQUEST", "message": "bad request: sign-in codes are sent by POST /otp/login/send"}
```

`purpose` also accepts `password_reset` and `login_2fa`. The app doesn't need them today:
password reset uses 6b, and two-step login isn't switched on.

---

## 10. Social sign-in (OAuth): not available yet

**Don't build "Sign in with Google" or "Sign in with Apple" yet.** The gateway has no social
sign-in. It has only two routes for **linking** a provider to an account that is already
signed in, and linking isn't connected to Google or Apple yet:

| Route | Today |
|---|---|
| `POST /oauth/{provider}/callback` with `{"code": "...", "state": "..."}` | Always `503 UNAVAILABLE`. |
| `DELETE /oauth/{provider}/unlink` | `204` if linked; `404 NOT_FOUND` otherwise. Nothing can be linked yet, so it is always `404`. |

```json
// 503
{"error": "UNAVAILABLE", "message": "unavailable: OAuth account linking is not configured"}

// 404
{"error": "NOT_FOUND", "message": "not found: provider not linked"}

// 401, called without a token
{"error": "UNAUTHORIZED", "message": "unauthorized: missing authorization header"}
```

Hide social buttons in the app. A later hand-off will describe social sign-in once the
gateway supports it.

---

## Errors

Every error has this body:

```json
{
  "error": "MACHINE_CODE",
  "message": "human-readable detail",
  "field": "only on VALIDATION_ERROR: the first bad field",
  "until": "only on ACCOUNT_BANNED with a timed ban"
}
```

- **Decide on `error` and the HTTP status, never on `message`.** The message wording can change.
- Don't show `message` to the user as is: it is written for developers (for example
  `validation error: password: must be 8 to 128 characters`) and isn't translated. Map `error`
  (and `field`) to your own text. The server never repeats submitted values in `message`.
- The same `error` can mean different things on different routes. For example
  `401 INVALID_CREDENTIALS` on change password is a wrong current password, not an ended
  session. Handle errors per call; the interceptor reacts only to `401 UNAUTHORIZED` and
  `401 TOKEN_BLACKLISTED`.
- No network or a timeout: "Can't reach the server. Check your connection." Offer Retry.
- `500` (`INTERNAL_ERROR`, `DATABASE_ERROR`, `CACHE_ERROR`) or `503`: "Something went wrong.
  Try again." Offer Retry.

Suggested Dart shape:

```dart
class ApiError implements Exception {
  final int status;       // HTTP status, 0 for no network
  final String code;      // "error" field, e.g. "INVALID_CREDENTIALS"
  final String? field;    // VALIDATION_ERROR only
  final DateTime? until;  // ACCOUNT_BANNED only
}
```

---

## Limits

| What | Limit |
|---|---|
| Sign-up, login, refresh, forgot-password, change-password and guest-create calls | 5 a minute per network address in production (raised for local testing). Over it: `429 RATE_LIMITED`. Don't retry automatically; let the user try again. |
| Guest convert | 5 a minute. |
| Email codes sent (`/otp/send`, `/otp/login/send`) | 10 an hour per network address, and 3 per email address every 10 minutes. |
| Email code checks | 5 tries per code; then the code is deleted. |
| Access token | 15 minutes |
| Refresh token | 7 days, single use |
| Email code and reset code | 6 digits, 10 minutes |
| Reset token | 10 minutes, single use |

---

## Done when

- [ ] Sign up with a new email signs the user in and shows their username from `GET /users/me`.
- [ ] Sign up sends `entry_game`, `entry_source` and the install's `device_id`.
- [ ] Sign up with a taken email or username shows the "already registered" message.
- [ ] Log in with a wrong password shows "Email or password is incorrect."
- [ ] Killing and reopening the app keeps the user signed in (full account and guest).
- [ ] After 15 minutes, the next request refreshes silently and succeeds, without a login screen.
- [ ] Two requests that fail with 401 together send only one refresh.
- [ ] Log out returns to the Welcome screen, and reopening the app stays signed out, also
      when offline. Logging out a guest warns first.
- [ ] Change password with a wrong current password shows the error and keeps the user
      signed in; with the right one, the user is sent to Log in and the new password works.
- [ ] Forgot password: request a code, enter it (pre-filled from `debug_code` in debug builds),
      set a new password, then the old password fails and the new one works.
- [ ] A wrong reset code shows the error; 5 wrong codes send the user back to step 1.
- [ ] "Play as guest" signs in at once, and reopening the app keeps the same guest.
- [ ] "Save your progress" turns the guest into a full account with the same id, and the new
      email and password log in.
- [ ] Log in with an email code works with the code from the server log.
- [ ] Verify email turns `email_verified_at` from `null` to a time; a wrong code shows the error.
- [ ] No social sign-in buttons are shown.
- [ ] No password, token or code appears in any log.

---

## Test accounts

Create your own accounts with Sign up or "Play as guest" on the development server (any
`@example.com` email). Don't use other people's accounts. Ask the project owner for the server
address, and for email codes from the server log.
