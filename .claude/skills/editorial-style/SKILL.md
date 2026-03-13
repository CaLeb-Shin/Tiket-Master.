---
name: editorial-style
description: Apply editorial/luxury magazine design style when building or modifying any UI screen. Use when creating new screens, adding features, modifying layouts, or building widgets in either melon_admin or melon_ticket_app.
version: 1.0.0
---

# Editorial / Luxury Magazine Design System

When building or modifying ANY UI in this project, always follow this editorial design system.

## Color Palette (from `melon_core/lib/app/theme.dart`)

| Token | Value | Usage |
|-------|-------|-------|
| `AppTheme.background` | `#FAF8F5` (ivory) | Page backgrounds |
| `AppTheme.surface` | `#FFFFFF` (white) | Cards, containers |
| `AppTheme.card` | `#FFFFFF` | Card backgrounds |
| `AppTheme.cardElevated` | `#F2F0EA` | Elevated/secondary surfaces |
| `AppTheme.gold` | `#3B0D11` (burgundy) | Primary accent, CTAs |
| `AppTheme.goldLight` | `#5D141A` | Gradient end, hover states |
| `AppTheme.sage` | `#748386` | Secondary text, borders, icons |
| `AppTheme.textPrimary` | `#3B0D11` | Body text |
| `AppTheme.textSecondary` | `#748386` | Secondary text |
| `AppTheme.textTertiary` | `#748386` @ 60% | Hints, placeholders |
| `AppTheme.onAccent` | `#FAF8F5` | Text on burgundy buttons |
| `AppTheme.success` | `#2D6A4F` | Success states |
| `AppTheme.error` | `#C42A4D` | Error states |
| `AppTheme.warning` | `#D4A574` | Warning states |

**NEVER use hardcoded dark colors.** Always reference `AppTheme.*` constants.

## Typography

Use these helper methods — NEVER use `GoogleFonts` directly:

```dart
// Headings (Noto Serif)
AppTheme.serif(fontSize: 28, fontWeight: FontWeight.w300)  // Page titles
AppTheme.serif(fontSize: 20, fontStyle: FontStyle.italic)   // Section headers
AppTheme.serif(fontSize: 16)                                 // Card titles

// Body (Inter)
AppTheme.sans(fontSize: 14)                                  // Body text
AppTheme.sans(fontSize: 13, color: AppTheme.textSecondary)  // Secondary

// Labels (Inter, UPPERCASE, letter-spacing: 2.0)
AppTheme.label(fontSize: 10)                                 // Uppercase labels
AppTheme.label(fontSize: 9, color: AppTheme.gold)           // Active labels
```

### Typography Rules
- Headings: **Noto Serif** via `AppTheme.serif()` — light weight (w300-w500), optional italic
- Body: **Inter** via `AppTheme.sans()` — regular weight (w400)
- Labels/badges: **Inter** via `AppTheme.label()` — ALWAYS uppercase, letter-spacing 2.0
- Section headers: serif italic + thin horizontal rule extending to fill width

## Layout & Spacing

- **Border radius**: 2px for cards/containers, 4px for buttons/inputs — NEVER more than 4px
- **Borders**: 0.5px width, `AppTheme.sage.withValues(alpha: 0.15)` or `AppTheme.border`
- **Shadows**: Use `AppShadows.small`, `AppShadows.card`, `AppShadows.elevated` — always subtle
- **Dividers**: 0.5px sage lines between items
- **No dark backgrounds** — everything is light ivory/white

## Components

### Buttons
- Primary CTA: Use `ShimmerButton` from `package:melon_core/widgets/premium_effects.dart`
  - `borderRadius: 4`, uppercase text, letter-spacing 2.0
  - Burgundy gradient background, ivory text
- Secondary: `OutlinedButton` with 0.5px border, `borderRadius: 4`
- Text buttons: burgundy text, no border

### Cards
- Background: `AppTheme.surface` (white)
- Border: 0.5px, `AppTheme.sage.withValues(alpha: 0.15)`
- Border radius: 2px
- Shadow: `AppShadows.small` or `AppShadows.card`
- Or use `GlowCard` from `package:melon_core/widgets/premium_effects.dart`

### Form Inputs
- Underline style only (no outlined/filled)
- Labels: UPPERCASE via `AppTheme.label()`
- Hint text: `AppTheme.textTertiary`
- Focus border: `AppTheme.gold` (burgundy)

### App Bar
- Background: `AppTheme.background` at 95% opacity with thin 0.5px bottom border
- Title: `AppTheme.serif(fontStyle: FontStyle.italic)`
- Icons: thin line icons (e.g., `Icons.west` for back)

### Status Badges
- UPPERCASE text via `AppTheme.label()`
- Semantic colors at 8% opacity for background
- Border radius: 2px
- Examples: "ON SALE", "SOLD OUT", "PENDING", "APPROVED"

### Dialogs & Sheets
- Use `showAnimatedDialog()` and `showSlideUpSheet()` from `package:melon_core/widgets/premium_effects.dart`
- Border radius: 4px
- Background: `AppTheme.surface`

### Loading States
- Use `ShimmerLoading` from `package:melon_core/widgets/premium_effects.dart`
- Or `CircularProgressIndicator` with `AppTheme.gold` color

## Section Header Pattern

```dart
// Reusable section header with serif italic + thin rule
Row(
  children: [
    Text('Section Title', style: AppTheme.serif(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.italic,
    )),
    const SizedBox(width: 16),
    Expanded(child: Divider(
      color: AppTheme.sage.withValues(alpha: 0.2),
      thickness: 0.5,
    )),
  ],
)
```

## Premium Effects (from `melon_core/lib/widgets/premium_effects.dart`)

| Widget | Usage |
|--------|-------|
| `ShimmerButton` | Primary CTA buttons with shimmer sweep |
| `GlowCard` | Cards with subtle hover glow |
| `PressableScale` | Wrap tappable items for press scale effect |
| `showAnimatedDialog()` | Scale+fade dialogs with backdrop blur |
| `showSlideUpSheet()` | Bottom sheets with slide animation |
| `ShimmerLoading` | Skeleton loading placeholders |

## Import Pattern

```dart
import 'package:melon_core/app/theme.dart';
import 'package:melon_core/widgets/premium_effects.dart';
```

## Checklist for Every Screen

- [ ] Background is `AppTheme.background` (ivory)
- [ ] Cards/containers are `AppTheme.surface` (white) with 0.5px borders
- [ ] All text uses `AppTheme.serif()`, `AppTheme.sans()`, or `AppTheme.label()`
- [ ] No `GoogleFonts` import — use AppTheme helpers
- [ ] No hardcoded colors — use `AppTheme.*` constants
- [ ] Border radius is 2-4px max
- [ ] Labels/badges are UPPERCASE with letter-spacing
- [ ] Buttons use `ShimmerButton` or styled Material buttons with borderRadius 4
- [ ] Shadows use `AppShadows.*` presets
- [ ] No dark backgrounds anywhere
