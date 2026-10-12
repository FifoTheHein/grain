import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/calendar_event.dart';
import '../models/meeting.dart';
import '../models/project_assignment.dart';
import '../providers/assignment_provider.dart';
import '../providers/calendar_import_provider.dart';
import '../theme/harvest_tokens.dart';

/// Lists meetings no rule or default could place, each with a project/task
/// picker plus Log and Skip. Skip records the meeting as handled so it stops
/// coming back.
Future<void> showPendingMeetingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PendingMeetingsSheet(),
    );

class _PendingMeetingsSheet extends StatelessWidget {
  const _PendingMeetingsSheet();

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final pending = context.watch<CalendarImportProvider>().pending;
    final projects = context.watch<AssignmentProvider>().projects;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              pending.isEmpty
                  ? 'All meetings are placed'
                  : '${pending.length} meeting${pending.length == 1 ? '' : 's'} need a project',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: palette.text),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: pending.length,
              itemBuilder: (_, i) => _PendingRow(
                key: ValueKey(meetingLedgerKey(pending[i])),
                event: pending[i],
                projects: projects,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatefulWidget {
  final CalendarEvent event;
  final List<HarvestProject> projects;

  const _PendingRow({super.key, required this.event, required this.projects});

  @override
  State<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends State<_PendingRow> {
  int? _projectId;
  int? _taskId;
  bool _busy = false;

  HarvestProject? get _project =>
      widget.projects.firstWhereOrNull((p) => p.id == _projectId);

  Future<void> _log() async {
    final provider = context.read<CalendarImportProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final error =
        await provider.logPending(widget.event, _projectId!, _taskId!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(
        content: Text('Could not log: $error'),
        backgroundColor: HarvestTokens.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final e = widget.event;
    final start = e.start.toLocal();
    final project = _project;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(meetingNotes(e),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: palette.text)),
          Text(
            '${DateFormat('EEE d MMM, HH:mm').format(start)} · '
            '${e.duration.inMinutes} min',
            style: TextStyle(fontSize: 11, color: palette.text3),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _projectId,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Project',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: widget.projects
                .map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (id) => setState(() {
              _projectId = id;
              _taskId = _project?.tasks.firstOrNull?.id;
            }),
          ),
          if (project != null) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey('task-${project.id}'),
              initialValue: _taskId,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Task',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: project.tasks
                  .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                  .toList(),
              onChanged: (id) => setState(() => _taskId = id),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => context
                        .read<CalendarImportProvider>()
                        .skipPending(widget.event),
                child: const Text('Skip'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    _busy || _projectId == null || _taskId == null ? null : _log,
                child: Text(_busy ? 'Logging…' : 'Log'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
