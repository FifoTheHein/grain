import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quick_template.dart';
import '../providers/assignment_provider.dart';
import '../providers/quick_template_provider.dart';
import '../theme/harvest_tokens.dart';

/// Horizontal row of one-tap template chips above the project selector.
/// Renders nothing when no templates are configured, so the form is unchanged
/// for anyone who never sets one up.
class QuickTemplateBar extends StatelessWidget {
  /// Called with the template to apply. The screen owns the notes field, so it
  /// does the applying rather than this widget.
  final void Function(QuickTemplate template) onApply;

  const QuickTemplateBar({super.key, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final templates = context.watch<QuickTemplateProvider>().enabledTemplates;
    final assignments = context.watch<AssignmentProvider>();

    if (templates.isEmpty) return const SizedBox.shrink();

    final selectedProjectId = assignments.selectedProject?.id;
    final selectedTaskId = assignments.selectedTask?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick start',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: palette.text3,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final template in templates) ...[
                _TemplateChip(
                  template: template,
                  active: template.projectId == selectedProjectId &&
                      template.taskId == selectedTaskId,
                  missing: !_isAssigned(assignments, template),
                  onTap: () => onApply(template),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static bool _isAssigned(
      AssignmentProvider assignments, QuickTemplate template) {
    final project = assignments.projects
        .firstWhereOrNull((p) => p.id == template.projectId);
    return project != null &&
        project.tasks.any((t) => t.id == template.taskId);
  }
}

class _TemplateChip extends StatelessWidget {
  final QuickTemplate template;
  final bool active;

  /// True when the template's project/task is no longer assigned to the user.
  final bool missing;
  final VoidCallback onTap;

  const _TemplateChip({
    required this.template,
    required this.active,
    required this.missing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final color = missing ? palette.text4 : template.color;

    return Tooltip(
      message: missing
          ? '${template.label} — project or task is no longer assigned to you'
          : template.notes?.isNotEmpty == true
              ? template.notes!
              : template.label,
      child: Material(
        color: active
            ? color.withValues(alpha: 0.16)
            : palette.surface2,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: missing ? null : onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: active ? color : palette.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(template.icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(
                  template.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: missing ? palette.text4 : palette.text,
                    decoration: missing ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
