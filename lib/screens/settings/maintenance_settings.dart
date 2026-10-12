import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/ado_instance_provider.dart';
import '../../providers/assignment_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../services/ado_service.dart';
import '../../theme/harvest_tokens.dart';
import 'settings_shared.dart';

/// One-off fixes and resets, kept out of the way of everyday settings.
class MaintenanceSettingsPage extends StatelessWidget {
  const MaintenanceSettingsPage({super.key});

  Future<void> _clearCache(BuildContext context) async {
    context.read<TimeEntryProvider>().entries.clear();
    await context.read<TimeEntryProvider>().loadRecentEntries();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache cleared — refreshed time entries'),
        backgroundColor: HarvestTokens.success,
      ),
    );
  }

  void _migrateAdoReferences(BuildContext context) {
    final entryProvider = context.read<TimeEntryProvider>();
    final adoService = context.read<AdoService>();
    final instances = context.read<AdoInstanceProvider>().instances;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MigrationProgressDialog(
        stream: entryProvider.migrateAdoReferences(adoService, instances),
      ),
    );
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to defaults?'),
        content: const Text(
          'Restores the Harvest credentials from the built-in config, clears '
          'the Log Time default project, sets the refresh interval back to 15 '
          'minutes and turns Completed Work updates back on.\n\n'
          'Rules, templates, ADO instances, calendar and appearance settings '
          'are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HarvestTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final timeEntryProvider = context.read<TimeEntryProvider>();
    final assignments = context.read<AssignmentProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'harvest_token',
      'harvest_account_id',
      'default_project_id',
      'default_task_id',
      'auto_refresh_interval_minutes',
      'ado_update_completed_work',
    ]) {
      await prefs.remove(key);
    }
    await timeEntryProvider.setRefreshInterval(15);
    assignments.load();
    timeEntryProvider.loadRecentEntries();
    messenger.showSnackBar(const SnackBar(content: Text('Reset to defaults')));
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return SettingsPageBody(children: [
      _MaintenanceAction(
        icon: Icons.refresh,
        title: 'Clear cache & refresh',
        description: 'Drops the loaded entries and fetches them again.',
        onPressed: () => _clearCache(context),
      ),
      _MaintenanceAction(
        icon: Icons.link,
        title: 'Migrate ADO references',
        description: 'Rewrites this week\'s work item links into the '
            'composite format Harvest\'s own ADO integration uses.',
        onPressed: () => _migrateAdoReferences(context),
      ),
      _MaintenanceAction(
        icon: Icons.restart_alt,
        title: 'Reset to defaults',
        description: 'Credentials, Log Time default, refresh interval and '
            'Completed Work. Asks first.',
        destructive: true,
        onPressed: () => _reset(context),
      ),
      const SizedBox(height: 16),
      Text(
        kIsWeb
            ? 'Settings are stored in this browser.'
            : 'Settings are stored on this device.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: palette.text3),
      ),
    ]);
  }
}

class _MaintenanceAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool destructive;
  final VoidCallback onPressed;

  const _MaintenanceAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final color = destructive ? HarvestTokens.error : palette.text;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: destructive ? HarvestTokens.error : palette.text2),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: Text(description),
      onTap: onPressed,
    );
  }
}

class _MigrationProgressDialog extends StatefulWidget {
  final Stream<({int done, int total, int failed})> stream;

  const _MigrationProgressDialog({required this.stream});

  @override
  State<_MigrationProgressDialog> createState() =>
      _MigrationProgressDialogState();
}

class _MigrationProgressDialogState extends State<_MigrationProgressDialog> {
  int done = 0;
  int total = 0;
  int failed = 0;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    widget.stream.listen(
      (progress) {
        if (mounted) {
          setState(() {
            done = progress.done;
            total = progress.total;
            failed = progress.failed;
            finished = progress.total > 0 && progress.done == progress.total;
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            finished = true;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Migrating ADO References'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!finished)
            LinearProgressIndicator(
              value: total == 0 ? null : done / total,
            ),
          const SizedBox(height: 12),
          Text(
            !finished && total == 0
                ? 'Starting...'
                : finished && total == 0
                    ? 'No entries needed migration'
                    : finished
                        ? 'Done: ${total - failed} updated, $failed failed'
                        : '$done / $total',
          ),
        ],
      ),
      actions: finished
          ? [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ]
          : [],
    );
  }
}
