import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../models/ado_work_item.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';
import '../widgets/project_task_selector.dart';
import '../widgets/error_banner.dart';

class LogTimeScreen extends StatefulWidget {
  const LogTimeScreen({super.key});

  @override
  State<LogTimeScreen> createState() => _LogTimeScreenState();
}

class _LogTimeScreenState extends State<LogTimeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController(text: '1');
  final _minutesController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _workItemIdController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  AdoInstance? _selectedAdoInstance;
  bool _hasAdoRef = false;
  Timer? _debounce;
  AdoWorkItem? _previewItem;
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    _workItemIdController.addListener(_onWorkItemChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hoursController.dispose();
    _minutesController.dispose();
    _notesController.dispose();
    _workItemIdController.dispose();
    super.dispose();
  }

  void _onWorkItemChanged() {
    final text = _workItemIdController.text.trim();
    if (text.isEmpty || _selectedAdoInstance == null) {
      _debounce?.cancel();
      setState(() {
        _previewItem = null;
        _previewLoading = false;
      });
      return;
    }

    final adoService = context.read<AdoService>();
    final cached = adoService.getCached(_selectedAdoInstance!.label, text);
    if (cached != null) {
      setState(() {
        _previewItem = cached;
        _previewLoading = false;
      });
      return;
    }

    _debounce?.cancel();
    setState(() {
      _previewItem = null;
      _previewLoading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final instance = _selectedAdoInstance;
      if (instance == null) return;
      await adoService.fetchWorkItem(instance, text);
      if (!mounted) return;
      setState(() {
        _previewItem = adoService.getCached(instance.label, text);
        _previewLoading = false;
      });
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    if (int.parse(_hoursController.text) == 0 &&
        int.parse(_minutesController.text) == 0) {
      setState(() {}); // trigger the inline error to show
      return;
    }

    final assignments = context.read<AssignmentProvider>();
    final entryProvider = context.read<TimeEntryProvider>();

    final project = assignments.selectedProject;
    final task = assignments.selectedTask;
    if (project == null || task == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a project and task')),
      );
      return;
    }

    ExternalReference? extRef;
    if (_hasAdoRef &&
        _workItemIdController.text.trim().isNotEmpty &&
        _selectedAdoInstance != null) {
      final workItemId = _workItemIdController.text.trim();
      extRef = ExternalReference(
        id: workItemId,
        permalink: _selectedAdoInstance!.permalinkFor(workItemId),
      );
    }

    final userNotes = _notesController.text.trim();
    String? notes;
    if (extRef != null) {
      final prefix =
          '${_selectedAdoInstance!.label} Azure DevOps User Story #${extRef.id}';
      notes = userNotes.isEmpty ? prefix : '$prefix - $userNotes';
    } else if (userNotes.isNotEmpty) {
      notes = userNotes;
    }

    final request = CreateTimeEntryRequest(
      userId: AppConfig.userId,
      projectId: project.id,
      taskId: task.id,
      spentDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
      hours: int.parse(_hoursController.text) +
          int.parse(_minutesController.text) / 60.0,
      notes: notes,
      externalReference: extRef,
    );

    final success = await entryProvider.submit(request);
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(entryProvider.successMessage ?? 'Time logged!'),
          backgroundColor: Colors.green,
        ),
      );
      _notesController.clear();
      _workItemIdController.clear();
      _hoursController.text = '1';
      _minutesController.text = '0';
      setState(() {
        _selectedDate = DateTime.now();
        _hasAdoRef = false;
        _selectedAdoInstance = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignments = context.watch<AssignmentProvider>();
    final entryProvider = context.watch<TimeEntryProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (assignments.error != null)
              ErrorBanner(message: 'Projects: ${assignments.error!}'),
            if (entryProvider.error != null)
              ErrorBanner(message: entryProvider.error!),

            const ProjectTaskSelector(),
            const SizedBox(height: 16),

            // Date picker
            InkWell(
              onTap: () => _pickDate(context),
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Hours + Minutes
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _hoursController.text,
                        isDense: true,
                        items: List.generate(25, (i) => '$i')
                            .map((h) => DropdownMenuItem(
                                  value: h,
                                  child: Text(h),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _hoursController.text = v!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _minutesController.text,
                        isDense: true,
                        items: List.generate(12, (i) => '${i * 5}')
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _minutesController.text = v!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (int.parse(_hoursController.text) == 0 &&
                int.parse(_minutesController.text) == 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  'Duration must be greater than 0',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                hintText: 'What did you work on?',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Azure DevOps section
            const Divider(),
            Row(
              children: [
                Checkbox(
                  value: _hasAdoRef,
                  onChanged: (v) => setState(() {
                    _hasAdoRef = v ?? false;
                    if (!_hasAdoRef) {
                      _workItemIdController.clear();
                      _selectedAdoInstance = null;
                    }
                  }),
                ),
                const Text(
                  'Link Azure DevOps Work Item',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),

            if (_hasAdoRef) ...[
              const SizedBox(height: 12),

              // ADO instance selector
              Builder(builder: (context) {
                final adoInstances =
                    context.watch<AdoInstanceProvider>().instances;
                return SegmentedButton<AdoInstance>(
                  segments: adoInstances
                      .map((instance) => ButtonSegment<AdoInstance>(
                            value: instance,
                            label: Text(instance.label),
                          ))
                      .toList(),
                  selected: _selectedAdoInstance != null
                      ? {_selectedAdoInstance!}
                      : {},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (selection) {
                    setState(() => _selectedAdoInstance =
                        selection.isEmpty ? null : selection.first);
                    _onWorkItemChanged();
                  },
                );
              }),
              const SizedBox(height: 8),

              TextFormField(
                controller: _workItemIdController,
                decoration: const InputDecoration(
                  labelText: 'Work Item #',
                  border: OutlineInputBorder(),
                  hintText: '13483',
                  prefixIcon: Icon(Icons.tag),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (!_hasAdoRef) return null;
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter a work item number';
                  }
                  if (_selectedAdoInstance == null) {
                    return 'Select an ADO instance above';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              if (_selectedAdoInstance != null)
                _WorkItemPreview(
                  isLoading: _previewLoading,
                  workItem: _previewItem,
                  hasPat: _selectedAdoInstance!.pat != null,
                  workItemId: _workItemIdController.text.trim(),
                  instance: _selectedAdoInstance!,
                ),
            ],

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: entryProvider.isSubmitting
                  ? null
                  : () => _submit(context),
              icon: entryProvider.isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(
                entryProvider.isSubmitting ? 'Logging...' : 'Log Time',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkItemPreview extends StatelessWidget {
  final bool isLoading;
  final AdoWorkItem? workItem;
  final bool hasPat;
  final String workItemId;
  final AdoInstance instance;

  const _WorkItemPreview({
    required this.isLoading,
    required this.workItem,
    required this.hasPat,
    required this.workItemId,
    required this.instance,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasPat) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Configure a PAT in Settings to see work item details.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    if (workItemId.isEmpty) return const SizedBox.shrink();

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Looking up work item...'),
          ],
        ),
      );
    }

    if (workItem != null) {
      final stateColor = _stateColor(context, workItem!.state);
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 3, right: 8),
              decoration: BoxDecoration(
                color: stateColor,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workItem!.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    workItem!.state,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: stateColor,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Fallback: show permalink
    final permalink = instance.permalinkFor(workItemId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        permalink,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Color _stateColor(BuildContext context, String state) {
    final s = state.toLowerCase();
    if (s.contains('done') || s.contains('closed') || s.contains('resolved')) {
      return Colors.green;
    }
    if (s.contains('active') ||
        s.contains('in progress') ||
        s.contains('committed')) {
      return Colors.blue;
    }
    if (s.contains('removed') || s.contains('cut')) {
      return Colors.grey;
    }
    return Theme.of(context).colorScheme.secondary;
  }
}
