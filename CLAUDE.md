# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run development server
flutter run -d web-server --web-port=8080

# Build for production — always build BOTH web and Android when asked for a production build

# 1. Web
# MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from expanding /grain/ to a Windows path
# --pwa-strategy=none disables the service worker — avoids a browser console error where the
# SW intercepts background API fetches but closes the message channel before responding
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /grain/ --pwa-strategy=none

# 2. Android APK
# Output: build\app\outputs\flutter-apk\app-release.apk
flutter build apk --release

# Lint / static analysis
flutter analyze
```

Run tests with `flutter test`. Coverage is the pure logic — mapping rules
(`test/mapping_rule_test.dart`), day analytics (`test/day_insights_test.dart`),
quick templates (`test/quick_template_test.dart`), work item search
(`test/work_item_search_test.dart`), the ICS parser (`test/ics_parser_test.dart`)
meeting filtering/dedup/placement (`test/meeting_test.dart`) and the rules' Any text field (`test/rule_any_text_test.dart`) — plus the
timer endpoints (`test/timer_test.dart`), the ADO Completed Work push
(`test/completed_work_test.dart`) and the calendar import
(`test/calendar_import_test.dart`), which drive the HTTP clients with a
`MockClient`, and the theme palettes (`test/theme_palette_test.dart`), which
assert contrast ratios. `test/widget_test.dart` covers Settings navigation
(group list, every page, the wide sidebar).

## Setup Requirement

`lib/config/app_config.dart` is gitignored and must be created manually. It contains Harvest API credentials (token, account ID, user ID) and default ADO instances. The app will not run without it.

## Architecture

A Flutter web app for logging time to the Harvest API with optional Azure DevOps (ADO) work item integration. All state persists in browser localStorage via `shared_preferences`.

**Layers:**

- **`lib/models/`** — Pure data classes: `TimeEntry` + request DTOs, `HarvestProject`/`HarvestTask`, `AdoWorkItem`, `AdoInstance`, `ExternalReference`, `MappingRule` + its matcher, `QuickTemplate`, `CalendarEvent` + the ICS parser, and the meeting import rules (`meeting.dart`)
- **`lib/services/`** — HTTP clients with no Flutter dependencies (plus `CalendarService`, which fetches an ICS feed, and `MeetingImporter`, which turns parsed meetings into entries):
  - `HarvestService` — Harvest API v2 (assignments, create/update time entries, start/stop/restart timers). Reads credentials from SharedPreferences.
  - `AdoService` (`ChangeNotifier`) — ADO REST API v7, in-memory work item cache, deduplication via a pending-request set, and a WIQL-backed "assigned to me" fetch for the search picker.
- **`lib/providers/`** — App state via `ChangeNotifier`:
  - `TimeEntryProvider` — time entry list, submit/update lifecycle, start/stop/continue timers
  - `AssignmentProvider` — selected project/task and defaults
  - `AdoInstanceProvider` — CRUD for ADO configurations
  - `ProjectCategoryProvider` — project color/code categories, `weeklyGoalHours`, and work day settings (`workDayStart`, `workDayEnd`, `breakHours`, `minGapMinutes`); exposes `dailyGoalHours` computed getter = `(end − start) − breakHours`
  - `MappingRuleProvider` — work item → project/task mapping rules and the auto-apply toggle
  - `QuickTemplateProvider` — one-tap Log Time templates (project/task/notes presets)
  - `MeetingRuleProvider` — meeting → project/task rules (a `MappingRuleProvider` on its own prefs keys)
  - `CalendarImportProvider` — ICS calendar settings, the logged-meeting ledger, and the auto-sync on entry refresh
  - `ThemeModeProvider` / `ThemePaletteProvider` — System/Light/Dark, and which colour palette the interface uses
- **`lib/screens/`** — Five screens composed under a bottom-nav `HomeScreen`. `LogTimeScreen` creates entries; `EditTimeScreen` updates them; `RecentEntriesScreen` shows daily entries with a date picker; `InsightsScreen` analyses the selected day; `SettingsScreen` is a group list (a sidebar when wide) opening one page per group from `lib/screens/settings/`.

@.claude/docs/recent-entries-screen.md

@.claude/docs/insights-screen.md

@.claude/docs/settings-screen.md

@.claude/docs/ado-integration.md

@.claude/docs/work-item-search.md

@.claude/docs/mapping-rules.md

@.claude/docs/quick-templates.md

@.claude/docs/timers.md

@.claude/docs/theming.md

@.claude/docs/calendar-import.md

**State setup** — `main.dart` wires all providers with `MultiProvider` and injects `AdoService` into both `AdoInstanceProvider` and `TimeEntryProvider`.

## Commit & PR Conventions

Do **not** add `Co-authored-by: Claude <noreply@anthropic.com>`,
`Claude-Session:` links, or "Generated with/by Claude Code" footers to commit
messages or pull request descriptions. Write the message as the change itself
warrants and stop there — no tooling reads those trailers, and this repo does
not want them in its history.

One of them is not yours to leave out: the GitHub integration appends
`_Generated by [Claude Code](…)_`, session link included, to a pull request
description **server-side** after it is created. Writing a clean description is
not enough — re-read the PR body and edit the footer out. An edit sticks; it is
not re-appended.
