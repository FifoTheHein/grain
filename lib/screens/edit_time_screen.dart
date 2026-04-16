import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/ado_work_item.dart';
import '../models/project_assignment.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';
import '../widgets/project_task_selector.dart';
import '../widgets/error_banner.dart';
import '../widgets/work_item_preview.dart';

class EditTimeScreen extends StatefulWidget {
  final TimeEntry entry;

  const EditTimeScreen({super.key, required this.entry});

  @override
  State<EditTimeScreen> createState() => _EditTimeScreenState();
}

class _EditTimeScreenState extends State<EditTimeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();
  final _notesController = TextEditingController();
  final _workItemIdController = TextEditingController();

  late DateTime _selectedDate;
  AdoInstance? _selectedAdoInstance;
  bool _hasAdoRef = false;
  Timer? _debounce;
  AdoWorkItem? _previewItem;
  bool _previewLoading = false;

  // Saved so we can restore AssignmentProvider on pop
  HarvestProject? _savedProject;
  HarvestTask? _savedTask;

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _prefillFromEntry();
    }
  }

  void _prefillFromEntry() {
    final entry = widget.entry;

    // Hours / Minutes
    final totalMinutes = (entry.hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    // Round minutes to nearest 5 to match the dropdown options
    final mRounded = ((m / 5).round() * 5) % 60;
    _hoursController.text = '$h';
    _minutesController.text = '$mRounded';

    // Notes (raw, including any ADO prefix)
    _notesController.text = entry.notes ?? '';

    // Date
    _selectedDate = DateFormat('yyyy-MM-dd').parse(entry.spentDate);

    // ADO reference
    if (entry.externalReference != null) {
      _hasAdoRef = true;
      _workItemIdController.text =
          AdoService.parseWorkItemId(entry.externalReference!.id);
      final permalink = entry.externalReference!.permalink ?? '';
      final instances = context.read<AdoInstanceProvider>().instances;
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          _selectedAdoInstance = inst;
          break;
        }
      }
    }

    // Project / Task — save current selection then switch to entry's values
    final assignments = context.read<AssignmentProvider>();
    _savedProject = assignments.selectedProject;
    _savedTask = assignments.selectedTask;
    assignments.selectProjectById(entry.projectId, taskId: entry.taskId);

    // Trigger work item preview if ADO ref exists
    if (_hasAdoRef && _selectedAdoInstance != null) {
      _onWorkItemChanged();
    }
  }

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

    // Restore the original AssignmentProvider selection so Log Time is unaffected
    final assignments = context.read<AssignmentProvider>();
    assignments.restoreSelection(_savedProject, _savedTask);

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

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final entryProvider = context.read<TimeEntryProvider>();
    final success = await entryProvider.delete(widget.entry.id);
    if (success && context.mounted) {
      Navigator.of(context).pop(); // back to recent entries
    }
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    if (int.parse(_hoursController.text) == 0 &&
        int.parse(_minutesController.text) == 0) {
      setState(() {});
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
      final originalRef = widget.entry.externalReference;

      // If the ADO reference is unchanged (same work item + same instance),
      // preserve the original external reference as-is. This prevents
      // accidentally overwriting a correct composite ID with a wrong GUID
      // when the user only changed hours, notes, date, etc.
      final originalWorkItemId = originalRef != null
          ? AdoService.parseWorkItemId(originalRef.id)
          : null;
      final instanceUnchanged = originalRef?.permalink != null &&
          _selectedAdoInstance!.matchesPermalink(originalRef!.permalink!);

      if (originalRef != null &&
          originalWorkItemId == workItemId &&
          instanceUnchanged) {
        extRef = originalRef; // ADO ref unchanged — preserve as-is
      } else {
        // ADO reference changed — build a fresh composite ID
        final adoService = context.read<AdoService>();
        var workItemType = _previewItem?.workItemType;
        if (workItemType == null && originalRef != null) {
          workItemType = AdoService.parseWorkItemType(originalRef.id);
        }
        workItemType ??= 'Work Item';

        final projectGuid =
            await adoService.getHarvestConnectionGuid(_selectedAdoInstance!);
        final refId = projectGuid != null
            ? 'AzureDevOps_${projectGuid}_${workItemType}_$workItemId'
            : workItemId;

        extRef = ExternalReference(
          id: refId,
          permalink: _selectedAdoInstance!.permalinkFor(workItemId),
        );
      }
    }

    final request = UpdateTimeEntryRequest(
      projectId: project.id,
      taskId: task.id,
      spentDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
      hours: int.parse(_hoursController.text) +
          int.parse(_minutesController.text) / 60.0,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      externalReference: extRef,
    );

    final success = await entryProvider.update(widget.entry.id, request);
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(entryProvider.successMessage ?? 'Entry updated!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final assignments = context.watch<AssignmentProvider>();
    final entryProvider = context.watch<TimeEntryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Entry'),
        backgroundColor: const Color(0xFFFA5D24),
        foregroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete entry',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
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
                      WorkItemPreview(
                        isLoading: _previewLoading,
                        workItem: _previewItem,
                        hasPat: _selectedAdoInstance!.pat != null,
                        workItemId: _workItemIdController.text.trim(),
                        instance: _selectedAdoInstance!,
                        permalink: _workItemIdController.text.trim().isNotEmpty
                            ? _selectedAdoInstance!
                                .permalinkFor(_workItemIdController.text.trim())
                            : null,
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
                      entryProvider.isSubmitting ? 'Saving...' : 'Update Entry',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
