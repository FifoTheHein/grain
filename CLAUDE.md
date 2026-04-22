# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run development server
flutter run -d web-server --web-port=8080

# Build for production
# MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from expanding /grain/ to a Windows path
# --pwa-strategy=none disables the service worker — avoids a browser console error where the
# SW intercepts background API fetches but closes the message channel before responding
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /grain/ --pwa-strategy=none

# Lint / static analysis
flutter analyze
```

There are no automated tests beyond a placeholder in `test/widget_test.dart`.

## Setup Requirement

`lib/config/app_config.dart` is gitignored and must be created manually. It contains Harvest API credentials (token, account ID, user ID) and default ADO instances. The app will not run without it.

## Architecture

A Flutter web app for logging time to the Harvest API with optional Azure DevOps (ADO) work item integration. All state persists in browser localStorage via `shared_preferences`.

**Layers:**

- **`lib/models/`** — Pure data classes: `TimeEntry` + request DTOs, `HarvestProject`/`HarvestTask`, `AdoWorkItem`, `AdoInstance`, `ExternalReference`
- **`lib/services/`** — HTTP clients with no Flutter dependencies:
  - `HarvestService` — Harvest API v2 (assignments, create/update time entries). Reads credentials from SharedPreferences.
  - `AdoService` (`ChangeNotifier`) — ADO REST API v7, in-memory work item cache, deduplication via a pending-request set.
- **`lib/providers/`** — App state via `ChangeNotifier`:
  - `TimeEntryProvider` — time entry list, submit/update lifecycle
  - `AssignmentProvider` — selected project/task and defaults
  - `AdoInstanceProvider` — CRUD for ADO configurations
  - `ProjectCategoryProvider` — project color/code categories, `weeklyGoalHours`, and work day settings (`workDayStart`, `workDayEnd`, `breakHours`); exposes `dailyGoalHours` computed getter = `(end − start) − breakHours`
- **`lib/screens/`** — Four screens composed under a bottom-nav `HomeScreen`. `LogTimeScreen` creates entries; `EditTimeScreen` updates them; `RecentEntriesScreen` shows daily entries with a date picker; `SettingsScreen` manages credentials and ADO instances.

### `RecentEntriesScreen` (`lib/screens/recent_entries_screen.dart`)

State: `_groupByProject` toggle (local `setState`). Listens to `TimeEntryProvider` via `addListener` in `didChangeDependencies` (not `initState`) to survive tab switches; triggers `AdoService.prefetchForEntries` on each change.

**Layout (top → bottom):**
1. `FilterChip` toolbar — "Group by project" toggle
2. Date nav row — `chevron_left` / tappable date label / `chevron_right` (capped at today)
3. `_WeekSummaryStrip` — Mon–Sun day chips + `WeeklyProgressRing`. Two variants: `_buildCompact` (narrow) and `_buildEmphasized` (≥ `HarvestTokens.kWideBreakpoint`); emphasized shows day-of-month numerals + per-day `LinearProgressIndicator` against `ProjectCategoryProvider.dailyGoalHours`
4. Entry list — flat `SliverList` of `TimeEntryCard`, or `_buildGroupedList` when grouped. Grouped view uses `groupBy` (collection pkg) keyed on `projectId`, sorted by `createdAt` desc; each group rendered by `_buildProjectGroup` → `_ProjectGroupHeader`
5. `_DailyProgressBar` — sticky bottom bar; goal from `ProjectCategoryProvider.dailyGoalHours`, `HarvestTokens.warn` color when over; when viewing today shows a tick marker at the expected position + "Expected: Xh Ym" label (proportional: `elapsedRatio × dailyGoalHours`)

**Private widgets (all in this file):**
- `_WeekSummaryStrip` — reads `weeklyGoalHours` and `dailyGoalHours` from `ProjectCategoryProvider`; `_DayData` holds per-day state
- `_DailyProgressBar` — reads `dailyGoalHours`, `workDayStart`, `workDayEnd` from `ProjectCategoryProvider`; accepts `isToday` to conditionally show expected time tick + label; shows "Xh Ym remaining" or "+Xh Ym over goal"
- `_ProjectGroupHeader` — colored code badge (from `ProjectCategoryProvider.categoryFor`), project name + client, entry count, total hours
- **`lib/widgets/`** — `WorkItemPreview` fetches and renders a live ADO work item card (debounced 600 ms). `TimeEntryCard` renders an entry with an optional embedded ADO card.

### `SettingsScreen` (`lib/screens/settings_screen.dart`)

State: token + accountId `TextEditingController`s, `_obscureToken`, `_defaultProjectId`, `_defaultTaskId`, `_autoRefreshIntervalMinutes` (all loaded from SharedPreferences in `_load()`). No provider listeners — reads on demand.

**Sections (scrollable column):**
1. **Harvest Credentials** — API token (obscured) + Account ID fields
2. **Default Project** — `_DefaultProjectDropdown` → `_DefaultTaskDropdown` (only shown when project selected); stored as `default_project_id` / `default_task_id` in prefs
3. **Background Refresh** — interval dropdown (5/15/30/60 min); applied on save via `TimeEntryProvider.setRefreshInterval`
4. **Project Categories** — `_ProjectCategoryRow` per project; edit dialog has 12-color palette + code (≤5 chars); persisted via `ProjectCategoryProvider.setCategory`
5. **Weekly Goal** — free-text hours field; calls `ProjectCategoryProvider.setWeeklyGoal` on every keystroke
6. **Work Day** — start time + end time (tappable, `showTimePicker`) and break hours field; calls `setWorkDayStart` / `setWorkDayEnd` / `setBreakHours`; derived label shows "= Xh work day" live
7. **Azure DevOps Instances** — `_AdoInstanceList`; add/edit via `_showAdoDialog`; each row shows label, baseUrl, PAT presence dot, and Harvest GUID status (check/warn icon); GUID editable via `_showEditGuidDialog` → `AdoService.setHarvestGuid`
8. **Action buttons** — Save & Reload, Clear Cache & Refresh, Migrate ADO References (streams progress via `_MigrationProgressDialog`), Reset to Defaults

**Private widgets (all in this file):**
- `_SectionHeader` — title + optional trailing action widget
- `_AdoInstanceList` — watches `AdoInstanceProvider` + `AdoService`; "Reset to Defaults" resets to `AppConfig` defaults
- `_DefaultProjectDropdown` / `_DefaultTaskDropdown` — guard against stale selected IDs missing from current project list
- `_ProjectCategoryRow` — color swatch + code badge + edit button; opens `_showEditCategoryDialog` with `StatefulBuilder` dialog
- `_MigrationProgressDialog` — subscribes to `Stream<({int done, int total, int failed})>`; shows indeterminate → determinate `LinearProgressIndicator`

**ADO integration details:**

When a time entry links to an ADO work item, the external reference ID stored in Harvest uses the composite format: `AzureDevOps_{projectGuid}_{workItemType}_{numericId}`. The project GUID is fetched from ADO and cached. The app degrades gracefully if the GUID is unavailable (falls back to the numeric ID alone) or if no ADO PAT is configured.

**State setup** — `main.dart` wires all providers with `MultiProvider` and injects `AdoService` into both `AdoInstanceProvider` and `TimeEntryProvider`.
