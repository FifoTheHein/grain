# Harvest Tracker

A personal Flutter web app for logging time entries to [Harvest](https://www.getharvest.com/) directly from the browser, with first-class Azure DevOps integration.

## Features

### Log Time
- **Project & task selection** — loads your assigned projects and tasks from the Harvest API, with cascading dropdowns
- **Default project & task** — configure defaults in Settings so the form is pre-filled on load
- **Hours & minutes input** — pick hours (0–24) and minutes in 5-minute intervals
- **Date picker** — log time against any past date, defaulting to today

### Azure DevOps Integration
- **Configurable ADO instances** — add any number of Azure DevOps project URLs in Settings
- **PAT authentication** — store a Personal Access Token per instance (stored in `localStorage`, never committed)
- **Live work item preview** — type a work item number and see the title + state fetched from ADO in real time (debounced 600 ms), with a colour-coded state dot
- **Auto-prefixed notes** — notes are automatically prefixed, e.g. `Transport Azure DevOps User Story #13483 - your notes`
- **Clickable work item cards** — tapping the card opens the work item in ADO in a new tab
- **Native Harvest composite IDs** — entries are saved with the correct `AzureDevOps_{guid}_{type}_{id}` format that Harvest's own ADO integration uses, so time entries appear in the Harvest widget inside Azure DevOps
- **Automatic GUID detection** — the Harvest connection GUID is learned automatically from any natively-created entry and persisted to `localStorage`; no manual configuration needed, and the correct ID is used from the first submission on every subsequent session
- **GUID visibility & manual override** — each ADO instance in Settings shows its current Harvest connection GUID (green when known, orange when not yet learned); a pencil icon lets you paste the correct GUID manually when auto-detection hasn't worked, taking effect immediately without a reload

### Recent Entries
- **Default landing screen** — the app opens directly on today's entries
- **Weekly summary strip** — a compact Mon–Sun strip above the entries list shows each day's total hours and the week total, matching the native Harvest app; tap any day to navigate to it; the selected day is highlighted
- **Daily view** — browse entries by day with prev/next navigation and a date picker
- **Work item cards** — each ADO-linked entry shows a clickable card with title, `#id · state` (colour-coded dot), and the work item creator's avatar and display name
- **8-hour progress bar** — visual indicator of daily progress toward the 8 h goal, with overflow tracking
- **Edit entries** — tap the pencil icon on any card to open a pre-filled edit form; changes are saved via `PATCH` and reflected immediately in the list; editing non-ADO fields (hours, notes, date) preserves the existing ADO link exactly as-is
- **Delete entries** — tap the trash icon in the Edit Entry screen to permanently remove an entry after confirmation; the entry is removed from Harvest and from the local list immediately

### Background Auto-refresh
- Entries logged externally (native Harvest app, web) appear automatically without a manual refresh
- Refresh interval is configurable in Settings: 5 min, 15 min, 30 min, or 1 hour (default 15 min)
- Refreshes are silent — no spinner or interruption while you're actively using the app
- Skipped automatically if a submit, update, or delete is in progress to prevent conflicts

### Settings
- All credentials and ADO instances persist in browser `localStorage` and take effect immediately without recompiling
- **Background Refresh** — configure how often the app silently re-fetches the current week's entries
- **Clear Cache & Refresh** — force-reloads time entries from the Harvest API
- **Migrate ADO References** — upgrades current-week entries from plain numeric external reference IDs to the correct native composite format; also repairs entries saved with the wrong GUID or a corrupted ID from an earlier migration run; scans the past 28 days for native Harvest entries to learn the correct GUID even when all recent entries were app-created

## Project Structure

```
lib/
├── main.dart
├── config/
│   └── app_config.dart                 # credentials & default ADO instances (gitignored)
├── models/
│   ├── ado_work_item.dart
│   ├── project_assignment.dart
│   └── time_entry.dart
├── services/
│   ├── ado_service.dart                # ADO REST API — work item fetch & cache
│   └── harvest_service.dart            # Harvest API v2
├── providers/
│   ├── ado_instance_provider.dart      # ADO instances (localStorage)
│   ├── assignment_provider.dart
│   └── time_entry_provider.dart
├── screens/
│   ├── home_screen.dart
│   ├── edit_time_screen.dart           # pre-filled edit form (pushes as new route)
│   ├── log_time_screen.dart
│   ├── recent_entries_screen.dart
│   └── settings_screen.dart
└── widgets/
    ├── error_banner.dart
    ├── project_task_selector.dart
    ├── time_entry_card.dart
    └── work_item_preview.dart          # shared ADO work item preview card
```

## Setup

### 1. Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (web support enabled)
- A [Harvest personal access token](https://id.getharvest.com/developers)
- (Optional) Azure DevOps Personal Access Token with **Read** access to Work Items

### 2. Configure credentials

Create `lib/config/app_config.dart` (gitignored — never commit this file):

```dart
import '../models/time_entry.dart';

class AppConfig {
  static const String defaultToken = 'YOUR_HARVEST_TOKEN';
  static const String defaultAccountId = 'YOUR_ACCOUNT_ID';
  static const int userId = YOUR_USER_ID;
  static const String userAgent = 'YourName (your@email.com)';
  static const String baseUrl = 'https://api.harvestapp.com/v2';

  // Default ADO instances — can be overridden at runtime in Settings
  static const List<AdoInstance> defaultAdoInstances = [
    AdoInstance(
      label: 'My Project',
      baseUrl: 'https://dev.azure.com/my-org/My-Project',
    ),
  ];
}
```

> **Note:** `/_workitems/edit/{id}` is appended automatically — only provide the project base URL.

### 3. Install dependencies & run

```bash
flutter pub get
flutter run -d web-server --web-port=8080
```

Then open `http://localhost:8080` in Chrome.

### 4. Build for production

```bash
# MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from expanding /Harvest/ to a Windows path
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /Harvest/ --pwa-strategy=none
```

Serve the `build/web` directory from any static host.

## Settings Reference

All settings persist in browser `localStorage`:

| Setting                  | Description                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------ |
| API Token                | Harvest personal access token                                                                    |
| Account ID               | Harvest account ID                                                                               |
| Default Project          | Pre-selected project on the Log Time screen                                                      |
| Default Task             | Pre-selected task for the default project                                                        |
| Background Refresh       | How often the app silently re-fetches the current week (5 / 15 / 30 / 60 min; default 15 min)  |
| ADO Instances            | Add, edit, or remove Azure DevOps project URLs                                                   |
| PAT (per ADO)            | Personal Access Token for each ADO instance — enables work item fetch                            |
| Harvest GUID (per ADO)   | The Harvest connection GUID, shown per instance with green/orange status; editable manually when auto-detection has not worked |
| Clear Cache & Refresh    | Discards cached time entries and reloads from the Harvest API                                    |
| Migrate ADO References   | Upgrades current-week entries to the native composite ID format; corrects wrong-GUID and corrupted entries; learns from the past 28 days of entries |
