---
name: HouseholdApp
description: A shared household board for chores, shopping, meals, garden, packing, and wishes.
colors:
  household-green: "#45A86D"
  member-blue: "#007AFF"
  member-pink: "#FF2D55"
  member-green: "#34C759"
  member-orange: "#FF9500"
  member-teal: "#30B0C7"
  member-red: "#FF3B30"
  member-mint: "#00C7BE"
  member-indigo: "#5856D6"
  everyone-purple: "#AF52DE"
  status-overdue: "#FF3B30"
  status-done: "#34C759"
  grouped-background: "#F2F2F7"
  card-background: "#FFFFFF"
  label: "#000000"
  secondary-label: "#3C3C4399"
typography:
  large-title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "34px"
    fontWeight: 400
  title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "20px"
    fontWeight: 400
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 400
  section-label:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 600
  meta:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12px"
    fontWeight: 400
  badge:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 500
  code:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "22px"
    fontWeight: 400
rounded:
  tile: "8px"
  panel: "12px"
  feature: "14px"
  pill: "999px"
spacing:
  hairline: "2px"
  badge-x: "6px"
  sm: "8px"
  md: "16px"
  touch: "44px"
components:
  badge-member:
    backgroundColor: "{colors.member-blue}"
    textColor: "{colors.member-blue}"
    typography: "{typography.badge}"
    rounded: "{rounded.pill}"
    padding: "2px 6px"
  check-button:
    textColor: "{colors.secondary-label}"
    size: "{spacing.touch}"
  check-button-done:
    textColor: "{colors.status-done}"
    size: "{spacing.touch}"
  icon-tile:
    backgroundColor: "{colors.household-green}"
    textColor: "{colors.household-green}"
    rounded: "{rounded.tile}"
    size: "40px"
  icon-tile-selected:
    backgroundColor: "{colors.household-green}"
    textColor: "{colors.card-background}"
    rounded: "{rounded.tile}"
    size: "40px"
  feature-header:
    backgroundColor: "{colors.household-green}"
    rounded: "{rounded.feature}"
  section-header:
    backgroundColor: "{colors.grouped-background}"
    textColor: "{colors.secondary-label}"
    typography: "{typography.section-label}"
    padding: "5px 16px"
---

# Design System: HouseholdApp

## Overview

**Creative North Star: "The Fridge Door"**

HouseholdApp is the shared surface a family glances at on the way past: everyone's stuff is on it, each person's things are recognisable by color at a glance, and nothing on it is precious. It is a native iOS app first. The structure is stock UIKit-era iOS (tab bar, navigation stacks, sheets, inset grouped lists), and personality lives only in the layer iOS leaves open: the green tint, per-person color, SF Symbols, and soft tinted badges.

Density is that of a good to-do list: one line of title, one line of quiet metadata, a big round check target on the left. Color carries meaning (who, what kind, how urgent) rather than decoration, which is why it can be plentiful without being loud: every colored fill is a 12% wash of its color, and full-strength color is reserved for the glyph or text on top of it.

**Key Characteristics:**
- Stock iOS structure; system text styles throughout, so Dynamic Type works.
- Color = identity: one color per household member, purple for Everyone, a chosen color per category.
- Soft tinted capsules for metadata (assignee, garden, trip, meal links).
- Large circular check targets (44 pt) with a haptic on toggle.
- Light, Dark, or System appearance, chosen per device in Settings.

## Colors

A bright, playful, many-hued palette held together by one rule: color is always tinted, never flooded.

### Primary
- **Household Green** (#45A86D): the app tint (`AccentColor`). Toolbar buttons, links, selected icon tiles, toggles. The one color that belongs to the app rather than to a person.

### Secondary
- **Member colors**, assigned by member index and cycling: Member Blue (#007AFF), Member Pink (#FF2D55), Member Green (#34C759), Member Orange (#FF9500), Member Teal (#30B0C7), Member Red (#FF3B30), Member Mint (#00C7BE), Member Indigo (#5856D6). Used on assignee badges, filter-bar selections, and note authorship in Looking For.
- **Everyone Purple** (#AF52DE): items assigned to the whole household.

### Tertiary
- **Category colors** are user-chosen hex values stored on each category (defaults like Kitchen #FF6B6B, Bathroom #4ECDC4, Laundry #45B7D1). They tint the category's icon and badge exactly like member colors.

### Neutral
- **Grouped Background** (#F2F2F7, `systemGroupedBackground`): the canvas behind inset lists and the sticky section headers.
- **Card Background** (#FFFFFF, `secondarySystemGroupedBackground`): list cells.
- **Label / Secondary Label** (`label`, `secondaryLabel`): titles and the quiet metadata line. Secondary is the most-used foreground in the app.

Hex values above are the light-appearance system values; in code they are always the semantic SwiftUI colors (`.blue`, `.secondary`, `Color(.systemGroupedBackground)`), which adapt to Dark Mode and Increase Contrast.

### Named Rules
**The Twelve Percent Rule.** A colored background is the color at 12% opacity (0.1–0.15 for emphasis panels), with the full-strength color on the glyph or text above it. Never a solid colored chip with white text, except a selected icon tile.

**The Red Means Late Rule.** Red text is reserved for overdue dates and overdue section headers, and destructive actions. Don't use it for decoration, even though red is also a member color slot.

**The Semantic Color Rule.** Use SwiftUI system colors, never raw hex, for anything except user-chosen category colors.

## Typography

**Display Font:** SF Pro (system)
**Body Font:** SF Pro (system)
**Label/Mono Font:** SF Mono, only for invite codes

**Character:** Entirely the system face at system text styles. The hierarchy is made with weight (semibold section labels, medium badges) and the secondary color, not with size jumps.

### Hierarchy
- **Large Title** (regular, 34 pt): navigation titles on top-level tabs, and the empty-state hero icon.
- **Title 2 / Title 3** (regular, 22/20 pt): the check-button glyph and row icons.
- **Headline** (semibold, 17 pt): emphasized row titles and confirmations.
- **Body** (regular, 17 pt): row titles. Completed items get strikethrough and `secondary` color.
- **Subheadline Semibold** (semibold, 15 pt): section headers in lists ("Overdue", "Today", "This Week"), with a count in caption beside them.
- **Caption** (regular, 12 pt): the metadata line under a title: due date, store, quantity.
- **Caption 2 Medium** (medium, 11 pt): text inside badges.

### Named Rules
**The Text Style Rule.** Always `.font(.caption)` style tokens, never fixed point sizes. The only fixed sizes allowed are decorative empty-state and celebration glyphs.

## Layout

Single-column, full-width iOS lists. Content sits in `.insetGrouped` lists; sticky section headers sit on the grouped background with 16 pt side and 5 pt vertical padding. A row is: 44×44 pt check target, then a VStack of title and caption metadata with badges, then any trailing icon. A horizontal filter bar ("All" plus one tab per member) sits above lists that support assignment. Badges space at 2 pt vertical / 6 pt horizontal padding. Forms are stock `Form` sections with headers and explanatory footers.

## Elevation & Depth

Flat. Depth comes from iOS's own layering: grouped background behind white cells, sheets over the current screen, navigation pushes. The app defines no shadows.

**The Platform Depth Rule.** If something needs to feel raised, present it as a sheet or put it in its own list section, never add a shadow.

## Shapes

Three corner sizes and two pure geometric shapes: 8 pt for small icon tiles in pickers, 12 pt for content panels (voice transcript, parsed result, sign-in button), 14 pt for the large icon header at the top of category, store, and item-type forms. Badges are capsules; check buttons and member avatars are circles. A selected emoji tile adds a 2 pt stroke in its accent color.

## Components

### Check Button
The signature interaction. An SF Symbol `circle` in secondary color that becomes `checkmark.circle.fill` in green when done, at Title 2 inside a 44×44 pt hit area. Toggling plays a haptic; the completed row drops to 60% opacity with a struck-through title.

### Badges (chips)
- **Style:** Caption 2 Medium text in the badge's color, on a 12% wash of the same color, capsule shape, 2×6 pt padding. Often led by a small SF Symbol.
- **Variants:** assignee (member color or Everyone purple), category, garden "Growing" hint, trip, meal link. Tappable link badges route to the other tab.

### Lists and Rows
- **Container:** `.insetGrouped` list; white cells on the grouped background.
- **Row:** check button, Body title, Caption metadata in secondary (red when overdue), trailing badges.
- **Swipe actions:** leading = positive (Restore green, Archive); trailing = destructive Delete. Delete of anything with children goes through a confirmation alert naming the count.

### Filter Bar
Horizontal row: "All" plus each member by name. The selected tab takes that member's color; filtering shows items assigned to Everyone too.

### Icon Picker Tiles
40×40 pt tiles, 8 pt corners, six per row. Unselected: accent glyph on a 12% accent wash. Selected: white glyph on solid accent. The one place solid color with white is allowed.

### Feature Header
At the top of category, store, and item-type forms: a large icon on a 12% wash of the item's color, 14 pt corners, centered.

### Navigation
Stock tab bar with SF Symbol tab icons, first four tabs visible and the rest under More; the order is user-configurable. Inline titles on sheets and detail screens; toolbar actions (add, mic, import) are SF Symbols in the tint color.

### Empty States
`ContentUnavailableView` with an SF Symbol and one sentence telling the user the gesture or button that fills the screen.

## Do's and Don'ts

### Do:
- **Do** use stock SwiftUI containers (`List`, `Form`, `NavigationStack`, `.sheet`, `ContentUnavailableView`) before building anything custom.
- **Do** give every person-related element its member color via `appSettings.memberColor(at:)`, and Everyone purple.
- **Do** tint backgrounds at 12% with the full color on the glyph (The Twelve Percent Rule).
- **Do** keep tap targets at 44×44 pt, add a haptic on toggles, and give rows a VoiceOver summary with `.accessibilityLabel`.
- **Do** check Light and Dark appearance; the user can force either in Settings.

### Don't:
- **Don't** use fixed point sizes for text (`.caption2`, not `.system(size: 11)`).
- **Don't** use raw hex for system roles; only user-chosen category colors are hex.
- **Don't** add shadows, gradients, or custom navigation chrome.
- **Don't** use red for anything except overdue and destructive states.
