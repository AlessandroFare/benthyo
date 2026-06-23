# Benthyo Brand Assets

Single source of truth for the app logo, app icons, favicons, and social
preview images.

```
brand/
├── raw/
│   └── logo-master.svg      ← EDIT THIS. 512×512, navy bg, bathymetric isolines.
├── generated/               ← output of generate-icons.mjs (committed, see below)
│   ├── mobile/              ← app icon + Android adaptive fg/bg
│   ├── dashboard/           ← favicon (svg+png), apple-touch, logo, mark
│   └── social/              ← og-image (1200×630), social-square (1024²)
├── generate-icons.mjs       ← the generator (Node + sharp)
├── .icon-tools/             ← transient sharp install (gitignored)
└── README.md                ← this file
```

## Why `generated/` is committed

The generated PNGs are committed to the repo (not gitignored) so that:
- the dashboard `public/` and mobile `assets/brand/` copies stay in sync,
- CI builds work without needing sharp/native toolchain,
- reviewers see the actual pixels in a PR.

Only `brand/.icon-tools/` (the transient `sharp` install) is gitignored.

## Regenerating everything after a logo change

1. Edit `raw/logo-master.svg` (keep the 512×512 viewBox).
2. From the repo root:

   ```bash
   node brand/generate-icons.mjs
   ```

   The script auto-installs `sharp` into `brand/.icon-tools/` on first run
   (it needs network only that once). It then writes every PNG/SVG into
   `generated/`.

3. Push the new `generated/` outputs to the consumer locations:

   ```bash
   # Dashboard (Vite serves apps/dashboard/public/ at the site root)
   cp brand/generated/dashboard/* apps/dashboard/public/
   cp brand/generated/social/og-image.png apps/dashboard/public/og-image.png

   # Mobile app (flutter_launcher_icons reads these)
   cp brand/generated/mobile/* apps/mobile/assets/brand/
   ```

4. Regenerate the native iOS/Android icons:

   ```bash
   cd apps/mobile
   flutter pub get
   dart run flutter_launcher_icons
   ```

## What each output is for

| File | Size | Used by |
|------|------|---------|
| `mobile/icon-1024.png` | 1024² | App Store / Play Store listing; iOS AppIcon source |
| `mobile/adaptive-foreground.png` | 1024², transparent, 18% safe-zone | Android adaptive icon foreground |
| `mobile/adaptive-background.png` | 1024², solid `#0F2238` | Android adaptive icon background (also set in pubspec as hex) |
| `dashboard/favicon.svg` | vector | Modern browsers (Chrome/Firefox/Edge) |
| `dashboard/favicon-32.png` | 32² | Legacy favicon fallback |
| `dashboard/favicon-16.png` | 16² | Legacy favicon fallback |
| `dashboard/apple-touch-icon.png` | 180², opaque | iOS Safari home-screen bookmark |
| `dashboard/logo.svg` | vector | Sidebar / header logo |
| `dashboard/logo-mark.svg` | vector, transparent, mark-only | Avatar / open-graph / where host owns bg |
| `social/og-image.png` | 1200×630 | Twitter / LinkedIn / WhatsApp / Slack link preview |
| `social/social-square.png` | 1024² | Store / press square thumbnail |

## Brand colors

| Token | Hex | Use |
|-------|-----|-----|
| Navy (bg) | `#0F2238` | icon background, dashboard `theme-color` |
| Cyan peak | `#00E5FF` | gradient highlight |
| Teal mid | `#00838F` | gradient body |

These match the dashboard Tailwind theme (`ocean` / `navy` palettes) and the
Flutter `AppColors` in `apps/mobile/lib/core/theme/app_theme.dart`.
