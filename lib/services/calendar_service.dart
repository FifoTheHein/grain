import 'dart:convert';

import 'package:http/http.dart' as http;

class CalendarFetchException implements Exception {
  final int? statusCode;
  final String message;

  const CalendarFetchException(this.message, [this.statusCode]);

  @override
  String toString() => statusCode == null
      ? 'CalendarFetchException: $message'
      : 'CalendarFetchException($statusCode): $message';
}

/// Downloads an ICS feed. Only usable off the web: published Outlook calendars
/// send no CORS headers, so a browser refuses the response — web imports an
/// uploaded file instead.
class CalendarService {
  final http.Client _client;

  CalendarService({http.Client? client}) : _client = client ?? http.Client();

  Future<String> fetchIcs(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      throw const CalendarFetchException('The calendar URL is not valid');
    }
    // Outlook hands out webcal:// links for the same https feed.
    final target = uri.scheme == 'webcal' ? uri.replace(scheme: 'https') : uri;
    final response = await _client.get(target);
    if (response.statusCode != 200) {
      throw CalendarFetchException(
          'Calendar feed returned ${response.statusCode}', response.statusCode);
    }
    // ICS is UTF-8 by spec; don't let a missing charset fall back to Latin-1.
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}
