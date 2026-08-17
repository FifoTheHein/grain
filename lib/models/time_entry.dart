import 'day_insights.dart';

class AdoInstance {
  final String label;
  final String baseUrl;
  final String? pat;

  const AdoInstance({required this.label, required this.baseUrl, this.pat});

  String permalinkFor(String workItemId) =>
      '$baseUrl/_workitems/edit/$workItemId';

  /// Returns true if [permalink] belongs to this ADO instance.
  /// Tries an exact baseUrl prefix first, then falls back to matching on the
  /// organisation segment only — native Harvest entries use the project GUID
  /// in the permalink rather than the project name.
  bool matchesPermalink(String permalink) {
    if (permalink.startsWith(baseUrl)) return true;
    try {
      final uri = Uri.parse(baseUrl);
      final segs = uri.pathSegments;
      if (segs.isNotEmpty) {
        final orgPrefix = '${uri.scheme}://${uri.host}/${segs[0]}/';
        return permalink.startsWith(orgPrefix);
      }
    } catch (_) {}
    return false;
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'baseUrl': baseUrl,
        if (pat != null) 'pat': pat,
      };

  factory AdoInstance.fromJson(Map<String, dynamic> json) => AdoInstance(
        label: json['label'] as String,
        baseUrl: json['baseUrl'] as String,
        pat: json['pat'] as String?,
      );
}

class ExternalReference {
  final String id;
  final String groupId;
  final String? permalink;
  final String service;
  final String serviceIconUrl;

  const ExternalReference({
    required this.id,
    this.groupId = 'AzureDevOpsWorkItem',
    this.permalink,
    this.service = 'dev.azure.com',
    this.serviceIconUrl =
        'https://proxy.harvestfiles.com/production_harvestapp_public/uploads/platform_icons/dev.azure.com.png?1594318998',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'account_id': null,
        if (permalink != null) 'permalink': permalink,
        'service': service,
        'service_icon_url': serviceIconUrl,
      };
}

class TimeEntry {
  final int id;
  final String spentDate;
  final double hours;
  final String? notes;
  final int projectId;
  final String projectName;
  final int taskId;
  final String taskName;
  final String? userName;
  final ExternalReference? externalReference;
  final String? createdAt;
  final bool isRunning;

  /// Harvest clock times, e.g. `"8:30am"`. Only populated when the Harvest
  /// account tracks time via start and end times rather than duration.
  final String? startedTime;
  final String? endedTime;

  const TimeEntry({
    required this.id,
    required this.spentDate,
    required this.hours,
    this.notes,
    required this.projectId,
    required this.projectName,
    required this.taskId,
    required this.taskName,
    this.userName,
    this.externalReference,
    this.createdAt,
    this.isRunning = false,
    this.startedTime,
    this.endedTime,
  });

  /// True when this entry knows when it happened, not just how long it took.
  bool get hasClockTimes =>
      parseClockMinutes(startedTime) != null &&
      parseClockMinutes(endedTime) != null;

  /// The entry as a span in minutes from midnight, or null when untimed.
  /// An end at or before the start (an entry crossing midnight) is dropped
  /// rather than guessed at.
  InsightSpan? get span {
    final start = parseClockMinutes(startedTime);
    final end = parseClockMinutes(endedTime);
    if (start == null || end == null || end <= start) return null;
    return InsightSpan(start: start, end: end, key: '$projectId:$taskId');
  }

  factory TimeEntry.fromJson(Map<String, dynamic> json) {
    final ext = json['external_reference'] as Map<String, dynamic>?;
    final user = json['user'] as Map<String, dynamic>?;
    final project = json['project'] as Map<String, dynamic>;
    final task = json['task'] as Map<String, dynamic>;
    return TimeEntry(
      id: json['id'] as int,
      spentDate: json['spent_date'] as String,
      hours: (json['hours'] as num).toDouble(),
      notes: json['notes'] as String?,
      projectId: project['id'] as int,
      projectName: project['name'] as String,
      taskId: task['id'] as int,
      taskName: task['name'] as String,
      userName: user?['name'] as String?,
      externalReference: ext == null
          ? null
          : ExternalReference(
              id: ext['id'] as String,
              permalink: ext['permalink'] as String?,
            ),
      createdAt: json['created_at'] as String?,
      isRunning: json['is_running'] as bool? ?? false,
      startedTime: json['started_time'] as String?,
      endedTime: json['ended_time'] as String?,
    );
  }
}

class CreateTimeEntryRequest {
  final int userId;
  final int projectId;
  final int taskId;
  final String spentDate;
  final double hours;
  final String? notes;
  final ExternalReference? externalReference;

  /// Clock times in `HH:mm`, sent only when the Harvest account tracks time via
  /// start and end times — duration-tracking accounts ignore them.
  final String? startedTime;
  final String? endedTime;

  const CreateTimeEntryRequest({
    required this.userId,
    required this.projectId,
    required this.taskId,
    required this.spentDate,
    required this.hours,
    this.notes,
    this.externalReference,
    this.startedTime,
    this.endedTime,
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'project_id': projectId,
        'task_id': taskId,
        'spent_date': spentDate,
        'hours': hours,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (externalReference != null)
          'external_reference': externalReference!.toJson(),
        if (startedTime != null) 'started_time': startedTime,
        if (endedTime != null) 'ended_time': endedTime,
      };
}

class UpdateTimeEntryRequest {
  final int projectId;
  final int taskId;
  final String spentDate;
  final double hours;
  final String? notes;
  final ExternalReference? externalReference;

  const UpdateTimeEntryRequest({
    required this.projectId,
    required this.taskId,
    required this.spentDate,
    required this.hours,
    this.notes,
    this.externalReference,
  });

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'task_id': taskId,
        'spent_date': spentDate,
        'hours': hours,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        if (externalReference != null)
          'external_reference': externalReference!.toJson(),
      };
}
