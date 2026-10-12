import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ado_work_item.dart';
import '../models/calendar_event.dart';
import '../models/ics_parser.dart';
import '../models/meeting.dart';
import '../models/time_entry.dart';
import '../services/ado_service.dart';
import '../services/calendar_service.dart';
import '../services/harvest_service.dart';
import '../services/meeting_importer.dart';
import 'ado_instance_provider.dart';
import 'assignment_provider.dart';
import 'mapping_rule_provider.dart';
import 'meeting_rule_provider.dart';
import 'time_entry_provider.dart';

/// Imports finished meetings from an ICS calendar into Harvest.
///
/// Off the web it fetches the feed itself and runs whenever the time entries
/// refresh. On the web the feed cannot be fetched (Outlook sends no CORS
/// headers), so an uploaded .ics goes through the same pipeline instead.
class CalendarImportProvider extends ChangeNotifier {
  static const _urlKey = 'calendar_ics_url';
  static const _autoLogKey = 'calendar_auto_log';
  static const _projectKey = 'calendar_default_project_id';
  static const _taskKey = 'calendar_default_task_id';
  static const _sinceKey = 'calendar_import_since';
  static const _lookbackKey = 'calendar_lookback_hours';
  static const _adoInstanceKey = 'calendar_ado_instance';
  static const _ledgerKey = 'calendar_logged_v1';

  static const ledgerRetention = Duration(days: 30);
  static const minSyncInterval = Duration(minutes: 5);
  static const lookbackChoices = [6, 24, 72, 168];

  final HarvestService _harvest;
  final CalendarService _calendar;
  final TimeEntryProvider _entries;
  final AdoService _ado;
  final AdoInstanceProvider _adoInstances;
  final AssignmentProvider _assignments;
  final MappingRuleProvider _workItemRules;
  final MeetingRuleProvider _meetingRules;

  CalendarImportProvider({
    required HarvestService harvest,
    required TimeEntryProvider entries,
    required AdoService ado,
    required AdoInstanceProvider adoInstances,
    required AssignmentProvider assignments,
    required MappingRuleProvider workItemRules,
    required MeetingRuleProvider meetingRules,
    CalendarService? calendar,
  })  : _harvest = harvest,
        _calendar = calendar ?? CalendarService(),
        _entries = entries,
        _ado = ado,
        _adoInstances = adoInstances,
        _assignments = assignments,
        _workItemRules = workItemRules,
        _meetingRules = meetingRules {
    _entries.addListener(_onEntriesChanged);
  }

  /// Whether this platform can fetch the feed URL itself.
  static bool get canFetchUrl => !kIsWeb;

  String _icsUrl = '';
  bool _autoLog = false;
  int? _defaultProjectId;
  int? _defaultTaskId;
  DateTime? _importSince;
  int _lookbackHours = 24;
  String? _adoInstanceLabel;
  final Map<String, String> _ledger = {};

  String get icsUrl => _icsUrl;
  bool get autoLog => _autoLog;
  int? get defaultProjectId => _defaultProjectId;
  int? get defaultTaskId => _defaultTaskId;
  int get lookbackHours => _lookbackHours;
  String? get adoInstanceLabel => _adoInstanceLabel;

  /// Meetings from before this are never logged, so switching auto-log on
  /// does not back-fill weeks of history.
  DateTime? get importSince => _importSince;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;
  MeetingImportResult? _lastResult;
  MeetingImportResult? get lastResult => _lastResult;
  String? _error;
  String? get error => _error;

  /// Meetings waiting for a project/task, from the last sync.
  List<CalendarEvent> get pending => _lastResult?.pending ?? const [];

  DateTime? _lastSeenFetch;
  DateTime? _lastAutoSync;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _icsUrl = prefs.getString(_urlKey) ?? '';
    _autoLog = prefs.getBool(_autoLogKey) ?? false;
    _defaultProjectId = prefs.getInt(_projectKey);
    _defaultTaskId = prefs.getInt(_taskKey);
    final since = prefs.getString(_sinceKey);
    _importSince = since == null ? null : DateTime.tryParse(since);
    _lookbackHours = prefs.getInt(_lookbackKey) ?? 24;
    _adoInstanceLabel = prefs.getString(_adoInstanceKey);
    _ledger.clear();
    final raw = prefs.getString(_ledgerKey);
    if (raw != null) {
      try {
        _ledger.addAll((jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String)));
      } catch (_) {
        // Corrupt ledger — Harvest-side dedup still guards against repeats.
      }
    }
    _pruneLedger();
    notifyListeners();
    // The first refresh may have landed before these settings loaded.
    _onEntriesChanged(force: true);
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  Future<void> setIcsUrl(String url) async {
    _icsUrl = url.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, _icsUrl);
  }

  Future<void> setAutoLog(bool value) async {
    _autoLog = value;
    final prefs = await SharedPreferences.getInstance();
    if (value && _importSince == null) {
      _importSince = DateTime.now().toUtc();
      await prefs.setString(_sinceKey, _importSince!.toIso8601String());
    }
    notifyListeners();
    await prefs.setBool(_autoLogKey, value);
    if (value) _lastAutoSync = null;
  }

  /// Moves the start of the import window — "start of today" to pick up this
  /// morning's meetings, for instance.
  Future<void> setImportSince(DateTime since) async {
    _importSince = since.toUtc();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sinceKey, _importSince!.toIso8601String());
  }

  Future<void> setDefaultTarget(int? projectId, int? taskId) async {
    _defaultProjectId = projectId;
    _defaultTaskId = taskId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (projectId == null || taskId == null) {
      await prefs.remove(_projectKey);
      await prefs.remove(_taskKey);
    } else {
      await prefs.setInt(_projectKey, projectId);
      await prefs.setInt(_taskKey, taskId);
    }
  }

  Future<void> setLookbackHours(int hours) async {
    _lookbackHours = hours;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lookbackKey, hours);
  }

  Future<void> setAdoInstanceLabel(String? label) async {
    _adoInstanceLabel = label;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (label == null) {
      await prefs.remove(_adoInstanceKey);
    } else {
      await prefs.setString(_adoInstanceKey, label);
    }
  }

  // ─── Sync ────────────────────────────────────────────────────────────────

  /// Runs an auto-sync when the time entries have just been re-read, at most
  /// once per [minSyncInterval].
  void _onEntriesChanged({bool force = false}) {
    final fetched = _entries.fetchedAt;
    if (fetched == _lastSeenFetch && !force) return;
    _lastSeenFetch = fetched;
    if (!_autoLog || !canFetchUrl || _icsUrl.isEmpty || _isSyncing) return;
    final last = _lastAutoSync;
    if (last != null && DateTime.now().difference(last) < minSyncInterval) {
      return;
    }
    _lastAutoSync = DateTime.now();
    sync();
  }

  /// Fetches the feed (or uses [icsText] from an upload) and logs every
  /// finished meeting not already in Harvest. Returns the result, or null when
  /// it could not run.
  ///
  /// An upload is explicit, so it imports whatever the file holds inside the
  /// lookback, without waiting for [importSince].
  Future<MeetingImportResult?> sync({String? icsText}) async {
    if (_isSyncing) return null;
    _isSyncing = true;
    _error = null;
    notifyListeners();
    try {
      final text = icsText ?? await _calendar.fetchIcs(_icsUrl);
      final now = DateTime.now().toUtc();
      var windowStart = now.subtract(Duration(hours: _lookbackHours));
      final since = _importSince;
      if (icsText == null && since != null && since.isAfter(windowStart)) {
        windowStart = since;
      }
      final events = await compute(_parseInBackground,
          (text: text, from: windowStart, to: now));

      if (_assignments.projects.isEmpty) await _assignments.load();

      final result = await _importer().run(
        events: events,
        windowStart: windowStart,
        now: now,
        ledger: _ledger.keys.toSet(),
        tracksByStartEnd: _entries.tracksByStartEnd,
        markLogged: _markLogged,
      );
      _lastResult = result;
      _lastSyncAt = DateTime.now();
      if (result.failed.isNotEmpty) {
        _error = 'Could not log ${result.failed.length} meeting(s): '
            '${result.failed.first.message}';
      }
      if (result.logged.isNotEmpty) {
        await _entries.loadRecentEntries(silent: true);
      }
      return result;
    } on CalendarFetchException catch (e) {
      _error = e.message;
    } on HarvestApiException catch (e) {
      _error = 'Harvest ${e.statusCode}: ${e.message}';
    } catch (e) {
      _error = kIsWeb && icsText == null
          ? 'The browser blocked the calendar feed. Upload an .ics file instead.'
          : 'Calendar import failed: $e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return null;
  }

  /// Logs a pending meeting to a project/task picked by hand.
  Future<String?> logPending(
      CalendarEvent event, int projectId, int taskId) async {
    final plan = await _planFor(
      event,
      MeetingTarget(
        projectId: projectId,
        taskId: taskId,
        source: MeetingTargetSource.manual,
      ),
    );
    final error = await _importer().logOne(event, plan,
        tracksByStartEnd: _entries.tracksByStartEnd, markLogged: _markLogged);
    if (error == null) {
      _removePending(event);
      await _entries.loadRecentEntries(silent: true);
    }
    return error;
  }

  /// Marks a pending meeting as handled without logging it, so it stops
  /// coming back.
  Future<void> skipPending(CalendarEvent event) async {
    await _markLogged(event);
    _removePending(event);
  }

  void _removePending(CalendarEvent event) {
    final result = _lastResult;
    if (result == null) return;
    _lastResult = MeetingImportResult(
      logged: result.logged,
      alreadyLogged: result.alreadyLogged,
      skipped: result.skipped,
      pending: result.pending
          .where((e) => meetingLedgerKey(e) != meetingLedgerKey(event))
          .toList(),
      failed: result.failed,
    );
    notifyListeners();
  }

  MeetingImporter _importer() =>
      MeetingImporter(harvest: _harvest, resolve: _resolve);

  bool _isAssigned(int projectId, int taskId) => _assignments.projects.any(
      (p) => p.id == projectId && p.tasks.any((t) => t.id == taskId));

  /// The ADO instance work item numbers in titles are looked up in: the one
  /// chosen in Settings, else the first with a PAT.
  AdoInstance? get _adoInstance {
    final withPat =
        _adoInstances.instances.where((i) => i.pat?.isNotEmpty ?? false);
    return withPat.firstWhereOrNull((i) => i.label == _adoInstanceLabel) ??
        withPat.firstOrNull;
  }

  Future<MeetingPlan?> _resolve(CalendarEvent e) async {
    final fallbackProject = _defaultProjectId;
    final fallbackTask = _defaultTaskId;
    final workItem = await _workItemFor(e);
    final target = chooseMeetingTarget(
      meetingMatch: _meetingRules.matchContext(meetingMatchContext(e)),
      workItemMatch: workItem == null
          ? null
          : _workItemRules.matchIgnoringToggle(workItem.item),
      fallback: fallbackProject == null || fallbackTask == null
          ? null
          : (projectId: fallbackProject, taskId: fallbackTask),
      isAssigned: _isAssigned,
    );
    if (target == null) return null;
    return _planFor(e, target, workItem: workItem);
  }

  /// The work item named in the meeting title, if it resolves.
  Future<({AdoInstance instance, String id, AdoWorkItem item})?> _workItemFor(
      CalendarEvent e) async {
    final id = workItemIdFromTitle(e.summary);
    final instance = _adoInstance;
    if (id == null || instance == null) return null;
    await _ado.fetchWorkItem(instance, id);
    final item = _ado.getCached(instance.label, id);
    if (item == null) return null;
    return (instance: instance, id: id, item: item);
  }

  Future<MeetingPlan> _planFor(
    CalendarEvent e,
    MeetingTarget target, {
    ({AdoInstance instance, String id, AdoWorkItem item})? workItem,
  }) async {
    workItem ??= await _workItemFor(e);
    final notes = meetingNoteFor(e, target);
    if (workItem == null) {
      return MeetingPlan(
        target: target,
        notes: notes,
        externalReference: meetingReference(e),
      );
    }
    final link = await _ado.workItemReference(workItem.instance, workItem.id);
    final instance = workItem.instance;
    final id = workItem.id;
    return MeetingPlan(
      target: target,
      notes: '${link.notePrefix} - $notes',
      externalReference: link.ref,
      afterLogged: (hours) async {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('ado_update_completed_work') ?? true) {
          await _ado.addCompletedWork(instance, id, hours);
        }
      },
    );
  }

  // ─── Ledger ──────────────────────────────────────────────────────────────

  Future<void> _markLogged(CalendarEvent e) async {
    _ledger[meetingLedgerKey(e)] = meetingSpentDate(e);
    await _persistLedger();
  }

  void _pruneLedger() {
    final cutoff = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(ledgerRetention));
    _ledger.removeWhere((_, date) => date.compareTo(cutoff) < 0);
  }

  Future<void> _persistLedger() async {
    _pruneLedger();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ledgerKey, jsonEncode(_ledger));
  }

  @override
  void dispose() {
    _entries.removeListener(_onEntriesChanged);
    super.dispose();
  }
}

/// Parsing a several-megabyte feed takes a second or more, so it runs off the
/// UI isolate where the platform allows.
List<CalendarEvent> _parseInBackground(
        ({String text, DateTime from, DateTime to}) args) =>
    parseIcs(args.text, windowStart: args.from, windowEnd: args.to);
