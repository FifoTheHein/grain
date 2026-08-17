import 'mapping_rule.dart';

class AdoWorkItem {
  final String id;
  final String title;
  final String state;
  final String? createdByName;
  final String? createdByAvatarUrl;
  final String? workItemType;
  final String? project;
  final String? areaPath;
  final String? iterationPath;
  final String? assignedToName;
  final List<String> tags;

  const AdoWorkItem({
    required this.id,
    required this.title,
    required this.state,
    this.createdByName,
    this.createdByAvatarUrl,
    this.workItemType,
    this.project,
    this.areaPath,
    this.iterationPath,
    this.assignedToName,
    this.tags = const [],
  });

  factory AdoWorkItem.fromJson(String id, Map<String, dynamic> json) {
    final fields = json['fields'] as Map<String, dynamic>;
    final createdBy = fields['System.CreatedBy'] as Map<String, dynamic>?;
    final assignedTo = fields['System.AssignedTo'] as Map<String, dynamic>?;
    return AdoWorkItem(
      id: id,
      title: fields['System.Title'] as String? ?? '(no title)',
      state: fields['System.State'] as String? ?? '',
      createdByName: createdBy?['displayName'] as String?,
      createdByAvatarUrl: createdBy?['imageUrl'] as String?,
      workItemType: fields['System.WorkItemType'] as String?,
      project: fields['System.TeamProject'] as String?,
      areaPath: fields['System.AreaPath'] as String?,
      iterationPath: fields['System.IterationPath'] as String?,
      assignedToName: assignedTo?['displayName'] as String?,
      tags: _parseTags(fields['System.Tags'] as String?),
    );
  }

  /// ADO returns tags as a single `; `-separated string.
  static List<String> _parseTags(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(';')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Field values keyed by [WorkItemField], for evaluating mapping rules.
  MatchContext get matchContext => {
        WorkItemField.id: id,
        WorkItemField.title: title,
        WorkItemField.state: state,
        WorkItemField.workItemType: workItemType,
        WorkItemField.project: project,
        WorkItemField.areaPath: areaPath,
        WorkItemField.iterationPath: iterationPath,
        WorkItemField.assignedTo: assignedToName,
        WorkItemField.tags: tags,
      };
}
