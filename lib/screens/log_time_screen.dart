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
import '../widgets/work_item_preview.dart';

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

  bool _useStartEndTime = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 9, minute: 30);
  bool _showEndBeforeStartError = false;

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

  int _timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  TimeOfDay _addMinutes(TimeOfDay t, int minutes) {
    final total = (_timeOfDayToMinutes(t) + minutes).clamp(0, 23 * 60 + 59);
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }

  void _initStartEndDefaults() {
    final entries = context.read<TimeEntryProvider>().entries;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final totalMinutes = entries
        .where((e) => e.spentDate == dateStr)
        .fold<double>(0, (sum, e) => sum + e.hours * 60)
        .round();

    final startTotalMinutes = (8 * 60 + 30 + totalMinutes).clamp(0, 23 * 60 + 59);
    final start = TimeOfDay(hour: startTotalMinutes ~/ 60, minute: startTotalMinutes % 60);

    final endCandidate = _addMinutes(start, 60);
    final now = TimeOfDay.now();
    final end = _timeOfDayToMinutes(endCandidate) <= _timeOfDayToMinutes(now)
        ? endCandidate
        : now;

    setState(() {
      _startTime = start;
      _endTime = end;
      _showEndBeforeStartError = false;
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        final endCandidate = _addMinutes(picked, 60);
        final now = TimeOfDay.now();
        _endTime = _timeOfDayToMinutes(endCandidate) <= _timeOfDayToMinutes(now)
            ? endCandidate
            : now;
      } else {
        _endTime = picked;
      }
      _showEndBeforeStartError = false;
    });
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
    if (picked != null) {
      setState(() => _selectedDate = picked);
      if (_useStartEndTime) _initStartEndDefaults();
    }
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    double hours;
    if (_useStartEndTime) {
      if (_timeOfDayToMinutes(_endTime) <= _timeOfDayToMinutes(_startTime)) {
        setState(() => _showEndBeforeStartError = true);
        return;
      }
      hours = (_timeOfDayToMinutes(_endTime) - _timeOfDayToMinutes(_startTime)) / 60.0;
    } else {
      if (int.parse(_hoursController.text) == 0 &&
          int.parse(_minutesController.text) == 0) {
        setState(() {}); // trigger inline error
        return;
      }
      hours = int.parse(_hoursController.text) +
          int.parse(_minutesController.text) / 60.0;
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
      final adoService = context.read<AdoService>();
      final projectGuid =
          await adoService.getHarvestConnectionGuid(_selectedAdoInstance!);
      final workItemType = _previewItem?.workItemType ?? 'Work Item';

      final refId = projectGuid != null
          ? 'AzureDevOps_${projectGuid}_${workItemType}_$workItemId'
          : workItemId;

      extRef = ExternalReference(
        id: refId,
        permalink: _selectedAdoInstance!.permalinkFor(workItemId),
      );
    }

    final userNotes = _notesController.text.trim();
    String? notes;
    if (extRef != null) {
      final workItemId = _workItemIdController.text.trim();
      final workItemType = _previewItem?.workItemType ?? 'Work Item';
      final prefix =
          '${_selectedAdoInstance!.label} Azure DevOps $workItemType #$workItemId';
      notes = userNotes.isEmpty ? prefix : '$prefix - $userNotes';
    } else if (userNotes.isNotEmpty) {
      notes = userNotes;
    }

    final request = CreateTimeEntryRequest(
      userId: AppConfig.userId,
      projectId: project.id,
      taskId: task.id,
      spentDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
      hours: hours,
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
        _showEndBeforeStartError = false;
      });
      if (_useStartEndTime) _initStartEndDefaults();
    }
  }

  Widget _buildTimeTile(String label, TimeOfDay time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.access_time),
        ),
        child: Text(
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        ),
      ),
    );
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

            // Mode toggle
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
                  icon: Icon(Icons.schedule),
                ),
              ],
              selected: {_useStartEndTime},
              onSelectionChanged: (s) {
                setState(() {
                  _useStartEndTime = s.first;
                  _showEndBeforeStartError = false;
                });
                if (_useStartEndTime) _initStartEndDefaults();
              },
            ),
            const SizedBox(height: 16),

            // Duration inputs or start/end time pickers
            if (!_useStartEndTime) ...[
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
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildTimeTile(
                      'Start',
                      _startTime,
                      () => _pickTime(true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTimeTile(
                      'End',
                      _endTime,
                      () => _pickTime(false),
                    ),
                  ),
                ],
              ),
              if (_showEndBeforeStartError)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(
                    'End time must be after start time',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
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
