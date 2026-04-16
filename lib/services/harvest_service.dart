import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/project_assignment.dart';
import '../models/time_entry.dart';

class HarvestApiException implements Exception {
  final int statusCode;
  final String message;

  const HarvestApiException(this.statusCode, this.message);

  @override
  String toString() => 'HarvestApiException($statusCode): $message';
}

class HarvestService {
  final http.Client _client;

  HarvestService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token =
        prefs.getString('harvest_token') ?? AppConfig.defaultToken;
    final accountId =
        prefs.getString('harvest_account_id') ?? AppConfig.defaultAccountId;
    return {
      'Authorization': 'Bearer $token',
      'Harvest-Account-ID': accountId,
      'User-Agent': AppConfig.userAgent,
      'Content-Type': 'application/json',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.baseUrl}$path')
          .replace(queryParameters: query);

  void _assertOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message;
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message = body['message'] as String? ?? response.body;
      } catch (_) {
        message = response.body;
      }
      throw HarvestApiException(response.statusCode, message);
    }
  }

  Future<List<HarvestProject>> fetchProjectAssignments() async {
    final response = await _client.get(
      _uri('/users/me/project_assignments', {'per_page': '100'}),
      headers: await _headers(),
    );
    _assertOk(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final assignments = body['project_assignments'] as List<dynamic>;
    return assignments
        .map((a) =>
            HarvestProject.fromAssignment(a as Map<String, dynamic>))
        .toList();
  }

  Future<List<TimeEntry>> fetchTimeEntries(
      {required String from, String? to}) async {
    final query = <String, String>{'from': from, if (to != null) 'to': to};
    final response = await _client.get(
      _uri('/time_entries', query),
      headers: await _headers(),
    );
    _assertOk(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = body['time_entries'] as List<dynamic>;
    return entries
        .map((e) => TimeEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TimeEntry> createTimeEntry(CreateTimeEntryRequest request) async {
    final response = await _client.post(
      _uri('/time_entries'),
      headers: await _headers(),
      body: jsonEncode(request.toJson()),
    );
    _assertOk(response);
    return TimeEntry.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<TimeEntry> updateTimeEntry(
      int id, UpdateTimeEntryRequest request) async {
    final response = await _client.patch(
      _uri('/time_entries/$id'),
      headers: await _headers(),
      body: jsonEncode(request.toJson()),
    );
    _assertOk(response);
    return TimeEntry.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteTimeEntry(int id) async {
    final response = await _client.delete(
      _uri('/time_entries/$id'),
      headers: await _headers(),
    );
    _assertOk(response);
  }
}
