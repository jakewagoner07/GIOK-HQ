# Tony Alpha — Theme & Branding System

*(Architecture Review 002)*

## Core principle

**Tony's functionality never depends on branding.** Branding is a **theme layer that sits
on top** of the application. The app reads names, colors, fonts, and images from a theme
object — it hardcodes none of them. You can re-brand the entire app (or hand it to another
company) by editing one JSON file and dropping in a few images. **No application code changes.**

If the theme is missing or broken, the app falls back to a neutral built-in theme and keeps
working — proof that functionality is independent of branding.

---

## How branding works

Three pieces:

```
dashboard/
├── theme/
│   ├── theme.json          # THE theme config (the only place branding lives)
│   ├── theme-loader.ps1    # Get-Theme: defaults -> merge theme.json -> resolve assets
│   └── assets/
│       ├── giok-logo.png   # logo (top bar + window icon)
│       ├── giok-profile.jpg# profile picture (top-bar avatar)
│       └── giok.ico        # desktop-shortcut icon
├── ui/tony-ui.ps1          # reads the theme; renders with it. No hardcoded brand values.
└── dashboard.ps1           # loads the theme, sets window title + icon from it
```

`agents_registry.json` and the business logic in `core/` are **untouched** by branding —
the theme only affects presentation.

### The theme object (`theme.json`)

Required fields (per Architecture Review 002):

| Field | Meaning | GIOK value |
|-------|---------|-----------|
| `companyName` | Window title / brand name | `GIOK` |
| `logo` | Path to logo image | `assets/giok-logo.png` |
| `colors.primary` | Primary color | `#0a1f44` (navy) |
| `colors.accent` | Accent color | `#C85A00` (orange) |
| `colors.background` | Background color | `#f7f8fc` |
| `colors.text` | Text color | `#1f2937` |
| `profilePicture` | Profile picture | `assets/giok-profile.jpg` |
| `tagline` | Tagline | `Protection for people who take ownership.` |

Supporting fields also read by the app: `companyWordmark`, `workspaceName`,
`assistantName`, `version`, `profileName`, `icon`, the extended `colors.*`
(primaryDark/Mid, accentLight/Dark/Soft, surface, textMuted, textOnPrimary, line),
and `typography.fontFamily` / `headingFamily`.

Semantic colors (status green/amber/red, priority chips) are intentionally **not** themed —
they carry meaning, not brand.

---

## How themes are loaded

1. `dashboard.ps1` calls `Get-Theme` (in `theme-loader.ps1`).
2. `Get-Theme` starts from `Get-DefaultTheme` — a neutral, brand-free theme.
3. It reads `theme/theme.json` and **merges** those values over the default (partial themes
   are fine; anything omitted keeps the default).
4. It resolves `logo` / `profilePicture` / `icon` to absolute paths and verifies they exist
   (a missing image is simply skipped — the app still runs).
5. The resulting theme object is passed to `New-TonyShell`, which calls
   `Initialize-TonyTheme` to populate the UI's color/font variables. Every view reads from
   these — nothing is hardcoded.

Fallback behaviour: no `theme.json` → neutral default. Malformed `theme.json` → neutral
default. Missing image → skipped. The app is never blocked by branding.

---

## How future users will customize their workspace

> This is **not** multi-user yet. The architecture is simply prepared for it.

A future user personalizes their workspace by providing their own theme — **no code change**:

1. **Drop in assets** — put a logo, profile picture, and (optional) `.ico` in `theme/assets/`.
2. **Edit `theme.json`** — set:
   - `companyName`, `workspaceName`
   - `logo`, `profilePicture`
   - `colors.primary`, `colors.accent`, `colors.background`, `colors.text`
   - `tagline`, `profileName`
3. **Relaunch** — the app reads the new theme on startup.

### Path to true multi-user (future)
The pieces are already shaped for it:
- `Get-Theme` takes a `-Path`, so per-user theme files (e.g. `themes/<user>.json`) drop in
  with no code change — just choose which path to load.
- The theme object is the single contract the UI depends on, so a future settings screen can
  write `theme.json` and the app re-themes on next launch.
- `workspaceName` / `profileName` already exist as per-workspace identity fields.

Nothing above requires touching `core/`, the registry, or the views — exactly the point:
**branding is a replaceable layer, functionality is permanent.**
