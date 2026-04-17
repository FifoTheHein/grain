# Group by Project — Design Spec

**Date:** 2026-04-17
**Branch:** screen/weekly-progress-ring
**Target file:** `lib/screens/recent_entries_screen.dart`

## Overview

Adds a "Group by project" toggle to the Recent Entries screen. Today's entries regroup by `projectId`, each group under a header showing a colour dot, project name, client name (if present), entry count, and total hours.

## Behaviour

| | |
|---|---|
| **Scope** | Selected day's entries only. Week strip, daily progress bar, and date picker are untouched. |
| **Group key** | `entry.projectId` |
| **Group sort** | Descending by `max(createdAt)` across entries in the group |
| **Within-group sort** | Descending by `createdAt` |
| **Header** | Colour dot · project name · client (if present) · entry count · total hours — label only, no tap target |
| **Collapse** | None — all groups always expanded |
| **Persistence** | Session-only. Plain `setState`, no `SharedPreferences`. Resets to off on app relaunch. |
| **Toggle location** | Recent Entries header row, right-aligned, as a `FilterChip` |
| **Toggle labels** | Off: *Group by project* · On: *Grouped by project* |

## Model changes

### `TimeEntry` — add `createdAt`

Add `createdAt` (nullable `String?`) parsed from `json['created_at']`. Used solely for group/within-group sort order. All existing fields remain unchanged.

```dart
// in TimeEntry class
final String? createdAt;

// in TimeEntry.fromJson
createdAt: json['created_at'] as String?,
```

### `HarvestProject` — add `clientName`

Add `clientName` (nullable `String?`) parsed from the `client` object in the assignments API response.

```dart
// in HarvestProject class
final String? clientName;

// in HarvestProject.fromAssignment
clientName: (assignment['client'] as Map<String, dynamic>?)?['name'] as String?,
```

## State changes in `_RecentEntriesScreenState`

Remove `_loadGroupPref()`, `_toggleGrouping()`, and the `shared_preferences` import for grouping. Replace with:

```dart
bool _groupByProject = false;
```

Toggle is now simply:

```dart
onSelected: (v) => setState(() => _groupByProject = v),
```

## Toggle UI

The existing toolbar `Padding` block (lines 186–206 of `recent_entries_screen.dart`) contains an `IconButton`. Replace the entire `IconButton` with a `FilterChip` — the surrounding `Padding` + `Row` stay:

```dart
FilterChip(
  avatar: Icon(
    _groupByProject ? Icons.folder_open : Icons.folder_outlined,
    size: 16,
  ),
  label: Text(_groupByProject ? 'Grouped by project' : 'Group by project'),
  selected: _groupByProject,
  onSelected: (v) => setState(() => _groupByProject = v),
)
```

## Dependencies

Add `collection` explicitly to `pubspec.yaml` (it's a transitive Flutter dep but should be declared):

```yaml
dependencies:
  collection: ^1.18.0
```

## Grouping logic

Uses `package:collection`'s `groupBy`.

```dart
import 'package:collection/collection.dart';

// Group by projectId
final grouped = groupBy<TimeEntry, int>(entries, (e) => e.projectId);

// Sort within each group: newest createdAt first
for (final es in grouped.values) {
  es.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
}

// Sort groups: group with most recent createdAt first
final groupList = grouped.entries.toList()
  ..sort((a, b) =>
      (b.value.first.createdAt ?? '').compareTo(a.value.first.createdAt ?? ''));
```

## `_ProjectGroupHeader` widget

Replaces the existing `_ProjectGroupHeader`. New anatomy:

```
[colour dot]  [project name]  [·  client name]          [N entries]  [h:mm]
```

- **Colour dot**: 10×10 filled circle in the project's category colour. Falls back to `HarvestTokens.text3` if no category.
- **Project name**: 13px, weight 600, `HarvestTokens.text`.
- **Client separator + name**: only rendered when `clientName != null`. Separator is `·` in `HarvestTokens.text4`; client name is 11px, weight 500, `HarvestTokens.text3`. Both truncate with ellipsis.
- **Spacer** between name block and right-side metadata.
- **Entry count**: 11px, weight 500, `HarvestTokens.text3` — `"N entry"` / `"N entries"`.
- **Total hours**: 13px, weight 600, in the project's category colour (or text3 fallback). Monospace, tabular figures via `FontFeature.tabularFigures()`.
- Bottom border: `HarvestTokens.divider` (1px), padding `fromLTRB(4, 10, 4, 7)`.

## Render structure

```dart
// For each group in groupList:
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    _ProjectGroupHeader(projectId: group.key, entries: group.value, ...),
    const SizedBox(height: 8),
    ...group.value.map((e) => TimeEntryCard(entry: e)),
  ],
)
// Groups separated by SizedBox(height: 16)
```

Wrap in a `SliverToBoxAdapter` containing a `Column` with the group columns.

## Flat list sort

When grouped mode is off, apply the same `createdAt` descending sort to the flat list so order is consistent.

## What is NOT changing

- `TimeEntryCard` internals
- Week summary strip (`_WeekSummaryStrip`)
- Daily progress bar (`_DailyProgressBar`)
- Date picker / navigation
- ADO integration
- Any other screen
