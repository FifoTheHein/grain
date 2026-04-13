import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ado_work_item.dart';
import '../models/time_entry.dart';

class AdoService extends ChangeNotifier {
  final http.Client _client;
  final Map<String, AdoWorkItem> _cache = {};
  final Set<String> _pending = {};

  AdoService({http.Client? client}) : _client = client ?? http.Client();

  AdoWorkItem? getCached(String instanceLabel, String workItemId) =>
      _cache['$instanceLabel:$workItemId'];

  Future<void> fetchWorkItem(AdoInstance instance, String workItemId) async {
    final trimmed = workItemId.trim();
    if (trimmed.isEmpty) return;

    final pat = instance.pat;
    if (pat == null || pat.isEmpty) return;

    final cacheKey = '${instance.label}:$trimmed';
    if (_cache.containsKey(cacheKey)) return;
    if (_pending.contains(cacheKey)) return;

    _pending.add(cacheKey);
    try {
      final uri = Uri.parse(
        '${instance.baseUrl}/_apis/wit/workitems/$trimmed'
        r'?api-version=7.0&$select=System.Title,System.State',
      );
      final credentials = base64Encode(utf8.encode(':$pat'));
      final response = await _client.get(uri, headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      });
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _cache[cacheKey] = AdoWorkItem.fromJson(trimmed, json);
        notifyListeners();
      }
    } catch (_) {
      // Silently ignore network errors — caller falls back to permalink display
    } finally {
      _pending.remove(cacheKey);
    }
  }

  Future<void> prefetchForEntries(
    List<dynamic> entries,
    List<AdoInstance> instances,
  ) async {
    for (final entry in entries) {
      final ref = entry.externalReference;
      if (ref == null) continue;
      final workItemId = ref.id as String;
      final permalink = ref.permalink as String? ?? '';
      for (final instance in instances) {
        if (permalink.startsWith(instance.baseUrl)) {
          await fetchWorkItem(instance, workItemId);
          break;
        }
      }
    }
  }
}
