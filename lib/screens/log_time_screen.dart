import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../models/ado_work_item.dart';
import '../models/mapping_rule.dart';
import '../models/project_assignment.dart';
import '../models/quick_template.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/mapping_rule_provider.dart';
import '../providers/quick_template_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';
import '../theme/harvest_tokens.dart';
import '../widgets/project_task_selector.dart';
import '../widgets/quick_template_bar.dart';
import '../widgets/error_banner.dart';
import '../widgets/work_item_picker.dart';
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
  bool _previewLoading = false;

  bool _useStartEndTime = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _endTime = const TimeOfDay(hour: 9, minute: 30);
  bool _showEndBeforeStartError = false;

  /// `instanceLabel:workItemId` a mapping rule has already been applied for, so
  /// a rebuild or a re-fetch never overrides a selection the user has since
  /// changed by hand.
  String? _mappingAppliedKey;
  String? _mappingBanner;
  _MappingUndo? _mappingUndo;

  /// Template whose notes are currently sitting in the notes field, so tapping
  /// a second template can replace them without clobbering anything typed.
  String? _notesFromTemplateId;

  @override
  void initState() {
    super.initState();
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

  static String _formatClock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _addMinutes(TimeOfDay t, int minutes) {
    final total = (_timeOfDayToMinutes(t) + minutes).clamp(0, 23 * 60 + 59).toInt();
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }

  void _initStartEndDefaults() {
    final entries = context.read<TimeEntryProvider>().entries;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final totalMinutes = entries
        .where((e) => e.spentDate == dateStr)
        .fold<double>(0, (sum, e) => sum + e.hours * 60)
        .round();

    final startTotalMinutes = (8 * 60 + 30 + totalMinutes).clamp(0, 23 * 60 + 59).toInt();
    final start = TimeOfDay(hour: startTotalMinutes ~/ 60, minute: startTotalMinutes % 60);

    final endCandidate = _addMinutes(start, 60);
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final selectedStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final TimeOfDay end;
    if (selectedStr == todayStr) {
      final now = TimeOfDay.now();
      end = _timeOfDayToMinutes(endCandidate) <= _timeOfDayToMinutes(now)
          ? endCandidate
          : now;
    } else {
      end = endCandidate;
    }

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
      builder: (ctx, child) {
        if (child == null) {
          return const SizedBox.shrink();
        }
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        final endCandidate = _addMinutes(picked, 60);
        final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final selectedStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        if (selectedStr == todayStr) {
          final now = TimeOfDay.now();
          _endTime = _timeOfDayToMinutes(endCandidate) <= _timeOfDayToMinutes(now)
              ? endCandidate
              : now;
        } else {
          _endTime = endCandidate;
        }
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
        _previewLoading = false;
        _clearMappingBanner();
      });
      return;
    }

    final adoService = context.read<AdoService>();
    final cached = adoService.getCached(_selectedAdoInstance!.label, text);
    if (cached != null) {
      setState(() => _previewLoading = false);
      _maybeApplyMapping(cached);
      return;
    }

    _debounce?.cancel();
    setState(() => _previewLoading = true);
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final instance = _selectedAdoInstance;
      if (instance == null) return;
      await adoService.fetchWorkItem(instance, text);
      if (!mounted) return;
      setState(() => _previewLoading = false);
      final item = adoService.getCached(instance.label, text);
      if (item != null) _maybeApplyMapping(item);
    });
  }

  /// Opens the work item picker and drops the chosen id into the field, then
  /// runs the same path as typing it — preview, then mapping rules.
  Future<void> _openWorkItemPicker() async {
    final instance = _selectedAdoInstance;
    if (instance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an ADO instance first')),
      );
      return;
    }
    final picked = await showWorkItemPicker(context, instance: instance);
    if (picked == null || !mounted) return;
    _workItemIdController.text = picked;
    _onWorkItemChanged();
  }

  /// Applies the first matching mapping rule to the project/task selection —
  /// once per work item, and only when both the rule's project and task are
  /// still in the current assignment list.
  void _maybeApplyMapping(AdoWorkItem item) {
    final instance = _selectedAdoInstance;
    if (instance == null) return;
    final key = '${instance.label}:${item.id}';
    if (_mappingAppliedKey == key) return;

    final match = context.read<MappingRuleProvider>().match(item);
    if (match == null) return;

    final assignments = context.read<AssignmentProvider>();
    final project =
        assignments.projects.firstWhereOrNull((p) => p.id == match.projectId);
    final task = project?.tasks.firstWhereOrNull((t) => t.id == match.taskId);
    if (project == null || task == null) return;

    final undo = _MappingUndo(
      project: assignments.selectedProject,
      task: assignments.selectedTask,
      notes: _notesController.text,
    );
    assignments.selectProjectById(project.id, taskId: task.id);

    // Only prefill notes the user has not already written into.
    final template = match.rule.noteTemplate;
    if (template != null &&
        template.trim().isNotEmpty &&
        _notesController.text.trim().isEmpty) {
      _notesController.text = renderNoteTemplate(template, item.matchContext);
    }

    setState(() {
      _mappingAppliedKey = key;
      _mappingUndo = undo;
      _mappingBanner = '${match.rule.name} → ${project.name} · ${task.name}';
    });
  }

  void _undoMapping() {
    final undo = _mappingUndo;
    if (undo == null) return;
    context.read<AssignmentProvider>().restoreSelection(undo.project, undo.task);
    _notesController.text = undo.notes;
    // _mappingAppliedKey stays set so the rule does not immediately re-apply.
    setState(() {
      _mappingUndo = null;
      _mappingBanner = null;
    });
  }

  /// Fills the form from a template. Project and task always win — the tap is
  /// an explicit choice — while notes only get overwritten when they are empty
  /// or came from another template.
  void _applyTemplate(QuickTemplate template) {
    final assignments = context.read<AssignmentProvider>();
    final project = assignments.projects
        .firstWhereOrNull((p) => p.id == template.projectId);
    final task = project?.tasks.firstWhereOrNull((t) => t.id == template.taskId);
    if (project == null || task == null) return;

    assignments.selectProjectById(project.id, taskId: task.id);

    final templateNotes = template.notes ?? '';
    final canReplaceNotes =
        _notesController.text.trim().isEmpty || _notesFromTemplateId != null;
    if (canReplaceNotes) {
      _notesController.text = templateNotes;
      _notesFromTemplateId = templateNotes.isEmpty ? null : template.id;
    }

    setState(() {
      // An explicit pick supersedes whatever a mapping rule chose.
      _mappingUndo = null;
      _mappingBanner = null;
    });
  }

  /// Caller is responsible for being inside `setState`.
  void _clearMappingBanner() {
    _mappingAppliedKey = null;
    _mappingUndo = null;
    _mappingBanner = null;
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

  /// Builds the Harvest external reference and the note that goes with it from
  /// the ADO section of the form. Shared by logging a duration and starting a
  /// timer, which differ only in the hours they send.
  Future<({ExternalReference? extRef, String? notes})> _buildAdoRefAndNotes(
      AdoService adoService) async {
    final userNotes = _notesController.text.trim();
    final workItemId = _workItemIdController.text.trim();
    final instance = _selectedAdoInstance;

    if (!_hasAdoRef || workItemId.isEmpty || instance == null) {
      return (extRef: null, notes: userNotes.isEmpty ? null : userNotes);
    }

    final projectGuid = await adoService.getHarvestConnectionGuid(instance);
    final workItemType =
        adoService.getCached(instance.label, workItemId)?.workItemType ??
            'Work Item';
    final refId = projectGuid != null
        ? 'AzureDevOps_${projectGuid}_${workItemType}_$workItemId'
        : workItemId;

    final prefix =
        '${instance.label} Azure DevOps $workItemType #$workItemId';
    return (
      extRef: ExternalReference(
        id: refId,
        permalink: instance.permalinkFor(workItemId),
      ),
      notes: userNotes.isEmpty ? prefix : '$prefix - $userNotes',
    );
  }

  /// Creates the entry with no hours, which starts Harvest timing it. The
  /// duration inputs are ignored — the timer decides how long it ran.
  Future<void> _startTimer(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

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

    final ado = await _buildAdoRefAndNotes(context.read<AdoService>());
    if (!context.mounted) return;

    final started = await entryProvider.startTimer(CreateTimeEntryRequest(
      userId: AppConfig.userId,
      projectId: project.id,
      taskId: task.id,
      spentDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      notes: ado.notes,
      externalReference: ado.extRef,
    ));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(started
            ? (entryProvider.successMessage ?? 'Timer started')
            : (entryProvider.error ?? 'Could not start the timer')),
        backgroundColor: started ? HarvestTokens.success : HarvestTokens.error,
      ),
    );

    if (started) {
      _notesController.clear();
      _workItemIdController.clear();
      setState(() {
        _hasAdoRef = false;
        _selectedAdoInstance = null;
        _notesFromTemplateId = null;
        _clearMappingBanner();
      });
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

    final adoService = context.read<AdoService>();
    final ado = await _buildAdoRefAndNotes(adoService);
    final extRef = ado.extRef;
    final notes = ado.notes;

    // Only meaningful in Start & End mode, and only accepted by accounts that
    // track time via clock times — sending them elsewhere would be noise.
    final sendClockTimes = _useStartEndTime && entryProvider.tracksByStartEnd;

    final request = CreateTimeEntryRequest(
      userId: AppConfig.userId,
      projectId: project.id,
      taskId: task.id,
      spentDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
      hours: hours,
      notes: notes,
      externalReference: extRef,
      startedTime: sendClockTimes ? _formatClock(_startTime) : null,
      endedTime: sendClockTimes ? _formatClock(_endTime) : null,
    );

    // Capture before clearing state on success
    final adoInstanceForUpdate = _selectedAdoInstance;
    final workItemIdForUpdate = _workItemIdController.text.trim();
    final shouldUpdateAdo = extRef != null && adoInstanceForUpdate != null;

    final success = await entryProvider.submit(request);
    if (success && context.mounted) {
      String snackMessage = entryProvider.successMessage ?? 'Time logged!';
      Color snackColor = Colors.green;

      if (shouldUpdateAdo) {
        final prefs = await SharedPreferences.getInstance();
        final updateEnabled = prefs.getBool('ado_update_completed_work') ?? true;
        if (updateEnabled && context.mounted) {
          try {
            await context
                .read<AdoService>()
                .addCompletedWork(adoInstanceForUpdate, workItemIdForUpdate, hours);
          } catch (_) {
            snackMessage = 'Time logged, but could not update ADO Completed Work';
            snackColor = Colors.orange;
          }
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(snackMessage), backgroundColor: snackColor),
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
        _notesFromTemplateId = null;
        _clearMappingBanner();
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
    final palette = HarvestTokens.of(context);
    final assignments = context.watch<AssignmentProvider>();
    final entryProvider = context.watch<TimeEntryProvider>();
    final adoService = context.watch<AdoService>();

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

            QuickTemplateBar(onApply: _applyTemplate),
            if (context.watch<QuickTemplateProvider>().enabledTemplates.isNotEmpty)
              const SizedBox(height: 16),

            if (_mappingBanner != null) ...[
              _MappingAppliedBanner(
                text: _mappingBanner!,
                onUndo: _mappingUndo != null ? _undoMapping : null,
                onDismiss: () => setState(() {
                  _mappingUndo = null;
                  _mappingBanner = null;
                }),
              ),
              const SizedBox(height: 12),
            ],

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
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: palette.brandTint,
                selectedForegroundColor: HarvestTokens.brand600,
              ),
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
              // Typing takes ownership of the field, so a later template tap
              // leaves what you wrote alone.
              onChanged: (_) => _notesFromTemplateId = null,
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
            CheckboxListTile(
              value: _hasAdoRef,
              onChanged: (v) {
                final adoInstances =
                    context.read<AdoInstanceProvider>().instances;
                setState(() {
                  _hasAdoRef = v ?? false;
                  if (!_hasAdoRef) {
                    _workItemIdController.clear();
                    _selectedAdoInstance = null;
                    _clearMappingBanner();
                  } else if (adoInstances.length == 1) {
                    _selectedAdoInstance = adoInstances.first;
                  }
                });
              },
              title: const Text(
                'Link Azure DevOps Work Item',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: HarvestTokens.brand,
            ),

            if (_hasAdoRef) ...[
              const SizedBox(height: 8),

              Builder(builder: (context) {
                final adoInstances =
                    context.watch<AdoInstanceProvider>().instances;
                return SegmentedButton<AdoInstance>(
                  segments: adoInstances
                      .map((instance) => ButtonSegment<AdoInstance>(
                            value: instance,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(instance.label),
                                if (instance.pat != null) ...[
                                  const SizedBox(width: 5),
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
                onChanged: (_) => _onWorkItemChanged(),
                decoration: InputDecoration(
                  labelText: 'Work Item #',
                  border: const OutlineInputBorder(),
                  hintText: '13483',
                  prefixIcon: const Icon(Icons.tag),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search your work items',
                    onPressed: _openWorkItemPicker,
                  ),
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
                Builder(builder: (context) {
                  final wid = _workItemIdController.text.trim();
                  final cachedItem = wid.isNotEmpty
                      ? adoService.getCached(_selectedAdoInstance!.label, wid)
                      : null;
                  return WorkItemPreview(
                    isLoading: _previewLoading && cachedItem == null,
                    workItem: cachedItem,
                    hasPat: _selectedAdoInstance!.pat != null,
                    workItemId: wid,
                    instance: _selectedAdoInstance!,
                    permalink: wid.isNotEmpty
                        ? _selectedAdoInstance!.permalinkFor(wid)
                        : null,
                  );
                }),
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
            const SizedBox(height: 10),

            // Start a running timer instead of logging a fixed duration. The
            // hours/start-end inputs above are ignored — Harvest counts from
            // now until you stop it.
            Builder(builder: (context) {
              final running = entryProvider.runningEntry;
              return OutlinedButton.icon(
                onPressed: entryProvider.isSubmitting || running != null
                    ? null
                    : () => _startTimer(context),
                icon: const Icon(Icons.play_arrow),
                label: Text(running == null
                    ? 'Start Timer'
                    : 'Timer already running on ${running.projectName}'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// The project/task/notes state a mapping rule replaced, so it can be restored.
class _MappingUndo {
  final HarvestProject? project;
  final HarvestTask? task;
  final String notes;

  const _MappingUndo({
    required this.project,
    required this.task,
    required this.notes,
  });
}

/// Tells the user a rule picked the project/task for them, and offers a way out.
class _MappingAppliedBanner extends StatelessWidget {
  final String text;
  final VoidCallback? onUndo;
  final VoidCallback onDismiss;

  const _MappingAppliedBanner({
    required this.text,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: palette.brandTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HarvestTokens.brand.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: HarvestTokens.brand600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HarvestTokens.brand600,
              ),
            ),
          ),
          if (onUndo != null)
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                foregroundColor: HarvestTokens.brand600,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Undo'),
            ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            color: HarvestTokens.brand600,
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
