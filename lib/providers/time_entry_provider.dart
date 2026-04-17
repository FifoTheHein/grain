import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
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

  DateTime selectedDate = DateTime.now();

  Future<void> loadRecentEntries({DateTime? date}) async {
    if (date != null) selectedDate = date;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final dayOfWeek = selectedDate.weekday; // 1=Mon, 7=Sun
      final monday = selectedDate.subtract(Duration(days: dayOfWeek - 1));
      final sunday = monday.add(const Duration(days: 6));
      final selectedStr = fmt.format(selectedDate);

      final all = await _service.fetchTimeEntries(
        from: fmt.format(monday),
        to: fmt.format(sunday),
      );

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
      error = '${e.statusCode}: ${e.message}';
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> update(int entryId, UpdateTimeEntryRequest request) async {
    isSubmitting = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      final updated = await _service.updateTimeEntry(entryId, request);
      final idx = entries.indexWhere((e) => e.id == entryId);
      if (idx != -1) entries[idx] = updated;
      successMessage = 'Updated ${updated.projectName}';
      return true;
    } on HarvestApiException catch (e) {
      error = '${e.statusCode}: ${e.message}';
      return false;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
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
    isSubmitting = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      await _service.deleteTimeEntry(entryId);
      entries.removeWhere((e) => e.id == entryId);
      successMessage = 'Entry deleted';
      return true;
    } on HarvestApiException catch (e) {
      error = '${e.statusCode}: ${e.message}';
      return false;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> submit(CreateTimeEntryRequest request) async {
    isSubmitting = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      final entry = await _service.createTimeEntry(request);
      // Only add to the visible list if it matches the currently viewed date
      if (entry.spentDate ==
          DateFormat('yyyy-MM-dd').format(selectedDate)) {
        entries.insert(0, entry);
      }
      successMessage =
          'Logged ${entry.hours}h on ${entry.projectName} (${entry.spentDate})';
      return true;
    } on HarvestApiException catch (e) {
      error = '${e.statusCode}: ${e.message}';
      return false;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
