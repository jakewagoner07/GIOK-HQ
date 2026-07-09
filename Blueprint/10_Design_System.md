# 10 — Design System

GIOK should feel like a **premium executive command center** — calm, confident, dark, and
disciplined. The design system is how every screen stays coherent as the product grows. It is
theme-driven: branding is a configurable layer on top of the app, never hard-coded into features
(the implementation lives in `tony-alpha/dashboard/theme/` and is documented in
`tony-alpha/dashboard/THEME.md` — not modified by this blueprint).

**Design north star:** *does this feel like a sharp chief of staff's cockpit, or like a busy
admin panel?* Always the former.

## Branding
- **Identity:** GIOK Agency. The **GA monogram** logo (orange circle on navy). Wordmark "GIOK"
  in white with "Agency" in orange.
- **Voice on screen:** direct, warm, disciplined — the same one-voice character as Tony. The
  brand line *"People Matter More Than Money"* appears where it grounds the product.
- **Feel:** ownership, calm, premium. Not playful, not clinical. A serious tool for a serious
  operator.
- **Configurable:** company name, logo, colors, profile, tagline, and workspace name all live in
  the theme so GIOK can be re-branded (or, later, per-user) with no code change.

## Color palette (GIOK dark, current default)
| Role | Value | Use |
|------|-------|-----|
| Navy (primary) | `#0A1A31` | Sidebar, structural surfaces |
| Navy background | `#0D1E39` | App background |
| Card surface | `#16294A` | Cards, panels |
| Orange (accent) | `#E8732A` | Highlights, active state, CTAs |
| Orange ink | `#F2A56B` | Accent text on dark |
| Orange (brand base) | `#C85A00` | Brand orange (logo/light contexts) |
| Heading | `#F3F7FC` | Titles, key numbers |
| Text | `#EAF0F7` | Body text |
| Muted | `#93A3BC` | Secondary text |
| Line | `#274063` | Borders, dividers |

**Semantic colors are separate from brand** and carry meaning, not style: green = healthy/done,
amber = warning, red = broken/critical. These stay consistent across themes.

## Typography
- **Family:** Inter (with Segoe UI fallback) — clean, modern, executive.
- **Hierarchy:** big bold headings and key numbers in the Heading color; readable body; muted
  secondary text. Weight and size carry hierarchy — color is used sparingly for emphasis.
- **Restraint:** few sizes, consistent scale. Typography should feel calm, not busy.

## Spacing
- Generous, consistent padding inside cards; clear breathing room between them.
- A predictable rhythm (small/medium/large) rather than ad-hoc values.
- Density is *earned*: Home is spacious and prioritized; Mission Control is denser because it's a
  glance-surface. Never cramped elsewhere.

## Cards
- The primary building block: rounded corners, subtle border, soft shadow, dark surface.
- A card has a clear title, optional affordance ("open ›"), and focused content.
- Cards are **entry points** — clickable to their fuller view, with a hover cue and hand cursor.
- Placeholder cards are **clearly tagged** (e.g. SAMPLE) until live data replaces them.

## Buttons
- **Primary:** solid orange accent with light text — for the main action.
- **Soft/secondary:** steel-navy with orange ink — for supporting actions.
- **Semantic:** red-tinted for destructive (delete), used sparingly and never as a primary.
- Rounded, comfortable padding, obvious hover, hand cursor. Buttons look pressable.

## Sidebar
- Persistent left rail on navy: logo + wordmark, Jake's profile (photo, name, title, agency),
  the workspace nav, Settings, version, and clock.
- Active item highlighted in orange. The sidebar is identity + navigation; it never holds content.

## Dark theme
- The **default and signature look.** Dark navy canvas, orange accents, light text, strong
  contrast — designed for long, calm, all-day use and second-monitor display.

## Light theme (future)
- GIOK will offer a light theme via the same theme system (the `heading`/color roles already make
  both possible). Light theme is a *palette swap*, not a redesign — same components, same rules.

## Animations (future)
- **Purposeful only:** gentle transitions between views, subtle feedback on capture and
  completion, calm reveal of the Morning Brief.
- **Never decorative or distracting.** Motion should reduce cognitive load (orient the eye,
  confirm an action), never add noise. Respect reduced-motion preferences.

## Rules
- Read from the theme; never hard-code brand values in a feature.
- Consistency over novelty — a new screen reuses existing components before inventing new ones.
- Honest states: loading, empty, error, and placeholder are all designed, never faked.
- If a screen feels like an admin panel, it's wrong — redesign toward the executive cockpit.
