# Test cases

Manual QA checklist for the app and every game, with **positive** cases (it
works) and **negative** cases (wrong input, edge cases and failures are handled
well), plus where the automated tests live. Run it on a **release build on a
real phone** before a demo or a release (`flutter build apk --release`; see
`RUN_AND_TEST.md`).

**How to use**
- **Type:** ✅ positive · ❌ negative.
- **Status:** ✅ pass · ❌ fail · ⏸ blocked · blank = not run. Write the date
  and device in the run log at the bottom.
- **Add a case:** append a row to the right section with the next ID
  (e.g. `AUTH-21`). Keep steps short and the expected result checkable.
- **A failing case:** put ❌ in Status, then a short note (what you saw) in
  *Notes*.

**Contents:** 1 Sign-in · 2 Session · 3 Home · 4 Services · 5 Profile &
Settings · 6 Store, Wheel, Daily rewards, Invite · 7 General · 8 Games
(Chess, Ludo, Snakes & Ladders, Othello, Checkers, Scrabble, Crash, Bingo,
Roulette, Poker, Racing, Rummy, all games) · 9 Release · Automated tests ·
Run log

---

## 1. Startup and sign-in (AUTH)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| AUTH-01 | ✅ | First launch | Fresh install → open | Splash bar fills, Language picker (no back button), intro, then Login | | |
| AUTH-02 | ✅ | Login screen layout | Open Login | No back button; logo right under the status bar; no empty gap at the top | | |
| AUTH-03 | ✅ | Email login | Valid email + password → Log in | Home opens; your name and initials in the header (never "NR") | | |
| AUTH-04 | ✅ | Guest login | Tap "Play as guest" | Home opens as a guest; Change password hidden in Settings | | |
| AUTH-05 | ✅ | Register | Login → Create account → fill in → Create | "Account created" toast, back on the **same** Login (no second Login underneath) | | |
| AUTH-06 | ✅ | Register screen layout | Open Register | No back button; "Create account" heading at the same height as Login | | |
| AUTH-07 | ✅ | Register → Sign in link | Register → tap "Sign in" | Returns to the existing Login | | |
| AUTH-08 | ✅ | Back gesture on Register / Reset | Phone back gesture | Returns to Login | | |
| AUTH-09 | ✅ | Reset password | Forgot password → email → code → new password | Password changed; "Back to login" returns to the existing Login | | |
| AUTH-10 | ✅ | Saved session | Log in → close app → reopen | Straight to Home; name / level shown at once | | |
| AUTH-11 | ✅ | Release build reaches the server | Release APK on a real phone | Login works; no request to `10.0.2.2` / the dev proxy | | |
| AUTH-12 | ❌ | Wrong password | Valid email, wrong password | Error shown, stays on Login, no "Session expired" dialog | | |
| AUTH-13 | ❌ | Unknown email | Email that has no account | Clear error; stays on Login | | |
| AUTH-14 | ❌ | Empty / invalid fields | Log in with empty fields; email without "@" | Field errors under the inputs; no request sent | | |
| AUTH-15 | ❌ | Register: email already used | Register with an existing email | Clear error; stays on Register, entries kept | | |
| AUTH-16 | ❌ | Register: weak password / terms unticked | Short password; terms not accepted | Field error / prompt; no account created | | |
| AUTH-17 | ❌ | Double-tap protection | Tap Log in twice fast; Guest then Create account | One request only; no duplicate screens | | |
| AUTH-18 | ❌ | No internet at login | Airplane mode → Log in | "You're offline" message; stays on Login; works after reconnecting | | |
| AUTH-19 | ❌ | Server down / slow | Server unreachable → Log in / open app | Friendly error with Retry; no crash, no endless spinner | | |
| AUTH-20 | ❌ | Offline start with saved session | Log in, close app, airplane mode, reopen | Home with the saved profile; no sign-out | | |

## 2. Session and token refresh (SESSION)

Access token lives 15 min; refresh token 7 days (rotated on every refresh).

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| SESSION-01 | ✅ | Silent refresh on an API call | Log in, wait > 15 min, Profile → pull to refresh | Data loads; no sign-out, no dialog | | |
| SESSION-02 | ✅ | Socket reconnect after expiry | Wait > 15 min, Wi-Fi off/on | Socket signs in again with a fresh token; online play works | | |
| SESSION-03 | ✅ | App start with expired access token | Close app > 15 min (< 7 days), reopen | Home opens signed in | | |
| SESSION-04 | ✅ | Logout | Settings → Log out | Login screen; reopening shows Login; saved profile gone | | |
| SESSION-05 | ✅ | Change password | Settings → Change password → valid new password | Signed out everywhere; can log in with the new password | | |
| SESSION-06 | ❌ | Refresh token no longer valid | Change password on another phone / wait > 7 days, then use the app | "Session expired" dialog **once** → Log in again | | |
| SESSION-07 | ❌ | Change password: wrong current password | Enter a wrong current password | Error on that field; **not** signed out | | |
| SESSION-08 | ❌ | Change password: mismatch / same as old | Confirmation differs; new = current | Field errors; nothing sent | | |
| SESSION-09 | ❌ | Many calls fail together | Expire the token, open a screen that makes several calls | One refresh only; all calls retried once | | |

## 3. Home (HOME)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| HOME-01 | ✅ | Balance pills | Open Home | Tokens and Gold from `/wallet/balance`; same width; "—" only while loading | | |
| HOME-02 | ✅ | Daily bonus after login | Log in with today's bonus unclaimed | Daily Rewards opens by itself once | | |
| HOME-03 | ✅ | Game chips | All-games build | One row scrolling to the screen edges; tapping a game switches Home to it | | |
| HOME-04 | ✅ | Quick Play | Tap Quick Play | The active game's setup / table opens | | |
| HOME-05 | ✅ | Online Play | Chess → Online Play | Stake sheet with the real balance; preview shows your initials | | |
| HOME-06 | ✅ | Bottom bar | Any phone (gesture bar, 3-button, iPhone) | Bar sits just above the phone's own bottom area; nothing overlaps | | |
| HOME-10 | ✅ | Single-game Home (e.g. `main_chess.dart`) | Open Home on a normal phone | No game list; small gap under the player bar; Online Play, Quick Play + Friends, Tournaments and the banner fill the screen with no scrolling | | |
| HOME-11 | ✅ | Single-game Home on a tall phone | Open Home on a large phone | Cards keep their normal size (not stretched); the slim ad strip sits just above the bottom bar, spare space above it | | |
| HOME-12 | ❌ | Single-game Home on a short phone | Open Home on a small phone | The banner drops first; if still too short the page scrolls; nothing cut off | | |
| HOME-07 | ❌ | Daily bonus already claimed | Log in again the same day | Daily Rewards does **not** open | | |
| HOME-08 | ❌ | Online Play for a game without it | Ludo active → Online Play | "Coming soon" message; no blank screen | | |
| HOME-09 | ❌ | Balance call fails | Server error on `/wallet/balance` | Pills show "—"; no crash; fills in on the next refresh | | |

## 4. Wallet and services (SVC)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| SVC-01 | ✅ | Balance refresh after claim | Claim the daily bonus | Balance updates on Home, Store and Wheel together | | |
| SVC-02 | ✅ | Back from background | Leave > 30 s, return | One balance refresh; after > 5 min also one profile refresh | | |
| SVC-03 | ❌ | No duplicate calls on tab switch | Switch tabs repeatedly (watch the logs) | No `/users/me`, profile, balance or daily-bonus call per switch | | |
| SVC-04 | ❌ | No calls while scrolling | Scroll Profile up and down | No daily-bonus status calls | | |
| SVC-05 | ❌ | Brief interruption | Pull the notification shade down and up | No refetch | | |
| SVC-06 | ❌ | Failed call isn't retried silently | Make `/wallet/balance` fail | One call only; no repeated retries in the logs | | |

## 5. Profile and settings (PROF)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| PROF-01 | ✅ | Manage section | Profile → Manage | Game History and Daily Bonus tiles (live countdown / "Day N ready") | | |
| PROF-02 | ✅ | Edit profile | Edit name, bio, DOB, language, country → Save | Saved; back to Profile; header shows the new name | | |
| PROF-03 | ✅ | Settings rows | Open Settings | No Haptics, Avatar or Game History rows; no Demo states in release | | |
| PROF-04 | ✅ | Language | Settings → Language → Hindi | Screens switch to Hindi; saved to the profile; "← Language" returns | | |
| PROF-05 | ✅ | Pull to refresh | Profile → pull down | Fresh profile; spinner closes | | |
| PROF-06 | ❌ | Edit profile: empty name / too young | Clear the name; DOB under 13 | Field errors; not saved | | |
| PROF-07 | ❌ | Save while offline | Airplane mode → Save | Error message; your edits stay on screen | | |

## 6. Store, Wheel, Daily rewards, Invite friends (ECO)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| ECO-01 | ✅ | Store tabs | Open Tokens / Gold / Boosts / VIP | No top banners; VIP plans from the API | | |
| ECO-02 | ✅ | Wheel layout | Open Wheel | Wheel centred; pills aligned with the Store's | | |
| ECO-03 | ✅ | Spin | Tap SPIN | Jewel button presses in; pointer flicks on pegs; wheel slows naturally | | |
| ECO-04 | ✅ | Win message | After a spin | "You won …" shows, fades after 3 s | | |
| ECO-05 | ✅ | Jackpot | Land on JACKPOT | Rim lights flash gold, golden rays, coin shower, "JACKPOT!" shout, strong vibration — only for the jackpot | | |
| ECO-06 | ✅ | Daily reward claim | Daily Rewards → Claim | Toast with the real payout; streak and balance update | | |
| ECO-07 | ✅ | Invite code | Settings → Invite friends | Code from `/referrals/my-code`; tap copies it ("Code copied") | | |
| ECO-08 | ✅ | Share invite | Share invite | System share sheet with the message and code | | |
| ECO-09 | ✅ | Referral stats | Same screen | Friends joined / Rewards earned from `/referrals/stats` | | |
| ECO-10 | ❌ | Spin with no spins left | Use all 3 spins | SPIN greyed; "No spins left — come back tomorrow" | | |
| ECO-11 | ❌ | Daily reward claimed twice | Claim, then try again | "Already claimed"; countdown to the next one | | |
| ECO-12 | ❌ | VIP subscribe (billing not live) | Store → VIP → Subscribe | "VIP subscriptions are coming soon"; nothing charged | | |
| ECO-13 | ❌ | Invite code expired / used up | Server returns an expired or full code | Code struck through, message shown, Share disabled | | |
| ECO-14 | ❌ | Referral calls fail | Offline → open Invite friends | Skeleton, then "Couldn't load…" with Retry | | |
| ECO-15 | ❌ | Zero referrals | New account | "No friends have joined yet — share your code…" | | |

## 7. General (GEN)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| GEN-01 | ✅ | Portrait only | Rotate the phone to landscape on every screen and in every game | Stays in portrait; nothing re-lays out or breaks | | |
| GEN-08 | ✅ | Wide window (Chrome, macOS, tablet) | Run on web / desktop, or a tablet in landscape | The app keeps its phone layout, centred, with dark side bars; nothing stretches | | |
| GEN-02 | ✅ | Hindi | Switch to Hindi, open each screen | Texts translated (English only where not yet translated) | | |
| GEN-03 | ✅ | Small and large phones | 5" phone and a large phone | No cut-off boards or cards; nothing overflows | | |
| GEN-04 | ❌ | Rotation lock on with auto-rotate on | Auto-rotate on, rotate during a game | Game keeps playing in portrait; no restart | | |
| GEN-05 | ❌ | Lose network mid-session | Airplane mode while on Home / Store | Offline banner; Retry; no crash | | |
| GEN-06 | ❌ | App killed in the background | Background the app, let the OS kill it, reopen | Opens on Home (saved session); no stale dialogs | | |
| GEN-07 | ❌ | Large text (accessibility font size) | Phone font size at maximum | Texts still fit (ellipsis where needed); no overlaps | | |

## 8. Games

### 8.1 Chess (CHESS)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| CHESS-01 | ✅ | Quick Play | Setup → side, difficulty, time → Start | Board large, centred, clean squares; clock + You above "Your move" | | |
| CHESS-02 | ✅ | Moves | Tap a piece → tap a target | Legal targets shown; smooth glide; captured piece fades; castling moves the rook | | |
| CHESS-03 | ✅ | Computer think time | Easy / Medium / Hard | ~2–3.5 s / 3–5.5 s / 4–8 s (faster in the opening) | | |
| CHESS-04 | ✅ | Promotion | Push a pawn to the last rank | Promotion picker; chosen piece appears | | |
| CHESS-05 | ✅ | Checkmate / stalemate | Reach either | Result screen: Victory / Defeat / Draw with the right subtitle; no XP chip | | |
| CHESS-06 | ✅ | 3D toggle | Tap the 3D button | Board tilts; taps still land on the right squares | | |
| CHESS-07 | ✅ | Online match | Online Play → stake → match | Opponent found; board glows purple on your move, blue on theirs; result refreshes balance | | |
| CHESS-08 | ✅ | Online draw offer | Opponent offers a draw | Accept / Decline buttons (same height as the action bar) | | |
| CHESS-09 | ❌ | Illegal move | Tap a square the piece can't reach | Nothing moves; selection changes or clears | | |
| CHESS-10 | ❌ | Move while in check | Try a move that leaves the king in check | Not allowed | | |
| CHESS-11 | ❌ | Time runs out | Let your clock reach 0 | You lose on time; correct subtitle | | |
| CHESS-12 | ❌ | Not your turn | Tap pieces while the computer thinks | Nothing happens | | |
| CHESS-13 | ❌ | No opponent found | Online Play → search 60 s | "No match found" with options; stake not lost | | |
| CHESS-14 | ❌ | Stake higher than balance | Pick a stake above your balance | "Not enough balance" dialog → Store | | |
| CHESS-15 | ❌ | Socket drops mid-game | Wi-Fi off/on during an online game | Reconnects and resumes, or a clear message | | |
| CHESS-16 | ❌ | Forfeit | Pause → Forfeit → confirm | Defeat result; "Keep playing" resumes instead | | |

### 8.2 Ludo (LUDO)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| LUDO-01 | ✅ | Quick Play | Setup → players, colour, time → Start | Board centred; banner above the board (not over it) | | |
| LUDO-02 | ✅ | Your turn | Wait for your turn | "YOUR TURN · tap the dice", "TAP" under the die, soft glow in your colour around the board, short vibration | | |
| LUDO-03 | ✅ | Roll and pick | Roll a 6 | "Rolling…" → "You rolled 6 · tap a pawn"; tap a pawn to move | | |
| LUDO-04 | ✅ | Computer turn | Watch a computer | Glow switches to its colour; "Nova rolled 3"; die keeps its number badge | | |
| LUDO-05 | ✅ | Capture | Land on an opponent | It flies back to its base | | |
| LUDO-06 | ✅ | Pawns sharing a square (2D) | Stack pawns | Shrink and line up; all visible; lone pawn stays in its square | | |
| LUDO-07 | ✅ | Base pawns (2D) | Start of game | Each waiting pawn sits inside its circle | | |
| LUDO-08 | ✅ | 3D | Toggle 3D | Original pawn placement | | |
| LUDO-09 | ✅ | Win | Bring all four home | Victory result; no XP chip | | |
| LUDO-10 | ❌ | No move possible | Roll without a 6 with all pawns in base | Turn passes ("no move"); no freeze | | |
| LUDO-11 | ❌ | Tap a pawn that can't move | Tap a blocked / base pawn on a non-6 | Nothing happens | | |
| LUDO-12 | ❌ | Time runs out | Let the turn clock reach 0 | The app rolls / moves for you ("Time's up") | | |
| LUDO-13 | ❌ | Tap the die when it's not your turn | Tap during a computer turn | Nothing happens | | |

### 8.3 Snakes & Ladders (SNAKES)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| SNAKES-01 | ✅ | Quick Play | Setup → Start | Board centred; readable square numbers; banner above the board | | |
| SNAKES-02 | ✅ | Your turn | Wait for your turn | "YOUR TURN · tap the dice", "TAP", soft glow in your colour, vibration | | |
| SNAKES-03 | ✅ | Roll | Roll | "Rolling…" → "You rolled 5"; badge stays on the die | | |
| SNAKES-04 | ✅ | Ladder / snake | Land on one | Pawn climbs rung by rung / slides along the snake | | |
| SNAKES-05 | ✅ | Pawns sharing a square (2D) | Stack 2–4 pawns | Shrink and line up; all visible | | |
| SNAKES-06 | ✅ | 3D | Toggle 3D | Original pawn placement | | |
| SNAKES-07 | ✅ | Win | Reach 100 | Victory result; no XP chip | | |
| SNAKES-08 | ❌ | Overshoot 100 | Need 3, roll 5 | Pawn shakes in place ("can't move"); turn passes | | |
| SNAKES-09 | ❌ | Time runs out | Let the turn clock reach 0 | The app rolls for you | | |
| SNAKES-10 | ❌ | Tap the die when it's not your turn | Tap during a computer turn | Nothing happens | | |

### 8.4 Othello (OTH)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| OTH-01 | ✅ | Quick Play | Start; tap a hinted square | Discs flip; computer replies | | |
| OTH-02 | ✅ | Game end | Fill the board | Result with the disc counts | | |
| OTH-03 | ❌ | Illegal square | Tap a square that flips nothing | Nothing happens | | |
| OTH-04 | ❌ | No legal move | Reach a position where you can't move | Your turn is passed automatically, with a message | | |

### 8.5 Checkers (CHK)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| CHK-01 | ✅ | Quick Play | Start; move a piece | Diagonal move; computer replies | | |
| CHK-02 | ✅ | Capture / multi-jump / king | Jump, chain jumps, reach the last row | Pieces removed; chain continues; piece crowned | | |
| CHK-03 | ❌ | Skip a forced capture | Try a plain move when a capture exists | Not allowed | | |
| CHK-04 | ❌ | Move backwards (not a king) | Try it | Not allowed | | |

### 8.6 Scrabble (SCR)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| SCR-01 | ✅ | Play a word | Place tiles → Play | Word accepted; score added; rack refills | | |
| SCR-02 | ✅ | Swap / pass | Swap tiles; pass | Turn passes correctly | | |
| SCR-03 | ❌ | Invalid word | Place a non-word | "Not a word" message; tiles stay | | |
| SCR-04 | ❌ | Tiles not in one line / not connected | Place them scattered | Clear error; nothing scored | | |

### 8.7 Crash (CRASH)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| CRASH-01 | ✅ | Bet and cash out | Bet in the window → Cash out while flying | Coin + confetti burst, "CASHED OUT" banner, balance counts up | | |
| CRASH-02 | ✅ | Auto cash-out | Turn on auto at 2.00x | Cashes out at 2.00x by itself | | |
| CRASH-03 | ✅ | Two bets | Use both panels | Each settles on its own | | |
| CRASH-04 | ❌ | Crash before cash-out | Hold until it flies away | Bet lost; red flash + shake | | |
| CRASH-05 | ❌ | Bet during a flight | Tap Bet while flying | Queued for the next round ("Cancel next round") | | |
| CRASH-06 | ❌ | Not enough chips | Bet more than the balance | Bet not placed | | |
| CRASH-07 | ❌ | Out of chips | Lose everything | "Top up" offer restores practice chips | | |

### 8.8 Bingo (BINGO)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| BINGO-01 | ✅ | Quick Play | Start | Whole card visible; blower; called-board on tap | | |
| BINGO-02 | ✅ | Daub and win | Mark called numbers → BINGO! | Winning cells light up, confetti; Victory | | |
| BINGO-03 | ✅ | Auto-daub | Turn it on | Called numbers are marked by themselves | | |
| BINGO-04 | ❌ | False BINGO | Tap BINGO! without a pattern | "Not yet" and claims lock for 4 s | | |
| BINGO-05 | ❌ | Tap a number not called | Tap it | Nothing happens | | |
| BINGO-06 | ❌ | Computer wins first | Let a computer complete first | Its "… called BINGO!" banner; Defeat | | |

### 8.9 Roulette (ROUL)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| ROUL-01 | ✅ | Bets and spin | Straight, split, corner, red → SPIN | Ball settles in the drawn pocket; correct payout; winning chips glow | | |
| ROUL-02 | ✅ | Undo / Clear / Double / Repeat | Use each | Table and balance update correctly | | |
| ROUL-03 | ❌ | Spin with no bets | Tap SPIN | "Place your bets" message | | |
| ROUL-04 | ❌ | Chip bigger than the balance | Pick a 1K chip with less | "Not enough chips" | | |
| ROUL-05 | ❌ | Table limit | Bet above 10,000 in total | "Table limit reached" | | |
| ROUL-06 | ❌ | Zero | Result 0 with only outside bets | All outside bets lose | | |

### 8.10 Poker (POKER)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| POKER-01 | ✅ | A hand | Play Check / Call / Raise / Fold | Blinds move; cards dealt and turned; pot slides to the winner | | |
| POKER-02 | ✅ | Raise panel | Min / ½ Pot / Pot / All-in / slider | Amount follows; button shows "Raise to …" | | |
| POKER-03 | ✅ | Showdown / split | Reach showdown | Winning cards outlined; split pots shared | | |
| POKER-04 | ✅ | Win the table | Take every chip | Victory | | |
| POKER-05 | ❌ | Time runs out | Let your timer reach 0 | Auto check, or fold when facing a bet | | |
| POKER-06 | ❌ | All-in short stack | Go all-in for less than the call | Side pot; you win at most what you covered | | |
| POKER-07 | ❌ | Bust out | Lose all chips | Defeat ("You ran out of chips") | | |

### 8.11 Racing (RACE)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| RACE-01 | ✅ | Bet and race | Win + Top 3 bets → Start race | Camera follows the leader; standings re-order; podium + payout | | |
| RACE-02 | ✅ | Watch without betting | Start with no bets | Race runs; no payout line | | |
| RACE-03 | ❌ | Bet more than the balance | Tap odds with too big a chip | "Not enough chips" | | |
| RACE-04 | ❌ | Losing bets | Bet on a car that finishes 4th+ | "No win this time"; balance unchanged | | |

### 8.12 Rummy (RUMMY)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| RUMMY-01 | ✅ | Draw and discard | Pick from closed / open deck → select → Discard | Card moves; turn passes | | |
| RUMMY-02 | ✅ | Sort / Group | Tap Sort; select cards → Group | Groups labelled Pure sequence / Sequence / Set / Invalid | | |
| RUMMY-03 | ✅ | Valid declare | Two sequences (one pure), all melded → Declare | "Valid show" → Victory | | |
| RUMMY-04 | ❌ | Invalid declare | Declare without a pure sequence | Warning (80 points); confirming = wrong show, Defeat | | |
| RUMMY-05 | ❌ | Discard before drawing | Try to discard first | Not allowed; draw hint shown | | |
| RUMMY-06 | ❌ | Drop | Drop before / after drawing | 20 / 40 points; Defeat | | |
| RUMMY-07 | ❌ | Time runs out | Let the timer reach 0 | Draws from the closed deck and throws that card | | |

### 8.13 All games (ALL)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| ALL-01 | ✅ | Pause | Pause in any vs-computer game | Clock and computer stop; Resume continues | | |
| ALL-02 | ✅ | Play again | Result → Play again | Same settings, new game | | |
| ALL-03 | ✅ | Quick Play result | Finish any vs-computer game | No XP / reward chip | | |
| ALL-04 | ❌ | Forfeit and cancel | Pause → Forfeit → Keep playing | Game resumes where it was | | |
| ALL-05 | ❌ | Background mid-game | Home button during a game, come back | Game still there (paused or continuing); no crash | | |

## 9. Release checks (REL)

| ID | Type | Scenario | Steps | Expected | Status | Notes |
|---|---|---|---|---|---|---|
| REL-01 | ✅ | Clean install | Uninstall old app → install the APK | Opens; fonts and icons load offline | | |
| REL-02 | ✅ | Single-game app | `-t lib/main_<game>.dart` build | Only that game; no game picker | | |
| REL-03 | ❌ | No debug UI | Browse Settings | No Demo states section | | |
| REL-04 | ❌ | Weak network | Throttle / mobile data | Skeletons and Retry instead of blank screens | | |

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
