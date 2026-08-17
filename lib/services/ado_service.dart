import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ado_work_item.dart';
import '../models/time_entry.dart';

class AdoService extends ChangeNotifier {
  final http.Client _client;
  final Map<String, AdoWorkItem> _cache = {};
  final Set<String> _pending = {};
  final Map<String, String> _projectGuidCache = {}; // label -> ADO project guid
  final Map<String, String> _harvestConnectionGuidCache = {}; // label -> Harvest connection guid

  AdoService({http.Client? client}) : _client = client ?? http.Client();

  /// Loads any previously-persisted Harvest connection GUIDs from localStorage.
  /// Call once on startup so the correct GUID is available before the first
  /// Log Time submission, even when no native Harvest entries are visible.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith('ado_harvest_guid_')) {
        final label = key.substring('ado_harvest_guid_'.length);
        final guid = prefs.getString(key);
        if (guid != null) {
          _harvestConnectionGuidCache[label] = guid;
        }
      }
    }
  }

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
        '?api-version=7.0&\$select=$_workItemFields',
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

  /// Fields requested for every work item, single or batched.
  static const _workItemFields =
      'System.Title,System.State,System.CreatedBy,System.WorkItemType,'
      'System.TeamProject,System.AreaPath,System.IterationPath,'
      'System.AssignedTo,System.Tags,System.Parent';

  /// ADO refuses more than 200 ids in one batch read.
  static const _batchSize = 200;

  final Map<String, List<AdoWorkItem>> _assignedCache = {}; // label -> items
  final Set<String> _assignedLoading = {};
  final Map<String, String> _assignedErrors = {};

  List<AdoWorkItem>? getCachedAssigned(String instanceLabel) =>
      _assignedCache[instanceLabel];

  bool isLoadingAssigned(String instanceLabel) =>
      _assignedLoading.contains(instanceLabel);

  String? assignedError(String instanceLabel) => _assignedErrors[instanceLabel];

  /// Fetches the work items assigned to the PAT's owner, most recently changed
  /// first, and caches them per instance. Returns the cached list unless
  /// [refresh] is set.
  ///
  /// Two calls: WIQL for the ids, then one field-limited batch read per 200
  /// ids — WIQL itself only ever returns ids.
  Future<List<AdoWorkItem>> fetchAssignedWorkItems(
    AdoInstance instance, {
    bool refresh = false,
    bool includeCompleted = false,
  }) async {
    final label = instance.label;
    if (!refresh && _assignedCache.containsKey(label)) {
      return _assignedCache[label]!;
    }
    final pat = instance.pat;
    if (pat == null || pat.isEmpty) {
      _assignedErrors[label] = 'No PAT configured for ${instance.label}';
      notifyListeners();
      return const [];
    }
    if (_assignedLoading.contains(label)) return _assignedCache[label] ?? const [];

    _assignedLoading.add(label);
    _assignedErrors.remove(label);
    notifyListeners();

    try {
      final clauses = <String>['[System.AssignedTo] = @Me'];
      if (!includeCompleted) {
        clauses.addAll([
          "[System.State] <> 'Closed'",
          "[System.State] <> 'Removed'",
          "[System.State] <> 'Done'",
        ]);
      }
      final wiql = 'SELECT [System.Id] FROM WorkItems WHERE '
          '${clauses.join(' AND ')} ORDER BY [System.ChangedDate] DESC';

      final credentials = base64Encode(utf8.encode(':$pat'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      };

      final wiqlResponse = await _client.post(
        Uri.parse('${instance.baseUrl}/_apis/wit/wiql?api-version=7.0'),
        headers: headers,
        body: jsonEncode({'query': wiql}),
      );
      if (wiqlResponse.statusCode != 200) {
        throw Exception('ADO query failed: ${wiqlResponse.statusCode}');
      }

      final wiqlJson = jsonDecode(wiqlResponse.body) as Map<String, dynamic>;
      final ids = (wiqlJson['workItems'] as List<dynamic>? ?? [])
          .map((w) => (w as Map<String, dynamic>)['id'])
          .whereType<num>()
          .map((n) => n.toInt())
          .toList();

      final items = <AdoWorkItem>[];
      for (var i = 0; i < ids.length; i += _batchSize) {
        final chunk = ids.sublist(
            i, i + _batchSize > ids.length ? ids.length : i + _batchSize);
        final batchUri = Uri.parse(
          '${instance.baseUrl}/_apis/wit/workitems'
          '?ids=${chunk.join(',')}&fields=$_workItemFields&api-version=7.0',
        );
        final batchResponse = await _client.get(batchUri, headers: headers);
        if (batchResponse.statusCode != 200) {
          throw Exception('ADO fetch failed: ${batchResponse.statusCode}');
        }
        final batchJson =
            jsonDecode(batchResponse.body) as Map<String, dynamic>;
        for (final raw in (batchJson['value'] as List<dynamic>? ?? [])) {
          final map = raw as Map<String, dynamic>;
          final id = (map['id'] as num).toInt().toString();
          final item = AdoWorkItem.fromJson(id, map);
          items.add(item);
          // Seed the single-item cache so the preview is instant on pick.
          _cache['$label:$id'] = item;
        }
      }

      _assignedCache[label] = items;
      return items;
    } catch (e) {
      _assignedErrors[label] = e.toString();
      return _assignedCache[label] ?? const [];
    } finally {
      _assignedLoading.remove(label);
      notifyListeners();
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

  /// Returns true when [permalink] was generated by Harvest's native ADO
  /// integration — identified by the second path segment being a UUID (the
  /// project GUID). App-generated permalinks use the project name instead.
  static bool _isNativePermalink(String permalink) {
    try {
      final segs = Uri.parse(permalink).pathSegments;
      if (segs.length < 2) return false;
      final seg = segs[1];
      return seg.length == 36 &&
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
                  caseSensitive: false)
              .hasMatch(seg);
    } catch (_) {
      return false;
    }
  }

  /// Extracts the Harvest connection GUID from a known-native composite ID and
  /// caches it for [instanceLabel]. Only learns from entries whose permalink
  /// contains the ADO project GUID (i.e. was created by Harvest natively).
  void learnHarvestGuid(
      String instanceLabel, String compositeId, String permalink) {
    if (_harvestConnectionGuidCache.containsKey(instanceLabel)) return;
    if (!compositeId.startsWith('AzureDevOps_')) return;
    if (!_isNativePermalink(permalink)) return;
    final parts = compositeId.split('_');
    if (parts.length >= 4 && parts[1].length == 36 && parts[1].contains('-')) {
      final guid = parts[1];
      _harvestConnectionGuidCache[instanceLabel] = guid;
      // Persist so it survives page reloads — fire-and-forget
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('ado_harvest_guid_$instanceLabel', guid),
      );
      notifyListeners();
    }
  }

  String? getCachedHarvestGuid(String instanceLabel) =>
      _harvestConnectionGuidCache[instanceLabel];

  /// Manually sets (and persists) the Harvest connection GUID for [instanceLabel].
  /// Use this when auto-detection has not worked and the GUID is known.
  Future<void> setHarvestGuid(String instanceLabel, String guid) async {
    _harvestConnectionGuidCache[instanceLabel] = guid;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ado_harvest_guid_$instanceLabel', guid);
    notifyListeners();
  }

  /// Returns the Harvest connection GUID for [instance] if one has been learned
  /// from a native entry, otherwise falls back to fetching the ADO project GUID.
  Future<String?> getHarvestConnectionGuid(AdoInstance instance) async {
    if (_harvestConnectionGuidCache.containsKey(instance.label)) {
      return _harvestConnectionGuidCache[instance.label];
    }
    return fetchProjectGuid(instance);
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

  Future<double?> fetchCompletedWork(
      AdoInstance instance, String workItemId) async {
    final pat = instance.pat;
    if (pat == null || pat.isEmpty) return null;
    try {
      final uri = Uri.parse(
        '${instance.baseUrl}/_apis/wit/workitems/$workItemId'
        '?fields=Microsoft.VSTS.Scheduling.CompletedWork&api-version=7.0',
      );
      final credentials = base64Encode(utf8.encode(':$pat'));
      final response = await _client.get(uri, headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      });
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final fields = json['fields'] as Map<String, dynamic>?;
        final value = fields?['Microsoft.VSTS.Scheduling.CompletedWork'];
        if (value is num) return value.toDouble();
      }
    } catch (_) {
      // Silently ignore — caller treats null as 0
    }
    return null;
  }

  Future<void> patchCompletedWork(
      AdoInstance instance, String workItemId, double newTotal) async {
    final pat = instance.pat;
    if (pat == null || pat.isEmpty) throw Exception('No PAT configured');
    final uri = Uri.parse(
      '${instance.baseUrl}/_apis/wit/workitems/$workItemId?api-version=7.0',
    );
    final credentials = base64Encode(utf8.encode(':$pat'));
    final response = await _client.patch(uri,
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/json-patch+json',
        },
        body: jsonEncode([
          {
            'op': 'add',
            'path': '/fields/Microsoft.VSTS.Scheduling.CompletedWork',
            'value': newTotal,
          }
        ]));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('ADO update failed: ${response.statusCode}');
    }
  }

  /// Fetches the current Completed Work value and adds [hoursToAdd] to it.
  Future<void> addCompletedWork(
      AdoInstance instance, String workItemId, double hoursToAdd) async {
    final current = await fetchCompletedWork(instance, workItemId) ?? 0;
    final newTotal = (current + hoursToAdd).clamp(0.0, double.infinity);
    await patchCompletedWork(instance, workItemId, newTotal);
  }

  Future<void> prefetchForEntries(
    List<dynamic> entries,
    List<AdoInstance> instances,
  ) async {
    for (final entry in entries) {
      final ref = entry.externalReference;
      if (ref == null) continue;
      final rawId = ref.id as String;
      final workItemId = parseWorkItemId(rawId);
      final permalink = ref.permalink as String? ?? '';
      for (final instance in instances) {
        if (instance.matchesPermalink(permalink)) {
          learnHarvestGuid(instance.label, rawId, permalink);
          await fetchWorkItem(instance, workItemId);
          break;
        }
      }
    }
  }
}
