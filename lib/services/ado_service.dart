import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ado_work_item.dart';
import '../models/time_entry.dart';

class AdoService extends ChangeNotifier {
  final http.Client _client;
  final Map<String, AdoWorkItem> _cache = {};
  final Set<String> _pending = {};
  final Map<String, String> _projectGuidCache = {}; // label -> guid

  AdoService({http.Client? client}) : _client = client ?? http.Client();

  AdoWorkItem? getCached(String instanceLabel, String workItemId) =>
      _cache['$instanceLabel:$workItemId'];

  bool isPending(String instanceLabel, String workItemId) =>
      _pending.contains('$instanceLabel:$workItemId');

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
        r'?api-version=7.0&$select=System.Title,System.State,System.CreatedBy,System.WorkItemType',
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

  Future<String?> fetchProjectGuid(AdoInstance instance) async {
    final cacheKey = instance.label;
    if (_projectGuidCache.containsKey(cacheKey)) {
      return _projectGuidCache[cacheKey];
    }

    final pat = instance.pat;
    if (pat == null || pat.isEmpty) return null;

    try {
      final uri = Uri.parse(instance.baseUrl);
      final segments = uri.pathSegments;
      if (segments.length < 2) return null;

      final org = segments[0];
      final project = segments[1]; // Uri.parse auto-decodes percent-encoding

      final apiUri = Uri.parse(
        'https://dev.azure.com/$org/_apis/projects/${Uri.encodeComponent(project)}?api-version=7.1',
      );
      final credentials = base64Encode(utf8.encode(':$pat'));
      final response = await _client.get(apiUri, headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      });
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final guid = json['id'] as String?;
        if (guid != null) {
          _projectGuidCache[cacheKey] = guid;
          return guid;
        }
      }
    } catch (_) {
      // Silently ignore network errors — caller falls back gracefully
    }
    return null;
  }

  static String parseWorkItemId(String refId) {
    // Composite format: AzureDevOps_{guid}_{type}_{numericId}
    // Note: type can contain spaces, so we need to extract the numeric ID from the end
    if (refId.startsWith('AzureDevOps_')) {
      // Work item type can have spaces; numeric ID is always the final token
      final parts = refId.split('_');
      if (parts.length >= 4) {
        // Format: ['AzureDevOps', guid, 'type (with spaces)', 'numericId']
        // We need to find where the numeric ID starts
        // The numeric ID is always the last part that is purely numeric
        for (int i = parts.length - 1; i >= 3; i--) {
          if (int.tryParse(parts[i]) != null) {
            return parts[i];
          }
        }
      }
    }
    return refId; // already a plain numeric string
  }

  static String? parseWorkItemType(String refId) {
    // Extract work item type from composite ID: AzureDevOps_{guid}_{type}_{numericId}
    // Example: AzureDevOps_4b6afb17-0252-4bf2-b64a-cf7227b6f0d6_User Story_42292
    if (refId.startsWith('AzureDevOps_')) {
      // Find the last numeric part (the work item ID)
      int lastNumericIdx = -1;
      final parts = refId.split('_');
      for (int i = parts.length - 1; i >= 0; i--) {
        if (int.tryParse(parts[i]) != null) {
          lastNumericIdx = i;
          break;
        }
      }

      if (lastNumericIdx > 2) {
        // The type is everything between index 2 and lastNumericIdx
        // (index 0 = 'AzureDevOps', index 1 = guid, indices 2..lastNumericIdx-1 = type)
        return parts.sublist(2, lastNumericIdx).join('_').replaceAll('_', ' ');
      }
    }
    return null;
  }

  Future<void> prefetchForEntries(
    List<dynamic> entries,
    List<AdoInstance> instances,
  ) async {
    for (final entry in entries) {
      final ref = entry.externalReference;
      if (ref == null) continue;
      final workItemId = parseWorkItemId(ref.id as String);
      final permalink = ref.permalink as String? ?? '';
      for (final instance in instances) {
        if (instance.matchesPermalink(permalink)) {
          await fetchWorkItem(instance, workItemId);
          break;
        }
      }
    }
  }
}
