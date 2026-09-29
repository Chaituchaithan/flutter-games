# Aura — Dynamic Data & Real-API Integration Plan

**Status:** planning only. The app is **presentation-complete** and stays that way
until we deliberately flip screens over. This doc is the bridge from the current
static UI to live data (**static → dynamic**) and real auth (**mockapi → real API**),
per the standing rule that button handlers + inline data are the single integration
seam.

Nothing here has been coded yet — it is the agreed shape for the next phase.

---

## 1. Where we are today

- **No data layer.** Every screen owns its data as inline `const` lists — 18 screens
  (`_friends`, `_matches`, `_live`, `_rest`, pack grids, rosters, …).
- **No networking, no models, no state management.** Only dependencies are
  `google_fonts` + `cupertino_icons`.
- **Handlers are already stubbed at the seam.** Buttons call `showAuraToast` /
  `showAuraDialog` / `Navigator` — the exact spots that become real calls.
- **Loading & error affordances already exist:** `LoadingSkeletonScreen` / `Shimmer` /
  `SkeletonBox` (`system/loading_skeleton_screen.dart`) and `AuraOfflineBanner` +
  `showAuraToast(kind: error)` (`widgets/aura_overlays.dart`). The dynamic phase
  *consumes* these; it doesn't need new UI.

**Design constraint:** the reskin must not regress. We add a layer *below* the
widgets; screens change from holding `const` data to reading it from a repository.
Widget trees and goldens stay identical.

---

## 2. Target architecture

A thin, testable 3-layer split. No framework lock-in.

```
lib/
  data/
    models/         # immutable DTOs + fromJson/toJson (friend.dart, match.dart, …)
    sources/
      static/       # the current const lists, moved here verbatim (StaticFriendsSource…)
      remote/       # HTTP-backed sources (RemoteFriendsSource…)
    repositories/   # one per domain; picks a source, exposes Futures/Streams
  services/
    api_client.dart # base URL, headers, auth token, error mapping, retry
    auth_service.dart
    session.dart    # holds current user + token; ChangeNotifier
  state/            # per-screen controllers (ChangeNotifier / AsyncValue)
```

**Key idea — the source swap is the "static → dynamic" switch.** Each repository is
constructed with a source. Ship with `StaticXSource` (today's const data) and flip to
`RemoteXSource` per-domain via one flag/DI binding. This lets us migrate **one screen
at a time** with zero UI churn and a trivial rollback.

### State management — recommendation

**`riverpod` (flutter_riverpod)** — reasons: no `BuildContext` plumbing for reads,
first-class async (`AsyncValue` → loading/error/data maps cleanly onto our skeleton /
offline banner / toast), easy to override providers with static sources in tests.

Alternative if we want to add nothing heavy: **`provider` + `ChangeNotifier`**, which
also matches the existing `MainShellScope` `InheritedWidget` idiom. Either works; the
repository layer below is identical. **Decision needed before coding.**

### Networking

`dio` (interceptors for auth header + refresh + logging + error mapping) or `http` if
we want minimal. `dio` recommended for the interceptor ergonomics.

---

## 3. Domain & endpoint map

One model + repository per domain. Endpoints are placeholders to confirm with the API.

| Domain | Model(s) | Static source (today) | Repository method | Likely endpoint |
|---|---|---|---|---|
| Auth/session | `User`, `AuthToken` | mock nav in `auth/*` | `login`, `register`, `verifyOtp`, `resetPassword`, `logout` | `POST /auth/*` |
| Profile | `Profile`, `Stats` | `profile_screen.dart` | `me()`, `updateProfile()`, `setAvatar()` | `GET/PATCH /me` |
| Wallet/economy | `Balance`, `Pack`, `Txn` | `store_screen.dart`, `transactions` | `balance()`, `packs()`, `purchase()`, `transactions()` | `GET /wallet`, `POST /purchase` |
| Daily/season/referral | `DailyReward`, `SeasonPass`, `Referral` | economy screens | `claimDaily()`, `seasonPass()`, `referral()` | `POST /rewards/*` |
| Friends/social | `Friend`, `FriendRequest` | `friends_screen.dart` | `friends()`, `requests()`, `suggested()`, `add/accept/decline/challenge()` | `GET/POST /friends/*` |
| Player profile | `PublicProfile` | `player_profile_screen.dart` | `player(id)`, `report()`, `block()` | `GET /users/:id` |
| Leaderboard | `RankEntry` | `leaderboard_screen.dart` | `board(scope)` | `GET /leaderboard` |
| Tournaments | `Tournament`, `Bracket` | `tournaments_screen.dart` | `list(state)`, `register()`, `recap()` | `GET/POST /tournaments/*` |
| Inbox | `InboxMessage` | `inbox_screen.dart` | `messages()`, `markAllRead()` | `GET/POST /inbox` |
| Matchmaking/match | `MatchConfig`, `MatchResult` | `online_play_sheet.dart`, `match/*` | `createMatch()`, `findMatch()`, `move()` | `POST /matches`, WS `/match/:id` |
| Games (live play) | board state per game | `games/*` | realtime channel | **WebSocket** (last, hardest) |
| Wheel | `WheelReward` | `wheel_screen.dart` | `spin()` | `POST /wheel/spin` |
| System | `AppConfig` | `maintenance`/`force_update` | `config()` on boot → gate to those screens | `GET /config` |

---

## 4. Loading / error / offline contract (reuse existing UI)

For every async screen, map the three states onto components we already built:

- **loading** → `LoadingSkeletonScreen` (or an inline `Shimmer` + `SkeletonBox`
  matching that screen's shape).
- **error** → `showAuraToast(context, msg, kind: AuraToastKind.error)`; for a
  full-screen failure, an inline retry state.
- **offline** → `AuraOfflineBanner` pinned in the screen's `Stack` when connectivity
  drops (add `connectivity_plus`); pause match flows.
- **empty** → the empty-state text pattern already used in Game history's filter.

With riverpod this is one `AsyncValue.when(data/loading/error)` per screen.

---

## 5. Auth (mockapi → real API)

1. `AuthService` wraps the endpoints; `Session` (ChangeNotifier/provider) holds
   `User?` + token, persisted with `flutter_secure_storage`.
2. `api_client` interceptor attaches the bearer token and handles 401 → refresh → retry
   → else bounce to `Routes.login`.
3. Route guard: on boot, `GET /config` first → if `maintenance`/`updateRequired`, push
   `Routes.maintenance` / `Routes.forceUpdate` (screens already exist); else check
   session → `home` or `login`.
4. Wire the currently-mock buttons: Login/Register/OTP/Reset "continue" call the
   service instead of `Navigator.push`, driving nav off the result.
5. **Never** hardcode secrets; base URL + keys via `--dart-define` / env.

---

## 6. Rollout phases (each independently shippable & reversible)

1. ✅ **Scaffold DONE** — `flutter_riverpod`/`dio`/`flutter_secure_storage`/
   `connectivity_plus` added; `ProviderScope` wraps the app; `data/`, `services/`,
   `state/` created with `ApiClient` (dio + interceptor + error mapping),
   `AppException`, `useRemoteSourcesProvider` (the static→remote switch),
   and `AsyncView`/`ErrorRetry` (shared loading/error state).
2. ✅ **Models + static sources — DONE.** Pattern is
   model → `sources/static/*` (+ `remote/*` ready) → repository (picks source via
   `useRemoteSourcesProvider`) → `FutureProvider` → screen consumes via `AsyncView`.
   **Migrated (UI + 46 tests unchanged):** Friends, Leaderboard, Game history,
   Tournaments, Inbox, **Store (wallet + packs)**, **Profile (via session)**.
   Power-ups/VIP catalogue + Profile analytics charts intentionally left static.
3. ✅ **Auth — DONE (mock phase).** `AuthService` (Static + Remote), `SessionController`
   (`Notifier<User?>`, `currentUserProvider`), best-effort `TokenStore` (secure
   storage), token wired into `ApiClient`. Wired: Login (email/pass/social/guest →
   `session.login` → home), OTP (`verifyOtp` → welcome), Settings logout
   (`signOut`), Edit profile Save (`updateProfile`). `restore()` exists for boot
   session-restore (not yet auto-called from Splash — Phase 4).
4. **Flip read domains to remote** — set `useRemoteSourcesProvider`/per-domain once
   endpoints exist (each already has a `Remote*Source`).
5. **Write actions** — purchase, claim daily, add/accept friend, challenge, register
   tournament, set avatar, save profile: replace toasts with real calls + optimistic UI.
   (Friends write methods already routed through `FriendsRepository`.)
6. **Realtime** — matchmaking + live game boards over WebSocket (largest; do last).
7. **Harden** — retries, cache/offline reads, analytics, error reporting.

---

## 7. Testing

- Repositories take an injected source → unit-test with a fake source.
- Widget/golden tests override providers with `StaticXSource` → the current 46 tests
  keep passing unchanged (goldens already tolerate the offline google_fonts path).
- Add contract tests per remote source against a mock server.

---

## 7b. Live API (dev) — from "Portal Gateway API" doc + probing (2026‑09‑29)

`http://169.58.184.121:30080/metrics` is the gateway's Prometheus endpoint. The real
API (142 endpoints under `/api/v1`; the doc is an index, not full JSON bodies):
- **Base URL:** `http://169.58.184.121:30080/api/v1`.
- **Health:** `/health` ok; `/health/deep` → `{postgres, redis, clickhouse: ok}`.
- **Auth scheme:** `Authorization: Bearer <access_token>` — **HS256 JWT, 15 min**;
  **refresh = opaque UUID, 7 days**, rotated via `/auth/refresh`. Every response carries
  an `X-Request-Id`. Auth rate limit 5/min per IP.
- **Envelopes:** error `{"error":"CODE","message":"…"}`; **list `{"data":[…],"total",
  "page","per_page","total_pages"}`** (remote list sources must unwrap `data`).
- **401 codes:** `UNAUTHORIZED`, `INVALID_CREDENTIALS`, `TOKEN_EXPIRED`, `TOKEN_BLACKLISTED`.
- **Backend:** Rust/serde → **snake_case** JSON.

### Account & sign-in endpoints (confirmed)
- `POST /auth/register` (public) — new account → access+refresh pair.
- `POST /auth/login` (public) `{email,password}` → token pair.
- `POST /auth/refresh` (public) `{refresh_token}` → new pair (rotation).
- `POST /auth/logout` (bearer) — ends the session (blacklists tokens).
- `POST /auth/change-password` (bearer) — needs current password; signs out all sessions.
- `POST /guest/create`, `POST /guest/convert`; `POST /otp/send`+`/otp/verify` (bearer,
  503 outside debug); `GET/DELETE /sessions`, `GET/POST/DELETE /devices`.
- **Current user:** `GET /api/v1/users/me`; profile: `PATCH /api/v1/users/me/profile`,
  `GET /api/v1/users/{id}/profile`. (There is **no public forgot-password** endpoint.)

### Auth wiring status — DONE (configured to the above)
`AuthResult` carries access+refresh; `RemoteAuthService` parses the pair (tolerant of
`access_token`/`token` names) and fetches the user from `/users/me` when the login body
has no embedded user; `refresh()` rotates; `TokenStore` persists both; `SessionController`
keeps the refresh token + `refreshSession()`; `ApiClient` preserves the `/api/v1` base
and only fires session-expired on an authenticated 401. `User.fromJson` accepts snake or
camel case.

**Remaining before flipping `useRemoteSourcesProvider` on:**
1. `--dart-define=API_BASE_URL=http://169.58.184.121:30080/api/v1` (done: documented).
2. Android cleartext scoped to the IP (done: `network_security_config.xml`).
3. **Non-auth domains** (friends/leaderboard/wallet/store/tournaments/inbox/history):
   their `Remote*Source`s still expect bare arrays + guessed field names. They need the
   **list `{data:[…]}` unwrap** and real field names — pending exact JSON (a token to read
   `/friends` etc., or the detailed schema). Auth can be verified now with a token.

## 8. Open decisions (need a call before Phase 1)

1. **State management:** riverpod (recommended) vs provider+ChangeNotifier.
2. **HTTP:** dio (recommended) vs http.
3. **Real API shape:** confirm base URL, auth scheme, and the endpoint list in §3.
4. **Realtime transport** for live games: WebSocket vs polling.
