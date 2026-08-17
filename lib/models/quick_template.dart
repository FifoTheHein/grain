import 'package:flutter/material.dart';

/// A one-click launcher for a recurring kind of work — "PR Reviews",
/// "Standup" — carrying a preset Harvest project/task and default notes.
///
/// Tapping one on Log Time fills in the form; it does not submit anything.
class QuickTemplate {
  final String id;
  final String label;
  final int projectId;
  final int taskId;

  /// Prefilled into the notes field when the template is applied.
  final String? notes;

  /// Index into [kTemplateIcons]; out-of-range values fall back to the first.
  final int iconIndex;

  /// Index into [kTemplateColors]; out-of-range values fall back to the first.
  final int colorIndex;

  /// Position in the chip row. Lower comes first.
  final int sortOrder;

  final bool enabled;

  const QuickTemplate({
    required this.id,
    required this.label,
    required this.projectId,
    required this.taskId,
    this.notes,
    this.iconIndex = 0,
    this.colorIndex = 0,
    this.sortOrder = 0,
    this.enabled = true,
  });

  IconData get icon => kTemplateIcons[iconIndex.clamp(0, kTemplateIcons.length - 1)];

  Color get color =>
      kTemplateColors[colorIndex.clamp(0, kTemplateColors.length - 1)];

  QuickTemplate copyWith({
    String? label,
    int? projectId,
    int? taskId,
    String? notes,
    int? iconIndex,
    int? colorIndex,
    int? sortOrder,
    bool? enabled,
    bool clearNotes = false,
  }) =>
      QuickTemplate(
        id: id,
        label: label ?? this.label,
        projectId: projectId ?? this.projectId,
        taskId: taskId ?? this.taskId,
        notes: clearNotes ? null : (notes ?? this.notes),
        iconIndex: iconIndex ?? this.iconIndex,
        colorIndex: colorIndex ?? this.colorIndex,
        sortOrder: sortOrder ?? this.sortOrder,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'projectId': projectId,
        'taskId': taskId,
        if (notes != null) 'notes': notes,
        'iconIndex': iconIndex,
        'colorIndex': colorIndex,
        'sortOrder': sortOrder,
        'enabled': enabled,
      };

  factory QuickTemplate.fromJson(Map<String, dynamic> json) => QuickTemplate(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Template',
        projectId: (json['projectId'] as num).toInt(),
        taskId: (json['taskId'] as num).toInt(),
        notes: json['notes'] as String?,
        iconIndex: (json['iconIndex'] as num?)?.toInt() ?? 0,
        colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// Icons offered in the template editor. These must stay `const` — the web
/// release build runs with icon tree-shaking, which rejects `IconData` built
/// from a runtime codepoint, so templates store an index into this list.
const kTemplateIcons = <IconData>[
  Icons.bolt,
  Icons.rate_review_outlined,
  Icons.groups_outlined,
  Icons.bug_report_outlined,
  Icons.code,
  Icons.design_services_outlined,
  Icons.support_agent,
  Icons.school_outlined,
  Icons.event_note_outlined,
  Icons.coffee_outlined,
  Icons.build_outlined,
  Icons.description_outlined,
];

/// Chip accent colours, matching the project category palette.
const kTemplateColors = <Color>[
  Color(0xFFFA5D24), // brand orange
  Color(0xFF7C5CFF), // violet
  Color(0xFF14B8A6), // teal
  Color(0xFF2563EB), // blue
  Color(0xFF16A34A), // green
  Color(0xFFC026D3), // purple
  Color(0xFFD97706), // amber
  Color(0xFFDC2626), // red
  Color(0xFF0891B2), // cyan
  Color(0xFF65A30D), // lime
  Color(0xFFDB2777), // pink
  Color(0xFF8A837A), // warm gray
];
