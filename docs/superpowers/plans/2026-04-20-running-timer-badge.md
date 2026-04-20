# Running Timer Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a small play-arrow badge overlaid on the `DurationPill` when a time entry's timer is actively running (`is_running: true` from Harvest API).

**Architecture:** Add `isRunning` to the `TimeEntry` model parsed from JSON, rename `DurationPill`'s `active` param to `running` and overlay a badge via `Stack` when true, then wire the flag through `TimeEntryCard`.

**Tech Stack:** Flutter (Dart), `HarvestTokens` color constants, `Icons.play_arrow` from Material.

---

## Files

| Action | File | Change |
|--------|------|--------|
| Modify | `lib/models/time_entry.dart` | Add `isRunning` field + JSON parse |
| Modify | `lib/widgets/duration_pill.dart` | Rename `active` → `running`, add badge Stack |
| Modify | `lib/widgets/time_entry_card.dart` | Pass `running: entry.isRunning` |

---

### Task 1: Add `isRunning` to `TimeEntry`

**Files:**
- Modify: `lib/models/time_entry.dart`

- [ ] **Step 1: Add `isRunning` field to `TimeEntry`**

In `lib/models/time_entry.dart`, replace the `TimeEntry` class with:

```dart
class TimeEntry {
  final int id;
  final String spentDate;
  final double hours;
  final String? notes;
  final int projectId;
  final String projectName;
  final int taskId;
  final String taskName;
  final String? userName;
  final ExternalReference? externalReference;
  final String? createdAt;
  final bool isRunning;

  const TimeEntry({
    required this.id,
    required this.spentDate,
    required this.hours,
    this.notes,
    required this.projectId,
    required this.projectName,
    required this.taskId,
    required this.taskName,
    this.userName,
    this.externalReference,
    this.createdAt,
    this.isRunning = false,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    final ext = json['external_reference'] as Map<String, dynamic>?;
    final user = json['user'] as Map<String, dynamic>?;
    final project = json['project'] as Map<String, dynamic>;
    final task = json['task'] as Map<String, dynamic>;
    return TimeEntry(
      id: json['id'] as int,
      spentDate: json['spent_date'] as String,
      hours: (json['hours'] as num).toDouble(),
      notes: json['notes'] as String?,
      projectId: project['id'] as int,
      projectName: project['name'] as String,
      taskId: task['id'] as int,
      taskName: task['name'] as String,
      userName: user?['name'] as String?,
      externalReference: ext == null
          ? null
          : ExternalReference(
              id: ext['id'] as String,
              permalink: ext['permalink'] as String?,
            ),
      createdAt: json['created_at'] as String?,
      isRunning: json['is_running'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/models/time_entry.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/models/time_entry.dart
git commit -m "feat: add isRunning field to TimeEntry"
```

---

### Task 2: Add running badge to `DurationPill`

**Files:**
- Modify: `lib/widgets/duration_pill.dart`

- [ ] **Step 1: Replace `DurationPill` implementation**

Replace the entire contents of `lib/widgets/duration_pill.dart` with:

```dart
import 'package:flutter/material.dart';
import '../theme/harvest_tokens.dart';

class DurationPill extends StatelessWidget {
  final double hours;
  final double size;
  final bool running;

  const DurationPill({
    super.key,
    required this.hours,
    this.size = 44,
    this.running = false,
  });

  String _label() {
    final total = (hours * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0 && m == 0) return '–';
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h\n${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final label = _label();
    final raw = label.replaceAll('\n', '');
    final fontSize = raw.length > 4 ? 11.0 : raw.length > 2 ? 12.0 : 13.0;

    final pill = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running ? HarvestTokens.brand : HarvestTokens.brandTint,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Courier New',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: running ? Colors.white : HarvestTokens.brand600,
          height: 1.1,
        ),
      ),
    );

    if (!running) return pill;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        pill,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HarvestTokens.brand,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(
              Icons.play_arrow,
              size: 9,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/widgets/duration_pill.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/duration_pill.dart
git commit -m "feat: add running badge to DurationPill"
```

---

### Task 3: Wire `running` flag in `TimeEntryCard`

**Files:**
- Modify: `lib/widgets/time_entry_card.dart`

- [ ] **Step 1: Pass `running` to `DurationPill`**

In `lib/widgets/time_entry_card.dart`, find the line:

```dart
DurationPill(hours: entry.hours),
```

Replace it with:

```dart
DurationPill(hours: entry.hours, running: entry.isRunning),
```

- [ ] **Step 2: Analyze the whole project**

```bash
flutter analyze
```

Expected: no errors. (`EditTimeScreen` uses `DurationPill(hours: ..., size: 32)` with no `active` param, so the rename is a no-op there — it uses `running: false` by default.)

- [ ] **Step 3: Build and manually verify**

```bash
flutter run -d web-server --web-port=8080
```

Open `http://localhost:8080` in a browser. Navigate to the Recent Entries screen. An entry with an active running timer should show:
- Solid orange `DurationPill` (instead of the tinted background)
- A small orange circle with a white play arrow at the bottom-right corner of the pill

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/time_entry_card.dart
git commit -m "feat: show running badge on active timer entry"
```
