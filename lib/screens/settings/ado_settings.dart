import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/time_entry.dart';
import '../../providers/ado_instance_provider.dart';
import '../../services/ado_service.dart';
import '../../theme/harvest_tokens.dart';
import '../../widgets/mapping_rule_editor.dart';
import 'settings_shared.dart';

/// The ADO instances Grain links work items in, whether logging time updates
/// Completed Work, and the rules that pick a project from a work item.
class AdoSettingsPage extends StatefulWidget {
  const AdoSettingsPage({super.key});

  @override
  State<AdoSettingsPage> createState() => _AdoSettingsPageState();
}

class _AdoSettingsPageState extends State<AdoSettingsPage> {
  static const _completedWorkKey = 'ado_update_completed_work';
  bool _updateCompletedWork = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _updateCompletedWork =
            prefs.getBool(_completedWorkKey) ?? true);
      }
    });
  }

  Future<void> _setUpdateCompletedWork(bool value) async {
    setState(() => _updateCompletedWork = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedWorkKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return SettingsPageBody(children: [
      SettingsSectionHeader(
        title: 'Instances',
        action: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          onPressed: () => showAdoInstanceDialog(context),
        ),
      ),
      const SizedBox(height: 4),
      _AdoInstanceList(
          onEdit: (i, instance) =>
              showAdoInstanceDialog(context, index: i, existing: instance)),
      const SizedBox(height: 4),
      SwitchListTile(
        value: _updateCompletedWork,
        onChanged: _setUpdateCompletedWork,
        title: const Text('Update Completed Work when logging time'),
        subtitle: const Text(
            'Adds logged hours to the work item\'s Completed Work field'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        activeThumbColor: palette.brand,
      ),
      const SettingsSectionDivider(),
      SettingsSectionHeader(
        title: 'Work Item Rules',
        action: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          onPressed: () => showMappingRuleDialog(context),
        ),
      ),
      const SizedBox(height: 4),
      MappingRuleList(),
    ]);
  }
}

Future<void> showAdoInstanceDialog(BuildContext context,
    {int? index, AdoInstance? existing}) async {
  final labelController = TextEditingController(text: existing?.label ?? '');
  final urlController = TextEditingController(text: existing?.baseUrl ?? '');
  final patController = TextEditingController(text: existing?.pat ?? '');
  final formKey = GlobalKey<FormState>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDialogState) {
        bool obscurePat = true;
        return AlertDialog(
          title:
              Text(existing == null ? 'Add ADO Instance' : 'Edit ADO Instance'),
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
                    helperText: '/_workitems/edit/{id} is appended automatically',
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
    final palette = HarvestTokens.of(context);
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
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: palette.surface3,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.link, size: 16, color: palette.text2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          instance.label,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                instance.baseUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: palette.text3),
                              ),
                            ),
                            if (instance.pat != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 6,
                                height: 6,
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
                    color: palette.text2,
                    tooltip: 'Edit',
                    onPressed: () => onEdit(i, instance),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 15),
                    color: HarvestTokens.error,
                    tooltip: 'Remove',
                    onPressed: () =>
                        context.read<AdoInstanceProvider>().remove(i),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 42, top: 4, bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      guid != null
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_outlined,
                      size: 13,
                      color: guid != null
                          ? HarvestTokens.success
                          : HarvestTokens.warn,
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
                          color: guid != null
                              ? palette.text3
                              : HarvestTokens.warn,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 13),
                      color: palette.brand600,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () =>
                          _showEditGuidDialog(context, instance, guid),
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
          label: const Text('Reset instances to defaults'),
          style: OutlinedButton.styleFrom(
            textStyle: Theme.of(context).textTheme.bodySmall,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }
}
