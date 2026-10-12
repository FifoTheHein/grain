import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/calendar_import_provider.dart';
import '../services/meeting_importer.dart';
import '../theme/harvest_tokens.dart';
import 'pending_meetings_sheet.dart';

/// The Calendar Import section of Settings. Changes apply immediately, like the
/// rule lists, rather than waiting for Save & Reload.
class CalendarImportSettings extends StatefulWidget {
  const CalendarImportSettings({super.key});

  @override
  State<CalendarImportSettings> createState() => _CalendarImportSettingsState();
}

class _CalendarImportSettingsState extends State<CalendarImportSettings> {
  late final TextEditingController _urlController;
  bool _obscureUrl = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
        text: context.read<CalendarImportProvider>().icsUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _upload(BuildContext context) async {
    final provider = context.read<CalendarImportProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ics'],
      withData: true,
    );
    final bytes = picked?.files.singleOrNull?.bytes;
    if (bytes == null) return;
    final result =
        await provider.sync(icsText: utf8.decode(bytes, allowMalformed: true));
    if (!context.mounted) return;
    _report(context, messenger, provider, result);
  }

  Future<void> _syncNow(BuildContext context) async {
    final provider = context.read<CalendarImportProvider>();
    final messenger = ScaffoldMessenger.of(context);
    await provider.setIcsUrl(_urlController.text);
    final result = await provider.sync();
    if (!context.mounted) return;
    _report(context, messenger, provider, result);
  }

  void _report(BuildContext context, ScaffoldMessengerState messenger,
      CalendarImportProvider provider, MeetingImportResult? result) {
    messenger.showSnackBar(SnackBar(
      content: Text(result == null
          ? (provider.error ?? 'Calendar import did not run')
          : describeImport(result)),
      backgroundColor: result == null || result.failed.isNotEmpty
          ? HarvestTokens.error
          : HarvestTokens.success,
    ));
    if (result != null && result.pending.isNotEmpty) {
      showPendingMeetingsSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final provider = context.watch<CalendarImportProvider>();
    final projects = context.watch<AssignmentProvider>().projects;
    final adoInstances = context
        .watch<AdoInstanceProvider>()
        .instances
        .where((i) => i.pat?.isNotEmpty ?? false)
        .toList();
    final canFetch = CalendarImportProvider.canFetchUrl;
    final project =
        projects.firstWhereOrNull((p) => p.id == provider.defaultProjectId);
    final taskId = project?.tasks
        .firstWhereOrNull((t) => t.id == provider.defaultTaskId)
        ?.id;
    final since = provider.importSince;
    final small = TextStyle(fontSize: 12, color: palette.text3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Logs finished meetings from your published calendar to Harvest, '
          'skipping declined, cancelled, free and private ones.',
          style: small,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _urlController,
          obscureText: _obscureUrl,
          decoration: InputDecoration(
            labelText: 'ICS calendar URL',
            border: const OutlineInputBorder(),
            helperText: canFetch
                ? 'Outlook → Settings → Calendar → Shared calendars → Publish'
                : 'Browsers cannot read this feed (no CORS). It is used by '
                    'the Android app — here, upload an .ics file instead.',
            helperMaxLines: 3,
            suffixIcon: IconButton(
              icon: Icon(_obscureUrl ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureUrl = !_obscureUrl),
            ),
          ),
          onSubmitted: provider.setIcsUrl,
          onTapOutside: (_) {
            if (_urlController.text.trim() != provider.icsUrl) {
              provider.setIcsUrl(_urlController.text);
            }
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: provider.autoLog,
          onChanged: canFetch ? provider.setAutoLog : null,
          title: const Text('Log meetings automatically'),
          subtitle: Text(canFetch
              ? 'Runs whenever entries refresh'
              : 'Android only — use Upload .ics on the web'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeThumbColor: palette.brand,
        ),
        if (since != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Meetings since ${DateFormat('d MMM, HH:mm').format(since.toLocal())}',
                  style: small,
                ),
              ),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  provider.setImportSince(DateTime(now.year, now.month, now.day));
                },
                child: const Text('From start of today'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: project?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Default project',
            helperText: 'For meetings no rule matches. None leaves them pending.',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int?>(
                value: null, child: Text('— None (review by hand) —')),
            ...projects.map((p) => DropdownMenuItem<int?>(
                  value: p.id,
                  child: Text(p.code.isNotEmpty ? '${p.code} — ${p.name}' : p.name,
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (id) {
            final p = projects.firstWhereOrNull((x) => x.id == id);
            provider.setDefaultTarget(id, p?.tasks.firstOrNull?.id);
          },
        ),
        if (project != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('meeting-task-${project.id}'),
            initialValue: taskId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Default task',
              border: OutlineInputBorder(),
            ),
            items: project.tasks
                .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                .toList(),
            onChanged: (id) => provider.setDefaultTarget(project.id, id),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: CalendarImportProvider.lookbackChoices
                        .contains(provider.lookbackHours)
                    ? provider.lookbackHours
                    : 24,
                decoration: const InputDecoration(
                  labelText: 'Look back',
                  border: OutlineInputBorder(),
                ),
                items: CalendarImportProvider.lookbackChoices
                    .map((h) => DropdownMenuItem(
                          value: h,
                          child: Text(h < 24 ? '$h hours' : '${h ~/ 24} day${h == 24 ? '' : 's'}'),
                        ))
                    .toList(),
                onChanged: (h) => h == null ? null : provider.setLookbackHours(h),
              ),
            ),
            if (adoInstances.isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: adoInstances
                          .any((i) => i.label == provider.adoInstanceLabel)
                      ? provider.adoInstanceLabel
                      : adoInstances.first.label,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '#123 in titles links to',
                    border: OutlineInputBorder(),
                  ),
                  items: adoInstances
                      .map((i) => DropdownMenuItem(
                          value: i.label,
                          child: Text(i.label, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: provider.setAdoInstanceLabel,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (canFetch) ...[
              Expanded(
                child: FilledButton.icon(
                  onPressed: provider.isSyncing || _urlController.text.trim().isEmpty
                      ? null
                      : () => _syncNow(context),
                  icon: provider.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OutlinedButton.icon(
                onPressed: provider.isSyncing ? null : () => _upload(context),
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload .ics'),
              ),
            ),
          ],
        ),
        if (provider.lastSyncAt != null || provider.error != null) ...[
          const SizedBox(height: 8),
          Text(
            provider.error ??
                'Last sync ${DateFormat('HH:mm').format(provider.lastSyncAt!)}: '
                    '${describeImport(provider.lastResult!)}',
            style: TextStyle(
              fontSize: 12,
              color: provider.error != null ? HarvestTokens.error : palette.text3,
            ),
          ),
        ],
        if (provider.pending.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showPendingMeetingsSheet(context),
              icon: const Icon(Icons.pending_actions, size: 18),
              label: Text('Review ${provider.pending.length} pending'),
            ),
          ),
      ],
    );
  }
}

/// One line describing what a sync did.
String describeImport(MeetingImportResult r) {
  final parts = <String>[
    'logged ${r.logged.length}',
    if (r.alreadyLogged > 0) '${r.alreadyLogged} already in Harvest',
    if (r.pending.isNotEmpty) '${r.pending.length} need a project',
    if (r.failed.isNotEmpty) '${r.failed.length} failed',
    for (final MapEntry(:key, :value) in r.skipped.entries)
      '$value ${key.label.toLowerCase()}',
  ];
  final text = parts.join(', ');
  return text[0].toUpperCase() + text.substring(1);
}
