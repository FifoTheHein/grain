# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install dependencies
flutter pub get

# Run development server
flutter run -d web-server --web-port=8080

# Build for production
flutter build web --release

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
- **`lib/screens/`** — Four screens composed under a bottom-nav `HomeScreen`. `LogTimeScreen` creates entries; `EditTimeScreen` updates them; `RecentEntriesScreen` shows daily entries with a date picker; `SettingsScreen` manages credentials and ADO instances.
- **`lib/widgets/`** — `WorkItemPreview` fetches and renders a live ADO work item card (debounced 600 ms). `TimeEntryCard` renders an entry with an optional embedded ADO card.

**ADO integration details:**

When a time entry links to an ADO work item, the external reference ID stored in Harvest uses the composite format: `AzureDevOps_{projectGuid}_{workItemType}_{numericId}`. The project GUID is fetched from ADO and cached. The app degrades gracefully if the GUID is unavailable (falls back to the numeric ID alone) or if no ADO PAT is configured.

**State setup** — `main.dart` wires all providers with `MultiProvider` and injects `AdoService` into both `AdoInstanceProvider` and `TimeEntryProvider`.
