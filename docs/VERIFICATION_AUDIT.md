# Aura — Screen Verification Audit (UI + interactions vs mockup)

Purpose: an honest, screen-by-screen check of the **current app** against the
mockup (`Aura Game UI.html`), covering both **visual fidelity** and **interaction/
functionality**. Use this to prioritize fixes. Reference: `docs/MOCKUP_AUDIT.md`.

**Legend:** ✅ done/matches · ◑ visually reskinned, interactions incomplete ·
🔧 structural gap (different UX than the mockup) · ⬜ not built yet ·
🎨 not yet fidelity-reworked (inherits the new theme only).

---

## A. Status by screen

| Screen | Visual | Interactions | Notes |
|---|---|---|---|
| Splash | ✅ | auto→language | reworked: 150px orb, display wordmark, bottom gradient progress bar |
| Onboarding carousel | ✅ | ✅ swipe/skip | reworked: display titles, secondary body, page indicator |
| Language | ✅ | ✅ select→continue | reworked: gradient globe, 2-col glass grid, accent-border selected |
| Login | ✅ | ◑ buttons navigate (mock auth — dynamic phase) | matches |
| Register | ✅ | ◑ terms checkbox works; social/create navigate (mock auth) | matches |
| OTP | ✅ | ✅ keypad + verify | matches |
| Welcome bonus | ✅ | ✅ claim→home | matches |
| Reset password | ✅ | ✅ **4-step** flow (email→code→new pw→done) | done (§C.4) |
| Home | ✅ | ✅ sticky HUD, ad dismiss, tabs, nav, Online Play sheet | done |
| Wheel | ✅ | ✅ spin animation | matches |
| Store | ✅ | ✅ pack buttons → purchase sheet; Subscribe → toast | done |
| Profile | ✅ | ✅ nav rows + Rank tile → Leaderboard | done |
| Edit profile | ✅ | ✅ editable name + multi-line bio, country picker, Save→toast | fidelity pass done |
| Avatars | ✅ | ✅ grid + ring/check selection, Save→toast | fidelity pass done |
| Game history | ✅ | ✅ stat tiles + All/Wins/Losses filter + rows | fidelity pass done |
| Achievements | ✅ | ✅ trophy room grid + progress/unlock | already matched |
| Settings | ✅ | ✅ Logout→dialog; Help/Privacy/VIP→toast; all nav wired | done |
| Daily rewards | ✅ | ✅ Claim → toast | done |
| Transactions | ✅ | ◑ Export → toast (static export deferred) | matches |
| Referral | ✅ | ✅ Copy/share → toast | done |
| Season pass | ✅ | ◑ claim tiers static (dynamic phase) | matches |
| Purchase confirm | ✅ | ✅ modal bottom sheet; Pay→toast; method picker | done (§C.2) |
| Match setup | ✅ | ✅ 3-step | but should be part of the Online Play **sheet** (§C) |
| Match preview | ✅ | ✅ create→result | should be step 4 of the sheet (§C) |
| Match result | ✅ | ✅ play again / home | matches |
| Level-up | ✅ | ✅ tap-to-dismiss overlay (`showLevelUp`) | radial glow + rays badge + reward tiles; routed fallback kept |
| Inbox | ✅ | ✅ mark-all-read, tap-to-read | new |
| Friends | ✅ | ✅ Challenge/Add/Accept→toast; rows→player profile | done |
| Tournaments | ✅ | ✅ Open/Register/Recap→toast | done |
| Chess / Ludo / Othello / Scrabble / Snakes | ✅ | ✅ shared chrome; chat/forfeit/paused wired | now share `game_widgets.dart` (header/pot/player cards/turn clock/action bar) |
| Trivia | ✅ | ✅ shared header + chat/forfeit/paused | shares `GameHeader`/`GamePotPill`; keeps its quiz body |

---

## B. Interaction stubs — mostly wired (§F #5 done)

All previously-empty `() {}` handlers now give feedback or navigate:
- Store — **Subscribe** → toast · Daily — **Claim** → toast · Referral —
  **Copy/Share** → toast · Edit profile — **Save** → toast (done in #2).
- Purchase confirm — **Pay** → toast; **payment method row** → method-picker sheet
  (`_MethodPicker`, updates the selected method).
- Settings — **Help center / Privacy policy / VIP banner** → toast; **Log out** →
  confirm dialog.
- Friends — **Challenge / + Add / Accept / Decline** → toast; **rows** → other-player
  profile.
- Leaderboard — **rows** → other-player profile.
- Tournaments — **Open / Register / Recap** → toast (per CTA).
- Game boards — **chat** → chat sheet · **forfeit** → confirm dialog · **pause** →
  paused overlay · **move buttons** → demo toast.

Remaining intentionally-static: deep game-move logic, real Save/persistence,
external Help/Privacy pages — all belong to the dynamic-data phase.

---

## C. Structural mismatches (different UX than the mockup)

1. ✅ **DONE — Online Play (featured) → bottom sheet.** Built
   `lib/screens/match/online_play_sheet.dart` (`showOnlinePlaySheet`): a modal bottom
   sheet with the 4 steps players → currency → stake (tiers + custom stepper + pot
   summary) → preview → "Create game". Home's featured card / Quick Play / game chips
   now open it. Verified all 4 steps + no overflow. (Routed `MatchSetupScreen` /
   `MatchPreviewScreen` kept as the "Play Again" fallback.)
2. ✅ **DONE — Purchase confirm → modal bottom sheet.** `showPurchaseSheet()` (shared
   `PurchaseSheet` widget); Store buy buttons open it; Pay → toast + close. Routed
   `PurchaseConfirmScreen` kept as fallback/test.
3. ✅ **DONE — Level-up → overlay.** `showLevelUp()` full-screen tap-to-dismiss
   overlay (radial glow + blur). Routed `LevelUpScreen` kept for tests. (No auto-
   trigger yet — fire it from real level-up logic later.)
4. ✅ **DONE — Reset password → 4 steps.** email → code (keypad) → new password
   (strength meter + confirm) → success → Back to login.

**Shared overlays built** (`lib/widgets/aura_overlays.dart`): `showAuraDialog`
(confirm/destructive), `showAuraToast` (success/gold/info/error), `AuraOfflineBanner`.
Wired: Settings **Log out → confirm dialog → login**; Referral **Copy/Share → toast**;
Daily **Claim → toast**; Store **Subscribe → toast**; Edit profile **Save → toast**,
**Change avatar → Avatars**.

---

## D. Not built yet (mockup-only) — to build

- ✅ **DONE — Leaderboard** (`leaderboard/leaderboard_screen.dart`): podium + your-rank + list; Profile "Rank" tile → it.
- ✅ **DONE — Play with Friends** (`social/play_with_friends_screen.dart`): menu → create → join (code keypad) → lobby (code/seats/start). Home "Friends" tile → it.
- ✅ **DONE — Matchmaking VS** (`match/matchmaking_screen.dart`): searching → reveal → countdown → result. "Create game" / lobby "Start" → it.
- ✅ **DONE — Maintenance** (`system/maintenance_screen.dart`) and **Force update** (`system/force_update_screen.dart`) — routed; no auto-trigger (server/version state).
- ✅ **DONE — shared Toast/Dialog/Offline** (see §C).
- ✅ **DONE — Other player profile** (`social/player_profile_screen.dart`): avatar/level/stats + Challenge/Message + Report/Block (overflow menu → toast/confirm). Reachable from Friends rows + Leaderboard rows.
- ✅ **DONE — Chat / emotes** bottom sheet (`showGameChatSheet` in `game_widgets.dart`): emote grid + quick messages → send toast.
- ✅ **DONE — Paused** overlay (`showGamePaused`): blur backdrop, Resume / Settings / Forfeit. Triggered by the header pause button on every board.
- ✅ **DONE — Loading skeleton** (`system/loading_skeleton_screen.dart`): `Shimmer` + `SkeletonBox` widgets, Home-shaped placeholder.

---

## E. Not yet fidelity-reworked (inherit theme, need a mockup pass)

✅ **All §E fidelity work is complete.** Splash · Onboarding · Language · the 6
game boards + Trivia · Edit profile · Avatars · Game history · Achievements ·
Level-up have all been reworked/verified against the mockup.

---

## F. Recommended fix order

1. **Online Play bottom sheet + match flow** (the reported issue) — §C.1.
2. **Shared overlays** (dialog / toast / offline) — unblocks Logout, Copy, Claim feedback + §C.3.
3. **New screens** — Leaderboard, Play-with-Friends/rooms/lobby, VS, Maintenance, Force-update (§D).
4. **Fidelity pass** on §E screens (Splash/Onboarding/Language first, then game boards → unified gameplay screen).
5. ✅ **DONE — Wire remaining stubs** (§B) to their real destinations/feedback.
