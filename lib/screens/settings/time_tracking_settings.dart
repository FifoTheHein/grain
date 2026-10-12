import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/assignment_provider.dart';
import '../../providers/project_category_provider.dart';
import '../../widgets/quick_template_editor.dart';
import 'settings_shared.dart';

/// What Log Time starts with, the goals the progress bars measure against, and
/// the one-tap templates.
class TimeTrackingSettingsPage extends StatefulWidget {
  const TimeTrackingSettingsPage({super.key});

  @override
  State<TimeTrackingSettingsPage> createState() =>
      _TimeTrackingSettingsPageState();
}

class _TimeTrackingSettingsPageState extends State<TimeTrackingSettingsPage> {
  static const _projectKey = 'default_project_id';
  static const _taskKey = 'default_task_id';

  int? _defaultProjectId;
  int? _defaultTaskId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _defaultProjectId = prefs.getInt(_projectKey);
      _defaultTaskId = prefs.getInt(_taskKey);
    });
  }

  /// Saved as soon as it is picked; Log Time reads it on its next load.
  Future<void> _setDefault(int? projectId, int? taskId) async {
    setState(() {
      _defaultProjectId = projectId;
      _defaultTaskId = taskId;
    });
    final prefs = await SharedPreferences.getInstance();
    if (projectId == null) {
      await prefs.remove(_projectKey);
    } else {
      await prefs.setInt(_projectKey, projectId);
    }
    if (taskId == null) {
      await prefs.remove(_taskKey);
    } else {
      await prefs.setInt(_taskKey, taskId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageBody(children: [
      const SettingsSectionHeader(title: 'Log Time Default'),
      const SizedBox(height: 12),
      _DefaultProjectDropdown(
        selectedId: _defaultProjectId,
        onChanged: (id) => _setDefault(id, null),
      ),
      if (_defaultProjectId != null) ...[
        const SizedBox(height: 12),
        _DefaultTaskDropdown(
          projectId: _defaultProjectId!,
          selectedTaskId: _defaultTaskId,
          onChanged: (id) => _setDefault(_defaultProjectId, id),
        ),
      ],
      const SettingsHint(
          'Pre-selected on the Log Time screen when the app loads.'),
      const SettingsSectionDivider(),
      const SettingsSectionHeader(title: 'Goals & Work Day'),
      const SizedBox(height: 12),
      _buildWeeklyGoalField(context),
      const SizedBox(height: 4),
      _buildWorkDaySection(context),
      const SettingsSectionDivider(),
      SettingsSectionHeader(
        title: 'Quick Templates',
        action: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          onPressed: () => showQuickTemplateDialog(context),
        ),
      ),
      const SizedBox(height: 4),
      const QuickTemplateList(),
    ]);
  }

  Widget _buildWeeklyGoalField(BuildContext context) {
    final catProvider = context.watch<ProjectCategoryProvider>();
    final goal = catProvider.weeklyGoalHours;
    final initialValue =
        goal == goal.truncateToDouble() ? goal.toInt().toString() : '$goal';

    return TextFormField(
      key: ValueKey(initialValue),
      initialValue: initialValue,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Weekly goal',
        border: OutlineInputBorder(),
        suffixText: 'h',
      ),
      onChanged: (v) {
        final hours = double.tryParse(v);
        if (hours != null && hours > 0) {
          context.read<ProjectCategoryProvider>().setWeeklyGoal(hours);
        }
      },
    );
  }

  Widget _buildWorkDaySection(BuildContext context) {
    final provider = context.watch<ProjectCategoryProvider>();
    final start = provider.workDayStart;
    final end = provider.workDayEnd;
    final breakH = provider.breakHours;
    final daily = provider.dailyGoalHours;
    final dailyLabel = daily == daily.truncateToDouble()
        ? '${daily.toInt()}h work day'
        : '${daily.toStringAsFixed(1)}h work day';
    final breakInitial = breakH == breakH.truncateToDouble()
        ? breakH.toInt().toString()
        : '$breakH';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start time'),
                trailing: Text(
                  start.format(context),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: start,
                  );
                  if (picked != null && context.mounted) {
                    context.read<ProjectCategoryProvider>().setWorkDayStart(picked);
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('End time'),
                trailing: Text(
                  end.format(context),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: end,
                  );
                  if (picked != null && context.mounted) {
                    context.read<ProjectCategoryProvider>().setWorkDayEnd(picked);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey(breakInitial),
                initialValue: breakInitial,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Break hours',
                  border: OutlineInputBorder(),
                  suffixText: 'h',
                ),
                onChanged: (v) {
                  final hours = double.tryParse(v);
                  if (hours != null && hours >= 0) {
                    context.read<ProjectCategoryProvider>().setBreakHours(hours);
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '= $dailyLabel',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: provider.minGapMinutes,
          decoration: const InputDecoration(
            labelText: 'Report gaps of at least',
            border: OutlineInputBorder(),
            helperText: 'Used by the Insights screen',
          ),
          items: const [5, 10, 15, 30, 60]
              .map((m) => DropdownMenuItem(value: m, child: Text('$m minutes')))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              context.read<ProjectCategoryProvider>().setMinGapMinutes(v);
            }
          },
        ),
      ],
    );
  }
}

class _DefaultProjectDropdown extends StatelessWidget {
  final int? selectedId;
  final void Function(int?) onChanged;

  const _DefaultProjectDropdown({
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssignmentProvider>();

    if (provider.isLoading) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.projects.isEmpty) {
      return const Text('No projects loaded yet.');
    }

    final items = [
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('— None (use first project) —'),
      ),
      ...provider.projects.map((p) => DropdownMenuItem<int?>(
            value: p.id,
            child: Text(p.code.isNotEmpty ? '${p.code} — ${p.name}' : p.name),
          )),
    ];

    // Ensure selectedId is valid — null if it no longer exists in projects
    final validId = provider.projects.any((p) => p.id == selectedId)
        ? selectedId
        : null;

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Default Project',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: validId,
          isDense: true,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DefaultTaskDropdown extends StatelessWidget {
  final int projectId;
  final int? selectedTaskId;
  final void Function(int?) onChanged;

  const _DefaultTaskDropdown({
    required this.projectId,
    required this.selectedTaskId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssignmentProvider>();
    final project = provider.projects.where((p) => p.id == projectId).firstOrNull;

    if (project == null || project.tasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final validTaskId =
        project.tasks.any((t) => t.id == selectedTaskId) ? selectedTaskId : null;

    final items = [
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('— None (use first task) —'),
      ),
      ...project.tasks.map((t) => DropdownMenuItem<int?>(
            value: t.id,
            child: Text(t.name),
          )),
    ];

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Default Task',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: validTaskId,
          isDense: true,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
