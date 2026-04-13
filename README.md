# Harvest Tracker

A personal Flutter web app for logging time entries to [Harvest](https://www.getharvest.com/) directly from the browser.

## Features

- **Project & task selection** — loads your assigned projects and tasks from the Harvest API, with cascading dropdowns
- **Default project & task** — configure a default project and task in Settings so the form is pre-filled on load
- **Hours & minutes input** — pick hours (0–24) and minutes (5-minute intervals) instead of typing decimals
- **Azure DevOps linking** — optionally link a work item to a time entry:
  - Select an ADO instance (configurable in Settings) and enter a work item number
  - Permalink is auto-constructed as `{projectUrl}/_workitems/edit/{id}`
  - Notes are automatically prefixed, e.g. `Transport Azure DevOps User Story #13483 - your notes here`
  - Work item links in the Recent tab are clickable and open in a new tab
- **Daily entries view** — browse entries by day with prev/next navigation and a date picker
- **8-hour progress bar** — visual indicator of daily progress toward the 8h goal, with overflow tracking
- **Configurable settings** — all credentials and ADO instances are stored in browser `localStorage` and can be updated at runtime without recompiling

## Project Structure

```
lib/
├── main.dart
├── config/
│   └── app_config.dart              # credentials & default ADO instances (gitignored)
├── models/
│   ├── project_assignment.dart
│   └── time_entry.dart
├── services/
│   └── harvest_service.dart         # Harvest API v2 calls
├── providers/
│   ├── ado_instance_provider.dart   # ADO instances (localStorage)
│   ├── assignment_provider.dart
│   └── time_entry_provider.dart
├── screens/
│   ├── home_screen.dart
│   ├── log_time_screen.dart
│   ├── recent_entries_screen.dart
│   └── settings_screen.dart
└── widgets/
    ├── error_banner.dart
    ├── project_task_selector.dart
    └── time_entry_card.dart
```

## Setup

### 1. Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (web support enabled)
- A [Harvest personal access token](https://id.getharvest.com/developers)

### 2. Configure credentials

Create `lib/config/app_config.dart` (this file is gitignored — never commit it):

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
flutter build web --release
```

Serve the `build/web` directory from any static host.

## Settings

All settings persist in browser `localStorage` and take effect immediately without recompiling:

| Setting | Description |
|---|---|
| API Token | Harvest personal access token |
| Account ID | Harvest account ID |
| Default Project | Pre-selected project on the Log Time screen |
| Default Task | Pre-selected task for the default project |
| ADO Instances | Add, edit, or remove Azure DevOps project links |
