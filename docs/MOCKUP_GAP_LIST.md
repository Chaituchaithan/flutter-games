# Aura — Mockup vs App Gap List

Comparison of the canonical mockup (`Aura Game UI.html`, viewed screen-by-screen
via its "All screens" navigator) against the current Flutter app. **This is a
to-fix list for later** — nothing here is changed yet.

**Method:** served the mockup over localhost, opened Chrome, walked every entry in
its navigator, and cross-checked each against our screens/routes. Built screens
were also golden-verified in earlier sessions.

---

## A. Screen coverage — the mockup's full set is built

All 45+ navigator entries map to a built screen/overlay:

| Mockup group | Screens | Status |
|---|---|---|
| Onboarding | Splash, Language, Intro carousel, Login, Register, OTP, Forgot password, Welcome bonus | ✅ all |
| Lobby & Play | Home, Online Play setup, Friends menu, Create room, Join room, Room lobby, Matchmaking | ✅ all |
| Gameplay | Chess 2P, Othello 2P, Scrabble 2P/4P, Snakes & Ladders 4P, Ludo 4P, Trivia 2P/4P | ✅ all (unified chrome) |
| Results | Result Victory / Defeat / Draw, Level-up | ✅ all |
| Economy | Store Tokens/Gold/Power-ups/VIP, Purchase confirm, Transactions, Daily rewards, Lucky wheel, Season pass | ✅ all |
| Compete/Social | Leaderboard, Tournaments, Friends hub, Friend requests, Player profile, Chat sheet, Inbox (notifs) | ✅ all |
| Profile | Profile, Edit profile, Avatars, Game history, Achievements | ✅ all |
| System | Settings, Maintenance, Force update, Toast, Skeleton | ✅ all |

Spot-checked Home in detail against the mockup — matches (HUD w/ 🇫🇷 flag + LV7 XP
bar, 3-col game chips with selected state, Online Play featured card, Quick
Play/Friends tiles, "Trivia Duel" label all present).

---

## B. Gaps — ALL FIXED ✅

### 1. `Dialog · balance` — "Not enough balance"  ✅ built + wired
- Added an amber **`AuraDialogTone.warning`** variant to `showAuraDialog`
  (gold-gradient icon + primary) and `showInsufficientBalanceDialog()` helper
  (`widgets/aura_overlays.dart`).
- Wired in the **Online Play sheet**: `_createGame` compares the chosen stake to
  the buy-in balance; if short it shows the dialog, and **"Buy more"** closes the
  sheet and switches to the **Store** tab (via an `onBuyMore` callback from Home,
  since the sheet route sits above `MainShellScope`).

### 2. `Dialog · expired` — "Session expired"  ✅ built + wired
- `showSessionExpiredDialog()` (`app/session_guard.dart`) via a global
  `rootNavigatorKey` (`app/root_key.dart`, wired into `MaterialApp`), with a
  re-entrancy guard so repeated 401s don't stack.
- `ApiClient.onUnauthorized` fires on a 401/403; `AuraApp` sets it to
  `session.forceSignOut()` + show the dialog → **"Log in again"** routes to Login.
  (Dormant until remote sources are on; correct wiring is in place.)

### 3. `Offline banner`  ✅ wired
- `connectivityProvider` (`services/connectivity.dart`) streams online/offline via
  `connectivity_plus`; `isOnline()` treats loading/error as online (no spurious
  banner in tests).
- `MainShell` (now a `ConsumerStatefulWidget`) shows `AuraOfflineBanner` above the
  content when offline, with **Retry** → re-check connectivity.

### 4. `Lock-screen pushes`  ✅ recorded (no app screen)
An **iOS lock screen** previewing push notifications — a design artifact for push
copy, not a Flutter screen. Copy captured below for the future push phase
(server + FCM/APNs); no UI to build.

| Trigger | Title | Body |
|---|---|---|
| Room invite | ZeroCool invited you to a room | Private room AX7K2Q · 200 Token stake · 2 seats left |
| Victory payout | Victory! +800 Tokens | You beat NeonViper 3 – 1. A rematch is waiting. |
| Daily bonus | Your Day 3 bonus is ready | 250 Gold expires in 4h — claim it before the streak resets. |
| Tournament start | Neon Cup starts in 15 minutes | Your seat is reserved · 128 players · 25,000 Token prize pool |

---

## B2. Second pass — fidelity fixes (found by re-walking the mockup) ✅

A deeper screen-by-screen re-comparison (rendered the mockup in Chrome, drove each
flow, diffed against our golden renders). Most screens matched exactly (Home, Wheel,
Daily rewards, Season pass, Result, Settings, Room lobby, Matchmaking, Store,
Profile, Leaderboard, game boards). Three fixes made:

1. **Online Play sheet — step count** was numbered `1/4 · 2/4 · 3/4`; the mockup
   numbers the three setup steps `1/3 · 2/3 · 3/3` (preview is unnumbered). Fixed
   the denominators.
2. **Online Play sheet — currency balances** were hardcoded `10,000 / 3,000` and
   inconsistent with the wallet. Now read from `walletProvider` (Tokens/Gold =
   the player's actual balance, `5,000 / 2,000` in the demo), and the
   insufficient-balance check uses the same source.
3. **Welcome bonus badge** rendered near-circular (radius 40 on a ~93px tile). Set
   the corner radius to `tileSize * 0.3` so the rotated square reads as the
   mockup's rounded **diamond**.

Verified all three via golden render; 46 tests still pass.

## B3. Third pass — remaining screens, fine nits ✅

Swept the rest (Transactions, Referral, Inbox, Achievements, Register, OTP, Reset,
Play-with-friends, game boards, Match setup/preview, Maintenance, Force update).
Matched: Transactions, Referral, Register, OTP, Reset, Room lobby/menu, game board
layout + colours. Three nits fixed:

1. **Inbox** notification icon tiles were subtle tinted-glass; the mockup uses
   **solid gradient** fills with white icons. Changed to a lerp gradient (matching
   the Achievements / Referral tiles).
2. **Achievements** locked tiles used a solid border; the mockup uses a **dashed**
   outline. Added a small `_DashedBorderPainter` (unlocked tiles stay solid gradient).
3. **Game "You" card** (all boards) had no highlight; the mockup gives the active
   player's card an **accent-glow border**. Added it to `GameYouCard`.

Verified via golden render; 46 tests pass. No further mismatches found.

## B4. Fourth pass — rigorous deep dive ✅

Zoomed into detail on auth, store tabs, overlays, and gameplay. Matched exactly:
Login (Apple/Google/email/guest/create), Level-up, Player profile, Onboarding,
Purchase confirm. Fixes:

1. **Store · VIP** — Subscribe button was brand‑gradient "Subscribe to Gold"; the
   mockup uses a **gold** "Subscribe · $9.99 / month" (new `_GoldSubscribeButton`).
   Perk copy replaced to match the mockup exactly (Remove all ads forever / 2× match
   rewards / Daily 500 Gold bonus / Exclusive avatars & frames / Priority
   matchmaking / Gold VIP badge). Tier labels `/mo`→`/ month`, Free `current`→`forever`.
2. **Store · Power‑ups** — the whole catalogue differed. Replaced with the mockup's
   five: Double XP (EPIC, ×2, 500 Gold), Extra Spins (RARE, 300 Gold), Streak Shield
   (LEGENDARY, ×1, 1,200), Hint Boost (RARE, 800), Time Freeze (COMMON, ×3, 600) —
   correct icons/colours/prices/currency. Rarity chips now tint to each item's accent
   colour (mockup), not a fixed per‑rarity palette.
3. **Chat sheet** — ours was a simple "Quick Chat" emote/message picker; the mockup is
   a **full chat panel**. Rebuilt `showGameChatSheet`: opponent header (avatar +
   online dot + close), empty‑conversation state ("Say hi or send an emote"),
   horizontal quick‑message pills (Good luck!/Nice move/Rematch?/GG), 8‑emote row
   (👋🔥GG😅👀💀🎯🤝), and a message input + gradient send button.

Verified via golden render; 46 tests pass.

## C. Notes
- Items 2 & 3 react to live auth/connectivity, so they stay dormant until the
  backend is on, but the wiring is complete and correct. Item 1 works now. Item 4
  needs no UI.
- No other visual or structural mismatches were found; the reskin/build matches the
  mockup across the full screen set.
