import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/time_entry.dart';
import '../services/ado_service.dart';
import '../services/harvest_service.dart';

class TimeEntryProvider extends ChangeNotifier {
  final HarvestService _service;

  TimeEntryProvider(this._service);

  List<TimeEntry> entries = [];
  Map<String, double> weeklyTotals = {};
  bool isLoading = false;
  bool isSubmitting = false;
  String? error;
  String? successMessage;
  int _loadRecentEntriesRequestId = 0;

  Timer? _refreshTimer;
  static const int _defaultRefreshIntervalMinutes = 15;
  static const _exceptionToStringText = 'Exception';
  static const _nullToStringText = 'null';
  int refreshIntervalMinutes = _defaultRefreshIntervalMinutes;
  static const _kRefreshKey = 'auto_refresh_interval_minutes';

  int _sanitizeRefreshInterval(int? minutes) {
    if (minutes == null || minutes <= 0) {
      return _defaultRefreshIntervalMinutes;
    }
    return minutes;
  }

  DateTime selectedDate = DateTime.now();

  /// Maps non-HTTP failures to a stable, user-friendly message.
  ///
  /// Timeout and invalid-response failures get dedicated messages, while
  /// unknown exceptions fall back to a safe generic message.
  String _errorMessageFrom(Object error) {
    if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    }
    if (error is FormatException) {
      return 'Received an invalid response from the server.';
    }
    final message = error.toString().trim();
    if (message.isEmpty ||
        message == _exceptionToStringText ||
        message == _nullToStringText) {
      return 'An unexpected error occurred. Please try again.';
    }
    return message;
  }

  /// Runs a submit/update/delete mutation with consistent state handling.
  ///
  /// [operation] must return a user-facing success message, which is assigned
  /// to [successMessage] when the mutation succeeds.
  Future<bool> _runMutation(Future<String> operation()) async {
    isSubmitting = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      successMessage = await operation();
      return true;
    } on HarvestApiException catch (e) {
      error = '${e.statusCode}: ${e.message}';
      return false;
    } catch (e) {
      error = _errorMessageFrom(e);
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> loadRecentEntries({DateTime? date, bool silent = false}) async {
    // Don't start a silent refresh while another mutating operation or a
    // foreground load is already in progress, otherwise the silent request can
    // advance `_loadRecentEntriesRequestId` and cause the foreground load to
    // skip clearing `isLoading` in `finally`.
    if (silent && (isSubmitting || isLoading)) return;

    final requestId = ++_loadRecentEntriesRequestId;
    final targetDate = date ?? selectedDate;
    selectedDate = targetDate;

    if (!silent) {
      isLoading = true;
      error = null;
      entries = [];
      weeklyTotals = {};
      notifyListeners();
    }

    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final dayOfWeek = targetDate.weekday; // 1=Mon, 7=Sun
      final monday = targetDate.subtract(Duration(days: dayOfWeek - 1));
      final sunday = monday.add(const Duration(days: 6));
      final selectedStr = fmt.format(targetDate);

      final all = await _service.fetchTimeEntries(
        from: fmt.format(monday),
        to: fmt.format(sunday),
      );

      if (requestId != _loadRecentEntriesRequestId) return;

      error = null;

      // Compute weekly totals
      final totals = <String, double>{};
      for (final e in all) {
        totals[e.spentDate] = (totals[e.spentDate] ?? 0) + e.hours;
      }
      weeklyTotals = totals;

      // Filter to selected day only
      entries = all.where((e) => e.spentDate == selectedStr).toList();
      entries.sort((a, b) => b.spentDate.compareTo(a.spentDate));
    } on HarvestApiException catch (e) {
      if (requestId != _loadRecentEntriesRequestId) return;
      if (!silent) error = '${e.statusCode}: ${e.message}';
    } catch (e) {
      if (requestId != _loadRecentEntriesRequestId) return;
      if (!silent) error = _errorMessageFrom(e);
    } finally {
      if (requestId == _loadRecentEntriesRequestId) {
        if (!silent) isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Reads the persisted interval and starts the background refresh timer.
  /// Call once after the initial [loadRecentEntries] in main.dart.
  Future<void> startAutoRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    refreshIntervalMinutes =
        _sanitizeRefreshInterval(prefs.getInt(_kRefreshKey));
    _restartTimer();
  }

  /// Updates the interval, persists it, and restarts the timer immediately.
  Future<void> setRefreshInterval(int minutes) async {
    final sanitizedMinutes = _sanitizeRefreshInterval(minutes);
    refreshIntervalMinutes = sanitizedMinutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRefreshKey, sanitizedMinutes);
    _restartTimer();
    notifyListeners();
  }

  void _restartTimer() {
    _refreshTimer?.cancel();
    refreshIntervalMinutes =
        _sanitizeRefreshInterval(refreshIntervalMinutes);
    _refreshTimer = Timer.periodic(
      Duration(minutes: refreshIntervalMinutes),
      (_) => loadRecentEntries(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<bool> update(int entryId, UpdateTimeEntryRequest request) async {
    return _runMutation(() async {
      final updated = await _service.updateTimeEntry(entryId, request);
      // Invalidate any concurrent silent refresh so it doesn't overwrite our
      // locally-applied change when its response eventually arrives.
      _loadRecentEntriesRequestId++;
      final idx = entries.indexWhere((e) => e.id == entryId);
      if (idx != -1) {
        final old = entries[idx];
        weeklyTotals[old.spentDate] =
            ((weeklyTotals[old.spentDate] ?? 0) - old.hours)
                .clamp(0.0, double.infinity)
                .toDouble();
        weeklyTotals[updated.spentDate] =
            (weeklyTotals[updated.spentDate] ?? 0) + updated.hours;
        if (updated.spentDate == old.spentDate) {
          entries[idx] = updated;
        } else {
          entries.removeAt(idx);
        }
      }
      return 'Updated ${updated.projectName}';
    });
  }

  Stream<({int done, int total, int failed})> migrateAdoReferences(
    AdoService adoService,
    List<AdoInstance> instances,
  ) async* {
    // Fetch the full Mon–Sun work week for the migration candidates.
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final fmt = DateFormat('yyyy-MM-dd');
    List<TimeEntry> weekEntries;
    try {
      weekEntries = await _service.fetchTimeEntries(
        from: fmt.format(monday),
        to: fmt.format(sunday),
      );
    } catch (_) {
      weekEntries = [];
    }

    // Extended learning phase: scan the past 28 days for any natively-created
    // Harvest entries (permalink contains ADO project GUID rather than project
    // name) so the correct Harvest connection GUID is available even when all
    // current-week entries were created by this app. Entries from the current
    // week are included in this scan, so no duplicate fetch is needed.
    List<TimeEntry> extendedEntries;
    try {
      final past28 = now.subtract(const Duration(days: 28));
      extendedEntries = await _service.fetchTimeEntries(
        from: fmt.format(past28),
        to: fmt.format(now),
      );
    } catch (_) {
      extendedEntries = weekEntries; // fall back to the week we already have
    }
    for (final entry in extendedEntries) {
      final ref = entry.externalReference;
      if (ref == null) continue;
      final permalink = ref.permalink ?? '';
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          adoService.learnHarvestGuid(inst.label, ref.id, permalink);
          break;
        }
      }
    }

    // Candidates:
    //   1. Entries with a plain numeric external reference (not yet composite).
    //   2. Entries already composite but using the wrong GUID — i.e. the ADO
    //      project GUID instead of the Harvest connection GUID.
    //   3. Entries already composite but with a corrupted work item ID segment
    //      (caused by a previous migration run before parseWorkItemId was used).
    final candidates = weekEntries.where((e) {
      final ref = e.externalReference;
      if (ref == null) return false;
      final id = ref.id;
      if (!id.startsWith('AzureDevOps_')) return true; // plain numeric

      // Already composite — check whether:
      //   (a) the embedded GUID is the wrong one, OR
      //   (b) the work item ID segment is not a plain number (corrupted by a
      //       previous migration run that embedded a full composite ID string).
      final permalink = ref.permalink ?? '';
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          final correctGuid = adoService.getCachedHarvestGuid(inst.label);
          final parts = id.split('_');
          // Check (b): last segment must be a pure integer
          final lastSegmentCorrupt =
              parts.isNotEmpty && int.tryParse(parts.last) == null;
          if (lastSegmentCorrupt) return true;
          if (correctGuid == null) return false; // can't verify GUID — leave alone
          // Check (a): wrong GUID
          return parts.length >= 2 && parts[1] != correctGuid;
        }
      }
      return false;
    }).toList();

    int done = 0;
    int failed = 0;
    final total = candidates.length;
    yield (done: done, total: total, failed: failed);

    for (final entry in candidates) {
      final ref = entry.externalReference!;
      final workItemId = AdoService.parseWorkItemId(ref.id);
      final permalink = ref.permalink ?? '';

      AdoInstance? instance;
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          instance = inst;
          break;
        }
      }

      if (instance == null || instance.pat == null) {
        failed++;
        done++;
        yield (done: done, total: total, failed: failed);
        continue;
      }

      try {
        await Future.wait([
          adoService.fetchWorkItem(instance, workItemId),
          adoService.getHarvestConnectionGuid(instance),
        ]);

        final projectGuid = await adoService.getHarvestConnectionGuid(instance);
        if (projectGuid == null) {
          failed++;
          done++;
          yield (done: done, total: total, failed: failed);
          continue;
        }

        final cachedItem = adoService.getCached(instance.label, workItemId);
        final workItemType = cachedItem?.workItemType ?? 'Work Item';
        final compositeId =
            'AzureDevOps_${projectGuid}_${workItemType}_$workItemId';

        final request = UpdateTimeEntryRequest(
          projectId: entry.projectId,
          taskId: entry.taskId,
          spentDate: entry.spentDate,
          hours: entry.hours,
          notes: entry.notes,
          externalReference: ExternalReference(
            id: compositeId,
            permalink: ref.permalink,
          ),
        );

        final success = await update(entry.id, request);
        if (!success) failed++;
      } catch (_) {
        failed++;
      }

      done++;
      yield (done: done, total: total, failed: failed);
    }
  }

  Future<bool> delete(int entryId) async {
    return _runMutation(() async {
      await _service.deleteTimeEntry(entryId);
      // Invalidate any concurrent silent refresh so it doesn't overwrite the
      // deletion when its response eventually arrives.
      _loadRecentEntriesRequestId++;
      final removedIndex = entries.indexWhere((e) => e.id == entryId);
      if (removedIndex != -1) {
        final removed = entries[removedIndex];
        weeklyTotals[removed.spentDate] =
            ((weeklyTotals[removed.spentDate] ?? 0) - removed.hours)
                .clamp(0.0, double.infinity)
                .toDouble();
        entries.removeAt(removedIndex);
      }
      return 'Entry deleted';
    });
  }

  Future<bool> submit(CreateTimeEntryRequest request) async {
    return _runMutation(() async {
      final entry = await _service.createTimeEntry(request);
      // Invalidate any concurrent silent refresh so it doesn't overwrite our
      // locally-inserted entry when its response eventually arrives.
      _loadRecentEntriesRequestId++;
      weeklyTotals[entry.spentDate] =
          (weeklyTotals[entry.spentDate] ?? 0) + entry.hours;
      // Only add to the visible list if it matches the currently viewed date
      if (entry.spentDate ==
          DateFormat('yyyy-MM-dd').format(selectedDate)) {
        entries.insert(0, entry);
      }
      return 'Logged ${entry.hours}h on ${entry.projectName} (${entry.spentDate})';
    });
  }
}
