import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/time_entry.dart';
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
