class AdoWorkItem {
  final String id;
  final String title;
  final String state;

  const AdoWorkItem({
    required this.id,
    required this.title,
    required this.state,
  });

  factory AdoWorkItem.fromJson(String id, Map<String, dynamic> json) {
    final fields = json['fields'] as Map<String, dynamic>;
    return AdoWorkItem(
      id: id,
      title: fields['System.Title'] as String? ?? '(no title)',
      state: fields['System.State'] as String? ?? '',
    );
  }
}
