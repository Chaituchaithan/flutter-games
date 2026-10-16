# Test cases

Manual QA checklist for the app, plus where the automated tests live.
Run it on a **release build on a real phone** before a demo or a release
(`flutter build apk --release`; see `RUN_AND_TEST.md`).

**How to use**
- Status: ✅ pass · ❌ fail · ⏸ blocked · blank = not run. Write the date and
  device in the run log at the bottom.
- Add a case: append a row to the right section with the next ID
  (e.g. `AUTH-12`). Keep steps short and the expected result checkable.
- A failing case: put ❌, then a short note (what you saw) in *Notes*.

---

## 1. Startup and sign-in (AUTH)

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| AUTH-01 | First launch | Fresh install → open | Splash bar fills, Language picker, intro, then Login | | |
| AUTH-02 | Login screen layout | Open Login | No back button, logo right under the status bar, no empty gap at the top | | |
| AUTH-03 | Email login | Enter a valid email + password → Log in | Home opens; your name and initials in the header (never "NR") | | |
| AUTH-04 | Wrong password | Valid email, wrong password | Error on screen, stays on Login, no "Session expired" dialog | | |
| AUTH-05 | Guest login | Tap "Play as guest" | Home opens as a guest; Change password is hidden in Settings | | |
| AUTH-06 | Register | Login → Create account → fill in → Create | "Account created" toast, back on the **same** Login (no second Login underneath) | | |
| AUTH-07 | Register → Sign in link | Register → tap "Sign in" | Returns to the existing Login | | |
| AUTH-08 | Reset password → back | Login → Forgot password → "Back to login" | Returns to the existing Login | | |
| AUTH-09 | Double-tap protection | Tap Log in twice quickly / Guest then Create account | Only one request; no duplicate screens | | |
| AUTH-10 | Saved session | Log in → close app → reopen | Straight to Home; name/level shown at once (saved profile) | | |
| AUTH-11 | Offline start with saved session | Log in, close app, airplane mode on, reopen | Home opens with the saved profile; no sign-out | | |
| AUTH-12 | Release build reaches the server | Release APK on a real phone (not the emulator) | Login works; no request goes to `10.0.2.2` / the dev proxy | | |

## 2. Session and token refresh (SESSION)

Access token lives 15 min; refresh token 7 days (rotated on every refresh).

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| SESSION-01 | Silent refresh on an API call | Log in, wait > 15 min with the app open, then open Profile → pull to refresh | Data loads; no sign-out, no dialog (401 → refresh → retried once) | | |
| SESSION-02 | Socket reconnect after expiry | Log in, wait > 15 min, turn Wi-Fi off/on (socket reconnects) | Socket signs in again with a fresh token; online play still works | | |
| SESSION-03 | App start with expired access token | Log in, close the app for > 15 min (< 7 days), reopen | Home opens signed in (token refreshed in the background) | | |
| SESSION-04 | Refresh token no longer valid | Sign in on one phone, change password on another / wait > 7 days, then use the app | "Session expired" dialog once → Log in again → Login screen | | |
| SESSION-05 | Logout | Settings → Log out | Login screen; reopening the app shows Login; saved profile is gone | | |
| SESSION-06 | Change password | Settings → Change password → valid new password | Signed out everywhere, back to Login, can log in with the new password | | |

## 3. Home (HOME)

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| HOME-01 | Balance pills | Open Home | Tokens and Gold from `/wallet/balance`; both pills the same width; "—" only while loading | | |
| HOME-02 | Daily bonus after login | Log in when today's bonus is unclaimed | Daily Rewards opens by itself once; not when already claimed | | |
| HOME-03 | Game chips | All-games build | 12 games listed; tapping one switches the Home actions to it | | |
| HOME-04 | Quick Play | Tap Quick Play | The active game's setup / table opens | | |
| HOME-05 | Online Play | Chess active → Online Play | Stake sheet with real balance; preview shows your initials | | |
| HOME-06 | No Earn Rewards / Recent matches | Open Home | Those sections are not shown | | |

## 4. Wallet and services (SVC)

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| SVC-01 | No duplicate calls on tab switch | Switch Home ↔ Wheel ↔ Store ↔ Profile repeatedly (watch the proxy/logs) | No `/users/me`, profile, balance or daily-bonus call per switch | | |
| SVC-02 | No calls while scrolling Profile | Scroll Profile up and down | No daily-bonus status calls | | |
| SVC-03 | Balance refresh after claim | Claim the daily bonus | Balance updates on Home, Store and Wheel together | | |
| SVC-04 | Back from background | Leave the app > 30 s, return | One balance refresh; after > 5 min also one profile refresh | | |
| SVC-05 | Brief interruption | Pull down the notification shade, close it | No refetch | | |

## 5. Profile and settings (PROF)

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| PROF-01 | Manage section | Profile → Manage | Game History and Daily Bonus tiles (live countdown / "Day N ready") | | |
| PROF-02 | Edit profile | Edit name, bio, DOB, language, country → Save | Saved; returns to Profile; header shows the new name | | |
| PROF-03 | Settings rows | Open Settings | No Haptics, Avatar or Game History rows; no Demo states in release | | |
| PROF-04 | Language | Settings → Language → Hindi | Translated screens switch to Hindi; saved to the profile | | |

## 6. Store, Wheel, Invite friends (ECO)

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| ECO-01 | Store | Open each tab | No top banners in Tokens / Gold / Boosts; VIP plans from the API | | |
| ECO-02 | Wheel layout | Open Wheel | Wheel centred; pills aligned with the Store's (no shift when switching tabs) | | |
| ECO-03 | Spin | Tap SPIN | Jewel button presses in; pointer flicks on pegs; wheel slows naturally | | |
| ECO-04 | Win message | After a spin | "You won …" shows, then fades after 3 s | | |
| ECO-05 | Invite code | Settings → Invite friends | Real code from `/referrals/my-code`; tap copies it ("Code copied") | | |
| ECO-06 | Share invite | Tap Share invite | System share sheet with the invite message and code | | |
| ECO-07 | Referral stats | Same screen | Friends joined / Rewards earned from `/referrals/stats`; empty-state text at 0 | | |

## 7. Games (GAME)

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| GAME-01 | Chess Quick Play | Setup → Medium → play a few moves | Board large and centred; clock + You above "Your move"; smooth piece glide; no card glow flash; board never shifts | | |
| GAME-02 | Chess think time | Easy / Medium / Hard | Computer waits ~2–3.5 s / 3–5.5 s / 4–8 s (faster in the opening) | | |
| GAME-03 | Online chess | Online Play → match | Opponent found or 60 s timeout; result refreshes balance | | |
| GAME-04 | Ludo / Snakes & Ladders | Quick Play, 2–4 players | Dice animation, moves, result screen with your initials | | |
| GAME-05 | Othello / Checkers / Scrabble | Quick Play | Board centred and large; computer replies; result screen | | |
| GAME-06 | Crash | Bet → cash out | Coin + confetti burst, "CASHED OUT" banner, balance counts up; crash flash + shake | | |
| GAME-07 | Bingo | Quick Play, 4 players | Whole card visible (no cut-off); blower, "1 TO GO", daub stamp, win celebration | | |
| GAME-08 | Roulette | Place chips (straight, split, corner, red) → SPIN | Ball settles in the drawn pocket; correct payout; Repeat / Double work | | |
| GAME-09 | Poker | 4 players → play hands | Blinds move; Check / Call / Raise / Fold; side pots; pot slides to the winner | | |
| GAME-10 | Racing | Bet Win + Top 3 → Start race | Camera follows the leader; standings re-order; podium + payout | | |
| GAME-11 | Rummy | Draw → Sort → Discard; then Declare | Groups labelled; invalid declare warns (80 pts); valid declare wins | | |
| GAME-12 | Pause / forfeit | Pause in any vs-computer game → Forfeit | Confirm dialog; defeat result screen | | |

## 8. Release checks (REL)

| ID | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|
| REL-01 | Clean install | Uninstall old app → install the APK | Opens; fonts and icons load offline | | |
| REL-02 | No debug UI | Browse Settings | No Demo states section | | |
| REL-03 | Weak network | Throttle / mobile data | Skeletons and Retry instead of blank screens | | |
| REL-04 | Single-game app | `-t lib/main_<game>.dart` build | Only that game; no game picker | | |

---

## Automated tests

`flutter test` (all) · `flutter analyze` must be clean. Currently 208 tests.

| Area | Files |
|---|---|
| Sign-in, session, refresh | `startup_test`, `login_busy_guard_test`, `jwt_expiry_test`, `profile_service_test` (401 → refresh → retry), `user_api_test`, `auth_parse_test`, `change_password_validation_test` |
| Socket | `socket_client_test` (reconnect with a fresh token), `app_socket_test`, `matchmaking_live_test` |
| Services | `daily_bonus_test`, `vip_plans_test`, `configs_test` |
| Screens | `screens_smoke_test`, `interaction_test`, `flow_test`, `text_field_focus_test`, `widget_test` |
| Games (rules) | `chess_engine_test`, `chess_bot_test`, `chess_clock_test`, `chess_session_test`, `chess_game_flow_test`, `dice_games_engine_test`, `othello_engine_test`, `checkers_engine_test`, `scrabble_engine_test`, `crash_engine_test`, `bingo_engine_test`, `roulette_engine_test`, `poker_engine_test`, `racing_engine_test`, `rummy_engine_test` |
| Structure | `game_isolation_test` (no game imports another), `l10n_test` (Hindi has every English key), `languages_test` |

---

## Run log

| Date | Build | Device | Tester | Result |
|---|---|---|---|---|
| | | | | |
