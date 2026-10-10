# Design Spec

How the app looks and which shared pieces to build screens from. The **source
of truth for visuals** is the Aura mockup (`Aura Game UI.html`); the
**Aura Components** sheet is the UI kit for colours, sizes and styling. This
doc records how the Flutter app implements them and every place it
deliberately differs.

Values below are read from the code (`lib/theme.dart`, `lib/widgets/`), so
treat the code as authoritative if they ever disagree.

---

## 1. Design tokens (`lib/theme.dart`)

### Colour — `AuraColors`
| Token | Value | Use |
|---|---|---|
| `bgDeep` | `#070510` | Deepest background (result, matchmaking) |
| `bgBase` | `#0C0A16` | Default screen background |
| `bgRaised` | `#1A1330` | Raised panels, dialogs |
| `brandPurple` → `brandPink` → `brandOrange` | `#8B5CF6` → `#EC4899` → `#FB923C` | Brand gradient: primary buttons, active tabs, highlights |
| `accentGlow` | `#C084FC` | Focus rings, links, active borders |
| `textPrimary` / `textSecondary` / `textMuted` | `#F4F1FB` at 100 / 60 / 40 % | Text |
| `glassStroke` | white @ 20 % | Hairline borders on glass |
| `gems` → `gemsDeep` | `#22D3EE` → `#3B82F6` | Tokens currency |
| `goldLight` → `gold` | `#FDE68A` → `#F59E0B` | Gold currency, VIP, premium |
| `green` / `amber` / `danger` | `#34D399` / `#FBBF24` / `#F43F5E` | Success / warning / error |

Screen background is a radial gradient `#171130 → #0A0816 → #070510` from
the top, plus one soft glow blob (`AuraBackground`).

### Type — `AuraText`
- **Display:** Space Grotesk (titles, numbers, buttons) — `AuraText.displayFamily`.
- **Body:** Manrope — `AuraText.bodyFamily`.
- Loaded at runtime with `google_fonts`; swap the family in one place to change every screen.

### Shape — `AuraRadii`
`xs 10 · sm 14 · md 16 · lg 20 · xl 28` (4 px grid). Screen headers use a
42 px glass back button (r14); cards r16–24; pills r99.

### Surfaces — `AuraGlass.decoration`
Frosted glass: white 9 % → 3 % gradient, 1 px white hairline, soft drop
shadow. **Rule:** a shadowed card gets an opaque fill (the glass blended onto
the background). A Flutter `BoxShadow` under a translucent fill shows
through as a lighter inner panel; CSS box-shadows don't, so the mockup never
has that artefact. Coloured glows on translucent cards go on an opaque base
layer for the same reason.

---

## 2. Shared widgets (`lib/widgets/`)

Build every screen from these — don't re-invent them.

| Widget | File | Notes |
|---|---|---|
| `AuraScaffold` | components | Background + glow + SafeArea; `scroll:` for long screens |
| `AuraAppBar` | components | Mockup header: back button + **left-aligned** 22 px title + optional trailing |
| `GlassIconButton` | components | 42 px rounded-square glass icon button |
| `GradientButton` / `SecondaryButton` / `LightButton` | aura_widgets / components | Primary (brand gradient, `loading`, `enabled`), outline, white/dark social |
| `AuraTextField` | components | Glass input with focus ring and inline `errorText` (stable layout — the keyboard never closes when the error clears) |
| `AuraCard` | components | Glass card |
| `SegmentedTabs` | components | Dark inset pill tabs |
| `AuraBottomNav` | components | Floating bar: Home · Wheel · Store · Profile, outline icons, pink active dot |
| `CurrencyPill` / `CurrencyGlyph` | components | Token / Gold balances; drawn gem and coin |
| `SectionBar` / `SectionHeader` | components | Gradient-bar section title / small uppercase label |
| `AuraBadge`, `StatTile`, `AuraToggle` | components | Pills, stat blocks, switch |
| `AuraAvatar`, `LetterAvatar` | aura_widgets | Conic-ring avatar with level badge; initials avatar |
| `showAuraDialog` (`brand`/`danger`/`warning`/`success`), `showAuraToast`, `AuraOfflineBanner` | aura_overlays | Dialogs, toasts, offline banner |
| `BusyGuard` | components | While a request runs, locks the screen: taps and back are ignored, and the tapped button shows its spinner. Use it on every screen that awaits a call and then navigates |
| `AsyncView` (+ `Shimmer`, `SkeletonBox`) | `lib/state/` | Loading skeleton → data → error/retry for any service call |

**Game area** (`lib/widgets/game_widgets.dart`): `GameHeader`,
`BoardPlayerCard` (rectangular timer ring, 3 text rows, active glow),
`BoardInfoPanel` (Last move / Turn clock), `BoardActionBar` (pinned: chat ·
status · draw · forfeit), `showGamePaused`, `confirmMatchForfeit`,
`showGameChatSheet`.

---

## 3. Screens and deliberate differences from the mockup

All mockup screens are built. Differences on purpose:

| Area | App | Why |
|---|---|---|
| Brand | "Chess" | Single-game app for now |
| Home game chips | Chess, Snakes & Ladders and Ludo are playable; the rest show **Soon** | Only those three have a game area (see `lib/configs/games/`) |
| Ludo / Snakes & Ladders | Quick Play vs computer (2–4 players, pick your colour); 2D/3D board toggle; animated 3D die; online play shows "coming soon" | Their socket protocols aren't integrated yet; pause / forfeit / results are the shared chess ones |
| Online Play sheet | No "How many players?" step; 2P badges; added a **Choose your side** (White/Black) step; CTA "Find match" | Chess is always 2 players; the side is sent as the matchmaking seat |
| Matchmaking (online) | Real search with a 60 s countdown under the empty seat; no opponent level chip | Driven by the server, not the mockup's fixed timings; a live opponent's level isn't sent |
| Register | **Username** field (mockup: Full name) | The API requires a username |
| Quick Play | Setup (side, difficulty, time per move) → vs computer | The mockup's Quick Play is a free online match |
| Chess board | Neon glass board, drawn 3D pieces, 2D/3D toggle | Chosen look; no image assets |
| Game History | All / Wins / Losses filter | Added |
| Join room | Phone keyboard (letters + digits) | The mockup keypad can't type real codes like `AX7K2Q` |
| Tournaments CTAs | Join → "Joined ✓", Watch → note, Past → Results | Realistic behaviour (mockup shows Join on past events) |
| Settings | "Demo states" only in debug builds | Prototype-only shortcuts |

**Behaviour rules:** everything should feel like a shipped app — realistic
pacing (the computer's thinking time scales with difficulty; a 0.6 s hand-over
before the next player's clock starts), state that changes after actions, and
no prototype oddities. A screen never navigates after a request unless it is still the one on
top, and only one action can run at a time (`BusyGuard`).

---

## 3b. Translations

Flutter's built-in `gen-l10n`: one ARB file per language in `lib/l10n/`
(`app_en.arb` is the template), generated into `lib/l10n/gen/` on build.
Screens use `context.l10n.<key>` (placeholders: `l10n.newToApp(name)`;
plurals: `l10n.spinsLeft(n)`). The language picked on the Language screen,
or saved in the profile, sets the app locale. A language without an ARB file
shows English.

- **Add a text:** add the key to `app_en.arb`, then to every other ARB file
  (`test/l10n_test.dart` fails if a language is missing a key), then use
  `context.l10n.key`.
- **Add a language:** copy `app_en.arb` to `app_<code>.arb` and translate it.
  `<code>` matches `appLanguages` in `lib/data/languages.dart`.
- **Status:** English + Hindi (machine-drafted — needs native review). Translated
  screens: Splash, Language, Login, Home. The other screens are still English
  (in progress).

## 4. Loading states

0. **App start** — native splash (dark + orb) → Flutter splash with a
   progress bar that follows the real startup steps (`lib/app/startup.dart`:
   fonts and saved preferences, session restore, game socket, Home data) and a
   status line. It ends on Language (first launch), Home (saved session) or
   Login. Offline or server errors show a message with Retry, and the saved
   session is kept.

1. **Button spinner** — `GradientButton(loading: true)` for one-shot actions
   (Log In, Create Account, Save profile). Blocks re-taps while in flight.
2. **Skeleton** — `AsyncView` shows mockup-style shimmering rows while a
   screen's data is loading (Store, Tournaments, Friends, Leaderboard, Inbox,
   Game History). Only where a real service is awaited — no fake delays.

---

## 5. Required assets

> **Asset rule.** Whenever a screen needs an asset (logo, badge, avatar, flag,
> product art…): record it in this table first; use a drawn shape, system
> icon or online image as a placeholder; swap in the real file when provided.

Nothing below needs a bundled file to run today.

| Asset | Usage | Size | Status |
|---|---|---|---|
| App logo mark ★ | Login, splash | 24–150 px | Placeholder (drawn gradient ring + dot) |
| App launcher icon ★ | Android/iOS/macOS home screen | 1024² + mipmaps | Default Flutter icon — pending |
| Display + body fonts | All text | — | **Bundled** Space Grotesk + Manrope TTFs in `assets/google_fonts/` (Latin; other scripts use the system font) |
| Native splash logo | Launch screen before Flutter starts | 600² / 960² (Android 12) | `assets/splash/` — the orb rendered from `AuraOrb`; regenerate with `dart run flutter_native_splash:create` |
| Google "G" logo ★ | Google sign-in | 18 px | Placeholder (drawn) |
| Apple glyph | Apple sign-in | 18 px | System icon |
| Country flags | Name rows (Home, Profile) | 13–16 px | Emoji from the profile's country code |
| User avatars | HUD, Profile, cards, lobby | 40–120 px | Initials on gradient (API `avatar_url` not used yet) |
| Gem / coin | Currency everywhere | 14–20 px | Drawn (`CurrencyGlyph`) |
| Chess board + pieces | Game area | board + 12 pieces | **Final:** drawn vector pieces and board (no assets will be provided) |
| Achievement / tournament icons | Achievements, Tournaments | 30–54 px | System icons on gradient tiles |
| Bottom-nav icons | Home/Wheel/Store/Profile | 23 px | Drawn from the mockup's SVG paths |
| Ad banner creative | Home ad slot | 320×50 | House-ad text placeholder |
| Snakes & Ladders / Ludo boards, pawns, die | Game areas | — | Drawn in code (`lib/game/snakes`, `lib/game/ludo`, `lib/game/common`) — no assets needed; swap in art if provided |
| Other games' boards ★ | Othello and the rest | — | Needed when those game areas are built |

★ = a real asset is wanted; send it and it replaces the placeholder.
