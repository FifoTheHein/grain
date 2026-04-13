# Harvest Tracker

[![Claude Code Review](https://github.com/FifoTheHein/harvest-tracker/actions/workflows/claude-code-review.yml/badge.svg)](https://github.com/FifoTheHein/harvest-tracker/actions/workflows/claude-code-review.yml)

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

### Recent Entries
- **Default landing screen** — the app opens directly on today's entries
- **Daily view** — browse entries by day with prev/next navigation and a date picker
- **Work item cards** — each ADO-linked entry shows a clickable card with title, `#id · state` (colour-coded dot), and the work item creator's avatar and display name
- **8-hour progress bar** — visual indicator of daily progress toward the 8 h goal, with overflow tracking

### Settings
- All credentials and ADO instances persist in browser `localStorage` and take effect immediately without recompiling

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
flutter build web --release
```

Serve the `build/web` directory from any static host.

## Settings Reference

All settings persist in browser `localStorage`:

| Setting         | Description                                                           |
| --------------- | --------------------------------------------------------------------- |
| API Token       | Harvest personal access token                                         |
| Account ID      | Harvest account ID                                                    |
| Default Project | Pre-selected project on the Log Time screen                           |
| Default Task    | Pre-selected task for the default project                             |
| ADO Instances   | Add, edit, or remove Azure DevOps project URLs                        |
| PAT (per ADO)   | Personal Access Token for each ADO instance — enables work item fetch |
