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

Run tests with `flutter test`. Coverage is limited to the pure logic —
mapping rules (`test/mapping_rule_test.dart`), day analytics
(`test/day_insights_test.dart`) and quick templates
(`test/quick_template_test.dart`) — plus a placeholder in
`test/widget_test.dart`.

## Setup Requirement

`lib/config/app_config.dart` is gitignored and must be created manually. It contains Harvest API credentials (token, account ID, user ID) and default ADO instances. The app will not run without it.

## Architecture

A Flutter web app for logging time to the Harvest API with optional Azure DevOps (ADO) work item integration. All state persists in browser localStorage via `shared_preferences`.

**Layers:**

- **`lib/models/`** — Pure data classes: `TimeEntry` + request DTOs, `HarvestProject`/`HarvestTask`, `AdoWorkItem`, `AdoInstance`, `ExternalReference`, `MappingRule` + its matcher, `QuickTemplate`
- **`lib/services/`** — HTTP clients with no Flutter dependencies:
  - `HarvestService` — Harvest API v2 (assignments, create/update time entries). Reads credentials from SharedPreferences.
  - `AdoService` (`ChangeNotifier`) — ADO REST API v7, in-memory work item cache, deduplication via a pending-request set.
- **`lib/providers/`** — App state via `ChangeNotifier`:
  - `TimeEntryProvider` — time entry list, submit/update lifecycle
  - `AssignmentProvider` — selected project/task and defaults
  - `AdoInstanceProvider` — CRUD for ADO configurations
  - `ProjectCategoryProvider` — project color/code categories, `weeklyGoalHours`, and work day settings (`workDayStart`, `workDayEnd`, `breakHours`, `minGapMinutes`); exposes `dailyGoalHours` computed getter = `(end − start) − breakHours`
  - `MappingRuleProvider` — work item → project/task mapping rules and the auto-apply toggle
  - `QuickTemplateProvider` — one-tap Log Time templates (project/task/notes presets)
- **`lib/screens/`** — Five screens composed under a bottom-nav `HomeScreen`. `LogTimeScreen` creates entries; `EditTimeScreen` updates them; `RecentEntriesScreen` shows daily entries with a date picker; `InsightsScreen` analyses the selected day; `SettingsScreen` manages credentials and ADO instances.

@.claude/docs/recent-entries-screen.md

@.claude/docs/insights-screen.md

@.claude/docs/settings-screen.md

@.claude/docs/ado-integration.md

@.claude/docs/mapping-rules.md

@.claude/docs/quick-templates.md

**State setup** — `main.dart` wires all providers with `MultiProvider` and injects `AdoService` into both `AdoInstanceProvider` and `TimeEntryProvider`.
