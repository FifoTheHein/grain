import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

Future<void> _showEditGuidDialog(
    BuildContext context, AdoInstance instance, String? currentGuid) async {
  final controller = TextEditingController(text: currentGuid ?? '');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Harvest GUID — ${instance.label}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Normally learned automatically from a native Harvest entry. '
            'Set manually if auto-detection has not worked.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Harvest Connection GUID',
              border: OutlineInputBorder(),
              hintText: '4b6afb17-0252-4bf2-b64a-cf7227b6f0d6',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
  );

  if (confirmed == true && context.mounted) {
    final guid = controller.text.trim();
    if (guid.isNotEmpty) {
      await context.read<AdoService>().setHarvestGuid(instance.label, guid);
    }
  }
}

class _AdoInstanceList extends StatelessWidget {
  final void Function(int index, AdoInstance instance) onEdit;

  const _AdoInstanceList({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdoInstanceProvider>();
    final adoService = context.watch<AdoService>();

    if (provider.instances.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No instances configured.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: [
        ...provider.instances.asMap().entries.map((entry) {
          final i = entry.key;
          final instance = entry.value;
          final guid = adoService.getCachedHarvestGuid(instance.label);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(instance.label),
                subtitle: Text(
                  instance.pat != null
                      ? '${instance.baseUrl}  •  PAT configured'
                      : instance.baseUrl,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                contentPadding: EdgeInsets.zero,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit',
                      onPressed: () => onEdit(i, instance),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Remove',
                      onPressed: () =>
                          context.read<AdoInstanceProvider>().remove(i),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 40, right: 8, bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      guid != null
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_outlined,
                      size: 13,
                      color: guid != null ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        guid ?? 'Harvest GUID not yet learned',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: guid != null
                              ? Theme.of(context).textTheme.bodySmall?.color
                              : Colors.orange,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () =>
                          _showEditGuidDialog(context, instance, guid),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => context.read<AdoInstanceProvider>().resetToDefaults(),
          icon: const Icon(Icons.restore, size: 16),
          label: const Text('Reset to Defaults'),
          style: OutlinedButton.styleFrom(
            textStyle: Theme.of(context).textTheme.bodySmall,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
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

class _SettingsScreenState extends State<SettingsScreen> {
  final _tokenController = TextEditingController();
  final _accountIdController = TextEditingController();
  bool _obscureToken = true;
  int? _defaultProjectId;
  int? _defaultTaskId;
  int _autoRefreshIntervalMinutes = 15;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _accountIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _tokenController.text =
          prefs.getString('harvest_token') ?? AppConfig.defaultToken;
      _accountIdController.text =
          prefs.getString('harvest_account_id') ?? AppConfig.defaultAccountId;
      _defaultProjectId = prefs.getInt('default_project_id');
      _defaultTaskId = prefs.getInt('default_task_id');
      _autoRefreshIntervalMinutes =
          prefs.getInt('auto_refresh_interval_minutes') ?? 15;
    });
  }

  Future<void> _save(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('harvest_token', _tokenController.text.trim());
    await prefs.setString(
        'harvest_account_id', _accountIdController.text.trim());
    if (_defaultProjectId != null) {
      await prefs.setInt('default_project_id', _defaultProjectId!);
    } else {
      await prefs.remove('default_project_id');
    }
    if (_defaultTaskId != null) {
      await prefs.setInt('default_task_id', _defaultTaskId!);
    } else {
      await prefs.remove('default_task_id');
    }

    if (!context.mounted) return;

    // Reload data with new credentials and apply new refresh interval
    context.read<AssignmentProvider>().load();
    context.read<TimeEntryProvider>().loadRecentEntries();
    context
        .read<TimeEntryProvider>()
        .setRefreshInterval(_autoRefreshIntervalMinutes);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved — reloading data'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _showAdoDialog(BuildContext context,
      {int? index, AdoInstance? existing}) async {
    final labelController =
        TextEditingController(text: existing?.label ?? '');
    final urlController =
        TextEditingController(text: existing?.baseUrl ?? '');
    final patController =
        TextEditingController(text: existing?.pat ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          bool obscurePat = true;
          return AlertDialog(
            title: Text(
                existing == null ? 'Add ADO Instance' : 'Edit ADO Instance'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      border: OutlineInputBorder(),
                      hintText: 'Transport',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: 'Project URL',
                      border: OutlineInputBorder(),
                      hintText: 'https://dev.azure.com/org/project',
                      helperText:
                          '/_workitems/edit/{id} is appended automatically',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  StatefulBuilder(
                    builder: (_, setPATState) => TextFormField(
                      controller: patController,
                      obscureText: obscurePat,
                      decoration: InputDecoration(
                        labelText: 'Personal Access Token (PAT)',
                        border: const OutlineInputBorder(),
                        helperText: 'Needs Read access to Work Items',
                        suffixIcon: IconButton(
                          icon: Icon(obscurePat
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setPATState(() => obscurePat = !obscurePat),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx2, true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    final labelText = labelController.text.trim();
    final urlText = urlController.text.trim();
    final patText = patController.text.trim();

    if (confirmed == true && context.mounted) {
      final instance = AdoInstance(
        label: labelText,
        baseUrl: urlText,
        pat: patText.isEmpty ? null : patText,
      );
      final provider = context.read<AdoInstanceProvider>();
      if (index == null) {
        provider.add(instance);
      } else {
        provider.update(index, instance);
      }
    }
  }

  Future<void> _reset(BuildContext context) async {
    final timeEntryProvider = context.read<TimeEntryProvider>();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('harvest_token');
    await prefs.remove('harvest_account_id');
    await prefs.remove('default_project_id');
    await prefs.remove('default_task_id');
    await prefs.remove('auto_refresh_interval_minutes');
    timeEntryProvider.setRefreshInterval(15);
    if (!mounted) return;
    setState(() {
      _tokenController.text = AppConfig.defaultToken;
      _accountIdController.text = AppConfig.defaultAccountId;
      _defaultProjectId = null;
      _defaultTaskId = null;
      _autoRefreshIntervalMinutes = 15;
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to defaults')),
    );
  }

  Future<void> _migrateAdoReferences(BuildContext context) async {
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

  Future<void> _clearCache(BuildContext context) async {
    context.read<TimeEntryProvider>().entries.clear();
    await context.read<TimeEntryProvider>().loadRecentEntries();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache cleared — refreshed time entries'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Harvest Credentials',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            obscureText: _obscureToken,
            decoration: InputDecoration(
              labelText: 'API Token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureToken ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _accountIdController,
            decoration: const InputDecoration(
              labelText: 'Account ID',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          const Divider(),
          Text(
            'Default Project',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _DefaultProjectDropdown(
            selectedId: _defaultProjectId,
            onChanged: (id) => setState(() {
              _defaultProjectId = id;
              _defaultTaskId = null; // reset task when project changes
            }),
          ),
          if (_defaultProjectId != null) ...[
            const SizedBox(height: 12),
            _DefaultTaskDropdown(
              projectId: _defaultProjectId!,
              selectedTaskId: _defaultTaskId,
              onChanged: (id) => setState(() => _defaultTaskId = id),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Pre-selected on the Log Time screen when the app loads.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const Divider(),
          Text(
            'Background Refresh',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Refresh interval',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _autoRefreshIntervalMinutes,
                isDense: true,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 5,  child: Text('Every 5 minutes')),
                  DropdownMenuItem(value: 15, child: Text('Every 15 minutes')),
                  DropdownMenuItem(value: 30, child: Text('Every 30 minutes')),
                  DropdownMenuItem(value: 60, child: Text('Every hour')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _autoRefreshIntervalMinutes = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Silently re-fetches the current week in the background. Takes effect after Save.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Azure DevOps Instances',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: () => _showAdoDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _AdoInstanceList(onEdit: (i, instance) => _showAdoDialog(context, index: i, existing: instance)),
          const SizedBox(height: 8),
          Text(
            'User ID: ${AppConfig.userId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const Divider(),
          FilledButton.icon(
            onPressed: () => _save(context),
            icon: const Icon(Icons.save),
            label: const Text('Save & Reload'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _clearCache(context),
            icon: const Icon(Icons.refresh),
            label: const Text('Clear Cache & Refresh'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _migrateAdoReferences(context),
            icon: const Icon(Icons.sync),
            label: const Text('Migrate ADO References'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _reset(context),
            icon: const Icon(Icons.restore),
            label: const Text('Reset to Defaults'),
          ),
          const SizedBox(height: 8),
          Text(
            'Settings are stored in browser localStorage.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
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
