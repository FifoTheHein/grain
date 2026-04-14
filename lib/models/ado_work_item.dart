class AdoWorkItem {
  final String id;
  final String title;
  final String state;
  final String? createdByName;
  final String? createdByAvatarUrl;
  final String? workItemType;

  const AdoWorkItem({
    required this.id,
    required this.title,
    required this.state,
    this.createdByName,
    this.createdByAvatarUrl,
    this.workItemType,
  });

  factory AdoWorkItem.fromJson(String id, Map<String, dynamic> json) {
    final fields = json['fields'] as Map<String, dynamic>;
    final createdBy = fields['System.CreatedBy'] as Map<String, dynamic>?;
    return AdoWorkItem(
      id: id,
      title: fields['System.Title'] as String? ?? '(no title)',
      state: fields['System.State'] as String? ?? '',
      createdByName: createdBy?['displayName'] as String?,
      createdByAvatarUrl: createdBy?['imageUrl'] as String?,
      workItemType: fields['System.WorkItemType'] as String?,
    );
  }
}
