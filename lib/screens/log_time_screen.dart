import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../models/ado_work_item.dart';
import '../models/day_insights.dart';
import '../models/duration_input.dart';
import '../models/future_days.dart';
import '../models/log_time_defaults.dart';
import '../models/log_time_prefill.dart';
import '../models/mapping_rule.dart';
import '../models/meeting.dart' show workItemIdFromTitle;
import '../models/project_assignment.dart';
import '../models/quick_template.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/mapping_rule_provider.dart';
import '../providers/project_category_provider.dart';
import '../providers/quick_template_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';
import '../theme/harvest_tokens.dart';
import '../widgets/duration_stepper.dart';
import '../widgets/log_action_bar.dart';
import '../widgets/project_task_selector.dart';
import '../widgets/quick_template_bar.dart';
import '../widgets/upcoming_tag.dart';
import '../widgets/error_banner.dart';
import '../widgets/work_item_picker.dart';
import '../widgets/work_item_preview.dart';

/// SharedPreferences key remembering Duration (false) vs Start & End (true).
const kLogTimeStartEndKey = 'log_time_start_end';

class LogTimeScreen extends StatefulWidget {
  /// The date the form opens on, e.g. an empty future day on Recent handing
  /// over "Log time for Thu 15 Oct". Today when null.
  final DateTime? initialDate;

  /// The form as Insights' "Log this" hands it over: mode, duration or
  /// times, and where the stretch was. Applied over [initialDate].
  final LogTimePrefill? prefill;

  const LogTimeScreen({super.key, this.initialDate, this.prefill});

  @override
  State<LogTimeScreen> createState() => _LogTimeScreenState();
}

class _LogTimeScreenState extends State<LogTimeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _workItemIdController = TextEditingController();

  late DateTime _selectedDate = widget.initialDate ?? DateTime.now();

  /// The handed-over prefill while it still describes the form. Cleared by a
  /// manual change of date or mode, and after logging.
  LogTimePrefill? _prefill;

  /// The mode remembered in prefs, which a prefill overrides on screen
  /// without replacing.
  bool _savedStartEnd = false;
  AdoInstance? _selectedAdoInstance;
  bool _hasAdoRef = false;
  Timer? _debounce;
  bool _previewLoading = false;

  /// Duration mode's value. Starts at nothing rather than a guess: a 1h
  /// default got logged as 1h whenever someone forgot to change it.
  int _durationMinutes = 0;

  /// Set by a tap on the disabled Log button, so "must be greater than 0" is
  /// a reply to trying rather than a scolding on arrival.
  bool _submitAttempted = false;

  bool _useStartEndTime = false;

  /// Start & End values once the user has touched them. While null the times
  /// follow [startEndDefaults], so they keep up with "now" and with entries
  /// that arrive after the screen opened.
  int? _startOverride;
  int? _endOverride;

  /// `#123` found in the notes and dismissed, so the Link card stays away.
  String? _dismissedDetectedId;

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
    final prefill = widget.prefill;
    if (prefill != null) _fillFrom(prefill);
    _loadMode();
  }

  Future<void> _loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final startEnd = prefs.getBool(kLogTimeStartEndKey) ?? false;
    _savedStartEnd = startEnd;
    // A prefill chose the mode for this visit; the saved one waits until it
    // clears.
    if (mounted && _prefill == null && startEnd != _useStartEndTime) {
      setState(() => _useStartEndTime = startEnd);
    }
  }

  Future<void> _setMode(bool startEnd) async {
    setState(() {
      _prefill = null;
      _useStartEndTime = startEnd;
      _resetStartEnd();
    });
    _savedStartEnd = startEnd;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kLogTimeStartEndKey, startEnd);
  }

  /// Caller is responsible for being inside `setState` (or `initState`).
  /// Start & End times count as touched, so the defaults don't replace them.
  void _fillFrom(LogTimePrefill p) {
    _prefill = p;
    _selectedDate = p.date;
    _useStartEndTime = p.startEnd;
    _submitAttempted = false;
    if (p.startEnd) {
      _startOverride = p.start;
      _endOverride = p.end;
    } else {
      _resetStartEnd();
      _durationMinutes = p.minutes;
    }
  }

  /// Caller is responsible for being inside `setState`. Drops the prefill
  /// and returns to the saved mode.
  void _clearPrefill() {
    if (_prefill == null) return;
    _prefill = null;
    _useStartEndTime = _savedStartEnd;
  }

  @override
  void didUpdateWidget(LogTimeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prefill = widget.prefill;
    if (prefill != null && prefill != oldWidget.prefill) {
      setState(() => _fillFrom(prefill));
      return;
    }
    final date = widget.initialDate;
    if (date != null && date != oldWidget.initialDate) _setDate(date);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _notesController.dispose();
    _workItemIdController.dispose();
    super.dispose();
  }

  // ── Dates and clock times ──────────────────────────────────────────────

  int get _daysFromToday => daysFromToday(_selectedDate, DateTime.now());

  bool get _isToday => _daysFromToday == 0;

  bool get _isYesterday => _daysFromToday == -1;

  bool get _isTomorrow => _daysFromToday == 1;

  /// Logging ahead: no gap chip and no timer, since Harvest only times today.
  bool get _isFuture => _daysFromToday > 0;

  static int _nowMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  /// "today", "yesterday", "tomorrow" or "Fri 9 Oct" — how the action bar
  /// names the date.
  String get _dateWord {
    if (_isToday) return 'today';
    if (_isYesterday) return 'yesterday';
    if (_isTomorrow) return 'tomorrow';
    return DateFormat('EEE d MMM').format(_selectedDate);
  }

  void _setDate(DateTime date) {
    setState(() {
      _clearPrefill();
      _selectedDate = date;
      _resetStartEnd();
    });
  }

  /// Caller is responsible for being inside `setState`.
  void _resetStartEnd() {
    _startOverride = null;
    _endOverride = null;
  }

  StartEndDefaults _startEndDefaults(TimeEntryProvider entries) {
    final workDayStart = context.read<ProjectCategoryProvider>().workDayStart;
    return startEndDefaults(
      entries.entriesOn(_selectedDate),
      workDayStart: workDayStart.hour * 60 + workDayStart.minute,
      isToday: _isToday,
      isFuture: _isFuture,
      nowMinutes: _nowMinutes(),
    );
  }

  /// The Start & End pair currently on screen: overrides where touched,
  /// defaults elsewhere.
  ({int start, int end, StartEndDefaults defaults}) _clockRange(
      TimeEntryProvider entries) {
    final defaults = _startEndDefaults(entries);
    return (
      start: _startOverride ?? defaults.start,
      end: _endOverride ?? defaults.end,
      defaults: defaults,
    );
  }

  /// Whatever is logged by the button: the stepper, or end − start.
  int _effectiveMinutes(TimeEntryProvider entries) {
    if (!_useStartEndTime) return _durationMinutes;
    final r = _clockRange(entries);
    return r.end > r.start ? r.end - r.start : 0;
  }

  void _nudge(TimeEntryProvider entries, {required bool isStart, required int delta}) {
    final r = _clockRange(entries);
    setState(() {
      // Touching one end pins both, so the other stops following "now".
      _startOverride = r.start;
      _endOverride = r.end;
      if (isStart) {
        _startOverride = nudgeClock(r.start, delta);
      } else {
        _endOverride = nudgeClock(r.end, delta,
            ceiling: _isToday ? _nowMinutes() : 23 * 60 + 59);
      }
    });
  }

  Future<void> _pickTime(TimeEntryProvider entries, bool isStart) async {
    final r = _clockRange(entries);
    final current = isStart ? r.start : r.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
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
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      _startOverride = r.start;
      _endOverride = r.end;
      if (isStart) {
        _startOverride = minutes;
        // Keep the end where it was unless the new start overtook it.
        if (r.end <= minutes) {
          final ceiling = _isToday ? _nowMinutes() : 23 * 60 + 59;
          _endOverride = nudgeClock(minutes, 60, ceiling: ceiling);
        }
      } else {
        _endOverride = minutes;
      }
    });
  }

  // ── ADO ────────────────────────────────────────────────────────────────

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

  /// The instance a `#123` in the notes is looked up in: the one already
  /// chosen, else the first with a PAT, else the first.
  AdoInstance? _detectInstance(List<AdoInstance> instances) =>
      _selectedAdoInstance ??
      instances.firstWhereOrNull((i) => i.pat != null && i.pat!.isNotEmpty) ??
      instances.firstOrNull;

  /// A work item number typed into the notes while nothing is linked yet.
  String? _detectedWorkItemId() {
    if (_hasAdoRef && _workItemIdController.text.trim().isNotEmpty) {
      return null;
    }
    final id = workItemIdFromTitle(_notesController.text);
    if (id == null || id == _dismissedDetectedId) return null;
    return id;
  }

  void _onNotesChanged(String _) {
    // Typing takes ownership of the field, so a later template tap leaves
    // what you wrote alone.
    _notesFromTemplateId = null;
    final id = _detectedWorkItemId();
    if (id != null) {
      final instance =
          _detectInstance(context.read<AdoInstanceProvider>().instances);
      if (instance != null) {
        // A no-op without a PAT, and deduplicated while in flight.
        context.read<AdoService>().fetchWorkItem(instance, id);
      }
    }
    setState(() {});
  }

  void _linkDetected(String id, AdoInstance instance) {
    _workItemIdController.text = id;
    setState(() {
      _hasAdoRef = true;
      _selectedAdoInstance = instance;
    });
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
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: clampToSelectable(_selectedDate, now),
      firstDate: DateTime(2020),
      lastDate: latestSelectableDate(now),
    );
    if (picked != null) _setDate(picked);
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

    final link = await adoService.workItemReference(instance, workItemId);
    final prefix = link.notePrefix;
    return (
      extRef: link.ref,
      notes: userNotes.isEmpty ? prefix : '$prefix - $userNotes',
    );
  }

  /// Caller is responsible for being inside `setState`. Clears the ADO link
  /// and template marker after an entry or timer is created.
  void _clearAfterCreate() {
    _hasAdoRef = false;
    _selectedAdoInstance = null;
    _notesFromTemplateId = null;
    _dismissedDetectedId = null;
    _clearMappingBanner();
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
      setState(_clearAfterCreate);
    }
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final entryProvider = context.read<TimeEntryProvider>();
    final range = _clockRange(entryProvider);
    final minutes = _effectiveMinutes(entryProvider);
    if (minutes <= 0) {
      setState(() => _submitAttempted = true);
      return;
    }
    final hours = minutes / 60.0;

    final assignments = context.read<AssignmentProvider>();
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
      startedTime: sendClockTimes ? formatClock(range.start) : null,
      endedTime: sendClockTimes ? formatClock(range.end) : null,
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
      setState(() {
        _selectedDate = DateTime.now();
        _durationMinutes = 0;
        _submitAttempted = false;
        _resetStartEnd();
        _clearPrefill();
        _clearAfterCreate();
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final assignments = context.watch<AssignmentProvider>();
    final entryProvider = context.watch<TimeEntryProvider>();
    final adoService = context.watch<AdoService>();
    final adoInstances = context.watch<AdoInstanceProvider>().instances;
    // Watched for the work-day start the Start & End defaults fall back to.
    context.watch<ProjectCategoryProvider>();

    final minutes = _effectiveMinutes(entryProvider);
    final range = _clockRange(entryProvider);
    final endBeforeStart = _useStartEndTime && range.end <= range.start;

    final gap = !_useStartEndTime && _isToday
        ? suggestGap(entryProvider.entriesOn(DateTime.now()),
            nowMinutes: _nowMinutes())
        : null;

    final detectedId = _detectedWorkItemId();
    final detectInstance = _detectInstance(adoInstances);

    final project = assignments.selectedProject;
    final task = assignments.selectedTask;
    final running = entryProvider.runningEntry;

    final String? disabledReason;
    if (project == null || task == null) {
      disabledReason = 'Pick a project and task';
    } else if (endBeforeStart) {
      disabledReason = 'End must be after start';
    } else if (minutes <= 0) {
      disabledReason = 'Set a duration first';
    } else {
      disabledReason = null;
    }

    final what = project == null
        ? ''
        : [
            project.code.isNotEmpty ? project.code : project.name,
            if (task != null) task.name,
          ].join(' · ');
    final when = _useStartEndTime
        ? '${_isToday ? '' : '$_dateWord '}'
            '${formatClock(range.start)}–${formatClock(range.end)}'
        : _dateWord;

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (assignments.error != null)
            ErrorBanner(message: 'Projects: ${assignments.error!}'),
          if (entryProvider.error != null)
            ErrorBanner(message: entryProvider.error!),

          if (_prefill != null) ...[
            _FromInsightsLine(origin: _prefill!.origin),
            const SizedBox(height: 12),
          ],

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

          _DateChips(
            date: _selectedDate,
            daysFromToday: _daysFromToday,
            onDay: (offset) {
              final now = DateTime.now();
              _setDate(DateTime(now.year, now.month, now.day + offset));
            },
            onPick: () => _pickDate(context),
          ),
          if (_isFuture) ...[
            const SizedBox(height: 8),
            const _LoggingAheadLine(),
          ],
          const SizedBox(height: 14),

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
            onSelectionChanged: (s) => _setMode(s.first),
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: palette.brandTint,
              selectedForegroundColor: palette.brand600,
            ),
          ),
          const SizedBox(height: 16),

          if (!_useStartEndTime) ...[
            DurationStepper(
              minutes: _durationMinutes,
              onChanged: (m) => setState(() => _durationMinutes = m),
              errorText: _submitAttempted && _durationMinutes == 0
                  ? 'Duration must be greater than 0'
                  : null,
            ),
            if (gap != null && gap.minutes != _durationMinutes) ...[
              const SizedBox(height: 12),
              _GapChip(
                gap: gap,
                onUse: () => setState(() =>
                    _durationMinutes = gap.minutes.clamp(0, kMaxDurationMinutes)),
              ),
            ],
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _ClockBox(
                    label: 'Start',
                    minutes: range.start,
                    caption: _startOverride != null
                        ? (_prefillHolds ? _prefill!.startCaption : null)
                        : _startCaption(range.defaults),
                    canNudgeUp: range.start < 23 * 60 + 59,
                    onNudge: (d) =>
                        _nudge(entryProvider, isStart: true, delta: d),
                    onTap: () => _pickTime(entryProvider, true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ClockBox(
                    label: 'End',
                    minutes: range.end,
                    caption: _endOverride == null && range.defaults.endIsNow
                        ? 'now'
                        : (_prefillHolds ? _prefill!.endCaption : null),
                    canNudgeUp: range.end <
                        (_isToday ? _nowMinutes() : 23 * 60 + 59),
                    onNudge: (d) =>
                        _nudge(entryProvider, isStart: false, delta: d),
                    onTap: () => _pickTime(entryProvider, false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (endBeforeStart)
              Text(
                'End time must be after start time',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              )
            else
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: '= '),
                  TextSpan(
                    text: formatDurationLabel(minutes),
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: palette.text),
                  ),
                ]),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: palette.text2),
              ),
          ],
          const SizedBox(height: 16),

          // Notes
          TextFormField(
            controller: _notesController,
            onChanged: _onNotesChanged,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
              hintText: 'What did you work on?',
            ),
            maxLines: 3,
          ),
          if (detectedId != null && detectInstance != null) ...[
            const SizedBox(height: 8),
            _DetectedWorkItemCard(
              id: detectedId,
              instance: detectInstance,
              item: adoService.getCached(detectInstance.label, detectedId),
              onLink: () => _linkDetected(detectedId, detectInstance),
              onDismiss: () => setState(() => _dismissedDetectedId = detectedId),
            ),
          ],
          const SizedBox(height: 16),

          // Azure DevOps section
          const Divider(),
          CheckboxListTile(
            value: _hasAdoRef,
            onChanged: (v) {
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
            activeColor: palette.brand,
          ),

          if (_hasAdoRef) ...[
            // With a single instance there is nothing to choose; it was
            // selected when the box was ticked.
            if (adoInstances.length > 1) ...[
              const SizedBox(height: 8),
              SegmentedButton<AdoInstance>(
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
              ),
            ],
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
          const SizedBox(height: 16),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: form,
          ),
        ),
        // Pinned under the scroll area so the button never falls below the
        // fold, and it says exactly what will be sent.
        LogActionBar(
          title: 'Log ${formatDurationLabel(minutes)}',
          subtitle: [what, when].where((s) => s.isNotEmpty).join(' · '),
          disabledReason: disabledReason,
          submitting: entryProvider.isSubmitting,
          onLog: () => _submit(context),
          onDisabledTap: minutes <= 0 && !_useStartEndTime
              ? () => setState(() => _submitAttempted = true)
              : null,
          // Start a running timer instead of logging a fixed duration. The
          // duration inputs are ignored — Harvest counts from now until you
          // stop it.
          onStartTimer: running != null || _isFuture
              ? null
              : () => _startTimer(context),
          timerTooltip: _isFuture
              ? 'Timers only run for today'
              : running == null
                  ? 'Start a timer'
                  : 'Timer already running on ${running.projectName}',
        ),
      ],
    );
  }

  /// True while the clock boxes still hold the prefill's times, so its
  /// captions ("after Standup") still describe them.
  bool get _prefillHolds {
    final p = _prefill;
    return p != null &&
        p.startEnd &&
        _startOverride == p.start &&
        _endOverride == p.end;
  }

  String? _startCaption(StartEndDefaults d) {
    switch (d.startSource) {
      case StartSource.lastEntry:
        final label = d.after?.label;
        return label == null ? null : 'after $label';
      case StartSource.loggedTotal:
        return 'work day start + logged';
      case StartSource.workDayStart:
        return 'work day start';
      case StartSource.hourBeforeNow:
        return '1h before now';
    }
  }
}

/// Yesterday / Today / Tomorrow / Pick, with the date itself at the right.
/// Pick reaches back to 2020 and forward to [latestSelectableDate].
class _DateChips extends StatelessWidget {
  final DateTime date;

  /// −1 yesterday, 0 today, 1 tomorrow; anything else selects Pick.
  final int daysFromToday;

  /// Called with the chosen offset from today.
  final ValueChanged<int> onDay;
  final VoidCallback onPick;

  const _DateChips({
    required this.date,
    required this.daysFromToday,
    required this.onDay,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    // Compact, so all four fit one row beside the date.
    const density = VisualDensity(horizontal: -2, vertical: -2);
    const labelPadding = EdgeInsets.symmetric(horizontal: 4);
    const padding = EdgeInsets.symmetric(horizontal: 4, vertical: 6);
    Widget day(String label, int offset) => ChoiceChip(
          label: Text(label),
          selected: daysFromToday == offset,
          onSelected: (_) => onDay(offset),
          showCheckmark: false,
          visualDensity: density,
          labelPadding: labelPadding,
          padding: padding,
        );
    // One row: the date keeps its width and the chips share the rest,
    // shrinking on a very narrow phone rather than wrapping onto a second
    // line.
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                day('Yesterday', -1),
                const SizedBox(width: 6),
                day('Today', 0),
                const SizedBox(width: 6),
                day('Tomorrow', 1),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Icon(Icons.calendar_today,
                      size: 16, semanticLabel: 'Pick a date'),
                  selected: daysFromToday.abs() > 1,
                  onSelected: (_) => onPick(),
                  showCheckmark: false,
                  tooltip: 'Pick a date',
                  visualDensity: density,
                  labelPadding: labelPadding,
                  padding: padding,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          DateFormat('EEE d MMM').format(date),
          style: TextStyle(fontSize: 12, color: palette.text3),
        ),
      ],
    );
  }
}

/// "From Insights · open after Standup": the form was filled from a stretch
/// on the Insights timeline.
class _FromInsightsLine extends StatelessWidget {
  final String origin;

  const _FromInsightsLine({required this.origin});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, size: 16, color: palette.text3),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'From Insights · '),
                TextSpan(
                  text: origin,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: palette.text),
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// "UPCOMING · Logging ahead. Timers only run for today."
class _LoggingAheadLine extends StatelessWidget {
  const _LoggingAheadLine();

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Row(
      key: const ValueKey('logging-ahead'),
      children: [
        const UpcomingTag(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Logging ahead. Timers only run for today.',
            style: TextStyle(fontSize: 12, color: palette.text2),
          ),
        ),
      ],
    );
  }
}

/// "1h 20m unlogged since Standup ended at 10:40" — Use.
class _GapChip extends StatelessWidget {
  final GapSuggestion gap;
  final VoidCallback onUse;

  const _GapChip({required this.gap, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Container(
      key: const ValueKey('gap-chip'),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: palette.brandTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.brand.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: palette.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${formatDurationLabel(gap.minutes)} unlogged',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: palette.text),
                ),
                TextSpan(
                  text: ' since ${gap.since.label} ended at ${gap.endClock}',
                ),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: palette.text2, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: onUse,
            style: TextButton.styleFrom(foregroundColor: palette.brand600),
            child: const Text('Use'),
          ),
        ],
      ),
    );
  }
}

/// One end of Start & End: −1 · HH:MM · +1, tapping the time for the dial.
/// The nudges speed up while held, like the duration ±.
class _ClockBox extends StatelessWidget {
  final String label;
  final int minutes;
  final String? caption;
  final bool canNudgeUp;
  final ValueChanged<int> onNudge;
  final VoidCallback onTap;

  const _ClockBox({
    required this.label,
    required this.minutes,
    required this.caption,
    required this.canNudgeUp,
    required this.onNudge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);

    Widget nudge(bool up, bool enabled) => HoldToRepeat(
          enabled: enabled,
          semanticLabel: '$label ${up ? 'plus' : 'minus'} 1 minute',
          onStep: (step) => onNudge(up ? step : -step),
          child: Container(
            width: 40,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? palette.brandTint : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              up ? '+1' : '−1',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled ? palette.brand600 : palette.text4,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        border: Border.all(color: palette.borderStrong),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: palette.text3)),
          const SizedBox(height: 2),
          Row(
            children: [
              nudge(false, minutes > 0),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatClock(minutes),
                        semanticsLabel: '$label ${formatClock(minutes)}, tap to pick',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
              nudge(true, canNudgeUp),
            ],
          ),
          SizedBox(
            height: 16,
            child: caption == null
                ? null
                : Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: palette.text3),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A `#123` spotted in the notes while nothing is linked: preview it and
/// offer to link it.
class _DetectedWorkItemCard extends StatelessWidget {
  final String id;
  final AdoInstance instance;
  final AdoWorkItem? item;
  final VoidCallback onLink;
  final VoidCallback onDismiss;

  const _DetectedWorkItemCard({
    required this.id,
    required this.instance,
    required this.item,
    required this.onLink,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final title = item?.title ?? 'Work item #$id';
    return Container(
      key: const ValueKey('detected-work-item'),
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: palette.brand, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 18, color: palette.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Found #$id in your notes · ${instance.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: palette.text3)),
              ],
            ),
          ),
          TextButton(
            onPressed: onLink,
            style: TextButton.styleFrom(foregroundColor: palette.brand600),
            child: const Text('Link'),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            color: palette.text3,
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
          ),
        ],
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
        border: Border.all(color: palette.brand.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: palette.brand600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.brand600,
              ),
            ),
          ),
          if (onUndo != null)
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                foregroundColor: palette.brand600,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Undo'),
            ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            color: palette.brand600,
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
