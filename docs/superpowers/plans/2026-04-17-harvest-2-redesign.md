# Harvest Tracker 2.0 — Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the full Harvest 2.0 visual redesign across 9 sequential git branches, each independently shippable.

**Architecture:** Foundation first — design tokens (PR 1) and project-category model (PR 2) land before widget and screen changes (PRs 3–9). All new state persists in browser localStorage via `shared_preferences`. No API changes; no model shape changes to existing classes.

**Tech Stack:** Flutter 3 (web), Material 3, `provider` package, `shared_preferences`, `intl`

**No automated tests exist** (only a placeholder in `test/widget_test.dart`). Each task verifies with `flutter analyze` + a dev-server visual check instead of a test suite.

**Run commands:**
```bash
# Lint check
flutter analyze

# Dev server
MSYS_NO_PATHCONV=1 flutter run -d web-server --web-port=8080

# Production build
MSYS_NO_PATHCONV=1 flutter build web --release --base-href /Harvest/ --pwa-strategy=none
```

---

## File Map

| File | Status | PR | Responsibility |
|---|---|---|---|
| `lib/theme/harvest_tokens.dart` | Create | 1 | All color constants + `kWideBreakpoint` |
| `lib/main.dart` | Modify | 1, 2 | ThemeData + MultiProvider registration |
| `lib/screens/home_screen.dart` | Modify | 1, 9 | Color literal → token; responsive shell |
| `lib/screens/recent_entries_screen.dart` | Modify | 1, 4, 5 | Color literals; grouping; emphasized week strip |
| `lib/models/project_category.dart` | Create | 2 | `ProjectCategory` data class |
| `lib/providers/project_category_provider.dart` | Create | 2 | Category map + weekly goal, SharedPreferences |
| `lib/widgets/duration_pill.dart` | Create | 3 | 44px circular hours pill |
| `lib/widgets/work_item_chip.dart` | Create | 3 | Compact ADO card with state stripe |
| `lib/widgets/time_entry_card.dart` | Rewrite | 3 | New card layout |
| `lib/screens/log_time_screen.dart` | Modify | 6 | SegmentedButton, responsive layout, quiet ADO |
| `lib/screens/settings_screen.dart` | Modify | 7 | Sections, ADO row v2, categories, weekly goal |
| `lib/screens/edit_time_screen.dart` | Modify | 8 | Context banner |

---

## Task 1: Design Tokens (PR `theme/harvest-tokens`)

**Files:**
- Create: `lib/theme/harvest_tokens.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/screens/recent_entries_screen.dart`

- [ ] **Step 1.1: Create the token file**

Create `lib/theme/harvest_tokens.dart`:

```dart
import 'package:flutter/material.dart';

class HarvestTokens {
  HarvestTokens._();

  // Brand
  static const brand = Color(0xFFFA5D24);
  static const brand600 = Color(0xFFE54714);
  static const brandTint = Color(0xFFFEE6DA);
  static const brandTint2 = Color(0xFFFDD3BD);

  // Surfaces (warm paper scale)
  static const bg = Color(0xFFF6F3EE);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFBF8F3);
  static const surface3 = Color(0xFFF1ECE3);
  static const border = Color(0xFFE8E1D4);
  static const borderStrong = Color(0xFFD5CCBB);
  static const divider = Color(0xFFEFEAE0);

  // Ink
  static const text = Color(0xFF1A1814);
  static const text2 = Color(0xFF56504A);
  static const text3 = Color(0xFF8A837A);
  static const text4 = Color(0xFFB4AEA4);

  // ADO work-item state colors
  static const stateActive = Color(0xFF2563EB);
  static const stateDone = Color(0xFF16A34A);
  static const stateRemoved = Color(0xFF8A837A);
  static const stateNew = Color(0xFFC026D3);

  // Semantic
  static const error = Color(0xFFDC2626);
  static const warn = Color(0xFFD97706);
  static const success = Color(0xFF16A34A);

  // Layout
  static const double kWideBreakpoint = 720.0;
}
```

- [ ] **Step 1.2: Update ThemeData in `lib/main.dart`**

Replace the existing `theme:` block in `HarvestApp.build`:

```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: HarvestTokens.brand,
  ),
  scaffoldBackgroundColor: HarvestTokens.bg,
  cardTheme: const CardTheme(
    color: HarvestTokens.surface,
    elevation: 0,
    margin: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      side: BorderSide(color: HarvestTokens.border),
    ),
  ),
  dividerColor: HarvestTokens.divider,
  useMaterial3: true,
),
```

Add the import at the top of `lib/main.dart`:
```dart
import 'theme/harvest_tokens.dart';
```

- [ ] **Step 1.3: Replace color literal in `lib/screens/home_screen.dart`**

In `home_screen.dart`, change the AppBar colors:

```dart
// Before
backgroundColor: const Color(0xFFFA5D24),
foregroundColor: Colors.white,

// After
backgroundColor: HarvestTokens.brand,
foregroundColor: Colors.white,
```

Add import at top:
```dart
import '../theme/harvest_tokens.dart';
```

- [ ] **Step 1.4: Replace color literals in `lib/screens/recent_entries_screen.dart`**

In `_DailyProgressBar.build`, replace the `barColor` line:

```dart
// Before
final barColor = isOver ? Colors.orange : colorScheme.primary;

// After
final barColor = isOver ? HarvestTokens.warn : HarvestTokens.brand;
```

Replace the overflow pulse marker color:

```dart
// Before
color: Colors.orange.shade800,

// After
color: HarvestTokens.brand600,
```

Add import at top:
```dart
import '../theme/harvest_tokens.dart';
```

- [ ] **Step 1.5: Verify**

```bash
flutter analyze
```

Expected: no errors or new warnings.

- [ ] **Step 1.6: Commit**

```bash
git checkout -b theme/harvest-tokens
git add lib/theme/harvest_tokens.dart lib/main.dart lib/screens/home_screen.dart lib/screens/recent_entries_screen.dart
git commit -m "feat: add HarvestTokens and wire into ThemeData

Warm paper surface scale, brand orange, ADO state colors.
Replace scattered color literals with token references.
Add kWideBreakpoint = 720.0 for responsive breakpoints."
```

---

## Task 2: Project Category Model (PR `model/project-categories`)

**Files:**
- Create: `lib/models/project_category.dart`
- Create: `lib/providers/project_category_provider.dart`
- Modify: `lib/main.dart`

- [ ] **Step 2.1: Create `lib/models/project_category.dart`**

```dart
import 'package:flutter/material.dart';

class ProjectCategory {
  final Color color;
  final Color tint;
  final String code;

  const ProjectCategory({
    required this.color,
    required this.tint,
    required this.code,
  });

  Map<String, dynamic> toJson() => {
        'color': color.value,
        'tint': tint.value,
        'code': code,
      };

  factory ProjectCategory.fromJson(Map<String, dynamic> j) => ProjectCategory(
        color: Color(j['color'] as int),
        tint: Color(j['tint'] as int),
        code: j['code'] as String,
      );
}
```

- [ ] **Step 2.2: Create `lib/providers/project_category_provider.dart`**

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_category.dart';

class ProjectCategoryProvider extends ChangeNotifier {
  static const _categoriesKey = 'project_categories_v1';
  static const _weeklyGoalKey = 'weekly_goal_hours';

  final Map<int, ProjectCategory> _categories = {};
  double _weeklyGoalHours = 40.0;

  // 12-color fixed palette (Material 500-level, warm-to-cool spread)
  static const _palette = [
    _Swatch(Color(0xFFFA5D24), Color(0xFFFEE6DA)), // brand orange
    _Swatch(Color(0xFF7C5CFF), Color(0xFFEEE9FF)), // violet
    _Swatch(Color(0xFF14B8A6), Color(0xFFD7F5F0)), // teal
    _Swatch(Color(0xFF8A837A), Color(0xFFF1ECE3)), // warm gray
    _Swatch(Color(0xFF2563EB), Color(0xFFDCEAFD)), // blue
    _Swatch(Color(0xFF16A34A), Color(0xFFDCFCE7)), // green
    _Swatch(Color(0xFFC026D3), Color(0xFFF5D0FE)), // purple
    _Swatch(Color(0xFFD97706), Color(0xFFFEF3C7)), // amber
    _Swatch(Color(0xFFDC2626), Color(0xFFFEE2E2)), // red
    _Swatch(Color(0xFF0891B2), Color(0xFFCFFAFE)), // cyan
    _Swatch(Color(0xFF65A30D), Color(0xFFECFCCB)), // lime
    _Swatch(Color(0xFFDB2777), Color(0xFFFCE7F3)), // pink
  ];

  Map<int, ProjectCategory> get categories => Map.unmodifiable(_categories);
  double get weeklyGoalHours => _weeklyGoalHours;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_categoriesKey);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _categories.clear();
      map.forEach((k, v) {
        _categories[int.parse(k)] =
            ProjectCategory.fromJson(v as Map<String, dynamic>);
      });
    }
    _weeklyGoalHours = prefs.getDouble(_weeklyGoalKey) ?? 40.0;
    notifyListeners();
  }

  /// Returns the stored category for [projectId], or auto-assigns one from
  /// the palette using the project ID as a deterministic index.
  ProjectCategory categoryFor(int projectId, {required String fallbackCode}) {
    if (_categories.containsKey(projectId)) return _categories[projectId]!;
    final swatch = _palette[projectId.abs() % _palette.length];
    return ProjectCategory(
      color: swatch.color,
      tint: swatch.tint,
      code: fallbackCode.isEmpty ? '?' : fallbackCode,
    );
  }

  Future<void> setCategory(int projectId, ProjectCategory cat) async {
    _categories[projectId] = cat;
    notifyListeners();
    await _persist();
  }

  Future<void> setWeeklyGoal(double hours) async {
    _weeklyGoalHours = hours;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_weeklyGoalKey, hours);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final e in _categories.entries) '${e.key}': e.value.toJson(),
    };
    await prefs.setString(_categoriesKey, jsonEncode(map));
  }
}

class _Swatch {
  final Color color;
  final Color tint;
  const _Swatch(this.color, this.tint);
}
```

- [ ] **Step 2.3: Register provider in `lib/main.dart`**

Add import:
```dart
import 'providers/project_category_provider.dart';
```

Add to the `providers:` list in `MultiProvider`, after the existing providers:
```dart
ChangeNotifierProvider(
  create: (_) => ProjectCategoryProvider()..load(),
),
```

- [ ] **Step 2.4: Verify**

```bash
flutter analyze
```

Expected: no errors.

- [ ] **Step 2.5: Commit**

```bash
git checkout -b model/project-categories
git add lib/models/project_category.dart lib/providers/project_category_provider.dart lib/main.dart
git commit -m "feat: add ProjectCategoryProvider with 12-color palette and weekly goal

Persists Map<projectId, ProjectCategory> + weeklyGoalHours to SharedPreferences.
Auto-assigns palette color by project ID hash when no override stored.
Exposes setCategory() and setWeeklyGoal() for Settings UI (PR 7)."
```

---

## Task 3: Entry Card v2 (PR `widget/entry-card-v2`)

**Files:**
- Create: `lib/widgets/duration_pill.dart`
- Create: `lib/widgets/work_item_chip.dart`
- Rewrite: `lib/widgets/time_entry_card.dart`

**Note:** `lib/widgets/work_item_preview.dart` is NOT changed.

- [ ] **Step 3.1: Create `lib/widgets/duration_pill.dart`**

```dart
import 'package:flutter/material.dart';
import '../theme/harvest_tokens.dart';

class DurationPill extends StatelessWidget {
  final double hours;
  final double size;
  final bool active;

  const DurationPill({
    super.key,
    required this.hours,
    this.size = 44,
    this.active = false,
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
    // font size: 13px ≤2 chars, 12px 3-4 chars, 11px 5+
    final raw = label.replaceAll('\n', '');
    final fontSize = raw.length > 4 ? 11.0 : raw.length > 2 ? 12.0 : 13.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? HarvestTokens.brand : HarvestTokens.brandTint,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : HarvestTokens.brand600,
          height: 1.1,
        ),
      ),
    );
  }
}
```

- [ ] **Step 3.2: Create `lib/widgets/work_item_chip.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../models/ado_work_item.dart';
import '../theme/harvest_tokens.dart';

class WorkItemChip extends StatelessWidget {
  final String workItemId;
  final AdoWorkItem? cached;
  final bool isLoading;
  final String? permalink;

  const WorkItemChip({
    super.key,
    required this.workItemId,
    this.cached,
    this.isLoading = false,
    this.permalink,
  });

  Color _stateColor(String state) {
    final s = state.toLowerCase();
    if (s.contains('done') || s.contains('closed') || s.contains('resolved')) {
      return HarvestTokens.stateDone;
    }
    if (s.contains('active') ||
        s.contains('progress') ||
        s.contains('committed')) {
      return HarvestTokens.stateActive;
    }
    if (s.contains('removed') || s.contains('cut')) {
      return HarvestTokens.stateRemoved;
    }
    return HarvestTokens.stateNew;
  }

  void _open() {
    if (permalink != null) web.window.open(permalink!, '_blank');
  }

  String? _initials(String? name) {
    if (name == null || name.isEmpty) return null;
    final parts = name.trim().split(' ');
    return parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: HarvestTokens.surface2,
          border: Border.all(color: HarvestTokens.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: HarvestTokens.text4,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Looking up work item…',
              style: TextStyle(fontSize: 12, color: HarvestTokens.text3),
            ),
          ],
        ),
      );
    }

    if (cached == null) {
      return GestureDetector(
        onTap: _open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new, size: 13, color: HarvestTokens.brand600),
            const SizedBox(width: 6),
            Text(
              'ADO #$workItemId',
              style: TextStyle(
                fontSize: 12,
                color: HarvestTokens.brand600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      );
    }

    final sColor = _stateColor(cached!.state);
    final initials = _initials(cached!.createdByName);

    return GestureDetector(
      onTap: _open,
      child: Container(
        decoration: BoxDecoration(
          color: HarvestTokens.surface2,
          border: Border.all(color: HarvestTokens.border),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.hardEdge,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: sColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cached!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '#$workItemId',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: sColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('·',
                              style: TextStyle(
                                  fontSize: 11, color: HarvestTokens.text4)),
                          const SizedBox(width: 4),
                          Text(
                            cached!.state,
                            style: TextStyle(
                              fontSize: 11,
                              color: sColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (cached!.workItemType != null) ...[
                            const SizedBox(width: 4),
                            Text('·',
                                style: TextStyle(
                                    fontSize: 11, color: HarvestTokens.text4)),
                            const SizedBox(width: 4),
                            Text(
                              cached!.workItemType!,
                              style: TextStyle(
                                  fontSize: 11, color: HarvestTokens.text3),
                            ),
                          ],
                          const Spacer(),
                          if (initials != null) ...[
                            Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: HarvestTokens.brandTint,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: HarvestTokens.brand600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Icon(Icons.open_in_new,
                              size: 12, color: HarvestTokens.text3),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3.3: Rewrite `lib/widgets/time_entry_card.dart`**

Replace the entire file:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/project_category_provider.dart';
import '../screens/edit_time_screen.dart';
import '../services/ado_service.dart';
import '../theme/harvest_tokens.dart';
import 'duration_pill.dart';
import 'work_item_chip.dart';

class TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;

  const TimeEntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final hasAdoRef = entry.externalReference != null;

    // Resolve ADO instance for this entry
    AdoInstance? matchingInstance;
    if (hasAdoRef) {
      final instances = context.watch<AdoInstanceProvider>().instances;
      final permalink = entry.externalReference!.permalink ?? '';
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          matchingInstance = inst;
          break;
        }
      }
    }

    final adoService = hasAdoRef ? context.watch<AdoService>() : null;
    final rawRefId = entry.externalReference?.id ?? '';
    final workItemId =
        rawRefId.isNotEmpty ? AdoService.parseWorkItemId(rawRefId) : '';

    // Self-trigger fetch when card renders without cached data.
    if (matchingInstance != null &&
        matchingInstance.pat != null &&
        adoService != null &&
        adoService.getCached(matchingInstance.label, workItemId) == null &&
        !adoService.isPending(matchingInstance.label, workItemId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        adoService.fetchWorkItem(matchingInstance!, workItemId);
      });
    }

    // Project category for the color chip
    final catProvider = context.watch<ProjectCategoryProvider>();
    final cat = catProvider.categoryFor(
      entry.projectId,
      fallbackCode: entry.projectName
          .split(' ')
          .where((w) => w.isNotEmpty)
          .take(3)
          .map((w) => w[0].toUpperCase())
          .join(),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading: duration pill
            DurationPill(hours: entry.hours),
            const SizedBox(width: 12),

            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row: project code chip + task name
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cat.tint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          cat.code,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: cat.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.taskName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HarvestTokens.text,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Notes
                  if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: HarvestTokens.text2,
                        height: 1.45,
                      ),
                    ),
                  ],

                  // ADO chip
                  if (hasAdoRef) ...[
                    const SizedBox(height: 6),
                    if (matchingInstance != null && adoService != null)
                      WorkItemChip(
                        workItemId: workItemId,
                        cached: adoService.getCached(
                            matchingInstance.label, workItemId),
                        isLoading: adoService.isPending(
                            matchingInstance.label, workItemId),
                        permalink: entry.externalReference!.permalink,
                      )
                    else
                      GestureDetector(
                        onTap: () {
                          final p = entry.externalReference!.permalink;
                          if (p != null) web.window.open(p, '_blank');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new,
                                size: 13,
                                color: HarvestTokens.brand600),
                            const SizedBox(width: 6),
                            Text(
                              'ADO #$workItemId',
                              style: const TextStyle(
                                fontSize: 12,
                                color: HarvestTokens.brand600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Trailing: edit button
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: 'Edit entry',
              color: HarvestTokens.text3,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditTimeScreen(entry: entry),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3.4: Verify**

```bash
flutter analyze
```

Expected: no errors. Also start the dev server and open `http://localhost:8080`. The Recent tab should show the new card layout: orange circle pill on left, project-code chip next to task name, compact ADO chip.

- [ ] **Step 3.5: Commit**

```bash
git checkout -b widget/entry-card-v2
git add lib/widgets/duration_pill.dart lib/widgets/work_item_chip.dart lib/widgets/time_entry_card.dart
git commit -m "feat: rewrite TimeEntryCard with DurationPill, project chip, WorkItemChip

DurationPill: 44px orange-tint circle with monospace hours label.
Project code chip: 3-letter, colored from ProjectCategoryProvider.
WorkItemChip: compact card with 3px state stripe replaces full WorkItemPreview inline."
```

---

## Task 4: Recent Entries Grouping (PR `screen/recent-entries-grouping`)

**Files:**
- Modify: `lib/screens/recent_entries_screen.dart`

- [ ] **Step 4.1: Add imports to `recent_entries_screen.dart`**

Add at the top with existing imports:
```dart
import '../providers/assignment_provider.dart';
import '../providers/project_category_provider.dart';
import '../theme/harvest_tokens.dart';
```

- [ ] **Step 4.2: Add `_groupByProject` state to `_RecentEntriesScreenState`**

Add to the state class (after existing fields like `_timeEntryProvider`):
```dart
bool _groupByProject = false;
```

- [ ] **Step 4.3: Load grouping pref in `didChangeDependencies`**

Add a SharedPreferences load in `initState` (add this method to the state class):
```dart
@override
void initState() {
  super.initState();
  _loadGroupPref();
}

Future<void> _loadGroupPref() async {
  final prefs = await SharedPreferences.getInstance();
  if (mounted) {
    setState(() {
      _groupByProject = prefs.getBool('group_by_project') ?? false;
    });
  }
}

Future<void> _toggleGrouping() async {
  final next = !_groupByProject;
  setState(() => _groupByProject = next);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('group_by_project', next);
}
```

Also add the SharedPreferences import at the top:
```dart
import 'package:shared_preferences/shared_preferences.dart';
```

- [ ] **Step 4.4: Add grouping toggle to AppBar in `HomeScreen`**

The grouping button lives in `RecentEntriesScreen` — expose it via the screen's appbar actions. Since `HomeScreen` owns the AppBar, the cleanest approach is to put the grouping button in `RecentEntriesScreen`'s build as a `Padding` row above the date picker, not in the AppBar. Use an icon row:

Inside `RecentEntriesScreen.build`, just above the date picker header, add:
```dart
// Toolbar row with grouping toggle
Padding(
  padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Tooltip(
        message: _groupByProject ? 'Flat list' : 'Group by project',
        child: IconButton(
          icon: Icon(
            Icons.filter_list,
            color: _groupByProject
                ? HarvestTokens.brand
                : HarvestTokens.text3,
          ),
          onPressed: _toggleGrouping,
        ),
      ),
    ],
  ),
),
```

- [ ] **Step 4.5: Add `_ProjectGroupHeader` private widget**

Add this class at the bottom of `recent_entries_screen.dart` (before or after `_DailyProgressBar`):

```dart
class _ProjectGroupHeader extends StatelessWidget {
  final int projectId;
  final String projectName;
  final ProjectCategory category;
  final int entryCount;
  final double totalHours;

  const _ProjectGroupHeader({
    required this.projectId,
    required this.projectName,
    required this.category,
    required this.entryCount,
    required this.totalHours,
  });

  String _fmt(double hours) {
    final total = (hours * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: category.tint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              category.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: category.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              projectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HarvestTokens.text,
              ),
            ),
          ),
          Text(
            _fmt(totalHours),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: category.color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· $entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
            style: const TextStyle(fontSize: 11, color: HarvestTokens.text3),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4.6: Replace the `SliverList` with grouped/flat builder**

In `_RecentEntriesScreenState.build`, replace the existing `SliverList` block with:

```dart
if (provider.entries.isEmpty)
  const SliverFillRemaining(
    child: Center(child: Text('No entries for this day.')),
  )
else if (_groupByProject)
  SliverToBoxAdapter(child: _buildGroupedList(context, provider.entries))
else
  SliverList(
    delegate: SliverChildBuilderDelegate(
      (ctx, i) => TimeEntryCard(entry: provider.entries[i]),
      childCount: provider.entries.length,
    ),
  ),
```

Add the `_buildGroupedList` method to `_RecentEntriesScreenState`:

```dart
Widget _buildGroupedList(BuildContext context, List entries) {
  final catProvider = context.watch<ProjectCategoryProvider>();
  final projects = context.watch<AssignmentProvider>().projects;

  // Preserve first-occurrence order
  final groupOrder = <int>[];
  final groups = <int, List>{};
  for (final e in entries) {
    if (!groups.containsKey(e.projectId)) {
      groups[e.projectId] = [];
      groupOrder.add(e.projectId);
    }
    groups[e.projectId]!.add(e);
  }

  return Column(
    children: [
      for (final pid in groupOrder) ...[
        const SizedBox(height: 8),
        Builder(builder: (ctx) {
          final proj = projects.firstWhere(
            (p) => p.id == pid,
            orElse: () => HarvestProject(
                id: pid,
                name: entries.first.projectName,
                code: '',
                tasks: []),
          );
          final cat = catProvider.categoryFor(pid,
              fallbackCode: proj.code.isNotEmpty
                  ? proj.code
                  : proj.name
                      .split(' ')
                      .where((w) => w.isNotEmpty)
                      .take(3)
                      .map((w) => w[0].toUpperCase())
                      .join());
          final groupEntries = groups[pid]!;
          final total = groupEntries.fold<double>(
              0, (s, e) => s + (e.hours as double));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProjectGroupHeader(
                projectId: pid,
                projectName: proj.name,
                category: cat,
                entryCount: groupEntries.length,
                totalHours: total,
              ),
              const Divider(height: 1),
              const SizedBox(height: 6),
              for (final e in groupEntries) TimeEntryCard(entry: e),
            ],
          );
        }),
      ],
    ],
  );
}
```

Add the missing import for `HarvestProject` (already available via `AssignmentProvider` import) — confirm `project_assignment.dart` is imported:
```dart
import '../models/project_assignment.dart';
```

- [ ] **Step 4.7: Verify**

```bash
flutter analyze
```

Start dev server. Toggle the filter icon — the list should switch between flat and grouped-by-project views.

- [ ] **Step 4.8: Commit**

```bash
git checkout -b screen/recent-entries-grouping
git add lib/screens/recent_entries_screen.dart
git commit -m "feat: add group-by-project toggle to Recent Entries

Persists to SharedPreferences. Groups entries by project with colored
header showing code chip, project name, total hours, and entry count."
```

---

## Task 5: Emphasized Week Strip (PR `screen/recent-entries-week-strip`)

**Files:**
- Modify: `lib/screens/recent_entries_screen.dart`

- [ ] **Step 5.1: Add `emphasized` variant to `_WeekSummaryStrip`**

In `recent_entries_screen.dart`, add an `emphasized` parameter to `_WeekSummaryStrip`:

```dart
class _WeekSummaryStrip extends StatelessWidget {
  final DateTime selectedDate;
  final Map<String, double> weeklyTotals;
  final bool isLoading;
  final void Function(DateTime) onDayTap;
  final bool emphasized; // NEW

  const _WeekSummaryStrip({
    required this.selectedDate,
    required this.weeklyTotals,
    required this.isLoading,
    required this.onDayTap,
    this.emphasized = false, // NEW
  });
  // ... rest of existing fields
```

At the top of `_WeekSummaryStrip.build`, branch on `emphasized`:

```dart
@override
Widget build(BuildContext context) {
  final fmt = DateFormat('yyyy-MM-dd');
  final dayOfWeek = selectedDate.weekday; // 1=Mon, 7=Sun
  final monday = selectedDate.subtract(Duration(days: dayOfWeek - 1));
  final selectedStr = fmt.format(selectedDate);
  final today = DateTime.now();
  final todayStr = fmt.format(today);

  double weekTotal = 0;
  for (final v in weeklyTotals.values) weekTotal += v;

  final days = List.generate(7, (i) {
    final day = monday.add(Duration(days: i));
    final dayStr = fmt.format(day);
    return _DayData(
      date: day,
      iso: dayStr,
      abbr: _dayAbbrs[i],
      hours: weeklyTotals[dayStr] ?? 0,
      isSelected: dayStr == selectedStr,
      isFuture: day.isAfter(today) && dayStr != todayStr,
      isToday: dayStr == todayStr,
    );
  });

  if (emphasized) {
    return _buildEmphasized(context, days, weekTotal);
  }
  return _buildCompact(context, days, weekTotal);
}
```

Add the `_DayData` helper class inside the file (not inside the widget):

```dart
class _DayData {
  final DateTime date;
  final String iso;
  final String abbr;
  final double hours;
  final bool isSelected;
  final bool isFuture;
  final bool isToday;
  const _DayData({
    required this.date,
    required this.iso,
    required this.abbr,
    required this.hours,
    required this.isSelected,
    required this.isFuture,
    required this.isToday,
  });
}
```

- [ ] **Step 5.2: Add `_buildCompact` method (existing logic refactored)**

Replace the existing `build` body with `_buildCompact` (keep exact same UI):

```dart
Widget _buildCompact(
    BuildContext context, List<_DayData> days, double weekTotal) {
  final colorScheme = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        ...days.map((d) {
          final textColor = d.isSelected
              ? HarvestTokens.brand
              : d.isFuture
                  ? colorScheme.onSurface.withValues(alpha: 0.3)
                  : colorScheme.onSurfaceVariant;
          return Expanded(
            child: InkWell(
              onTap: d.isFuture ? null : () => onDayTap(d.date),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.abbr,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: textColor,
                          fontWeight: d.isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLoading ? '–' : _fmt(d.hours),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textColor,
                          fontWeight: d.isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                  ),
                ],
              ),
            ),
          );
        }),
        // Week total
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Week',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                isLoading ? '–' : _fmt(weekTotal),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 5.3: Add `_buildEmphasized` method**

```dart
Widget _buildEmphasized(
    BuildContext context, List<_DayData> days, double weekTotal) {
  final weeklyGoal =
      context.read<ProjectCategoryProvider>().weeklyGoalHours;
  const dailyGoal = 8.0; // existing daily goal constant

  return Container(
    decoration: BoxDecoration(
      color: HarvestTokens.surface2,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: HarvestTokens.border),
    ),
    padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
    child: Row(
      children: [
        ...days.map((d) {
          final textColor = d.isSelected
              ? HarvestTokens.brand600
              : d.isFuture
                  ? HarvestTokens.text4
                  : HarvestTokens.text;
          final labelColor = d.isSelected
              ? HarvestTokens.brand
              : d.isFuture
                  ? HarvestTokens.text4
                  : HarvestTokens.text3;
          final isOver = d.hours > dailyGoal;
          final progress =
              (d.hours / dailyGoal).clamp(0.0, 1.0);

          return Expanded(
            child: GestureDetector(
              onTap: d.isFuture ? null : () => onDayTap(d.date),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: d.isSelected
                      ? HarvestTokens.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: d.isSelected
                        ? HarvestTokens.brandTint2
                        : Colors.transparent,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.abbr.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d.date.day}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d.isFuture
                          ? '–'
                          : isLoading
                              ? '–'
                              : _fmt(d.hours),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            d.isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Progress tick
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: d.isFuture ? 0 : progress,
                          backgroundColor: HarvestTokens.surface3,
                          color: isOver
                              ? HarvestTokens.warn
                              : HarvestTokens.brand,
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        // Week total tile
        Container(
          width: 1,
          height: 60,
          color: HarvestTokens.border,
          margin: const EdgeInsets.symmetric(horizontal: 4),
        ),
        SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'WEEK',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: HarvestTokens.text2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isLoading ? '–' : _fmt(weekTotal),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: HarvestTokens.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'of ${weeklyGoal % 1 == 0 ? weeklyGoal.toInt() : weeklyGoal}h',
                style: const TextStyle(
                  fontSize: 11,
                  color: HarvestTokens.text3,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: weeklyGoal > 0
                        ? (weekTotal / weeklyGoal).clamp(0.0, 1.0)
                        : 0,
                    backgroundColor: HarvestTokens.surface3,
                    color: HarvestTokens.brand,
                    minHeight: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
```

Add the `_fmt` method to `_WeekSummaryStrip` (it already exists — confirm it's there or add):
```dart
String _fmt(double hours) {
  final total = (hours * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0 && m == 0) return '–';
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
```

- [ ] **Step 5.4: Wire `emphasized` to screen width**

In `_RecentEntriesScreenState.build`, replace the `_WeekSummaryStrip(...)` call with a `LayoutBuilder`:

```dart
LayoutBuilder(
  builder: (ctx, constraints) => _WeekSummaryStrip(
    selectedDate: provider.selectedDate,
    weeklyTotals: provider.weeklyTotals,
    isLoading: provider.isLoading,
    onDayTap: (date) { /* existing onDayTap logic */ },
    emphasized: constraints.maxWidth >= HarvestTokens.kWideBreakpoint,
  ),
),
```

Copy the existing `onDayTap` lambda exactly as-is from the current code into the new call.

Add import for `ProjectCategoryProvider` if not already present:
```dart
import '../providers/project_category_provider.dart';
```

- [ ] **Step 5.5: Verify**

```bash
flutter analyze
```

Start the dev server. On a narrow window (< 720px) the compact strip shows. Resize to > 720px — the emphasized card grid with day tiles and progress bars appears. The "Week" tile shows "of 40h" (default).

- [ ] **Step 5.6: Commit**

```bash
git checkout -b screen/recent-entries-week-strip
git add lib/screens/recent_entries_screen.dart
git commit -m "feat: emphasized week-strip on wide viewports (>=720dp)

Day tiles show weekday label, date number, hours, and 3px progress bar.
Week-total tile shows weekly hours vs configured goal (default 40h).
Compact strip unchanged on mobile."
```

---

## Task 6: Log Time Polish (PR `screen/log-time-polish`)

**Files:**
- Modify: `lib/screens/log_time_screen.dart`

- [ ] **Step 6.1: Add `HarvestTokens` import**

Add to the imports at the top:
```dart
import '../theme/harvest_tokens.dart';
```

- [ ] **Step 6.2: Replace the duration/start-end toggle with `SegmentedButton`**

Find the existing row that renders the toggle for `_useStartEndTime`. In the current code it appears as a `SwitchListTile` or `Row` with a `Switch`. Replace it with:

```dart
SegmentedButton<bool>(
  segments: const [
    ButtonSegment(
      value: false,
      label: Text('Duration'),
      icon: Icon(Icons.timer_outlined),
    ),
    ButtonSegment(
      value: true,
      label: Text('Start & End'),
      icon: Icon(Icons.access_time_outlined),
    ),
  ],
  selected: {_useStartEndTime},
  onSelectionChanged: (s) {
    final newVal = s.first;
    if (newVal && !_useStartEndTime) _initStartEndDefaults();
    setState(() => _useStartEndTime = newVal);
  },
  style: SegmentedButton.styleFrom(
    selectedBackgroundColor: HarvestTokens.brandTint,
    selectedForegroundColor: HarvestTokens.brand600,
  ),
),
```

- [ ] **Step 6.3: Make Project + Task selectors responsive**

Find the section of `log_time_screen.dart` that renders the `ProjectTaskSelector` or the two `DropdownButton`/`DropdownButtonFormField` widgets for project and task. Wrap them in a `LayoutBuilder` so they go side-by-side on wide screens:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final wide = constraints.maxWidth >= HarvestTokens.kWideBreakpoint;
    final projectField = _buildProjectDropdown(context);  // extract existing widget
    final taskField = _buildTaskDropdown(context);         // extract existing widget
    if (wide) {
      return Row(
        children: [
          Expanded(child: projectField),
          const SizedBox(width: 12),
          Expanded(child: taskField),
        ],
      );
    }
    return Column(
      children: [projectField, const SizedBox(height: 12), taskField],
    );
  },
),
```

If the project and task fields are currently inline (not in helper methods), extract them to `_buildProjectDropdown` and `_buildTaskDropdown` private methods that return the existing widget subtrees.

- [ ] **Step 6.4: Quiet the ADO section border when unchecked**

Find the `CheckboxListTile` or `Column` that wraps the ADO "Link Azure DevOps Work Item" section. Currently it likely has a visible `Container` with a border around the whole section. Remove the border container when `_hasAdoRef` is false — only show the checkbox row when unchecked:

```dart
// Before: a bordered Container always wrapping the ADO section
// After: no Container border; just the checkbox row when unchecked

Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    CheckboxListTile(
      value: _hasAdoRef,
      onChanged: (v) => setState(() => _hasAdoRef = v ?? false),
      title: const Text('Link Azure DevOps Work Item',
          style: TextStyle(fontWeight: FontWeight.w600)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      activeColor: HarvestTokens.brand,
    ),
    if (_hasAdoRef) ...[
      const SizedBox(height: 8),
      // ... instance picker and work item ID field (unchanged)
    ],
  ],
),
```

- [ ] **Step 6.5: Replace PAT indicator dots with 6px circles**

In the instance picker (the `SegmentedButton` or `Row` of `OutlinedButton`s / `FilterChip`s that pick the ADO instance), find where the "PAT configured" text or icon appears. Replace with a 6px green dot:

```dart
// Find existing PAT indicator (likely an Icon or Text) and replace:
Container(
  width: 6,
  height: 6,
  decoration: const BoxDecoration(
    shape: BoxShape.circle,
    color: HarvestTokens.success,
  ),
),
```

Remove any text label next to the dot.

- [ ] **Step 6.6: Verify**

```bash
flutter analyze
```

Start dev server. Open Log Time tab:
- SegmentedButton shows "Duration" and "Start & End" segments
- On wide viewport (>720px): project + task are side-by-side
- ADO section shows only the checkbox row when unchecked (no heavy border)
- PAT dots are 6px green circles

- [ ] **Step 6.7: Commit**

```bash
git checkout -b screen/log-time-polish
git add lib/screens/log_time_screen.dart
git commit -m "feat: polish Log Time — SegmentedButton, responsive layout, quiet ADO section

SegmentedButton replaces switch for Duration/Start-End toggle.
Project+Task fields go side-by-side on wide viewports.
ADO section has no border when unchecked; PAT dots are 6px circles."
```

---

## Task 7: Settings Polish (PR `screen/settings-polish`)

**Files:**
- Modify: `lib/screens/settings_screen.dart`

This is the largest modification. The existing settings form is reorganized into titled sections separated by `Divider`s. Work through each section in order.

- [ ] **Step 7.1: Add imports**

Add to imports:
```dart
import '../models/project_category.dart';
import '../providers/project_category_provider.dart';
import '../theme/harvest_tokens.dart';
```

- [ ] **Step 7.2: Add `_SectionHeader` helper widget**

Add this private widget near the top of the file (before the main screen class or as a top-level private class):

```dart
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: HarvestTokens.text,
              )),
        ),
        if (action != null) action!,
      ],
    );
  }
}
```

- [ ] **Step 7.3: Add Project Categories section**

In `_SettingsScreenState.build` (inside the form `Column`), add a "Project Categories" section. Place it after the "Default Project" section and before "Background Refresh":

```dart
const Divider(),
const SizedBox(height: 8),
_SectionHeader(title: 'Project Categories'),
const SizedBox(height: 12),
_buildProjectCategoriesSection(context),
```

Add the builder method:

```dart
Widget _buildProjectCategoriesSection(BuildContext context) {
  final assignmentProvider = context.watch<AssignmentProvider>();
  final catProvider = context.watch<ProjectCategoryProvider>();
  final projects = assignmentProvider.projects;

  if (projects.isEmpty) {
    return const Text('No projects loaded.',
        style: TextStyle(fontSize: 12, color: HarvestTokens.text3));
  }

  return Column(
    children: [
      for (final project in projects)
        _ProjectCategoryRow(project: project, catProvider: catProvider),
    ],
  );
}
```

Add the row widget:

```dart
class _ProjectCategoryRow extends StatelessWidget {
  final HarvestProject project;
  final ProjectCategoryProvider catProvider;

  const _ProjectCategoryRow({
    required this.project,
    required this.catProvider,
  });

  @override
  Widget build(BuildContext context) {
    final cat = catProvider.categoryFor(project.id,
        fallbackCode: project.code.isNotEmpty ? project.code : '?');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: cat.color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cat.tint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              cat.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cat.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: HarvestTokens.text)),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: HarvestTokens.text3,
            tooltip: 'Edit category',
            onPressed: () =>
                _showEditCategoryDialog(context, project, cat, catProvider),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCategoryDialog(
    BuildContext context,
    HarvestProject project,
    ProjectCategory current,
    ProjectCategoryProvider provider,
  ) async {
    final codeController = TextEditingController(text: current.code);
    Color selectedColor = current.color;
    Color selectedTint = current.tint;

    // 12-color palette matching ProjectCategoryProvider._palette
    final palette = [
      (const Color(0xFFFA5D24), const Color(0xFFFEE6DA)),
      (const Color(0xFF7C5CFF), const Color(0xFFEEE9FF)),
      (const Color(0xFF14B8A6), const Color(0xFFD7F5F0)),
      (const Color(0xFF8A837A), const Color(0xFFF1ECE3)),
      (const Color(0xFF2563EB), const Color(0xFFDCEAFD)),
      (const Color(0xFF16A34A), const Color(0xFFDCFCE7)),
      (const Color(0xFFC026D3), const Color(0xFFF5D0FE)),
      (const Color(0xFFD97706), const Color(0xFFFEF3C7)),
      (const Color(0xFFDC2626), const Color(0xFFFEE2E2)),
      (const Color(0xFF0891B2), const Color(0xFFCFFAFE)),
      (const Color(0xFF65A30D), const Color(0xFFECFCCB)),
      (const Color(0xFFDB2777), const Color(0xFFFCE7F3)),
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Edit category — ${project.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Color', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (c, t) in palette)
                    GestureDetector(
                      onTap: () => setDlgState(() {
                        selectedColor = c;
                        selectedTint = t;
                      }),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: selectedColor == c
                              ? Border.all(
                                  color: Colors.black, width: 2)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Code (3 letters)',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: codeController,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. TFN',
                  counterText: '',
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      await provider.setCategory(
        project.id,
        ProjectCategory(
          color: selectedColor,
          tint: selectedTint,
          code: codeController.text.trim().toUpperCase(),
        ),
      );
    }
  }
}
```

Add the missing import for `HarvestProject`:
```dart
import '../models/project_assignment.dart';
```

- [ ] **Step 7.4: Add Weekly Goal field**

After the Project Categories section (and its divider), add:

```dart
const Divider(),
const SizedBox(height: 8),
_SectionHeader(title: 'Weekly Goal'),
const SizedBox(height: 12),
_buildWeeklyGoalField(context),
```

Add the builder method to `_SettingsScreenState`:

```dart
Widget _buildWeeklyGoalField(BuildContext context) {
  final catProvider = context.watch<ProjectCategoryProvider>();
  // Use a local controller initialized from provider value
  return Row(
    children: [
      Expanded(
        child: TextFormField(
          initialValue:
              catProvider.weeklyGoalHours == catProvider.weeklyGoalHours.truncate()
                  ? catProvider.weeklyGoalHours.toInt().toString()
                  : catProvider.weeklyGoalHours.toString(),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Weekly goal hours',
            border: OutlineInputBorder(),
            suffixText: 'h',
          ),
          onChanged: (v) {
            final hours = double.tryParse(v);
            if (hours != null && hours > 0) {
              context.read<ProjectCategoryProvider>().setWeeklyGoal(hours);
            }
          },
        ),
      ),
    ],
  );
}
```

Add extension at bottom of file:
```dart
extension on double {
  double get truncate => floorToDouble();
}
```

- [ ] **Step 7.5: Update ADO instance rows**

Find the existing `_AdoInstanceList` / `ListTile` rows for ADO instances and update to show the new two-line format. Replace the `ListTile` for each instance with:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: HarvestTokens.surface3,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.link, size: 16, color: HarvestTokens.text2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(instance.label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      instance.baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: HarvestTokens.text3),
                    ),
                  ),
                  if (instance.pat != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: HarvestTokens.success,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 15),
          color: HarvestTokens.text2,
          onPressed: () => onEdit(i, instance),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 15),
          color: HarvestTokens.error,
          onPressed: () => /* existing delete logic */,
        ),
      ],
    ),
    // Line 2: GUID status
    Padding(
      padding: const EdgeInsets.only(left: 42, top: 4, bottom: 8),
      child: Row(
        children: [
          Icon(
            guid != null ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            size: 13,
            color: guid != null ? HarvestTokens.success : HarvestTokens.warn,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              guid ?? 'Harvest GUID not yet learned',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: guid != null ? 'monospace' : null,
                fontSize: 11,
                color: guid != null ? HarvestTokens.text3 : HarvestTokens.warn,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 13),
            color: HarvestTokens.brand600,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () =>
                _showEditGuidDialog(context, instance, guid),
          ),
        ],
      ),
    ),
  ],
),
```

- [ ] **Step 7.6: Reorder Actions section**

Find the existing action buttons (Save & Reload, Clear Cache, Migrate ADO References, Reset to Defaults) and ensure they appear in this order, after a `Divider`:

```dart
const Divider(),
const SizedBox(height: 8),
FilledButton.icon(
  onPressed: _saveAndReload,
  icon: const Icon(Icons.save_outlined),
  label: const Text('Save & Reload'),
  style: FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
    backgroundColor: HarvestTokens.brand,
  ),
),
const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: _clearCache,
  icon: const Icon(Icons.refresh),
  label: const Text('Clear Cache & Refresh'),
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(44),
  ),
),
const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: _migrateAdoReferences,
  icon: const Icon(Icons.link),
  label: const Text('Migrate ADO References'),
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(44),
  ),
),
const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: _resetToDefaults,
  icon: const Icon(Icons.restart_alt),
  label: const Text('Reset to Defaults'),
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(44),
  ),
),
const SizedBox(height: 12),
const Text(
  'Settings are stored in browser localStorage.',
  textAlign: TextAlign.center,
  style: TextStyle(fontSize: 11, color: HarvestTokens.text3),
),
```

Keep the existing `_saveAndReload`, `_clearCache`, `_migrateAdoReferences`, `_resetToDefaults` method implementations unchanged — only the button widget layout changes.

- [ ] **Step 7.7: Verify**

```bash
flutter analyze
```

Start dev server. Open Settings:
- Sections are separated by dividers with bold titles
- "Project Categories" section shows one row per loaded project with color swatch, code chip, edit button
- "Weekly Goal" shows a number field
- ADO instance rows show two lines: label + PAT dot on line 1; GUID status on line 2
- Actions are in order: Save (filled) → Clear Cache → Migrate → Reset (outlined)

- [ ] **Step 7.8: Commit**

```bash
git checkout -b screen/settings-polish
git add lib/screens/settings_screen.dart
git commit -m "feat: reorganize Settings into titled sections with ADO row v2

Sections: Credentials, Default Project, Background Refresh, Project
Categories (editable), Weekly Goal, ADO Instances, Actions.
ADO rows: two-line format with GUID status. Actions reordered."
```

---

## Task 8: Edit Time Context Banner (PR `screen/edit-time-context-banner`)

**Files:**
- Modify: `lib/screens/edit_time_screen.dart`

- [ ] **Step 8.1: Add imports**

```dart
import '../theme/harvest_tokens.dart';
import '../widgets/duration_pill.dart';
```

- [ ] **Step 8.2: Add the context banner**

In `_EditTimeScreenState.build`, after the `AppBar` is placed (in the `Scaffold` body), insert the banner as the first child of the `Column`/`ListView` that contains the form. Add it before the first form field:

```dart
// Context banner
Container(
  margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  decoration: BoxDecoration(
    color: HarvestTokens.brandTint,
    border: Border.all(color: HarvestTokens.brandTint2),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(
    children: [
      DurationPill(hours: widget.entry.hours, size: 32),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EDITING ENTRY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: HarvestTokens.brand600,
              ),
            ),
            Text(
              '#${widget.entry.id} · ${DateFormat('EEE d MMM yyyy').format(_selectedDate)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HarvestTokens.text,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
),
```

`DateFormat` is already imported via `package:intl/intl.dart`.

- [ ] **Step 8.3: Verify**

```bash
flutter analyze
```

Open an entry's Edit screen — the orange tinted banner should appear at the top showing the duration pill, "EDITING ENTRY" label, and the entry ID + date.

- [ ] **Step 8.4: Commit**

```bash
git checkout -b screen/edit-time-context-banner
git add lib/screens/edit_time_screen.dart
git commit -m "feat: add orange context banner to Edit Time screen

Shows DurationPill + entry ID + date at top of the edit form,
using brandTint background and brandTint2 border."
```

---

## Task 9: Responsive Shell (PR `screen/responsive-shell`)

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 9.1: Add `HarvestTokens` import**

```dart
import '../theme/harvest_tokens.dart';
```

- [ ] **Step 9.2: Replace the `Scaffold` with a responsive shell**

Replace the entire `_HomeScreenState.build` method:

```dart
@override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= HarvestTokens.kWideBreakpoint;

      if (wide) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType: NavigationRailLabelType.all,
                indicatorColor: HarvestTokens.brandTint,
                selectedIconTheme:
                    const IconThemeData(color: HarvestTokens.brand),
                selectedLabelTextStyle:
                    const TextStyle(color: HarvestTokens.brand, fontWeight: FontWeight.w600),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.list_alt_outlined),
                    selectedIcon: Icon(Icons.list_alt),
                    label: Text('Recent'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.add_circle_outline),
                    selectedIcon: Icon(Icons.add_circle),
                    label: Text('Log Time'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: Text('Settings'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    AppBar(
                      title: const Text('Harvest Tracker 2.0'),
                      backgroundColor: HarvestTokens.brand,
                      foregroundColor: Colors.white,
                      elevation: 2,
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _screens[_tab],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      // Mobile: existing layout unchanged
      return Scaffold(
        appBar: AppBar(
          title: const Text('Harvest Tracker 2.0'),
          backgroundColor: HarvestTokens.brand,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _screens[_tab],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: _destinations,
        ),
      );
    },
  );
}
```

- [ ] **Step 9.3: Verify**

```bash
flutter analyze
```

Start dev server. On a narrow window (< 720px): bottom nav is visible, AppBar at top. Resize to > 720px: left NavigationRail appears with icons + labels, bottom nav is gone. Tab switching works in both modes.

- [ ] **Step 9.4: Commit**

```bash
git checkout -b screen/responsive-shell
git add lib/screens/home_screen.dart
git commit -m "feat: responsive shell — NavigationRail on wide viewports (>=720dp)

LayoutBuilder switches between bottom NavigationBar (mobile) and
NavigationRail (tablet/desktop) at 720dp. Tab state is shared.
No routing changes."
```

---

## Self-Review Checklist

- [x] All 9 PRs from the spec have tasks
- [x] `HarvestTokens.kWideBreakpoint` used consistently in tasks 5, 6, 9
- [x] `ProjectCategoryProvider.categoryFor` signature consistent across tasks 2, 3, 4, 7
- [x] `DurationPill` created in task 3, reused in task 8 — import path consistent
- [x] `WorkItemChip` uses `AdoWorkItem.createdByName` (not `.assignedTo` — field doesn't exist)
- [x] No density toggle (dropped for MVP, as decided in brainstorming)
- [x] `weeklyGoalHours` owned by `ProjectCategoryProvider`, read in task 5 week strip
- [x] No API or model shape changes
- [x] `work_item_preview.dart` unchanged
