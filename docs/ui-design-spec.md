# Space — Flutter UI Design Specification (from source)

Extracted read-only from `apps/frontend/`. All token values cite source files/lines. Values not found in source are flagged **"Not verified in source."**

---

## 1. Design tokens — colors (`lib/theme.dart`)

`SpaceColors` is a `ThemeExtension` (`lib/theme.dart:5–179`). `SpaceColors.of(context)` falls back to **dark** when no extension is present (`theme.dart:100–101`). Global const `spaceAccent = Color(0xFFADC6FF)` (`theme.dart:3`).

| Token | Dark | Light | Semantic usage |
|---|---|---|---|
| `background` | `0xFF05070A` | `0xFFF4E7D0` | Scaffold base (`theme.dart:53,77`) |
| `surface` | `0xFF111417` | `0xFFF9EEDC` | Dialogs, bottom sheets, nav surfaces |
| `surface2` | `0xFF1A1E24` | `0xFFE9D5B8` | Text field fills, snackbar bg, reaction btns |
| `surface3` | `0xFF242A33` | `0xFFD9B98D` | Nested surfaces (unused directly in main UI paths) |
| `card` | `0x9911141B` | `0xCCFFF6E8` | Glass panels, message bubbles (others'), step cards |
| `primaryText` | `0xFFE1E2E7` | `0xFF090807` | Main headings/body |
| `secondaryText` | `0xFFC2C6D6` | `0xFF3D3329` | Supporting text, coordinates |
| `disabled` | `0xFF8C909F` | `0xFF776A5C` | Disabled text, hints, meta |
| `accent` | `0xFFADC6FF` | `0xFFC45A11` | Primary accent (light = burnt orange, dark = soft blue) |
| `secondaryAccent` | `0xFFB79CFF` | `0xFF8F3208` | Gradient partner (purple / deep brown) |
| `tertiary` | `0xFF37D399` | `0xFF20735B` | "inside" decision, success green |
| `onAccent` | `0xFFFFFFFF` | `0xFF090807` | Text/icon on accent gradients |
| `danger` | `0xFFFFB4AB` | `0xFFBA1A1A` | Destructive actions, "Leave" |
| `warning` | `0xFFFFD166` | `0xFF9A4A05` | nearBoundary / lowAccuracy, amber |
| `dangerStrong` | `0xFFFF7B72` | `0xFF93000A` | outside / rejected, error text |
| `outline` | `0x14FFFFFF` | `0x66906D45` | Borders (very subtle) |
| `outlineSubtle` | `0x0DFFFFFF` | `0x40A9875C` | Slider inactive track |
| `gradientTop` | `0xFF111827` | `0xFFFBECD3` | Radial bg top |
| `gradientBottom` | `0xFF05070A` | `0xFFF4E7D0` | Radial bg bottom |
| `navBackground` | `0x991D2023` | `0xE6F5E7D2` | Bottom nav bar |
| `chipBackground` | `0x14282A2E` | `0x99FFF6E8` | Glass chips, glass icon buttons |

Raw `Colors.*` used in `main.dart`: `Colors.transparent` (nav, Materials), `Colors.white` α 0.46/0.82/0.16/0.08 (glass panel light fill/borders, mine-bubble quote bg), `Colors.white70` (mine poll text), `Colors.white54` (mine poll border), `Colors.black` α 0.05 (others' bubble shadow). No `Color(0x…)` literals in `main.dart`.

**Format note:** `0xAARRGGBB` — e.g. `card = 0x9911141B` = 60% alpha over `#11141B`; `outline = 0x14FFFFFF` = 8% white.

## 2. Typography (`lib/theme.dart:181–282`)

Families: `Montserrat` (heading), `Hanken Grotesk` (body), `JetBrains Mono` (technical). **Not bundled** — `pubspec.yaml` has no `fonts:` section, so Flutter falls back to default (system). Theme-level `fontFamily: 'Hanken Grotesk'` (`theme.dart:306`).

| Style | Family | Size | Weight | Height | LetterSp | Default color |
|---|---|---|---|---|---|---|
| `headingLarge` | Montserrat | 26 | w700 | — | 0 | `0xFFF8FAFC` |
| `headingMedium` | Montserrat | 18 | w700 | — | 0 | `0xFFF8FAFC` |
| `headingSmall` | Montserrat | 15 | w600 | — | var | `0xFFF8FAFC` |
| `bodyLarge` | Hanken Grotesk | 15 | w400 | 1.4 | var | `0xFFF8FAFC` |
| `bodyMedium` | Hanken Grotesk | 13 | w400 | 1.4 | var | `0xFFA1AAB8` |
| `bodySmall` | Hanken Grotesk | 12 | w400 | 1.3 | var | `0xFF6B7280` |
| `technical` | JetBrains Mono | 11 | w600 | — | 0.4 | `0xFFA1AAB8` |

**Hardcoded overrides in components** (`main.dart` unless noted):

| Use | Size/Weight | Color | Source |
|---|---|---|---|
| `_SpaceTopBar` + Location header "Space" | 31 / w800 | accent | main.dart:2486–2491; location_selection_screen.dart:321–330 |
| Greeting "Good …," / "My Spaces" | 32 / w800, h 1.15 | primaryText | main.dart:1907–1924, 2341 |
| Chat header space title | 22 / w800 | accent | main.dart:1545–1550 |
| Create Space title | 24 / w700 | accent | main.dart:711 |
| Section headers ("2. Geofence") | 23 / w700 | primaryText | main.dart:789 |
| Space card name | 21 / w800, h 1.12 | primaryText | main.dart:2917–2923 |
| Empty-state title | 20 / w800 | primaryText | main.dart:2693 |
| Message body | 16 / w400, h 1.38 | white (mine) / primaryText | main.dart:3424–3431 |
| Primary buttons (icon label) | 15 / w800; Location variant 16 / w800 | onAccent | main.dart:2791, 3823; location…:711–716 |
| Glass chip label | 11 / w800, ls 0.7 | accent | main.dart:2609–2614 |
| Distance/status text | 12 / w800 (CTA), 14 / w400 (desc), 13 (coords) | activeColor / secondaryText | main.dart:2965, 2931; location…:557 |
| Poll vote total | 12 | white70 / secondaryText | main.dart:3478 |

## 3. Spacing & radius

**Screen padding** (`main.dart`): Discovery/MySpaces body `LTRB(24,32,24,20)` headers, grid `LTRB(24,8,24,112)` (112 = FAB clearance); CreateSpace list `LTRB(20,16,20,118)`; Chat list `LTRB(16,16,16,18)`; Empty/error `all(24)`. Location screen horizontal pad 24 (18 when compact), confirm bar bottom 20.

**Recurring gaps (SizedBox):** 6, 8, 10, 12, 14, 16, 18, 20, 22, 34.

**Radii:**

| Value | Where |
|---|---|
| `999` (pill) | Buttons, chips, icon buttons, field, slider track, map controls — 11 uses `main.dart` + theme |
| `24` | Dialogs (`theme.dart:326`, all AlertDialogs), glass panels, chat header panel |
| `28` | Space cards, chat composer top, nav top, map container placeholders |
| `22` | Chat top-bar bottom, bubble `topLeft/topRight + one bottom corner 22` / other bottom 5 (`main.dart:3312–3317`) |
| `20` | Step cards, snackbar, result list, search results |
| `18` | Reply strip panel, chips radius (reaction btn 12) |
| `16` | Text fields (`main.dart:3611`), geo panel inner |
| `14` | FilledButton inside dialogs |
| `12` | Reply quote block, poll option buttons |
| `32` / `30` | Location glass panel default / confirm bar (`location_selection_screen.dart:591–592, 542`) |

## 4. Gradients, borders, shadows

**Primary brand gradient** — `LinearGradient([accent, secondaryAccent], topLeft → bottomRight)`, used identically in 5 places (`main.dart:2640` FAB, `2763` _SpaceButton, `3265` send, `3367` mine-bubble, `3785` SpaceButton). Variants: space-card avatar `[activeColor α0.92, secondaryAccent α0.82]`; **Location** primary button accent→secondaryAccent.

**Screen background (`SpaceScaffold`, main.dart:3838–3899, 4 stacked layers):**
1. `RadialGradient(center: topRight, radius 1.18, [gradientTop α0.92 dark / α0.7 light, gradientBottom], stops [0, 0.62])`
2. `RadialGradient(center: centerLeft, radius 1.08, [accent α0.07 dark / α0.10 light, transparent], stops [0, 0.48])`
3. `_StarfieldPainter` — 12 fixed stars (normalized offsets listed `main.dart:3906–3919`), radius 1.1 px, color white α0.16 (dark) / accent α0.10 (light)
4. Content.

**Location screen background** (`location_selection_screen.dart:253–293`): 3-stop `LinearGradient(topCenter→bottomCenter)` stops `[0,0.56,1]` — dark `#111827 → background → #02040A` / light `#FFF1D9 → background → #FFF6E8`; plus `RadialGradient(0,0.15, r0.82, #C0C1FF α0.10/0.30 → transparent)`.

**Shadows (BoxShadow):**

| Component | Color/α | Blur | Offset | Source |
|---|---|---|---|---|
| Primary buttons | accent α0.28 | 24 | (0,8) | main.dart:2770, 3791 |
| Location primary button | accent α0.25 | 24 | (0,8) | location…:697 |
| FAB | secondaryAccent α0.36 | 24 | (0,8) | main.dart:2645 |
| Card avatar | activeColor α0.24 | 18 | none | main.dart:2865 |
| Mine bubble | accent α0.16 | 18 | (0,8) | main.dart:3378 |
| Others' bubble | black α0.05 | 18 | (0,8) | main.dart:3379 |
| Map container | accent α0.12/0.08 | 28 | (0,12) | interactive_geofence_map.dart:110 |
| Bottom nav (upward) | accent α0.08 | 24 | (0,-6) | main.dart:366 |
| Send button | accent α0.24 | 20 | — | main.dart:3271 |
| Pin halo / dot | accent α0.30 / α0.70 | 26 / 14 | — | map:174–193 |

**Borders:** default width 1 (outline); picker decisions map circle stroke 2; pin ring 1.6; my-reply quote left border 2 solid white (mine) / accent (other), radius 12, bg whiteα0.16 / accentα0.08 (`main.dart:3389–3422`).

## 5. Reusable components (`lib/main.dart`)

| Component | Line | Key values |
|---|---|---|
| `_SpaceTopBar` | 2449 | h64, frosted `surface α0.58` + blur 18, bottom radius 22, bottom outline border, title Montserrat 31 w800 accent; glass icon buttons both sides |
| `_GlassPanel` | 2503 | blur 16, padding all 18 (default), radius 24; fill `card α0.62` (dark) / `white α0.46` (light); border white α0.08 / α0.82 |
| `_GlassIconButton` | 2543 | 44×44, `chipBackground`, radius 999, outline border, icon 21 accent |
| `_GlassChip` | 2579 | pill, `chipBackground`, outline border, padding h11 v7, label 11 w800 ls0.7 accent, opt icon 14 |
| `_GradientFab` | 2623 | 64×64 circle, brand gradient, shadow, icon 31 onAccent |
| `_EmptyState` | 2659 | icon tile = glass panel radius 999 pad 22, icon 42 accent; title 20 w800; optional outline pill action btn (radius 999, padding h18 v12) |
| `_SpaceButton` / `SpaceButton` | 2746 / 3764 | h56 pill, brand gradient, shadow, icon 20 + label 15 w800 onAccent; public adds 18×18 spinner (stroke 2) loading state |
| `_SpaceCard` | 2806 | glass panel radius 28 pad 20; avatar 48×48 circle gradient; invite (vpn_key), leave (logout, **danger**), badge chip (Owner/Joined/distance); name 21 w800; stat chips `people_alt` + `public`; CTA pill h44 border activeColor α0.72, label 12 w800 ls1.2; icon pool: terminal/headphones/cafe/nightlife/restaurant/bolt/blur_on (_rounded) |
| `StepCard` | 3533 | radius 20, `card` fill, outline border, pad 18; step number 12 disabled, title headingSmall |
| `SpaceTextField` | 3573 | `surface2` fill, radius 16, contentPad h16 v14, hint disabled, focused border accent 1.5 |
| `ChoicePill` | 3628 | pill, `AnimatedContainer` 180ms; selected = accent α0.14 fill + accent border + accent text; unselected `chipBackground` + outline + primaryText; leading StatusDot (9×9, hollow variant) |
| `StatusDot` | 3939 | 9×9 circle, border 1.6 |
| `_ReactionButton` | 4013 | `surface2`, radius 12, outline border, pad h10 v7, emoji 19 |
| `GeofenceDecisionPanel` | 3688 | decision→color: inside→**tertiary**, nearBoundary/lowAccuracy→**warning**, outside/rejected→**dangerStrong**; labels: "Inside perimeter / Near boundary / Outside perimeter / Low accuracy / Rejected"; compact = chip; full = icon circle 42×42 (fill α0.12, border α0.3), label 15 w800, "χm from center" 12 secondary |

**Dialogs** (`theme.dart:322–345` + main.dart): bg `surface`, tint transparent, radius 24, outline border 1; bottom sheets top radius 24; snackbars floating, `surface2`, radius 16, outline 1. Dialog FilledButtons radius **14**. `PollComposerDialog` width 360, `SizedBox` question maxLength 280, options maxLength 100, 6 controllers start at 2, add/remove via `Icons.add/remove` with tooltips.

**Bottom nav** (`main.dart:353–411`): frosted wrapper (blur 18, top radius 28, top outline border, shadow), `NavigationBar` h76, indicator accent α0.20 (theme default α0.15), tabs: Explore (`explore_outlined/_rounded`), My Spaces (`layers_outlined/_rounded`), icons 23, labels Montserrat 12 w700 selected (accent) / w500 (disabled).

## 6. Screens (layouts)

| Screen | Layout |
|---|---|
| **Splash (`OrbitOpeningScreen`)** | `Scaffold` bg background → bg gradient → orbit `OrbitAnimation` 256 + static spinner 34×34 (stroke 2.4) → title 32 w800 h1.16 accent "Finding your orbit…", subtitle 15–17 w500 secondary (maxWidth 290) `location_selection_screen.dart:57–102` |
| **Location** | header (Space 31 w800, blur icon) → orbit 232 (178 compact / 132 veryCompact) → copy → map (radius **100 m hardcoded**) → confirm bar. Button label logic: "Detecting orbit…" / "Use current orbit" / "Open app settings" / "Open location settings" / "Retry current orbit" (`location_selection_screen.dart:386–397`) |
| **Discovery** | `_SpaceTopBar('Space', language → change location, theme toggle)` → greeting 32 w800 ("Good Morning/Afternoon/Evening/Night, **Explorer.**") → orbit 104 → coord chip → "Join with Invite" → responsive grid of `_SpaceCard`s → FAB |
| **Create Space** | Steps: Identity (name ≥2, desc ≥4) → Visibility (Public/Invite Only pills) → Geofence (radius slider 30–300, default 120, `_accuracy` 18, live `_GlassChip` radius + map) → bottom-pinned `SpaceButton('Initialize Space')`; private → invite-code dialog after creation |
| **My Spaces** | `_SpaceTopBar('Space', refresh, theme)` → "My Spaces" 32 w800 + orbit 86 → chip "N created / M joined" → responsive grid (same delegate as discovery) with owner invite + leave |
| **Chat** | frosted header (back button, title 22 w800, space name + StatusDot accent, "Alias:" mono 11 tertiary, theme toggle, **danger** `more_vert` leave w/o confirm) → "Today" chip → `MessageCard`s → `ChatComposer` |

## 7. Chat / reaction / poll UI (`main.dart:3295–3531`, `3133–3293`)

- **Bubbles:** max width 82%; radius 22/22/(22|5). Mine = brand gradient + white text + accent shadow; others = `card` + outline + black α0.05 shadow. Padding all 16. Others' header: name 12 w800 secondary + HH:mm 10 w600 disabled. Long-press → action sheet.
- **Replies:** quote block radius 12, left border 2, bg whiteα0.16 (mine)/accentα0.08 (other), text 12 h1.25 maxLines 2.
- **Reactions:** `_GlassChip 'emoji count'` chips, `color: colors.accent`, `Wrap(spacing: 6, runSpacing: 6)`; pinned set `['👍','❤️','😄','😂','🔥','🎉']` (`main.dart:4003`).
- **Polls:** option = `OutlinedButton` radius 8 pad 10, radio icon 18, count right, side border white54 (mine)/outline (other), radio accent; footer "N vote(s)"; 2–6 distinct options ≤100 chars backend-enforced.
- **Composer:** frosted bar (`surface α0.78`, blur 18, top 28); reply banner (radius 18, `reply_rounded` 17 accent, text 12 w600, close 18); add-options `add_circle_rounded` 28; field glass pill radius 28, text 15; hint `'Message <space>…'`; send 50×50 circle brand gradient + accent α0.24 shadow, `send_rounded` 21.

## 8. Map UI (`lib/features/location/presentation/interactive_geofence_map.dart`)

- Tiles: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, agent `com.space.space_mobile`; initial zoom 16, min 3, max 19; long-press recenters.
- **Dark tiles:** double `ColorFiltered` — outer invert+offset matrix `[-0.55,0,0,0,150]×3 + alpha`; inner rec601 grayscale `[0.30,0.59,0.11,…]`.
- **Geofence circle:** `CircleMarker` fill `decisionColor α0.14`, border `α0.55` width 2.
- **Pin:** 72×72 marker — halo circle accent α0.18, ring accent α0.55 w1.6, shadow α0.30 blur 26; core 13×13 accent α0.70 blur 14.
- **Controls** (right-bottom, gap 8): GPS (loading spinner 18), zoom `+1`/`-1`; button = `surface α0.72`, radius 999, outline, icon 20 accent, disabled disabled.
- **Search** (top, blur 16, round 999, `surface α0.68`, icon 19, hint "Search address or paste coordinates"): debounce **350 ms**; results list top 66, maxHeight 180, radius 20, `surface α0.82`, row dividers `outlineSubtle`, `ListTile` dense, place icon 19, title 13 w600, coords 11 disabled; select → zoom 17.
- **Status bar** (bottom-left, chip `surface α0.70`): `'lat, lon • radius'` + icon `verified_rounded` (participate) / `info_outline_rounded` (warning, amber).
- **Fog overlay** top/bottom: `[background α0.74, transparent, α0.78]` stops `[0,0.32,1]`.
- Decision→color: inside→**tertiary**, nearBoundary→**warning**, outside→**dangerStrong**, lowAccuracy→**warning**, rejected→**dangerStrong**.

## 9. Icons & assets

- Material rounded icons throughout (full inventory at `main.dart`: `explore`, `layers`, `language`, `my_location`, `vpn_key`, `radar`, `add`, `rocket_launch`, `poll_outlined`, `reply`, `delete_outline`, `flag_outlined`, `more_vert`, `forum`, `today`, `send`, `mood`, `blur_on`, `logout`, `check_circle`, `people_alt`, `terminal/headphones/cafe/nightlife/restaurant/bolt/blur_on`, etc.).
- Assets (`assets/orbit/`): `crystals.webp`, `crystals-warm.webp`, `crystals-still.webp`, `crystals-still-warm.webp` — picked by dark + `MediaQuery.disableAnimationsOf` (`orbit_animation.dart:18–24`). Circular backdrop `#242637` (dark) / `#F4E7D0` (light), frame = size+36.

## 10. Animations & transitions

| Animation | Values | Source |
|---|---|---|
| ChoicePill (implicit) | `AnimatedContainer` 180 ms | main.dart:3649 |
| Space-card reveal | `TweenAnimationBuilder` 220 + i·45 ms (clamp 320) → 220–540 ms; fade + slide 14px | main.dart:2053–2066 |
| Splash min-hold | 2600 ms `Future.wait` | main.dart:104–106 |
| Geofence poll | `Timer.periodic` 30 s | main.dart:233 |
| Search debounce | 350 ms | map:395 |
| Dead splash (`AnimatedSplashScreen`, not used) | 12 s repeat controller; 28 crystals, seeded Random(42); 3 crystal types; palettes per theme (dark: indigo/blue/violet families; light: amber/brown) | animated_splash_screen.dart:29–383 |
| Page routes | default `MaterialPageRoute` only; tab/screen switch is instant `setState` | main.dart:522 |

## 11. Light vs dark differences

- **Selective:** accent `ADC6FF→C45A11`, secondaryAccent `B79CFF→8F3208`, tertiary `37D399→20735B`, onAccent inverts, text colors swap, radial bg gradient colors, starfield white/accent, glass panel fill `cardα0.62→whiteα0.46` + border whiteα0.08/0.82, map dark-tile `ColorFiltered` on/off, `#C0C1FF` glow α0.10/0.30.
- `ThemeMode` defaults dark; not persisted across launches (`main.dart:38`).
- **No** animated theme cross-fade (instant swap).

## 12. Responsive / adaptive

- Discovery/MySpaces grid: columns `3` if ≥920, `2` if ≥620, else `1`; card aspect `1.06` (1 col) / `0.88` (2–3 col); spacing 18/18 (`main.dart:2036–2049`).
- Location screen: compact <760, veryCompact <680 → orbit 232/178/132, hPad 24/18.
- Chat bubbles `maxWidth 82%`; app runs on Flutter web/desktop/mobile.

## 13. Accessibility

- Tooltips: "Light mode/Dark mode", "Invite Code", "Leave Space", "Add option", "Remove last option", "Chat options".
- `excludeFromSemantics: true` on orbit image (`orbit_animation.dart:40`); `reduceMotion` uses still images.
- Invite field `TextCapitalization.characters`; `FocusScope.unfocus()` before pop.
- Long-press for message actions; text selection via `SelectableText` on invite codes.
- **No** explicit `Semantics`/`semanticLabel`/`FocusNode` in `main.dart` → rely on framework defaults.
- **Not verified in source:** dedicated contrast/`textScaler` handling, custom focus traversal, semantic labels on glass buttons.

---

## Machine-readable design tokens

```json
{
  "brand": { "accent": "#ADC6FF", "spaceAccent_const": "lib/theme.dart:3" },
  "fonts": {
    "families": { "heading": "Montserrat", "body": "Hanken Grotesk", "mono": "JetBrains Mono" },
    "bundled": false,
    "theme_fontFamily": "Hanken Grotesk"
  },
  "colors": {
    "dark": {
      "background": "#05070A", "surface": "#111417", "surface2": "#1A1E24", "surface3": "#242A33",
      "card": "#AA11141B", "primaryText": "#E1E2E7", "secondaryText": "#C2C6D6", "disabled": "#8C909F",
      "accent": "#ADC6FF", "secondaryAccent": "#B79CFF", "tertiary": "#37D399", "onAccent": "#FFFFFF",
      "danger": "#FFB4AB", "warning": "#FFD166", "dangerStrong": "#FF7B72",
      "outline": "#0FFFFFFF", "outlineSubtle": "#08FFFFFF",
      "gradientTop": "#111827", "gradientBottom": "#05070A",
      "navBackground": "#AA1D2023", "chipBackground": "#0F282A2E"
    },
    "light": {
      "background": "#F4E7D0", "surface": "#F9EEDC", "surface2": "#E9D5B8", "surface3": "#D9B98D",
      "card": "#CCFFF6E8", "primaryText": "#090807", "secondaryText": "#3D3329", "disabled": "#776A5C",
      "accent": "#C45A11", "secondaryAccent": "#8F3208", "tertiary": "#20735B", "onAccent": "#090807",
      "danger": "#BA1A1A", "warning": "#9A4A05", "dangerStrong": "#93000A",
      "outline": "#66906D45", "outlineSubtle": "#40A9875C",
      "gradientTop": "#FBECD3", "gradientBottom": "#F4E7D0",
      "navBackground": "#E6F5E7D2", "chipBackground": "#99FFF6E8"
    },
    "location_screen": {
      "gradDark": ["#111827", "@background", "#02040A"], "gradLight": ["#FFF1D9", "@background", "#FFF6E8"],
      "glow": "#C0C1FF", "glowAlphaDark": 0.10, "glowAlphaLight": 0.30,
      "orbitBackdropDark": "#242637", "orbitBackdropLight": "#F4E7D0"
    },
    "decision": {
      "inside": "@tertiary", "nearBoundary": "@warning", "lowAccuracy": "@warning",
      "outside": "@dangerStrong", "rejected": "@dangerStrong"
    }
  },
  "typography": [
    { "name": "headingLarge", "family": "Montserrat", "size": 26, "weight": 700, "color": "#F8FAFC" },
    { "name": "headingMedium", "family": "Montserrat", "size": 18, "weight": 700, "color": "#F8FAFC" },
    { "name": "headingSmall", "family": "Montserrat", "size": 15, "weight": 600, "color": "#F8FAFC" },
    { "name": "bodyLarge", "family": "Hanken Grotesk", "size": 15, "weight": 400, "height": 1.4, "color": "#F8FAFC" },
    { "name": "bodyMedium", "family": "Hanken Grotesk", "size": 13, "weight": 400, "height": 1.4, "color": "#A1AAB8" },
    { "name": "bodySmall", "family": "Hanken Grotesk", "size": 12, "weight": 400, "height": 1.3, "color": "#6B7280" },
    { "name": "technical", "family": "JetBrains Mono", "size": 11, "weight": 600, "letterSpacing": 0.4, "color": "#A1AAB8" },
    { "name": "topBarTitle", "size": 31, "weight": 800, "color": "@accent" },
    { "name": "greeting", "size": 32, "weight": 800, "height": 1.15 },
    { "name": "chatHeaderTitle", "size": 22, "weight": 800, "color": "@accent" },
    { "name": "cardName", "size": 21, "weight": 800, "height": 1.12 },
    { "name": "emptyTitle", "size": 20, "weight": 800 },
    { "name": "messageText", "size": 16, "height": 1.38 },
    { "name": "primaryButton", "size": 15, "weight": 800, "color": "@onAccent" },
    { "name": "locationButton", "size": 16, "weight": 800, "color": "@onAccent" },
    { "name": "chipLabel", "size": 11, "weight": 800, "letterSpacing": 0.7, "color": "@accent" },
    { "name": "cardCta", "size": 12, "weight": 800, "letterSpacing": 1.2, "color": "@activeColor" }
  ],
  "spacing": {
    "screenPad": { "main": 24, "createSpace": 20, "chat": 16 },
    "gridPad": "LTRB(24,8,24,112)", "headerPad": "LTRB(24,32,24,20)",
    "createListPad": "LTRB(20,16,20,118)", "chatListPad": "LTRB(16,16,16,18)",
    "gaps": [6, 8, 10, 12, 14, 16, 18, 20, 22, 34],
    "buttons": { "primaryHeight": 56, "locationHeight": 56, "fab": 64, "send": 50, "glassIcon": 44, "avatar": 48, "nav": 76, "geoIconCircle": 42, "statusDot": 9, "spinnerSmall": 18, "spinnerCard": 22 }
  },
  "radius": {
    "pill": 999, "dialog": 24, "card": 28, "topBar": 22, "composerTop": 28, "navTop": 28,
    "stepCard": 20, "snackbar": 16, "field": 16, "insideDialogButton": 14, "replyQuote": 12,
    "pollOption": 8, "reactionBtn": 12, "bubble": [22, 22, 22, 5], "locationPanel": 30, "resultList": 20
  },
  "gradients": {
    "brand": { "type": "linear", "colors": ["@accent", "@secondaryAccent"], "begin": "topLeft", "end": "bottomRight" },
    "screen": [
      { "type": "radial", "center": "topRight", "radius": 1.18, "colors": ["@gradientTop:a92", "@gradientBottom"], "stops": [0, 0.62], "alphaDark": 0.92, "alphaLight": 0.70 },
      { "type": "radial", "center": "centerLeft", "radius": 1.08, "colors": ["@accent:a07", "transparent"], "stops": [0, 0.48], "alphaDark": 0.07, "alphaLight": 0.10 }
    ],
    "locationBg": { "type": "linear", "begin": "topCenter", "end": "bottomCenter", "stops": [0, 0.56, 1] }
  },
  "shadows": [
    { "name": "primaryButton", "color": "@accent:0.28", "blur": 24, "offset": [0, 8] },
    { "name": "locationButton", "color": "@accent:0.25", "blur": 24, "offset": [0, 8] },
    { "name": "fab", "color": "@secondaryAccent:0.36", "blur": 24, "offset": [0, 8] },
    { "name": "mineBubble", "color": "@accent:0.16", "blur": 18, "offset": [0, 8] },
    { "name": "otherBubble", "color": "#000000:0.05", "blur": 18, "offset": [0, 8] },
    { "name": "mapContainer", "color": "@accent:0.12", "blur": 28, "offset": [0, 12] },
    { "name": "nav", "color": "@accent:0.08", "blur": 24, "offset": [0, -6] },
    { "name": "send", "color": "@accent:0.24", "blur": 20, "offset": [0, 0] },
    { "name": "pinHalo", "color": "@accent:0.30", "blur": 26, "offset": [0, 0] },
    { "name": "pinDot", "color": "@accent:0.70", "blur": 14, "offset": [0, 0] }
  ],
  "map": {
    "tiles": "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    "userAgent": "com.space.space_mobile",
    "zoom": { "initial": 16, "min": 3, "max": 19, "searchSelect": 17, "step": 1 },
    "circleFillAlpha": 0.14, "circleBorderAlpha": 0.55, "circleStroke": 2,
    "pin": { "marker": 72, "haloAlpha": 0.18, "ringAlpha": 0.55, "ringWidth": 1.6, "dot": 13 },
    "darkTileMatrixOuter": "[-0.55,0,0,0,150 | 0,-0.55,0,0,150 | 0,0,-0.55,0,150 | 0,0,0,1,0]",
    "darkTileMatrixInner": "[0.30,0.59,0.11,0,0 | 0.30,0.59,0.11,0,0 | 0.30,0.59,0.11,0,0 | 0,0,0,1,0]"
  },
  "intervals": {
    "geofencePollSec": 30, "gpsTimeLimitSec": 12, "searchDebounceMs": 350,
    "splashMinMs": 2600, "choicePillMs": 180, "cardRevealMs": "220 + i*45 (clamp 320)"
  },
  "emojis": ["👍", "❤️", "😄", "😂", "🔥", "🎉"],
  "reportReasons": ["Spam", "Harassment", "Hate speech", "Inappropriate content", "Other"]
}
```

**Not verified in source:** bundled font files (`pubspec.yaml` has `fonts:` only as comments — `pubspec.yaml:80–97`), explicit `Semantics`/`semanticLabel` on interactive components, custom `textScaler` support, animated theme-transition.