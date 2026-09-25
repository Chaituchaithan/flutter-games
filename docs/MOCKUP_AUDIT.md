# Aura — Mockup vs Implementation Audit

**Reference (source of truth):** `Aura Game UI.html` (bundled React prototype).
**Guidance:** `Aura Components.html` (Flutter component sheet).
**Audited build:** `lib/` as of this document.

> **Verdict:** The implemented screens do **not** match the mockup. The screen
> *structure* is largely correct (Home, Store, Profile, match flow all exist and
> carry the right content), but the app renders in an **older, flat visual
> system** while the mockup is a **glassmorphic redesign** with different fonts,
> palette, backgrounds, and control shapes. The differences are **systemic** —
> they touch `theme.dart` + every shared widget + every screen. On top of the
> re-skin, the mockup adds **~15 screens/overlays** the app doesn't have yet.
>
> Recommended order: **(1)** re-skin `theme.dart` + `lib/widgets/`, **(2)** rework
> existing screens against §5, **(3)** build the new screens in §6.

---

## 1. Design system — exact tokens (THE core of the mismatch)

Every value below is taken verbatim from the mockup. The "Current" column is the
value in `lib/theme.dart` / `lib/widgets/`. Fix these first — most per-screen
discrepancies disappear once the design system matches.

### 1.1 Typography  *(decision: add `google_fonts`)*

The **component sheet is authoritative**: display font is a **configurable pick**
whose **default is `Chakra Petch`** ("Techy · default"). The app prototype happens
to render in `Space Grotesk`, which the sheet lists as **"Original"** (the fallback).
Body is always **`Manrope`**.

| Role | Spec | Current (`AuraText`) |
|---|---|---|
| Display / headings / numbers / buttons | **`Chakra Petch`** (default) w600–w700; swappable → Orbitron, Rajdhani, Russo One, Audiowide, Exo 2, Teko, Saira Condensed, Michroma, Bungee, Black Ops One, Tourney, Zen Dots, Syncopate, Bai Jamjuree, Space Grotesk | system, `_display = null`, w800 |
| Body / inputs / secondary | **`Manrope`** w400–w600 | system default |

- **Type scale** (component sheet): `display 34/700` · `h1 26/700` · `h2 20/700` ·
  `numeric 26/700 tabular-nums` · `label 12/600 +0.8` · `body 15/400` ·
  `body-2 14/400` · `caption 12/500`. All headings **w700** (not w800).
- Numbers use **tabular-nums**.
- **Action:** add `google_fonts`; expose a single display-font hook (default
  `GoogleFonts.chakraPetch`) so it can be swapped, and a body default of
  `GoogleFonts.manrope`. Build `AuraText` from the scale above.

> **Cross-file note:** the app prototype uses `Space Grotesk`; the handoff sheet
> defaults to `Chakra Petch`. Confirm which the user wants as the shipped default
> (easy to swap via the hook).

### 1.2 Color palette  *(named tokens from the handoff → `ThemeExtension<AuraColors>`)*

| Token (handoff name) | Value | Current (`AuraColors`) |
|---|---|---|
| `bg.deep` | `#070510` | — |
| `bg.base` | `#0C0A16` | `background #0C0A16` ✅ |
| `bg.raised` | `#1A1330` | `card #17141F` (diff) |
| `brand.violet` | `#8B5CF6` | `brandPurple #8B5CF6` ✅ |
| `brand.pink` | `#EC4899` | `brandPink #EC4899` ✅ |
| `brand.orange` | `#FB923C` | `brandOrange #FB923C` ✅ |
| `accent.glow` (links, labels, icons, focus ring) | `#C084FC` | — (app used pink for links) |
| `currency.token` | `#22D3EE → #3B82F6` | `gems #38BDF8` |
| `currency.gold` | `#FDE68A → #F59E0B` | `gold #F5B301` |
| `state.success` | `#34D399` | `green #10B981` |
| `state.warning` | `#FBBF24` | `amber #F5B301` |
| `state.danger` | `#F43F5E` (text `#FB7185`) | `danger #EF4444` |
| `text.primary` | `#F4F1FB` (+ 60% / 40% muted) | `textPrimary #F5F3FF` |
| `gradient.primary` | `linear 135° #8B5CF6 → #EC4899 52% → #FB923C` | `AuraGradients.brand` (left→right) |
| `surface.glass` | `rgba(255,255,255,0.10)→0.04 + 20% stroke` | solid `#17141F` |
| `bg.screen` | `radial 120% 70% at 50% 0%, #171130 → #0a0816 → #070510` | flat + glows |

- **Radii scale:** `10 / 14 / 16 / 20 / 28`. **Spacing grid:** 4px.
- CTA hero gradient sometimes deepens to `#7C3AED → #DB2777 → #F97316`.
- **Rarity/status pills:** COMMON `#CBD5E1`, RARE `#67E8F9`, EPIC `#E9D5FF`,
  LEGENDARY gold-gradient `#FDE68A`, NEW brand-gradient, VIP gold-gradient.

### 1.3 Backgrounds

- **Mockup:** every screen has a **radial-gradient** background, tinted per screen,
  e.g. Home `radial-gradient(120% 70% at 50% 0%, #15102b 0%, #0a0816 56%, #070510 100%)`;
  Login `#171130 → #0a0816 → #070510`; Register `#1a1132 …`; plus a large blurred
  **glow blob** (`radius ~360px`, `rgba(139,92,246,0.24)` or pink, `blur(30–44px)`)
  positioned per screen.
- **Current:** flat `background #0C0A16` + `AuraBackground` two static glows.
- **Action:** replace `AuraBackground` with a radial-gradient base + a single
  configurable glow blob (color + position per screen). Keep it a shared widget.

### 1.4 Surfaces — glassmorphism (the biggest visual delta)

Mockup cards/controls are **frosted glass**, not solid:
```
background: linear-gradient(160deg, rgba(255,255,255,0.09), rgba(255,255,255,0.03));
border: 1px solid rgba(255,255,255,0.20);
box-shadow: inset 0 1px 0 rgba(255,255,255,0.12), 0 12px 28px -14px rgba(0,0,0,0.7);
border-radius: 16–22px;
```
Accent/hero cards raise the tint (e.g. `rgba(139,92,246,0.28–0.32)`) and border
(`rgba(192,132,252,0.45–0.6)`). Current `AuraCard` is solid `#17141F` + `white@8%`
hairline, no inset highlight, no drop shadow. **Action:** rebuild `AuraCard` with
the glass recipe + an `accent`/`gradient` variant.

### 1.5 Buttons

| Button | Mockup | Current |
|---|---|---|
| Primary CTA | full-width **h56**, `radius 17`, brand gradient, `border 1px rgba(255,255,255,0.3)`, `inset 0 1px 0 rgba(255,255,255,.35)` + glow shadow, **Space Grotesk 17 w600** | `GradientButton` (check radius/height/inset) |
| Secondary / "guest" | **h52**, `radius 16`, transparent, `border 1.5px rgba(255,255,255,0.24)`, Manrope 15 | `SecondaryButton` solid card |
| Circular back / icon | **42×42 rounded-square, `radius 14`**, glass gradient + inset highlight, 9×16 chevron | **circular** `_CircleIconButton` 40×40, `Icons.chevron_left` |
| Small icon action (bell/gear) | 40×40, `radius 13`, glass | circular |

**The back button is a rounded square everywhere in the mockup**, not a circle —
this alone changes every sub-screen header. Build one `GlassIconButton(radius:14)`.

### 1.6 Inputs

Mockup: **h54**, `radius 15`, `background rgba(255,255,255,0.06)`,
`border 1.5px rgba(255,255,255,0.22)`, `inset 0 2px 6px rgba(0,0,0,0.35)`, left icon
inset 46px, focus → `border #A855F7` + `0 0 0 3px rgba(168,85,247,0.18)`.
Current `AuraTextField`: `field #17141F`, `radius 16`, `white@8%` border, **no focus
ring, no inset shadow**. **Action:** update fill/border/radius + add focus ring.

### 1.7 Recurring components

- **Currency chip:** pill, tinted gradient bg (`rgba(34,211,238,0.24→0.06)` for
  tokens / amber for gold), colored border, **drawn gem = diamond path `M6 3h12l4 6-10 12L2 9z`**,
  gold = layered circles + star. `+` is a filled circle. Current `CurrencyPill`
  uses `Icons.diamond`/`Icons.monetization_on` on a solid pill. Rework.
- **Section header:** a **4×16px gradient bar** (`linear-gradient(180deg,#8B5CF6,#EC4899)`)
  + Space Grotesk 15 w600 label — *not* the current uppercase grey `SectionHeader`.
  Both styles appear (settings groups still use uppercase grey `w600 letter-spacing`).
- **Toggle:** track `52×30`... gradient when on. (Matches current `AuraToggle` closely.)
- **Segmented tabs:** container `rgba(0,0,0,0.3)`, `radius 14`, `inset` shadow; active
  segment brand-gradient. Current `SegmentedTabs` uses a card bg — retint to dark inset.
- **Avatar:** conic-gradient ring (`conic-gradient(#C084FC 234deg, rgba(255,255,255,0.12) 0)`
  = XP ring) → dark gap → gradient initials disc; level badge pill below. Richer than
  current `LetterAvatar`.
- **Bottom nav:** floating glass bar, 4 items, active icon brand-gradient
  (current `AuraBottomNav` is close; retint to glass). **⚠ label mismatch — see §1.9.**

### 1.8 Component library — Flutter widget targets (from the handoff sheet)

The handoff names the intended API. Build/rename toward these; each carries the
states listed:

| Widget | States / variants | Key specs |
|---|---|---|
| `AuraButton(variant, size, state)` | variants: primary · secondary · glass · gold · danger · loading; sizes: CTA **56** / standard **48** / compact **40**; states: default/pressed/disabled | radius **15**; pressed = `scale .97 + brightness .88 @120ms`; primary = gradient + `inset 0 1px 0 rgba(255,255,255,.35)` + glow shadow |
| `AuraTextField` | default · focused · filled(+trailing) · error · disabled | h54, radius **16**, focus `border #C084FC` + `0 0 0 3px rgba(192,132,252,.18)`; error uses `#FB7185` |
| `AuraOtpField` | filled · active · empty | cells **44×54**, radius 14, inset shadow |
| `AuraTabBar` | active/inactive | container `rgba(255,255,255,.05)` r16, active seg gradient r12 |
| `AuraChip` | selected · default · with-count · disabled + rarity/status badges | pill; selected = `#C084FC` border + `rgba(192,132,252,.18)` |
| `AuraSwitch` | on · off · disabled | 50×30, on = brand gradient |
| `AuraGlassCard` | plain · accent(gradient) | glass recipe §1.4 |
| `AuraListTile` | nav row · currency row · leaderboard row · ledger row | 40–46 leading tile, chevron/trailing value |
| `AuraToast` | success · gold · info | auto-dismiss **2.6s**, tap to close, dark glass pill |
| `AuraDialog` | info · destructive(+secondary) | rounded 24–28 sheet, icon tile, primary + ghost |
| `AuraSkeleton` | row / block | shimmer **1.4s** (`auraShimmer`) |
| `AuraProgress` | bar · stepper(2/4) · radial · page-dots | bar h10 gradient+glow; active dot = 26×8 pill |
| Icon button / FAB | — | icon **42** rounded-14, unread badge **18**, FAB **56** circle |
| Avatar | 32 / 40 / 56 / 96 | online dot + conic level ring; LV badge pill |

### 1.9 Cross-file inconsistencies to resolve with the user

1. **Display font:** app prototype = `Space Grotesk`; handoff default = `Chakra Petch`.
2. **Bottom-nav tabs:** app = **Home · Wheel · Store · Profile**; handoff sheet shows
   **Home · Ranks · Store · Profile** (Wheel vs Ranks). Confirm the 4 destinations.
3. **Input focus color:** app screens used `#A855F7`; handoff uses `#C084FC`
   (`accent.glow`). Prefer the handoff value unless told otherwise.

These are minor but affect every screen — worth a one-line confirmation before build.

---

## 2. Screen inventory

| Mockup screen | State flag | Flutter today | Status |
|---|---|---|---|
| Splash | `isSplash` | `splash_screen.dart` | reskin |
| Intro carousel (3 slides) | `isIntro` | `onboarding/` | reskin |
| Language | `isLanguage` | `language_screen.dart` | reskin |
| Login | `isLogin` | `login_screen.dart` | reskin |
| Register | `isRegister` | `register_screen.dart` | reskin |
| OTP verify | `isOTP` | `otp_screen.dart` | reskin |
| Welcome bonus | `isWelcome` | `welcome_bonus_screen.dart` | reskin |
| Home | `isHome` | `home_screen.dart` | reskin |
| Daily rewards | `isDaily` | `daily_rewards_screen.dart` | reskin + structure |
| Lucky wheel | `isWheel` | `wheel_screen.dart` | reskin |
| Match result | `isResult` | `match_result_screen.dart` | reskin |
| Profile | `isProfile` | `profile_screen.dart` | reskin + **4th stat tile, mode breakdown** |
| Edit profile | `isEdit` | `edit_profile_screen.dart` | reskin |
| Avatars | `isAvatars` | `avatars_screen.dart` | reskin |
| Game history | `isHistory` | `game_history_screen.dart` | reskin |
| Store | `isShop` | `store_screen.dart` | reskin + Power-Ups/VIP tab content |
| Settings | `isSettings` | `settings_screen.dart` | reskin + new rows |
| Transactions | `isLedger` | `transactions_screen.dart` | reskin |
| Achievements | `isAchievements` | `achievements_screen.dart` | reskin |
| Referral | `isReferral` | `referral_screen.dart` | reskin |
| Season pass | `isSeason` | `season_pass_screen.dart` | reskin |
| Confirm purchase | `purchaseOpen` | `purchase_confirm_screen.dart` | reskin → **bottom sheet** |
| Level-up | `levelUp` | `level_up_screen.dart` | reskin → **tap-to-dismiss overlay** |
| Match setup + preview | `opOpen` (4-step) | `match_setup_screen.dart` + `match_preview_screen.dart` | reskin → **single bottom sheet** |
| Gameplay: chess/ludo/othello/scrabble/snakes | `isGame`+`gpBoard` | 6 separate `games/*_screen.dart` | **unify → 1 screen** |
| Gameplay: trivia | `isGame`+`gpTrivia` | `trivia_screen.dart` | reskin |
| **Play with Friends** (menu) | `isFriends`/`frMenu` | — | **NEW** |
| **Create room** | `frCreateMode` | — | **NEW** |
| **Join room** | `frJoinMode` | — | **NEW** |
| **Room lobby** | `frLobby` | — | **NEW** |
| **Matchmaking VS** (search→reveal→countdown) | `isVs` | — | **NEW** |
| **Reset-password flow** (4 steps) | `isForgot` (`fp1..fp4`) | `reset_password_screen.dart` (1) | **expand to 4** |
| **Leaderboard** | `isLeaderboard` | — | **NEW** |
| **Tournaments** (full) | `isTournaments` | Home "SOON" row only | **NEW** |
| **Inbox / notifications** | `isNotifs` | — | **NEW** |
| **Friends & social** (tabs) | `isSocial` | — | **NEW** |
| **Other player profile** | `isPlayer` | — | **NEW** |
| **Chat / emotes sheet** | `chatOpen` | — | **NEW** |
| **Paused overlay** | `gpPaused` | — | **NEW** |
| **Maintenance** | `isMaintenance` | — | **NEW** |
| **Force update** | `isUpdate` | — | **NEW** |
| **Lock-screen push preview** | `isLock` | — | **NEW (prototype-only)** |
| **Loading skeleton** | `isLoading` | — | **NEW (recommended)** |
| **Toast / snackbar** | `toastOpen` | — | **NEW (component)** |
| **Global dialog** | `dialogOpen` | — | **NEW (component)** |
| **Offline banner** | `offline` | — | **NEW (component)** |

> The mockup's "DEMO STATES" settings group and the "All screens" navigator are
> **prototype-only** — do not port them into the app.

---

## 3. Per-screen discrepancies (existing screens)

For each, apply §1 globally; below are the **screen-specific** deltas.

### Splash (`splash_screen.dart`)
- Mockup: conic-gradient spinning ring (`#8B5CF6→#EC4899→#FB923C`) → dark gap →
  gradient dot; wordmark **Space Grotesk 46px, letter-spacing 6px**; tagline;
  bottom 150×3 progress bar filling to 45%. Tap anywhere → intro.

### Intro carousel (`onboarding/`)
- 3 panels: **Find your people** / **Share your moment** / **Always in sync** with
  the exact sub-copy in the mockup (lines 1271/1300/1318). Skip (top-right) → login.
  Dots + gradient CTA (`Continue` → `Get Started`). Illustrations are drawn (avatar
  cluster / floating post card / concentric "live" rings).

### Language (`language_screen.dart`)
- Two entry modes: **from splash** (globe icon + "Choose your language" h1) and
  **from settings** (back button + "Language" h2). 2-col grid of language tiles
  (flag + native name + English name + check). Gradient `Continue`.

### Login (`login_screen.dart`)  — *fully verified*
- Back = **rounded-square glass** (currently circular). Logo ring+dot + "Aura" 19px.
- Title 32px. **Apple button = white + real Apple glyph**; **Google = glass + real
  multicolor G** (currently drawn "G" on dark card). Inputs per §1.6. Password eye
  toggle. `Forgot password?` = `#C084FC`. CTA "Log In" h56. "Continue as guest"
  transparent h52. Footer "New to Aura? **Create account**".

### Register (`register_screen.dart`)
- Apple/Google are **side-by-side compact** (label only). Fields: Full name / Email /
  Create password. Agree checkbox = 22×22 `radius 7`, checked = brand gradient +
  check. CTA "Create Account" → OTP.

### OTP (`otp_screen.dart`)
- Glass mail icon tile (64×64 `radius 20`). "Verify your email" 30px. 6 OTP cells.
  "Resend in 0:24" (`#C084FC`). **Custom 12-key numeric keypad** grid (3-col). CTA
  "Verify & Continue".

### Welcome bonus (`welcome_bonus_screen.dart`)
- Rotated gradient gift square + star; "WELCOME GIFT" label; "You're all set!" 31px;
  3 reward tiles **+5,000 Tokens / +1,000 Gold / +3 Spins**; CTA "Claim & Play".

### Home (`home_screen.dart`)
- Structure already matches (HUD card, game chips, featured hero, Quick Play/Friends,
  tournaments row, ad, Season card, Daily/Wheel, Recent matches). Deltas: HUD is a
  **glass card** with 50px conic-XP-ring avatar + level badge, **bell/notifications
  button with unread badge** (missing), currency chips stacked right, LV7 + gradient
  progress `65%` + `1,300/2,000`. Featured hero uses CTA gradient `#7C3AED→#DB2777→#F97316`.
  Tournaments row = **LIVE** (green) not SOON; Season card shows tier + XP bar.

### Daily rewards (`daily_rewards_screen.dart`)
- Streak hero (flame, "{{n}}-Day Streak" + 7 pips), "TODAY'S REWARD" card, **This week**
  4-col grid of day tiles with states (gold/token icon, MEGA/TODAY/claimed✓/locked).
  Footer "Miss a day and your streak resets to Day 1."

### Wheel (`wheel_screen.dart`)
- "Lucky Spin" + token/gold chips; "{{n}} free spins left" glass pill; **286px 8-seg
  conic wheel** (`#6D28D9`/`#9D174D`/`#B45309`), top pointer, center SPIN hub;
  result banner. Verify segment labels match.

### Match result (`match_result_screen.dart`)
- 116×116 `radius 34` result icon tile; title **42px letter-spacing 2px**
  (VICTORY/DEFEAT/DRAW); You vs Rival avatars + big score; `+XP` reward chip;
  "Play Again" CTA + "Back to Home" ghost.

### Profile (`profile_screen.dart`)  — *structural change*
- Hero card: 92px conic-XP-ring avatar + edit pencil + LV badge, name+flag+**VIP tier
  badge**, `@handle`, **bio (italic)**, GOLD III chip + XP bar, "Edit profile" button.
- **4 stat tiles** (not 3): Matches / Wins / Streak / **Rank** (→ leaderboard). Current
  has 3. Add the 4th.
- Win-rate radial (68%) + W/D/L legend; **Last 7 days** bar chart (+12% badge).
- **NEW "Game stats" mode-breakdown card** (per-mode bars + best-streak/tokens/gold row) — not in current build.
- Achievements strip (4 tiles, "See all x/y"). **Manage** grid: Edit profile / Avatar /
  Game history / Settings.

### Edit profile (`edit_profile_screen.dart`)
- Avatar w/ camera badge + "Change avatar". DISPLAY NAME (maxlength 20) / BIO
  (maxlength 60) / COUNTRY 4-col flag grid. "Save changes".

### Avatars (`avatars_screen.dart`)
- Large preview (conic ring + initials), "Tap a tile to equip it", 4-col grid of
  avatar tiles w/ selected check badge, "Save Avatar".

### Game history (`game_history_screen.dart`)
- 3 summary tiles (Played/Won/Win rate) + list rows: W/L/D badge, opponent avatar,
  name, "Final {score}", reward (`#C084FC`) + relative time.

### Store (`store_screen.dart`)
- Tabs Tokens/Gold/Power-Ups/VIP correct. Each tab has a header banner
  (`2× WEEKEND` / `PREMIUM` badges) + 2-col pack grid; **pack price buttons are
  currency-colored gradients** (cyan for tokens, gold for gold). **Power-Ups** = list
  rows w/ rarity + owned count + buy button. **VIP** = 3 tier cards + selected-plan
  perks panel + subscribe. Current build only has the Tokens-style grid.

### Settings (`settings_screen.dart`)
- VIP upsell banner; **PREFERENCES** (Sound/Music/Notifications/Haptics toggles +
  **Language row**); **ACCOUNT** (Edit profile, Change avatar, **Friends & blocked**,
  **Transactions & receipts**, **Invite friends**, Game history); **SUPPORT** (Help,
  Privacy, App version 1.0.0); red **Log out**. Add the new account rows. *(Skip the
  "DEMO STATES" group — prototype only.)*

### Transactions (`transactions_screen.dart`)
- Two summary tiles (EARNED·7D green / SPENT·7D red) + "Recent activity" (Export) list:
  up/down icon, title, "{detail} · {when}", currency + signed amount.

### Achievements (`achievements_screen.dart`)
- "Trophy Room" hero w/ progress bar (x/y badge) + list rows: icon, name, progress
  text, desc, progress bar (if incomplete) / green check (if done).

### Referral (`referral_screen.dart`)
- Gift illustration w/ floating +2,000/+300 chips; "Give 1,000, get 2,000"; copy
  explaining the reward; **YOUR CODE `NOVA-7K2Q`** card + Copy; 4 share buttons
  (WhatsApp/Telegram/SMS/More — real brand colors); "Your referrals" progress list.

### Season pass (`season_pass_screen.dart`)
- "Ends in 12d 04h" chip; Season 4 · Neon Tide hero (tier x/20 + XP bar); "Unlock
  Premium track · 950 Gold" CTA; **FREE / PREMIUM two-track reward grid** (tier rows
  with claim states).

### Confirm purchase (`purchase_confirm_screen.dart`)  — *→ bottom sheet*
- Mockup is a **bottom sheet** (drag handle, rounded-top, `#17112c→#0b0916`): item card
  (icon + name + amount + price), "Balance after", "Payment · Apple Pay", "Pay {price}"
  CTA, "Secure checkout" note. Current is a full screen — convert to `showModalBottomSheet`.

### Level-up (`level_up_screen.dart`)  — *→ tap overlay*
- Mockup is a **full-screen tap-to-dismiss overlay** (radial purple glow, spinning
  conic ring w/ big level numeral, "Level 8 reached", "New rank: Platinum I", 3 reward
  tiles, "Tap anywhere to continue"). Current is a routed screen — make it an overlay.

### Match setup + preview (`match_setup_screen.dart`, `match_preview_screen.dart`)  — *→ one sheet*
- Mockup `opOpen` is **one bottom sheet with 4 steps**: (1) players 2/4, (2) currency
  Tokens/Gold w/ balances, (3) tier grid (50/100/200/500/1k/2k + pots) + CUSTOM stepper
  (− amount +, min 50/max 5,000) + YOUR STAKE / TOTAL POT·N× summary, (4) preview (VS
  avatars, entry/pot/format rows, "Create game"). Current is two separate routed
  screens with 3 steps — consolidate into the sheet.

### Gameplay board games (`chess/ludo/othello/scrabble/snakes_ladders`)  — *unify*
- Mockup renders **all five board games through one `gpBoard` screen** parameterized
  by game type: pause button + title "{icon} {name}" + "Move n · players", up to 4
  glass player corner-cards (turn state), a **glass board container** whose grid/cells
  vary by game (`boardGrid`/`boardCells`, scrabble adds a rack, snakes adds cell
  numbers), last-move/dice/turn-clock panel, and an action bar (chat / **primary action
  (roll/move)** / forfeit). Current app has 6 separate hand-built screens. Recommend a
  single `GameplayScreen(gameType)` with per-game board painters.

### Gameplay trivia (`trivia_screen.dart`)
- `gpTrivia`: HUD (pause/round/pot), players+circular timer row, question card
  (category chip + Q), 2×2 answer grid (letter chips, correct/wrong states, opponent
  pick marks), reveal banner, Hint ×n / Freeze ×n power-up bar.

---

> **Data & auth (current phase):** the app stays **presentation-only** — all screen
> data is **static/hardcoded** for now and becomes **dynamic** later; **auth runs on
> a mock API (`mockapi`)** now and swaps to the **real API** later. Keep the re-skin
> UI-only: hold data behind simple in-widget constants / a thin mock service, and
> keep button handlers as the single integration seam (per `DESIGN_SPEC.md`). Don't
> hard-wire networking into widgets during the re-skin.

## 4. Architecture / navigation notes

- **One gameplay screen** replaces six game files (see §3). Big simplification.
- **Match setup/preview** collapse into a single bottom-sheet flow (`opOpen`).
- **Confirm purchase / level-up / paused / chat / toast / dialog / offline / online-play**
  are **overlays & bottom sheets**, not routed pages — build a shared overlay layer.
- New destinations need routes/nav: Leaderboard, Tournaments, Inbox, Friends/social,
  Other-player profile, Play-with-Friends (menu/create/join/lobby), Matchmaking VS,
  Maintenance, Force-update.
- Reset-password grows from 1 screen to a **4-step flow** (email → code → new
  password w/ strength meter → success).

---

## 5. Assets & fonts

Per the project asset rule (see `DESIGN_SPEC.md`): document required assets, use
online sources now, swap real files later.
- **Fonts:** `Chakra Petch` (display default) + `Manrope` (body) via **`google_fonts`**
  (approved). Runtime fetch on first launch; needs `INTERNET` (Android, default) and
  HTTPS (iOS ATS ok). Keep the display face behind one hook so it stays swappable.
- **Brand glyphs in mockup are inline SVG paths** (Apple, Google multicolor, gem
  diamond, gold coin, trophy, flame, etc.) — port as `CustomPaint`/SVG rather than
  Material icons where fidelity matters. Add each to the `DESIGN_SPEC.md` asset table.
- No raster assets are required to hit the mockup — it is 100% drawn + gradients.

## 6. Suggested implementation sequence

1. **Foundation:** `google_fonts` (Chakra Petch display + Manrope body, display
   behind a swap hook) + `AuraText` type scale; `AuraColors` as
   `ThemeExtension` (accent.glow `#C084FC`, currency.token `#22D3EE→#3B82F6`,
   currency.gold `#FDE68A→#F59E0B`, success `#34D399`, warning `#FBBF24`,
   danger `#F43F5E`/`#FB7185`, bg.raised `#1A1330`);
   `AuraBackground` (radial + glow blob); glass `AuraCard`; `GlassIconButton`
   (rounded-square back); `AuraTextField` (glass + focus ring); currency chips
   (drawn gem/coin); gradient section-bar header; retint tabs & bottom nav.
2. **Existing screens** (§3) — reskin; add Profile 4th tile + mode card, Store
   Power-Ups/VIP, Settings rows, Home bell; convert purchase/level-up/match-flow to
   overlays/sheet; unify board games.
3. **New screens** (§2/§6) — shared overlays (dialog/toast/offline) first, then
   Leaderboard, Tournaments, Inbox, Friends/social, rooms + lobby, matchmaking VS,
   maintenance, force-update, 4-step reset.
4. Update `test/screens_smoke_test.dart` to cover new screens; keep offline-safe
   fallbacks so tests pass without network (fonts/images).
