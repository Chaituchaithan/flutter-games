# Aura — Flutter UI Build Spec

Static UI recreation of the "Aura Game UI" prototype (a stake-based multiplayer
game). This phase is **presentation only** — real data, networking and game logic
come later. Every screen is dark-themed, mobile-portrait, and shares one visual
system.

**Auth / data:** currently there is **no API** — auth buttons (Log In, Create
Account, social, Send code, Verify) just navigate. The button handlers are the
single integration point: drop a **mock API** here now and swap in the **real
API** later without touching the UI.

## Design tokens (see `lib/theme.dart` → `AuraColors`, `AuraGradients`, `AuraText`)

- **Background** `#0C0A16`, with a purple radial glow (top-left) and magenta glow
  (bottom-right) — provided by `AuraBackground`.
- **Brand gradient** `#8B5CF6` (purple) → `#EC4899` (pink) → `#FB923C` (orange).
  Used on primary buttons, active pager/segments, the "You"/orb avatars, progress
  bars, and the wheel center.
- **Gems** = cyan diamond `#38BDF8`; **Gold/coins** = amber `#F5B301`.
- **Accent green** `#10B981` (Quick Play, Live, wins, win-rate ring).
- **Cards** `#17141F` on `#1A1726`, hairline border `white @ 8%`, radius 18–22.
- **Text**: primary `#F5F3FF`, secondary `#9A93B0`, muted/skip `#6E6880`.
- **Display font**: rounded geometric; currently system `w800` via `AuraText`
  (single hook to swap in a bundled font later).

## Shared widgets (see `lib/widgets/`)

Build every screen from these — do not re-invent them:

- `AuraBackground(child)` — dark bg + glows. Wrap each screen body.
- `AuraScaffold(...)` — Scaffold + AuraBackground + SafeArea helper.
- `GradientButton(label, onPressed)` — full-width brand-gradient pill.
- `SecondaryButton(label, onPressed)` — dark outline pill (e.g. "Continue as guest").
- `AuraTextField(hint, icon, obscure, trailing)` — dark rounded input.
- `CurrencyPill(kind: gems|gold, amount, showPlus)` — the 10,000 / 3,000 chips.
- `AuraAppBar(title, showBack, trailing)` — back chevron + centered title.
- `SegmentedTabs(labels, index, onChanged)` — Store/section pill tabs.
- `AuraBottomNav(index, onChanged)` — Home · Wheel · Store · Profile floating bar.
- `SectionHeader(text)` — small uppercase grey label.
- `LetterAvatar(letter, color, size, glow)` — gradient circle w/ initials.
- `Badge(text, color)` — SOON / POPULAR / MEGA / +10% pills.
- `AuraToggle(value, onChanged)` — gradient iOS-style switch.
- `StatTile(value, label, valueColor)` — Profile stat block.

## Routing (see `lib/app/routes.dart`, `lib/app/main_shell.dart`)

- `/onboarding` → `/login` (Skip / Get Started).
- Login ↔ Register; both → `MainShell`.
- `MainShell` = `IndexedStack` over Home/Wheel/Store/Profile + `AuraBottomNav`.
- Home "Online Play"/"Play" → match flow: setup(3 steps) → preview → result.
- Profile gear → Settings.

---

## Screens

### 1. Onboarding — DONE (`lib/onboarding/`)
3 slides (Find your people / Share your moment / Always in sync), pager, Continue →
Get Started.

### 2. Login — "Welcome back"
Back chevron. Aura logo (gradient ring + dot) + "Aura". Title **Welcome back**,
sub "Log in to pick up where you left off." White **Continue with Apple** (apple
glyph), dark **Continue with Google** (G). Divider "or log in with email". Fields:
Email (mail icon), Password (lock icon + eye toggle). Right-aligned **Forgot
password?** (brand color). **Log In** (gradient). **Continue as guest** (dark).
Footer "New to Aura? **Create account**".

### 3. Register — "Create account"
Back chevron. Title **Create account**, sub "Join the community in under a minute."
Two compact buttons side-by-side: **Apple** / **Google**. Divider "or sign up with
email". Fields: Full name (person icon), Email (mail), Create password (lock + eye).
Checkbox row "I agree to the **Terms** & **Privacy Policy**". **Create Account**
(gradient). Footer "Already have an account? **Log in**".

### 4. Home
Scroll. **Profile header card**: avatar "NR" w/ level badge 7, "Nova Rider" 🇫🇷,
@nova_rider, right side two `CurrencyPill`s (10,000 gems +, 3,000 gold +), then
`LV 7` chip + gradient progress bar + "1,300 / 2,000".
**Featured hero** (brand-gradient card): "FEATURED", `2P · 4P` badge, **Online
Play**, "Stake to enter · winner takes the pot", `♦ 50 – 5K` chip, **Play →**.
Tapping opens the match flow.
Row of two cards: **Quick Play** (green play icon, "Free practice match") /
**Friends** (purple people icon, "Play with a room code").
**Tournaments** list row (gold trophy, "Bracket events · opens Friday", `SOON`).
**Ad banner**: "AD · 320 × 50", "Banner placement", "House ad fallback · remove
with VIP", ✕.
**Earn rewards** header → two cards: **Daily Bonus** ("Day 3 ready", calendar) /
**Lucky Wheel** ("3 spins left", target). **Recent matches** header + list.

### 5. Wheel — "Lucky Spin"
Title **Lucky Spin** + gems/gold pills. Chip "↻ 3 free spins left". Large
8-segment fortune wheel with top pointer ▼; segments (clockwise from top):
500 Tokens, 200 Gold, 1,000 Tokens, 50 Gold, 500 Gold, 2,000 Tokens, JACKPOT
5,000, 100 Tokens. Center circular **SPIN** button (brand gradient, dark ring).

### 6. Store
`AuraAppBar` "Store" + gems/gold pills. `SegmentedTabs`: Tokens / Gold /
Power-Ups / VIP (Tokens active). 2-col grid of packs, each: corner badge
(+10% / POPULAR / +25% / +40% / MEGA), diamond icon, amount, blue-gradient price
button. Packs: 1,000 $0.99 · 5,500 $3.99 (+10%) · 12,000 $7.99 (POPULAR) ·
30,000 $14.99 (+25%) · 70,000 $29.99 (+40%) · 150,000 $49.99 (MEGA).

### 7. Profile
`AuraAppBar` "Profile" (back + gear→Settings). Big avatar "NR" (gradient) with
edit-pencil badge. "Nova Rider 🇫🇷", "@nova_rider · Level 7 · Gold III". Three
`StatTile`: 248 Matches / 169 Wins (green) / 7 Streak (amber). Two cards:
**win-rate ring** 68% (green arc) + **"Last 7 days"** bar chart (M T W T F S S,
bars brand-gradient). **Achievements** header + 4 tiles: First Win, On Fire,
Sharpshooter, Locked (greyed). Button **View full match history**.

### 8. Settings
`AuraAppBar` "Settings". Gold **Upgrade to VIP** banner ("2× rewards, no ads &
more", crown, chevron). `PREFERENCES` toggles: Sound effects ON, Music ON,
Notifications ON, Haptics OFF (`AuraToggle`). `ACCOUNT` list rows: Edit profile,
Change avatar, Game history. `SUPPORT`: Help center, Privacy policy, App version
`1.0.0`. Destructive **Log out**.

### 9–11. Match setup (bottom-sheet style, 3 steps)
Each: drag handle, "‹ back", step pill (`1/3`, `2/3`, `3/3 · buy-in`), title, sub.
- **1/3 How many players?** "Pick the match size" → two big option cards:
  **2** "Players · 1v1" (2 dots), **4** "Players · free-for-all" (4 dots, selected
  = brand border).
- **2/3 Choose your stake** "Token or Gold buy-in" → **Tokens** (diamond, "Balance
  10,000", selected) / **Gold** (coin, "Balance 3,000").
- **3/3 How many tokens?** "2 Players · Tokens". `PICK A TIER` 3×2 grid: 50/pot
  100, 100/pot 200, 200/pot 400 (selected), 500/pot 1,000, 1k/pot 2,000, 2k/pot
  4,000. `CUSTOM AMOUNT` "min 50 · max 5,000" stepper (− 200 +). Summary: YOUR
  STAKE 200, TOTAL POT · 2× **400** (amber). **Preview match →**.

### 12. Match preview
Drag handle, "‹ back", "preview" pill. Title **Match preview**, "Online · 2P ·
Tokens". Card: **NR** avatar **VS** **?** avatar, "Matching you with 2 players
online". Rows: Entry stake 200, Total prize pot **400** (amber), Format **Winner
takes all**. **Create game** (gradient).

### 13. Match result
Centered. Big rounded icon tile (red ✕ for defeat / could be green ✓ for victory).
Title **DEFEAT** (bold), sub "So close — run it back." Score row: **NR** "You"
`1 : 3` **RV** "Rival". Chip "⚡ +20 XP". **Play Again** (gradient), **Back to
Home** (text/dark).

---

## Required Assets

> **Asset rule (current policy).** Whenever a screen needs an asset (logo, badge,
> avatar, flag, product art, etc.):
> 1. **Record it in this table** — never introduce an undocumented asset dependency.
> 2. **Use an online icon/image (network URL) as the placeholder for now** rather
>    than bundling a file or hand-drawing it.
> 3. The **real asset files will be provided later** and swapped in; the online
>    sources are temporary stand-ins.

Everything below is currently rendered with **Flutter-drawn shapes, gradients,
Material/Cupertino icons, or online (network) images** — no bundled image files
are needed to run the static build. This table lists what a production build would
want, and flags where a real asset should replace a placeholder. **If you can
provide the ★ items I'll drop them in; otherwise the online/drawn placeholders stand.**

| Asset | Type | Usage | Size / Dimensions | Status |
|---|---|---|---|---|
| App logo "Aura" mark | SVG/Icon | Login/Register header, splash | 24–32 px | Placeholder (gradient ring + dot, drawn) |
| App launcher icon ★ | PNG set | Android/iOS home-screen icon | 1024² (+ mipmaps) | Pending |
| Display/rounded font ★ | Font (ttf/otf) | All titles & buttons | — | Placeholder (system `w800`) |
| Apple glyph | Icon | Apple sign-in button | 18 px |  Placeholder (`Icons`/drawn) |
| Google "G" logo ★ | SVG (multicolor) | Google sign-in button | 18 px | Placeholder (drawn) |
| Country flag 🇫🇷 | Emoji/Image | Profile name row | 16–20 px | Placeholder (emoji) |
| User avatar "NR"/"RV" | Image | Header, Profile, match VS | 40–120 px | Placeholder (initials on gradient) |
| Gem/diamond icon | Icon/SVG | Currency pills, Store, wheel | 16–20 px | Placeholder (drawn diamond) |
| Gold coin icon | Icon/SVG | Currency pills, wheel | 16–20 px | Placeholder (drawn coin) |
| VIP crown icon | Icon/SVG | Settings VIP banner, Store VIP | 20–24 px | Placeholder (`Icons`) |
| Trophy icon | Icon | Tournaments row | 20 px | Placeholder (`Icons`) |
| Achievement badges (4) ★ | SVG/PNG | Profile achievements | 40 px | Placeholder (icon + gradient) |
| Featured/"Online Play" art | Image (opt) | Home hero card background | full-width | Placeholder (gradient) |
| Post image (onboarding) | Image | "Share your moment" card | ~240×118 | Placeholder (gradient) |
| Tab bar icons (4) | Icon | Home/Wheel/Store/Profile | 24 px | Placeholder (`Icons`) |
| Ad banner creative | Image | Home ad slot | 320×50 | Placeholder (house-ad text) |

Legend: **Provided** = shipped file · **Pending** = waiting on you (★) · **Placeholder** = drawn/system stand-in that works today · **Online placeholder** = temporary network image/icon, to be swapped for a provided file later.
