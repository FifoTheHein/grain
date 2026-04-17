# Harvest Tracker 2.0 — Redesign Spec

**Date:** 2026-04-17  
**Branch base:** `redesign`  
**Approach:** Sequential 9-PR sequence, each independently shippable  
**Source:** Design handoff in `harvest-2-0/` bundle (JSX mockups + `CLAUDE_CODE_PLAN.md`)

---

## Open Questions — Resolved

| Question | Decision |
|---|---|
| Project categories editable? | Yes — user-editable in Settings (B) |
| Weekly goal source | User-configurable field in Settings, default 40h (C) |
| ADO PAT indicator style | Subtle 6px green dot only (A) |
| Density setting | Dropped for MVP (B) |

---

## Design Tokens

Source: `harvest-2-0/project/styles.css` → `harvest-2-0/project/CLAUDE_CODE_PLAN.md`

New file `lib/theme/harvest_tokens.dart`:

```dart
class HarvestTokens {
  static const brand        = Color(0xFFFA5D24);
  static const brand600     = Color(0xFFE54714);
  static const brandTint    = Color(0xFFFEE6DA);
  static const brandTint2   = Color(0xFFFDD3BD);

  static const bg           = Color(0xFFF6F3EE);
  static const surface      = Color(0xFFFFFFFF);
  static const surface2     = Color(0xFFFBF8F3);
  static const surface3     = Color(0xFFF1ECE3);
  static const border       = Color(0xFFE8E1D4);
  static const borderStrong = Color(0xFFD5CCBB);
  static const divider      = Color(0xFFEFEAE0);

  static const text  = Color(0xFF1A1814);
  static const text2 = Color(0xFF56504A);
  static const text3 = Color(0xFF8A837A);
  static const text4 = Color(0xFFB4AEA4);

  static const stateActive  = Color(0xFF2563EB);
  static const stateDone    = Color(0xFF16A34A);
  static const stateRemoved = Color(0xFF8A837A);
  static const stateNew     = Color(0xFFC026D3);
}
```

Wire into `ThemeData` in `main.dart`: `colorSchemeSeed`, `scaffoldBackgroundColor`, `CardTheme`, `InputDecorationTheme`. Replace all scattered `Color(0xFF...)` literals with `HarvestTokens.*`.

---

## PR Sequence

### PR 1 — `theme/harvest-tokens`

**Files changed:**
- `lib/theme/harvest_tokens.dart` (new)
- `lib/main.dart` — ThemeData update
- All screens/widgets — replace color literals

**What:** Add `HarvestTokens` class, wire into `ThemeData`, sweep color literals.  
**Why:** Foundation that all subsequent PRs depend on for consistent tokens.

---

### PR 2 — `model/project-categories`

**Files changed:**
- `lib/models/project_category.dart` (new)
- `lib/providers/project_category_provider.dart` (new)
- `lib/main.dart` — register `ProjectCategoryProvider` in `MultiProvider`

**What:**
- `ProjectCategory` model: `{ Color color, Color tint, String code }`
- `ProjectCategoryProvider` (ChangeNotifier): `Map<int, ProjectCategory>` keyed on Harvest project ID, persisted as JSON in SharedPreferences
- Ships with a default seed list matching `data.js` `PROJECT_CATEGORIES`
- Also adds `weeklyGoalHours` (double, default 40.0) to SharedPreferences — read/written by this provider since it's a simple scalar pref

**Why:** Shared data layer that entry cards (PR 3), week strip (PR 5), and settings (PR 7) all read from.

---

### PR 3 — `widget/entry-card-v2`

**Files changed:**
- `lib/widgets/time_entry_card.dart` — full rewrite
- `lib/widgets/duration_pill.dart` (new)
- `lib/widgets/work_item_chip.dart` (new)

**What:**

`DurationPill` — 44px circle widget:
- Background: `brandTint`, text color: `brand600` (inactive)
- Background: `brand`, text color: white (active/running)
- Text: formatted hours in monospace (e.g. `2h 30m`); font size: 13px for ≤2 chars, 12px for 3–4 chars, 11px for 5+ chars

`WorkItemChip` — compact ADO card:
- 3px left stripe colored by ADO work item state (`stateActive`, `stateDone`, `stateNew`, `stateRemoved`)
- Title line (semibold, truncated)
- Metadata row: `#id · state · type · [initials avatar] · external-link icon`
- Tapping opens the ADO URL
- Loading state: spinner + "Looking up work item…"
- No-cache fallback: underlined `ADO #id` link

`TimeEntryCard` rewrite:
- Leading: `DurationPill` (44px, or 40px compact — compact mode dropped, always 44px)
- Title row: project-code chip (3-letter monospace, colored from `ProjectCategoryProvider`) + task name (truncated)
- Notes: 2-line clamp below title row
- ADO: `WorkItemChip` inline if entry has `externalReference`
- Trailing: 32px edit icon button
- No second metadata row

`work_item_preview.dart` — unchanged (kept for future full-card tap).

---

### PR 4 — `screen/recent-entries-grouping`

**Files changed:**
- `lib/screens/recent_entries_screen.dart`

**What:**
- Add `_groupByProject` bool, loaded from and persisted to SharedPreferences on toggle
- AppBar actions: filter `IconButton` that toggles grouping
- When `_groupByProject` is true, wrap `ListView.builder` entries in `_ProjectGroupHeader` sections:
  - Colored project-code chip + full project name + total hours + entry count
  - Groups in first-occurrence order (order entries appear in the list)
- When false, existing flat list (unchanged behavior)

---

### PR 5 — `screen/recent-entries-week-strip`

**Files changed:**
- `lib/screens/recent_entries_screen.dart`

**What:**
- `_WeekSummaryStrip` gains a `emphasized` parameter
- Mobile (`< 720dp`): existing compact strip, unchanged
- Desktop (`>= 720dp`): emphasized variant — card-like grid, 7 day tiles + week-total tile
  - Each day tile: weekday abbreviation (uppercase, small), date number (large monospace), hours logged, 3px progress bar (orange; amber if over daily goal)
  - Week-total tile: `Xh Ym` + `of Wh` where `W` = `ProjectCategoryProvider.weeklyGoalHours`
- Breakpoint via `LayoutBuilder` or `MediaQuery.sizeOf`

---

### PR 6 — `screen/log-time-polish`

**Files changed:**
- `lib/screens/log_time_screen.dart`

**What:**
- Project + Task selectors: `Row` with two `Expanded` children on tablet/desktop; single column on mobile
- Duration mode toggle: replace current duration-only UI with `SegmentedButton<TimeMode>` (Flutter 3 built-in)
  - `TimeMode.duration` → hours + minutes dropdowns (existing)
  - `TimeMode.startEnd` → two tappable time tiles (Start, End) — each shows the selected time in monospace and opens Flutter's `showTimePicker` on tap
- ADO section when checkbox unchecked: remove heavy container border; render only the checkbox row
- Instance picker dots: 6px `Container` with `shape: BoxDecoration(shape: BoxShape.circle, color: Colors.green)` — no text label
- "Log Time" button: full-width `FilledButton` at bottom (unchanged)

---

### PR 7 — `screen/settings-polish`

**Files changed:**
- `lib/screens/settings_screen.dart`

**What:**

Reorganize into titled sections with `Divider` separators:
1. **Harvest Credentials** — API Token (obscured, eye toggle), Account ID
2. **Default Project** — Default Project + Default Task dropdowns + helper text
3. **Background Refresh** — interval dropdown + helper text
4. **Project Categories** — one row per Harvest project the user has assignments for: colored swatch + 3-letter code + edit button → dialog (fixed 12-color palette — Material 500-level swatches covering common hues — plus a code text field, writes to `ProjectCategoryProvider`)
5. **Weekly Goal** — single `TextFormField` for weekly goal hours, writes to `ProjectCategoryProvider.weeklyGoalHours`
6. **Azure DevOps Instances** — Add button in section header; each instance row:
   - Line 1: icon box + label + muted URL + PAT 6px dot
   - Line 2 (indented): check-circle + GUID or warning + "Harvest GUID not yet learned" + edit-GUID pencil
   - Trailing: edit + trash icon buttons
7. **Actions** (after divider):
   - `FilledButton` Save & Reload (primary)
   - `OutlinedButton` Clear Cache & Refresh
   - `OutlinedButton` Migrate ADO References
   - `OutlinedButton` Reset to Defaults
   - Helper text: "Settings are stored in browser localStorage."

---

### PR 8 — `screen/edit-time-context-banner`

**Files changed:**
- `lib/screens/edit_time_screen.dart`

**What:**
- Insert a banner widget between the AppBar and the form body
- Banner: `brandTint` background, `brandTint2` border, 8px border radius
- Contains: `DurationPill` at 32px + column with "EDITING ENTRY" overline (11px, semibold, uppercase, `brand600`) + `#id · Day DD Mon YYYY` on the second line (13px semibold, truncated)
- Reuses `DurationPill` from PR 3
- Rest of the form inherits PR 6's polish (2-col layout, ADO section treatment)

---

### PR 9 — `screen/responsive-shell`

**Files changed:**
- `lib/screens/home_screen.dart`

**What:**
- Wrap `Scaffold` body in `LayoutBuilder`
- `constraints.maxWidth < 720`: current layout unchanged (bottom `NavigationBar`)
- `constraints.maxWidth >= 720`: `Row` with `NavigationRail` on left + `Expanded` content area
  - Same three destinations: Recent (list icon), Log Time (plus-circle icon), Settings (settings icon)
  - `NavigationRail` uses `HarvestTokens.brand` as `indicatorColor`
  - Bottom nav hidden
- No routing changes — same tab index state, same three screens

---

## What Is NOT Changed

- API surface: `ado_service.dart`, `harvest_service.dart` — no renames or new methods
- Model shapes: `time_entry.dart`, `ado_work_item.dart`, `project_assignment.dart` — unchanged
- localStorage keys — no migration needed
- `work_item_preview.dart` — kept as-is for future full-card view

---

## Architecture Notes

- `ProjectCategoryProvider` is injected into `MultiProvider` in `main.dart` alongside existing providers
- `ProjectCategoryProvider` owns `weeklyGoalHours` (a scalar pref) to avoid a separate provider for one field
- All new widgets (`DurationPill`, `WorkItemChip`) live in `lib/widgets/`
- Breakpoint (720dp) is consistent across PRs 5, 6, 7, 8, 9 — use a shared constant `kWideBreakpoint = 720.0` in `lib/theme/harvest_tokens.dart`
- No test changes (placeholder test in `test/widget_test.dart` stays)
