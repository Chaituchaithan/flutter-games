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

### Spacing
- **Page margin** `kPageGutter` = 16 px left and right on every screen (game screens 12 px, so boards are larger).
- **Sideways-scrolling rows** (Home game chips, game result strips) run to the screen edges with `EdgeBleed`; their first item still lines up with the margin.
- **Bottom bar** floats on top of the phone's own bottom area (`viewPadding.bottom`: iPhone home indicator, Android 3-button or gesture bar); 10 px when the system takes no room.

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
| Home game chips | All 14 games are playable: Chess, Snakes & Ladders, Ludo, Othello, Scrabble, Checkers, Crash, Bingo, Roulette, Poker, Racing, Rummy, Uno and Carrom | Each has a game area (see `lib/configs/games/`) |
| Ludo / Snakes & Ladders | Quick Play vs computer (2–4 players, colour, **time per turn: 30 s / 1 min / 2 min / Unlimited**); chess game-area layout (`DiceBoardLayout`: opponent cards with timer rings, Last move, [Turn clock] · dice slot · You card, action bar; Snakes shows no Turn clock panel, since the card timer rings show the time); 2D/3D toggle; animated 3D die. When time runs out, the turn is played for you (auto-roll / auto-move), not a loss. Online play shows "coming soon" | Same look and clock as chess; their socket protocols aren't integrated yet |
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
- **Status (154 texts):** English + Hindi (machine-drafted — needs native review).
  Translated: Splash, Language, Login, Register, Home, Settings, Change
  password, Profile, Edit profile, Daily Rewards. Still English: game screens,
  Store, Friends, Tournaments, Season Pass, Inbox, results, dialogs, and
  validation messages (in progress).

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
| Othello / Checkers / Scrabble | Quick Play vs computer (3 difficulty levels). Setup: side · difficulty · time. Chess layout and frame. Othello: green felt, flipping discs, move hints. Checkers: wooden board, ridged pieces, crowned kings, tap-by-hop multi-jumps. Scrabble: 15×15 premium board, wooden rack, Shuffle/Recall · Swap · Pass · Play with live score | Othello and Checkers: running out of time loses (as in chess). Scrabble: 1/2/5 min or unlimited per turn, and time up = pass. Online play waits for the socket protocols |
| Scrabble word list | Scrabble | 1.6 MB | `assets/scrabble/words.txt` — ENABLE (public domain, 168,551 words); compiled into Scrabble's code by `tools/gen_scrabble_words.dart`, so only the Scrabble app carries it. It lacks a few newer words (QI, ZA); swap in a licensed list if wanted |
| Crash (Aviator style) | Continuous rounds: 6 s betting, then a rising multiplier until it "flies away" (fair crash point, 1% edge). Two bet panels with auto cash-out, recent results, live bets of computer players. Effects: exhaust trail, drifting stars, milestone pulses (2×, 3×, 5×…), a coin + confetti burst and "CASHED OUT" banner on your cash-out, floating tags for other players' cash-outs, red flash + sparks + shake when it flies away; the balance counts up with a glow | **Practice chips only** (1,000, top-up when empty), separate from Tokens/Gold: real-money crash is gambling and needs store/legal approval |
| Bingo | 75-ball, 2–4 players vs computer. Patterns: Line / Four corners / Full house. Call speed Fast / Normal / Slow. Tap called numbers to daub (or auto-daub); BINGO! claims, and a false claim locks for 4 s. Ball blower with tumbling balls, the drawn ball rolls out; classic calls ("Legs eleven", English only); tap the caller for the 75-number board. Called-but-unmarked numbers glow (hand daubing), "1 TO GO" cells shine amber, ink-stamp daubs; your win lights the winning cells in turn with confetti and a BINGO! shout, a computer win shows its banner |
| Roulette | Three tables, picked on the setup screen: **European** (single 0, 2.70% edge), **French** (single 0, La Partage — even-money bets get half back on 0, 1.35%) with French labels (Manque / Pair / Impair / Passe, P12 / M12 / D12), and **American** (0 and 00, 38 pockets, 5.26%). Practice chips. Vertical table: tap a number (straight 35:1), the line between two (split 17:1), a crossing (corner 8:1), a row's left edge (street 11:1); dozens, columns (2:1) and even-money bets. Undo / Clear / Double / Repeat. Casino look: the wheel sits at the head of the table in perspective and turns slowly between spins; SPIN zooms in on it (ball runs the track, drops with bounces, settles), shows the number, then pulls back to the table where a dolly marks it and winning chips glow. Table printed on baize inside a leather rail (cream grid, arched 0), LED results board, wooden chip tray, gold SPIN button | Practice chips (5,000), separate from Tokens/Gold |
| Poker | Texas Hold'em, 2–6 players vs computer; stakes 1K·10/20, 2K·25/50, 5K·50/100; time per move. Blinds, four betting rounds, side pots, split pots; raise panel (Min / ½ Pot / Pot / All-in + slider). Cards dealt from the centre, the board turns over, the pot slides to the winner, winning cards outlined | Computers estimate their chance by simulation; difficulty sets accuracy and bluffing |
| Racing | Six cars, odds from each car's form (8% margin); Win and Top 3 bets. The race: side view following the leader, grandstand, lane markings, distance boards, checkered finish; live standings that re-order, commentary (lead changes, final stretch, photo finish); podium and payout | Practice chips (5,000) |
| Rummy | 13-card points rummy (2 decks + 2 printed jokers, cut wild joker), 2–4 players vs computer. Closed / open deck, Sort (best melds), Group, Discard, Declare (checks the show first; a wrong show costs 80), Drop (20 / 40). Groups labelled Pure sequence / Sequence / Set / Invalid; live points | Losers score unmelded cards, capped at 80 | Computer daub/claim speed follows difficulty |
| Uno | One round, 2–4 players vs computer (3 levels), 15 s / 30 s / unlimited per turn. Full 108-card deck: Skip, Reverse (= Skip with two players), +2, Wild, Wild +4; the first card turned up is a number. Draw one — play it or Keep. Tap UNO! before going down to one card, or draw 2. Cards are our own drawn design (no brand on them; the back says AURA). Card table from above (wooden rim, baize): opponents seated round it with their cards fanned, avatar, turn ring and count; an animated deal; cards fly from hand to pile and from the deck to hands; your hand fans in an arc (playable cards lift, the rest dim); the pile is ringed in the colour in play and a ring of arrows turns with the direction | "UNO" is a Mattel trademark: the name is `unoConfig.displayName` and the `unoCall` string — rename both before a store release |
| Carrom | You (white, bottom) vs computer (black, 3 levels), 30 s / 1 min / unlimited per shot. Slide the striker on the baseline (on the board or the slider), drag back from it to aim: a dotted guide to the first coin, a ghost striker, the coin's path and a power ring. Real physics (friction, mass, bounces, pockets). Rules: own coin = shoot again; the queen counts only after one of yours and must be covered next shot; striker in a pocket = foul (a coin comes back); your last coin before the queen is covered comes back. Board points = the loser's coins left + 3 for the queen. Look: mitred wooden frame with grain, lacquered plywood under an overhead light, leather pockets with nets, coins with turned grooves and motion trails, "+1" / ♛ / FOUL rising from pockets, the shooter's baseline glows, a coin tray per player, 2D / tilted 3D view | Board, coins and striker drawn in code — no assets |
| Board frame + palette (all board games) | Game areas | — | `GameBoardFrame` + `BoardPalette` (`lib/game/common/board_frame.dart`): the chess bezel, neon edge, sheen and lavender / deep-violet squares; 3D tilts inside the frame |
| Snakes & Ladders / Ludo boards, pawns, die | Game areas | — | Drawn in code (`lib/game/snakes`, `lib/game/ludo`, `lib/game/common`) — no assets needed; swap in art if provided |
| Other games' boards ★ | Othello and the rest | — | Needed when those game areas are built |

★ = a real asset is wanted; send it and it replaces the placeholder.
