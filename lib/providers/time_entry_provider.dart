import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/time_entry.dart';
import '../services/ado_service.dart';
import '../services/harvest_service.dart';

class TimeEntryProvider extends ChangeNotifier {
  final HarvestService _service;

  TimeEntryProvider(this._service);

  List<TimeEntry> entries = [];
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
      final from = DateFormat('yyyy-MM-dd').format(selectedDate);
      final all = await _service.fetchTimeEntries(from: from);
      // Filter to just the selected date
      entries = all.where((e) => e.spentDate == from).toList();
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
    // Fetch the full Mon–Fri work week regardless of the currently displayed date
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

    // Learn Harvest connection GUIDs from any natively-created entries first,
    // so the correct GUID is available before we build composite IDs below.
    for (final entry in weekEntries) {
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
    final candidates = weekEntries.where((e) {
      final ref = e.externalReference;
      if (ref == null) return false;
      final id = ref.id;
      if (!id.startsWith('AzureDevOps_')) return true; // plain numeric

      // Already composite — check whether the embedded GUID is the correct one.
      final permalink = ref.permalink ?? '';
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          final correctGuid = adoService.getCachedHarvestGuid(inst.label);
          if (correctGuid == null) return false; // can't verify — leave alone
          final parts = id.split('_');
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
